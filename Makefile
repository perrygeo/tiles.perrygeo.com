TF_DIR := terraform
AWS_ENV := eval "$$(aws configure export-credentials --format env)"

# One z0 tile from each tileset served by martin.
TEST_URLS := \
  https://tiles.perrygeo.com/latest/0/0/0 \
  https://tiles.perrygeo.com/hillshade/0/0/0 \
  https://tiles.perrygeo.com/s2cloudless/0/0/0

.PHONY: help init plan apply destroy rebuild ssh test purge

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
