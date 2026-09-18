#!/bin/bash
# XCTest ships with Xcode, not the Command Line Tools, so point the toolchain at
# Xcode without changing the machine-wide xcode-select setting.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
exec swift test "$@"
