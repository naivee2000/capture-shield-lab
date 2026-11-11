#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/paths.sh"
require_stopped_build_apps
bash "$ROOT/scripts/build.sh"
mkdir -p "$ROOT/artifacts"
open "$APP_ROOT/CaptureProbe.app" --args --output "$ROOT/artifacts"
echo 'Close private windows, select Synthetic WebView and a display, then start the test. Reports stay in artifacts/.'
