#!/usr/bin/env bash

RED='\033[0;31m'
BLINK='\033[5m'
RES='\033[0m'

echo -e "\\n+-------------------------------------------------+"
echo -e "🚨 ${BLINK}${RED}DANGER:${RES} This will nuke entire infrastructure 🔥"
echo -e "+-------------------------------------------------+\\n"

read -p "Are you sure? (y/n): " answer
if [[ "$answer" == [Yy]* ]]; then
  echo "✅ You said yes."
else
  echo "❌ You said no."
  exit 1
fi

# 🧩 1. Delete all K3d clusters
k3d cluster delete --all && \
# 🧱 2. Delete all K3d registries
k3d registry delete --all && \
# 🧰 3. OPTIONAL — stop *all* containers
docker stop $(docker ps -aq) 2> /dev/null || true && \
# 🧰 4. OPTIONAL — remove *all* containers (including tagged ones)
docker rm -f $(docker ps -aq) 2> /dev/null || true && \
# 🧰 5. OPTIONAL — remove *all* images (including tagged ones)
docker rmi -f $(docker images -aq) 2> /dev/null || true && \
# 🧼 6. Remove unused volumes (old intermediate layers)
docker volume prune -f && \
# 🧱 8. Remove all unused networks (old intermediate layers)
docker network prune -f && \
# 🧱 9. Remove all unused build cache (old intermediate layers)
docker builder prune -af && \
# 🧺 10. Remove all volumes (careful: deletes ALL Docker volumes)
docker system prune -af --volumes
# 🧺 11. Remove all k3d infra (careful: deletes ALL k3d infra)
export $(grep -E '^REPO_NAME' ./.env | xargs) && \
k3d cluster delete ${REPO_NAME}-cluster
# 🧺 12. Remove all kubernetes workloads (careful: deletes ALL kubernetes workloads)
kubectl delete all --all --all-namespaces 2> /dev/null || true && \
rm -rf ${KUBECONFIG} && unset KUBECONFIG

echo -e "\\n❗💥💥 NUKED 💥💥❗"
