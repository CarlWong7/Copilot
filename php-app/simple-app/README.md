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
