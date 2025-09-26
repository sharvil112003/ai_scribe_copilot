# ---------- build stage ----------
# Use Google's mirror of Docker Hub to avoid Cloudflare/DNS issues
FROM mirror.gcr.io/library/node:20-bookworm-slim AS build
WORKDIR /app

# copy manifests
COPY package*.json tsconfig.json ./

# Install dev deps to compile TS (use ci if lockfile exists, else install)
RUN if [ -f package-lock.json ]; then npm ci --include=dev; else npm install --include=dev; fi

# copy source and build
COPY src ./src
RUN npm run build

# ---------- runtime stage ----------
FROM mirror.gcr.io/library/node:20-bookworm-slim AS runtime
WORKDIR /app

# Only prod deps in final image
COPY package*.json ./
RUN if [ -f package-lock.json ]; then npm ci --omit=dev; else npm install --omit=dev; fi

# bring compiled JS
COPY --from=build /app/dist ./dist

EXPOSE 3001
CMD ["node", "dist/server.js"]
