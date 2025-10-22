<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Simple Notes</title>
  <style>body{font-family:Arial;max-width:720px;margin:24px auto;padding:12px}</style>
</head>
<body>
  <h1>Notes</h1>
  <form method="post">
    <input name="note" placeholder="New note" required style="padding:8px;width:70%" />
    <button type="submit">Add</button>
  </form>
  <ul>
    <?php foreach ($notes as $n): ?>
      <li><?php echo htmlentities($n['text']); ?></li>
    <?php endforeach; ?>
  </ul>
</body>
</html>
