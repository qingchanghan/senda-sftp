#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Package an existing, signed app without rebuilding or replacing a running copy.
app="${1:-$PWD/dist/Senda.app}"
if [[ ! -d "$app" || ! -f "$app/Contents/MacOS/Senda" ]]; then
    echo "Senda.app not found. Run ./scripts/build-app.sh first or pass its path." >&2
    exit 1
fi
codesign --verify --deep --strict "$app"
architecture="$(lipo -archs "$app/Contents/MacOS/Senda")"
case "$architecture" in
    arm64|x86_64) ;;
    "x86_64 arm64"|"arm64 x86_64") architecture="universal" ;;
    *) echo "Unsupported app architecture: $architecture" >&2; exit 1 ;;
esac
output="$PWD/dist/Senda-macOS-$architecture.dmg"
mkdir -p "$PWD/dist"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/senda-dmg.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT
mkdir "$temporary_root/image"
ditto "$app" "$temporary_root/image/Senda.app"
ln -s /Applications "$temporary_root/image/Applications"

hdiutil create -quiet -fs HFS+ -volname Senda \
    -srcfolder "$temporary_root/image" -format UDZO "$temporary_root/Senda.dmg"
hdiutil verify -quiet "$temporary_root/Senda.dmg"
mv -f "$temporary_root/Senda.dmg" "$output"
echo "Packaged: $output"
