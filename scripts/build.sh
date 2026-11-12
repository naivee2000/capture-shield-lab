#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/paths.sh"
BUNDLE_PREFIX="${CAPTURESHIELD_BUNDLE_PREFIX:-dev.naivee2000.captureshield}"
if [[ ! "$BUNDLE_PREFIX" =~ ^[A-Za-z0-9.-]+$ ]]; then echo 'Invalid bundle identifier prefix.' >&2; exit 2; fi
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo 'Apple Silicon macOS is required.' >&2; exit 1
fi
if [[ "$(sw_vers -productVersion | cut -d. -f1)" -lt 26 ]]; then
  echo 'macOS 26 or newer is required. New OS versions remain unverified until retested.' >&2; exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
  echo 'Install Apple Command Line Tools first: xcode-select --install' >&2; exit 1
fi
SWIFT_VERSION="$(xcrun swift --version | sed -nE 's/.*Swift version ([0-9]+)\.([0-9]+).*/\1 \2/p' | head -1)"
read -r SWIFT_MAJOR SWIFT_MINOR <<< "$SWIFT_VERSION"
if [[ -z "${SWIFT_MAJOR:-}" || "$SWIFT_MAJOR" -lt 6 || ( "$SWIFT_MAJOR" -eq 6 && "$SWIFT_MINOR" -lt 2 ) ]]; then
  echo 'Swift 6.2 or later is required. Update Apple Command Line Tools or select a compatible Xcode.' >&2; exit 1
fi
xcrun swift build "$@"
BIN="$(xcrun swift build "$@" --show-bin-path)"
BUILD_COMMIT="$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then BUILD_COMMIT="$BUILD_COMMIT-dirty"; fi
for NAME in CaptureShieldLab CaptureProbe; do
  APP="$APP_ROOT/$NAME.app"
  mkdir -p "$APP/Contents/MacOS"
  mkdir -p "$APP/Contents/Resources"
  cp "$ROOT/Assets/CaptureShield.icns" "$APP/Contents/Resources/CaptureShield.icns"
  cp "$BIN/$NAME" "$APP/Contents/MacOS/$NAME"
  chmod +x "$APP/Contents/MacOS/$NAME"
  if [[ "$NAME" == CaptureShieldLab ]]; then SUFFIX=lab; else SUFFIX=probe; fi
  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_PREFIX.$SUFFIX</string>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.2</string>
<key>CFBundleVersion</key><string>6</string>
<key>CaptureShieldBuildCommit</key><string>$BUILD_COMMIT</string>
<key>CFBundleIconFile</key><string>CaptureShield</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSScreenCaptureUsageDescription</key><string>Capture a screen for local review or protection testing. Images are handed to ChatGPT only after you confirm Add to Chat.</string>
</dict></plist>
PLIST
  codesign --force --sign - --identifier "$BUNDLE_PREFIX.$SUFFIX" "$APP"
  codesign --verify --strict "$APP"
done
xcrun swift "$ROOT/scripts/register-app.swift" "$APP_ROOT/CaptureShieldLab.app" "$APP_ROOT/CaptureProbe.app"
echo "Built both applications in $APP_ROOT"
