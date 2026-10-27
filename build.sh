#!/bin/bash
# Construit Select2Admin.app (universel Apple Silicon + Intel) dans ./build
# Prérequis : outils en ligne de commande Xcode  →  xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Select2Admin.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ Compilation…"
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13.0" -o "build/Select2Admin-$arch" Sources/main.swift
done
lipo -create -output "$APP/Contents/MacOS/Select2Admin" build/Select2Admin-arm64 build/Select2Admin-x86_64
rm build/Select2Admin-arm64 build/Select2Admin-x86_64

cp Resources/Info.plist "$APP/Contents/"
cp config.ini "$APP/Contents/Resources/"

if [ -f Resources/AppIcon.png ]; then
  echo "→ Icône…"
  ICONSET="build/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

echo "→ Signature ad hoc…"
codesign --force --sign - "$APP"

(cd build && ditto -c -k --keepParent Select2Admin.app Select2Admin-macOS.zip)
echo "✓ $APP"
echo "✓ build/Select2Admin-macOS.zip"
