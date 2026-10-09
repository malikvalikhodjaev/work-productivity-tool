FROM node:24-bookworm-slim
WORKDIR /app
COPY package.json server.mjs ./
COPY lib ./lib
COPY public ./public
COPY docs ./docs
COPY scripts/backup.mjs ./scripts/backup.mjs
RUN mkdir -p /app/data && chown -R node:node /app/data
ENV NODE_ENV=production DASHBOARD_DATA_DIR=/app/data DASHBOARD_BIND=0.0.0.0 DASHBOARD_GATEWAY_BIND=0.0.0.0
USER node
EXPOSE 8787 8789
CMD ["node","server.mjs"]
