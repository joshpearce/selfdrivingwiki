#!/usr/bin/env bash
#
# copy-wiki-data.sh — copy Self Driving Wiki data from this Mac to another,
# so the app on the other Mac loads every wiki exactly as it does here.
#
# All wiki data lives in a single App Group container directory:
#
#     ~/Library/Group Containers/<group-id>/
#       ├── <ULID>.sqlite (+ -wal/-shm)   one SQLite DB per wiki (pages,
#       │                                 attachments, images, bookmarks — all
#       │                                 inside the DB, no loose asset files)
#       ├── wikis.json                    the registry: which wikis exist, MRU,
#       │                                 home pages — WITHOUT THIS the app sees
#       │                                 no wikis, so it is always copied
#       └── *.json                        app config (non-secret; API keys/tokens
#                                         live in the login Keychain, not here)
#
# The destination Mac MUST run a build that uses the SAME App Group id (it is
# baked in at build/sign time). The signed "Self Driving Wiki.app" uses
# group.com.jjpdev.wiki; a fresh source build with no signing config defaults to
# group.org.sockpuppet.wiki. If the two Macs differ, set DEST_GROUP_ID.
#
# Secrets NOT copied (re-enter on the other Mac): anything in the login Keychain,
# and the optional podcast token at
#   ~/Library/Application Support/SelfDrivingWiki/podcast-bearer-token.json
#
# Usage:
#   scripts/copy-wiki-data.sh user@other-mac.local        # push over SSH (rsync)
#   scripts/copy-wiki-data.sh /Volumes/USB/wiki-backup    # copy to a local dir / drive
#   scripts/copy-wiki-data.sh --dry-run user@other-mac.local
#
# Env overrides:
#   GROUP_ID=group.org.sockpuppet.wiki   source container group id (auto-detected)
#   DEST_GROUP_ID=group.com.jjpdev.wiki  destination group id (defaults to GROUP_ID)
#   APP_NAME="Self Driving Wiki"         running app to quit before copying
#
set -euo pipefail

APP_NAME="${APP_NAME:-Self Driving Wiki}"
GROUP_CONTAINERS="$HOME/Library/Group Containers"

# ---- parse args -------------------------------------------------------------
DRY_RUN=0
DEST=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,44p' "$0"; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) DEST="$arg" ;;
  esac
done

if [[ -z "$DEST" ]]; then
  echo "error: no destination given." >&2
  echo "usage: $0 [--dry-run] <user@host | /local/path>" >&2
  exit 2
fi

# ---- locate the source container --------------------------------------------
# Prefer an explicit GROUP_ID; otherwise auto-detect the group.*.wiki container
# that actually holds a wikis.json registry.
if [[ -n "${GROUP_ID:-}" ]]; then
  SRC="$GROUP_CONTAINERS/$GROUP_ID"
else
  SRC=""
  for dir in "$GROUP_CONTAINERS"/group.*wiki*; do
    if [[ -f "$dir/wikis.json" ]]; then
      if [[ -n "$SRC" ]]; then
        echo "error: multiple wiki containers found; set GROUP_ID to pick one:" >&2
        ls -d "$GROUP_CONTAINERS"/group.*wiki* >&2
        exit 1
      fi
      SRC="$dir"
    fi
  done
fi

if [[ -z "$SRC" || ! -d "$SRC" ]]; then
  echo "error: no wiki data container found under $GROUP_CONTAINERS" >&2
  echo "       (looked for a group.*.wiki directory containing wikis.json)" >&2
  echo "       set GROUP_ID explicitly if your group id is non-standard." >&2
  exit 1
fi
GROUP_ID="$(basename "$SRC")"
DEST_GROUP_ID="${DEST_GROUP_ID:-$GROUP_ID}"

echo "Source container : $SRC"
echo "Source group id  : $GROUP_ID"
printf 'Wikis to copy    : '
ls "$SRC"/*.sqlite 2>/dev/null | wc -l | tr -d ' '
du -sh "$SRC" 2>/dev/null | awk '{print "Total size       : " $1}'
echo "Destination      : $DEST  (group id: $DEST_GROUP_ID)"
echo

# ---- quit the app so SQLite checkpoints cleanly -----------------------------
# Skipped under --dry-run so a preview never touches the running app or the DBs.
if [[ "$DRY_RUN" == 1 ]]; then
  echo "(dry run: not quitting \"$APP_NAME\" or checkpointing databases)"
else
  if osascript -e "application \"$APP_NAME\" is running" 2>/dev/null | grep -q true; then
    echo "Quitting \"$APP_NAME\" so its databases are checkpointed…"
    osascript -e "tell application \"$APP_NAME\" to quit" || true
    # give it a moment to flush and exit
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      osascript -e "application \"$APP_NAME\" is running" 2>/dev/null | grep -q true || break
      sleep 0.5
    done
  fi

  # Belt-and-suspenders: truncate each WAL into its DB so we copy a single
  # self-contained file even if the app was force-quit. Harmless if already clean.
  if command -v sqlite3 >/dev/null 2>&1; then
    for db in "$SRC"/*.sqlite; do
      [[ -e "$db" ]] || continue
      sqlite3 "$db" 'PRAGMA wal_checkpoint(TRUNCATE);' >/dev/null 2>&1 || true
    done
  fi
fi

# ---- copy -------------------------------------------------------------------
# Trailing slash on SRC copies the CONTENTS of the container into the dest
# container. --delete makes the destination an exact mirror.
RSYNC_OPTS=(-av --delete --exclude '.com.apple.containermanagerd.metadata.plist')
[[ "$DRY_RUN" == 1 ]] && RSYNC_OPTS+=(--dry-run)

if [[ "$DEST" == *:* || "$DEST" == *@* ]]; then
  # Remote: <user@host>. Target path is relative to the remote home dir.
  REMOTE_HOST="${DEST%%:*}"
  REMOTE_DIR="Library/Group Containers/$DEST_GROUP_ID/"
  echo "Ensuring remote directory exists…"
  [[ "$DRY_RUN" == 1 ]] || ssh "$REMOTE_HOST" "mkdir -p \"$REMOTE_DIR\""
  echo "rsync → $REMOTE_HOST:$REMOTE_DIR"
  rsync "${RSYNC_OPTS[@]}" "$SRC/" "$REMOTE_HOST:$REMOTE_DIR"
else
  # Local path / mounted drive.
  mkdir -p "$DEST"
  echo "rsync → $DEST/"
  rsync "${RSYNC_OPTS[@]}" "$SRC/" "$DEST/"
fi

echo
if [[ "$DRY_RUN" == 1 ]]; then
  echo "Dry run complete — no files were changed. Re-run without --dry-run to copy."
else
  echo "Done. Launch \"$APP_NAME\" on the other Mac; it reads wikis.json and loads the wikis."
  echo "If it shows no wikis, the destination build likely uses a different App Group id —"
  echo "set DEST_GROUP_ID to match that Mac's group.*.wiki directory and re-run."
fi
