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
      # --style points at the repo's styles/ dir; martin discovers every .json
      # file recursively and serves each as /style/{filename-stem}.
      ExecStart = "${lib.getExe pkgs.martin} --config ${./martin-config.yaml} --style ${../styles}";
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
    recommendedOptimisation = true;

    # We manage the proxy headers ourselves instead of
    # recommendedProxySettings: nginx sits behind CloudFront, which terminates
    # TLS, so nginx's own `$scheme` is always "http". Martin builds absolute
    # URLs (WebUI and TileJSON) from the `X-Forwarded-Proto` header it receives,
    # so we must forward the viewer's real protocol (https), not nginx's.
    # CloudFront forwards the viewer protocol in the `CloudFront-Forwarded-Proto`
    # header (whitelisted in the origin request policy, see
    # terraform/cloudfront.tf). Map it into `X-Forwarded-Proto` for Martin.
    # Fall back to `$scheme` for direct (non-CloudFront) access.
    appendHttpConfig = ''
      map $http_cloudfront_forwarded_proto $forwarded_proto {
        default $scheme;
        https   https;
        http    http;
      }

      proxy_redirect          off;
      proxy_connect_timeout   60s;
      proxy_send_timeout      60s;
      proxy_read_timeout      60s;
      proxy_http_version      1.1;
      # Don't let clients close the keep-alive connection to upstream.
      proxy_set_header        "Connection" "";
      proxy_set_header        Host $host;
      proxy_set_header        X-Real-IP $remote_addr;
      proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header        X-Forwarded-Proto $forwarded_proto;
      proxy_set_header        X-Forwarded-Host $host;
      proxy_set_header        X-Forwarded-Server $hostname;
    '';

    # Default server: any Host that isn't tiles.perrygeo.com gets a 404. Keep
    # this block — without it nginx would serve tiles on every hostname.
    virtualHosts."_" = {
      default = true;
      locations."/" = {
        return = "404";
      };
    };

    virtualHosts."tiles.perrygeo.com" = {
      # Tiles are immutable: cache them for 7 days. This regex matches only the
      # canonical tile path /{sourceID}/{z}/{x}/{y}. Martin serves the
      # /{sourceID}/{z}/{x}/{y}.{ext} and /tiles/... aliases as 301 redirects,
      # so those (and all metadata/WebUI routes) fall through to the no-store
      # location below.
      locations."~ ^/[^/]+/[0-9]+/[0-9]+/[0-9]+$" = {
        priority = 500;
        proxyPass = "http://127.0.0.1:3000";
        extraConfig = ''
          proxy_hide_header Cache-Control;
          add_header Cache-Control "public, max-age=604800";

          # Public tiles: emit a static CORS origin. Martin echoes the request
          # Origin, and CloudFront caches that per-tile — the first Origin to hit
          # a tile would poison it for everyone else. "*" is safe here because
          # tiles are anonymous (no credentials/cookies).
          proxy_hide_header Access-Control-Allow-Origin;
          add_header Access-Control-Allow-Origin "*" always;
        '';
      };

      # WebUI HTML/JS, TileJSON, /catalog, /health, and tile-redirect aliases:
      # never cache, so metadata/config changes show up without a CloudFront
      # purge.
      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
        extraConfig = ''
          proxy_hide_header Cache-Control;
          add_header Cache-Control "no-store";

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
