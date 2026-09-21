#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Prefer the standalone tools when available; no global Xcode setting is changed.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Library/Developer/CommandLineTools ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
swift scripts/make-icon.swift
/usr/bin/iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
swift build -c release --product IronSearch
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="dist/Iron Search.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/IronSearch" "$APP/Contents/MacOS/IronSearch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/bin/codesign --force --sign - --identifier ai.toyo.ironsearch "$APP"
/usr/bin/codesign --verify --strict "$APP"
echo "Built: $PWD/$APP"
