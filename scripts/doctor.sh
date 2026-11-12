#!/bin/bash
# Read-only checks: never register apps, build, reset TCC, install tools or launch UI.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/paths.sh"
source "$ROOT/scripts/support.sh"
if [[ "$#" -ne 0 ]]; then echo 'Usage: bash scripts/doctor.sh'; exit 2; fi
result=0
if capture_build_prerequisites; then tools_ready=1; else tools_ready=0; result=1; fi
for name in CaptureShieldLab CaptureProbe; do
  app="$APP_ROOT/$name.app"
  echo "$name: ${app/#$HOME/\~}"
  if [[ ! -x "$app/Contents/MacOS/$name" ]]; then
    echo '  Missing build. Run bash scripts/dev.sh with a compatible toolchain.'; result=1; continue
  fi
  if codesign --verify --strict "$app" 2>/dev/null; then echo '  Signature: valid'; else
    echo '  Signature: invalid. Quit the app, then run bash scripts/build.sh.'; result=1
  fi
  for key in CFBundleShortVersionString CFBundleVersion CaptureShieldBuildCommit LSMinimumSystemVersion; do
    value="$(/usr/libexec/PlistBuddy -c "Print $key" "$app/Contents/Info.plist" 2>/dev/null || echo missing)"
    echo "  $key: $value"
  done
  floor="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$app/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$floor" != "$MINIMUM_MACOS" ]]; then echo '  This is an older/different build. Quit it, then run bash scripts/dev.sh.'; result=1; fi
  if [[ "$tools_ready" -eq 1 ]]; then
    if ! xcrun swift "$ROOT/scripts/register-app.swift" --check-only "$app"; then
      echo '  Registration differs. Quit the app and run bash scripts/build.sh in the intended checkout.'; result=1
    fi
  fi
done
echo 'Screen Recording: check inside the app via Compatibility… (this script cannot attest another process permission).'
echo 'For a denied/stale grant, open System Settings → Privacy & Security → Screen & System Audio Recording and re-add the intended app if needed.'
echo 'No permissions, settings or app signatures were changed. No receiver-hiding verdict was produced.'
exit "$result"
