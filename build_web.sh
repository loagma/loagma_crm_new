#!/usr/bin/env bash
set -euo pipefail

FLUTTER_DIR="/opt/flutter"

echo "==> Installing Flutter SDK (stable)..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_DIR"
export PATH="$FLUTTER_DIR/bin:$PATH"

echo "==> Configuring Flutter..."
flutter config --no-analytics
flutter precache --web

echo "==> Installing dependencies..."
flutter pub get

echo "==> Building Flutter web..."
flutter build web --release

echo "==> Done. Output in build/web"
