#!/bin/bash
# Build Nagi.app.
#
# SwiftPM produces a bare executable, but a menu-bar app needs a real bundle:
# LSUIElement (no Dock icon), a bundle identifier for preferences and login-item
# registration, and a code signature so macOS will let it register a hotkey.
# This assembles that bundle around the built binary.
#
#   ./scripts/build-app.sh            # release build into ./build/Nagi.app
#   ./scripts/build-app.sh --debug    # faster, unoptimized
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="release"
if [ "${1:-}" = "--debug" ]; then
    CONFIGURATION="debug"
fi

APP_DIR="build/Nagi.app"
CONTENTS="${APP_DIR}/Contents"

echo "==> Building (${CONFIGURATION})"
swift build -c "${CONFIGURATION}"

BINARY="$(swift build -c "${CONFIGURATION}" --show-bin-path)/Nagi"
if [ ! -f "${BINARY}" ]; then
    echo "error: built binary not found at ${BINARY}" >&2
    exit 1
fi

echo "==> Assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"

cp "${BINARY}" "${CONTENTS}/MacOS/Nagi"
cp Resources/Info.plist "${CONTENTS}/Info.plist"
printf 'APPL????' > "${CONTENTS}/PkgInfo"

# The icon is committed rather than drawn here: scripts/make-icon.swift needs
# only the Command Line Tools too, but it changes about as often as the logo
# does, and a missing one should fail loudly rather than produce a blank app.
if [ ! -f Resources/AppIcon.icns ]; then
    echo "error: Resources/AppIcon.icns is missing — run ./scripts/make-icon.swift" >&2
    exit 1
fi
cp Resources/AppIcon.icns "${CONTENTS}/Resources/AppIcon.icns"

# Ad-hoc signature. Enough for local use: it gives the bundle a stable identity
# so macOS remembers permissions between launches. Replace with a Developer ID
# for distribution.
echo "==> Signing (ad-hoc)"
# --deep is deprecated for signing and unnecessary here: the bundle holds a
# single executable and no nested code.
codesign --force --sign - "${APP_DIR}"

echo
echo "Built ${APP_DIR}"
echo "  open ${APP_DIR}      # run it"
echo "  cp -r ${APP_DIR} /Applications/   # install"
