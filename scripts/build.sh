#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/paths.sh"
BUNDLE_PREFIX="${CAPTURESHIELD_BUNDLE_PREFIX:-dev.naivee2000.captureshield}"
if [[ ! "$BUNDLE_PREFIX" =~ ^[A-Za-z0-9.-]+$ ]]; then echo 'Invalid bundle identifier prefix.' >&2; exit 2; fi
source "$ROOT/scripts/support.sh"
require_stopped_build_apps
capture_build_prerequisites
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
  if [[ "$NAME" == CaptureShieldLab ]]; then SUFFIX=lab; AGENT=true; else SUFFIX=probe; AGENT=false; fi
  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_PREFIX.$SUFFIX</string>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.6.2</string>
<key>CFBundleVersion</key><string>11</string>
<key>CaptureShieldBuildCommit</key><string>$BUILD_COMMIT</string>
<key>CFBundleIconFile</key><string>CaptureShield</string>
<key>LSMinimumSystemVersion</key><string>$MINIMUM_MACOS</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSUIElement</key><$AGENT/>
<key>NSSpeechRecognitionUsageDescription</key><string>Transcribe selected application audio on this Mac into an editable draft. Audio is not sent to a cloud speech service.</string>
<key>NSScreenCaptureUsageDescription</key><string>Capture screens for local review or selected application audio for on-device transcription. Images are handed to ChatGPT only after you confirm Add to Chat.</string>
</dict></plist>
PLIST
  codesign --force --sign - --identifier "$BUNDLE_PREFIX.$SUFFIX" "$APP"
  codesign --verify --strict "$APP"
done
xcrun swift "$ROOT/scripts/register-app.swift" "$APP_ROOT/CaptureShieldLab.app" "$APP_ROOT/CaptureProbe.app"
echo "Built both applications in $APP_ROOT"
