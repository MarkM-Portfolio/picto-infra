#!/usr/bin/env bash

set -euo pipefail

# ======================================================
# 🧩 Load environment variables
# ======================================================
set -a

ENV_FILE="./.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Environment file not found at $ENV_FILE"
  exit 1
fi

source "$ENV_FILE"
set +a

kubectl rollout restart deployment
echo "✅ Roolout Restart success!"
