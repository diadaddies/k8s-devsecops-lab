# Threat Model — vault-api

A lightweight threat model for the deliberately-vulnerable `vault-api` microservice.
The point isn't exhaustiveness — it's to show the *process*: understand the system,
find where trust is crossed, enumerate threats with STRIDE, and map each to a control.

## 1. System & data flow

`vault-api` is a FastAPI service storing "notes" (some containing secrets) in SQLite.
It is deployed as a single Pod in Kubernetes behind a ClusterIP Service.

```
   client ──HTTP──►  [ vault-api Pod ]  ──►  SQLite (/tmp/vault.db)
                          │
                          ├─ /ping   ──► shells out to `ping`      (OS boundary)
                          ├─ /fetch  ──► outbound HTTP to any URL  (network boundary)
                          └─ /config ──► deserializes user YAML    (parser boundary)
```

**Trust boundaries** (where untrusted input crosses into a trusted context):
1. Client → app (all HTTP params are attacker-controlled).
2. App → OS shell (`/ping`).
3. App → arbitrary network (`/fetch`).
4. App → YAML deserializer (`/config`).
5. Pod → cluster (a compromised Pod is a foothold in the cluster).

## 2. Assets to protect

- The notes data (contains secrets/tokens).
- The container/Pod integrity (no code execution, no shell).
- The cluster (no lateral movement or privilege escalation from a Pod).
- The build/artifact integrity (only our signed image should ever run).

## 3. STRIDE → threats → controls

| STRIDE | Threat in vault-api | Endpoint | Control that should catch it |
|--------|--------------------|----------|------------------------------|
| **T**ampering / **E**oP | SQL injection reads/edits any row | `/notes/search` | SAST (semgrep/bandit) → fix to parameterized query |
| **E**oP | OS command injection → RCE in container | `/ping` | SAST + **Falco** (shell spawn) → fix: drop shell, validate input |
| **I**nfo disclosure | SSRF reaches internal services / metadata | `/fetch` | SAST + NetworkPolicy (egress) + manual |
| **T**ampering / **E**oP | Unsafe YAML deserialization → RCE | `/config` | SAST (yaml.load) + **SCA** (PyYAML CVE) → SafeLoader + upgrade |
| **I**nfo disclosure | BOLA/IDOR: read another user's note | `/notes/{id}` | Manual testing only (logic flaw) → add authz check |
| **I**nfo disclosure | Hardcoded secret in source | source | Secret scan + SAST → move to a Secret/KMS |
| **T**ampering | A malicious/unsigned image is deployed | supply chain | **cosign** signing + **Kyverno** verifyImages |
| **E**oP | Container runs as root / privileged | deploy | Manifest scan + **Kyverno** Pod Security |

## 4. Defense-in-depth: which layer owns which threat

```
  code review / SAST / SCA / secrets   →  catch it before it builds
  image scan + SBOM + signing          →  trust the artifact
  Kyverno admission                    →  refuse bad workloads at the door
  Pod securityContext + NetworkPolicy  →  contain what does run
  Falco runtime                        →  detect exploitation in progress
  manual pentest                       →  the logic flaws tools can't see
```

## 5. Explicitly out of scope (say this in an interview)

Authn/session management, DoS/rate-limiting, and multi-tenancy isolation are not
modeled here — a real threat model would state its boundaries. Naming what you
*didn't* cover is a sign of maturity, not a gap.
