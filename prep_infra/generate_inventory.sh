#!/bin/bash
set -euo pipefail

echo "Récupération de l'adresse IP de la VM..."

K3S_IP=$(vagrant ssh k3s -c "hostname -I | awk '{print \$2}'" 2>/dev/null | tr -d '\r')
MONITORING_IP=$(vagrant ssh monitoring -c "hostname -I | awk '{print \$2}'" 2>/dev/null | tr -d '\r')

if [ -z "$K3S_IP" ] || [ -z "$MONITORING_IP" ]; then
  echo "Erreur: Impossible de récupérer l'IP. Voici ce que la VM répond :"
  vagrant ssh k3s -c "hostname -I" || true
  vagrant ssh monitoring -c "hostname -I" || true
  exit 1
fi

echo "IP k3s: $K3S_IP"
echo "IP monitoring: $MONITORING_IP"
echo "Génération de l'inventaire Ansible..."

cat <<EOF > inventory.ini
[k3s_nodes]
$K3S_IP ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/k3s/virtualbox/private_key

[monitoring_nodes]
$MONITORING_IP ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/monitoring/virtualbox/private_key
EOF

echo "Le fichier inventory.ini a été généré avec succès !"