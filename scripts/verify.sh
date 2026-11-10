#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/paths.sh"
bash "$ROOT/scripts/build.sh"
mkdir -p "$ROOT/artifacts"
open "$APP_ROOT/CaptureProbe.app" --args --output "$ROOT/artifacts"
echo 'Use CaptureProbe to select a display and start a synthetic-content test. Reports stay in artifacts/.'
