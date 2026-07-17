# py-harbor

Reusable Python `uv2nix` and `pyproject-nix` infrastructure for Nix flakes.

`py-harbor` exposes a small `lib.*` API, following the same consumption style as
`rs-harbor`: downstream flakes keep project policy local while sharing the
boring Python/Nix plumbing.

## API

- `mkPkgs`, `forAllSystems`, `forPackageSystems`
- `mkPythonEnv`
- `mkUvHelper`, `mkUvDevShell`, `mkUvDevShells`
- `mkUvPythonSet`, `mkUvVirtualEnv`, `mkUvCheckEnv`, `mkUvAppPackage`
- `mkFfmpegCompat`
- `mkFfmpegTorchCodecAbiCheck`
- `pythonOverrides.addSetuptools`
- `pythonOverrides.addTorchRuntime`
- `pythonOverrides.addTorchCodecFfmpegRuntime`

## Minimal Usage

```nix
{
  inputs.py-harbor.url = "git+https://codeberg.org/caniko/py-harbor.git";

  outputs = { self, nixpkgs, py-harbor, ... }:
    let
      py = py-harbor.lib;
    in {
      devShells = py.forAllSystems (system:
        let
          pkgs = py.mkPkgs { inherit system; };
        in {
          default = py.mkUvDevShell {
            inherit pkgs;
            uvExtra = "dev";
          };
        });
    };
}
```
