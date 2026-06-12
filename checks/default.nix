{
  self,
  harbor,
  pkgs,
  system,
}:
let
  python = pkgs.python313;
  fixture = ../fixtures/minimal;
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

  helper = harbor.mkUvHelper {
    inherit pkgs;
    name = "py-harbor-uv-helper-check";
    command = "--version";
  };

  shell = harbor.mkUvDevShell {
    inherit pkgs python;
    uvExtra = "dev";
    basePackages = [ helper ];
    autoSync = false;
  };

  ffmpegAbiCheck = harbor.mkFfmpegTorchCodecAbiCheck {
    inherit pkgs ffmpeg;
    name = "py-harbor-ffmpeg-torchcodec-abi-check";
  };
in
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
    mkdir -p $out
    echo ok > $out/result
  '';

  uv-dev-shell = pkgs.runCommand "py-harbor-uv-dev-shell" { } ''
    test -e ${shell}
    test -x ${helper}/bin/py-harbor-uv-helper-check
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
