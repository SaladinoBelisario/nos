# Nebulnetes version. Used by release workflow, do not move this line.
N8S_VERSION ?= 0.0.1-alpha.2

# Image URLs to build/push Docker image targets
OPERATOR_IMG ?= ghcr.io/telemaco019/nebulnetes-operator:$(N8S_VERSION)
SCHEDULER_IMG ?= ghcr.io/telemaco019/nebulnetes-scheduler:$(N8S_VERSION)
GPU_PARTITIONER_IMG ?= ghcr.io/telemaco019/nebulnetes-gpu-partitioner:$(N8S_VERSION)
MIG_AGENT_IMG ?= ghcr.io/telemaco019/nebulnetes-mig-agent:$(N8S_VERSION)
TS_AGENT_IMG ?= ghcr.io/telemaco019/nebulnetes-time-slicing-agent:$(N8S_VERSION)

# Helm chart URL to push Helm charts
HELM_CHART_REGISTRY ?= oci://ghcr.io/telemaco019/helm-charts

CERT_MANAGER_VERSION ?= v1.9.1
# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.24.2

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: operator-manifests ## Generate manifests for the n8s operator (CRD, ClusterRole, WebhookConfig, etc.).
operator-manifests: controller-gen ## Generate CustomResourceDefinition objects.
	$(CONTROLLER_GEN) crd paths="./internal/controllers/elasticquota/;./pkg/api/..." \
	webhook \
	rbac:roleName=operator-role \
	output:rbac:artifacts:config=config/operator/rbac \
	output:crd:artifacts:config=config/operator/crd/bases \
	output:webhook:artifacts:config=config/operator/webhook

.PHONY: gpu-partitioner-manifests ## Generate manifests for the gpu-partitioner (ClusterRole, etc.).
gpu-partitioner-manifests: controller-gen
	$(CONTROLLER_GEN) paths="./internal/controllers/gpupartitioner" \
	rbac:roleName=gpu-partitioner-role \
	output:rbac:artifacts:config=config/gpupartitioner/rbac

.PHONY: mig-agent-manifests ## Generate manifests for the mig-agent (ClusterRole, etc.).
mig-agent-manifests: controller-gen
	$(CONTROLLER_GEN) paths="./internal/controllers/migagent/..." \
	rbac:roleName=mig-agent-role \
	output:rbac:artifacts:config=config/migagent/rbac

.PHONY: ts-agent-manifests	## Generate manifests for the time-slicing-agent (ClusterRole, etc.).
ts-agent-manifests: controller-gen
	$(CONTROLLER_GEN) paths="./internal/controllers/tsagent/..." \
	rbac:roleName=time-slicing-agent-role \
	output:rbac:artifacts:config=config/tsagent/rbac

.PHONY: manifests
manifests: operator-manifests \
	mig-agent-manifests \
	gpu-partitioner-manifests \
	ts-agent-manifests

.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate/license.txt" paths="./..."

.PHONY: generate-scheduler
generate-scheduler: defaulter-gen conversion-gen ## Generate defaults and conversions for scheduler.
	CONVERSION_GEN=$(CONVERSION_GEN) DEFAULTER_GEN=$(DEFAULTER_GEN) bash hack/generate-scheduler.sh

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: manifests generate fmt vet envtest ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) -p path)" go test -tags integration ./... -coverprofile cover.out -covermode=count

.PHONY: lint
lint: vet golangci-lint ## Run Go linter.
	$(GOLANGCI_LINT) run ./... -v

.PHONY: license-check
license-check: license-eye ## Check all files have the license header
	$(LICENSE_EYE) header check

.PHONY: license-fix
license-fix: license-eye ## Add license header to files that still don't have it
	$(LICENSE_EYE) header fix

.PHONY: helm-doc
helm-doc: ## Generate Helm charts documentation
	$(HELM_DOCS) --chart-search-root ./helm-charts --document-dependency-values

##@ Build

.PHONY: cluster
cluster: kind ## Create a KIND cluster for development
	kind create cluster --config hack/kind/cluster.yaml

.PHONY: build
build: generate fmt vet ## Build manager binary.
	go build -o bin/manager main.go

.PHONY: docker-build-gpu-partitioner
docker-build-gpu-partitioner: ## Build docker image with the gpu-partitioner.
	docker build -t ${GPU_PARTITIONER_IMG} -f build/gpupartitioner/Dockerfile .

.PHONY: docker-build-mig-agent
docker-build-mig-agent: ## Build docker image with the mig-agent.
	docker build -t ${MIG_AGENT_IMG} -f build/migagent/Dockerfile .

.PHONY: docker-build-ts-agent
docker-build-ts-agent: ## Build docker image with the time-slicing-agent.
	docker build -t ${TS_AGENT_IMG} -f build/tsagent/Dockerfile .

.PHONY: docker-build-operator
docker-build-operator: ## Build docker image with the operator.
	docker build -t ${OPERATOR_IMG} -f build/operator/Dockerfile .

.PHONY: docker-build-scheduler
docker-build-scheduler: ## Build docker image with the scheduler.
	docker build -t ${SCHEDULER_IMG} -f build/scheduler/Dockerfile .

.PHONY: docker-push-operator
docker-push-operator: ## Push docker image with the operator.
	docker push ${OPERATOR_IMG}

.PHONY: docker-push-mig-agent
docker-push-mig-agent: ## Push docker image with the mig-agent.
	docker push ${MIG_AGENT_IMG}

.PHONY: docker-push-ts-agent
docker-push-ts-agent: ## Push docker image with the time-slicing-agent.
	docker push ${TS_AGENT_IMG}

.PHONY: docker-push-scheduler
docker-push-scheduler: ## Push docker image with the scheduler.
	docker push ${SCHEDULER_IMG}

.PHONY: docker-push-gpu-partitioner
docker-push-gpu-partitioner: ## Push docker image with the gpu-partitioner.
	docker push ${GPU_PARTITIONER_IMG}

.PHONY: docker-build
docker-build: test \
	docker-build-mig-agent \
	docker-build-ts-agent \
	docker-build-operator \
	docker-build-scheduler \
	docker-build-gpu-partitioner \

.PHONY: docker-push
docker-push: docker-push-mig-agent \
	docker-build-ts-agent \
	docker-push-operator \
	docker-push-scheduler \
	docker-push-gpu-partitioner

.PHONY: helm-push-gpu-partitioner
helm-push-gpu-partitioner: ## Push the gpu-partitioner Helm chart to the Helm repository.
	helm package helm-charts/gpu-partitioner --destination /tmp
	helm push /tmp/gpu-partitioner-$(N8S_VERSION).tgz $(HELM_CHART_REGISTRY)
	rm /tmp/gpu-partitioner-$(N8S_VERSION).tgz

.PHONY: helm-push-n8s-scheduler
helm-push-n8s-scheduler: ## Push the n8s-scheduler Helm chart to the Helm repository.
	helm package helm-charts/n8s-scheduler --destination /tmp
	helm push /tmp/n8s-scheduler-$(N8S_VERSION).tgz $(HELM_CHART_REGISTRY)
	rm /tmp/n8s-scheduler-$(N8S_VERSION).tgz

.PHONY: helm-push-n8s-operator
helm-push-n8s-operator: ## Push the n8s-operator Helm chart to the Helm repository.
	helm package helm-charts/n8s-operator --destination /tmp
	helm push /tmp/n8s-operator-$(N8S_VERSION).tgz $(HELM_CHART_REGISTRY)
	rm /tmp/n8s-operator-$(N8S_VERSION).tgz

.PHONY: helm-push-nebulnetes
helm-push-nebulnetes: ## Push the n8s-operator Helm chart to the Helm repository.
	helm package helm-charts/nebulnetes --destination /tmp
	helm push /tmp/nebulnetes-$(N8S_VERSION).tgz $(HELM_CHART_REGISTRY)
	rm /tmp/nebulnetes-$(N8S_VERSION).tgz

.PHONY: helm-push
helm-push: helm-push-gpu-partitioner helm-push-n8s-scheduler helm-push-n8s-operator helm-push-nebulnetes ## Push the all the Helm charts to the Helm repository.

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = true
endif

.PHONY: install-cert-manager
install-cert-manager: ## Deploy cert-manager on the K8s cluster specified in ~/.kube/config
	kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/$(CERT_MANAGER_VERSION)/cert-manager.yaml

.PHONY: deploy-operator
deploy-operator: operator-manifests kustomize ## Deploy the Nebulnetes Operator to the K8s cluster specified in ~/.kube/config.
	cd config/operator/manager && $(KUSTOMIZE) edit set image controller=${OPERATOR_IMG}
	$(KUSTOMIZE) build config/operator/default | kubectl apply -f -

.PHONY: deploy-scheduler
deploy-scheduler: kustomize ## Deploy the Nebulnetes scheduler to the K8s cluster specified in ~/.kube/config.
	cd config/scheduler/deployment && $(KUSTOMIZE) edit set image scheduler=${SCHEDULER_IMG}
	$(KUSTOMIZE) build config/scheduler/default | kubectl apply -f -

.PHONY: deploy-mig-agent
deploy-mig-agent: kustomize ## Deploy the MIG Agent to the K8s cluster specified in ~/.kube/config.
	cd config/migagent/manager && $(KUSTOMIZE) edit set image mig-agent=${MIG_AGENT_IMG}
	$(KUSTOMIZE) build config/migagent/default | kubectl apply -f -

.PHONY: deploy-ts-agent
deploy-ts-agent: kustomize ## Deploy the Time Slicing Agent to the K8s cluster specified in ~/.kube/config.
	cd config/tsagent/manager && $(KUSTOMIZE) edit set image time-slicing-agent=${TS_AGENT_IMG}
	$(KUSTOMIZE) build config/tsagent/default | kubectl apply -f -

.PHONY: deploy-gpu-partitioner
deploy-gpu-partitioner: kustomize deploy-mig-agent deploy-ts-agent ## Deploy the GPU Partitioner to the K8s cluster specified in ~/.kube/config.
	cd config/gpupartitioner/manager && $(KUSTOMIZE) edit set image gpu-partitioner=${GPU_PARTITIONER_IMG}
	$(KUSTOMIZE) build config/gpupartitioner/default | kubectl apply -f -

.PHONY: undeploy-operator
undeploy-operator: ## Undeploy the Nebulnetes operator from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/operator/default | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: undeploy-scheduler
undeploy-scheduler: ## Undeploy the Nebulnetes scheduler from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/scheduler/default | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: undeploy-mig-agent
undeploy-mig-agent: ## Undeploy the MIG agent from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/migagent/default | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: undeploy-gpu-partitioner
undeploy-gpu-partitioner: ## Undeploy the GPU Partitioner from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/gpupartitioner/default | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

##@ Build Dependencies

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

## Tool Binaries
KUSTOMIZE ?= $(LOCALBIN)/kustomize
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
DEFAULTER_GEN ?= $(LOCALBIN)/defaulter-gen
CONVERSION_GEN ?= $(LOCALBIN)/conversion-gen
CODE_GEN ?= $(LOCALBIN)/code-generator
ENVTEST ?= $(LOCALBIN)/setup-envtest
KIND ?= $(LOCALBIN)/kind
GOLANGCI_LINT ?= $(LOCALBIN)/golangci-lint
LICENSE_EYE ?= $(LOCALBIN)/license-eye
HELM_DOCS ?= $(LOCALBIN)/helm-docs

## Tool Versions
KUSTOMIZE_VERSION ?= v4.5.5
CONTROLLER_TOOLS_VERSION ?= v0.9.2
CODE_GENERATOR_VERSION ?= v0.24.3
GOLANGCI_LINT_VERSION ?= 1.50.1
HELM_DOCS_VERSION ?= v1.11.0

KUSTOMIZE_INSTALL_SCRIPT ?= "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"
.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary.
$(KUSTOMIZE): $(LOCALBIN)
	test -s $(LOCALBIN)/kustomize || { curl -s $(KUSTOMIZE_INSTALL_SCRIPT) | bash -s -- $(subst v,,$(KUSTOMIZE_VERSION)) $(LOCALBIN); }

.PHONY: controller-gen
controller-gen: $(CONTROLLER_GEN) ## Download controller-gen locally if necessary.
$(CONTROLLER_GEN): $(LOCALBIN)
	test -s $(LOCALBIN)/controller-gen || GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_TOOLS_VERSION)

.PHONY: defaulter-gen
defaulter-gen: $(DEFAULTER_GEN) ## Download defaulter-gen locally if necessary
$(DEFAULTER_GEN): $(LOCALBIN)
	test -s $(LOCALBIN)/defaulter-gen || GOBIN=$(LOCALBIN) go install k8s.io/code-generator/cmd/defaulter-gen@$(CODE_GENERATOR_VERSION)

.PHONY: conversion-gen
conversion-gen: $(CONVERSION_GEN) ## Download defaulter-gen locally if necessary
$(CONVERSION_GEN): $(LOCALBIN)
	test -s $(LOCALBIN)/conversion-gen || GOBIN=$(LOCALBIN) go install k8s.io/code-generator/cmd/conversion-gen@$(CODE_GENERATOR_VERSION)

.PHONY: envtest
envtest: $(ENVTEST) ## Download envtest-setup locally if necessary.
$(ENVTEST): $(LOCALBIN)
	test -s $(LOCALBIN)/setup-envtest || GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest

.PHONY: kind ## Download Kind if necessary
kind: $(KIND)
$(KIND): $(LOCALBIN)
	test -s $(LOCALBIN)/kind || GOBIN=$(LOCALBIN) go install sigs.k8s.io/kind@latest

.PHONY: golangci-lint ## Download golanci-lint if necessary
golangci-lint: $(GOLANGCI_LINT)
$(GOLANGCI_LINT): $(LOCALBIN)
	test -s $(LOCALBIN)/golanci-lint || GOBIN=$(LOCALBIN) go install github.com/golangci/golangci-lint/cmd/golangci-lint@v${GOLANGCI_LINT_VERSION}

.PHONY: license-eye ## Download license-eye if necessary
license-eye: $(LICENSE_EYE)
$(LICENSE_EYE): $(LOCALBIN)
	test -s $(LOCALBIN)/license-eye || GOBIN=$(LOCALBIN) go install github.com/apache/skywalking-eyes/cmd/license-eye@latest

.PHONY: helm-docs-bin ## Download helm-docs if necessary
helm-docs-bin: $(HELM_DOCS)
$(HELM_DOCS): $(LOCALBIN)
	test -s $(LOCALBIN)/helm-docs || GOBIN=$(LOCALBIN) go install github.com/norwoodj/helm-docs/cmd/helm-docs@$(HELM_DOCS_VERSION)
