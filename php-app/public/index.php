<?php
// Simple user login app (single-file router)
require_once __DIR__ . '/../src/App.php';

use App\App;

session_start();

$app = new App();
$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

$dataDir = __DIR__ . '/../data';
if (!is_dir($dataDir)) mkdir($dataDir, 0755, true);

$usersFile = $dataDir . '/users.json';
if (!file_exists($usersFile)) {
    // seed a demo user: user@example.com / password
    file_put_contents($usersFile, json_encode([['email'=>'user@example.com','password'=>'password']], JSON_PRETTY_PRINT));
}

// Routes:
// GET /login -> show login
// POST /login -> attempt login
// GET /dashboard -> protected page
// GET /logout -> logout

if ($uri === '/' || $uri === '/login') {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $body = $_POST;
        $email = trim($body['email'] ?? '');
        $password = trim($body['password'] ?? '');
        $users = json_decode(file_get_contents($usersFile), true) ?? [];
        $found = null;
        foreach ($users as $u) { if ($u['email'] === $email && $u['password'] === $password) { $found = $u; break; } }
        if ($found) {
            $_SESSION['user'] = ['email' => $found['email']];
            header('Location: /dashboard'); exit;
        } else {
            $app->render('login', ['error' => 'Invalid credentials', 'email' => $email]); exit;
        }
    }
    $app->render('login', ['error' => '', 'email' => '']);
    exit;
}

if ($uri === '/dashboard') {
    if (empty($_SESSION['user'])) { header('Location: /login'); exit; }
    $app->render('dashboard', ['user' => $_SESSION['user']]);
    exit;
}

if ($uri === '/logout') {
    session_unset(); session_destroy(); header('Location: /login'); exit;
}

http_response_code(404);
$app->render('404');
