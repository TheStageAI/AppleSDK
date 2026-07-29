#!/usr/bin/env bash
# Build EngineBench (Release) and install it on a connected iPhone.
#
# Prereqs: Xcode 16+, xcodegen, physical iPhone (iOS 18+), Apple Silicon Mac.
# Models download from Hugging Face on first use — nothing is bundled.
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f Secrets.xcconfig ]]; then
  cp Secrets.xcconfig.example Secrets.xcconfig
fi

if ! grep -qE 'TS_API_TOKEN[[:space:]]*=[[:space:]]*th_' Secrets.xcconfig; then
  echo "Set TS_API_TOKEN=th_… in Secrets.xcconfig (from https://app.thestage.ai)."
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required: brew install xcodegen"
  exit 1
fi

BUNDLE_ID="com.example.enginebench"
SCHEME="EngineBench"

DEVICE_ID="${DEVICE_ID:-}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null \
    | awk -F'  +' '/connected/ {print $3; exit}')
fi
if [[ -z "$DEVICE_ID" ]]; then
  echo "No connected device. Unlock your iPhone, then:"
  echo "  xcrun devicectl list devices"
  echo "  DEVICE_ID=<identifier> $0"
  exit 1
fi
echo "Using device: $DEVICE_ID"

xcodegen generate

xcodebuild \
  -project EngineBench.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  build

APP="build/Build/Products/Release-iphoneos/${SCHEME}.app"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
echo "Launching EngineBench — first model load downloads from Hugging Face."
xcrun devicectl device process launch --terminate-existing \
  --device "$DEVICE_ID" "$BUNDLE_ID"
