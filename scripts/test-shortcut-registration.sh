#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product ClearFlow
BUILD_DIR="$(swift build --show-bin-path)"
swiftc -parse-as-library -I "$BUILD_DIR/Modules" "$BUILD_DIR"/ClearFlowCore.build/*.o \
  Sources/ClearFlow/GlobalShortcut.swift Tests/ShortcutRegistrationChecks.swift \
  -o "$BUILD_DIR/ShortcutRegistrationChecks"
"$BUILD_DIR/ShortcutRegistrationChecks"
