#!/bin/bash
# Deterministic checks; fake commands never install tools or change host settings.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/support.sh"
expect_version() {
  local actual="$1" minimum="$2" expected="$3" result=0
  if ! capture_version_at_least "$actual" "$minimum"; then result=1; fi
  [[ "$result" -eq "$expected" ]] || { echo "Version check failed: $*"; exit 1; }
}
expect_version 15.5 15.6 1
expect_version 15.6 15.6 0
expect_version 15.6.1 15.6 0
expect_version 26.0 15.6 0
expect_version 27.0 15.6 0
expect_version 99.0 15.6 0
expect_version invalid 15.6 1
expect_version 6.1 6.2 1
expect_version 6.2.3 6.2 0
expect_version 15.5 26.0 1
capture_test_os=15.6; capture_test_swift=6.2; capture_test_sdk=26.0
uname() { [[ "$1" == -s ]] && echo Darwin || echo arm64; }
sw_vers() { echo "$capture_test_os"; }
xcode-select() { return 0; }
xcrun() {
  if [[ "$1" == swift ]]; then echo "Apple Swift version $capture_test_swift"; else
    [[ "$capture_test_sdk" != missing ]] || return 1
    echo "$capture_test_sdk"
  fi
}
capture_build_prerequisites >/dev/null
capture_test_os=15.5
if capture_build_prerequisites >/dev/null 2>&1; then echo 'Old OS incorrectly allowed'; exit 1; fi
capture_test_os=15.6; capture_test_sdk=15.5
if capture_build_prerequisites >/dev/null 2>&1; then echo 'Old SDK incorrectly allowed'; exit 1; fi
capture_test_sdk=26.0; capture_test_swift=6.1
if capture_build_prerequisites >/dev/null 2>&1; then echo 'Old Swift incorrectly allowed'; exit 1; fi
capture_test_swift=6.2; capture_test_sdk=missing
set +e
capture_test_output="$( (set -e; capture_build_prerequisites) 2>&1)"
capture_test_result=$?
set -e
[[ "$capture_test_result" -ne 0 && "$capture_test_output" == *'macOS SDK 26+'* ]] || { echo 'Missing SDK did not give repair guidance'; exit 1; }
echo 'Toolchain/version checks passed; no host settings changed.'
