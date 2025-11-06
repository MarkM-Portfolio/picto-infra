#!/usr/bin/env bash

set -euo pipefail

# Load port from .env
export $(grep -E '^CONTAINER_REGISTRY_LOCAL_PORT' ./.env | xargs)
REGISTRY_URL="http://localhost:${CONTAINER_REGISTRY_LOCAL_PORT}"

echo -e "\\n📦 Repositories and tags in ${REGISTRY_URL}\\n"

# Get repository list
repos=$(curl -s "${REGISTRY_URL}/v2/_catalog" | jq -r '.repositories[]?')

# Check if empty
if [[ -z "${repos}" ]]; then
    echo "⚠️  No repositories found in registry."
    exit 0
fi

# Loop through repos and list tags
echo "${repos}" | while read repo; do
    tags=$(curl -s "${REGISTRY_URL}/v2/${repo}/tags/list" | jq -r '.tags[]?' | tr '\n' ' ')
    echo "🧱 ${repo}: ${tags:-<none>}"
done