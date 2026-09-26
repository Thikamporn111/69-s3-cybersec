'use strict';

module.exports = {
  routes: [
    {
      method: 'GET',
      path: '/teachers',
      handler: 'teacher.find',
      config: {
        policies: [],
        middlewares: [],
      },
    },
    {
      method: 'GET',
      path: '/teachers/:id',
      handler: 'teacher.findOne',
      config: {
        policies: [],
        middlewares: [],
      },
    },
    {
      method: 'POST',
      path: '/teachers',
      handler: 'teacher.create',
      config: {
        policies: [],
        middlewares: [],
      },
    },
    {
      method: 'PUT',
      path: '/teachers/:id',
      handler: 'teacher.update',
      config: {
        policies: [],
        middlewares: [],
      },
    },
  ],
};