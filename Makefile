TF_DIR := terraform
AWS_ENV := eval "$$(aws configure export-credentials --format env)"

# One z0 tile from each tileset served by martin.
TEST_URLS := \
  https://tiles.perrygeo.com/latest/0/0/0 \
  https://tiles.perrygeo.com/hillshade/0/0/0 \
  https://tiles.perrygeo.com/s2cloudless/0/0/0

.PHONY: help init plan apply destroy rebuild ssh test purge vendor-assets

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  init       terraform init"
	@echo "  plan       terraform plan"
	@echo "  apply      terraform apply (creates/reconfigures the tile server)"
	@echo "  destroy    terraform destroy"
	@echo "  rebuild    force nixos-rebuild without editing files"
	@echo "  ssh        SSH into the instance as root"
	@echo "  test       curl one tile from each tileset (checks HTTP 200)"
	@echo "  purge      invalidate the entire CloudFront cache"
	@echo "  vendor-assets  re-download protomaps fonts/sprites into assets/"

init:
	cd $(TF_DIR) && terraform init

plan:
	cd $(TF_DIR) && $(AWS_ENV) && terraform plan

apply:
	cd $(TF_DIR) && $(AWS_ENV) && terraform apply

destroy:
	cd $(TF_DIR) && $(AWS_ENV) && terraform destroy

# Re-run the nixos_rebuild provisioner against the same instance.
rebuild:
	cd $(TF_DIR) && $(AWS_ENV) && terraform apply -replace='terraform_data.nixos_rebuild'

ssh:
	cd $(TF_DIR) && $$(terraform output -raw ssh_command)

# Invalidate every cached object in the CloudFront distribution.
purge:
	@id=$$(cd $(TF_DIR) && terraform output -raw cloudfront_distribution_id); \
	echo "Creating CloudFront invalidation for distribution $$id"; \
	$(AWS_ENV) && aws cloudfront create-invalidation \
	  --distribution-id "$$id" \
	  --paths "/*" \
	  --query 'Invalidation.{Id:Id,Status:Status}' \
	  --output table

# Re-download the protomaps fonts/sprites into assets/ (see README "Fonts & sprites").
# Replaces assets/fonts/ and assets/sprites/v4/ only, so assets/sprites/LICENSE.md
# and any local overrides outside those trees are preserved.
vendor-assets:
	rm -rf /tmp/basemaps-assets && mkdir -p /tmp/basemaps-assets
	curl -sSL -o /tmp/basemaps-assets/main.tar.gz https://codeload.github.com/protomaps/basemaps-assets/tar.gz/refs/heads/main
	tar -xzf /tmp/basemaps-assets/main.tar.gz -C /tmp/basemaps-assets
	rm -rf assets/fonts assets/sprites/v4
	mkdir -p assets/sprites
	cp -a /tmp/basemaps-assets/basemaps-assets-main/fonts assets/fonts
	cp -a /tmp/basemaps-assets/basemaps-assets-main/sprites/v4 assets/sprites/v4
	rm -rf /tmp/basemaps-assets

# Curl one z0 tile from each tileset and fail on any non-200 response.
test:
	@for u in $(TEST_URLS); do \
	  code=$$(curl -sS -o /dev/null -w '%{http_code}' "$$u"); \
	  if [ "$$code" = "200" ]; then \
	    echo "OK   $$u"; \
	  else \
	    echo "FAIL $$u (HTTP $$code)" >&2; \
	    exit 1; \
	  fi; \
	done
