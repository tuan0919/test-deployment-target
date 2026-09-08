FROM node:22-bookworm-slim AS dependencies

WORKDIR /app
COPY app/package.json app/package-lock.json ./
RUN npm ci --omit=dev

FROM node:22-bookworm-slim

WORKDIR /app
ENV NODE_ENV=production
COPY --from=dependencies /app/node_modules ./node_modules
COPY app/src ./src
COPY app/public ./public
USER node
EXPOSE 8080
CMD ["node", "src/server.js"]
