{
  description = "keiki";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        haskellPackages = pkgs.haskell.packages."ghc912";
      in
      {
        packages = {
          default  = haskellPackages.keiki;
          jitsurei = haskellPackages.jitsurei;
        };

        checks = {
        };

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.zlib
            pkgs.just
            pkgs.nodejs_22
            pkgs.pnpm
            pkgs.cabal-install
            pkgs.pkg-config
            pkgs.z3
            (haskellPackages.ghcWithPackages (ps: [
              ps.haskell-language-server
            ]))
          ]
          ++ pkgs.lib.optional false pkgs.process-compose;

          shellHook = ''
            export LANG=en_US.UTF-8
          '';
        };
      }
    );
}
