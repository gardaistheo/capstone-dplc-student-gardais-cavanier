# Stage 1: Build
FROM node:20-alpine AS builder

WORKDIR /app

# Copier les fichiers de dépendances en premier pour optimiser le cache
COPY package*.json ./

# Installer les dépendances avec npm ci pour la reproductibilité
RUN npm ci --only=production

# Stage 2: Runtime
FROM node:20-alpine

WORKDIR /app

# Créer un utilisateur non-root pour la sécurité
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Copier les dépendances depuis le stage builder
COPY --from=builder /app/node_modules ./node_modules

# Copier le code applicatif
COPY --chown=nodejs:nodejs . .

# Utiliser l'utilisateur non-root
USER nodejs

EXPOSE 3000

CMD ["node", "main.js"]
