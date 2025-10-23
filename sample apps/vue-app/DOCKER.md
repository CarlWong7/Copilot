# Dockerizing this Vite + Vue app

This repository contains a multi-stage Dockerfile that builds the app with Node and serves the static output with Nginx.

Build image

```powershell
docker build -t copilot-vue-app:latest .
```

Run container (maps container port 80 to host 5173)

```powershell
docker run --rm -p 5173:80 --name copilot-vue-app copilot-vue-app:latest
```

Open http://localhost:5173 in your browser.

Notes
- The Dockerfile does a full production build (npm run build) and serves `dist` via Nginx.
- For local development with HMR, continue using `npm run dev` (Vite) instead of the containerized build.
