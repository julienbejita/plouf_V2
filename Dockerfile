# --- build ---
FROM node:20-alpine AS build
WORKDIR /app

# Copie package.json et lockfile (si tu en as un)
COPY package*.json ./

# Installe les dépendances + Tailwind/PostCSS
RUN npm install --no-audit --no-fund && \
    npm install -D tailwindcss postcss autoprefixer && \
    npx tailwindcss init -p

# Copie tout le reste du projet
COPY . .

# Build
RUN npm run build

# --- run ---
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost/ || exit 1
