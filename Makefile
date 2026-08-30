export KUBECONFIG := /etc/rancher/k3s/k3s.yaml
SHELL := /bin/bash

.PHONY: help cluster-info install-stack policies deploy demo-block attack falco-logs kube-bench scan-image sbom down

help: ## Show targets
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n",$$1,$$2}'

cluster-info: ## Show cluster + stack status
	kubectl get nodes
	@kubectl get pods -n kyverno 2>/dev/null | head -3 || true
	@kubectl get pods -n falco 2>/dev/null | head -3 || true

install-stack: ## Install Kyverno + Falco via Helm
	bash scripts/install-stack.sh

policies: ## Apply Kyverno policies
	kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f policies/

deploy: ## Deploy vault-api + service + networkpolicy
	kubectl apply -f k8s/deployment.yaml -f k8s/service.yaml -f k8s/networkpolicy.yaml
	kubectl -n vault rollout status deploy/vault-api

demo-block: ## Show Kyverno REJECTING the insecure pod (the money shot)
	@echo "Applying an insecure Pod — expect Kyverno to block it:"; echo
	-kubectl apply -f k8s/insecure-pod.yaml

attack: ## Run the purple-team exploit script
	bash scripts/attack.sh

falco-logs: ## Tail Falco alerts (run in a 2nd terminal during 'make attack')
	kubectl -n falco logs -l app.kubernetes.io/name=falco -c falco -f --tail=20

kube-bench: ## CIS Kubernetes Benchmark against the node
	kubectl run kube-bench --rm -i --restart=Never --image=aquasec/kube-bench:latest -- run --targets node 2>/dev/null || true

scan-image: ## Trivy scan the built image (set IMG=...)
	trivy image $(IMG)

sbom: ## Generate an SBOM for the built image (set IMG=...)
	syft $(IMG) -o cyclonedx-json

down: ## Remove the app namespace (keeps cluster + stack)
	-kubectl delete namespace vault
