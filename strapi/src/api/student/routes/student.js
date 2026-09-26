'use strict';

module.exports = {
  routes: [
    {
      method: 'GET',
      path: '/students',
      handler: 'student.find',
      config: {
        policies: [],
        middlewares: [],
      },
    },
    {
      method: 'GET',
      path: '/students/:id',
      handler: 'student.findOne',
      config: {
        policies: [],
        middlewares: [],
      },
    },
    {
      method: 'POST',
      path: '/students',
      handler: 'student.create',
      config: {
        policies: [],
        middlewares: [],
      },
    },
    {
      method: 'PUT',
      path: '/students/:id',
      handler: 'student.update',
      config: {
        policies: [],
        middlewares: [],
      },
    },
  ],
};