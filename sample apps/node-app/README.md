# Minimal Node.js App

This is a minimal Node.js HTTP app with three endpoints:

- GET / -> text greeting
- GET /health -> JSON health status
- POST /echo -> echoes request body as JSON

Run the server:

```powershell
npm install
npm start
```

Run tests:

```powershell
npm test
```

Docker
------

Build the image and run the container locally:

```powershell
cd C:\Users\carlk\OneDrive\Documents\GitHub\Copilot\node-app
docker build -t minimal-node-app .
docker run -p 3000:3000 minimal-node-app
```

Or use docker-compose:

```powershell
docker compose up --build
```

