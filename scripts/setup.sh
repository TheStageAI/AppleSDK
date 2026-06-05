#!/usr/bin/env bash
#
# One-time host setup for the TheStage Apple SDK distribution.
#
# What it does (by default):
#   1. Symlinks TheStageCore.xcframework into the Flutter plugin's Binaries/.
#   2. Bootstraps secrets.json from secrets.example.json for each example.
#
# With --espeak (only needed if you build a neutts-NANO app):
#   3. Clones espeak-ng-spm and applies the two build patches it needs,
#      into extras/espeak/espeak-ng-spm. The multilingual TTS model and all
#      shipped examples do NOT need this.
#
# Usage:
#   ./scripts/setup.sh            # xcframework + secrets
#   ./scripts/setup.sh --espeak   # also fetch & patch espeak-ng for nano apps
#
# Safe to re-run; every step short-circuits if its output already exists.

set -euo pipefail

WANT_ESPEAK=0
for arg in "$@"; do
    case "$arg" in
        --espeak) WANT_ESPEAK=1 ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) printf 'Unknown argument: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_ROOT="$REPO_ROOT/plugin/thestage_apple_sdk/ios/thestage_apple_sdk"

err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }
ok() { printf '[ok] %s\n' "$*"; }

# ---------------------------------------------------------------
# 1. Symlink TheStageCore.xcframework into the plugin
# ---------------------------------------------------------------
XCF_LINK="$PLUGIN_ROOT/Binaries/TheStageCore.xcframework"
if [ -L "$XCF_LINK" ] || [ -e "$XCF_LINK" ]; then
    ok "xcframework symlink already present"
else
    info "Linking TheStageCore.xcframework into the plugin"
    mkdir -p "$(dirname "$XCF_LINK")"
    ln -s ../../../../../TheStageCore.xcframework "$XCF_LINK"
    ok "xcframework symlink created"
fi

# ---------------------------------------------------------------
# 2. Bootstrap per-example secrets.json from secrets.example.json
# ---------------------------------------------------------------
for app_dir in "$REPO_ROOT"/examples/*/ ; do
    [ -d "$app_dir" ] || continue
    template="$app_dir/secrets.example.json"
    target="$app_dir/secrets.json"
    if [ -f "$template" ] && [ ! -f "$target" ]; then
        cp "$template" "$target"
        info "Created $target — fill in your keys before running."
    fi
done

# ---------------------------------------------------------------
# 3. (opt-in) Clone and patch espeak-ng-spm for neutts-nano apps
# ---------------------------------------------------------------
if [ "$WANT_ESPEAK" -eq 1 ]; then
    ESPEAK_DIR="$REPO_ROOT/extras/espeak/espeak-ng-spm"
    ESPEAK_REMOTE="https://github.com/espeak-ng/espeak-ng-spm.git"

    if [ -f "$ESPEAK_DIR/Package.swift" ]; then
        ok "espeak-ng-spm already present"
    else
        info "Cloning espeak-ng-spm (nano-only dependency)"
        mkdir -p "$(dirname "$ESPEAK_DIR")"
        git clone --recursive "$ESPEAK_REMOTE" "$ESPEAK_DIR"

        SPEECH_C="$ESPEAK_DIR/Sources/libespeak-ng/_repo/src/libespeak-ng/speech.c"
        if [ -f "$SPEECH_C" ]; then
            info "Patching speech.c (PATH_ESPEAK_DATA)"
            sed -i '' 's/strcpy(path_home, PATH_ESPEAK_DATA);/sprintf(path_home, PATH_ESPEAK_DATA);/' "$SPEECH_C"
        fi

        PKG="$ESPEAK_DIR/Package.swift"
        if [ -f "$PKG" ] && ! grep -q 'Wno-int-conversion' "$PKG"; then
            info "Patching Package.swift (suppress -Wint-conversion)"
            sed -i '' '/\.define("N_PATH_HOME"/a\
        .unsafeFlags(["-Wno-int-conversion"]),
' "$PKG"
        fi

        rm -rf "$ESPEAK_DIR/.git" "$ESPEAK_DIR/.gitmodules"
        find "$ESPEAK_DIR/Sources" -name ".git" -delete 2>/dev/null || true
        ok "espeak-ng-spm cloned and patched into extras/espeak/espeak-ng-spm"
    fi
    info "Next: see extras/espeak/README.md to wire it into your nano app."
fi

# ---------------------------------------------------------------
# 4. Verify
# ---------------------------------------------------------------
errors=0
[ -f "$REPO_ROOT/TheStageCore.xcframework/Info.plist" ] || { echo "missing TheStageCore.xcframework"; errors=1; }
[ -f "$XCF_LINK/Info.plist" ] || { echo "xcframework symlink is broken"; errors=1; }
if [ "$WANT_ESPEAK" -eq 1 ]; then
    [ -f "$REPO_ROOT/extras/espeak/espeak-ng-spm/Package.swift" ] || { echo "espeak-ng-spm clone failed"; errors=1; }
fi

if [ $errors -ne 0 ]; then
    err "Setup completed with errors. See messages above."
fi

cat <<'EOF'

Setup complete.

Next steps:
  1. Edit examples/<app>/secrets.json and put in your TheStage API token
     (and OpenAI key for voice_agent).
  2. Open examples/<app>/ios/Runner.xcodeproj in Xcode and set Team +
     Bundle Identifier under Signing & Capabilities.
  3. Build and run:
       cd examples/tts_front_stream
       flutter pub get
       flutter run --release \
           --dart-define-from-file=secrets.json \
           -d <YOUR_DEVICE_ID>

(Building a neutts-nano app? Run ./scripts/setup.sh --espeak first.)
EOF
