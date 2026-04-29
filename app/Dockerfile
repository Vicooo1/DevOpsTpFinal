# --- Étape 1 : Builder ---
FROM node:18-alpine AS builder
WORKDIR /app
# Copier uniquement les fichiers de dépendances en premier pour utiliser le cache Docker
COPY package*.json ./
# Installer les dépendances (y compris de dev si besoin de build)
RUN npm install
# Copier le reste du code source
COPY . .

# --- Étape 2 : Image finale ---
FROM node:18-alpine
WORKDIR /app
# Récupérer uniquement les modules générés depuis le builder
COPY --from=builder /app/node_modules ./node_modules
# Copier le code source de l'application
COPY . .

# Exposer le port par défaut de l'application
EXPOSE 3000

# Commande de démarrage
CMD ["npm", "start"]