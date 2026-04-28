#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Bucky"
APP_PATH="build/${APP_NAME}.app"
EXECUTABLE_PATH="${APP_PATH}/Contents/MacOS/${APP_NAME}"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"
DIST_DIR="dist"

if [[ ! -d "${APP_PATH}" ]]; then
    echo "error: ${APP_PATH} does not exist. Run 'make bundle' first." >&2
    exit 1
fi

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
    echo "error: ${EXECUTABLE_PATH} does not exist or is not executable." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}" 2>/dev/null || true)"
if [[ -z "${VERSION}" ]]; then
    VERSION="dev"
fi

ARCHS="$(lipo -archs "${EXECUTABLE_PATH}")"
ARCH_LABEL="${ARCHS// /-}"
ZIP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}-macos-${ARCH_LABEL}.zip"

mkdir -p "${DIST_DIR}"
rm -f "${ZIP_PATH}" "${ZIP_PATH}.sha256"

ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"
shasum -a 256 "${ZIP_PATH}" > "${ZIP_PATH}.sha256"

echo "Created ${ZIP_PATH}"
echo "Created ${ZIP_PATH}.sha256"
