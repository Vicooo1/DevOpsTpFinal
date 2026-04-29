#!/bin/bash
set -e

echo "--- Déploiement sur Kubernetes (k3s) ---"

# On remonte d'un dossier et on va dans prep_infra
cd ../prep_infra || exit

echo "1. Déploiement de la base de données MySQL..."
vagrant ssh k3s -c "cat > /tmp/mysql.yaml" < ../k8s/mysql.yaml
vagrant ssh k3s -c "sudo /usr/local/bin/k3s kubectl apply -f /tmp/mysql.yaml"

echo "2. Déploiement de l'API Lacets..."
vagrant ssh k3s -c "cat > /tmp/api.yaml" < ../k8s/api.yaml
vagrant ssh k3s -c "sudo /usr/local/bin/k3s kubectl apply -f /tmp/api.yaml"

echo "3. Vérification des ressources déployées..."
vagrant ssh k3s -c "sudo /usr/local/bin/k3s kubectl get all"

echo "--- Déploiement k8s terminé avec succès ! ---"