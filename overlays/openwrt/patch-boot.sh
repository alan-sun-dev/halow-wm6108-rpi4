#!/usr/bin/env bash
#
# Patch a freshly flashed OpenWrt boot partition for the SenseCAP M1 mPCIe slot.
# Usage: sudo ./patch-boot.sh /path/to/mounted/boot   (the 64 MB FAT32 partition)
#
set -euo pipefail

BOOT="${1:?usage: $0 /path/to/mounted/boot}"
HERE="$(cd "$(dirname "$0")" && pwd)"

[[ -f "$BOOT/config.txt" && -d "$BOOT/overlays" ]] || {
	echo "$BOOT does not look like an OpenWrt/Raspberry Pi boot partition" >&2
	exit 1
}

# 1. stock mm610x-spi.dtbo is for Morse's EKH01 pin map; swap in the M1 one.
[[ -f "$BOOT/overlays/mm610x-spi.dtbo.orig" ]] || \
	cp -p "$BOOT/overlays/mm610x-spi.dtbo" "$BOOT/overlays/mm610x-spi.dtbo.orig"
cp "$HERE/mm610x-spi.dtbo" "$BOOT/overlays/mm610x-spi.dtbo"
echo "replaced overlays/mm610x-spi.dtbo (original kept as .orig)"

# 2. morse-ps.dtbo drives gpio5 as the reset line and gpio7 as async wakeup.
#    On this carrier gpio5 is the module's SPI_INT (an output *from* the module),
#    so that overlay would fight it. Power save needs pins the M1 does not wire
#    anyway, so drop it.
if grep -q '^dtoverlay=morse-ps' "$BOOT/distroconfig.txt"; then
	[[ -f "$BOOT/distroconfig.txt.orig" ]] || \
		cp -p "$BOOT/distroconfig.txt" "$BOOT/distroconfig.txt.orig"
	sed -i 's/^dtoverlay=morse-ps/#dtoverlay=morse-ps  # gpio5 is SPI_INT on this carrier/' \
		"$BOOT/distroconfig.txt"
	echo "disabled dtoverlay=morse-ps in distroconfig.txt"
fi

# 3. Slot power and a belt-and-braces reset release, applied by the firmware
#    before the kernel starts.
if ! grep -q 'halow-slot-power' "$BOOT/config.txt"; then
	[[ -f "$BOOT/config.txt.orig" ]] || cp -p "$BOOT/config.txt" "$BOOT/config.txt.orig"
	cat >> "$BOOT/config.txt" <<'CFG'

# SenseCAP M1 mPCIe slot: gpio18 gates power to the slot (halow-slot-power),
# gpio17 is RESET_N and is released by being floated, so it needs a pull-up.
gpio=18=op,dh
gpio=17=ip,pu
CFG
	echo "appended gpio= lines to config.txt"
fi

sync
echo "done"
