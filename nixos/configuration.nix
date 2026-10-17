{
  pkgs,
  lib,
  modulesPath,
  ...
}:

let
  martinConfig = pkgs.writeText "martin-config.yaml" ''
    listen_addresses: "127.0.0.1:3000"
    cache:
      size_mb: 768
    pmtiles:
      skip_signature: true
      region: us-east-1
      sources:
        latest: s3://pmtiles.perrygeo.com/latest.pmtiles
    passthrough:
      sources:
        hillshade:
          url: https://services.arcgisonline.com/arcgis/rest/services/Elevation/World_Hillshade/MapServer/tile/{z}/{y}/{x}
          format: jpg
          minzoom: 0
          maxzoom: 23
          attribution: 'Esri'
  '';
in
{
  imports = [
    (modulesPath + "/virtualisation/amazon-image.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking.hostName = "tiles";
  # EC2 networking is plain DHCP on the ENI; do not bring up NetworkManager.
  networking.useDHCP = true;

  system.stateVersion = "26.05";

  # ── Martin PMTiles tile server ──────────────────────────────────────────────
  #
  # Serves the public Protomaps basemap archive from S3 (anonymous, no AWS
  # credentials) as a ZXY MVT endpoint on 127.0.0.1:3000. nginx proxies
  # tiles.perrygeo.com to it. skip_signature=true makes unsigned S3 range
  # requests, so the box needs no AWS credential/role.
  #
  systemd.services.martin = {
    description = "Martin PMTiles tile server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.martin} --config ${martinConfig}";
      Restart = "always";
      RestartSec = "3s";
      DynamicUser = true;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };

  # ── nginx: reverse proxy for CloudFront ─────────────────────────────────────
  #
  # TLS is terminated at CloudFront; nginx only speaks HTTP to CloudFront on :80.
  #
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedOptimisation = true;

    # Default server: any Host that isn't tiles.perrygeo.com gets a 404. Keep
    # this block — without it nginx would serve tiles on every hostname.
    virtualHosts."_" = {
      default = true;
      locations."/" = {
        return = "404";
      };
    };

    virtualHosts."tiles.perrygeo.com" = {
      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
        extraConfig = ''
          proxy_hide_header Cache-Control;
          add_header Cache-Control "public, max-age=86400";

          # Public tiles: emit a static CORS origin. Martin echoes the request
          # Origin, and CloudFront caches that per-tile for 24h — the first Origin
          # to hit a tile poisons it for everyone else. "*" is safe here because
          # tiles are anonymous (no credentials/cookies).
          proxy_hide_header Access-Control-Allow-Origin;
          add_header Access-Control-Allow-Origin "*" always;
        '';
      };
    };
  };

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [
    22
    80
  ];
}
