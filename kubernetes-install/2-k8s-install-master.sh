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
NETWORKTYPE="192.168.15.0/24"

# Main user of the server (will receive docker permissions and others)
MAINUSER="rsantos"

# SECTION 1 -  CONTROL PLANE INIT

echo  "Control-plane init (run ONLY on master-1)"

sudo kubeadm init \
 - apiserver-advertise-address=$MASTER1IP \
 - pod-network-cidr=192.168.0.0/16 \
 - cri-socket=unix:///run/cri-dockerd.sock

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "Control-Plane initiated starting validation ( control-plane will be NotReady until CNI is installed)"

kubectl cluster-info

kubectl get nodes -o wide 

echo "press ENTER to continue"
read


# SECTION 2 - INSTALL CALICO CNI

echo "Install Calico CNI (on master-1)"

# Install operator + CRDs (use latest v3.xx from docs page; example uses v3.30.3)
kubectl create -f calico/operator-crds.yaml
kubectl create -f calico/tigera-operator.yaml

# Get default custom-resources (edit if you want to change IP pool/CIDR/encapsulation)
kubectl create -f calico/custom-resources.yaml
echo "install finished. validating..."

# Calico Install validation
echo "calico install validation - should turn Ready once calico-node is up"
kubectl -n tigera-operator rollout status deploy/tigera-operator
watch kubectl get pods -n calico-system
kubectl get nodes 
echo "press ENTER to continue"
read

echo "Kubernetes setup finished. run join command on worker nodes to add them."
exit 0


