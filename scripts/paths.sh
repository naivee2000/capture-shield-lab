#!/bin/bash
# Build bundles on the local Mac filesystem. exFAT/SMB AppleDouble metadata
# can invalidate codesign resource seals even when source compilation succeeds.
APP_ROOT="${CAPTURESHIELD_APP_ROOT:-$HOME/Library/Caches/CaptureShieldLab/Apps}"
