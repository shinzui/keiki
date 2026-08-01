{
  description = "keiki";

  inputs = {
    # The shared base flake. Provides the GHC 9.12.4 / cabal / HLS toolchain via
    # `mkDevShell`, and the single pinned nixpkgs the whole fleet follows.
    haskell-nix-dev.url = "github:shinzui/haskell-nix-dev";
    nixpkgs.follows = "haskell-nix-dev/nixpkgs";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    treefmt-nix.follows = "haskell-nix-dev/treefmt-nix";

    pre-commit-hooks.url = "github:cachix/git-hooks.nix";
    pre-commit-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };

  # The fleet's shared binary cache, matching mori://shinzui/haskell-nix-dev.
  # These were empty, so nix fell back to cache.nixos.org alone and warned about
  # ignoring the untrusted (empty) settings on every `nix develop`.
  #
  # nixConfig is only honored for users who trust this flake — run
  # `cachix use shinzui`, or accept the prompt on first use. CI does not rely on
  # this: it configures the substituter through install-nix-action instead, which
  # writes nix.conf as a trusted user (see .github/workflows/ci.yml).
  nixConfig = {
    extra-substituters = [ "https://shinzui.cachix.org" ];
    extra-trusted-public-keys = [ "shinzui.cachix.org-1:QEmAoJrA9WwLP0uxfDgktLi2BRrcvQQWdz8NzcMg4/E=" ];
  };

  # Thin flake-parts dev shell. The dev toolchain comes from the haskell-nix-dev
  # base flake (GHC 9.12.4 / cabal / HLS via mkDevShell); project wiring lives in
  # the imported ./nix modules. This project is dev-shell-only: consumers build it
  # from source via the shared registry, so there is no package build.
  outputs = inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      imports =
        [
          ./nix/haskell.nix
          ./nix/treefmt.nix
          ./nix/pre-commit.nix
        ]
        ++ nixpkgs.lib.optional (builtins.pathExists ./flake.module.nix) ./flake.module.nix;
    };
}
