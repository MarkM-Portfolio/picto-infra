#!/usr/bin/env bash

set -euo pipefail

# Initially build and run registry
docker-compose --env-file ./.env --profile container-registry up -d --build

# Build and push images to registry (registry image included)
docker-compose --env-file ./.env --profile '*' build --push

# Verify registry catalog
./registry.sh
