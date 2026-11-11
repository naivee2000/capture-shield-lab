#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/paths.sh"
if pgrep -x CaptureShieldLab >/dev/null || pgrep -x CaptureProbe >/dev/null; then
  echo 'Quit CaptureShieldLab and CaptureProbe before rebuilding (Cmd-Q), then rerun this command.' >&2; exit 1
fi
bash "$ROOT/scripts/build.sh"
mkdir -p "$ROOT/artifacts"
open "$APP_ROOT/CaptureProbe.app" --args --output "$ROOT/artifacts"
echo 'Close private windows, select Synthetic WebView and a display, then start the test. Reports stay in artifacts/.'
