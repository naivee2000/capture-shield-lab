#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/paths.sh"
bash "$ROOT/scripts/build.sh"
open "$APP_ROOT/CaptureShieldLab.app"
echo 'If the lab was already running, quit it and rerun this command to load the new build.'
