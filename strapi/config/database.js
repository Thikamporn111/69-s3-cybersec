module.exports = ({ env }) => ({
  connection: {
    client: env('DATABASE_CLIENT', 'postgres'),
    connection: {
      host: env('DATABASE_HOST', 'db'),
      port: env.int('DATABASE_PORT', 5432),
      database: env('DATABASE_NAME'),
      user: env('DATABASE_USERNAME'),
      password: env('DATABASE_PASSWORD'),
      ssl: env.bool('DATABASE_SSL', false),
      connectionTimeoutMillis: 10000,
    },
    pool: {
      min: 0,
      max: 10,
      acquireTimeoutMillis: 30000,
      idleTimeoutMillis: 30000,
    },
    debug: false,
  },
});
