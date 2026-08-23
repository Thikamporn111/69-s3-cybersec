module.exports = ({ env }) => ({
  'users-permissions': {
    config: { jwtSecret: env('JWT_SECRET') },
  },
  email: {
    config: {
      provider: 'nodemailer',
      providerOptions: {
        host: env('SMTP_HOST', 'mailpit'),
        port: env.int('SMTP_PORT', 1025),
        secure: false,
        ignoreTLS: true,
      },
      settings: {
        defaultFrom: env('SMTP_FROM', 'no-reply@cybersec.local'),
        defaultReplyTo: env('SMTP_FROM', 'no-reply@cybersec.local'),
      },
    },
  },
});
