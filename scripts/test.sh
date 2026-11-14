#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TOOL_DIR="$(xcode-select -p)"
FRAMEWORKS="$TOOL_DIR/Library/Developer/Frameworks"
CUSTOM_SELECTION=false
for ARG in "$@"; do
  case "$ARG" in --filter|--filter=*|--skip|--skip=*) CUSTOM_SELECTION=true ;; esac
done
set -- --disable-xctest "$@"
# Some CLT distributions omit framework search paths and an optional Testing
# Foundation overlay module. Use the bundled runtime; never alter the SDK.
if [[ "$TOOL_DIR" == *CommandLineTools && -d "$FRAMEWORKS/Testing.framework" ]]; then
  set -- -Xswiftc -F -Xswiftc "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS" "$@"
  if [[ ! -d "$FRAMEWORKS/_Testing_Foundation.framework/Modules" ]]; then
    set -- -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays "$@"
  fi
fi
TEST_LOG="$(mktemp "${TMPDIR:-/tmp}/captureshield-native.XXXXXX")"
trap 'rm -f "$TEST_LOG"' EXIT
run_native() {
  set +e
  xcrun swift test "$@" 2>&1 | tee "$TEST_LOG"
  RESULTS=("${PIPESTATUS[@]}")
  set -e
  if [[ "${RESULTS[0]}" -ne 0 ]]; then exit "${RESULTS[0]}"; fi
  if [[ "${RESULTS[1]}" -ne 0 ]]; then exit "${RESULTS[1]}"; fi
  python3 "$ROOT/scripts/verify-test-output.py" "$TEST_LOG"
}
if $CUSTOM_SELECTION; then
  run_native "$@"
else
  # Native window replacement/activation exercises process-wide AppKit lifetime.
  # Run that suite in a fresh process, once, rather than retrying shared-host exits.
  run_native "$@" --skip '^CaptureWindowTests\.WindowTests/'
  run_native "$@" --filter '^CaptureWindowTests\.WindowTests/'
fi
