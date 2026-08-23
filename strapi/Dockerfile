FROM node:20-alpine

RUN apk add --no-cache build-base gcc autoconf automake zlib-dev libpng-dev nasm bash vips-dev git

WORKDIR /opt/app
COPY package.json ./
RUN npm install
COPY . .
RUN npm run build

EXPOSE 1337
CMD ["npm", "run", "develop"]
