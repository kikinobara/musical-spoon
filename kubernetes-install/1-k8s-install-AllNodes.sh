#!/bin/bash
# ==========================================================
# Ubuntu 24 LTS - Kubernetes env install automation
# ==========================================================
# v0.0.3 - corrigido por ChatGPT (GPT-5)
# ----------------------------------------------------------

MASTER1IP="192.168.15.190"
WORKER1IP="192.168.15.191"
WORKER2IP="192.168.15.192"


# SECTION 1 - PRE CONFIGS AND DEPENDENCIES
echo "Setting hosts entries..."
echo "$MASTER1IP master-1" | sudo tee -a /etc/hosts
echo "$WORKER1IP worker-1" | sudo tee -a /etc/hosts
echo "$WORKER2IP worker-2" | sudo tee -a /etc/hosts

sudo apt-get update && sudo apt-get install -y curl ca-certificates gpg apt-transport-https

echo "Validate and press ENTER to continue"
hostnamectl
getent hosts master-1 worker-1 worker-2
read

echo "Kernel & networking sysctls & disable swap"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system

sudo swapoff -a
sudo sed -ri '/\sswap\s/s/^/#/' /etc/fstab
swapon --show
read -p "Check if swap shows nothing and press ENTER..."

# SECTION 2 - INSTALL DOCKER ENGINE
echo "Installing Docker..."

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

sudo mkdir -p /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "100m" },
  "storage-driver": "overlay2"
}
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now docker

# Adiciona o usuário principal ao grupo docker
sudo usermod -aG docker $MAINUSER
echo "⚠️  O usuário $MAINUSER foi adicionado ao grupo 'docker'."
echo "Você precisará sair e entrar novamente na sessão para aplicar a permissão."
echo

# Testa Docker via sudo (sem precisar reiniciar a sessão agora)
sudo docker ps
sudo docker info --format '{{.CgroupDriver}}'
systemctl is-active docker
read -p "Docker validated. Press ENTER..."

# SECTION 2.1 - INSTALL CRI-DOCKERD

echo "Installing cri-dockerd..."

# Detecta e baixa automaticamente a versão mais recente
LATEST=$(curl -s https://api.github.com/repos/Mirantis/cri-dockerd/releases/latest | grep "browser_download_url" | grep "ubuntu-jammy" | cut -d '"' -f 4)
wget $LATEST -O cri-dockerd.deb
sudo dpkg -i cri-dockerd.deb || sudo apt-get install -f -y

sudo systemctl enable --now cri-docker.socket
sudo systemctl enable --now cri-docker.service

systemctl is-active cri-docker.socket
systemctl is-active cri-docker.service
which cri-dockerd
ss -ltn | grep cri-dockerd
read -p "CRI-dockerd validated. Press ENTER..."

# SECTION 3 - INSTALL KUBEADM, KUBELET, KUBECTL
echo "Installing kubeadm, kubelet, kubectl..."

sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

kubeadm version && kubelet --version && kubectl version --client
read -p "Press ENTER to finish..."

echo "✅ All nodes installation finished successfully!"
exit 0