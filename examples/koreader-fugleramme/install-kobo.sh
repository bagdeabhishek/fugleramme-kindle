#!/bin/sh
set -eu

usage() {
    echo "usage: $0 KOBO_MOUNT KOREADER_ZIP NICKELMENU_TGZ [SERVER_URL]" >&2
    exit 2
}

[ "$#" -ge 3 ] && [ "$#" -le 4 ] || usage

KOBO_MOUNT=${1%/}
KOREADER_ZIP=$2
NICKELMENU_TGZ=$3
SERVER_URL=${4:-}
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR=${KOBO_BACKUP_DIR:-"$PWD/kobo-backup-$STAMP"}
TARGET="$KOBO_MOUNT/.kobo/koreader"
CONF="$KOBO_MOUNT/.kobo/Kobo/Kobo eReader.conf"
DB="$KOBO_MOUNT/.kobo/KoboReader.sqlite"

[ -d "$KOBO_MOUNT/.kobo" ] || { echo "not a Kobo mount: $KOBO_MOUNT" >&2; exit 1; }
[ -f "$KOBO_MOUNT/.kobo/version" ] || { echo "Kobo version file is missing" >&2; exit 1; }
[ -f "$KOREADER_ZIP" ] || { echo "KOReader archive is missing: $KOREADER_ZIP" >&2; exit 1; }
[ -f "$NICKELMENU_TGZ" ] || { echo "NickelMenu archive is missing: $NICKELMENU_TGZ" >&2; exit 1; }
[ -f "$CONF" ] || { echo "Kobo configuration is missing: $CONF" >&2; exit 1; }
[ -f "$DB" ] || { echo "Kobo database is missing: $DB" >&2; exit 1; }
[ ! -e "$TARGET" ] || { echo "refusing to overwrite existing $TARGET" >&2; exit 1; }

mkdir -p "$BACKUP_DIR"
cp -p "$CONF" "$BACKUP_DIR/Kobo eReader.conf"
cp -p "$DB" "$BACKUP_DIR/KoboReader.sqlite"
cp -p "$KOBO_MOUNT/.kobo/version" "$BACKUP_DIR/version"
[ ! -f "$KOBO_MOUNT/metadata.calibre" ] || cp -p "$KOBO_MOUNT/metadata.calibre" "$BACKUP_DIR/metadata.calibre"
CONF_HASH=$(sha256sum "$CONF" | awk '{print $1}')

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT HUP INT TERM
unzip -q "$KOREADER_ZIP" 'koreader/*' -d "$STAGE"
[ -x "$STAGE/koreader/koreader.sh" ] || { echo "archive does not contain an executable koreader/koreader.sh" >&2; exit 1; }

mkdir -p "$TARGET"
cp -Rp "$STAGE/koreader/." "$TARGET/"
mkdir -p "$TARGET/plugins"
cp -Rp "$SCRIPT_DIR/fugleramme.koplugin" "$TARGET/plugins/"

mkdir -p "$KOBO_MOUNT/.adds/nm"
printf '%s\n' \
    'menu_item :main :KOReader :cmd_spawn :quiet:/mnt/onboard/.kobo/koreader/koreader.sh' \
    > "$KOBO_MOUNT/.adds/nm/fugleramme-koreader"
cp -p "$NICKELMENU_TGZ" "$KOBO_MOUNT/.kobo/KoboRoot.tgz"

if [ -n "$SERVER_URL" ]; then
    mkdir -p "$TARGET/settings"
    SERVER_URL=$(printf '%s' "$SERVER_URL" | sed 's:/*$::')
    case "$SERVER_URL" in
        *'"'*|*'\\'*) echo "server URL must not contain quotes or backslashes" >&2; exit 1 ;;
    esac
    printf 'return {\n    ["interval_seconds"] = 300,\n    ["server_url"] = "%s",\n}\n' "$SERVER_URL" \
        > "$TARGET/settings/fugleramme.lua"
fi

[ "$CONF_HASH" = "$(sha256sum "$CONF" | awk '{print $1}')" ] || {
    echo "Kobo configuration changed unexpectedly; stop and restore the backup" >&2
    exit 1
}

sync
echo "KOReader and Fugleramme staged successfully."
echo "Host backup: $BACKUP_DIR"
echo "Safely eject the Kobo and allow it to restart."
