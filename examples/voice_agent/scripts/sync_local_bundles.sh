#!/usr/bin/env bash
# Sync local v2 prepare trees into ios/Runner/BundledModels for on-device runs.
#
# Default stack for this app:
#   LLM  lfm2.5-350m
#   TTS  qwen3-tts-12hz-0.6b-base
#   STT  thewhisper-large-v3-turbo
#   VAD  silero-vad
#   EOT  smart-turn-v3
#
# A Run Script build phase in the Xcode project copies BundledModels into the
# .app resources at build time (see ios/Runner.xcodeproj).
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_ROOT="$(cd ../.. && pwd)"
PREPARE_ROOT="${QLIP_V2_PREPARE_ROOT:-$REPO_ROOT/work/v2_prepare}"
DEST="ios/Runner/BundledModels"

MODELS="${MODELS:-lfm2.5-350m qwen3-tts-12hz-0.6b-base thewhisper-large-v3-turbo silero-vad smart-turn-v3}"

if [[ ! -d "$PREPARE_ROOT" ]]; then
  echo "ERROR: prepare root missing: $PREPARE_ROOT" >&2
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"
echo "syncing voice_agent bundles from $PREPARE_ROOT -> $DEST/"
for m in $MODELS; do
  src="$PREPARE_ROOT/$m/extracted/$m"
  if [[ ! -d "$src" ]]; then
    echo "  ERROR: missing $src" >&2
    exit 1
  fi
  out="$DEST/$m"
  mkdir -p "$out"
  rsync -a \
    --exclude '.DS_Store' \
    --exclude '_intermediates' \
    --exclude '*.log' \
    "$src/" "$out/"
  echo "  $m  ($(du -sh "$out" | cut -f1))"
done

# Keep Xcode from indexing huge binary trees as source.
cat > "$DEST/.gitignore" <<'EOF'
*
!.gitignore
EOF

echo "done. ~$(du -sh "$DEST" | cut -f1) under $DEST"
echo "Next: flutter run --release --dart-define-from-file=../secrets.json -d <iphone>"
