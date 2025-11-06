#!/usr/bin/env bash

set -e

# Generate Grafana provisioning YAML
echo "🔧 Generating Grafana provisioning from template..."

sed \
  -e "s|\${PROMETHEUS_PORT}|${PROMETHEUS_PORT}|g" \
  -e "s|\${REDIS_PORT}|${REDIS_PORT}|g" \
  ${GRAFANA_PVC}/provisioning/datasources/data-metrics.template \
  > ${GRAFANA_PVC}/provisioning/datasources/data-metrics.yml

# Start Grafana
echo "🚀 Starting Grafana..."

/run.sh
