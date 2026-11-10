#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TOOL_DIR="$(xcode-select -p)"
FRAMEWORKS="$TOOL_DIR/Library/Developer/Frameworks"
set -- --disable-xctest "$@"
# Some CLT distributions omit framework search paths and an optional Testing
# Foundation overlay module. Use the bundled runtime; never alter the SDK.
if [[ "$TOOL_DIR" == *CommandLineTools && -d "$FRAMEWORKS/Testing.framework" ]]; then
  set -- -Xswiftc -F -Xswiftc "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS" "$@"
  if [[ ! -d "$FRAMEWORKS/_Testing_Foundation.framework/Modules" ]]; then
    set -- -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays "$@"
  fi
fi
xcrun swift test "$@"
