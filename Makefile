# Platform lifecycle for the costly stacks. bootstrap is applied once by hand and kept.
# Each stack reads its gitignored backend.hcl and terraform.tfvars (see infra/<stack>/README.md).
# Every apply and destroy asks for confirmation; nothing is auto-approved.

TF := terraform

.DEFAULT_GOAL := help
.PHONY: help up down

help: ## Show the available targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-6s %s\n", $$1, $$2}'

up: ## Create the platform: apply network, then eks
	$(TF) -chdir=infra/network init -backend-config=backend.hcl
	$(TF) -chdir=infra/network apply
	$(TF) -chdir=infra/eks init -backend-config=backend.hcl
	$(TF) -chdir=infra/eks apply

down: ## Tear the platform down: destroy eks, then network
	$(TF) -chdir=infra/eks init -backend-config=backend.hcl
	$(TF) -chdir=infra/eks destroy
	$(TF) -chdir=infra/network init -backend-config=backend.hcl
	$(TF) -chdir=infra/network destroy
