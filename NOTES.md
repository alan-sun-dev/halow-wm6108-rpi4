# Wio-WM6108 (MM6108A1) on SenseCAP M1 — bring-up state, 2026-08-19

*[中文版](NOTES.zh-TW.md)*

## 2026-08-22 follow-up: four end-to-end tests

Same board (SenseCAP M1 mPCIe slot with Wio-WM6108, WM1302 HAT pinout), same driver release (`mm6108-2.0.1` with the patches in `./patches`), same firmware and BCF binaries (`mm6108.bin` crc32 `0xbe7b5c8f`, `bcf_fgh100mhaamd.bin` crc32 `0x941b2a82`). Only the kernel and its patch stack change:

| Kernel | Tree / packaging | Result |
|---|---|---|
| **6.6.138** | OpenWrt linux-6.6 (OpenMANET 1.8.0) | ✅ `wlh0` up as AP on SG @ 22 dBm |
| 6.6.51+rpt-rpi-v8 | raspberrypi/linux rpi-6.6.y (RPi OS Bookworm 2024-11-19) | ❌ CMD63 fail → `spi_rx_lshift=2` → CMD53 write fail at `0x00004050:4`, `ret:-71` |
| 6.12.93+rpt-rpi-v8 | raspberrypi/linux rpi-6.12.y (RPi OS Bookworm 2025-05) | ❌ byte-identical fingerprint to above |
| 6.18.34+rpt-rpi-v8 | raspberrypi/linux rpi-6.18.y (RPi OS Trixie) | ❌ byte-identical fingerprint |

**Key conclusion:** the fault is a `spi-bcm2835` (or SPI-core) **tree difference**, not a version regression. Both trees share mainline stable-tag numbering, but `raspberrypi/linux`'s patch stack breaks MM6108 driven via GPIO CS, and OpenWrt's does not. Bisecting versions inside `raspberrypi/linux` is the wrong strategy — the productive comparison is `drivers/spi/spi-bcm2835.c` and adjacent SPI-core files between the two trees at similar stable tags.

**Practical bottom line:** OpenMANET 1.8.0 remains the only tested working path. Any recommendation of a stock Raspberry Pi OS variant is unsafe until this is fixed upstream. For a Debian userspace, options are:
- (a) OpenMANET as a dedicated gateway,
- (b) Ubuntu Server or a mainline-kernel Debian image on the Pi (both untested but expected to work since they do not use `raspberrypi/linux`),
- (c) build a mainline kernel and install on Bookworm.

The retraction: earlier "next things to try" below (§) suggested that some 6.6.x kernel on Raspberry Pi OS should work because it's the same LTS branch as OpenMANET. Wrong. Any `+rpt-rpi-v8` kernel tested carries the bug.

**Public status:** four comments now on `MorseMicro/morse_driver` issue #9 (v1 initial, v2 OpenMANET pass, v3 Bookworm 6.12.93 fail, v4 Bookworm 6.6.51 fail + tree-split reframing). No maintainer response as of this update.

Full per-test evidence in `logs/`:
- `logs/2026-08-22-openmanet-1.8.0-*.log/.txt` — the passing case
- `logs/2026-08-22-bookworm-6.6.51-*.log/.txt`
- `logs/2026-08-22-bookworm-6.12.93-*.log/.txt`

Below is the earlier bring-up writeup that led to this conclusion. The "next things to try" section at the end is now historical — items (1) OpenMANET and (2) Seeed's prebuilt image were both examined; the OpenMANET test drove the conclusion above, and Seeed's release (`Wvirgil123/openwrt` v2.7-dev, kernel 5.15, EKH01 pinout) is another OpenWrt-tree data point but would need the same overlay swap the Heltec HT-HC01P image needs.

---

## Hardware: confirmed good
- Chip identified by the driver over SPI: **chip ID 0x0306 = MM6108A1**
  (`MORSE_DEVICE_ID(0x6, rev 3, silicon)` in hw.h). Not a guess - the driver's
  own `mm610x_chip_id_matches()` accepted it.
- Pin map (Seeed WM1302 Pi HAT, reused by the M1 carrier):
  MISO 9 / MOSI 10 / CLK 11 / CS 8, RESET_N 17, SPI_INT 5, WAKE 23, BUSY 24,
  slot power enable 18 (M1-specific).
- RESET_N is active low and `morse_hw_reset()` releases it by *floating* the
  pin, so GPIO17 must be configured pull-up or the BCM2711's default pull-down
  holds the radio in reset. Handled in the overlay.

## Software state
- Driver: MorseMicro/morse_driver tag `mm6108-2.0.1`, builds clean against
  kernel 6.18.34+rpt-rpi-v8 with the patches in ./patches.
- Firmware installed to /lib/firmware/morse: mm6108.bin + quectel BCFs.
  Chip OTP reports board serial "default", so the BCF must be named explicitly:
  `bcf=bcf_fgh100mhaamd.bin`.
- Regulatory: driver has no TW regdomain. `SG` is 920-925 MHz / 4 MHz / 22 dBm,
  which matches the Taiwan NCC allocation exactly. Built with
  CONFIG_MORSE_COUNTRY=SG, overridable with country=.

## What works
Reset, chip ID read, firmware load, BCF load - i.e. the whole CMD52/CMD53-read
path, but only with `spi_rx_lshift=2`.

## The open problem: a constant 2-bit skew on the chip's responses
Every response from the chip arrives 2 bit times late, off the byte grid.
Verified in userspace against /dev/spidev0.0, independent of the driver:
- CMD0 with a correct CRC7  -> R1 = 0x01 (idle)
- CMD0 with a corrupted CRC -> R1 = 0x09 (idle + CRC error)
- CMD13                     -> R1 = 0x05 (idle + illegal command)
- no command                -> nothing at all (all 0xff)
So the chip decodes our commands perfectly (it validates our CRC7); only its
*transmit* framing is 2 bits off ours. Clock-independent: identical at 400 kHz,
1 MHz, 20 MHz and 50 MHz, so it is not a propagation-delay effect.

`spi_rx_lshift=N` (added in the patch, mirrors the existing `is_rk3288` 1-bit
right-shift hack) re-aligns receives and makes reads work.

Writes still fail: CMD53 data-block writes get a correct R1, but no data
response token ever appears - dumped a 71-byte window, all 0xff. Yet the same
transaction driven by hand from userspace *does* return token 0x05
(SPI_RESPONSE_ACCEPTED) two bytes after the CRC. Difference between the two
paths is not yet understood; card state (idle vs initialised) is the main
suspect. `spi_tx_rshift=2` moves the failure to an earlier stage, so the TX
grid matters too.

## Eliminated (2026-08-19, all tested on hardware)
- SPI clock: 400 kHz, 1, 10, 20, 50 MHz - identical 2-bit skew at every speed.
- SPI mode 0/1/2/3 - mode 1 shows a 1-bit skew instead of 2, none is clean.
- TX bit alignment (`spi_tx_rshift`): shifting transmits breaks CMD63 outright,
  which proves the chip's *receive* byte grid already matches ours. Only its
  transmit path is late.
- Longer wait between the write command's R1 and the data token
  (`spi_pre_token_bytes` 4/8/16/32) - no change.
- Wider ack search window (`spi_post_write_status_bytes` 4/8/16/32/64) - the
  window is all 0xff out to 71 bytes; the chip sends nothing at all.
- `enable_ext_xtal_init=1` - no change.
- Cold power cycle of the slot (GPIO18 low 3 s, not just a RESET_N pulse) -
  skew and write failure both survive it, so neither is a stuck-state artifact.
- Driver tag 1.16.4. It does not build against 6.18 without work, but the
  reason is not what it first looks like - see "Driver version is ruled out"
  below, which supersedes an earlier wrong conclusion here.

## Carrier wiring finding
With the module powered and out of reset, tested by flipping the BCM2711
internal pull up/down and reading the level back:
- GPIO5 (SPI_INT, mPCIe pin 10): actively driven high -> connected.
- GPIO23 (WAKE, mPCIe 33) and GPIO24 (BUSY, mPCIe 31): follow the internal
  pull both ways -> floating, i.e. not wired on the M1 carrier.
BUSY is a module output, so it should be driven if it were connected. The M1's
mPCIe slot looks like a subset of the WM1302 Pi HAT wiring - enough for the
LoRa concentrator it was built for, not the full HaLow handshake.
Note this does *not* explain the write failure: `gpios.busy`/`gpios.wake` are
referenced only from ps.c (power save), never from the transfer path. But
power-gpios should be dropped from the overlay so the driver does not arm
power-save against pins that are not there.

## Driver version is ruled out (2026-08-19, later)
1.17.9 *does* build on kernel 6.18. The earlier "needs a Morse-patched kernel"
conclusion was wrong: the only blocker is one version guard. 2.0.1 changed

    #if KERNEL_VERSION(5, 10, 11) > MAC80211_VERSION_CODE
to
    #if KERNEL_VERSION(5, 10, 11) > MAC80211_VERSION_CODE || \
        KERNEL_VERSION(6, 18, 0) <= MAC80211_VERSION_CODE

because mainline 6.18 changed the S1G definitions again. Copy that one line into
1.17.9's dot11ah/s1g_ieee80211.h, apply the same three spi.c patches, and it
builds (worktree at ~/halow/morse_1.17.9).

**1.17.9 then behaves exactly like 2.0.1**: needs spi_rx_lshift=2, reads chip ID
0x0306, loads firmware and BCF, and dies at the first CMD53 write with
find_data_ack failing. Two independent driver generations, identical symptom ->
this is not a driver regression, it is the bus/hardware interaction.

Also tried and ineffective: `spi_tx_lshift` 1/2/3 (the untested shift direction).

## From the datasheet (SKU 109990565)
- VBAT 3.0-3.6 V typ 3.3 V, but **VDD_IO is 1.62-3.6 V, typ 1.8/3.3 V** - the
  module has a separate I/O rail that can be 1.8 V. Where that rail is fed from
  on the M1's mPCIe slot is unverified and is a live suspect: the M1 carrier was
  built for a WM1303 LoRa concentrator, not for this module.
- The datasheet references an official pinout figure but the PDF only embeds a
  thumbnail; the readable version is on the Seeed product page.

## DECISIVE: this is an open upstream bug on officially supported hardware
MorseMicro/morse_driver **issue #9**, opened 2026-02-22, still open with no
maintainer reply:
  Raspberry Pi 4 Model B + **genuine Seeed WM1302 Pi HAT** + Wio-WM6108
  (FGH100M-H) + a **Morse-patched kernel 6.12.25-v8-morse+** + Raspberry Pi OS
  Trixie. Firmware and BCF load, then:
      morse_spi_cmd53_write failed
      cmd53_write fn=2 0x00000000:10 ... (ret:-71)
      morse_firmware_init failed: -5
  Reporter tried 50 MHz down to 2.5 MHz, SPI modes 0 and 3, several BCFs, and a
  reset script. No resolution.

So **the WM1302 Pi HAT would not have fixed this** - that configuration fails
the same way. The carrier board is not the problem, and neither is the kernel
patch set.

Every documented success is on a **Pi 5** (RP1 SPI controller), and even there
`cmd53_write ret:-71` shows up under sustained load. Nobody in the Morse
community thread reports success on a Pi 4 / bcm2835 SPI controller.

Seeed's own getting-started page supports exactly one configuration: Raspberry
Pi 4 Model B running their **pre-built OpenWrt image**, flashed to a microSD.
They also state the device "only supports the US and does not support other
countries or regions".

## Next things to try, in order of expected value
1. **OpenMANET's `rpi4-mm6108-spi` image** on a spare microSD. Its device tree
   is already the WM1302 HAT pin map with GPIO17 pulled up, and it carries the
   same driver release and firmware built here, so the only variable left is
   the kernel and its `spi-bcm2835` generation (6.6.138 there, 6.18.34 here).
   Only the slot power line (`gpio=18=op,dh`) has to be added. A tip from
   not5erpe on issue #9; the rpi4-mm6108-spi asset is by far the most
   downloaded of that release, which suggests the combination is in real use.
2. Seeed's own prebuilt image. It is the only configuration Seeed document, and it pulls in a completely different kernel - 5.15.189
   against the 6.18.34 here - so it also tests a different `spi-bcm2835`
   generation, which is a variable that cannot be changed on the running
   system. `overlays/openwrt/` has the corrected overlay and a script that
   patches a freshly flashed boot partition; the stock image will not work
   unmodified because its overlay is for Morse's EKH01 pin map.
   Note the driver in those images is stock, with no `spi_rx_lshift`, so if the
   skew is still present it will stop at CMD63 rather than reaching the write.
   Either outcome is a result worth having.
3. Establish whether the 2-bit skew comes from the BCM2835 SPI controller
   rather than the module - the driver already carries a 1-bit shift quirk for
   RK3288, so a controller-side skew has precedent.
4. Failing all of that, this module and a Pi 4 may simply not work together. Every
   documented success is on a Pi 5 / RP1, and a USB HaLow adapter would side-
   step the SPI transport entirely.

## Nothing here persists across a reboot
The device tree overlay was applied at runtime only; config.txt is untouched.
A reboot returns the machine to plain spidev0.0/0.1 with no morse driver.
Files installed outside ~/halow: /lib/firmware/morse/* only.
