#!/bin/bash
# Builds the thestage_sdk wheel: thestage-host in release, signed (Developer ID
# from THESTAGE_SIGN_IDENTITY, ad hoc otherwise), copied into the package, and
# the wheel tagged macosx_15_0_arm64 so pip installs it only where it runs.
# Users need Python and pip; no Xcode or Swift toolchain.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
swift_dir="$here/../swift"

swift build -c release --package-path "$swift_dir" --product thestage-host
bin="$(swift build -c release --package-path "$swift_dir" --show-bin-path)/thestage-host"

mkdir -p "$here/src/thestage_sdk/_bin"
cp "$bin" "$here/src/thestage_sdk/_bin/thestage-host"
identity="${THESTAGE_SIGN_IDENTITY:--}"
codesign --force --options runtime --timestamp=none --sign "$identity" "$here/src/thestage_sdk/_bin/thestage-host"

rm -rf "$here/dist"
python3 -m pip wheel --no-deps --wheel-dir "$here/dist" "$here" -q
python3 -m wheel tags --remove --platform-tag macosx_15_0_arm64 "$here"/dist/thestage_sdk-*.whl
ls -la "$here/dist"
