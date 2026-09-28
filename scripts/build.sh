#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Keep the chosen identity local to this checkout; never silently fall back to
# ad-hoc signing, which invalidates privacy grants when the binary changes.
SIGNING_IDENTITY="${IRONSEARCH_SIGNING_IDENTITY:-$(git config --local --get ironsearch.signingIdentity || true)}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo 'No signing identity configured. Run security find-identity -v -p codesigning,' >&2
    echo 'then git config --local ironsearch.signingIdentity <certificate-SHA1>.' >&2
    echo 'For an explicitly ad-hoc build only: IRONSEARCH_SIGNING_IDENTITY=- bash scripts/build.sh' >&2
    exit 1
fi

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
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --identifier ai.toyo.ironsearch "$APP"
/usr/bin/codesign --verify --strict "$APP"
echo "Built: $PWD/$APP"
