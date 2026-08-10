#!/bin/bash
# Build Nagi.app.
#
# SwiftPM produces a bare executable, but a menu-bar app needs a real bundle:
# LSUIElement (no Dock icon), a bundle identifier for preferences and login-item
# registration, and a code signature so macOS will let it register a hotkey.
# This assembles that bundle around the built binary.
#
#   ./scripts/build-app.sh              # release build into ./build/Nagi.app
#   ./scripts/build-app.sh --debug      # faster, unoptimized
#   ./scripts/build-app.sh --universal  # arm64 + x86_64, for distribution
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="release"
UNIVERSAL=0
for arg in "$@"; do
    case "${arg}" in
        --debug)     CONFIGURATION="debug" ;;
        --universal) UNIVERSAL=1 ;;
        *) echo "error: unknown option ${arg}" >&2; exit 1 ;;
    esac
done

APP_DIR="build/Nagi.app"
CONTENTS="${APP_DIR}/Contents"

echo "==> Building (${CONFIGURATION})"
swift build -c "${CONFIGURATION}"

BINARY="$(swift build -c "${CONFIGURATION}" --show-bin-path)/Nagi"
if [ ! -f "${BINARY}" ]; then
    echo "error: built binary not found at ${BINARY}" >&2
    exit 1
fi

# The x86_64 slice, for distribution. `swift build --arch arm64 --arch x86_64`
# would be the obvious way, but SwiftPM hands that to xcbuild, which only ships
# with a full Xcode — it would break the "Command Line Tools are enough" premise
# this whole script exists to keep. Building the slice separately with -target
# and joining the two with lipo needs nothing Xcode-only.
#
# The deployment target is read from Info.plist rather than written twice: the
# arm64 slice takes it from Package.swift's `platforms:`, and a disagreement
# between the two slices would only show up on someone else's Intel Mac.
if [ "${UNIVERSAL}" = "1" ]; then
    MIN_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"
    X86_ARGS=(
        -c "${CONFIGURATION}"
        --scratch-path .build/x86_64
        -Xswiftc -target -Xswiftc "x86_64-apple-macos${MIN_MACOS}"
    )

    echo "==> Building x86_64 slice (macOS ${MIN_MACOS})"
    swift build "${X86_ARGS[@]}"

    X86_BINARY="$(swift build "${X86_ARGS[@]}" --show-bin-path)/Nagi"
    if [ ! -f "${X86_BINARY}" ]; then
        echo "error: x86_64 binary not found at ${X86_BINARY}" >&2
        exit 1
    fi
fi

echo "==> Assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"

if [ "${UNIVERSAL}" = "1" ]; then
    lipo -create "${BINARY}" "${X86_BINARY}" -output "${CONTENTS}/MacOS/Nagi"
else
    cp "${BINARY}" "${CONTENTS}/MacOS/Nagi"
fi
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
