{
  pkgs,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/virtualisation/amazon-image.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  environment.systemPackages = with pkgs; [
    htop
    jq
    git
    gnumake
    just
    babashka
    # So `htop`/ncurses apps work over SSH from a kitty terminal
    # (local TERM=xterm-kitty is forwarded to the box).
    kitty.terminfo
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
      ExecStart = "${lib.getExe pkgs.martin} --config ${./martin-config.yaml}";
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
      # s2cloudless tiles are immutable satellite imagery: cache them for 7 days
      # instead of the 24h default applied by the catch-all location below.
      locations."/s2cloudless/" = {
        proxyPass = "http://127.0.0.1:3000";
        extraConfig = ''
          proxy_hide_header Cache-Control;
          add_header Cache-Control "public, max-age=604800";

          proxy_hide_header Access-Control-Allow-Origin;
          add_header Access-Control-Allow-Origin "*" always;
        '';
      };

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
