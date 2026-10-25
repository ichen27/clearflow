#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product ClearFlow
BUILD_DIR="$(swift build --show-bin-path)"
swiftc -parse-as-library -I "$BUILD_DIR/Modules" "$BUILD_DIR"/ClearFlowCore.build/*.o \
  Sources/ClearFlow/SettingsStore.swift Sources/ClearFlow/AudioCapture.swift Tests/AudioCaptureChecks.swift \
  -o "$BUILD_DIR/AudioCaptureChecks"
"$BUILD_DIR/AudioCaptureChecks"
swiftc -parse-as-library -I "$BUILD_DIR/Modules" "$BUILD_DIR"/ClearFlowCore.build/*.o \
  Sources/ClearFlow/SettingsStore.swift Sources/ClearFlow/TranscriptionClient.swift Tests/LongTranscriptionChecks.swift \
  -o "$BUILD_DIR/LongTranscriptionChecks"
"$BUILD_DIR/LongTranscriptionChecks"

swiftc -parse-as-library -I "$BUILD_DIR/Modules" "$BUILD_DIR"/ClearFlowCore.build/*.o \
  Sources/ClearFlow/SettingsStore.swift Sources/ClearFlow/AudioCapture.swift \
  Sources/ClearFlow/TranscriptionClient.swift Sources/ClearFlow/TextInsertion.swift \
  Sources/ClearFlow/DictationModel.swift Tests/RecoveryChecks.swift \
  -o "$BUILD_DIR/RecoveryChecks"
"$BUILD_DIR/RecoveryChecks"
