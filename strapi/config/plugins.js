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
        // httpOnly=true would move the refresh token into an HttpOnly cookie, but in
        // production that cookie is also flagged Secure and Strapi refuses to set
        // Secure cookies over plain HTTP. This sandbox is HTTP-only (nginx on
        // 127.0.0.1), so it stays false: the token is returned in the JSON body.
        // No client in this repo reads refreshToken from the body for anything
        // security-relevant beyond this sandbox. Flip to true only once the proxy
        // terminates TLS.
        httpOnly: env.bool('SESSION_REFRESH_HTTPONLY', false),
      },
      jwt: {
        // Ignored while jwtManagement is 'refresh'. Kept short so that
        // switching back to the plain plugin JWT does not silently restore a
        // one-hour token that nothing can revoke.
        expiresIn: env('JWT_EXPIRES_IN', '10m'),
      },
      ratelimit: {
        enabled: true,
        interval: env.int('AUTH_RATE_LIMIT_INTERVAL_MS', 60000),
        // Second line of defence behind the Nginx auth zone, keyed per path
        // and per IP. Keep it at or below the proxy rate so bypassing one
        // limiter still runs into the other.
        max: env.int('AUTH_RATE_LIMIT_MAX', 10),
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
