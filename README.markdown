# Kubernetes 2-Node Cluster Setup

This repository provides scripts and documentation to set up a basic Kubernetes cluster using kubeadm on two Ubuntu nodes:
- **Master Node**: Hostname `master`, IP `<master-ip>`
- **Worker Node**: Hostname `worker-01`, IP `<worker-ip>`

The setup uses:
- Kubernetes v1.33.3
- Docker as the container runtime
- Containerd with cgroup v2 and custom configs
- Calico v3.27.2 as the CNI (pod network CIDR: `192.168.0.0/16`)

## Prerequisites
- Two Ubuntu machines (tested on 22.04 LTS or similar).
- Root/sudo access on both nodes.
- Nodes can communicate over the network (firewalls allow ports like 6443, 10250, etc.; see [Kubernetes ports](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)).
- SSH access between nodes for convenience (not required).
- Know your master and worker node IPs to pass as arguments to the scripts.

## Scripts
- `common-setup.sh`: Run on both nodes to install dependencies, configure containerd/Docker, set up `/etc/hosts` with provided IPs, and install Kubernetes tools.
- `master-init.sh`: Run only on the master to initialize the cluster and apply Calico.
- `worker-join.sh`: Run on the worker to join the cluster (requires the join command from the master).

### How to Use the Scripts
1. Copy the scripts to both nodes.
2. Make them executable: `chmod +x *.sh`

On **Master Node**:
3. Run common setup: `sudo ./common-setup.sh master <master-ip> <worker-ip>` (e.g., `sudo ./common-setup.sh master 192.168.137.147 192.168.137.148`)
4. Run init: `sudo ./master-init.sh <master-ip>`
   - This will output a join command like `kubeadm join <master-ip>:6443 --token ... --discovery-token-ca-cert-hash sha256:...`
   - Copy this command.

On **Worker Node**:
5. Run common setup: `sudo ./common-setup.sh worker-01 <master-ip> <worker-ip>`
6. Join the cluster: `sudo ./worker-join.sh 'paste-the-full-join-command-here'`

## Verification
- On master: `kubectl get nodes` (should show both nodes as Ready after a few minutes).
- On master: `kubectl get pods --all-namespaces` (check Calico and core pods are running).
- If issues: Check logs with `journalctl -u kubelet` or `kubectl logs`.

## Detailed Steps (Manual Equivalent)
If you prefer manual execution, here are the steps the scripts automate:

### Common Steps (All Nodes)
1. Set hostname: `hostnamectl set-hostname <master or worker-01>`
2. Disable swap: `sed -i '/swap/s/^\//\#\//g' /etc/fstab && swapoff -a`
3. Update packages: `sudo apt update`
4. Install tools: `apt install apt-transport-https ca-certificates curl gnupg lsb-release htop net-tools vim -y`
5. Set up Docker repo:  
   `mkdir -p /etc/apt/keyrings`  
   `curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg`  
   `echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null`
6. Install Docker: `apt update && apt install docker.io -y`
7. Configure containerd:  
   `containerd config default | sudo tee /etc/containerd/config.toml`  
   `mkdir -p /etc/containerd/`  
   Edit `/etc/containerd/config.toml`:  
   - Set `sandbox_image = "registry.k8s.io/pause:3.10"`  
   - Add `config_path = "/etc/containerd/certs.d"` under `[plugins."io.containerd.grpc.v1.cri".registry]`  
   - Set `SystemdCgroup = true`
8. Restart services: `systemctl restart containerd.service && systemctl restart docker.service`
9. Load modules:  
   `cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf`  
   `overlay`  
   `br_netfilter`  
   `EOF`  
   `modprobe overlay && modprobe br_netfilter`
10. Sysctl config:  
    `cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf`  
    `net.bridge.bridge-nf-call-iptables = 1`  
    `net.ipv4.ip_forward = 1`  
    `net.bridge.bridge-nf-call-ip6tables = 1`  
    `EOF`  
    `sysctl --system`
11. Update `/etc/hosts`: Add lines for `<master-ip> master` and `<worker-ip> worker-01`
12. Set up Kubernetes repo:  
    `curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg`  
    `echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list > /dev/null`
13. Install Kubernetes: `apt update && apt install -qy kubelet=1.33.3-1.1 kubectl=1.33.3-1.1 kubeadm=1.33.3-1.1`  
    `apt-mark hold kubelet kubeadm kubectl`

### Master-Only Steps
14. Pull images: `kubeadm config images pull`
15. Init cluster: `kubeadm init --kubernetes-version=v1.33.3 --pod-network-cidr=192.168.0.0/16 --upload-certs --control-plane-endpoint=<master-ip>:6443 --apiserver-advertise-address=<master-ip>`
16. Set up kubeconfig:  
    `mkdir -p $HOME/.kube`  
    `sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config`  
    `sudo chown $(id -u):$(id -g) $HOME/.kube/config`
17. Apply Calico: `kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/calico.yaml`
18. Generate join command: `kubeadm token create --print-join-command`

### Worker-Only Steps
19. Join: Run the join command from master, e.g., `kubeadm join <master-ip>:6443 --token ... --discovery-token-ca-cert-hash sha256:...`

## Troubleshooting
- **Node not ready?** Ensure Calico pods are running and check for taint removal if needed: `kubectl taint nodes --all node-role.kubernetes.io/control-plane-`
- **Networking issues?** Verify pod CIDR matches Calico config and IPs in `/etc/hosts` are correct.
- **Version mismatches?** Use `apt-cache policy kubeadm` to confirm versions.
- For more, see official docs: [Kubernetes](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/), [Calico](https://docs.tigera.io/calico/latest/getting-started/kubernetes/quickstart).

## License
MIT License - feel free to use and modify.