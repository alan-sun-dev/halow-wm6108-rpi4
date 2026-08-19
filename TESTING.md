# Testing the OpenMANET image on a SenseCAP M1

*[中文版](TESTING.zh-TW.md)*

Written to be readable from a phone while the Pi is running OpenWrt and the
machine that holds these notes is powered down.

## What is on the card

`openmanet-1.8.0-rpi4-mm6108-spi-squashfs-sysupgrade.img.gz`
sha256 `461aea8cc2805f64e83e68d1f45acdedad7bef5560861926a5de79a3489d8316`
from <https://github.com/OpenMANET/firmware/releases> (tag 1.8.0)

OpenWrt 24.10, kernel 6.6.138, morse driver `0-rel_mm6108_2_0_1_2026_Jun_11`.
Its overlay is already the WM1302 HAT pin map — RESET on gpio17 (pull-up),
SPI_INT on gpio5, WAKE/BUSY on gpio23/24, CS on gpio8 at 50 MHz.

One line was appended to `config.txt`, and it is the only change:

```
gpio=18=op,dh
```

That is the SenseCAP M1's mPCIe slot power enable. It is not part of the HAT pin
map and appears in no upstream overlay, so without it the slot has no power and
the module is invisible on the bus.

## Swapping the card

1. Shut the running system down properly: `sudo poweroff`. Do not pull the plug —
   the original card carries a working LoRaWAN gateway.
2. Unplug power, open the case, swap the microSD.
3. Connect Ethernet — read the next section first.
4. Power on.

**The original card is not modified by any of this.** Putting it back restores
everything exactly as it was.

## Getting in

OpenMANET comes up on **192.168.1.1** and runs its own DHCP server, so do not
plug it into a home LAN that already has one — connect the Pi's Ethernet
directly to a laptop instead and give the laptop a static address:

    IP 192.168.1.100   mask 255.255.255.0

Then:

- Web UI: <http://192.168.1.1>
- SSH: `ssh root@192.168.1.1` — **root has no password** on a fresh image

## The three commands that matter

```sh
dmesg | grep -i morse
ls /sys/class/ieee80211/
iw dev
```

| what you see | what it means |
|---|---|
| `Morse Micro SPI device found, chip ID=0x0306`, firmware and BCF load, a phy appears | **It works.** The 2-bit skew was coming from the 6.18 kernel's `spi-bcm2835`, not the hardware. |
| `failed to init SPI with CMD63` | The skew is still there. It is not the SPI controller driver — it is at the hardware level. |
| firmware and BCF load, then `cmd53_write ... (ret:-71)` and `find_data_ack failed` | Same failure as morse_driver issue #9, now reproduced across two operating systems and three kernels. |

The driver in this image is stock and has no `spi_rx_lshift`, so if the skew is
present it stops at CMD63 and never reaches the write. All three outcomes are
useful results.

## Capture this before swapping back

```sh
dmesg | grep -i -A2 -B2 morse > /tmp/morse.log
cat /tmp/morse.log
```

Photograph or copy the output. That is the whole point of the exercise.

## Before transmitting anything

This image defaults to the US regulatory domain, 902–928 MHz. In Taiwan the NCC
allocation is **920–925 MHz only**. The driver's `SG` regdomain is
920–925 MHz / 4 MHz / 22 dBm, which fits exactly:

```sh
uci set wireless.@wifi-device[0].country='SG'
uci commit wireless
wifi reload
```

Confirm the radio attaches first, set the region, and only then bring up an AP.

## Getting back

Shut down, swap the original card back in, power on. The LoRaWAN gateway, the
driver work under `~/halow`, and the full bring-up log are all still there —
nothing on that card was touched.
