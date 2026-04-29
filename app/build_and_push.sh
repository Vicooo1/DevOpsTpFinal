#!/bin/bash

# Définition du nom de l'image (Remplace 'ton_pseudo' par ton identifiant Docker Hub)
IMAGE_NAME="vicopetit/api-lacets:v1"

echo "--- 1. Construction de l'image localement ---"
# Le point '.' à la fin indique que le Dockerfile est dans le répertoire courant
docker build -t $IMAGE_NAME .

echo "--- 2. Connexion à Docker Hub ---"
# Cette commande demandera tes identifiants la première fois
docker login

echo "--- 3. Pousser l'image sur Docker Hub ---"
docker push $IMAGE_NAME

echo "--- Opération terminée avec succès ! ---"