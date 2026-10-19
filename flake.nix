{
  description = "tiles.perrygeo.com — Martin PMTiles tile server on a NixOS EC2 spot instance";

  inputs = {
    # Match the official NixOS AMI release (26.05) so the first nixos-rebuild
    # on a freshly-launched instance is not a multi-release jump. The terraform
    # AMI data source filters nixos/26.05*.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # martin 2.0 (beta, see nixos/martin-2.nix) requires rustc 1.98; nixpkgs
    # 26.05 ships rustc 1.95, so the package is built with unstable's
    # rustPlatform. See nixos/martin-2.nix.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable }: {
    nixosConfigurations.tiles = nixpkgs.lib.nixosSystem {
      modules = [
        { nixpkgs.hostPlatform = "x86_64-linux"; }
        ({ ... }: {
          nixpkgs.overlays = [
            (final: prev:
              let
                system = prev.stdenv.hostPlatform.system;
                unstable = nixpkgs-unstable.legacyPackages.${system};
              in
              {
                # Local martin 2.0 build; see nixos/martin-2.nix. Built with
                # unstable's rustPlatform (rustc 1.98) and stdenv.
                martin = (import ./nixos/martin-2.nix) {
                  inherit (unstable)
                    lib
                    fetchFromGitHub
                    rustPlatform
                    buildNpmPackage
                    pkg-config
                    curl
                    libuv
                    libz
                    openssl
                    runCommand;
                };
              }
            )
          ];
        })
        ./nixos/configuration.nix
      ];
    };
  };
}
