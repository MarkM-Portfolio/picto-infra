#!/usr/bin/env bash

set -euo pipefail


# adjust timezone
# install docker, k3d, helm, git, vim, nano, curl, python3
# hosts file cfg, 

# KUBERNETES / K&s
sudo apt -y update
sudo apt -y install ca-certificates curl curl apt-transport-https gnupg
# -- kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
# -- k3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
k3d --version
# -- helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# certs
sudo apt update
sudo apt install -y libnss3-tools
wget -O mkcert https://github.com/FiloSottile/mkcert/releases/latest/download/mkcert-linux-amd64
sudo mv mkcert /usr/local/bin/
sudo chmod +x /usr/local/bin/mkcert

mkcert -install

mkcert -cert-file picto-sdn-cert.pem -key-file picto-sdn-key.pem \
  "*.picto-sdn.com" picto-sdn.com "*.picto-sdn.dev" picto-sdn.dev "*.localhost" localhost "*.nip.io" nip.io
