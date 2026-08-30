"""
vault-api — a deliberately vulnerable FastAPI microservice for DevSecOps practice.

Every flaw below is INTENTIONAL and labelled with the control that should catch it.
Do NOT copy this into anything real. See docs/threat-model.md.
"""
import os
import sqlite3
import subprocess

import requests
import yaml
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

app = FastAPI(title="vault-api", version="0.1.0")

# FLAW (hardcoded secret / weak JWT key): secret scanning + SAST should flag this.
SECRET_KEY = "supersecret123"  # nosec-NOT — intentionally left for scanners to find

DB_PATH = os.environ.get("VAULT_DB", "/tmp/vault.db")


def db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


@app.on_event("startup")
def seed():
    conn = db()
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS notes(
            id INTEGER PRIMARY KEY, owner TEXT, title TEXT, body TEXT);
        DELETE FROM notes;
        INSERT INTO notes(owner,title,body) VALUES
            ('alice','alice-note','alice private data'),
            ('bob','bob-note','bob SECRET token abc123');
        """
    )
    conn.commit()
    conn.close()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/notes/search")
def search(q: str):
    # FLAW (SQL injection): query built by string concatenation. SAST + manual.
    conn = db()
    sql = "SELECT id,owner,title FROM notes WHERE title LIKE '%" + q + "%'"
    rows = conn.execute(sql).fetchall()
    conn.close()
    return {"query": sql, "results": [dict(r) for r in rows]}


@app.get("/notes/{note_id}")
def get_note(note_id: int):
    # FLAW (BOLA / IDOR): returns any note by id, no ownership check. Manual only.
    conn = db()
    row = conn.execute("SELECT * FROM notes WHERE id=?", (note_id,)).fetchone()
    conn.close()
    if not row:
        raise HTTPException(404, "not found")
    return dict(row)


@app.get("/ping")
def ping(host: str):
    # FLAW (OS command injection): user input to a shell. SAST + FALCO at runtime.
    out = subprocess.check_output("ping -c 1 " + host, shell=True)  # nosec
    return JSONResponse({"output": out.decode(errors="replace")})


@app.get("/fetch")
def fetch(url: str):
    # FLAW (SSRF): fetches an attacker-controlled URL server-side. SAST + manual.
    r = requests.get(url, timeout=5)
    return {"status": r.status_code, "body": r.text[:500]}


@app.post("/config")
def load_config(raw: str):
    # FLAW (unsafe deserialization): yaml.load w/o SafeLoader on old PyYAML. SAST + SCA.
    data = yaml.load(raw, Loader=yaml.Loader)  # nosec
    return {"parsed": data}
