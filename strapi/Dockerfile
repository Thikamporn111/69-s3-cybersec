FROM node:24.20.0-alpine3.23 AS build

RUN apk add --no-cache build-base gcc autoconf automake zlib-dev libpng-dev nasm bash vips-dev git

WORKDIR /opt/app
COPY package.json package-lock.json ./
RUN npm ci --no-audit

COPY . .
ENV NODE_ENV=production
RUN npm run build && npm prune --omit=dev

FROM node:24.20.0-alpine3.23 AS runtime

RUN apk add --no-cache vips

ENV NODE_ENV=production
WORKDIR /opt/app
COPY --from=build --chown=node:node /opt/app ./

USER node
EXPOSE 1337
CMD ["npm", "run", "start"]
