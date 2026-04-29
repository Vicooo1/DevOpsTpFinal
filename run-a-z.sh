#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREP_DIR="$ROOT_DIR/prep_infra"
APP_DIR="$ROOT_DIR/app"
K8S_DIR="$ROOT_DIR/k8s"

DOCKER_IMAGE="${DOCKER_IMAGE:-vicopetit/api-lacets:latest}"
DB_NAME="${DB_NAME:-lacets_db}"
DB_USER="${DB_USER:-api_user}"
DB_PASSWORD="${DB_PASSWORD:-api_password}"

step() {
  echo
  echo "=== $1 ==="
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Commande manquante: $1"
    exit 1
  fi
}

step "0) Verification des prerequis"
require_cmd vagrant
require_cmd docker

step "1) Preparation infrastructure (k3s + monitoring + observabilite)"
cd "$PREP_DIR"
chmod +x deploy_infra.sh generate_inventory.sh
./deploy_infra.sh
./generate_inventory.sh

step "2) Build image API"
cd "$APP_DIR"
docker build -t "$DOCKER_IMAGE" .

step "3) Push image Docker Hub"
docker push "$DOCKER_IMAGE"

step "4) Deploiement Kubernetes"
cd "$K8S_DIR"
chmod +x deploy_k8s.sh
./deploy_k8s.sh

step "5) Mise a jour image API et attente des pods"
cd "$PREP_DIR"
vagrant ssh k3s -c "sudo /usr/local/bin/k3s kubectl set image deployment/api-lacets api-lacets=$DOCKER_IMAGE"
vagrant ssh k3s -c "sudo /usr/local/bin/k3s kubectl rollout status deployment/mysql --timeout=240s"
vagrant ssh k3s -c "sudo /usr/local/bin/k3s kubectl rollout status deployment/api-lacets --timeout=240s"

step "6) Initialisation schema SQL"
vagrant ssh k3s -c "sudo /usr/local/bin/k3s kubectl exec deploy/mysql -- mysql -u$DB_USER -p$DB_PASSWORD $DB_NAME -e \"CREATE TABLE IF NOT EXISTS users (id VARCHAR(255) PRIMARY KEY, first_name VARCHAR(100) NOT NULL, last_name VARCHAR(100) NOT NULL, age INT NOT NULL);\""

step "7) Verification finale"
vagrant ssh k3s -c "sudo /usr/local/bin/k3s kubectl get pods,svc,hpa"

K3S_IP="$(vagrant ssh k3s -c "hostname -I | awk '{print \$2}'" 2>/dev/null | tr -d '\r')"
MONITORING_IP="$(vagrant ssh monitoring -c "hostname -I | awk '{print \$2}'" 2>/dev/null | tr -d '\r')"

echo
echo "Deploiement termine."
echo "K3s VM IP:        $K3S_IP"
echo "Monitoring VM IP: $MONITORING_IP"
echo "Prometheus:       http://$MONITORING_IP:9090"
echo "Grafana:          http://$MONITORING_IP:3001 (admin/admin au premier login)"
echo
echo "Pour tester l'API:"
echo "  cd $PREP_DIR"
echo "  vagrant ssh k3s -c 'sudo /usr/local/bin/k3s kubectl port-forward svc/api-lacets 3000:80'"
echo "  curl http://localhost:3000/api"
