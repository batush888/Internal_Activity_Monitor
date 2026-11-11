#!/bin/zsh
set -euo pipefail

if [[ -f ".env" ]]; then
    set -a
    source .env
    set +a
fi

APP_NAME="PulseMatrixPro"
BUNDLE_ID="${PULSEMATRIX_BUNDLE_ID:-io.pulsematrix.pro}"
BUILD_DIR=".build/debug"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swift-module-cache swift build --build-system native --disable-index-store --disable-sandbox --cache-path /tmp/swiftpm-cache -Xswiftc -module-cache-path -Xswiftc /tmp/swift-module-cache -Xcc -fmodules-cache-path=/tmp/clang-module-cache

rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>PulseMatrix Pro</string>
    <key>CFBundleDisplayName</key>
    <string>PulseMatrix Pro</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>200</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Successfully packaged ${BUNDLE_DIR}"
