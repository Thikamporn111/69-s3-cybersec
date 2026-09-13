module.exports = ({ env }) => [
  'strapi::logger',
  'strapi::errors',
  {
    name: 'strapi::security',
    config: {
      // HSTS is scoped to the host name and ignores the port, so sending it
      // for "localhost" would force HTTPS on every other localhost service on
      // this machine. Enable it once this stack has a real hostname.
      hsts: false,
      // Helmet defaults apply to the admin panel and the API. The `sandbox`
      // policy for uploaded files is set at the proxy instead, in
      // security/nginx.conf under `location ^~ /uploads/`, because that is the
      // only path by which an uploaded file reaches a browser.
      contentSecurityPolicy: {
        useDefaults: true,
        directives: {
          upgradeInsecureRequests: null,
        },
      },
    },
  },
  {
    name: 'strapi::cors',
    config: {
      origin: env.array('CORS_ORIGINS', [
        'http://localhost:9093',
        'http://127.0.0.1:9093',
      ]),
      credentials: true,
      methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'],
      headers: ['Content-Type', 'Authorization', 'Origin', 'Accept', 'X-Requested-With'],
      keepHeaderOnError: true,
    },
  },
  {
    name: 'strapi::query',
    config: {
      arrayLimit: 50,
      depth: 5,
    },
  },
  {
    name: 'strapi::body',
    config: {
      jsonLimit: '256kb',
      formLimit: '256kb',
      textLimit: '64kb',
      formidable: {
        maxFileSize: 5 * 1024 * 1024,
        maxFiles: 5,
        keepExtensions: false,
      },
    },
  },
  'strapi::session',
  {
    name: 'strapi::favicon',
    config: {
      path: './public/favicon.svg',
      maxAge: 86400000,
    },
  },
  {
    name: 'strapi::public',
    config: {
      maxAge: 60000,
    },
  },
];
