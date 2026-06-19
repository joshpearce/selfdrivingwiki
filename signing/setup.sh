#!/usr/bin/env bash
#
# signing/setup.sh — provision this machine to build + codesign Self Driving Wiki
# against YOUR Apple Developer account, then write signing/local.config.
#
#   ./signing/setup.sh [--prefix com.yourname] [--app-group group.com.yourname.wiki]
#
# Automates (via the `asc` CLI + keychain) everything that the App Store Connect
# API allows: discovering your team + dev cert (minting one if absent),
# registering this Mac, creating the two bundle ids + their App Groups
# capability, and creating + downloading both development provisioning profiles.
#
# The ONE step the API cannot do — creating the App Group identifier and binding
# it to the bundle ids — is done by you in the portal; the script pauses with
# exact instructions and resumes when you confirm.
#
# Prereqs: a paid Apple Developer membership, `asc` authenticated
# (`asc auth status`), and macOS `security`/`openssl`/`curl`. See
# ../plans/signing.md and ~/.apple_dev/GETTING_STARTED_GUIDE.md.
set -euo pipefail

# --- locate repo root (this script lives in signing/) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SIGNING_DIR="${SCRIPT_DIR}"
CONFIG_OUT="${SIGNING_DIR}/local.config"

# --- args ---
PREFIX=""
APP_GROUP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)    PREFIX="$2"; shift 2 ;;
    --app-group) APP_GROUP="$2"; shift 2 ;;
    -h|--help)   sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

say()  { printf '\033[1;34m→\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }
# json <jq-ish python expr on `d`> — read stdin JSON, print expr.
jget() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)"; }

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------
command -v asc >/dev/null  || die "asc not found — install it (brew) and run 'asc auth login' first."
command -v openssl >/dev/null || die "openssl not found."
asc auth status >/dev/null 2>&1 || die "asc is not authenticated — run 'asc auth login --name personal …' (see GETTING_STARTED_GUIDE.md A3/B1)."
ok "asc authenticated"

# ---------------------------------------------------------------------------
# 1. Choose identifiers
# ---------------------------------------------------------------------------
if [ -z "${PREFIX}" ]; then
  # Suggest a prefix from an existing bundle id if there is one.
  GUESS="$(asc bundle-ids list --output json 2>/dev/null | jget "next(('.'.join(b['attributes']['identifier'].split('.')[:2]) for b in d.get('data',[]) if b['attributes']['identifier'].count('.')>=2), 'com.example'))" 2>/dev/null || echo com.example)"
  printf 'Reverse-DNS prefix for your bundle ids [%s]: ' "${GUESS}"
  read -r PREFIX || true
  PREFIX="${PREFIX:-$GUESS}"
fi
BUNDLE_ID="${PREFIX}.WikiFS"
EXT_BUNDLE_ID="${PREFIX}.WikiFS.FileProvider"
APP_GROUP="${APP_GROUP:-group.${PREFIX}.wiki}"
say "Using:"
echo "    app bundle id : ${BUNDLE_ID}"
echo "    ext bundle id : ${EXT_BUNDLE_ID}"
echo "    app group     : ${APP_GROUP}"

# ---------------------------------------------------------------------------
# 2. Dev certificate (keychain identity)
# ---------------------------------------------------------------------------
DEV_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep 'Apple Development:' | head -1 | sed -E 's/^[ ]*[0-9]+\) [0-9A-F]+ "(.*)"$/\1/')" || true
if [ -n "${DEV_IDENTITY}" ]; then
  ok "found dev identity in keychain: ${DEV_IDENTITY}"
else
  say "no Apple Development identity in keychain — minting one via asc"
  CERTDIR="${HOME}/.apple_dev/wikifs-cert"; mkdir -p "${CERTDIR}"
  EMAIL="$(asc auth status --output json 2>/dev/null | jget "''" 2>/dev/null || true)"
  asc certificates create --certificate-type DEVELOPMENT --generate-csr \
    --common-name "Self Driving Wiki Dev" \
    --key-out "${CERTDIR}/dev.key" --csr-out "${CERTDIR}/dev.csr" \
    --output json | tee "${CERTDIR}/create.json" >/dev/null
  python3 -c "import json,base64; d=json.load(open('${CERTDIR}/create.json')); open('${CERTDIR}/dev.cer','wb').write(base64.b64decode(d['data']['attributes']['certificateContent']))"
  openssl x509 -inform DER -in "${CERTDIR}/dev.cer" -out "${CERTDIR}/dev.pem"
  # -legacy + a real password: OpenSSL 3.x default p12s fail Apple's MAC check,
  # and empty-password p12s fail too. (See GETTING_STARTED_GUIDE.md B3b.)
  openssl pkcs12 -export -legacy -inkey "${CERTDIR}/dev.key" -in "${CERTDIR}/dev.pem" \
    -out "${CERTDIR}/dev.p12" -passout pass:wikifs -name "Apple Development (wikifs)"
  curl -fsSL https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer -o "${CERTDIR}/wwdrg3.cer"
  security import "${CERTDIR}/wwdrg3.cer" -k "${HOME}/Library/Keychains/login.keychain-db" 2>/dev/null || true
  security import "${CERTDIR}/dev.p12" -k "${HOME}/Library/Keychains/login.keychain-db" \
    -P wikifs -T /usr/bin/codesign -T /usr/bin/security
  DEV_IDENTITY="$(security find-identity -v -p codesigning | grep 'Apple Development:' | head -1 | sed -E 's/^[ ]*[0-9]+\) [0-9A-F]+ "(.*)"$/\1/')"
  [ -n "${DEV_IDENTITY}" ] || die "cert minted but no valid identity in keychain (missing WWDR intermediate?)."
  ok "minted + imported: ${DEV_IDENTITY}"
fi
CERT_ID="$(asc certificates list --output json | jget "next((c['id'] for c in d['data'] if c['attributes']['certificateType']=='DEVELOPMENT'),'')")"
[ -n "${CERT_ID}" ] || die "no DEVELOPMENT certificate found in your account."

# ---------------------------------------------------------------------------
# 3. Register this Mac (Provisioning UDID — NOT the Hardware UUID)
# ---------------------------------------------------------------------------
UDID="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Provisioning UDID/{print $2}')"
[ -n "${UDID}" ] || die "could not read Provisioning UDID from system_profiler."
DEVICE_ID="$(asc devices list --output json | jget "next((x['id'] for x in d['data'] if x['attributes'].get('udid')=='${UDID}'),'')")"
if [ -n "${DEVICE_ID}" ]; then
  ok "this Mac already registered (${UDID})"
else
  DEVICE_ID="$(asc devices register --name "$(scutil --get ComputerName 2>/dev/null || echo 'My Mac')" \
    --platform MAC_OS --udid "${UDID}" --output json | jget "d['data']['id']")"
  ok "registered this Mac (${UDID})"
fi

# ---------------------------------------------------------------------------
# 4. Bundle ids + APP_GROUPS capability (idempotent)
# ---------------------------------------------------------------------------
ensure_bundle() {  # ident, name -> echoes resource id
  local ident="$1" name="$2" id
  id="$(asc bundle-ids list --output json | jget "next((b['id'] for b in d['data'] if b['attributes']['identifier']=='${ident}'),'')")"
  if [ -z "${id}" ]; then
    id="$(asc bundle-ids create --identifier "${ident}" --name "${name}" --platform MAC_OS --output json | jget "d['data']['id']")"
    say "created bundle id ${ident}" >&2
  fi
  # APP_GROUPS capability (ignore 'already exists' errors)
  asc bundle-ids capabilities add --bundle "${id}" --capability APP_GROUPS >/dev/null 2>&1 || true
  printf '%s' "${id}"
}
APP_RES="$(ensure_bundle "${BUNDLE_ID}" "Self Driving Wiki")"
EXT_RES="$(ensure_bundle "${EXT_BUNDLE_ID}" "Self Driving Wiki File Provider")"
ok "bundle ids ready (app=${APP_RES} ext=${EXT_RES})"
TEAM_ID="$(asc bundle-ids list --output json | jget "next((b['attributes'].get('seedId','') for b in d['data'] if b['id']=='${APP_RES}'),'')")"
[ -n "${TEAM_ID}" ] || die "could not determine Team/Seed ID."
ok "team / seed id: ${TEAM_ID}"

# ---------------------------------------------------------------------------
# 5. App Group — the ONE manual portal step (no API)
# ---------------------------------------------------------------------------
cat <<MANUAL

  ┌─ MANUAL STEP (App Store Connect API can't create App Groups) ────────────┐
  │ At https://developer.apple.com/account/resources/identifiers            │
  │   1. + → App Groups → Identifier: ${APP_GROUP}
  │   2. Open '${BUNDLE_ID}' → App Groups → Edit → tick ${APP_GROUP} → Save
  │   3. Open '${EXT_BUNDLE_ID}' → same → Save
  └────────────────────────────────────────────────────────────────────────┘
MANUAL
printf 'Press Return once the App Group is created AND bound to both bundle ids… '
read -r _ || true

# ---------------------------------------------------------------------------
# 6. Provisioning profiles (regenerate so the App Group is included)
# ---------------------------------------------------------------------------
make_profile() {  # name, bundle-res-id, out-path
  local name="$1" bundle="$2" out="$3" pid
  # Delete any existing profile of this name so it regenerates with current
  # capabilities (a profile made before the App Group binding omits it).
  for old in $(asc profiles list --output json | jget "' '.join(p['id'] for p in d['data'] if p['attributes']['name']=='${name}')"); do
    asc profiles delete --id "${old}" --confirm >/dev/null 2>&1 || true
  done
  pid="$(asc profiles create --name "${name}" --profile-type MAC_APP_DEVELOPMENT \
        --bundle "${bundle}" --certificate "${CERT_ID}" --device "${DEVICE_ID}" \
        --output json | jget "d['data']['id']")"
  asc profiles download --id "${pid}" --output "${out}" >/dev/null
  say "downloaded $(basename "${out}")"
}
make_profile "Self Driving Wiki Dev"              "${APP_RES}" "${SIGNING_DIR}/WikiFS.provisionprofile"
make_profile "Self Driving Wiki FileProvider Dev" "${EXT_RES}" "${SIGNING_DIR}/WikiFSFileProvider.provisionprofile"

# Verify the App Group made it into the app profile.
if security cms -D -i "${SIGNING_DIR}/WikiFS.provisionprofile" 2>/dev/null | grep -q "${APP_GROUP}"; then
  ok "App Group present in profile"
else
  warn "App Group ${APP_GROUP} NOT in the profile — re-check the portal binding (step 5), then re-run."
fi

# ---------------------------------------------------------------------------
# 7. Write signing/local.config
# ---------------------------------------------------------------------------
cat > "${CONFIG_OUT}" <<CFG
# signing/local.config — generated by signing/setup.sh. Safe to hand-edit.
TEAM_ID="${TEAM_ID}"
DEV_IDENTITY="${DEV_IDENTITY}"
BUNDLE_ID="${BUNDLE_ID}"
EXT_BUNDLE_ID="${EXT_BUNDLE_ID}"
APP_GROUP="${APP_GROUP}"
CFG
ok "wrote ${CONFIG_OUT}"
echo
ok "Done. Build with:  make run"
