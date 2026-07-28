const http = require('http');

const app = require('./app');
const connectDb = require('./config/db');
const { port, corsAllowedOrigins } = require('./config/env');
const { attachSocketServer } = require('./realtime/socketServer');
const { checkAndReassignPassedRequests } = require('./services/pickupReassignment.service');
const {
  reconcileAnnouncementStatuses,
} = require('./services/announcement.service');

const start = async () => {
  await connectDb();
  const server = http.createServer(app);
  attachSocketServer(server, { corsOrigins: corsAllowedOrigins });

  // Allow the process to exit cleanly even while the periodic checker is registered.
  const reassignmentInterval = setInterval(() => {
    checkAndReassignPassedRequests().catch((error) => {
      console.error('[Background Job] Error in reassignment check:', error);
    });
  }, 15000);
  reassignmentInterval.unref?.();

  const announcementInterval = setInterval(() => {
    reconcileAnnouncementStatuses().catch((error) => {
      console.error('[Background Job] Error reconciling announcements:', error);
    });
  }, 30000);
  announcementInterval.unref?.();
  await reconcileAnnouncementStatuses();

  server.listen(port, () => {
    // eslint-disable-next-line no-console
    console.log(`ParaGO backend running on port ${port}`);
    console.log('Background job: Pickup reassignment checker started (15s interval)');
    console.log('Background job: Announcement checker started (30s interval)');
  });
};

start().catch((error) => {
  // eslint-disable-next-line no-console
  console.error('Unable to start app:', error.message);
  process.exit(1);
});
