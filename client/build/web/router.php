<?php
// SPA static router: serve real files, fall back to index.html for app routes.
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$file = __DIR__ . $path;
if ($path !== '/' && file_exists($file) && !is_dir($file)) {
    return false; // let PHP's built-in server serve the static asset
}
readfile(__DIR__ . '/index.html');
