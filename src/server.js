const app = require('./app');
const connectDb = require('./config/db');
const { port } = require('./config/env');

const start = async () => {
  await connectDb();
  app.listen(port, () => {
    // eslint-disable-next-line no-console
    console.log(`ParaGO backend running on port ${port}`);
  });
};

start().catch((error) => {
  // eslint-disable-next-line no-console
  console.error('Unable to start app:', error.message);
  process.exit(1);
});
