# Combined workspace

This workspace contains four small apps (Node, PHP, React, Vue). This root-level `docker-compose.yml` builds and runs all four together on non-conflicting ports.

Services and ports:
- node-app: http://localhost:3000 (container exposes 3000)
- react-app: http://localhost:3001 (served by nginx on container port 80)
- vue-app: http://localhost:3002 (served by nginx on container port 80)
- php-app: http://localhost:3003 (Apache on container port 80)

Quick start (PowerShell):

```powershell
# Build and start all services in foreground
docker-compose up --build

# Or start in background
docker-compose up -d --build

# Stop and remove
docker-compose down
```
