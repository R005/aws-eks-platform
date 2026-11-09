# Platform lifecycle for the costly stacks. bootstrap is applied once by hand and kept.
# Each stack reads its gitignored backend.hcl and terraform.tfvars (see infra/<stack>/README.md).
# Every apply and destroy asks for confirmation; nothing is auto-approved.

TF := terraform

# Used by check-clean. The region comes from the environment or the active AWS profile, never from code.
CLUSTER ?= eks-platform-dev
REGION  ?= $(or $(AWS_REGION),$(AWS_DEFAULT_REGION),$(shell aws configure get region 2>/dev/null))

.DEFAULT_GOAL := help
.PHONY: help up down check-clean

help: ## Show the available targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-12s %s\n", $$1, $$2}'

up: ## Create the platform: apply network, eks, then addons
	$(TF) -chdir=infra/network init -backend-config=backend.hcl
	$(TF) -chdir=infra/network apply
	$(TF) -chdir=infra/eks init -backend-config=backend.hcl
	$(TF) -chdir=infra/eks apply
	$(TF) -chdir=infra/addons init -backend-config=backend.hcl
	$(TF) -chdir=infra/addons apply

check-clean: ## Fail if Ingresses, LoadBalancer Services or PVCs still exist in the cluster
	@test -n "$(REGION)" || { echo "REGION is empty: set AWS_REGION or pass REGION=<region>" >&2; exit 1; }
	@scripts/check-cluster-clean.sh $(CLUSTER) $(REGION)

down: check-clean ## Tear the platform down: destroy addons, eks, then network
	$(TF) -chdir=infra/addons init -backend-config=backend.hcl
	$(TF) -chdir=infra/addons destroy
	$(TF) -chdir=infra/eks init -backend-config=backend.hcl
	$(TF) -chdir=infra/eks destroy
	$(TF) -chdir=infra/network init -backend-config=backend.hcl
	$(TF) -chdir=infra/network destroy
