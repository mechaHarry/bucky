#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
# A caller's make dry-run flags must not silently turn packaging into a stale build.
unset MAKEFLAGS MFLAGS GNUMAKEFLAGS MAKELEVEL

APP_NAME="Bucky"
APP_PATH="build/${APP_NAME}.app"
EXECUTABLE_PATH="${APP_PATH}/Contents/MacOS/${APP_NAME}"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"
DIST_DIR="${BUCKY_PACKAGE_DIST_DIR:-dist}"

# Incremental builds preserve the successful test gate and other agents' outputs.
# make bundle retains the existing ad-hoc signing default for local packages.
sourceVersion="$(python3 scripts/releaseTooling.py --plist-version packaging/Info.plist)"
make bundle

if [[ ! -d "${APP_PATH}" ]]; then
    echo "error: ${APP_PATH} does not exist after build." >&2
    exit 1
fi

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
    echo "error: ${EXECUTABLE_PATH} does not exist or is not executable." >&2
    exit 1
fi

VERSION="$(python3 scripts/releaseTooling.py --plist-version "${INFO_PLIST}")"
if [[ "${VERSION}" != "${sourceVersion}" ]]; then
    echo "error: bundle version differs from source version" >&2
    exit 1
fi

ARCHS="$(lipo -archs "${EXECUTABLE_PATH}")"
if [[ ! "${ARCHS}" =~ ^(arm64|x86_64)(\ (arm64|x86_64))?$ ]]; then
    echo "error: unsupported package architectures" >&2
    exit 1
fi
ARCH_LABEL="${ARCHS// /-}"
ZIP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}-macos-${ARCH_LABEL}.zip"

mkdir -p "${DIST_DIR}"
if [[ -e "${ZIP_PATH}" || -L "${ZIP_PATH}" || -e "${ZIP_PATH}.sha256" || -L "${ZIP_PATH}.sha256" ]]; then
    echo "error: package assets already exist; review them before choosing a new output" >&2
    exit 1
fi

umask 077
packageTempDir="$(mktemp -d "${DIST_DIR}/.package.XXXXXXXX")"
trap 'rm -rf -- "${packageTempDir}"' EXIT

codesign --verify --deep --strict "${APP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${packageTempDir}/package.zip"
python3 scripts/releaseTooling.py --install-package "${packageTempDir}/package.zip" "${ZIP_PATH}"

echo "Created ${ZIP_PATH}"
echo "Created ${ZIP_PATH}.sha256"
