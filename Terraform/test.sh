

###########################################
# Initialize Kubernetes
###########################################
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
until sudo -u ubuntu kubectl get pods -n kube-system | grep -Ev 'STATUS|Running|Completed' | wc -l | grep -q '^0$'; do
    echo "Waiting for system pods..."
    sleep 10
done

echo " Kubernetes control-plane setup complete!"
sudo -u ubuntu kubectl get nodes
sudo -u ubuntu kubectl get pods --all-namespaces

###########################################
# Install ArgoCD
###########################################
echo "Installing ArgoCD..."
sudo -u ubuntu kubectl create namespace argocd || true
sudo -u ubuntu kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Expose ArgoCD server via NodePort
sudo -u ubuntu kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'

###########################################
# Create ArgoCD Application for GitOps Repo
###########################################
cat <<EOF | sudo -u ubuntu kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Tracel-web-project/Travel-gitops.git
    targetRevision: main
    path: apps/dev/all-services
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

###########################################
# Install Metrics Server
###########################################
echo "Installing Metrics Server..."
sudo -u ubuntu kubectl apply -f https://raw.githubusercontent.com/vilasvarghese/docker-k8s/refs/heads/master/yaml/hpa/components.yaml

sudo -u ubuntu kubectl -n kube-system wait --for=condition=Available \
  deploy/metrics-server --timeout=300s || \
sudo -u ubuntu kubectl -n kube-system wait --for=condition=Available \
  deploy -l k8s-app=metrics-server --timeout=300s

echo " Metrics Server installation done"

###########################################
# Install Ingress Controller
###########################################
echo "Installing Ingress Controller..."
sudo -u ubuntu kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.0.0/deploy/static/provider/baremetal/deploy.yaml

sudo -u ubuntu kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

# Patch ingress controller NodePort
sudo -u ubuntu kubectl patch service -n ingress-nginx ingress-nginx-controller \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/ports/0/nodePort", "value":32000}]'

echo " Ingress Controller installation done"

###########################################
# Install Helm
###########################################
echo "Installing Helm..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
helm version
echo " Helm installation done"

###########################################
# Install Prometheus + Grafana
###########################################
echo "Adding Prometheus repo..."
sudo -u ubuntu helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
sudo -u ubuntu helm repo update

echo "Installing Prometheus + Grafana..."
sudo -u ubuntu kubectl create ns monitoring || echo "Namespace monitoring already exists"

if [ -f "./custom_kube_prometheus_stack.yml" ]; then
  sudo -u ubuntu helm install monitoring prometheus-community/kube-prometheus-stack \
    -n monitoring \
    -f ./custom_kube_prometheus_stack.yml \
    --wait --timeout 20m --atomic
else
  sudo -u ubuntu helm install monitoring prometheus-community/kube-prometheus-stack \
    -n monitoring \
    --wait --timeout 20m --atomic
fi

echo " Prometheus + Grafana installation done"

###########################################
# Print Grafana Access Info
###########################################
GRAFANA_PASS=$(kubectl get secret monitoring-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d)
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(kubectl get svc monitoring-grafana -n monitoring -o jsonpath='{.spec.ports[0].nodePort}')

echo ""
echo "==============================="
echo " Setup Complete!"
echo "Grafana URL: http://$NODE_IP:$NODE_PORT"
echo "Username: admin"
echo "Password: $GRAFANA_PASS"
echo "==============================="
