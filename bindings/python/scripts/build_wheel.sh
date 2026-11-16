#!/bin/bash
# Builds the thestage_sdk wheel: thestage-host in release and the SDK framework
# it loads, signed (Developer ID from THESTAGE_SIGN_IDENTITY, ad hoc otherwise),
# copied into the package, and the wheel tagged macosx_15_0_arm64 so pip
# installs it only where it runs.
# Users need Python and pip; no Xcode or Swift toolchain.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
swift_dir="$here/../swift"

swift build -c release --package-path "$swift_dir" --product thestage-host
bin_dir="$(swift build -c release --package-path "$swift_dir" --show-bin-path)"

dest="$here/src/thestage_sdk/_bin"
rm -rf "$dest"
mkdir -p "$dest"
cp "$bin_dir/thestage-host" "$dest/thestage-host"
identity="${THESTAGE_SIGN_IDENTITY:--}"

# TheStageCore is a dynamic framework: the host loads it from beside itself
# (`@loader_path`). A wheel holds no symlinks, so only the binary is copied,
# at the path its install name spells. A source build of the SDK links it
# statically and has no framework to copy.
core="TheStageCore.framework/Versions/A/TheStageCore"
if [ -f "$bin_dir/$core" ]; then
    mkdir -p "$dest/$(dirname "$core")"
    cp "$bin_dir/$core" "$dest/$core"
    codesign --force --timestamp=none --sign "$identity" "$dest/$core"
fi
# Hardened runtime only with a real identity: under it the host may load only
# libraries signed by its own team, and an ad hoc signature has no team.
if [ "$identity" = "-" ]; then
    codesign --force --sign - "$dest/thestage-host"
else
    codesign --force --options runtime --timestamp=none --sign "$identity" "$dest/thestage-host"
fi

rm -rf "$here/dist"
python3 -m pip wheel --no-deps --wheel-dir "$here/dist" "$here" -q
python3 -m wheel tags --remove --platform-tag macosx_15_0_arm64 "$here"/dist/thestage_sdk-*.whl
ls -la "$here/dist"
