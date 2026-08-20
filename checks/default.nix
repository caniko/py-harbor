{
  self,
  harbor,
  pkgs,
  system,
  nixpkgs,
  treefmt-nix,
  git-hooks,
  meta,
}:
let
  python = pkgs.python313;
  fixture = ../templates/default;
  templateFlake = builtins.readFile (fixture + "/flake.nix");
  templateSimit = builtins.fromTOML (builtins.readFile (fixture + "/simit.toml"));
  templateTreefmt = builtins.readFile (fixture + "/nix/treefmt.nix");
  templateHooks = builtins.readFile (fixture + "/nix/pre-commit.nix");
  ffmpeg = harbor.mkFfmpegCompat { inherit pkgs; };

  pythonSet = harbor.mkUvPythonSet {
    inherit pkgs python;
    workspaceRoot = fixture;
    dependencies = {
      minimal = [ ];
    };
    pyprojectOverrides = final: prev: {
      minimal = prev.minimal.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
          final.hatchling
        ];
      });
    };
  };

  minimalEnv = harbor.mkUvVirtualEnv {
    inherit pkgs python;
    name = "minimal-env";
    workspaceRoot = fixture;
    dependencies = {
      minimal = [ ];
    };
    pyprojectOverrides = final: prev: {
      minimal = prev.minimal.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
          final.hatchling
        ];
      });
    };
  };

  genericPackage = harbor.mkUvPackage {
    inherit pkgs python;
    name = "minimal-package";
    workspaceRoot = fixture;
    dependencies = {
      minimal = [ ];
    };
    pyprojectOverrides = final: prev: {
      minimal = prev.minimal.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
          final.hatchling
        ];
      });
    };
  };

  helper = harbor.mkUvHelper {
    inherit pkgs;
    name = "py-harbor-uv-helper-check";
    command = "--version";
  };

  validationPython = harbor.mkPythonEnv {
    inherit pkgs;
    packages = ps: [ ps.pyyaml ];
  };

  validationPackage = harbor.mkPythonApplicationPackage {
    inherit pkgs;
    name = "py-harbor-python-app";
    environment = validationPython;
    scripts = [ "python3" ];
  };

  shell = harbor.mkUvDevShell {
    inherit pkgs python;
    uvExtra = "dev";
    basePackages = [ helper ];
    autoSync = false;
  };

  shellWithoutSelections = harbor.mkUvDevShell {
    inherit pkgs python;
    uvExtra = null;
    devGroup = null;
    autoSync = false;
    opencodeLsp = {
      enable = false;
    };
  };

  ffmpegAbiCheck = harbor.mkFfmpegTorchCodecAbiCheck {
    inherit pkgs ffmpeg;
    name = "py-harbor-ffmpeg-torchcodec-abi-check";
  };
in
assert
  templateSimit.flake == {
    scope = "full";
    mode = "custom";
    backend = "py-harbor";
    components = [
      "treefmt"
      "nix-flake-check"
    ];
  };
assert pkgs.lib.hasInfix "treefmt-nix.follows" templateFlake;
assert pkgs.lib.hasInfix "git-hooks.follows" templateFlake;
assert pkgs.lib.hasInfix "treefmtEval.config.build.check self" templateFlake;
assert pkgs.lib.hasInfix "pre-commit-check.shellHook" templateFlake;
assert pkgs.lib.hasInfix "programs.alejandra.enable = true" templateTreefmt;
assert pkgs.lib.hasInfix "programs.taplo.enable = true" templateTreefmt;
assert pkgs.lib.hasInfix "treefmt =" templateHooks;
assert pkgs.lib.hasInfix "nix-flake-check" templateHooks;
{
  exports-lib = pkgs.runCommand "py-harbor-exports-lib" { } ''
    test "${toString (builtins.elem "x86_64-linux" self.lib.packageSystems)}" = "1"
    mkdir -p $out
    echo ok > $out/result
  '';

  uv-python-set = pkgs.runCommand "py-harbor-uv-python-set" { } ''
    test -e ${pythonSet.minimal}
    test -x ${minimalEnv}/bin/python
    ${minimalEnv}/bin/python -c 'import minimal; print(minimal.VALUE)'
    test -x ${minimalEnv.passthru.pythonInterpreter}
    test -d ${minimalEnv.passthru.pythonSitePackages}
    test -x ${genericPackage}/bin/python
    ${genericPackage}/bin/python -c 'import minimal; print(minimal.VALUE)'
    mkdir -p $out
    echo ok > $out/result
  '';

  uv-dev-shell = pkgs.runCommand "py-harbor-uv-dev-shell" { } ''
    test -e ${shell}
    test -x ${helper}/bin/py-harbor-uv-helper-check
    test -e ${shellWithoutSelections}
    test "${builtins.toJSON (pkgs.lib.hasInfix "--extra" shellWithoutSelections.passthru.devShellSpec.shellHook)}" = "false"
    test "${builtins.toJSON (pkgs.lib.hasInfix "--group" shellWithoutSelections.passthru.devShellSpec.shellHook)}" = "false"
    mkdir -p $out
    echo ok > $out/result
  '';

  template-default = meta.templateTests.mkCheck {
    inherit pkgs system;
    flakeNix = ../templates/default/flake.nix;
    inputs = {
      inherit nixpkgs treefmt-nix git-hooks;
      py-harbor = self;
    };
    requiredFiles = [
      "flake.nix"
      "pyproject.toml"
      "uv.lock"
      "src/minimal/__init__.py"
      "simit.toml"
      "nix/treefmt.nix"
      "nix/pre-commit.nix"
    ];
    requiredInputs = [
      "py-harbor"
      "treefmt-nix"
      "git-hooks"
    ];
    commands = [
      "uv"
      "python"
    ];
    env.UV_PYTHON_DOWNLOADS = "never";
    hookContains = [ "uv sync" ];
    inherit (meta) devShellTests;
  };

  python-env = pkgs.runCommand "py-harbor-python-env" { } ''
    test -x ${validationPython}/bin/python3
    ${validationPython}/bin/python3 -c 'import yaml; print(yaml.__version__)'
    test -x ${validationPackage}/bin/python3
    test -x ${validationPackage.passthru.pythonInterpreter}
    ${validationPackage.passthru.pythonInterpreter} -c 'import yaml'
    mkdir -p $out
    echo ok > $out/result
  '';

  ml-helpers = pkgs.runCommand "py-harbor-ml-helpers" { } ''
    test -x ${ffmpeg}/bin/ffmpeg
    test -e ${ffmpegAbiCheck}/result
    mkdir -p $out
    echo ok > $out/result
  '';
}
