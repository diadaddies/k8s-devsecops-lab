# Project 2 — Cloud-Native Kubernetes DevSecOps Pipeline

**End-to-end plan.** A deliberately-vulnerable microservice *you write*, driven through a
full secure software supply chain, deployed to a local Kubernetes cluster gated by
policy-as-code, and watched at runtime by a threat-detection engine. Where project 1
was **shift-left + DAST**, this one adds the two things it lacked: the **software
supply chain** (SBOM, signing, attestation) and **shift-right runtime security**.

> Status: PLAN — review this, then we scaffold it (same way we built the crAPI lab).

---

## 1. Why this is the right "level 2"

Project 1 taught: CI/CD, SAST/SCA/secrets/IaC gates, DAST (nuclei/ZAP), manual testing.
It scanned a *third-party* app and never touched Kubernetes, image signing, or runtime.

Project 2 adds the modern cloud-native security stack — the topics that dominate senior
AppSec / DevSecOps interviews right now:

| New capability | Concept it teaches |
|----------------|--------------------|
| You write the vulnerable app | SAST fires on **your** code; secure coding & code review |
| SBOM + image signing + attestation | **Software supply chain security** (SLSA, Sigstore/cosign) |
| Admission control (Kyverno) | **Policy-as-code** — the pipeline *blocks* bad deploys |
| Falco runtime detection | **Shift-right** — catching attacks in a *running* container |
| K8s hardening + CIS benchmark | Pod Security, securityContext, NetworkPolicy, kube-bench |

The through-line: **defense in depth across the entire lifecycle — code → build →
artifact → admission → runtime** — with a purple-team exercise proving which layer
catches which attack.

---

## 2. The application (what you'll build)

A small **FastAPI** microservice — call it `vault-api`, a toy "secrets/notes" service —
with *intentional*, realistic flaws so every layer of the pipeline has something to catch:

| Planted flaw | Which control should catch it |
|--------------|-------------------------------|
| SQL injection (string-built query) | SAST (semgrep/bandit) + manual |
| OS command injection (`subprocess` with user input) | SAST + **Falco at runtime** |
| SSRF (fetches a user-supplied URL) | SAST + manual |
| Hardcoded secret / weak JWT | Secret scan + SAST |
| Vulnerable dependency (pinned old library w/ known CVE) | **SCA** (grype/trivy) |
| Broken object-level authorization (IDOR) | Manual testing only (logic flaw) |
| Runs as root / fat base image / no limits | Image scan + **manifest scan** + **Kyverno** |

You build it insecure on purpose, then **harden it** as the remediation phase — so you
experience both sides, exactly like project 1's attack→fix loop.

---

## 3. Architecture (end-to-end)

```
  ┌── SOURCE ──────────────┐   pre-commit + GitHub Actions (cloud)
  │  gitleaks  (secrets)   │   shift-left: never runs the app
  │  semgrep + bandit (SAST)│
  │  grype     (SCA / deps)│
  └───────────┬────────────┘
              ▼
  ┌── BUILD / SUPPLY CHAIN ────────────────┐   the new core of this project
  │  docker build (distroless, non-root)   │
  │  syft   → SBOM (CycloneDX/SPDX)         │
  │  trivy  → image CVE scan               │
  │  cosign → SIGN image (keyless, OIDC)   │
  │  cosign → ATTEST the SBOM              │
  │  push → GHCR (public package)          │
  └───────────┬────────────────────────────┘
              ▼
  ┌── MANIFESTS / IaC ─────┐   kube-linter / trivy config
  │  Deployment + hardening│   runAsNonRoot, RO rootfs, drop caps, limits, probes
  │  Service + NetworkPolicy│
  └───────────┬────────────┘
              ▼
  ┌── ADMISSION (policy-as-code) ──────────┐   k3s + Kyverno
  │  ✗ block unsigned images (verify cosign)│  ← the "aha" moment: a bad
  │  ✗ block privileged / root / no-limits  │     deploy is REJECTED at the door
  │  ✓ admit the signed, hardened workload  │
  └───────────┬────────────────────────────┘
              ▼
  ┌── RUNTIME (shift-right) ───────────────┐   Falco (eBPF) + kube-bench
  │  detect: shell in container, sensitive │  ← exploit the app live,
  │  file reads, unexpected outbound conns │     watch Falco alert in real time
  └───────────┬────────────────────────────┘
              ▼
     purple-team attack → CONTROL COVERAGE MATRIX → fix → re-run
```

**Signing flow (the supply-chain centerpiece):** GitHub Actions builds the image and
signs it **keyless** using its OIDC identity via Sigstore/cosign — no private keys to
manage. The image (and its SBOM attestation) go to GHCR as a *public* package. On the
cluster, **Kyverno's `verifyImages` policy** checks that signature against the expected
GitHub identity and **refuses to run anything unsigned or tampered**. That is a real,
current supply-chain control end to end.

---

## 4. Tools (and what each proves you know)

Carried from project 1: **GitHub Actions, Docker, gitleaks, semgrep, trivy.**
New in project 2:

| Tool | Layer | One-line "why" |
|------|-------|----------------|
| **k3s** | Platform | Lightweight production-grade Kubernetes (fits this box) |
| **kubectl / helm** | Platform | Operate the cluster; install stack via charts |
| **bandit** | SAST | Python-specific static analysis (complements semgrep) |
| **grype** | SCA | Dependency & image CVE scanning (pairs with syft) |
| **syft** | Supply chain | Generates the SBOM (bill of materials) |
| **cosign** | Supply chain | Signs images & attests SBOMs (Sigstore, keyless) |
| **Kyverno** | Admission | Policy-as-code; verifies signatures, enforces Pod Security |
| **Falco** | Runtime | eBPF threat detection inside running containers |
| **kube-bench** | Posture | CIS Kubernetes Benchmark audit |
| **kube-linter** | IaC | Static analysis of K8s manifests |

Interview phrase to internalize: *"code scanning is shift-left, admission control is the
deploy-time gate, and Falco is shift-right — three enforcement points, one policy story."*

---

## 5. Step-by-step process (the phases we'll build)

### Phase 0 — Prep the box
- `make down` the crAPI stack (free its ~1.8 GB — k3s needs the room).
- Install tooling: k3s, kubectl, helm, syft, grype, cosign, trivy, kube-bench, kube-linter.
- Stand up a single-node **k3s** cluster; confirm `kubectl get nodes`.
- Create the repo `k8s-devsecops-lab` (local + GitHub, like project 1).

### Phase 1 — Build the app + threat model
- Write the FastAPI `vault-api` with the planted flaws above.
- Write `docs/threat-model.md`: a data-flow diagram, trust boundaries, STRIDE table,
  and a mapping of each flaw to the control that should catch it. (This document alone
  is strong interview material.)

### Phase 2 — Shift-left CI (source stage)
- `pre-commit` hooks: gitleaks + bandit locally, so issues never even get pushed.
- GitHub Actions `source-scan.yml`: gitleaks, semgrep, bandit, grype (deps). Report-only
  first, then gate on HIGH/CRITICAL.

### Phase 3 — Build & supply chain (the centerpiece)
- Harden the `Dockerfile`: multi-stage, distroless or slim base, non-root user, no shell.
- `build-sign.yml` (GitHub Actions): build → `syft` SBOM → `trivy` image scan →
  `cosign sign` (keyless) → `cosign attest` the SBOM → push to GHCR (public).
- Verify locally: `cosign verify` + `cosign verify-attestation`.

### Phase 4 — Manifests + IaC hardening
- Author `k8s/` manifests: Deployment (securityContext: runAsNonRoot, readOnlyRootFilesystem,
  drop ALL caps, seccomp RuntimeDefault, resource limits, liveness/readiness probes),
  Service, and a default-deny **NetworkPolicy**.
- Scan them: `kube-linter` + `trivy config`. Fix findings.

### Phase 5 — Admission control (policy-as-code)
- Install **Kyverno** in the cluster.
- Policies: (a) `verifyImages` — only run images signed by your GitHub OIDC identity;
  (b) require non-root; (c) disallow privileged; (d) require resource limits & probes;
  (e) allowed-registries (only GHCR/your namespace).
- **The demo:** try to deploy an unsigned or privileged pod → Kyverno **blocks it**.
  Then deploy the signed, hardened app → admitted. That rejection is the money shot.

### Phase 6 — Runtime detection (shift-right)
- Install **Falco** (with the modern eBPF driver).
- Exploit the app's command-injection endpoint against the *running* pod → Falco fires
  a "shell spawned in container" / "sensitive file read" alert in real time.
- Tune a custom Falco rule for one app-specific behavior.

### Phase 7 — Cluster posture
- Run **kube-bench** (CIS benchmark) against the node; read and interpret the findings.
- Confirm the NetworkPolicy actually blocks lateral traffic (test with a scratch pod).

### Phase 8 — Purple-team attack + coverage matrix
- Attack each planted flaw against the live deployment (SQLi, cmd-injection, SSRF, IDOR).
- Fill in the **control coverage matrix**: for each attack, which layer caught it —
  SAST? SCA? admission? Falco? — and, crucially, **which attacks nothing caught**
  (the logic flaws). That gap analysis is the deliverable that impresses.

### Phase 9 — Fix & regress
- Harden the app, pin safe deps, rebuild/re-sign, redeploy.
- Watch the same gates now pass, and Kyverno/Falco stay quiet. Loop closed.

---

## 6. What you'll be able to say in an interview

> "My second lab is a cloud-native pipeline on Kubernetes. I wrote a vulnerable
> microservice and secured its whole lifecycle: shift-left scanning of my own code,
> then a signed software supply chain — SBOM generation, image signing and SBOM
> attestation with Sigstore keyless — enforced at deploy time by Kyverno admission
> policies that refuse unsigned or privileged workloads, and Falco watching the running
> containers for runtime attacks. I proved it by exploiting each flaw and mapping which
> control caught which attack, including the authorization logic flaws that only manual
> testing found."

That paragraph covers supply-chain security, policy-as-code, Pod Security, and runtime
detection — the exact vocabulary senior DevSecOps roles screen for.

---

## 7. Resource & housekeeping notes (this box)

- **crAPI must be down** while working here (`cd ~/devsecops-crapi && make down`).
- k3s is single-node; the whole stack (k3s + Kyverno + Falco + app) fits ~2–2.5 GB.
- Watch disk (19 GB free): prune unused images periodically.
- Everything is local + free; GHCR public packages avoid pull-secret friction.
- We reuse project 1's GitHub + `gh` setup and (optionally) the self-hosted runner.

---

## 8. Deliverables when scaffolded

```
k8s-devsecops-lab/
├── app/                      FastAPI vault-api (the vulnerable microservice)
│   ├── main.py               planted flaws
│   ├── requirements.txt      one pinned-vulnerable dependency
│   └── Dockerfile            hardened multi-stage, non-root, distroless
├── k8s/                      Deployment, Service, NetworkPolicy (hardened)
├── policies/                 Kyverno policies (verify-images, pod-security, registries)
├── falco/                    custom Falco rule(s)
├── .github/workflows/        source-scan.yml, build-sign.yml
├── docs/
│   ├── threat-model.md       STRIDE + data-flow + control mapping
│   └── coverage-matrix.md    which layer caught which attack
├── scripts/                  cluster-up.sh, install-tools.sh, attack.sh
├── Makefile                  cluster-up / deploy / attack / scan / down
└── README.md                 the runbook + learning loop
```

Review this plan; when you're happy, say the word and I'll start scaffolding at Phase 0.
```
