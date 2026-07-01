const http = require('http');
const app = require('./src/app');

const server = http.createServer(app);
server.listen(0, async () => {
  const port = server.address().port;
  const baseUrl = 'http://127.0.0.1:' + port;
  const paths = ['/health', '/api/v1/health', '/api/v1', '/api/v1/does-not-exist'];

  for (const path of paths) {
    const response = await fetch(baseUrl + path);
    const body = await response.text();
    console.log('PATH ' + path + ' STATUS ' + response.status);
    console.log(body);
  }

  server.close();
});
