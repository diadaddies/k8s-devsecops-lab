# Control Coverage Matrix

The payoff of the whole project: for each planted flaw, **which layer caught it** —
and, more tellingly, **which attacks nothing automated stopped**. The table is the
design intent; the **Observed run** section below records what actually happened when
the pipeline was exercised end to end on 2026-08-30 (k3s + Kyverno + Falco, signed
image from GHCR).

| # | Flaw | Shift-left (SAST/SCA/secret) | Supply chain (scan/sign) | Admission (Kyverno) | Runtime (Falco) | Manual | Expected owner |
|---|------|:---:|:---:|:---:|:---:|:---:|----------------|
| 1 | SQL injection (`/notes/search`) | ✅ SAST | — | — | — | ✅ | **SAST** finds it in code |
| 2 | Cmd injection (`/ping`) | ✅ SAST | — | — | ✅ **Falco** | ✅ | SAST + **runtime** |
| 3 | SSRF (`/fetch`) | ✅ SAST | — | ⚠️ NetworkPolicy limits blast | — | ✅ | SAST + egress policy |
| 4 | Unsafe YAML (`/config`) | ✅ SAST | ✅ SCA (PyYAML CVE) | — | ⚠️ Falco on payload exec | ✅ | SAST + **SCA** |
| 5 | BOLA / IDOR (`/notes/{id}`) | ❌ | ❌ | ❌ | ❌ | ✅ **only manual** | **Manual only** — logic flaw |
| 6 | Hardcoded secret | ✅ Secret scan / SAST | — | — | — | — | Secret scanning |
| 7 | Vulnerable dependency | ✅ SCA (grype) | ✅ image scan (trivy) | — | — | — | **SCA** |
| 8 | Unsigned / tampered image | — | ✅ cosign verify | ✅ **Kyverno blocks** | — | — | **Admission** |
| 9 | Privileged / root Pod | — | — | ✅ **Kyverno blocks** | — | — | **Admission** |
| 10 | No resource limits | — | — | ✅ **Kyverno blocks** | — | — | **Admission** |

## The two lessons this table teaches

1. **Defense in depth is real.** No single layer catches everything. Flaw #2 is caught
   in code *and* at runtime; #4 by both SAST and SCA. Layers overlap on purpose.

2. **Automation has a hard floor.** Flaw #5 (BOLA/IDOR) is invisible to every automated
   control — SAST, DAST, admission, runtime all miss it, because no tool *understands*
   that user A shouldn't read user B's note. **Authorization logic flaws are why manual
   testing and threat modeling still matter.** This is the single most important point
   to make in an interview: you know where tooling stops.

## How to demo each row

- Rows 1–5, 7: `make attack` (with `make falco-logs` running) + the CI scan logs.
- Row 8: try to deploy an image that isn't signed by your workflow → Kyverno rejects.
- Rows 9–10: `make demo-block` → Kyverno rejects the insecure Pod.

---

## Observed run — 2026-08-30

Actual evidence captured while running the full pipeline. This is the "it really works"
record — quote these in an interview.

**Shift-left (CI, cloud runners)**
- SCA: `grype` → `pyyaml 5.3.1  GHSA-8q59-q68h-6hv4  Critical (fixed in 5.4)` — flaw #7 caught.
- IaC: `kube-linter` → hardened manifests clean bar a `:latest` best-practice flag;
  the insecure Pod → **7 lint errors**.

**Supply chain**
- `build-sign` workflow: build → SBOM → trivy → **cosign keyless sign + attest** → GHCR, all green.
- `cosign verify` → *"transparency log claims verified"* + *"code-signing certificate verified"*,
  Subject `…/build-sign.yml@refs/heads/master`, Issuer `token.actions.githubusercontent.com`.

**Admission (Kyverno)**
- Signature (flaw #8): at `make deploy`, Kyverno verified the signature and **mutated the
  image to its digest** — pod ran `ghcr.io/diadaddies/vault-api:latest@sha256:39d169cc…`.
- Pod Security + limits (flaws #9–10): `make demo-block` → **request denied**:
  *privileged, runAsUser=0, runAsNonRoot missing, allowPrivilegeEscalation, capabilities
  not dropped, seccompProfile missing, CPU/memory limits required.*

**Runtime (Falco) + manual (flaws #1–5)** — `make attack`:
- CMD injection (#2): `/ping?host=127.0.0.1;id` → app returned `uid=10001(appuser)…`, and
  **Falco fired**: `Unexpected process in vault-api container (proc=id parent=sh)` plus
  `Sensitive file opened … file=/etc/passwd proc=id`. Caught in code (SAST) AND at runtime.
- IDOR (#5): `/notes/2` → `bob SECRET token abc123` leaked. **No automated layer caught it.**
- SSRF (#3): `/fetch` performed the server-side request (NetworkPolicy limits its reach).
- Unsafe YAML (#4): `/config` → `yaml.load` executed `os.getcwd()` → `"/app"` (RCE proven).
- SQLi (#1): injected clause visible in the echoed query.

## Falco false positive — a tuning note

The same run also logged, at container **startup**:

```
Sensitive file opened in vault-api (file=/etc/passwd proc=runc:[1:CHILD] init …)
```

This is **benign**: the container runtime (`runc`) reads `/etc/passwd` during init to set
up the user — not an attack. It's a textbook **false positive**, and handling it is the
skill that separates running a tool from operating it:

- **Tune the rule** to exclude the init context, e.g. add
  `and not proc.name in (runc) and not proc.pname=runc` (or `and container.start_ts`
  guards) to the `Sensitive file read in vault-api` rule.
- **Why it matters:** unfiltered FPs cause alert fatigue; a detection engineer's job is
  tuning signal-to-noise, not just enabling rules.

Interview line: *"Falco caught the injection, but it also fired on runc reading
/etc/passwd at init — a false positive I'd tune out, because alert fatigue is how real
detections get missed."*
