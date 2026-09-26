'use strict';

// Section 3 of api.rest calls these content routes with a logged-in user's
// Bearer token, so the Authenticated role needs exactly these actions.
// `delete` is deliberately not granted, and the Public role gets nothing.
const CONTENT_TYPES = ['student', 'subject', 'teacher'];
const ACTIONS = ['create', 'find', 'findOne', 'update'];

async function grantAuthenticatedContentPermissions(strapi) {
  const role = await strapi.db
    .query('plugin::users-permissions.role')
    .findOne({ where: { type: 'authenticated' } });
  if (!role) {
    strapi.log.warn('[content] Authenticated role not found; permissions not granted.');
    return;
  }

  const wanted = CONTENT_TYPES.flatMap((name) =>
    ACTIONS.map((action) => `api::${name}.${name}.${action}`)
  );
  const existing = await strapi.db
    .query('plugin::users-permissions.permission')
    .findMany({ where: { role: role.id, action: { $in: wanted } } });
  const have = new Set(existing.map((p) => p.action));

  const missing = wanted.filter((action) => !have.has(action));
  for (const action of missing) {
    await strapi.db
      .query('plugin::users-permissions.permission')
      .create({ data: { action, role: role.id } });
  }
  if (missing.length) {
    strapi.log.info(`[content] Granted Authenticated: ${missing.join(', ')}`);
  }
}

module.exports = {
  register() {},

  async bootstrap({ strapi }) {
    await grantAuthenticatedContentPermissions(strapi);
  },
};
