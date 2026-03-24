const http = require('http');

const app = require('./app');
const connectDb = require('./config/db');
const { port } = require('./config/env');
const { attachSocketServer } = require('./realtime/socketServer');

const start = async () => {
  await connectDb();
  const server = http.createServer(app);
  attachSocketServer(server);
  server.listen(port, () => {
    // eslint-disable-next-line no-console
    console.log(`ParaGO backend running on port ${port}`);
  });
};

start().catch((error) => {
  // eslint-disable-next-line no-console
  console.error('Unable to start app:', error.message);
  process.exit(1);
});
