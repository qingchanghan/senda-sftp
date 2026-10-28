#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if pgrep -f "^$PWD/dist/Senda.app/Contents/MacOS/Senda$" >/dev/null; then
    echo "请先退出正在运行的 Senda，再执行打包，以免覆盖运行中的程序。" >&2
    exit 1
fi
python3 scripts/generate-tokens.py --check
swift build -c "$configuration" --product Senda -j 2
bin_dir="$(swift build -c "$configuration" --show-bin-path)"
app="$PWD/dist/Senda.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Senda" "$app/Contents/MacOS/Senda"
if [ "$configuration" = "release" ]; then
    # Swift's release debug map can retain absolute build-machine paths.
    # Strip it before signing and fail if the checkout path is still embedded.
    xcrun strip -S "$app/Contents/MacOS/Senda"
    python3 - "$app/Contents/MacOS/Senda" <<'PY'
import os
import sys
from pathlib import Path

if os.fsencode(Path.cwd()) in Path(sys.argv[1]).read_bytes():
    raise SystemExit('Release binary still contains the local checkout path.')
PY
fi
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Senda</string>
  <key>CFBundleIdentifier</key><string>app.senda.sftp</string>
  <key>CFBundleName</key><string>Senda</string>
  <key>CFBundleDisplayName</key><string>Senda</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.7.0</string>
  <key>CFBundleVersion</key><string>8</string>
  <key>CFBundleIconFile</key><string>Senda</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>Senda — Free and open source</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Senda 需要浏览和下载文件到你的下载目录。</string>
  <key>NSDesktopFolderUsageDescription</key><string>Senda 需要浏览和传输你选择的桌面文件。</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Senda 需要浏览和传输你选择的文稿文件。</string>
</dict></plist>
PLIST
swiftc Sources/Senda/DesignTokens.generated.swift scripts/make-icon.swift -o "$PWD/.build/senda-icon-generator"
"$PWD/.build/senda-icon-generator" "$PWD/dist"
iconutil -c icns "$PWD/dist/Senda.iconset" -o "$app/Contents/Resources/Senda.icns"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp ThirdParty/BeautifulUI/LICENSE "$app/Contents/Resources/BeautifulUI-LICENSE"
codesign --force --sign - "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$PWD/dist/Senda-macOS-$(uname -m).zip"
./scripts/package-dmg.sh "$app"
echo "Built: $app"
