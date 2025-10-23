const http = require('http');
const { createServer } = require('../index');

function request(options, body) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => resolve({ res, data }));
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

async function runTests() {
  const server = createServer();
  await new Promise((r) => server.listen(0, r));
  const port = server.address().port;
  let passed = 0;
  let failed = 0;

  try {
    // GET /
    const { res: r1, data: d1 } = await request({ hostname: '127.0.0.1', port, path: '/', method: 'GET' });
    if (r1.statusCode === 200 && d1 === 'Hello from Node.js') passed++; else { failed++; console.error('GET / failed', r1.statusCode, d1); }

    // GET /health
    const { res: r2, data: d2 } = await request({ hostname: '127.0.0.1', port, path: '/health', method: 'GET' });
    if (r2.statusCode === 200 && JSON.parse(d2).status === 'ok') passed++; else { failed++; console.error('GET /health failed', r2.statusCode, d2); }

    // POST /echo
    const payload = 'hello';
    const { res: r3, data: d3 } = await request({ hostname: '127.0.0.1', port, path: '/echo', method: 'POST', headers: { 'Content-Type': 'text/plain' } }, payload);
    if (r3.statusCode === 200 && JSON.parse(d3).echo === payload) passed++; else { failed++; console.error('POST /echo failed', r3.statusCode, d3); }

    console.log(`Passed: ${passed}, Failed: ${failed}`);
    process.exitCode = failed === 0 ? 0 : 1;
  } catch (err) {
    console.error('Test run error', err);
    process.exitCode = 2;
  } finally {
    server.close();
  }
}

runTests();
