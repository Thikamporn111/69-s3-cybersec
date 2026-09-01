module.exports = ({ env }) => ({
  'users-permissions': {
    config: {
      jwtSecret: env('JWT_SECRET'),
      jwtManagement: 'legacy-support',
      jwt: {
        expiresIn: env('JWT_EXPIRES_IN', '1h'),
      },
      ratelimit: {
        enabled: true,
        interval: env.int('AUTH_RATE_LIMIT_INTERVAL_MS', 60000),
        max: env.int('AUTH_RATE_LIMIT_MAX', 5),
      },
      register: {
        allowedFields: [],
      },
    },
  },
  email: {
    config: {
      provider: 'nodemailer',
      providerOptions: {
        // Lab-only sink transport: Forgot Password still creates a token, but
        // no email server or mailbox is exposed. Inspect the database only in
        // this local lab; configure a real provider before deployment.
        jsonTransport: true,
        disableFileAccess: true,
        disableUrlAccess: true,
      },
      settings: {
        defaultFrom: 'no-reply@cybersec.local',
        defaultReplyTo: 'no-reply@cybersec.local',
      },
    },
  },
});
