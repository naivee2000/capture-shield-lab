#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TOOL_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
FRAMEWORKS="$TOOL_DIR/Library/Developer/Frameworks"
if [[ -d "$TOOL_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks/Testing.framework" ]]; then
  FRAMEWORKS="$TOOL_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks"
fi
# Swift 6.4 defaults to Swift Build's per-target framework bundles. Keep the
# native unit host on SwiftPM's supported native product layout on every SDK;
# packaged-app UI tests still build the application through scripts/build.sh.
BUILD_ARGS=(--build-system native)
RUN_ARGS=()
CUSTOM_SELECTION=false
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --filter|--skip)
      [[ "$#" -ge 2 ]] || { echo 'Missing test selection.' >&2; exit 2; }
      CUSTOM_SELECTION=true; RUN_ARGS+=("$1" "$2"); shift 2 ;;
    --filter=*|--skip=*)
      CUSTOM_SELECTION=true; RUN_ARGS+=("${1%%=*}" "${1#*=}"); shift ;;
    --parallel|--no-parallel) RUN_ARGS+=("$1"); shift ;;
    *) BUILD_ARGS+=("$1"); shift ;;
  esac
done
HOST_FLAGS=(-swift-version 6 -parse-as-library -target arm64-apple-macosx15.6)
if [[ -d "$FRAMEWORKS/Testing.framework" ]]; then
  BUILD_ARGS+=(-Xswiftc -F -Xswiftc "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS")
  HOST_FLAGS+=(-F "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS")
  if [[ "$TOOL_DIR" == *CommandLineTools && ! -d "$FRAMEWORKS/_Testing_Foundation.framework/Modules" ]]; then
    BUILD_ARGS+=(-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays)
    HOST_FLAGS+=(-Xfrontend -disable-cross-import-overlays)
  fi
fi
TEST_LOG="$(mktemp "${TMPDIR:-/tmp}/captureshield-native.XXXXXX")"
trap 'rm -f "$TEST_LOG"' EXIT
# Build/discover through SwiftPM; never edit its generated runner or SDK files.
xcrun swift test list --disable-xctest "${BUILD_ARGS[@]}" > "$TEST_LOG"
BIN="$(xcrun swift build "${BUILD_ARGS[@]}" --show-bin-path)"
# SwiftPM versions produce either one package bundle or one per test target.
# Require the complete expected set; never run an accidental partial selection.
BUNDLES="$(python3 - "$BIN" <<'PYBUNDLE'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
combined = root / 'CaptureShieldLabPackageTests.xctest'
paths = [combined] if combined.is_dir() else [root / (name + '.xctest') for name in ('CaptureCoreTests', 'CaptureWindowTests')]
if not all(path.is_dir() for path in paths):
    raise SystemExit('SwiftPM did not produce the complete expected test bundle set.')
print(json.dumps([str(path) for path in paths]))
PYBUNDLE
)"
xcrun swiftc "${HOST_FLAGS[@]}" -Xlinker -rpath -Xlinker "$BIN" "$ROOT/scripts/native-test-main.swift" -o "$BIN/CaptureShieldNativeTests"
run_native() {
  set +e
  CAPTURESHIELD_NATIVE_BUNDLES="$BUNDLES" "$BIN/CaptureShieldNativeTests" "${RUN_ARGS[@]}" "$@" 2>&1 | tee "$TEST_LOG"
  RESULTS=("${PIPESTATUS[@]}")
  set -e
  if [[ "${RESULTS[0]}" -ne 0 ]]; then exit "${RESULTS[0]}"; fi
  if [[ "${RESULTS[1]}" -ne 0 ]]; then exit "${RESULTS[1]}"; fi
  python3 "$ROOT/scripts/verify-test-output.py" "$TEST_LOG"
}
if $CUSTOM_SELECTION; then
  run_native
else
  # Keep the established isolated AppKit lifecycle/configuration hosts. Every
  # case runs once; a partial run never becomes a pass, and nothing is retried.
  run_native --skip '(^CaptureWindowTests\.WindowTests/|modePolicyDoesNotRequireWindowLevelChanges)'
  run_native --filter '^CaptureWindowTests\.WindowTests/'
  run_native --filter 'modePolicyDoesNotRequireWindowLevelChanges'
fi
