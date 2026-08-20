{
  description = "Python uv project — powered by py-harbor";

  inputs = {
    py-harbor.url = "github:caniko/py-harbor";
    nixpkgs.follows = "py-harbor/nixpkgs";
    treefmt-nix.follows = "py-harbor/treefmt-nix";
    git-hooks.follows = "py-harbor/git-hooks";
  };

  outputs =
    {
      self,
      nixpkgs,
      py-harbor,
      treefmt-nix,
      git-hooks,
    }:
    let
      py = py-harbor.lib;
      forSystem =
        system:
        let
          pkgs = py.mkPkgs { inherit system; };
          treefmtEval = treefmt-nix.lib.evalModule pkgs (import ./nix/treefmt.nix);
          pre-commit-check = git-hooks.lib.${system}.run {
            src = ./.;
            hooks = import ./nix/pre-commit.nix {
              inherit pkgs;
              treefmtWrapper = treefmtEval.config.build.wrapper;
            };
          };
        in
        {
          inherit treefmtEval pre-commit-check;
          default = py.mkUvDevShell {
            inherit pkgs;
            extraPackages = pre-commit-check.enabledPackages;
            shellHookSuffix = pre-commit-check.shellHook;
          };
        };
    in
    {
      devShells = nixpkgs.lib.genAttrs py.packageSystems (system: {
        default = (forSystem system).default;
      });

      formatter = nixpkgs.lib.genAttrs py.packageSystems (
        system: (forSystem system).treefmtEval.config.build.wrapper
      );

      checks = nixpkgs.lib.genAttrs py.packageSystems (system: {
        formatting = (forSystem system).treefmtEval.config.build.check self;
      });
    };
}
