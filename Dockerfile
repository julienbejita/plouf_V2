# --- build ---
FROM node:20-alpine AS build
WORKDIR /app

# Copie package.json et lockfile (si tu en as un)
COPY package*.json ./

# Installe les dépendances
RUN npm install --no-audit --no-fund

# Copie tout le reste du projet
COPY . .

# Build
RUN npm run build

# --- run ---
FROM node:20-alpine
WORKDIR /app
RUN apk add --no-cache python3 make g++
COPY package*.json ./
RUN npm install --omit=dev --no-audit --no-fund
COPY --from=build /app/dist ./dist
COPY server.js ./
ENV NODE_ENV=production
EXPOSE 80
CMD ["node", "server.js"]
