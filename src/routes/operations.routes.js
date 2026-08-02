const express = require('express');

const authenticate = require('../middlewares/authenticate');
const authorize = require('../middlewares/authorize');
const asyncHandler = require('../utils/asyncHandler');
const { ADMIN } = require('../constants/roles');
const { ok } = require('../utils/response');
const {
  getQueueHealth,
  listFailedJobs,
} = require('../services/asyncJobQueue.service');

const router = express.Router();

router.get(
  '/worker',
  authenticate,
  authorize(ADMIN),
  asyncHandler(async (_req, res) => {
    const queues = await getQueueHealth();
    const failedJobs = await listFailedJobs(50);
    return ok(
      res,
      {
        queues,
        failedJobs,
      },
      'Worker operations status'
    );
  })
);

module.exports = router;
