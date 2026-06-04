# git-hooks.nix (pre-commit) as a flake-parts module. The dev shell installs the
# hooks via `config.pre-commit.installationScript` (see ./haskell.nix). The old
# flake had no custom hooks, so only the treefmt hook is wired here.
{ inputs, ... }:
{
  imports = [ inputs.pre-commit-hooks.flakeModule ];

  perSystem = { config, pkgs, ... }: {
    pre-commit.settings.hooks = {
      treefmt = {
        enable = true;
        package = config.treefmt.build.wrapper;
      };
    };
  };
}
