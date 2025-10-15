# Copilot Vue App

Minimal Vue 3 + Vite app scaffolded by an assistant.

How to run (Windows PowerShell):

```powershell
cd c:\Users\carlk\OneDrive\Documents\GitHub\Copilot\app
npm install
npm run dev
```

Then open the URL printed by Vite (usually http://localhost:5173).

Login page
-----------

This scaffold now shows a simple client-side `Login` page at the root of the app.
It contains an email and password form and performs only local validation and a simulated "success" message — there is no backend or authentication provider wired up.

To extend:
- Replace the simulated submit in `src/pages/Login.vue` with a call to your auth API.
- Add routing if you want multiple pages (install `vue-router`).

Signup
------

The `Login` page includes a Sign up tab where users can create an account using name, email, password, and password confirmation. This is client-side only and displays a simulated success message. To test signing up, switch to the Sign up tab and submit the form.


