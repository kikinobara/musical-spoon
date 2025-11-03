#!/bin/bash
# ==========================================================
# Ubuntu 24 LTS - Kubernetes env install automation
# ==========================================================
# v0.0.1
# 
# 
# ----------------------------------------------------------

# Setup the ip addresses here
MASTER1IP="192.168.15.190"
WORKER1IP="192.168.15.191"
WORKER2IP="192.168.15.192"

# Main user of the server (will receive docker permissions and others)
MAINUSER="rsantos"



# --- BEGINNING OF AUTOMATION ---


# SECTION 1 - PRE CONFIGS AND DEPENDENCIES

echo set hostnames:
sudo hostnamectl set-hostname master-1

echo "setting hosts entries  on all nodes (adjust if you use internal/private IPs)"
echo "$MASTER1IP master-1" | sudo tee -a /etc/hosts
echo "$WORKER1IP worker-1" | sudo tee -a /etc/hosts
echo "$WORKER2IP worker-2" | sudo tee -a /etc/hosts

# refresh packages & basic tools
sudo apt-get update && sudo apt-get install -y curl ca-certificates gpg apt-transport-https


Echo "Validate and press ENTER to continue"

hostnamectl
getent hosts master-1 worker-1 worker-2

read

echo "Kernel & networking sysctls & disable swap"

echo "load modules on boot"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
echo done

echo "sysctls for routing & bridged traffic"
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system
echo done

echo "disable swap (runtime + persistent)..."
sudo swapoff -a
sudo sed -ri '/\sswap\s/s/^/#/' /etc/fstab
echo done

echo "config finished. starting validation..."
lsmod | grep -E 'br_netfilter|overlay'
sysctl net.ipv4.ip_forward
sysctl net.bridge.bridge-nf-call-iptables
swapon --show     # (should print nothing)
echo done

echo "finished. please check if swapon has returned 0 and press ENTER to continue"
read


# SECTION 2 - INSTALL DOCKER ENGINE

echo "installing docker"

# Docker official repo
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg - dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg - print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
echo done

echo "setting cgroup driver to systemd..."

sudo mkdir -p /etc/docker

cat <<'EOF' | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "100m" },
  "storage-driver": "overlay2"
}
EOF


sudo systemctl daemon-reload
sudo systemctl enable --now docker
sudo systemctl restart docker
echo done

echo "setting up user for docker use without sudo access..."
sudo usermod -aG docker $MAINUSER
newgrp docker
docker ps
echo done

echo "validating docker cgroup format (must be systemd-active)"
docker info --format '{{.CgroupDriver}}' # should be: systemd
systemctl is-active docker # active
echo "press ENTER to continue..."
read


# Install cri-dockerd
echo "Install cri-dockerd (all nodes)"
wget https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.20/cri-dockerd_0.3.20.3-0.debian-bookworm_amd64.deb
sudo dpkg -i cri-dockerd_0.3.20.3-0.debian-bookworm_amd64.deb
sudo apt-get install -f -y
which cri-dockerd
# enable socket/service
sudo systemctl enable --now cri-docker.socket
sudo systemctl enable --now cri-docker.service
echo done

echo "validating installation:"
systemctl is-active cri-docker.socket
systemctl is-active cri-docker.service
ss -ltn | grep -E '(/run/cri-dockerd.sock)?' # optional
which cri-dockerd
echo "press ENTER to continue"
read

# SECTION 3 - INSTALL KUBEADM, KUBELET, KUBECTL (ALL NODES)

echo "Install kubeadm, kubelet, kubectl (all nodes):"

sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
# keyring (create dir if needed)
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | \
        sudo gpg - dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl


echo "validating install - kubelet may stay in a waiting state until init/join"
kubeadm version && kubelet --version && kubectl version --client
systemctl enable - now kubelet || true 
echo "press ENTER to continue"
read


echo "all nodes installation finished."

exit 0
