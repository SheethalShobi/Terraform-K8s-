#!/bin/bash
 
kubeadm init
 
# Set up kubectl for ubuntu user
mkdir -p /home/ubuntu/.kube
cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config
 
# Install Weave Net CNI
echo "Installing Weave Net..."
sudo -u ubuntu kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
 
# Wait for node to become Ready
echo "Waiting for node to become Ready..."
until sudo -u ubuntu kubectl get nodes | grep -q ' Ready '; do
    echo "Node not ready yet, waiting..."
    sleep 5
done
 
# Remove control-plane taint
echo "Removing control-plane taint..."
sudo -u ubuntu kubectl taint node $(hostname) node-role.kubernetes.io/control-plane:NoSchedule- || true
 
# Wait for kube-system pods to be ready
echo "Waiting for kube-system pods to be Ready..."
until sudo -u ubuntu kubectl get pods -n kube-system | grep -Ev 'STATUS|Running|Completed' | wc -l | grep -q '^0; do
    echo "Waiting for system pods..."
    sleep 10
done
 
echo "Kubernetes control-plane setup complete!"
echo "Cluster status:"
sudo -u ubuntu kubectl get nodes
sudo -u ubuntu kubectl get pods --all-namespaces
