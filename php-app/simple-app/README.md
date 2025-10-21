Simple PHP Login App

Run locally:

php -S 127.0.0.1:9000 -t public

Open http://127.0.0.1:9000/login

Routes:
- GET /login      -> login form
- POST /login     -> authenticate (demo user)
- GET /dashboard  -> protected page
- GET /logout     -> sign out

Files:
- public/index.php
- src/App.php
- templates/login.php
- templates/dashboard.php
- templates/404.php

Data stored in simple-app/data/users.json (demo user: user@example.com / password)

Docker
------
Build and run with Docker Compose (requires Docker):

docker compose up --build

Then open http://127.0.0.1:9000/login

Notes:
- The container runs Apache+PHP and mounts the local `simple-app` directory for live edits.
- For production, remove the bind mount and persist data in a proper volume or DB.
