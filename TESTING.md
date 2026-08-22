# Hardware test procedures

*[中文版](TESTING.zh-TW.md)*

Three procedures, pending first. Sections 2 and 3 are done and are kept for
reproduction and because their reasoning is what later results are read against.

---

# 1. The A/B: run the userspace probe on the OpenMANET card

**Status: pending. This is the only experiment left.** Everything else has been
eliminated — see [NOTES.md](NOTES.md). The question it answers: the same board
shows a constant 2-bit offset on the chip's responses under Raspberry Pi OS and
none at all under OpenMANET, with the SPI driver source byte-identical between
the two kernel trees. Measuring the wire directly on the working image is the
only direct comparison left.

## Prepare *before* swapping the card

The probe is Python and needs `python3` plus the `spidev` module. A stock
OpenWrt image is unlikely to have either, and OpenMANET comes up as a LAN
appliance on 10.41.254.1 with no WAN, so `opkg update` will not reach the
internet. Fetch the packages onto the laptop first.

Target is **OpenWrt 24.10, `aarch64_cortex-a72`, kernel 6.6.138**. You need
`python3-light` (or `python3-base`) and `python3-spidev`, plus `kmod-spi-dev`.
OpenMANET publishes prebuilt packages at
<https://github.com/OpenMANET/packages-repo>; the OpenWrt 24.10 feed is the
fallback.

I have not been able to verify the exact package names or whether they are
already in the image — that needs the card booted. So the first thing to run
after swapping is the check below, and only then decide whether the ipks are
needed.

## After swapping in the card

```sh
ssh root@10.41.254.1

opkg list-installed | grep -iE 'python3|spi-dev'
ls /dev/spidev* 2>/dev/null
lsmod | grep -i spidev
```

If the packages are missing, `scp` the ipks over and `opkg install ./*.ipk`.

## Step 1 — the part that always works, no Python needed

Do this first, whatever the Python situation. It is directly comparable to
`logs/2026-08-22-bookworm-6.6.51-retest-dt-pinmux.txt`:

```sh
{
echo "=== uname ==="; uname -r
echo; echo "=== spi0 device-tree node ==="
for f in /proc/device-tree/soc/spi@7e204000/*; do
  n=$(basename "$f"); [ -d "$f" ] && { echo "  [child node] $n"; continue; }
  printf "%-22s " "$n"; hexdump -e '16/1 "%02x " "\n"' "$f" 2>/dev/null | head -1
done
echo; echo "=== pinmux 7..11 ==="
grep -E "^pin (7|8|9|10|11) " /sys/kernel/debug/pinctrl/*gpio*/pinmux-pins
echo; echo "=== morse lines from dmesg ==="
dmesg | grep -iE 'morse|spi0'
} > /tmp/openmanet-dt-pinmux.txt 2>&1
cat /tmp/openmanet-dt-pinmux.txt
```

Copy that file off the card before swapping back.

| what differs from the Raspberry Pi OS capture | what it means |
|---|---|
| the pin mux differs — e.g. GPIO8 not `gpio_out`, or 9/10/11 not `alt0` | that is the variable. The failing side is mux'd differently despite identical driver source. |
| `cs-gpios`, `pinctrl-0` or `dmas` differ | same conclusion, in the device tree rather than the mux. |
| both captures are equivalent | the difference is not in the visible configuration at all, and the skew has to come from timing the kernel does not describe. |

## Step 2 — the probe itself, if Python is available

Bind spidev to the chip select the same way as on Raspberry Pi OS. Do **not**
remove the overlay to get a spidev node — that would take the module's power and
reset with it.

```sh
rmmod mm6108_sdio 2>/dev/null            # note the module name on this image
echo spidev > /sys/bus/spi/devices/spi0.0/driver_override
echo spi0.0 > /sys/bus/spi/drivers/spidev/bind
ls -la /dev/spidev0.0
```

`driver_override` is a kernel SPI-core feature and is present in 6.6, so this
should work on OpenWrt too — but it is untested there, which is why step 1 comes
first and does not depend on it.

Then copy `tools/mmcspi.py` and `tools/discriminate.py` onto the card and run:

```sh
python3 discriminate.py
python3 mmcspi.py
```

Note `reset_module()` uses `pinctrl`, which is a Raspberry Pi OS utility and is
**not** on OpenWrt. Either pulse RESET_N by hand with whatever the image has —
`gpioset`, or writing to `/sys/class/gpio` — or accept that the chip is not
freshly reset and say so when recording the result.

| what you see | what it means |
|---|---|
| `CMD0 → R1=0x01 @bit8` — no offset | **The skew is host-side.** The same chip frames correctly under this image, so something in the Raspberry Pi OS configuration shifts it. Compare against step 1's capture to find what. |
| `CMD0 → R1=0x01 @bit10` — the same 2-bit offset | The skew is on the wire under *both* images, and the working driver simply tolerates it. That would mean `spi_rx_lshift` is treating a symptom, and the real difference is somewhere in how the driver handles the response — a much better lead than anything currently open. |
| no response at all | Check power and reset first: GPIO18 must be driven high on this carrier, and RESET_N released. |

Either of the first two outcomes is decisive. This is the rare experiment where
every result is worth having.

## Restore

Clear `driver_override`, unbind spidev, reload the morse module — or just
reboot, which restores everything since none of this is persistent.

---

# 2. Completed: retest on Raspberry Pi OS — the ack window and the init burst

**Status: done, 2026-08-22 — all six hypotheses eliminated, none of them the
cause.** Results in `logs/2026-08-22-bookworm-6.6.51-retest-*`. The procedure is
kept because it is the harness the instrumented driver was built for, and any
further parameter test on that card should follow it.

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

# 3. Completed: testing the OpenMANET image on a SenseCAP M1

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

OpenMANET comes up on **10.41.254.1 / 255.255.0.0** — a **/16**, not a /24 — and
runs a DHCP server on it (pool starts at .100, 150 leases). Do not plug it into a
home LAN that already has DHCP; connect the Pi's Ethernet directly to a laptop
and give the laptop a static address:

    IP 10.41.254.100   mask 255.255.0.0   router: leave empty

Leaving the router field empty keeps Wi-Fi as the laptop's route to the internet.

Then:

- Web UI: <http://10.41.254.1>
- SSH: `ssh root@10.41.254.1` — **root has no password** on a fresh image

**This address is not the OpenWrt default**, and earlier revisions of this file
said 192.168.1.1, which is wrong and cost an evening. The sources of truth:

- `OpenMANET/firmware`, `boards/common/general_diffconfig`:
  `CONFIG_TARGET_PREINIT_IP="10.41.254.1"`
- `OpenMANET/openmanetd`, `internal/network/random.go`:
  `FactoryMeshIP = "10.41.254.1"`
- `OpenMANET/openmanetd`, `testfixtures/setup-wizard/before/network`: `lan` is a
  static `10.41.254.1/16` on `br-lan`, and `br-lan` has `eth0` in it, so the
  built-in Ethernet really is LAN.

**The address changes once the setup wizard has run.** `openmanetd` randomises the
mesh IP on provisioning — that is what `FactoryMeshIP` exists to avoid colliding
with. So a card that has been through the wizard is somewhere else in
`10.41.0.0/16`, not on `.254.1`. To find it, set the laptop to `10.41.254.100/16`
and sweep the segment:

```sh
ping -c 3 10.41.255.255
arp -a | grep 10.41
```

If the laptop's interface shows a `169.254.x.x` address, it received no DHCP at
all — that is a link or cabling problem, not an addressing one.

## Recommended: run Claude Code on that laptop and SSH in

You already need a laptop on the other end of the Ethernet cable, so work from
there rather than trying to install Claude Code onto OpenWrt:

```sh
git clone https://github.com/alan-sun-dev/halow-wm6108-rpi4
cd halow-wm6108-rpi4
claude
```

Then `ssh root@10.41.254.1` from that laptop, run the commands below and read
the output together. This gives more context than any saved memory would - the
memory is a compressed summary, this repository is the full detail, including
every hypothesis that was eliminated and the measurements behind it.

**Why not install Claude Code on the OpenWrt box:**

- OpenWrt is built against **musl libc, not glibc**, and Claude Code's
  distributed binaries and native modules target glibc. That is the hard wall.
- OpenWrt is not a supported platform.
- It needs Node.js, and building native dependencies against musl tends to fail.
- The image comes up as a network appliance on LAN `10.41.254.1`; you would have
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
