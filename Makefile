# Platform lifecycle for the costly stacks, plus the api image and the task-tracker release.
# bootstrap and foundation are applied once by hand and kept.
# Each stack reads its gitignored backend.hcl and terraform.tfvars (see infra/<stack>/README.md).
# Every apply and destroy asks for confirmation; nothing is auto-approved.

TF := terraform

# The region comes from the environment or the active AWS profile, never from code.
CLUSTER ?= eks-platform-dev
REGION  ?= $(or $(AWS_REGION),$(AWS_DEFAULT_REGION),$(shell aws configure get region 2>/dev/null))

# App image and release. The account ID is looked up at most once, and only by targets that use it.
AWS_ACCOUNT_ID = $(eval AWS_ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account --output text))$(AWS_ACCOUNT_ID)
REGISTRY      = $(AWS_ACCOUNT_ID).dkr.ecr.$(REGION).amazonaws.com
IMAGE_REPO   := eks-platform/api
TAG          ?= $(shell git rev-parse --short HEAD)
PLATFORM     ?= linux/amd64
RELEASE      := task-tracker
NAMESPACE    := tasks
# Context name written by `aws eks update-kubeconfig` (the cluster ARN). Passed explicitly so
# deploy and undeploy never act on whatever context happens to be current.
KUBE_CONTEXT ?= arn:aws:eks:$(REGION):$(AWS_ACCOUNT_ID):cluster/$(CLUSTER)

.DEFAULT_GOAL := help
.PHONY: help up down check-clean check-region image deploy undeploy

help: ## Show the available targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-12s %s\n", $$1, $$2}'

check-region:
	@test -n "$(REGION)" || { echo "REGION is empty: set AWS_REGION or pass REGION=<region>" >&2; exit 1; }

up: ## Create the platform: apply network, eks, then addons
	$(TF) -chdir=infra/network init -backend-config=backend.hcl
	$(TF) -chdir=infra/network apply
	$(TF) -chdir=infra/eks init -backend-config=backend.hcl
	$(TF) -chdir=infra/eks apply
	$(TF) -chdir=infra/addons init -backend-config=backend.hcl
	$(TF) -chdir=infra/addons apply

check-clean: check-region ## Fail if the app release, Ingresses, LoadBalancer Services or PVCs still exist
	@scripts/check-cluster-clean.sh $(CLUSTER) $(REGION) $(NAMESPACE)/$(RELEASE)

down: check-clean ## Tear the platform down: destroy addons, eks, then network
	$(TF) -chdir=infra/addons init -backend-config=backend.hcl
	$(TF) -chdir=infra/addons destroy
	$(TF) -chdir=infra/eks init -backend-config=backend.hcl
	$(TF) -chdir=infra/eks destroy
	$(TF) -chdir=infra/network init -backend-config=backend.hcl
	$(TF) -chdir=infra/network destroy

image: check-region ## Build the api image for linux/amd64, tag it with the short Git SHA, push it to ECR
	@test -z "$$(git status --porcelain -- apps/api)" || { echo "apps/api has uncommitted changes: commit them first, so tag $(TAG) matches the code" >&2; exit 1; }
	aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $(REGISTRY)
	docker buildx build --platform $(PLATFORM) --tag $(REGISTRY)/$(IMAGE_REPO):$(TAG) --push apps/api

deploy: check-region ## Install or upgrade the task-tracker release with image tag TAG (default: HEAD)
	@aws ecr describe-images --region $(REGION) --repository-name $(IMAGE_REPO) --image-ids imageTag=$(TAG) >/dev/null 2>&1 \
	  || { echo "Image $(IMAGE_REPO):$(TAG) is not in ECR: run make image, or pass TAG=<pushed-sha>" >&2; exit 1; }
	helm upgrade --install $(RELEASE) helm/task-tracker \
	  --kube-context $(KUBE_CONTEXT) --namespace $(NAMESPACE) --create-namespace \
	  --set image.registry=$(REGISTRY) --set image.tag=$(TAG) --set externalSecrets.region=$(REGION) \
	  --wait --timeout 10m

undeploy: check-region ## Uninstall the task-tracker release, then delete its Postgres PVC (deletes the data)
	@read -r -p "Uninstall $(RELEASE) and delete its database volume in $(CLUSTER)? [y/N] " answer && [ "$$answer" = y ]
	helm uninstall $(RELEASE) --kube-context $(KUBE_CONTEXT) --namespace $(NAMESPACE) --ignore-not-found --wait
	kubectl --context $(KUBE_CONTEXT) --namespace $(NAMESPACE) delete pvc --wait \
	  --selector app.kubernetes.io/instance=$(RELEASE),app.kubernetes.io/component=postgres
