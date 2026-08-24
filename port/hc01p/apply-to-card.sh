#!/bin/bash
# Run on the Mac AFTER Raspberry Pi Imager has written the image and the boot
# partition has remounted.  Writes the first-boot payload onto it.
#
#   ./apply-to-card.sh [/Volumes/bootfs]
#
# Burn with NO customisation in Imager: Imager 2.x writes custom.toml, which
# this image's raspberrypi-sys-mods is too old to process.  firstrun.sh +
# cmdline.txt is the mechanism that does work here.
set -euo pipefail

BOOT="${1:-/Volumes/bootfs}"
SRC="$(cd "$(dirname "$0")" && pwd)/boot"

[ -d "$BOOT" ] || { echo "no boot partition at $BOOT" >&2; exit 1; }
[ -f "$BOOT/cmdline.txt" ] || { echo "$BOOT has no cmdline.txt - wrong volume?" >&2; exit 1; }
[ -f "$BOOT/firstrun.sh" ] && { echo "$BOOT already provisioned; re-burn first" >&2; exit 1; }

# The two secrets are not in git. Fill in secrets.env (see secrets.env.example)
# and they are substituted into the copies written to the card, never into the
# files in the working tree.
SECRETS="$(cd "$(dirname "$0")" && pwd)/secrets.env"
[ -f "$SECRETS" ] || { echo "missing $SECRETS - copy secrets.env.example and fill it in" >&2; exit 1; }
# shellcheck disable=SC1090
. "$SECRETS"
[ -n "${WIFI_PSK:-}" ] && [ "$WIFI_PSK" != "__WIFI_PSK__" ] || { echo "WIFI_PSK is not set in $SECRETS" >&2; exit 1; }
[ -n "${PASSWORD_HASH:-}" ] && [ "$PASSWORD_HASH" != "__PASSWORD_HASH__" ] || { echo "PASSWORD_HASH is not set in $SECRETS" >&2; exit 1; }

cp "$SRC/authorized_keys" "$SRC/eth0.nmconnection" "$BOOT/"
sed "s|__PASSWORD_HASH__|$PASSWORD_HASH|" "$SRC/firstrun.sh"      > "$BOOT/firstrun.sh"
sed "s|__WIFI_PSK__|$WIFI_PSK|"           "$SRC/sun.nmconnection" > "$BOOT/sun.nmconnection"
chmod +x "$BOOT/firstrun.sh"

if grep -q "__WIFI_PSK__\|__PASSWORD_HASH__" "$BOOT/firstrun.sh" "$BOOT/sun.nmconnection"; then
    echo "substitution failed, placeholders still present on the card" >&2; exit 1
fi

# One line, no newline games: read it, strip any previous copies of what we add,
# append ours.
CMDLINE=$(tr -d '\n' < "$BOOT/cmdline.txt")
CMDLINE=$(printf '%s' "$CMDLINE" \
    | sed -e 's/ *cfg80211\.ieee80211_regdom=[^ ]*//g' \
          -e 's/ *systemd\.run=[^ ]*//g' \
          -e 's/ *systemd\.run_success_action=[^ ]*//g' \
          -e 's/ *systemd\.unit=[^ ]*//g')
printf '%s cfg80211.ieee80211_regdom=TW systemd.run=/boot/firmware/firstrun.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target\n' \
    "$CMDLINE" > "$BOOT/cmdline.txt"

sync
echo "--- $BOOT/cmdline.txt ---"
cat "$BOOT/cmdline.txt"
echo "--- files ---"
ls -l "$BOOT/firstrun.sh" "$BOOT/authorized_keys" "$BOOT"/*.nmconnection
echo
echo "OK.  Eject the card, put it in the HT-HC01P's Pi, power on."
echo "It boots twice (resize, then firstrun) - allow ~3 minutes."
