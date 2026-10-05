#!/bin/bash
# Install a dev-signed Self Driving Wiki build from a `make dev-release` GitHub
# pre-release. Put this script next to the downloaded zip (and its .sha256) and
# run:   bash install-dev-build.sh [path/to/zip]
#
# No sudo needed for an admin account. Under sudo, the app is still installed
# owned by, and launched as, the invoking user: a root-launched app would use
# root's keychain and File Provider domains.
set -euo pipefail

APP_NAME="Self Driving Wiki"
DEST="/Applications/${APP_NAME}.app"
EXT_PATH="${DEST}/Contents/PlugIns/WikiFSFileProvider.appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

HERE="$(cd "$(dirname "$0")" && pwd)"
ZIP="${1:-}"
if [ -z "${ZIP}" ]; then
  ZIP="$(ls -t "${HERE}/${APP_NAME}"-dev-*-macos.zip 2>/dev/null | head -1 || true)"
fi
[ -f "${ZIP}" ] || { echo "✗ no '${APP_NAME}-dev-*-macos.zip' next to this script — pass its path"; exit 1; }

# Run user-facing steps as the real user even under sudo.
USER_NAME="${SUDO_USER:-$(id -un)}"
as_user() {
  if [ "$(id -u)" -eq 0 ] && [ "${USER_NAME}" != "root" ]; then
    sudo -u "${USER_NAME}" "$@"
  else
    "$@"
  fi
}

if [ -f "${ZIP}.sha256" ]; then
  (cd "$(dirname "${ZIP}")" && shasum -a 256 -c "$(basename "${ZIP}").sha256" >/dev/null) \
    || { echo "✗ checksum mismatch for ${ZIP}"; exit 1; }
  echo "✓ checksum OK"
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
ditto -x -k "${ZIP}" "${STAGE}"
[ -d "${STAGE}/${APP_NAME}.app" ] || { echo "✗ zip does not contain ${APP_NAME}.app"; exit 1; }
xattr -dr com.apple.quarantine "${STAGE}/${APP_NAME}.app" 2>/dev/null || true
codesign --verify --deep --strict "${STAGE}/${APP_NAME}.app" \
  || { echo "✗ signature check failed"; exit 1; }

# Quit the running app and its extension before replacing the bundle.
as_user osascript -e "quit app \"${APP_NAME}\"" >/dev/null 2>&1 || true
pkill -f "WikiFSFileProvider.appex" 2>/dev/null || true
sleep 1

rm -rf "${DEST}"
ditto "${STAGE}/${APP_NAME}.app" "${DEST}"
if [ "$(id -u)" -eq 0 ] && [ "${USER_NAME}" != "root" ]; then
  chown -R "${USER_NAME}:admin" "${DEST}"
fi
echo "✓ installed ${DEST}"

as_user "${LSREGISTER}" -f "${DEST}"
as_user pluginkit -a "${EXT_PATH}" || true
as_user pluginkit -e use -i "$(defaults read "${EXT_PATH}/Contents/Info" CFBundleIdentifier)" \
  -p com.apple.fileprovider-nonui >/dev/null 2>&1 || true
echo "✓ registered File Provider extension"

as_user open "${DEST}"
echo "✓ launched ${APP_NAME}"
