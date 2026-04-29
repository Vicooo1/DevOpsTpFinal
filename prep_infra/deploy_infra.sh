#!/bin/bash
set -euo pipefail

echo "--- Lancement des VM k3s + monitoring ---"
vagrant up k3s
vagrant up monitoring

echo "--- Récupération des IP ---"
K3S_IP=$(vagrant ssh k3s -c "hostname -I | awk '{print \$2}'" 2>/dev/null | tr -d '\r')
MONITORING_IP=$(vagrant ssh monitoring -c "hostname -I | awk '{print \$2}'" 2>/dev/null | tr -d '\r')

echo "--- Installation des prerequis (curl + docker) ---"
vagrant ssh k3s -c "command -v curl >/dev/null 2>&1 || (sudo apt-get update -y && sudo apt-get install -y curl)"
vagrant ssh monitoring -c "command -v curl >/dev/null 2>&1 || (sudo apt-get update -y && sudo apt-get install -y curl)"
vagrant ssh monitoring -c "command -v docker >/dev/null 2>&1 || (sudo apt-get update -y && sudo apt-get install -y docker.io)"
vagrant ssh monitoring -c "sudo usermod -aG docker vagrant"

echo "--- Installation de k3s sur la VM k3s ($K3S_IP) ---"
vagrant ssh k3s -c "command -v k3s >/dev/null 2>&1 || curl -sfL https://get.k3s.io | sh -"

echo "--- Installation de node_exporter sur k3s et monitoring ---"
vagrant ssh k3s -c "command -v node_exporter >/dev/null 2>&1 || (sudo useradd --no-create-home --shell /usr/sbin/nologin node_exporter || true; curl -L -o /tmp/node_exporter.tar.gz https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz; tar -xzf /tmp/node_exporter.tar.gz -C /tmp; sudo mv /tmp/node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/node_exporter; sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter)"
vagrant ssh monitoring -c "command -v node_exporter >/dev/null 2>&1 || (sudo useradd --no-create-home --shell /usr/sbin/nologin node_exporter || true; curl -L -o /tmp/node_exporter.tar.gz https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz; tar -xzf /tmp/node_exporter.tar.gz -C /tmp; sudo mv /tmp/node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/node_exporter; sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter)"

vagrant ssh k3s -c "sudo bash -c 'cat > /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Node Exporter
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF'"
vagrant ssh monitoring -c "sudo bash -c 'cat > /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Node Exporter
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF'"

vagrant ssh k3s -c "sudo systemctl daemon-reload && sudo systemctl enable --now node_exporter"
vagrant ssh monitoring -c "sudo systemctl daemon-reload && sudo systemctl enable --now node_exporter"

echo "--- Installation de Prometheus + Grafana sur monitoring ---"
vagrant ssh monitoring -c "sudo mkdir -p /opt/monitoring/prometheus"
vagrant ssh monitoring -c "sudo bash -c 'cat > /opt/monitoring/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: node_exporter_k3s
    static_configs:
      - targets: [\"$K3S_IP:9100\"]
  - job_name: node_exporter_monitoring
    static_configs:
      - targets: [\"$MONITORING_IP:9100\"]
EOF'"
vagrant ssh monitoring -c "sudo docker rm -f prometheus grafana >/dev/null 2>&1 || true"
vagrant ssh monitoring -c "sudo docker run -d --name prometheus --restart unless-stopped -p 9090:9090 -v /opt/monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml prom/prometheus:latest"
vagrant ssh monitoring -c "sudo docker run -d --name grafana --restart unless-stopped -p 3001:3000 grafana/grafana:latest"

echo "--- Génération de l'inventaire ---"
cat <<EOF > inventory.ini
[k3s_nodes]
$K3S_IP ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/k3s/virtualbox/private_key

[monitoring_nodes]
$MONITORING_IP ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/monitoring/virtualbox/private_key
EOF

echo "--- Infrastructure prête ! ---"
echo "Prometheus: http://$MONITORING_IP:9090"
echo "Grafana:    http://$MONITORING_IP:3001 (admin/admin au premier login)"