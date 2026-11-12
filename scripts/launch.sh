#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/paths.sh"
source "$ROOT/scripts/support.sh"
case "${1:-}" in
  ''|--lab|--web-test|--chat-preview) ;;
  *) echo 'Usage: bash scripts/launch.sh [--lab | --web-test | --chat-preview]' >&2; exit 2 ;;
esac
if [[ "$#" -gt 1 ]]; then echo 'Pass at most one launch mode.' >&2; exit 2; fi
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]] || ! capture_version_at_least "$(sw_vers -productVersion)" "$MINIMUM_MACOS"; then
  echo "Apple Silicon macOS $MINIMUM_MACOS+ is required." >&2; exit 1
fi
APP="$APP_ROOT/CaptureShieldLab.app"
if [[ ! -x "$APP/Contents/MacOS/CaptureShieldLab" ]]; then
  echo 'No built app found. Run bash scripts/dev.sh first.' >&2; exit 1
fi
codesign --verify --strict "$APP"
open "$APP" --args "$@"
echo 'Opened the existing application without rebuilding or changing its signature.'
