#!/usr/bin/env bash
# Creates .env with random secrets. Usage: ./setup.sh [OPENAI_API_KEY]
set -euo pipefail
cd "$(dirname "$0")"

if [ -f .env ]; then
  echo ".env already exists, leaving it untouched."
  exit 0
fi

rand() { openssl rand -hex "$1"; }

OPENAI_KEY="${1:-}"
if [ -z "$OPENAI_KEY" ] && [ -t 0 ]; then
  read -rsp "OpenAI API key (Enter to skip and set it later in .env): " OPENAI_KEY
  echo
fi

OWNER_PASSWORD="Demo$(rand 5)1"

cp .env.example .env
sed -i.bak \
  -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(rand 12)|" \
  -e "s|^N8N_ENCRYPTION_KEY=.*|N8N_ENCRYPTION_KEY=$(rand 24)|" \
  -e "s|^OWNER_PASSWORD=.*|OWNER_PASSWORD=${OWNER_PASSWORD}|" \
  -e "s|^OPENAI_API_KEY=.*|OPENAI_API_KEY=${OPENAI_KEY}|" \
  .env
rm -f .env.bak
chmod 600 .env

echo
echo ".env created."
echo "  n8n URL : http://localhost:5678"
echo "  user    : $(sed -n 's/^OWNER_EMAIL=//p' .env)"
echo "  password: ${OWNER_PASSWORD}"
[ -n "$OPENAI_KEY" ] || echo "  WARNING : OPENAI_API_KEY is empty. Edit .env before starting."
echo
echo "Next: docker compose up -d"
