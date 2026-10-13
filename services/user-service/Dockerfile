# ---- builder ----
FROM node:24-alpine AS builder
WORKDIR /build
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund

# ---- runtime ----
FROM node:24-alpine
# Runtime only needs `node`. npm/corepack ship in the base image with their own
# bundled deps (tar, glob, cross-spawn, ...) that carry HIGH CVEs and fail the
# CI Trivy gate, so drop them; apk upgrade picks up OS fixes (e.g. openssl).
RUN apk upgrade --no-cache  && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack            /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack  && addgroup -S app && adduser -S -G app -u 10001 app
WORKDIR /app
COPY --from=builder /build/node_modules ./node_modules
COPY --chown=app:app package.json ./
COPY --chown=app:app src/ ./src/
USER 10001
EXPOSE 8081
HEALTHCHECK --interval=30s --timeout=3s CMD node -e "require('http').get('http://localhost:8081/healthz',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"
CMD ["node", "src/index.js"]
