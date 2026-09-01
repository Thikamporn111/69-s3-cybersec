module.exports = ({ env }) => ({
  host: env('HOST', '0.0.0.0'),
  port: env.int('PORT', 1337),
  url: env('PUBLIC_URL', 'http://localhost:9093'),
  emitErrors: false,
  app: {
    keys: env.array('APP_KEYS'),
    proxyIpHeader: 'X-Forwarded-For',
    maxIpsCount: 1,
  },
  proxy: {
    koa: true,
  },
  cron: {
    enabled: false,
  },
  transfer: {
    remote: {
      enabled: false,
    },
  },
  webhooks: {
    populateRelations: false,
  },
  openapi: {
    'content-api': { access: 'disabled' },
    admin: { access: 'disabled' },
  },
  http: {
    serverOptions: {
      requestTimeout: 30000,
      headersTimeout: 15000,
      keepAliveTimeout: 5000,
      maxHeaderSize: 16384,
    },
  },
});
