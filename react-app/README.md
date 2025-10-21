
# React App (Vite)

Minimal Vite + React starter created by an automated assistant. Includes pages for Home, Login, and Sign Up.

Local development

1. npm install
2. npm run dev

Open the address printed by the dev server (usually http://localhost:5173).

Docker

Build and run with Docker (multi-stage build, served by nginx):

1. Build the image:

	docker build -t react-app:latest .

2. Run the container:

	docker run -p 5173:80 --rm react-app:latest

Alternatively use docker-compose:

	docker-compose up --build

Then open http://localhost:5173 in your browser.

Notes

- The container serves the production `dist/` built by Vite. The Sign Up and Login pages currently store the username in localStorage (client-only).
- For real authentication or persistent storage, integrate a backend API.

