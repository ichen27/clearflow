#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch arm64 --product ClearFlow
APP="$PWD/dist/ClearFlow.app"
# Always package a fresh bundle so stale resources cannot leak into releases.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/ClearFlow" "$APP/Contents/MacOS/ClearFlow"
python3 - "$APP" "http://127.0.0.1:8768" <<'PY'
import pathlib,plistlib,sys
app=pathlib.Path(sys.argv[1])
info={"CFBundleName":"ClearFlow","CFBundleDisplayName":"ClearFlow","CFBundleIdentifier":"org.clearflow.app","CFBundleExecutable":"ClearFlow","CFBundlePackageType":"APPL","CFBundleShortVersionString":"0.4.1","CFBundleVersion":"9","LSMinimumSystemVersion":"14.0","LSUIElement":True,"NSHighResolutionCapable":True,"NSMicrophoneUsageDescription":"ClearFlow records your voice only when you start dictation, then sends it to the transcription service you configure.","ClearFlowEndpoint":sys.argv[2]}
(app/"Contents/Info.plist").write_bytes(plistlib.dumps(info))
PY
# Remove linker debug records containing the build machine absolute source paths.
strip -S "$APP/Contents/MacOS/ClearFlow"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
rm -f "$PWD/dist/ClearFlow-macOS-arm64.zip"
ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP" "$PWD/dist/ClearFlow-macOS-arm64.zip"
echo "Built $APP"
