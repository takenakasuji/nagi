#!/bin/bash
# Run the NagiCore unit tests.
#
# Nagi is built with plain SwiftPM (no Xcode project) so it can be built with
# only the Command Line Tools installed. In that configuration swift-testing's
# Testing.framework is present but not on the default search path, so we add it.
# With a full Xcode install `swift test` already finds it and no flags are added.
set -euo pipefail

cd "$(dirname "$0")/.."

DEVELOPER_DIR_PATH="$(xcode-select -p)"
FRAMEWORK_DIR="${DEVELOPER_DIR_PATH}/Library/Developer/Frameworks"

ARGS=()
if [ -d "${FRAMEWORK_DIR}/Testing.framework" ]; then
    ARGS+=(
        -Xswiftc -F -Xswiftc "${FRAMEWORK_DIR}"
        -Xlinker -F -Xlinker "${FRAMEWORK_DIR}"
        -Xlinker -rpath -Xlinker "${FRAMEWORK_DIR}"
    )
fi

# The Command Line Tools ship _Testing_Foundation's dylib and the cross-import
# declaration but not its .swiftmodule, so importing Foundation and Testing in
# one file fails to resolve the overlay. We don't use the overlay's API, so turn
# the automatic import off.
if [ ! -d "${FRAMEWORK_DIR}/_Testing_Foundation.framework/Modules/_Testing_Foundation.swiftmodule" ]; then
    ARGS+=(-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays)
fi

exec swift test "${ARGS[@]}" "$@"
