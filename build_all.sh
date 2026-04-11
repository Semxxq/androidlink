#!/bin/bash
set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AndroidLink — сборка APK + macOS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$(dirname "$0")"

echo ""
echo "→ Установка зависимостей..."
flutter pub get

echo ""
echo "━━ 1/2  Android APK ━━━━━━━━━━━━━━━━"
flutter build apk --release --no-tree-shake-icons
APK="build/app/outputs/flutter-apk/app-release.apk"
echo "✓ APK готов: $APK"
echo "  Размер: $(du -sh $APK | cut -f1)"

echo ""
echo "━━ 2/2  macOS .app ━━━━━━━━━━━━━━━━━"
flutter build macos --release
APP="build/macos/Build/Products/Release/androidlink.app"

# Создаём DMG
echo "→ Создаём AndroidLink.dmg..."
if command -v create-dmg &> /dev/null; then
  create-dmg \
    --volname "AndroidLink" \
    --window-size 540 380 \
    --icon-size 128 \
    --icon "androidlink.app" 140 190 \
    --app-drop-link 400 190 \
    --background "/System/Library/Desktop Pictures/Solid Colors/Black.png" \
    "build/AndroidLink.dmg" \
    "$APP"
  echo "✓ DMG готов: build/AndroidLink.dmg"
else
  # Простой вариант — zip .app
  cd build/macos/Build/Products/Release
  zip -r ../../../../AndroidLink-mac.zip androidlink.app
  cd - > /dev/null
  echo "✓ ZIP готов: build/AndroidLink-mac.zip"
  echo "  (для DMG установи: brew install create-dmg)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Готово!"
echo ""
echo "  Android: $APK"
echo "  → Скинь в Telegram себе и установи"
echo ""
if [ -f "build/AndroidLink.dmg" ]; then
  echo "  macOS:   build/AndroidLink.dmg"
else
  echo "  macOS:   build/AndroidLink-mac.zip"
fi
echo "  → Разархивируй, перетащи в /Applications"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
