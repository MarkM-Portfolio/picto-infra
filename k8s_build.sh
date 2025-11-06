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

# Normalize environment name and set Helm release name
case "$(echo "$ENVIRONMENT" | tr '[:upper:]' '[:lower:]')" in
  prod | production)
    ENVIRONMENT="production"
    RELEASE="${REPO_NAME}"
    ;;
  dev | development)
    ENVIRONMENT="development"
    RELEASE="${REPO_NAME}-dev"
    ;;
  stage | staging)
    ENVIRONMENT="staging"
    RELEASE="${REPO_NAME}-stage"
    ;;
  test | testing)
    ENVIRONMENT="test"
    RELEASE="${REPO_NAME}-test"
    ;;
  *)
    ENVIRONMENT="unknown"
    RELEASE="${REPO_NAME}-unknown"
    ;;
esac

CHART=$(basename "./kubernetes")
export ENVIRONMENT HOST_IP HOST_GATEWAY_IP RELEASE CHART

generate_envsubst_vars() {
  grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$1" \
    | cut -d '=' -f1 \
    | awk '{printf "${%s} ", $1}' \
    | sed 's/ $//'  # remove trailing space
}

# ========================================
# CLI Colors
# ========================================
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
RES='\033[0m'

# ========================================
# Detect host platform for K3d configuration
# ========================================
HOST_IP=""
HOST_GATEWAY_IP=""
HOST_ALIAS_FLAG=""
LOCALHOST_ALIAS_CMD=""
DELETE_ALIAS_CMD=""
DOMAIN_ALIAS_CMD=""

case "$(uname -s)" in
  Darwin*)
    # macOS / Docker Desktop
    INTERFACE=$(route get default 2>/dev/null | awk '/interface:/ {print $2}')
    HOST_IP=$(ipconfig getifaddr "${INTERFACE}")
    HOST_GATEWAY_IP=$(route -n get default | grep gateway | awk '{print$2}')
    LOCALHOST_ALIAS_CMD='sudo sed -i "" -E "s/(127\.0\.0\.1[[:space:]]+localhost).*/\1/" /etc/hosts; sudo sed -i "" -E "s/^(127\.0\.0\.1[[:space:]]+localhost)$/\1 registry-browser.localhost grafana.localhost prometheus.localhost/" /etc/hosts'
    DELETE_ALIAS_CMD='sudo sed -i "" -E "/(ca-server|registry-browser|grafana|prometheus)\.picto-sdn\.com/d" /etc/hosts'
    DOMAIN_ALIAS_CMD='echo -e "${HOST_IP}\tca-server.${DOMAIN_PREFIX}.dev ca-server.${DOMAIN_PREFIX}.com registry-browser.${DOMAIN_PREFIX}.dev registry-browser.${DOMAIN_PREFIX}.com grafana.${DOMAIN_PREFIX}.dev grafana.${DOMAIN_PREFIX}.com prometheus.${DOMAIN_PREFIX}.dev prometheus.${DOMAIN_PREFIX}.com" | sudo tee -a /etc/hosts > /dev/null'
    echo -e "\\n🍎 MACOS detected → no host alias needed (Docker Desktop already provides host.docker.internal)\\n"
    ;;
  Linux*)
    # Linux — manually inject host.docker.internal
    INTERFACE=$(ip route | awk '/default/ {print $5; exit}')
    HOST_IP=$(ip -4 addr show "${INTERFACE}" | awk '/inet / {print $2}' | cut -d/ -f1)
    HOST_GATEWAY_IP=$(ip route | awk '/default/ {print $3}')
    LOCALHOST_ALIAS_CMD='sudo sed -i -E "s/(127\.0\.0\.1[[:space:]]+localhost).*/\1/" /etc/hosts; sudo sed -i -E "s/^(127\.0\.0\.1[[:space:]]+localhost)$/\1 registry-browser.localhost grafana.localhost prometheus.localhost/" /etc/hosts'
    DELETE_ALIAS_CMD='sudo sed -i -E "/(ca-server|registry-browser|grafana|prometheus)\.picto-sdn\.com/d" /etc/hosts'
    DOMAIN_ALIAS_CMD='echo -e "${HOST_IP}\tca-server.${DOMAIN_PREFIX}.dev ca-server.${DOMAIN_PREFIX}.com registry-browser.${DOMAIN_PREFIX}.dev registry-browser.${DOMAIN_PREFIX}.com grafana.${DOMAIN_PREFIX}.dev grafana.${DOMAIN_PREFIX}.com prometheus.${DOMAIN_PREFIX}.dev prometheus.${DOMAIN_PREFIX}.com" | sudo tee -a /etc/hosts > /dev/null'
    if [[ -n "$HOST_GATEWAY_IP" ]]; then
      HOST_ALIAS_FLAG="--host-alias ${HOST_GATEWAY_IP}:host.docker.internal"
      echo -e "\\n🐧 LINUX detected → using host alias ${HOST_GATEWAY_IP}:host.docker.internal\\n"
    else
      echo -e "\\n⚠️ Could not determine Docker gateway IP — skipping host alias\\n"
    fi
    ;;
  MINGW*|CYGWIN*|MSYS*)
    # Windows (Git Bash / WSL Docker Desktop)
    echo -e "\\n🪟 Windows detected → no host alias needed (Docker Desktop provides host.docker.internal)\\n"
    ;;
  *)
    echo -e "\\n❓ Unknown OS ($(uname -s)) → skipping host alias\\n"
    ;;
esac

VARS_TO_SUBST=$(generate_envsubst_vars ${ENV_FILE})
VARS_TO_SUBST="${VARS_TO_SUBST} \${PWD} \${ENVIRONMENT} \${HOST_IP} \${HOST_GATEWAY_IP} \${RELEASE} \${CHART}"

if ! command -v k3d > /dev/null 2>&1; then
    echo "❌ k3d not found in PATH. Please install it first."
    exit 1
fi

# ======================================================
# ☸️ Create K3d cluster (after registry ready)
# ======================================================
if ! k3d cluster list | grep -q ^${REPO_NAME}-cluster; then
    echo "🧩 No cluster named '${REPO_NAME}-cluster' found. Creating new K3d cluster..."
    k3d cluster create ${REPO_NAME}-cluster \
        --servers ${CONTROL_PLANE_NODES} --agents ${WORKER_NODES} \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer" \
        --k3s-arg "--node-name=${REPO_NAME}@server:*" \
        --registry-config <(cat <<EOF
mirrors:
  "localhost:${CONTAINER_REGISTRY_LOCAL_PORT}":
    endpoint:
      - "http://registry:${CONTAINER_REGISTRY_PORT}"
EOF
    ) \
    ${HOST_ALIAS_FLAG}
    echo "✅ Cluster '${REPO_NAME}-cluster' created."
else
    echo "✅ Cluster '${REPO_NAME}-cluster' already exists."
fi

# Add local DNS entries
for cmd in "${LOCALHOST_ALIAS_CMD}" "${DELETE_ALIAS_CMD}" "${DOMAIN_ALIAS_CMD}"; do
    [[ -n "$cmd" ]] && eval "$cmd"
done

echo -e "\n→ ${CYAN}/etc/hosts${RES} entries (ca-server/registry-browser/grafana/prometheus):"
grep -E "ca-server|registry-browser|grafana|prometheus" /etc/hosts | sed 's/^/\t/' || true

# ======================================================
# 🧱 Ensure registry container is running before cluster
# ======================================================
if ! docker ps --format '{{.Names}}' | grep -q '^registry$'; then
    echo "🧱 Starting local Docker registry..."
    docker-compose --env-file ./.env up -d registry
else
  echo "✅ Registry container already running."
fi

# ======================================================
# 🔗 Connect registry to k3d network (if exists)
# ======================================================
NETWORK="k3d-${REPO_NAME}-cluster"
CONTAINER="registry"
# 1. Make sure network exists
if ! docker network ls --format '{{.Name}}' | grep -qx "$NETWORK"; then
    echo "❌ Docker network '$NETWORK' not found."
    exit 1
fi
# 2. Try to connect and capture both stdout + stderr
output="$(docker network connect "$NETWORK" "$CONTAINER" 2>&1)" || true
exit_code=$?
# 3. Decide what happened
if [[ "$output" == *"already exists"* ]]; then
    echo "ℹ️  Registry already connected to Docker network '$NETWORK'."
elif [[ $exit_code -eq 0 ]]; then
    echo "✅ Connected registry to Docker network '$NETWORK'."
else
    echo "❌ Failed to connect registry to Docker network '$NETWORK'."
    echo "---- docker output ----"
    echo "$output"
    echo "------------------------"
    exit "$exit_code"
fi

# ========================================
# Wait for Kubernetes nodes to be ready
# ========================================
echo -e "\\n⏳ Checking Kubernetes nodes..."
if ! kubectl get nodes --no-headers | grep -q "Ready"; then
    echo "⏳ Waiting for nodes to become Ready..."
    sleep 10
    kubectl wait --for=condition=Ready nodes --all --timeout=120s
else
    echo "✅ Nodes are ready."
fi

# # ======================================================
# # Generate Chart.yaml | values.yaml | values-env.yaml from template
# # ======================================================
envsubst "${VARS_TO_SUBST}" < ${CHART}/Chart-template.yaml > ${CHART}/Chart.yaml
envsubst "${VARS_TO_SUBST}" < ${CHART}/values-template.yaml > ${CHART}/values.yaml

{
  echo "config:"
  echo "  name: ${REPO_NAME}-env"
  echo "  env:"
  envsubst "${VARS_TO_SUBST}" < ${ENV_FILE} \
    | grep -vE '^\s*#' \
    | awk -F= '{if (NF>= 2) printf "    %s: \"%s\"\n", $1, $2}' \
    | cut -d '#' -f1,3 | sed -e 's/[[:space:]]*$//' -e '/"$/!s/$/"/'
} > "${CHART}/values-env.yaml"

# ======================================================
# Deploy Helm chart
# ======================================================
echo ""
echo -e "${CYAN}───────────────────────────────────────────────${RES}"
echo -e "${PURPLE}🚀 Deployment Summary${RES}"
echo -e "${CYAN}───────────────────────────────────────────────${RES}"
echo ""
echo -e "📦  ${GREEN}Release:${RES}                 🧩  ${RELEASE}"
echo -e "📁  ${GREEN}Chart Path:${RES}              🗂️  ${CHART}"
echo -e "☸️  ${GREEN}K3d Cluster:${RES}             🖥️  ${REPO_NAME}-cluster"
echo -e "🔐  ${GREEN}Container Registry:${RES}      🧱  k3d-${REPO_NAME}-registry:${CONTAINER_REGISTRY_PORT}"
echo -e "🪣  ${GREEN}Local Registry (Host):${RES}   🌐  localhost:${CONTAINER_REGISTRY_LOCAL_PORT}"
echo -e "🏷️  ${GREEN}Namespace:${RES}               🗃️  ${RELEASE}"
echo -e "🔧  ${GREEN}Environment:${RES}             🌍  ${ENVIRONMENT}"
echo -e "🕒  ${GREEN}Deploy Time:${RES}             ⏰  $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo -e "${CYAN}───────────────────────────────────────────────${RES}"
echo ""

# # ======================================================
# 🧩 Ensure Namespace Exists (Helm-compatible)
# # ======================================================
if kubectl get namespace "${RELEASE}" > /dev/null 2>&1; then
  echo "✅ Namespace '${RELEASE}' already exists. Ensuring Helm ownership labels..."
  kubectl label namespace "${RELEASE}" app.kubernetes.io/managed-by=Helm --overwrite > /dev/null 2>&1 || true
  kubectl annotate namespace "${RELEASE}" meta.helm.sh/release-name="${RELEASE}" --overwrite > /dev/null 2>&1 || true
  kubectl annotate namespace "${RELEASE}" meta.helm.sh/release-namespace="${RELEASE}" --overwrite > /dev/null 2>&1 || true
else
  echo "🆕 Creating namespace '${RELEASE}'..."
  kubectl create namespace "${RELEASE}" > /dev/null 2>&1 || true
  kubectl label namespace "${RELEASE}" app.kubernetes.io/managed-by=Helm > /dev/null 2>&1
  kubectl annotate namespace "${RELEASE}" meta.helm.sh/release-name="${RELEASE}" > /dev/null 2>&1
  kubectl annotate namespace "${RELEASE}" meta.helm.sh/release-namespace="${RELEASE}" > /dev/null 2>&1
fi

# # ======================================================
# 🚀 Helm Upgrade / Install (NO create-namespace)
# # ======================================================
echo -e "\\n🚀 Deploying Helm release '${RELEASE}'..."
helm upgrade --install ${RELEASE} ${CHART} \
  --namespace ${RELEASE} \
  -f ${CHART}/values.yaml \
  -f ${CHART}/values-env.yaml \
  --set-file secret.tls.cert=${PWD}/${DOMAIN_PREFIX}-cert.pem \
  --set-file secret.tls.key=${PWD}/${DOMAIN_PREFIX}-key.pem

# ======================================================
# 🔍 Post-deploy checks
# ======================================================
echo -e "\\n🔍 Switching kubectl context to namespace '${RELEASE}'..."
kubectl config set-context --current --namespace="${RELEASE}" > /dev/null

echo -e "\\n📋 Deployed pods:"
kubectl get pods -n "${RELEASE}"

echo -e "\\n🏁 ${GREEN}Kubernetes build completed${RES}! 🏁"

# ======================================================
# 📱 Serve mkcert Root CA
# ======================================================
# echo -e "\n🔐 Preparing mkcert root CA for local network devices..."
# # Find mkcert root CA path
# local CAROOT
# CAROOT=$(mkcert -CAROOT 2> /dev/null)
# local CA_FILE="${CAROOT}/rootCA.pem"

# if [[ ! -f "$CA_FILE" ]]; then
#   echo "❌ mkcert root CA not found. Run 'mkcert -install' first."
#   exit 1
# fi
# # Copy CA file to current directory
# cp "$CA_FILE" ./mkcert-rootCA.pem

# echo ""
# echo -e "🌐 Serving mkcert CA on:  ${CYAN}http://${HOST_IP}:8080/mkcert-rootCA.pem${RES}"
# echo -e "📱 Scan the QR code below or open in mobile browser to trust this CA:\n"
# # Generate and display QR code
# qrencode -t ANSIUTF8 "http://${HOST_IP}:8080/mkcert-rootCA.pem"
# # Serve via Python HTTP server in background
# nohup python3 -m http.server 8080 > /dev/null 2>&1 &
# echo -e "\n✅ mkcert CA is now being served in the background (PID: $!)"
