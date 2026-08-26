# USB-C out-of-band access for a console-server Pi

One USB-C cable from a laptop to a Raspberry Pi 4 gives two things at once:

- **NCM** — a USB Ethernet link. The laptop gets an address by DHCP and can
  `ssh` in with no site network at all.
- **ACM** — a serial console on `/dev/ttyGS0`, which works before the network
  is up and while it is broken. A console server with no console of its own is
  a gap worth closing, and this closes it with the same cable.

Chosen over a per-station Wi-Fi AP because it needs no infrastructure, raises
no rogue-AP policy question in a datacentre, and does not consume `eth0`.

## What the laptop does and does not get

Verified on macOS 26 (Tahoe) against a Pi 4 Model B:

| | |
|---|---|
| address | `192.168.44.x` by DHCP, automatic |
| default route | **unchanged** — the laptop's internet stays on its own Wi-Fi |
| DNS | **unchanged** — none is offered on this link |
| route to `10.41.0.0/16` | offered via DHCP option 121, so the same cable reaches every node behind the Pi |

`traceroute` from the laptop to a node two hops away: `192.168.44.1` (0.9 ms,
the Pi over USB) then `10.41.0.208` (7.0 ms, over HaLow).

`.local` names still resolve — mDNS is multicast and does not need a DNS
server, so `ssh alan@<host>.local` works over the link.

## Install

1. `/boot/firmware/config.txt` — add under `[all]`:

       dtoverlay=dwc2,dr_mode=peripheral

   **The `otg_mode=1` and `dtoverlay=dwc2,dr_mode=host` lines already in that
   file sit under `[cm4]` and `[cm5]` and do not apply to a Pi 4 Model B.** A
   Pi 4 Model B has no dwc2 overlay at all until this line is added; reading
   those lines out of the file with `grep -n` and missing the section headers
   is an easy way to conclude the opposite.

2. Reboot. `/sys/class/udc/` must then contain `fe980000.usb`.

3. Install the files:

       install -m 0755 usb-gadget-oob.sh      /usr/local/sbin/usb-gadget-oob.sh
       install -m 0644 usb-gadget-oob.service /etc/systemd/system/
       install -m 0644 86-nm-manage-usb-gadget.rules /etc/udev/rules.d/
       install -m 0644 usb-oob-dnsmasq.conf   /etc/NetworkManager/dnsmasq-shared.d/usb-oob.conf
       udevadm control --reload

4. NetworkManager profile:

       nmcli con add type ethernet ifname usb0 con-name usb-oob \
         ipv4.method shared ipv4.addresses 192.168.44.1/24 \
         ipv4.never-default yes ipv6.method ignore connection.autoconnect yes

5. Enable:

       systemctl enable --now serial-getty@ttyGS0.service
       systemctl enable usb-gadget-oob.service

## Two things that will otherwise waste an hour

**NetworkManager refuses to manage USB gadget interfaces.** It ships
`/usr/lib/udev/rules.d/85-nm-unmanaged.rules` with

    # USB gadget device. Unmanage by default, since whatever created it
    # might want to set it up itself (e.g. activate an ipv4.method=shared
    # connection).
    ENV{DEVTYPE}=="gadget", ENV{NM_UNMANAGED}="1"

`nmcli dev status` then reports `usb0 ... unmanaged` and the profile never
activates. `86-nm-manage-usb-gadget.rules` overrides it.

**A gadget netdev does not assert carrier until it is administratively up**,
and NetworkManager will not touch a device it sees as carrier-less — it
reports `unavailable` and stops. Chicken and egg. `usb-gadget-oob.sh` breaks it
by running `ip link set usb0 up` itself after binding the UDC.

## Attaching to the console shows a blank screen — press Enter

`agetty` prints its banner and `login:` **once**, when it starts. Anything that
consumes that output — an earlier session, a script reading the port — takes it
with it, and the next person to attach sees an empty screen with a live,
healthy console behind it.

    screen /dev/cu.usbmodem<N> 115200     # blank
    <press Enter>                          # dkmstest login:

Confirmed rather than assumed: `agetty` was `Ss+` on `ttyGS0` the whole time
and the tty was in normal canonical mode. If a fresh prompt is wanted without
touching the port (e.g. someone is already attached), restart the unit from
another session:

    systemctl restart serial-getty@ttyGS0.service

**Do not write to a console that is sitting at a `Password:` prompt.** Anything
piped to `/dev/ttyGS0` at that moment is consumed as the password and lands in
the journal as `FAILED LOGIN`. Found the obvious way.

**On macOS the port is exclusive.** A `screen` session holds
`/dev/cu.usbmodem<N>`, and anything else opening it gets `resource busy`. Check
with `lsof /dev/cu.usbmodem<N>` and read **lsof's own exit code** — 1 means
nothing holds it. Piping lsof into `head` throws that status away, so
`lsof ... | head || echo free` always reports free.

## Power

The Pi 4's USB-C port is both power input and the gadget port, so a board
powered over USB-C must be moved to the laptop, not connected in addition to
its supply. Measured on a MacBook Air: `vcgencmd get_throttled` stayed `0x0`
across a full boot with the HaLow HAT and both radios running, so that laptop
supplies enough. **Check it per laptop** — a non-zero result means the supply
is not adequate and the board should be powered over the GPIO header instead,
leaving USB-C for data only.

The four USB-A ports are on the VL805 xHCI controller and are unaffected by
putting the USB-C port into peripheral mode: USB-serial adapters keep working.
