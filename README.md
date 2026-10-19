# tiles.perrygeo.com

Standalone Terraform + NixOS repo for the public Protomaps tile server.

```
Internet → CloudFront (TLS/ACM) → nginx:80 (EC2 spot + Elastic IP) → martin:3000
                                                                        │
                                                         pmtiles.perrygeo.com S3 (public)
                                                         + Esri hillshade passthrough
                                                         + EOX Sentinel-2 cloudless passthrough
```

This repo was extracted from the `dotfiles` repo (phase 2 of
`REMOVE-gateway.md`). The AWS resources predate this repo; the first `make
apply` adopts them in place rather than creating duplicates.

## Layout

```
flake.nix                  NixOS config for the EC2 instance (.#tiles)
nixos/configuration.nix    martin + nginx systemd/services
nixos/martin-config.yaml   martin tile sources/cache config
nixos/martin-2.nix         local martin 2.0 package (until nixpkgs ships it)
nixos/dont-build-webui.patch  skip build.rs's npm build (nix pre-builds the UI)
nixos/libdeflate-gcc16.patch  martin build fix for gcc 16
styles/                    MapLibre style JSON, served by martin as /style/{name}
assets/                    vendored MapLibre fonts + sprites, served by nginx as /assets/
metrics/                   local Prometheus + Grafana stack (see metrics/README.md)
terraform/                 all AWS infrastructure
```

Terraform and Nix are wired together the way the
[climate-changed](https://github.com/perrygeo/climate-changed) infra is:
`terraform_data.nixos_rebuild` runs `nixos-rebuild switch --flake .#tiles`
against the instance whenever the flake/lock/config/martin-config/patch or any
file under `styles/` or `assets/` changes. There is no separate `sync`/`deploy`
step.

## Prerequisites

- Terraform >= 1.5
- Nix with flakes enabled
- AWS credentials in your environment (`aws configure` / `AWS_PROFILE` / env vars)
- The EC2 key pair named in `terraform.tfvars`, plus its local private key

## First time: adopt the existing infrastructure

The AWS resources were originally managed from `dotfiles/terraform/gateway`.
Bring them under this repo with a one-time import, then `apply` reconciles the
drift (tags, CloudFront aliases, etc.).

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars (key_name, ssh_private_key_path, acm_certificate_arn)

terraform init

eval "$(aws configure export-credentials --format env)"

terraform import aws_vpc.tiles                         vpc-07ddbebb3a4c4d49a
terraform import aws_subnet.tiles                      subnet-088f6a642191b2c86
terraform import aws_internet_gateway.tiles            igw-0dd3c72e747430936
terraform import aws_route_table.tiles                 rtb-01ebf42d656290d43
terraform import aws_route_table_association.tiles     rtbassoc-055e0a103e043d4cd
terraform import aws_security_group.tiles              sg-055ebd537c75ecf44
terraform import aws_spot_instance_request.tiles       sir-1ze7nngj
terraform import aws_eip.tiles                         eipalloc-02e530f0cdae84d22
terraform import aws_eip_association.tiles             eipassoc-0261a4809a161a203
terraform import aws_cloudfront_cache_policy.tiles     6bed32bd-1415-41f7-916b-bb687870e936
terraform import aws_cloudfront_origin_request_policy.tiles 3a697196-26f1-472e-9b5d-04b32aed68af
terraform import aws_cloudfront_distribution.tiles     EWZE0H34S8KAX

terraform plan
terraform apply
```

After the first apply, `tiles.perrygeo.com` should serve tiles again. If the
instance was recreated (AMI refresh, key change, etc.) the `nixos_rebuild`
provisioner configures it automatically.

### Fresh start (no existing infra to adopt)

If the AWS resources do not exist yet, skip the `terraform import` step above;
`terraform apply` creates everything. You will also need to:

1. Create the ACM certificate for `tiles.perrygeo.com` in `us-east-1` and put
   its ARN in `terraform.tfvars` (or reuse the existing `*.perrygeo.com` cert).
2. Point `tiles.perrygeo.com` (Cloudflare CNAME, unproxied) at the
   `cloudfront_domain_name` output.

## Day-to-day

```bash
make plan      # preview changes
make apply     # apply infra changes; re-runs nixos-rebuild if the flake changed
make rebuild   # force nixos-rebuild without editing files
make ssh       # SSH in: make ssh SSH_KEY=~/.ssh/labs-keypair.pem EIP=<elastic_ip>
make purge     # invalidate the entire CloudFront cache
make watch-metrics  # local Prometheus + Grafana dashboard for /_/metrics
```

To change the tile server software (martin/nginx), edit `nixos/configuration.nix`
and run `make apply` — Terraform detects the file hash change and rebuilds the
instance in place. The EC2 instance is not replaced.

## Notes

- **Legacy names:** the security group (`gateway`), CloudFront cache policy
  (`gateway-origin-driven`), and origin request policy
  (`gateway-forward-to-origin`) keep their pre-extraction names so the import is
  1:1. Renaming the SG is `ForceNew` and would recreate the instance; the
  policies can be renamed in place later if it matters.
- **S3 source:** the PMTiles archive lives in the public
  `s3://pmtiles.perrygeo.com/latest.pmtiles` bucket, which is **not** managed by
  this repo. Uploading a new archive is an out-of-band step.
- **Sentinel-2 cloudless passthrough:** the `s2cloudless` source proxies the EOX
  WMTS (`…/g/{z}/{y}/{x}.jpg` — row/column order, not XYZ) up to zoom 18. The
  in-memory tile cache is Martin's own (`cache.size_mb`), replacing the
  application-level cache climate-changed used for the same endpoint.
- **CloudFront caching:** TTLs are origin-driven. nginx sets
  `Cache-Control: public, max-age=604800` on tile paths
  (`/{source}/{z}/{x}/{y}`) and on `/assets/*` (vendored fonts/sprites), and
  `Cache-Control: no-store` on everything else (WebUI HTML/JS, TileJSON,
  `/catalog`, `/style/*`, `/health`), so metadata changes appear without a
  purge. The cache key is `Host + query string` (no cookies /
  `X-Forwarded-For`). After updating an origin archive, force a refresh with
  `make purge`, which issues a CloudFront invalidation for `/*`.
- **Styles:** martin is started with `--style styles/`, so every `.json` file in
  that directory is served at `/style/{filename-stem}` (e.g.
  `styles/hillshade.json` → `/style/hillshade`). The protomaps styles point at
  `https://tiles.perrygeo.com/latest/{z}/{x}/{y}`; `hillshade.json` and
  `s2cloudless.json` are minimal raster styles over the two passthrough sources.
- **Fonts & sprites:** the styles used to load glyphs and sprites from
  `protomaps.github.io/basemaps-assets`. Those assets are now vendored under
  `assets/` (glyph PBFs in `assets/fonts/`, sprite sheets in `assets/sprites/v4/`)
  and served by nginx at `/assets/...`, so the styles no longer depend on a
  third-party origin. They are committed as-is from the
  [protomaps/basemaps-assets](https://github.com/protomaps/basemaps-assets) repo;
  to refresh them, re-download that repo and copy `fonts/` and `sprites/v4/`
  into `assets/`. Martin is *not* used for this — its `--font`/`--sprite`
  sources generate glyphs/sprites from TTF/SVG inputs rather than serving the
  pre-built PBF/PNG/JSON artifacts, and can't reproduce protomaps' merged
  fontstacks (e.g. `Noto Sans Regular` = base + ~30 script fallbacks, and the
  `Noto Sans Devanagari Regular v1` variant).
