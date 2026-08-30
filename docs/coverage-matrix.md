# Control Coverage Matrix

The payoff of the whole project: for each planted flaw, **which layer caught it** —
and, more tellingly, **which attacks nothing automated stopped**. Fill the "observed"
column as you actually run each stage; the "expected" column is the design intent.

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
