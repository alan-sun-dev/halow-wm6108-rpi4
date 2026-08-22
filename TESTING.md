# Hardware test procedures

*[中文版](TESTING.zh-TW.md)*

Two procedures. The first is the one that is pending; the second is kept because
it is the test that produced the only passing result so far.

---

# 1. Retest on Raspberry Pi OS: the ack window and the init burst

**Status: pending.** This is the test the 2026-08-22 findings ask for. Nothing
here needs a card swap or a reflash — it runs on the Raspberry Pi OS card that is
already in the machine.

## What it is testing

Two independent questions, in order:

1. **Was the CMD53 write ack window ever wide enough?** Morse's own OpenWrt build
   clocks a floor of 250 padding bytes after the CRC of a non-block write. Stock
   `mm6108-2.0.1` defaults to 4, and the widest value tested here so far is 64.
2. **Is the 2-bit RX skew self-inflicted by the init training burst?** Those
   clocks are deliberately sent with CS deasserted, via a `SPI_CS_HIGH` flip. If
   that flip goes the wrong way on this kernel, the chip counts them as selected
   and its response framing is off from the start — which is exactly the constant,
   clock-independent offset that has been measured.

Both are now module parameters. See [NOTES.md](NOTES.md) for the derivation.

## Prerequisites

Any of the Raspberry Pi OS cards (Bookworm 6.6.51, Bookworm 6.12.93, Trixie
6.18.34) is fine — the failure fingerprint is identical on all three. Use
whichever is in the machine. What must be true:

- matching `linux-headers-$(uname -r)` installed;
- `/lib/firmware/morse/` holds `mm6108.bin` and `bcf_fgh100mhaamd.bin`;
- `/boot/firmware/config.txt` has `dtparam=spi=on` and
  `dtoverlay=mm610x-spi-sensecap`;
- a `morse_driver` worktree at tag `mm6108-2.0.1` (referred to below as
  `~/halow/morse_driver`).

Because the overlay is in `config.txt`, the module is auto-loaded at boot and
fails there first. Every run below therefore starts with `rmmod`.

## Rebuild with the current patch

`patches/morse-driver-2.0.1-rpi-spi.patch` changed on 2026-08-22 — it now carries
the new parameters and the instrumented ack-window failure path. Re-apply it from
a clean `spi.c`:

```sh
cd ~/halow/morse_driver
git checkout -- spi.c
patch -p1 < ~/halow-wm6108-rpi4/patches/morse-driver-2.0.1-rpi-spi.patch

make KERNEL_SRC=/lib/modules/$(uname -r)/build \
     CONFIG_WLAN_VENDOR_MORSE=m CONFIG_MORSE_SPI=y \
     CONFIG_MORSE_USER_ACCESS=y CONFIG_MORSE_VENDOR_COMMAND=y -j4
```

## A helper for the runs

Every run is the same shape, so define this once in the shell:

```sh
run() {                      # usage: run <tag> [extra module params...]
  local tag="$1"; shift
  sudo rmmod morse 2>/dev/null
  sudo dmesg -C
  sudo insmod morse.ko country=SG bcf=bcf_fgh100mhaamd.bin "$@"
  sleep 5
  dmesg > ~/retest-"$tag".log
  grep -iE 'morse|spi' ~/retest-"$tag".log | tail -30
}
```

Everything is left at the last failing configuration — 10 MHz overlay,
`bcf_fgh100mhaamd.bin`, `country=SG` — so that each run changes one thing.

## Step 0 — baseline, defaults only

```sh
run baseline spi_rx_lshift=2
```

The new parameters default to the previous behaviour, so this must reproduce the
old failure exactly. If it does not, stop: the patch changed something it should
not have, and every result after this would be uninterpretable.

Expected, verbatim to `logs/2026-08-22-bookworm-6.6.51-lshift-dmesg.log`:

```
morse_spi spi0.0: Loaded firmware from morse/mm6108.bin, size 468304, crc32 0xbe7b5c8f
morse_spi spi0.0: spi: cmd53_write fn=1 0x00004050:4 r=0x10050002 b=0xffffffff (ret:-71)
```

New in this build, and worth reading even on the baseline run:

```
morse_spi spi0.0: init: mode=0x… cs_high_default=… train=18 flip=1
morse_spi spi0.0: init: CS deasserted for training, mode=0x…
morse_spi spi0.0: init: CS polarity restored, mode=0x…
```

Those three lines say which `SPI_CS_HIGH` branch this kernel actually takes —
until now that was inference, not measurement. Record them.

## Step 1 — does the ack window matter?

One variable against the baseline:

```sh
run window512 spi_rx_lshift=2 spi_post_write_status_bytes=512
```

| what you see | what it means |
|---|---|
| firmware and BCF load, no `cmd53_write … ret:-71`, a phy appears | **The padding was the wall.** Morse's OpenWrt-only patch is the fix, and the release tarball's default of 4 is the bug. This reframes the whole issue #9 thread. |
| `find_data_ack failed: first non-0xff 0x05 … at +N of 512` with N > 64 | Same conclusion, and now you know the exact number the driver needs. Report N. |
| `find_data_ack failed: first non-0xff 0x… (code 0x…) at +N of 512` where the byte is not an accept token | The chip answers but with something else — read the following hex dump; this is a different failure from silence. |
| `find_data_ack failed: no non-0xff byte in the 512 bytes clocked after CRC` | **The padding hypothesis is dead.** That is a strong negative result: it also rules out Morse's own fix as the explanation. Worth reporting on its own. |

If this passes, jump to step 3 — but still run step 2 afterwards, because the
skew is a separate defect and will still be there.

## Step 2 — is the skew self-inflicted by the init burst?

Six runs. Read `morse rx:` in each and note the offset — the baseline signature is
`c0 7f ff ff`, i.e. 2 bits late.

```sh
run flipY_train18 spi_rx_lshift=2                                        # = baseline
run flipY_train0  spi_rx_lshift=2 spi_init_train_bytes=0
run flipY_train2  spi_rx_lshift=2 spi_init_train_bytes=2
run flipY_train17 spi_rx_lshift=2 spi_init_train_bytes=17
run flipY_train20 spi_rx_lshift=2 spi_init_train_bytes=20
run flipN_train18 spi_rx_lshift=2 spi_init_cs_flip=N
run flipN_train0  spi_rx_lshift=2 spi_init_cs_flip=N spi_init_train_bytes=0
```

| what you see | what it means |
|---|---|
| the offset moves with `spi_init_train_bytes` | **Found it.** The chip is counting the training clocks; the CS flip is going the wrong way on this kernel. |
| the offset disappears with `spi_init_cs_flip=N` but not with `train=0` | The flip itself is the problem, not the clocks. |
| `spi_rx_lshift=2` starts *breaking* a run that used to work | Same finding read from the other side — that run has no skew, so the compensation now over-corrects. Re-run it without `spi_rx_lshift`. |
| the offset is `c0 7f` in all seven runs | The init sequence is exonerated. The skew is upstream of anything the driver does, and step 3 becomes the next lead. |

## Step 3 — diff the live configuration against OpenMANET

With the SPI source known byte-identical between the two kernel trees, only the
running configuration is left to differ. Capture on Raspberry Pi OS:

```sh
dtc -I fs -O dts /proc/device-tree/soc/spi@7e204000 2>/dev/null > ~/retest-dt-rpios.dts
sudo cat /sys/kernel/debug/pinctrl/*gpio/pinmux-pins | sed -n '/pin 7 /,/pin 12 /p'
```

Then the same on the OpenMANET card (`dtc` may be absent there — dump the
properties raw instead):

```sh
for f in /proc/device-tree/soc/spi@7e204000/*; do echo "== $f"; hexdump -C "$f" | head -3; done
cat /sys/kernel/debug/pinctrl/*gpio/pinmux-pins | sed -n '/pin 7 /,/pin 12 /p'
```

What to look for: `cs-gpios`, `pinctrl-0`, `dmas`, and above all whether **GPIO8
is muxed ALT0 (native CE0) while also being used as a GPIO chip select**. Two
drivers on the same pin would explain a great deal.

## Step 4 — only if step 1 passed

Converge on OpenMANET's configuration one variable at a time, so that whatever
turns out to matter is attributable:

1. overlay `spi-max-frequency = <50000000>` — this alone changes the driver's
   computed `inter_block_delay_bytes` from 50 to 250;
2. then `enable_ext_xtal_init=1` — must come after writes work, since
   `mm610x_ext_xtal_init()` is itself a sequence of register writes;
3. then `bcf=bcf_default.bin` — what the passing OpenMANET run actually loaded.

## Archiving the result

Same shape as the existing entries in `logs/`:

```sh
cp ~/retest-*.log <repo>/logs/
uname -r; cat /etc/os-release; dpkg -l | grep linux-image
```

Write a `2026-XX-XX-<image>-environment.txt` alongside them recording kernel,
image, driver tag and patch, firmware CRC32s, the exact `insmod` line for each
run, and the outcome. The existing
`logs/2026-08-22-bookworm-6.6.51-environment.txt` is the template.

## Before transmitting anything

`country=SG` is in every command above and is not optional: the driver has no
`TW` regdomain, and `SG` (920–925 MHz / 4 MHz / 22 dBm) is the only built-in
region that fits the Taiwan NCC allocation. Confirm the radio attaches before
bringing up an AP.

---

# 2. Completed: testing the OpenMANET image on a SenseCAP M1

**Status: done, 2026-08-22 — it passed.** `wlh0` came up as an AP on SG at
22 dBm. Kept for reproduction; the result is archived in
`logs/2026-08-22-openmanet-1.8.0-*`.

Written to be readable from a phone while the Pi is running OpenWrt and the
machine that holds these notes is powered down.

## What is on the card

`openmanet-1.8.0-rpi4-mm6108-spi-squashfs-sysupgrade.img.gz`
sha256 `461aea8cc2805f64e83e68d1f45acdedad7bef5560861926a5de79a3489d8316`
from <https://github.com/OpenMANET/firmware/releases> (tag 1.8.0)

OpenWrt 24.10, kernel 6.6.138, morse driver `0-rel_mm6108_2_0_1_2026_Jun_11`.
Its overlay is already the WM1302 HAT pin map — RESET on gpio17 (pull-up),
SPI_INT on gpio5, WAKE/BUSY on gpio23/24, CS on gpio8 at 50 MHz.

Note that driver is *not* the plain git tag: the image is built through
`MorseMicro/morse-feed`, which applies SPI patches that are not in the tarball.
That turned out to matter — see [NOTES.md](NOTES.md).

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

## Recommended: run Claude Code on that laptop and SSH in

You already need a laptop on the other end of the Ethernet cable, so work from
there rather than trying to install Claude Code onto OpenWrt:

```sh
git clone https://github.com/alan-sun-dev/halow-wm6108-rpi4
cd halow-wm6108-rpi4
claude
```

Then `ssh root@192.168.1.1` from that laptop, run the commands below and read
the output together. This gives more context than any saved memory would - the
memory is a compressed summary, this repository is the full detail, including
every hypothesis that was eliminated and the measurements behind it.

**Why not install Claude Code on the OpenWrt box:**

- OpenWrt is built against **musl libc, not glibc**, and Claude Code's
  distributed binaries and native modules target glibc. That is the hard wall.
- OpenWrt is not a supported platform.
- It needs Node.js, and building native dependencies against musl tends to fail.
- The image comes up as a network appliance on LAN `192.168.1.1`; you would have
  to configure a WAN before it can reach the internet at all.
- You would have to authenticate again.

Even if all of that were solved, the Pi 4 would then be running OpenWrt, Node.js
and the HaLow driver you are trying to test, all at once.

**If you try anyway, run the test and save the dmesg output first.** Then, if
the install fails, you still have the result you came for. A copy of the memory
files is at `/boot/claude-memory/` on the card - just tell Claude to read
`/boot/claude-memory/`, no particular path is required.

## The three commands that matter

```sh
dmesg | grep -i morse
ls /sys/class/ieee80211/
iw dev
```

| what you see | what it means |
|---|---|
| `Morse Micro SPI device found, chip ID=0x0306`, firmware and BCF load, a phy appears | It works on this image. *(This is what happened.)* |
| `failed to init SPI with CMD63` | The skew is still there. |
| firmware and BCF load, then `cmd53_write ... (ret:-71)` and `find_data_ack failed` | Same failure as morse_driver issue #9. |

The driver in this image is stock as far as `spi_rx_lshift` goes — it has none —
so if the skew were present it would stop at CMD63 and never reach the write. It
did not, which is why the skew is known to be absent on this image.

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
