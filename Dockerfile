FROM node:24-alpine AS build

WORKDIR /app

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile --network-timeout 600000

COPY . .
RUN yarn build

FROM node:24-alpine AS deps

WORKDIR /app

COPY package.json yarn.lock ./
RUN yarn install --production --frozen-lockfile --network-timeout 600000 \
  && yarn cache clean

FROM node:24-alpine

ARG VERSION=dev
ARG REVISION
ARG CREATED

LABEL org.opencontainers.image.title="Workcenter" \
      org.opencontainers.image.description="Files, chat and mail in one self-hosted workspace" \
      org.opencontainers.image.documentation="https://github.com/<your-org>/workcenter#readme" \
      org.opencontainers.image.source="https://github.com/<your-org>/workcenter" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"

ENV NODE_ENV=production \
    IS_DOCKER=true \
    PORT=8080 \
    HOST=0.0.0.0

WORKDIR /app

RUN apk upgrade --no-cache \
 && apk add --no-cache tzdata tini \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx

COPY --chown=node:node --from=deps  /app/node_modules ./node_modules
COPY --chown=node:node --from=build /app/dist ./dist
COPY --chown=node:node --from=build /app/public ./public
COPY --chown=node:node --from=build /app/services ./services
COPY --chown=node:node --from=build /app/src/utils/config/ConfigSchema.json ./src/utils/config/ConfigSchema.json
COPY --chown=node:node --from=build /app/server.js ./server.js
COPY --chown=node:node --from=build /app/package.json ./package.json
COPY --chown=node:node --from=build /app/user-data/conf.yml ./user-data/conf.yml

USER node

EXPOSE 8080

HEALTHCHECK --interval=5m --timeout=10s --start-period=20s --retries=3 \
  CMD node services/healthcheck.js

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "server.js"]
