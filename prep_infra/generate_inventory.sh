#!/bin/bash

echo "Récupération de l'adresse IP de la VM..."

# On récupère la deuxième IP (celle du DHCP)
VM_IP=$(vagrant ssh -c "hostname -I | awk '{print \$2}'" 2>/dev/null | tr -d '\r')

if [ -z "$VM_IP" ]; then
  echo "Erreur: Impossible de récupérer l'IP. Voici ce que la VM répond :"
  vagrant ssh -c "hostname -I"
  exit 1
fi

echo "L'IP de la VM est : $VM_IP"
echo "Génération de l'inventaire Ansible..."

# On crée l'inventaire avec le bon chemin vers la clé SSH (dossier 'default')
cat <<EOF > inventory.ini
[k3s_nodes]
$VM_IP ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/default/virtualbox/private_key
EOF

echo "Le fichier inventory.ini a été généré avec succès !"