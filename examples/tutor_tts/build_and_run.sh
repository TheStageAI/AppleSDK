#!/usr/bin/env bash
# Build + install TutorTTS on a connected iPhone (Release).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

command -v xcodegen >/dev/null || { echo "brew install xcodegen"; exit 1; }
command -v xcodebuild >/dev/null || { echo "need Xcode CLI tools"; exit 1; }

if [[ ! -f Secrets.xcconfig ]]; then
  cp Secrets.xcconfig.example Secrets.xcconfig
  echo "Created Secrets.xcconfig — set TS_API_TOKEN then re-run."
  exit 1
fi

xcodegen generate

DEVICE_ID="${DEVICE_ID:-}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(xcrun xctrace list devices 2>/dev/null \
    | awk -F'[()]' '/iPhone/{print $(NF-1); exit}')"
fi
[[ -n "$DEVICE_ID" ]] || { echo "No iPhone found; set DEVICE_ID="; exit 1; }

DERIVED="$ROOT/build"
rm -rf "$DERIVED"
xcodebuild \
  -project TutorTTS.xcodeproj \
  -scheme TutorTTS \
  -configuration Release \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED" \
  build

APP="$DERIVED/Build/Products/Release-iphoneos/TutorTTS.app"
[[ -d "$APP" ]] || { echo "missing $APP"; exit 1; }

xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
xcrun devicectl device process launch --device "$DEVICE_ID" com.example.tutortts \
  || true
echo "Installed TutorTTS on $DEVICE_ID"
