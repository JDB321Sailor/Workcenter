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

# Alpine packages, installed once, with retries.
#
# `apk upgrade` and `apk add` each fetch the package index, so the original
# two-command form resolved and downloaded twice — and a single DNS blip on the
# second fetch failed the whole build with a misleading "unable to select
# packages: tzdata (no such package)". The package was always there; the index it
# is listed in was not. One transaction and three attempts keep a transient
# resolver or mirror failure from failing an otherwise valid image, which is what
# a build behind a flaky network needs. A genuine failure still fails: the last
# attempt's status is the one that counts.
RUN set -eux; \
    attempt=1; \
    while true; do \
      if apk upgrade --no-cache && apk add --no-cache tzdata tini; then break; fi; \
      if [ "${attempt}" -ge 3 ]; then \
        echo "apk failed after ${attempt} attempts; the index fetch is not recovering" >&2; \
        exit 1; \
      fi; \
      echo "apk attempt ${attempt} failed (transient DNS or mirror?); retrying in 5s" >&2; \
      attempt=$((attempt + 1)); \
      sleep 5; \
    done; \
    rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx

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
