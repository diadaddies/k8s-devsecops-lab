# Multi-stage, hardened image. The APP CODE is deliberately vulnerable, but the
# CONTAINER is built correctly — that separation is itself a lesson: a well-built
# image can still ship exploitable code, which is why runtime detection matters.

# ---- build stage: install deps into a venv ----
FROM python:3.12-slim AS build
WORKDIR /app
RUN python -m venv /venv
ENV PATH="/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ---- runtime stage: slim, non-root, no build tools ----
FROM python:3.12-slim AS runtime
# Create an unprivileged user; Kyverno will require runAsNonRoot.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
COPY --from=build /venv /venv
COPY main.py /app/main.py
ENV PATH="/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    VAULT_DB=/tmp/vault.db
WORKDIR /app
USER 10001
EXPOSE 8000
# uvicorn on 8000; app writes only to /tmp so readOnlyRootFilesystem works.
ENTRYPOINT ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
