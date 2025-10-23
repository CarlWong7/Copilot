<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Dashboard</title>
  <style>body{font-family:Arial;max-width:720px;margin:24px auto;padding:12px}</style>
</head>
<body>
  <h1>Dashboard</h1>
  <p>Welcome, <?php echo htmlentities($user['email']); ?>!</p>
  <p><a href="/logout">Sign out</a></p>
</body>
</html>
