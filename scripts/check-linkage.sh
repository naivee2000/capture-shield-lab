#!/bin/bash
# Regression gate for the pre-main macOS 15 crash found by cross-OS CI.
# Inspect the actual executable/test bundle, not just source #available checks.
set -euo pipefail
if [[ "$#" -ne 1 || ! -f "$1" ]]; then
  echo 'Usage: bash scripts/check-linkage.sh /path/to/Mach-O-binary' >&2
  exit 2
fi
symbols="$(xcrun nm -m "$1")"
for name in SCScreenshotConfiguration SCScreenshotOutput; do
  symbol="_OBJC_CLASS_\$_$name"
  references="$(printf '%s\n' "$symbols" | awk -v symbol="$symbol" 'index($0, " " symbol " ")')"
  # An optimized build may eliminate the reference. If present, it must be weak.
  if [[ -n "$references" && "$references" != *'(undefined) weak external '* ]]; then
    echo "Unsafe deployment: $name is required at load time on macOS 15." >&2
    exit 1
  fi
done
echo 'Screenshot class linkage supports the pre-macOS-26 runtime branch.'
