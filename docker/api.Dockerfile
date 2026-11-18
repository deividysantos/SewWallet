FROM node:22-bookworm-slim AS base
RUN apt-get update \
  && apt-get install -y --no-install-recommends openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app

# Desenvolvimento: o código vem do volume montado em /app.
FROM base AS dev
ENV NODE_ENV=development
EXPOSE 3000
ENTRYPOINT ["sh", "/app/docker-entrypoint.sh"]
CMD ["npm", "run", "dev"]

# Produção (PC de casa): imagem com o código compilado.
FROM base AS prod
ENV NODE_ENV=production
COPY api/package.json api/package-lock.json ./
# --include=dev: NODE_ENV=production faria o npm pular TypeScript/@types, necessários no build.
RUN npm ci --include=dev
COPY api/ ./
RUN npx prisma generate && npm run build && npm prune --omit=dev
EXPOSE 3000
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/server.js"]
