# Cloud-Native Kubernetes DevSecOps Lab

Project 2 of the DevSecOps series. A deliberately-vulnerable **FastAPI** microservice
(`vault-api`) secured across its **entire lifecycle** — code → build → artifact →
admission → runtime — on a local **k3s** cluster.

Where [project 1](../devsecops-crapi) was shift-left + DAST, this adds the two layers it
lacked: the **software supply chain** (SBOM, signing, attestation) and **shift-right
runtime detection** (Falco). See `PLAN.md` for the full design and `docs/` for the
threat model and control-coverage matrix.

```
 SOURCE            BUILD / SUPPLY CHAIN         ADMISSION           RUNTIME
 gitleaks          docker build (hardened)      Kyverno:            Falco (eBPF):
 semgrep/bandit →  syft SBOM + trivy scan   →   verify signature →  detect shell /
 grype (SCA)       cosign sign + attest         enforce PodSec      sensitive reads
 (GitHub cloud)    (GitHub cloud → GHCR)        (k3s)               (k3s)
```

## Prerequisites (already set up in Phase 0)

- Tools in `~/.local/bin`: `kubectl helm cosign syft grype trivy kube-linter`
- A running k3s cluster (`kubectl get nodes` → Ready)
- crAPI (project 1) **down** to free RAM: `cd ../devsecops-crapi && make down`

## Runbook

### A. Local cluster stack (do this first)

```bash
make install-stack     # Kyverno + Falco via Helm
make policies          # create 'vault' namespace + apply Kyverno policies
make demo-block        # watch Kyverno REJECT an insecure Pod  ← the money shot
```

### B. Supply chain via GitHub (produces the signed image)

1. Push the repo and let CI sign an image (reuses project 1's `gh` login):
   ```bash
   gh repo create k8s-devsecops-lab --private --source=. --remote=origin --push
   ```
   - `source-scan` runs immediately (secrets/SAST/SCA).
   - `build-sign` builds → SBOMs → scans → **keyless-signs** → pushes to GHCR.
2. In GitHub → your repo → **Packages** → `vault-api` → make it **public** (so k3s can
   pull it and Kyverno can verify the signature without a pull secret).
3. Confirm the signature locally:
   ```bash
   cosign verify ghcr.io/<you>/vault-api:latest \
     --certificate-identity-regexp '.*build-sign.yml.*' \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com
   ```

### C. Deploy the verified workload + attack it

```bash
make deploy            # Kyverno verifies the signature, then admits the Pod
make falco-logs        # (2nd terminal) stream Falco alerts
make attack            # exploit each flaw; watch Falco fire on the cmd-injection
make kube-bench        # CIS benchmark of the node
```

Then fill in `docs/coverage-matrix.md` from what you observed.

## The learning loop

1. **Attack** each planted flaw (`make attack`).
2. **Observe** which layer caught it — CI scan? Kyverno? Falco? Only manual?
3. **Fix** the app (parameterize SQL, drop the shell, `SafeLoader`, upgrade PyYAML,
   add the authz check), rebuild → CI re-signs → redeploy.
4. **Confirm** the gates now pass and Falco stays quiet.

## Layout

```
app/            vault-api (vulnerable FastAPI) + hardened Dockerfile
k8s/            deployment (hardened), service, networkpolicy, insecure-pod (demo)
policies/       Kyverno: pod-security-restricted, require-limits, verify-images
falco/          custom runtime-detection rules
.github/workflows/  source-scan.yml, build-sign.yml
docs/           threat-model.md, coverage-matrix.md
scripts/        install-stack.sh, attack.sh
Makefile        install-stack / policies / deploy / demo-block / attack / falco-logs
```

## Resource notes (this box)

- Keep crAPI down while working here; the k3s + Kyverno + Falco + app stack fits ~2–2.5 GB.
- `make down` removes the app namespace; the cluster + stack stay up.
- To stop k3s entirely: `sudo systemctl stop k3s`.
