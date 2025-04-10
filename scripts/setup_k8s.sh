#!/bin/bash

NODE_TYPE=$1
CONTROL_PLANE_IP=$2

# Configuração inicial (comum para ambos)
sudo apt update
sudo apt install -y docker.io apt-transport-https curl
sudo systemctl enable --now docker

# Desativa swap
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# Kubernetes Repositório
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Instala Kubernetes
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

if [ "$NODE_TYPE" = "control-plane" ]; then
  # Inicializa o Control Plane
  sudo kubeadm init --apiserver-advertise-address=$CONTROL_PLANE_IP --pod-network-cidr=10.244.0.0/16

  # Configuração do kubectl para o usuário padrão (ubuntu)
  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

  # Rede CNI (Flannel)
  kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

else
  # Junta-se ao cluster (workers)
  TOKEN=$(ssh -o StrictHostKeyChecking=no ubuntu@$CONTROL_PLANE_IP "kubeadm token create --print-join-command")
  sudo $TOKEN
fi
