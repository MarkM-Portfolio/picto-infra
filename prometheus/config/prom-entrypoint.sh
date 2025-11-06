#!/usr/bin/env bash

set -e

# Generate Prometheus config YAML
echo "🔧 Generating Prometheus config from template..."

sed \
  -e "s|\${NODE_EXPORTER_HOST}|${NODE_EXPORTER_HOST}|g" \
  -e "s|\${NODE_EXPORTER_PORT}|${NODE_EXPORTER_PORT}|g" \
  -e "s|\${METRICS_PORT}|${METRICS_PORT}|g" \
  -e "s|\${API_PORT}|${API_PORT}|g" \
  -e "s|\${REDIS_PORT}|${REDIS_PORT}|g" \
  ${PROMETHEUS_EPH}/config/prometheus.template \
  > ${PROMETHEUS_EPH}/config/prometheus.yml

# Start Prometheus
echo "🚀 Starting Prometheus..."

exec /bin/prometheus \
    --config.file="${PROMETHEUS_EPH}/config/prometheus.yml" \
    --storage.tsdb.path="${PROMETHEUS_EPH}/data" \
    "$@"
    