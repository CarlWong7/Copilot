<?php
namespace App;

class App {
    public function render(string $tpl, array $vars = []) {
        extract($vars, EXTR_SKIP);
        $file = __DIR__ . '/../templates/' . $tpl . '.php';
        if (!file_exists($file)) {
            http_response_code(500);
            echo "Template not found: " . htmlentities($tpl);
            return;
        }
        include $file;
    }
}
