#!/bin/bash
# ==========================================================
# Ubuntu 24 LTS - Kubernetes Control Plane Init Automation
# ==========================================================
# v0.0.2 - corrigido e validado (mantendo Calico local)
# ----------------------------------------------------------

# Setup the IP addresses here
MASTER1IP="192.168.15.190"
WORKER1IP="192.168.15.191"
WORKER2IP="192.168.15.192"
NETWORKTYPE="192.168.15.0/24"
POD_NETWORK_CIDR="192.168.0.0/16"

# Main user of the server (will receive docker permissions and others)
MAINUSER="rsantos"

# ==========================================================
# SECTION 1 - CONTROL PLANE INIT
# ==========================================================
echo -e "\n🔹 Iniciando Control Plane (rodar APENAS no master-1)\n"

sudo kubeadm init \
  --apiserver-advertise-address=${MASTER1IP} \
  --pod-network-cidr=${POD_NETWORK_CIDR} \
  --cri-socket=unix:///run/cri-dockerd.sock

echo -e "\n🔹 Configurando kubeconfig para o usuário ${MAINUSER}..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo -e "\n✅ Control Plane inicializado."
echo "   (O nó ficará como 'NotReady' até a instalação do Calico CNI)"
kubectl cluster-info
kubectl get nodes -o wide

read -p "Pressione ENTER para continuar..."

# ==========================================================
# SECTION 2 - INSTALL CALICO CNI (LOCAL FILES)
# ==========================================================
echo -e "\n🔹 Instalando Calico CNI (arquivos locais em ./calico)\n"

# Confirma se a pasta existe
if [ ! -d "./calico" ]; then
  echo "❌ Erro: diretório ./calico não encontrado."
  echo "Certifique-se de estar rodando o script na mesma pasta que a pasta 'calico'."
  exit 1
fi

# Instala operador, CRDs e custom resources (na ordem correta)
kubectl create -f calico/operator-crds.yaml
kubectl create -f calico/tigera-operator.yaml
kubectl create -f calico/custom-resources.yaml

echo -e "\n⏳ Aguardando implantação do operador Calico..."
kubectl -n tigera-operator rollout status deploy/tigera-operator --timeout=180s || true

echo -e "\n✅ Calico instalado com sucesso!"
echo "Use os comandos abaixo para acompanhar:"
echo "  watch kubectl get pods -n calico-system"
echo "  kubectl get nodes -o wide"

read -p "Pressione ENTER para continuar..."

echo -e "\n✅ Kubernetes Control Plane configurado com sucesso!"
echo "👉 Agora, execute o comando 'kubeadm join ...' mostrado durante o init nos nodes worker."
echo
exit 0