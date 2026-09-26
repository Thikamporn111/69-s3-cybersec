'use strict';

module.exports = {
  routes: [
    {
      method: 'GET',
      path: '/subjects',
      handler: 'subject.find',
      config: {
        policies: [],
        middlewares: [],
      },
    },
    {
      method: 'GET',
      path: '/subjects/:id',
      handler: 'subject.findOne',
      config: {
        policies: [],
        middlewares: [],
      },
    },
    {
      method: 'POST',
      path: '/subjects',
      handler: 'subject.create',
      config: {
        policies: [],
        middlewares: [],
      },
    },
    {
      method: 'PUT',
      path: '/subjects/:id',
      handler: 'subject.update',
      config: {
        policies: [],
        middlewares: [],
      },
    },
  ],
};