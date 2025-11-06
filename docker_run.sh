#!/usr/bin/env bash

set -euo pipefail

# Initially make sure registry is running (force run/restart)
docker-compose --env-file ./.env --profile container-registry up -d

# Only run docker services container (exclude k8s)
docker-compose --env-file ./.env --profile infra up -d
