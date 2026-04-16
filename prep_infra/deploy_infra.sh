#!/bin/bash

# 1. Lancement de la VM via Vagrant
echo "--- Lancement de la VM ---"
vagrant up

# 2. Récupération de l'IP (on utilise la méthode automatique maintenant que c'est stable)
echo "--- Récupération de l'IP ---"
VM_IP=$(vagrant ssh -c "hostname -I | awk '{print \$2}'" 2>/dev/null | tr -d '\r')

# 3. Installation de k3s à distance via SSH (sans avoir besoin d'Ansible sur ton PC !)
# C'est l'astuce ultime pour la compatibilité : on utilise le SSH natif de Vagrant.
echo "--- Installation de k3s sur la VM ($VM_IP) ---"
vagrant ssh -c "curl -sfL https://get.k3s.io | sh -"

# 4. Génération de l'inventaire pour les parties suivantes
echo "--- Génération de l'inventaire ---"
cat <<EOF > inventory.ini
[k3s_nodes]
$VM_IP ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/default/virtualbox/private_key
EOF

echo "--- Infrastructure prête ! ---"