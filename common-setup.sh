#!/bin/bash

# Set hostname and IPs (run with hostname and IPs: 'master <master-ip> <worker-ip>' or 'worker-01 <master-ip> <worker-ip>')
if [ "$#" -ne 3 ]; then
    echo "Usage: sudo $0 <hostname> <master-ip> <worker-ip> (e.g., master 192.168.137.147 192.168.137.148)"
    exit 1
fi
HOSTNAME=$1
MASTER_IP=$2
WORKER_IP=$3

hostnamectl set-hostname $HOSTNAME

# Disable swap
sed -i '/swap/s/^\//\#\//g' /etc/fstab
swapoff -a

# Update and install prerequisites
apt update
apt install apt-transport-https ca-certificates curl gnupg lsb-release htop net-tools vim -y

# Install Docker
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install docker.io -y

# Configure containerd
containerd config default | sudo tee /etc/containerd/config.toml
mkdir -p /etc/containerd/  # Ensure directory exists
sed -i 's|sandbox_image = "registry.k8s.io/pause:3.8"|sandbox_image = "registry.k8s.io/pause:3.10"|g' /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Restart and verify containerd
systemctl restart containerd.service
if ! systemctl is-active --quiet containerd; then
    echo "Error: containerd failed to start. Check logs with 'journalctl -u containerd -n 100'"
    exit 1
fi
if [ ! -S /var/run/containerd/containerd.sock ]; then
    echo "Error: containerd socket /var/run/containerd/containerd.sock not found."
    exit 1
fi

# Restart and verify Docker
systemctl restart docker.service
if ! systemctl is-active --quiet docker; then
    echo "Error: Docker failed to start. Check logs with 'journalctl -u docker -n 100'"
    exit 1
fi

# Load kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Sysctl settings
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system

# Update /etc/hosts with provided IPs
cat <<EOF | sudo tee -a /etc/hosts
${MASTER_IP} master
${WORKER_IP} worker-01
EOF

# Install Kubernetes repo
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
apt update -q

# Install specific Kubernetes versions
apt install -qy kubelet=1.33.3-1.1 kubectl=1.33.3-1.1 kubeadm=1.33.3-1.1
apt-mark hold kubelet kubeadm kubectl

echo "Common setup complete. On master, proceed to master-init.sh. On worker, wait for join command."
