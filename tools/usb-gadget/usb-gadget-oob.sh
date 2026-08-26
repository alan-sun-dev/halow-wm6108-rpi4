#!/bin/sh
# USB-C composite gadget for local out-of-band access to a console-server Pi.
#
# One USB-C cable from a laptop gives two things at once:
#   NCM  -> a USB Ethernet link, so you can ssh in with no network at all
#   ACM  -> a serial console (/dev/ttyGS0), which works before the network is
#           up and while it is broken. A console server with no console of its
#           own is a gap worth closing, and this closes it with the same cable.
#
# Runs on Raspberry Pi 4 Model B. Requires `dtoverlay=dwc2,dr_mode=peripheral`
# in /boot/firmware/config.txt -- note that the otg_mode / dwc2 lines shipped
# in config.txt sit under [cm4] and [cm5] and do NOT apply to a Pi 4 Model B.
#
# The four USB-A ports are on the VL805 xHCI controller and are unaffected by
# putting the USB-C port into peripheral mode -- USB-serial adapters for the
# switches keep working.
set -eu

G=/sys/kernel/config/usb_gadget/oob
UDC_DIR=/sys/class/udc

case "${1:-up}" in
down)
    [ -d "$G" ] || { echo "no gadget at $G"; exit 0; }
    echo "" > "$G/UDC" 2>/dev/null || true
    rm -f "$G"/configs/c.1/ncm.usb0 "$G"/configs/c.1/acm.usb0
    rmdir "$G"/configs/c.1/strings/0x409 "$G"/configs/c.1 2>/dev/null || true
    rmdir "$G"/functions/ncm.usb0 "$G"/functions/acm.usb0 2>/dev/null || true
    rmdir "$G"/strings/0x409 "$G" 2>/dev/null || true
    echo "gadget torn down"
    exit 0
    ;;
up) ;;
*)  echo "usage: $0 [up|down]" >&2; exit 2 ;;
esac

[ -d "$G" ] && { echo "gadget already configured at $G"; exit 0; }

modprobe libcomposite
[ -d /sys/kernel/config/usb_gadget ] || { echo "configfs usb_gadget missing" >&2; exit 1; }
udc=$(ls "$UDC_DIR" 2>/dev/null | head -1)
[ -n "$udc" ] || { echo "no UDC in $UDC_DIR -- is dr_mode=peripheral set and rebooted?" >&2; exit 1; }

# Stable, locally-administered MACs derived from the Pi's own serial number, so
# the host does not invent a new network interface on every reconnect. Built
# from exactly the last 10 hex digits, left-padded, so the result is always a
# well-formed 6-octet address and never depends on the serial's length.
serial=$(tr -d '\0' < /proc/device-tree/serial-number 2>/dev/null || echo 0000000000000000)
hex=$(printf '%s' "$serial" | tr -dc '0-9a-fA-F' | tr 'A-F' 'a-f' | tail -c 10)
while [ ${#hex} -lt 10 ]; do hex="0$hex"; done
oct=$(printf '%s' "$hex" | sed 's/../&:/g; s/:$//')
DEV_MAC="02:$oct"             # the Pi's end
HOST_MAC="06:$oct"            # the laptop's end

mkdir -p "$G"
cd "$G"
echo 0x1d6b > idVendor            # Linux Foundation
echo 0x0104 > idProduct           # Multifunction Composite Gadget
echo 0x0100 > bcdDevice
echo 0x0200 > bcdUSB

mkdir -p strings/0x409
echo "$serial"                        > strings/0x409/serialnumber
echo "halow-oob"                      > strings/0x409/manufacturer
echo "$(hostname) console server"     > strings/0x409/product

mkdir -p configs/c.1/strings/0x409
echo "NCM network + ACM serial" > configs/c.1/strings/0x409/configuration
echo 250                        > configs/c.1/MaxPower

mkdir -p functions/ncm.usb0
echo "$DEV_MAC"  > functions/ncm.usb0/dev_addr
echo "$HOST_MAC" > functions/ncm.usb0/host_addr

mkdir -p functions/acm.usb0

ln -s functions/ncm.usb0 configs/c.1/
ln -s functions/acm.usb0 configs/c.1/

echo "$udc" > UDC

# Bring the interface up ourselves. A gadget netdev does not assert carrier
# until it is administratively up, and NetworkManager will not touch a device
# it sees as carrier-less -- it reports `unavailable` and never activates the
# profile. Chicken and egg; the script that created the interface is the right
# place to break it.
i=0
while [ ! -d /sys/class/net/usb0 ] && [ $i -lt 20 ]; do i=$((i+1)); sleep 0.1; done
if [ -d /sys/class/net/usb0 ]; then
    ip link set usb0 up
    echo "usb0 up (carrier $(cat /sys/class/net/usb0/carrier 2>/dev/null))"
else
    echo "usb0 did not appear within 2s" >&2
fi

echo "gadget bound to $udc  (dev $DEV_MAC / host $HOST_MAC)"
