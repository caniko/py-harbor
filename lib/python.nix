{
  nixLib,
  pyproject-nix,
  uv2nix,
  pyproject-build-systems,
  opencodeLspLib ? null,
}: let
  defaultTorchCodecMissingDeps = [
    "libavcodec.so.58"
    "libavcodec.so.59"
    "libavcodec.so.60"
    "libavdevice.so.58"
    "libavdevice.so.59"
    "libavdevice.so.60"
    "libavfilter.so.7"
    "libavfilter.so.8"
    "libavfilter.so.9"
    "libavformat.so.58"
    "libavformat.so.59"
    "libavformat.so.60"
    "libavutil.so.56"
    "libavutil.so.57"
    "libavutil.so.58"
    "libswresample.so.3"
    "libswresample.so.4"
    "libswscale.so.5"
    "libswscale.so.6"
    "libswscale.so.7"
  ];
in rec {
  mkFfmpegCompat = {
    pkgs,
    requireTorchCodecAbi ? true,
  }: let
    ffmpeg =
      if pkgs ? ffmpeg_7-full
      then pkgs.ffmpeg_7-full
      else if pkgs ? ffmpeg_7
      then pkgs.ffmpeg_7
      else if pkgs ? ffmpeg_6-full
      then pkgs.ffmpeg_6-full
      else pkgs.ffmpeg_6;
  in
    assert nixLib.assertMsg (builtins.isBool requireTorchCodecAbi)
    "internal error: requireTorchCodecAbi must be a boolean"; ffmpeg;

  mkFfmpegTorchCodecAbiCheck = {
    pkgs,
    ffmpeg,
    name ? "ffmpeg-torchcodec-abi-check",
  }:
    pkgs.runCommand name {} ''
      test -e ${pkgs.lib.getLib ffmpeg}/lib/libavutil.so.59 -o -e ${pkgs.lib.getLib ffmpeg}/lib/libavutil.so.58
      mkdir -p $out
      echo ok > $out/result
    '';

  pythonOverrides = {
    addSetuptools = final: prev: package:
      prev.${package}.overrideAttrs (old: {
        nativeBuildInputs =
          (old.nativeBuildInputs or [])
          ++ [
            final.setuptools
          ];
      });

    addTorchRuntime = python: final: prev: package:
      prev.${package}.overrideAttrs (old: {
        buildInputs =
          (old.buildInputs or [])
          ++ [
            final.torch
          ];
        preFixup =
          (old.preFixup or "")
          + ''
            addAutoPatchelfSearchPath "${final.torch}/${python.sitePackages}/torch"
          '';
      });

    addTorchCodecFfmpegRuntime = {
      python,
      ffmpeg,
      ignoredMissingDeps ? defaultTorchCodecMissingDeps,
    }: final: prev:
      prev.torchcodec.overrideAttrs (old: {
        buildInputs =
          (old.buildInputs or [])
          ++ [
            final.torch
            ffmpeg
          ];
        preFixup =
          (old.preFixup or "")
          + ''
            addAutoPatchelfSearchPath "${final.torch}/${python.sitePackages}/torch"
          '';
        autoPatchelfIgnoreMissingDeps = (old.autoPatchelfIgnoreMissingDeps or []) ++ ignoredMissingDeps;
      });
  };

  mkUvHelper = {
    pkgs,
    name,
    command,
    uv ? pkgs.uv,
  }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [uv];
      text = ''
        unset UV_NO_SYNC
        uv ${command} "$@"
      '';
    };

  mkUvDevShell = {
    pkgs,
    python ? pkgs.python313,
    uvExtra,
    devGroup ? "dev",
    basePackages ? [],
    extraPackages ? [],
    baseLibs ? [],
    extraLibs ? [],
    extraEnv ? {},
    pythonPathEntries ? [],
    helperPackages ? [],
    helperSpecs ? [],
    shellHookPrefix ? "",
    shellHookSuffix ? "",
    autoSync ? true,
    opencodeLsp ? {enable = true;},
  }: let
    uvFlags = "--extra ${uvExtra} --group ${devGroup}";
    generatedHelpers = map (spec: mkUvHelper ({inherit pkgs;} // spec)) helperSpecs;
    opencodeLspEnabled = opencodeLsp.enable or true;
    opencodeLspHook =
      if opencodeLspEnabled && opencodeLspLib != null
      then
        (opencodeLspLib.mkShell {
          inherit pkgs;
          profiles = ["python"];
        }).shellHook
      else "";
    pythonPath =
      if pythonPathEntries == []
      then ""
      else ''
        export PYTHONPATH="${nixLib.concatStringsSep ":" pythonPathEntries}''${PYTHONPATH:+:$PYTHONPATH}"
      '';
    syncHook = nixLib.optionalString autoSync ''
      unset UV_NO_SYNC
      uv sync ${uvFlags}
      export UV_NO_SYNC=1
      . .venv/bin/activate
    '';
  in
    pkgs.mkShell {
      packages =
        [
          python
          pkgs.uv
        ]
        ++ basePackages
        ++ extraPackages
        ++ generatedHelpers
        ++ helperPackages;

      env =
        {
          LD_LIBRARY_PATH = nixLib.makeLibraryPath (baseLibs ++ extraLibs);
          UV_LINK_MODE = "copy";
          UV_PYTHON_DOWNLOADS = "never";
        }
        // extraEnv;

      shellHook = ''
        ${shellHookPrefix}
        ${opencodeLspHook}
        ${pythonPath}
        ${syncHook}
        ${shellHookSuffix}
      '';
    };

  mkUvDevShells = {
    pkgs,
    extras,
    defaultExtra,
    mkShellArgs,
  }: let
    mkShellForExtra = uvExtra:
      mkUvDevShell (
        (mkShellArgs uvExtra)
        // {
          inherit pkgs uvExtra;
        }
      );
    shells = nixLib.genAttrs extras mkShellForExtra;
  in
    shells
    // {
      default = shells.${defaultExtra};
    };

  mkUvPythonSet = {
    pkgs,
    python ? pkgs.python313,
    workspaceRoot,
    dependencies,
    sourcePreference ? "wheel",
    pyprojectOverrides ? final: prev: {},
    extraOverlays ? [],
  }: let
    workspace = uv2nix.lib.workspace.loadWorkspace {inherit workspaceRoot;};
    overlay = workspace.mkPyprojectOverlay {
      inherit sourcePreference dependencies;
    };
  in
    (pkgs.callPackage pyproject-nix.build.packages {
      inherit python;
    }).overrideScope
    (
      nixLib.composeManyExtensions (
        [
          pyproject-build-systems.overlays.default
          overlay
          pyprojectOverrides
        ]
        ++ extraOverlays
      )
    );

  mkUvVirtualEnv = {
    name,
    dependencies,
    ...
  } @ args: let
    pythonSet = mkUvPythonSet (builtins.removeAttrs args ["name"]);
  in
    pythonSet.mkVirtualEnv name dependencies;

  mkUvCheckEnv = mkUvVirtualEnv;

  mkUvAppPackage = {
    pkgs,
    name,
    scripts,
    dependencies,
    envName ? "${name}-env",
    runtimePathPackages ? [],
    runtimeLibraryPackages ? [],
    wrapperEnv ? {},
    ...
  } @ args: let
    venv = mkUvVirtualEnv (
      (builtins.removeAttrs args [
        "name"
        "scripts"
        "envName"
        "runtimePathPackages"
        "runtimeLibraryPackages"
        "wrapperEnv"
      ])
      // {
        name = envName;
      }
    );
    wrapEnvFlags = nixLib.concatStringsSep " " (
      nixLib.mapAttrsToList (
        key: value: "--set ${key} ${nixLib.escapeShellArg (toString value)}"
      )
      wrapperEnv
    );
    wrapScript = script: ''
      wrapProgram $out/bin/${script} \
        --prefix PATH : ${nixLib.makeBinPath runtimePathPackages} \
        --prefix LD_LIBRARY_PATH : ${nixLib.makeLibraryPath runtimeLibraryPackages}${
        nixLib.optionalString (wrapEnvFlags != "") " \\\n  ${wrapEnvFlags}"
      }
    '';
  in
    pkgs.symlinkJoin {
      inherit name;
      paths = [venv];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild = nixLib.concatStringsSep "\n" (map wrapScript scripts);
    };
}
