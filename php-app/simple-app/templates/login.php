<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Login</title>
  <style>body{font-family:Arial;max-width:520px;margin:32px auto;padding:12px} label{display:block;margin-top:8px} .error{color:#b91c1c}</style>
</head>
<body>
  <h1>Sign in</h1>
  <?php if (!empty($error)): ?><div class="error"><?php echo htmlentities($error); ?></div><?php endif; ?>
  <form method="post" action="/login">
    <label>Email <input name="email" type="email" value="<?php echo htmlentities($email ?? ''); ?>" required></label>
    <label>Password <input name="password" type="password" required></label>
    <button type="submit">Sign in</button>
  </form>
  <p>Demo user: <strong>user@example.com</strong> / <strong>password</strong></p>
</body>
</html>
