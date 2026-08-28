#!/bin/bash
# Read-only soak checkpoint for the A1 station.
#
# Runs FROM THE LAPTOP so the station itself is never written to. It does not
# reboot, reload, restart NetworkManager, touch power save, or change the AP.
# Every command below is a read.
#
#   ./soak-checkpoint.sh [label] >> logs/<date>-a1-soak-checkpoints.txt
#
# The measurement set is fixed. Do not add or remove fields between runs, or
# the checkpoints stop being comparable.
#
# One amendment, 2026-08-28: three reconnect-history fields were APPENDED
# (disconnects_boot, beacon_loss_boot, longest_outage_s). Appending is the only
# change this rule allows, and only because none of the thirty existing fields
# moved or changed meaning -- every checkpoint already in the logs still compares
# against every checkpoint taken after it, and the older ones simply lack the
# three. Removing or redefining a field is still forbidden.
#
# The framing lines -- mgmt_path, mgmt_medium, checkpoint_status and any line
# starting `!!!!` -- are not measurements. They say whether the measurements
# below them can be trusted, and they may change without breaking anything.
#
# THIS SCRIPT FAILS LOUDLY AND EXITS NON-ZERO WHEN A BLOCK IS MISSING.
# On 2026-08-26 an earlier version wrote a checkpoint with exit 0 and 25 of its
# 30 fields blank: the station's out-of-band management address had gone away,
# and the ssh stderr went to /dev/null, so the failure was invisible. A
# checkpoint missing its subject is not a checkpoint, and it must not look
# like one in the log. Exit codes: 0 complete, 2 incomplete or unreachable.
set -u

HALOW=${HALOW:-10.41.0.208}
AP=${AP:-192.168.108.5}                 # the AP on the house LAN. 10.41.254.1 is
                                        # its HaLow side only and the laptop cannot reach it
STA_MAC=${STA_MAC:-9c:04:b6:ff:df:fe}   # the A1 station, as the AP sees it
KH=${KH:-$HOME/.ssh/known_hosts_soak}
LABEL=${1:-unlabelled}

# Management paths to the station, in preference order. The first is
# out-of-band (house Wi-Fi). The second IS the link under test: usable when
# nothing else is left, but then the ping below shares the medium with the ssh
# carrying the instrument, so it stops being an independent measurement. Which
# one was used is recorded in mgmt_medium.
STATION_CANDIDATES=${STATION_CANDIDATES:-"192.168.108.19 $HALOW"}
STATION=${STATION:-}

SSHOPTS=(-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new
         -o ServerAliveInterval=5 -o ServerAliveCountMax=4
         -o UserKnownHostsFile="$KH")
# A management path that answers but crawls is not a usable path. The station's
# house Wi-Fi came back at -86 dBm on 2026-08-26: `ssh <host> true` succeeded,
# the tool selected it, and the checkpoint then hung for minutes in the middle
# of the station block. Reachable is not the same as usable, so the probe is
# timed and a slow path is rejected like an unreachable one.
PROBE_MAX=${PROBE_MAX:-8}
ERR=$(mktemp -t soakerr) || exit 2
OUT=$(mktemp -t soakout) || exit 2
trap 'rm -f "$ERR" "$OUT"' EXIT

incomplete=0
# Loud on stdout so it lands in the log next to the fields it invalidates, and
# on stderr so it is visible when stdout is redirected.
warn() { printf '!!!! %s\n' "$*"; printf '!!!! %s\n' "$*" >&2; incomplete=1; }
die()  { warn "$*"; printf '%-18s %s\n' "checkpoint_status" "FAILED"; exit 2; }

s() { ssh "${SSHOPTS[@]}" alan@"$STATION" "$@" 2>"$ERR"; }
a() { ssh "${SSHOPTS[@]}" root@"$AP" "$@" 2>"$ERR"; }

echo "================ SOAK CHECKPOINT: $LABEL ================"
echo "taken(laptop)      $(date -Iseconds)"

# ---- preflight: find a live management path before measuring anything -------
probe() {  # $1 = host. Sets PROBE_SECS. Returns ssh's status.
  local t0 t1 rc
  t0=$(date +%s)
  ssh "${SSHOPTS[@]}" alan@"$1" true 2>"$ERR"; rc=$?
  t1=$(date +%s)
  PROBE_SECS=$((t1 - t0))
  return $rc
}

if [ -n "$STATION" ]; then
  probe "$STATION" \
    || die "station $STATION (given explicitly) is not reachable: $(tr -d '\r' < "$ERR" | tail -1)"
  [ "$PROBE_SECS" -le "$PROBE_MAX" ] \
    || warn "station $STATION answered but took ${PROBE_SECS}s (limit ${PROBE_MAX}s) -- it was given explicitly, so it is being used anyway"
else
  for h in $STATION_CANDIDATES; do
    if probe "$h"; then
      if [ "$PROBE_SECS" -le "$PROBE_MAX" ]; then STATION=$h; break; fi
      warn "management path $h answers but took ${PROBE_SECS}s (limit ${PROBE_MAX}s) -- too slow to carry a checkpoint, skipping"
      continue
    fi
    warn "management path $h is down: $(tr -d '\r' < "$ERR" | tail -1)"
  done
  [ -n "$STATION" ] || die "no management path to the station: tried $STATION_CANDIDATES"
  # A path being down is a fact about the bench, not a broken checkpoint --
  # only having none is. Reset so a fallback still scores OK.
  incomplete=0
fi

case "$STATION" in
  10.41.*) MEDIUM="halow -- SAME MEDIUM AS THE LINK UNDER TEST, ping_20x is not independent" ;;
  *)       MEDIUM="out-of-band (house Wi-Fi)" ;;
esac
printf '%-18s %s\n' "mgmt_path" "$STATION"
printf '%-18s %s\n' "mgmt_medium" "$MEDIUM"

ssh "${SSHOPTS[@]}" root@"$AP" true 2>"$ERR" \
  || die "AP $AP is not reachable: $(tr -d '\r' < "$ERR" | tail -1)"

# ---- station-side view -----------------------------------------------------
# The remote block ends in a sentinel. Without one, a block that dies halfway
# through is indistinguishable from a block that had nothing to say.
s '
echo "taken(station)     $(date -Iseconds)"
echo "uptime_seconds     $(cut -d. -f1 /proc/uptime)"
echo "uptime_human       $(uptime -p)"
echo "boot_id            $(cat /proc/sys/kernel/random/boot_id)"
echo "kernel             $(uname -r)"
for m in morse dot11ah; do
  # modinfo lives in /usr/sbin: off a non-root PATH, so call it through sudo
  sudo modinfo "$m" 2>/dev/null | awk -v m="$m" "
    /^filename:/   {printf \"%-18s %s\n\", m\"_filename\", \$2}
    /^version:/    {printf \"%-18s %s\n\", m\"_version\", \$2}
    /^srcversion:/ {printf \"%-18s %s\n\", m\"_srcversion\", \$2}
    /^vermagic:/   {sub(/^vermagic: */,\"\"); printf \"%-18s %s\n\", m\"_vermagic\", \$0}"
done
IF=$(for i in /sys/class/net/*/device/driver; do d=$(readlink -f $i); case "$d" in *morse_spi*) echo $i | cut -d/ -f5;; esac; done)
echo "halow_iface        $IF"
echo "halow_mac          $(cat /sys/class/net/$IF/address)"
echo "halow_ip           $(ip -4 -br addr show $IF | awk "{print \$3}")"
echo "power_save         $(/sbin/iw dev $IF get power_save | sed "s/.*: //")"
/sbin/iw dev $IF station dump | awk "
  /connected time/ {printf \"%-18s %s\n\", \"assoc_uptime_s\", \$3}
  /tx retries/     {printf \"%-18s %s\n\", \"sta_tx_retries\", \$3}
  /tx failed/      {printf \"%-18s %s\n\", \"sta_tx_failed\", \$3}
  /rx drop misc/   {printf \"%-18s %s\n\", \"sta_rx_drop_misc\", \$4}
  /tx bitrate/     {printf \"%-18s %s %s %s %s\n\", \"sta_tx_bitrate\", \$3, \$4, \$5, \$6}
  /rx bitrate/     {printf \"%-18s %s %s %s %s\n\", \"sta_rx_bitrate\", \$3, \$4, \$5, \$6}
  /signal:/        {printf \"%-18s %s\n\", \"sta_signal_dbm\", \$2}"
P=/sys/class/spi_master/spi0/spi0.0/statistics
for f in messages bytes errors timedout; do printf "%-18s %s\n" "spi_$f" "$(cat $P/$f)"; done
printf "%-18s %s\n" "dmesg_failures" "$(sudo dmesg | grep -icE "cmd63|eproto|crc error|read fail|write fail|probe fail")"
printf "%-18s %s\n" "dmesg_control"  "$(sudo dmesg | grep -c morse_spi)"
# Reconnect history. A checkpoint says how long the CURRENT association has
# lasted; it cannot say how many earlier ones ended. That history was sitting in
# the station journal unread through the whole soak, and the maturity review of
# 2026-08-27 called out a missing reconnect counter while the counter existed.
# These three are reads of that journal. They add no traffic to the link under
# test beyond the ssh already carrying this block.
#
# Field names are kept at or under 18 characters on purpose -- the column width
# of every other field in this checkpoint.
#
# `-o short-unix` is not a style choice. It makes the timestamp an epoch second
# so the outage arithmetic needs no date parsing: the first attempt at this used
# `date -j -f` on macOS, which failed on every line and printed eleven outages of
# "0 s" with no error anywhere. A zero that means "not measured" must never be
# printable, so an unreadable journal prints UNREADABLE and a genuine zero prints 0.
JU=$(sudo journalctl -b --no-pager -o short-unix -u wpa_supplicant 2>/dev/null | grep "$IF: CTRL-EVENT-")
if [ -z "$JU" ]; then
  for f in disconnects_boot beacon_loss_boot longest_outage_s; do
    printf "%-18s %s\n" "$f" "UNREADABLE -- no wpa_supplicant journal for this boot"
  done
else
  printf "%-18s %s\n" "disconnects_boot" "$(printf "%s\n" "$JU" | grep -c "CTRL-EVENT-DISCONNECTED")"
  printf "%-18s %s\n" "beacon_loss_boot" "$(printf "%s\n" "$JU" | grep -c "CTRL-EVENT-BEACON-LOSS")"
  printf "%s\n" "$JU" | grep -E "CTRL-EVENT-(DISCONNECTED|CONNECTED)" | awk "
    { e=int(\$1)
      if (\$0 ~ /CTRL-EVENT-DISCONNECTED/) { if (!open) { open=1; d=e } }
      else if (\$0 ~ /CTRL-EVENT-CONNECTED/ && open) { g=e-d; if (g>max) max=g; open=0 } }
    END { if (open) printf \"%-18s %s\n\", \"longest_outage_s\", max+0\" -- STILL DOWN at capture\"
          else       printf \"%-18s %s\n\", \"longest_outage_s\", max+0 }"
fi
echo "__station_block_end__"
' > "$OUT"
rc=$?
grep -v '^__station_block_end__$' "$OUT"
if [ $rc -ne 0 ]; then
  warn "station block exited $rc: $(tr -d '\r' < "$ERR" | tail -1)"
elif ! grep -q '^__station_block_end__$' "$OUT"; then
  warn "station block stopped early -- the fields above are partial: $(tr -d '\r' < "$ERR" | tail -1)"
fi
# 25 measurement lines when whole. Fewer means a field went missing quietly.
n=$(grep -vc '^__station_block_end__$' "$OUT")
[ "$n" -ge 25 ] || warn "station block produced $n measurement lines, expected 25"

# ---- AP-side view ----------------------------------------------------------
# A second, independently maintained set of counters -- the station's own
# numbers and the AP's should move together.
if ! a "iw dev wlh0 station dump" > "$OUT"; then
  warn "AP station dump failed: $(tr -d '\r' < "$ERR" | tail -1)"
elif ! grep -qi "^Station $STA_MAC" "$OUT"; then
  warn "the AP's station dump does not list $STA_MAC -- the station is not associated"
fi
awk -v mac="$STA_MAC" '/^Station/{p=(tolower($2)==tolower(mac))} p' "$OUT" | awk '
  /rx packets/  {printf "%-18s %s\n", "ap_rx_packets", $3}
  /tx packets/  {printf "%-18s %s\n", "ap_tx_packets", $3}
  /rx bytes/    {printf "%-18s %s\n", "ap_rx_bytes", $3}
  /tx bytes/    {printf "%-18s %s\n", "ap_tx_bytes", $3}
  /tx retries/  {printf "%-18s %s\n", "ap_tx_retries", $3}
  /tx failed/   {printf "%-18s %s\n", "ap_tx_failed", $3}
  /expected thr/{printf "%-18s %s\n", "ap_expected_thr", $3}
  /connected ti/{printf "%-18s %s\n", "ap_assoc_uptime_s", $3}
  /MFP/         {printf "%-18s %s\n", "ap_mfp", $2}'
ap_up=$(a uptime | sed 's/^ *//')
[ -n "$ap_up" ] || warn "AP uptime came back empty: $(tr -d '\r' < "$ERR" | tail -1)"
printf "%-18s %s\n" "ap_uptime" "$ap_up"

# Small, deliberately light sample: 20 pings at 3/s over HaLow, from the
# laptop. Independent of the management ssh only while mgmt_medium says
# out-of-band -- read that line before reading this one.
printf "%-18s %s\n" "ping_20x" "$(ping -c 20 -i 0.3 "$HALOW" 2>&1 | tail -2 | tr '\n' ' ' | sed 's/  */ /g')"

if [ "$incomplete" -eq 0 ]; then
  printf '%-18s %s\n' "checkpoint_status" "OK"
else
  printf '%-18s %s\n' "checkpoint_status" "INCOMPLETE -- see the !!!! lines above"
fi
echo
[ "$incomplete" -eq 0 ] || exit 2
