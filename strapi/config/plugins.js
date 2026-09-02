module.exports = ({ env }) => ({
  'users-permissions': {
    config: {
      jwtSecret: env('JWT_SECRET'),
      // SessionManager mode. Access tokens stay short lived and refresh tokens
      // are stored server side, so logging out or revoking a session takes
      // effect immediately. The login response still carries `jwt`, so the
      // existing REST flow keeps working; it just also returns `refreshToken`.
      jwtManagement: 'refresh',
      sessions: {
        accessTokenLifespan: env.int('SESSION_ACCESS_TOKEN_LIFESPAN', 600),
        maxRefreshTokenLifespan: env.int('SESSION_MAX_REFRESH_LIFESPAN', 7 * 24 * 60 * 60),
        idleRefreshTokenLifespan: env.int('SESSION_IDLE_REFRESH_LIFESPAN', 24 * 60 * 60),
        maxSessionLifespan: env.int('SESSION_MAX_LIFESPAN', 12 * 60 * 60),
        idleSessionLifespan: env.int('SESSION_IDLE_LIFESPAN', 60 * 60),
        httpOnly: false,
      },
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
