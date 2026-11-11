#!/bin/bash
# Build bundles on the local Mac filesystem. exFAT/SMB AppleDouble metadata
# can invalidate codesign resource seals even when source compilation succeeds.
APP_ROOT="${CAPTURESHIELD_APP_ROOT:-$HOME/Library/Caches/CaptureShieldLab/Apps}"

require_stopped_build_apps() {
  local app_name
  for app_name in CaptureShieldLab CaptureProbe; do
    # Check the actual bundle being replaced, not unrelated QA/other-checkout apps
    # that happen to have the same executable name.
    if /usr/sbin/lsof -t "$APP_ROOT/$app_name.app/Contents/MacOS/$app_name" >/dev/null 2>&1; then
      echo "Quit the running $app_name build in $APP_ROOT before rebuilding, then rerun this command." >&2
      return 1
    fi
  done
}
