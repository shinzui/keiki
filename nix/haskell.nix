# Dev shell, built from the haskell-nix-dev base flake's mkDevShell (GHC 9.12.4 +
# cabal + HLS). This project is dev-shell-only (no package build / no
# flake.module.nix). Add project-specific dev tools via
# `haskellProject.extraDevPackages`, or directly in the extraNativeBuildInputs
# list below.
#
# mkDevShell already provides: the GHC compiler, cabal, HLS (when withHls),
# pkg-config, and zlib, plus a LANG=en_US.UTF-8 export. Only list tools BEYOND
# those in extraNativeBuildInputs (e.g. pkgs.just, pkgs.sqlite, pkgs.xz).
{ inputs, lib, flake-parts-lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption ({ ... }: {
    options.haskellProject.extraDevPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.ghciwatch ]";
      description = "Extra packages to add to the dev shell.";
    };
  });

  config.perSystem = { system, pkgs, config, ... }:
    let
      hsdev = inputs.haskell-nix-dev.lib.${system};

      # `interactive` distinguishes a human's shell from CI's. CI gets the same
      # toolchain and the same tool list — that parity is the point, it is what
      # keeps `z3` identical to the one specs are written against — but skips
      # HLS (a large closure no batch job invokes) and the pre-commit install
      # (which writes into .git/hooks and only makes sense for a working tree).
      mkProjectShell = { ghc, interactive ? true }: hsdev.mkDevShell {
        inherit ghc;
        withHls = interactive;
        extraNativeBuildInputs =
          [
            pkgs.just
            pkgs.nodejs_22
            pkgs.pnpm
            pkgs.z3
          ]
          ++ config.haskellProject.extraDevPackages;
        shellHook = lib.optionalString interactive ''
          ${config.pre-commit.installationScript}
        '';
      };
    in
    {
      devShells.default = mkProjectShell { ghc = "ghc9124"; };
      devShells.ghc9124 = mkProjectShell { ghc = "ghc9124"; };

      # Consumed by .github/workflows/ci.yml. See the comment above for what it
      # drops relative to the interactive shell.
      devShells.ci = mkProjectShell { ghc = "ghc9124"; interactive = false; };
    };
}
