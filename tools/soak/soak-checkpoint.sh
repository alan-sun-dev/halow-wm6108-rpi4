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
set -u

STATION=${STATION:-192.168.108.19}      # house-Wi-Fi management path, NOT the link under test
HALOW=${HALOW:-10.41.0.208}
AP=${AP:-10.41.254.1}
KH=${KH:-$HOME/.ssh/known_hosts_soak}
LABEL=${1:-unlabelled}

s() { ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KH" alan@"$STATION" "$@" 2>/dev/null; }
a() { ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KH" root@"$AP" "$@" 2>/dev/null; }

echo "================ SOAK CHECKPOINT: $LABEL ================"
echo "taken(laptop)      $(date -Iseconds)"

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
'

# AP-side view. A second, independently maintained set of counters -- the
# station's own numbers and the AP's should move together.
a "iw dev wlh0 station dump" | awk '/^Station/{p=($2=="9c:04:b6:ff:df:fe")} p' | awk '
  /rx packets/  {printf "%-18s %s\n", "ap_rx_packets", $3}
  /tx packets/  {printf "%-18s %s\n", "ap_tx_packets", $3}
  /rx bytes/    {printf "%-18s %s\n", "ap_rx_bytes", $3}
  /tx bytes/    {printf "%-18s %s\n", "ap_tx_bytes", $3}
  /tx retries/  {printf "%-18s %s\n", "ap_tx_retries", $3}
  /tx failed/   {printf "%-18s %s\n", "ap_tx_failed", $3}
  /expected thr/{printf "%-18s %s\n", "ap_expected_thr", $3}
  /connected ti/{printf "%-18s %s\n", "ap_assoc_uptime_s", $3}
  /MFP/         {printf "%-18s %s\n", "ap_mfp", $2}'
printf "%-18s %s\n" "ap_uptime" "$(a uptime | sed 's/^ *//')"

# Small, deliberately light sample: 20 pings at 3/s over HaLow, from the laptop,
# which reaches it through the AP bridge -- a different path from the management
# SSH, so the instrument is not sharing the medium with the thing it measures.
printf "%-18s %s\n" "ping_20x" "$(ping -c 20 -i 0.3 "$HALOW" 2>&1 | tail -2 | tr '\n' ' ' | sed 's/  */ /g')"
echo
