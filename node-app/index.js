const http = require('http');
const fs = require('fs');

function createServer() {
  // Simple in-memory user logs
  const userLogs = [];

  const server = http.createServer((req, res) => {
    const { method, url } = req;

    // Serve the React app at /app and static files under /public
    if (method === 'GET' && (url === '/app' || url === '/app/' || url.startsWith('/public/'))) {
      // Map /app -> /public/index.html
      const filePath = url === '/app' || url === '/app/' ? __dirname + '/public/index.html' : __dirname + url;
      fs.readFile(filePath, (err, data) => {
        if (err) {
          res.writeHead(404, { 'Content-Type': 'text/plain' });
          res.end('Not Found');
          return;
        }
        const contentType = filePath.endsWith('.html') ? 'text/html' : filePath.endsWith('.js') ? 'application/javascript' : 'text/plain';
        res.writeHead(200, { 'Content-Type': contentType });
        res.end(data);
      });
      return;
    }

    if (method === 'GET' && url === '/') {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end('Hello from Node.js');
      return;
    }

    if (method === 'GET' && url === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'ok' }));
      return;
    }

    // POST /log -> accept JSON { user: 'name' } and store in memory
    if (method === 'POST' && url === '/log') {
      let body = '';
      req.on('data', (chunk) => (body += chunk));
      req.on('end', () => {
        try {
          const parsed = JSON.parse(body || '{}');
          const user = parsed.user || 'anonymous';
          const entry = { user, at: new Date().toISOString() };
          userLogs.push(entry);
          res.writeHead(201, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ status: 'created', entry }));
        } catch (err) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'invalid json' }));
        }
      });
      return;
    }

    // GET /logs -> return JSON array of logs
    if (method === 'GET' && url === '/logs') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(userLogs));
      return;
    }

    if (method === 'POST' && url === '/echo') {
      let body = '';
      req.on('data', (chunk) => (body += chunk));
      req.on('end', () => {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ echo: body }));
      });
      return;
    }

    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found');
  });

  return server;
}

if (require.main === module) {
  const port = process.env.PORT || 3000;
  const server = createServer();
  server.listen(port, () => console.log(`Server listening on http://localhost:${port}`));
}

module.exports = { createServer };
