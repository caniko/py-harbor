{
  nixpkgs,
  pyproject-nix,
  uv2nix,
  pyproject-build-systems,
}:
let
  nixLib = nixpkgs.lib;
  pythonLib = import ./python.nix {
    inherit
      nixLib
      pyproject-nix
      uv2nix
      pyproject-build-systems
      ;
  };
in
pythonLib
// rec {
  allSystems = nixLib.systems.flakeExposed;
  packageSystems = [
    "x86_64-linux"
    "aarch64-darwin"
  ];

  forAllSystems = f: nixLib.genAttrs allSystems f;
  forPackageSystems = f: nixLib.genAttrs packageSystems f;

  mkPkgs =
    {
      system,
      overlays ? [ ],
      config ? { },
    }:
    import nixpkgs {
      inherit system overlays;
      config = {
        allowUnfree = true;
      }
      // config;
    };
}
