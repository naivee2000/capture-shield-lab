#!/bin/bash
# Source after ROOT is set. Keep the deployment floor in Package.swift.
MINIMUM_MACOS="$(sed -nE 's/.*\.macOS\("([0-9.]+)"\).*/\1/p' "$ROOT/Package.swift")"

capture_version_at_least() {
  local actual="$1" required="$2" i a b
  local actual_parts required_parts
  [[ "$actual" =~ ^[0-9]+(\.[0-9]+)*$ && "$required" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 1
  IFS=. read -r -a actual_parts <<< "$actual"
  IFS=. read -r -a required_parts <<< "$required"
  for i in 0 1 2; do
    a=$((10#${actual_parts[i]:-0})); b=$((10#${required_parts[i]:-0}))
    if (( a > b )); then return 0; fi
    if (( a < b )); then return 1; fi
  done
  return 0
}

capture_build_prerequisites() {
  if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    echo 'Apple Silicon macOS is required.' >&2; return 1
  fi
  if ! capture_version_at_least "$(sw_vers -productVersion)" "$MINIMUM_MACOS"; then
    echo "macOS $MINIMUM_MACOS or newer is required. New OS versions still require runtime/receiver tests." >&2; return 1
  fi
  if ! xcode-select -p >/dev/null 2>&1; then
    echo 'Install Apple developer tools: xcode-select --install' >&2; return 1
  fi
  local swift_version sdk_version
  swift_version="$(xcrun swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p' | head -1 || true)"
  sdk_version="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
  if ! capture_version_at_least "$swift_version" 6.2 || ! capture_version_at_least "$sdk_version" 26.0; then
    echo 'Build requires Swift 6.2+ and macOS SDK 26+. On macOS 15.6–15.x use Xcode / Command Line Tools 26.0–26.3.' >&2
    echo 'Select an installed compatible Xcode with xcode-select, or install compatible tools from developer.apple.com/download/all/.' >&2
    return 1
  fi
  echo "Build host: macOS $(sw_vers -productVersion); Swift $swift_version; SDK $sdk_version; deployment minimum $MINIMUM_MACOS"
}
