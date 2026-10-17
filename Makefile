TF_DIR := terraform
AWS_ENV := eval "$$(aws configure export-credentials --format env)"

.PHONY: help init plan apply destroy rebuild ssh

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  init       terraform init"
	@echo "  plan       terraform plan"
	@echo "  apply      terraform apply (creates/reconfigures the tile server)"
	@echo "  destroy    terraform destroy"
	@echo "  rebuild    force nixos-rebuild without editing files"
	@echo "  ssh        SSH into the instance as root"

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
	ssh -i $(SSH_KEY) root@$(EIP)
