#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/paths.sh"
case "${1:-}" in
  ''|--lab|--web-test|--chat-preview) ;;
  *) echo 'Usage: bash scripts/dev.sh [--lab | --web-test | --chat-preview]' >&2; exit 2 ;;
esac
if [[ "$#" -gt 1 ]]; then echo 'Pass at most one launch mode.' >&2; exit 2; fi
if pgrep -x CaptureShieldLab >/dev/null || pgrep -x CaptureProbe >/dev/null; then
  echo 'Quit CaptureShieldLab and CaptureProbe before rebuilding (Cmd-Q), then rerun this command.' >&2; exit 1
fi
bash "$ROOT/scripts/build.sh"
open "$APP_ROOT/CaptureShieldLab.app" --args "$@"
echo 'Opened CaptureShield. Each Mac keeps its own login. Retest screen sharing on this Mac.'
