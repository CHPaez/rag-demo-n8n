#!/bin/sh
# Runs before n8n starts: creates credentials and imports workflows from .env values.
# Idempotent: credentials are refreshed on every start (so a new OPENAI_API_KEY applies);
# workflows are imported only once, so edits made in the UI are never overwritten.
set -eu

MARKER=/home/node/.n8n/.rag-bootstrap-done
CREDS=/tmp/rag-credentials.json

# --- 1. Owner account (optional): needs OWNER_EMAIL and OWNER_PASSWORD -----------------
if [ -n "${OWNER_EMAIL:-}" ] && [ -n "${OWNER_PASSWORD:-}" ]; then
  N8N_INSTANCE_OWNER_PASSWORD_HASH=$(cd /usr/local/lib/node_modules/n8n && \
    node -e 'process.stdout.write(require("bcryptjs").hashSync(process.env.OWNER_PASSWORD, 10))')
  export N8N_INSTANCE_OWNER_PASSWORD_HASH
  export N8N_INSTANCE_OWNER_MANAGED_BY_ENV=true
  echo "[bootstrap] Owner account will be created from OWNER_EMAIL / OWNER_PASSWORD."
else
  unset N8N_INSTANCE_OWNER_EMAIL || true
  echo "[bootstrap] OWNER_EMAIL/OWNER_PASSWORD not set: create the owner in the web UI."
fi

# --- 2. Credentials (Postgres + OpenAI) -------------------------------------------------
node -e '
const e = process.env;
const creds = [
  { id: "ragPostgresCred", name: "Postgres RAG (auto)", type: "postgres",
    data: { host: "db", port: 5432, database: e.POSTGRES_DB, user: e.POSTGRES_USER,
            password: e.POSTGRES_PASSWORD, ssl: "disable", allowUnauthorizedCerts: false,
            maxConnections: 100 } },
  { id: "ragOpenAiCred", name: "OpenAI RAG (auto)", type: "openAiApi",
    data: { apiKey: e.OPENAI_API_KEY || "", url: "https://api.openai.com/v1", header: false } },
];
require("fs").writeFileSync(process.argv[1], JSON.stringify(creds));
' "$CREDS"

if n8n import:credentials --input="$CREDS" >/dev/null 2>&1; then
  echo "[bootstrap] Credentials imported."
else
  echo "[bootstrap] WARNING: could not import credentials; create them in the UI."
fi
rm -f "$CREDS"

if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "[bootstrap] WARNING: OPENAI_API_KEY is empty. Set it in .env and run: docker compose up -d --force-recreate n8n"
fi

# --- 3. Workflows (first start only) ----------------------------------------------------
if [ ! -f "$MARKER" ]; then
  ok=1
  for f in /workflows/*.json; do
    n8n import:workflow --input="$f" >/dev/null 2>&1 || ok=0
  done
  if [ "$ok" = 1 ]; then
    touch "$MARKER"
    echo "[bootstrap] Workflows imported."
  else
    echo "[bootstrap] WARNING: some workflows failed to import; retry with a restart."
  fi
fi

exec /docker-entrypoint.sh "$@"
