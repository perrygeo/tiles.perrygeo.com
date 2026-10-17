{
  description = "tiles.perrygeo.com — Martin PMTiles tile server on a NixOS EC2 spot instance";

  inputs = {
    # Match the official NixOS AMI release (26.05) so the first nixos-rebuild
    # on a freshly-launched instance is not a multi-release jump. The terraform
    # AMI data source filters nixos/26.05*.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # martin 1.16.1 (with the `passthrough` sources used by the hillshade layer)
    # is not in 26.05 yet; take it from unstable and patch its vendored
    # libdeflate for gcc 16. See nixos/libdeflate-gcc16.patch.
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
                system = final.stdenv.hostPlatform.system;
                unstable = nixpkgs-unstable.legacyPackages.${system};
                # martin 1.16.1 vendors libdeflate 1.24.0, which emits
                # `__attribute__((target("evex512")))`. gcc 16 no longer accepts
                # the evex512/no-evex512 target attributes, so libdeflate-sys
                # fails to compile. Patch the vendored crate to skip those
                # attributes on gcc >= 16.
                patchedVendor = prev.runCommand "martin-1.16.1-vendor-gcc16" { } ''
                  cp -r ${unstable.martin.cargoDeps}/. "$out"
                  chmod -R u+w "$out"
                  patch -p1 -d "$out" < ${./nixos/libdeflate-gcc16.patch}
                '';
              in
              {
                martin = unstable.martin.overrideAttrs (_: { cargoDeps = patchedVendor; });
              }
            )
          ];
        })
        ./nixos/configuration.nix
      ];
    };
  };
}
