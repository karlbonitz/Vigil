# Vantage community-intel collector — container image for Coolify / Docker / any VPS.
# In Coolify: New Resource -> this Git repo -> Build Pack "Dockerfile",
# Base Directory "/collector", add a persistent volume mounted at /data, set a
# domain (Coolify provisions HTTPS), and the env vars below.
FROM node:22-bookworm-slim
WORKDIR /app

# Build deps let better-sqlite3 compile if no prebuilt matches the VPS arch
# (amd64/arm64 both get a prebuilt in practice, so this is just insurance).
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 make g++ ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install deps against the image's own platform (don't copy local node_modules).
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund

COPY . .

ENV NODE_ENV=production \
    PORT=8080 \
    DB_PATH=/data/intel.db
EXPOSE 8080
VOLUME ["/data"]

# Container healthcheck hits /health.
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+ (process.env.PORT||8080) +'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server.mjs"]
