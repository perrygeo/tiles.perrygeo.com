# Martin 2.0 (beta) package, vendored locally until nixpkgs ships it.
#
# Why a local package instead of nixpkgs' martin:
#   - 2.0 is not in nixpkgs (stable 26.05 has 1.9.1, unstable has 1.16.1)
#   - 2.0 requires rustc 1.98 (edition 2024); nixpkgs 26.05 ships rustc 1.95,
#     so this MUST be built with nixpkgs-unstable's rustPlatform.
#   - 2.0's default build drops `rendering`, and this deployment does not use
#     server-side rendering, so the maplibre-native precompiled blob (MLN_*)
#     is not needed here. Add it back only if styles.rendering is enabled.
#
# The webUI is built by nix (buildNpmPackage) and embedded by martin/build.rs
# via `static_files`. `dont-build-webui.patch` stops build.rs from running its
# own `npm install`/`npm run build` (no network/node_modules in the sandbox)
# while still embedding the dist/ that preBuild copies in.
{ lib, fetchFromGitHub, rustPlatform, buildNpmPackage, pkg-config, curl, libuv, libz, openssl, runCommand }:

let
  version = "2.0.0-beta.3";

  src = fetchFromGitHub {
    owner = "maplibre";
    repo = "martin";
    tag = "martin-v${version}";
    hash = "sha256-Uykilq3Qo+5WbVdc1svKea3t5GZu9KwtyI8kcYOweLo=";
  };

  webui = buildNpmPackage {
    pname = "martin-ui";
    inherit version;

    src = "${src}/martin/martin-ui";

    npmDepsHash = "sha256-3L1KhnMATzo0w2RwAuDH63Pm6jLzi3MALmBEOyrj7Kg=";

    postPatch = ''
      # public/_/assets/favicon.ico is a symlink to demo/frontend/public/favicon.ico
      # (outside this subtree), which dangles once nix copies only martin/martin-ui.
      # Replace it with a symlink to the real file in the full source tree.
      ln -sf ${src}/demo/frontend/public/favicon.ico public/_/assets/favicon.ico
    '';

    buildPhase = ''
      runHook preBuild
      npm exec vite build
      runHook postBuild
    '';

    installPhase = ''
      cp -r dist $out
    '';
  };

  martin = rustPlatform.buildRustPackage {
    pname = "martin";
    inherit version src;

    cargoHash = "sha256-ewSQ11zT8K5kgrpCZ7ZM/jyDERnQUEU7VJ/SAkfUOGs=";

    # Skip build.rs's own npm build; nix pre-builds the UI and preBuild copies it.
    patches = [ ./dont-build-webui.patch ];

    nativeBuildInputs = [ pkg-config ];

    buildInputs = [ curl libuv libz openssl ];

    doCheck = false;

    preBuild = ''
      rm -rf martin/martin-ui/dist
      cp -r ${webui} martin/martin-ui/dist
    '';

    meta = {
      description = "Blazing fast and lightweight tile server (PostGIS, MBTiles, PMTiles, and more)";
      homepage = "https://martin.maplibre.org/";
      license = with lib.licenses; [ mit asl20 ];
      mainProgram = "martin";
      platforms = [ "x86_64-linux" "aarch64-linux" ];
    };
  };

  # martin 2.0.0-beta.3 vendors libdeflate-sys 1.24.0, which emits
  # `__attribute__((target("evex512")))`. gcc 16 (nixpkgs-unstable's stdenv) no longer accepts
  # the evex512/no-evex512 target attributes, so libdeflate-sys fails to
  # compile. Patch the vendored crate to skip those attributes on gcc >= 16.
  # cargoPatches would patch the martin source, not the vendored deps, so patch
  # the final cargoDeps output here instead.
  patchedVendor = runCommand "martin-${version}-vendor-gcc16" { } ''
    cp -r ${martin.cargoDeps}/. "$out"
    chmod -R u+w "$out"
    patch -p1 -d "$out" < ${./libdeflate-gcc16.patch}
  '';
in
martin.overrideAttrs (_: { cargoDeps = patchedVendor; })
