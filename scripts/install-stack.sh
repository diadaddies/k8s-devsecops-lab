#!/usr/bin/env bash
# Installs the in-cluster security stack: Kyverno (admission) + Falco (runtime).
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export PATH="$HOME/.local/bin:$PATH"
cd "$(dirname "$0")/.."

echo ">> Kyverno (admission control)"
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install kyverno kyverno/kyverno \
  -n kyverno --create-namespace --wait --timeout 5m

echo ">> Falco (runtime detection, modern eBPF)"
helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install falco falcosecurity/falco \
  -n falco --create-namespace \
  --set driver.kind=modern_ebpf \
  --set-file customRules."vault_rules\.yaml"=falco/custom-rules.yaml \
  --wait --timeout 5m

echo ">> done. Pods:"
kubectl get pods -n kyverno
kubectl get pods -n falco
