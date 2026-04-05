const http = require('http');

const app = require('./app');
const connectDb = require('./config/db');
const { port } = require('./config/env');
const { attachSocketServer } = require('./realtime/socketServer');
const { checkAndReassignPassedRequests } = require('./services/pickupReassignment.service');

const start = async () => {
  await connectDb();
  const server = http.createServer(app);
  attachSocketServer(server);
  
  // Start background job to check for passed jeeps every 15 seconds
  setInterval(() => {
    checkAndReassignPassedRequests().catch((error) => {
      console.error('[Background Job] Error in reassignment check:', error);
    });
  }, 15000);
  
  server.listen(port, () => {
    // eslint-disable-next-line no-console
    console.log(`ParaGO backend running on port ${port}`);
    console.log('Background job: Pickup reassignment checker started (15s interval)');
  });
};

start().catch((error) => {
  // eslint-disable-next-line no-console
  console.error('Unable to start app:', error.message);
  process.exit(1);
});
