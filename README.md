# Wio-WM6108 (Morse Micro MM6108) over SPI on a Raspberry Pi 4

*[中文版 README](README.zh-TW.md)*

Bring-up notes, patches and measurement tools for a Seeed **Wio-WM6108** Wi-Fi
HaLow mini-PCIe module (Quectel FGH100M-H, Morse Micro **MM6108A1**) driven over
SPI from a Raspberry Pi 4.

> ## Update 2026-08-23 — SOLVED. `wlan1` is up on stock Raspberry Pi OS
>
> ```
> phy33 -> platform/soc/fe204000.spi/spi_master/spi0/spi0.0
> wlan1 up, 0 write failures, 0 read failures, 0 probe failures
> SPI core statistics: errors 0, timedout 0
> ```
>
> No module parameters, no `spi_rx_lshift`, stock kernel 6.6.51+rpt-rpi-v8.
> Three defects in the driver's `spi.c` had to be fixed, and each one hid the
> next.
>
> **1. The driver does not build** where `SPI_CONTROLLER_ENABLE_CS_GPIOD` is
> undefined — a `#warning` under `-Werror`. That includes raspberrypi/linux
> 6.6.51, not just mainline.
>
> **2. The chip was never put into SPI mode.** It needs ~74 clocks with chip
> select **deasserted** to enter it. `morse_spi_initsequence()` tries to arrange
> that by flipping `SPI_CS_HIGH` around the training burst — but on a `cs-gpios`
> controller `spi_setup()` forces that bit straight back on, so the burst goes out
> with the chip *selected*. It never enters SPI mode, and every response
> afterwards sits two bit times off the byte grid. **Fix: `SPI_NO_CS` for the
> burst**, so the controller leaves the CS line alone and the GPIO stays high
> throughout. Order matters — the burst must come after reset and before any other
> transaction; once the chip has been addressed with CS asserted it does not
> recover.
>
> **3. The inter-transaction delay is counted in SPI clocks, not in time.** The
> driver derives it as `40000ns / (clk_period * 8)` — 250 bytes at 50 MHz, 50 at
> 10 MHz. Both are 40 µs, yet 50 fails and 250 works. **Fix: floor all three
> delay sites at 250 bytes.** Morse's own OpenWrt feed already carries that floor;
> it is simply not in the released driver. This is why every setup that works runs
> at 50 MHz.
>
> Verified by single-parameter A/B inside one driver binary on one board, and in
> userspace with the chip select driven by hand. Detail in
> [`logs/2026-08-23-nocs-init-fix-environment.txt`](logs/2026-08-23-nocs-init-fix-environment.txt)
> and [`logs/2026-08-23-WORKING-environment.txt`](logs/2026-08-23-WORKING-environment.txt).
>
> **The clean fixes are in [`patches/upstream/`](patches/upstream/)** — three
> patches against tag `mm6108-2.0.1`, no instrumentation, verified on hardware
> with no module parameters. Submitted as
> [morse_driver#16](https://github.com/MorseMicro/morse_driver/pull/16); the init
> defect is also reported on its own as
> [issue #15](https://github.com/MorseMicro/morse_driver/issues/15).
> `patches/morse-driver-2.0.1-rpi-spi.patch` is the investigation's working file
> — instrumentation and experiment parameters — and is not the one to use.
>
> **Verified under this repo's own overlay, on a cold boot.** The runs above were
> made with an experiment overlay installed over the stock filename, which sets
> `reset-gpios` flag 0 — OpenMANET's setting. (That flag was believed to stop
> RESET_N from firing; **corrected 2026-08-24** — `morse_driver` 2.0.1 has no
> `gpiod_` call at all, so the flag is discarded and RESET_N fires either way.
> What OpenMANET actually has is a Morse-authored kernel patch. See NOTES.md,
> "Why OpenMANET never needed the fix".)
> Re-run 2026-08-23 with the stock overlay in place: `reset-gpios` flag 1,
> two chip selects from `dtparam=spi=on`, module
> auto-loaded at boot, no parameters beyond `country=` and `bcf=` — `phy1` on
> `spi0.0`, `wlan1` up, `errors 0`, `timedout 0`, zero failure lines. The same
> boot reproduced the original failure under the identical device tree by loading
> an unfixed build (`c0 7f`, CMD63 `-71`), so the A/B holds the device tree
> constant and varies only the driver binary. Capture in
> [`logs/2026-08-23-stock-overlay-clean-series-environment.txt`](logs/2026-08-23-stock-overlay-clean-series-environment.txt).
>
> **Not specific to this carrier.** Defect 2 measured on 6.6.51; by inspection it
> applies to any host where `spi_setup()` forces `SPI_CS_HIGH` for a `cs-gpios`
> device, which is mainline and every rpi kernel carrying `950-0204`. The fix
> belongs in the driver.
>
> **Association and data transfer are verified** (2026-08-23), against a peer
> running a different driver: this patched driver as the station, Morse's own
> OpenWrt build as the AP on a second board. WPA3-SAE with PMF, DHCP over the
> air, 4 MiB transferred and checksummed in both directions — 1.3–1.5 Mbit/s
> down, 0.2–0.9 Mbit/s up at 2 MHz bandwidth on 923.0 MHz — 200/200 pings at 0%
> loss, and 88.9 MB of SPI traffic with `errors 0`. Detail, including what is
> still unknown, in
> [`logs/2026-08-23-association-verified-environment.txt`](logs/2026-08-23-association-verified-environment.txt).
>
> **Correction.** This section previously said scans found nothing "because
> there is no HaLow network in range". That was wrong: an AP was broadcasting a
> few metres away throughout. It was invisible because it was on `country=US`
> and the station on `country=SG`, and the dot11ah mapping resolves the same
> mapped channel to a different S1G frequency per country. Aligning both to `SG`
> made it appear on the first scan.

> **Update 2026-08-22.** Four end-to-end tests on the same board, changing only the OS image:
>
> | Kernel | Tree | Outcome |
> |---|---|---|
> | **6.6.138** | **OpenWrt linux-6.6** (via OpenMANET 1.8.0) | ✅ `wlh0` up as AP on SG @ 22 dBm |
> | 6.6.51+rpt-rpi-v8 | raspberrypi/linux rpi-6.6.y (RPi OS Bookworm 2024-11-19) | ❌ same 2-bit RX offset, CMD53 write at `0x00004050:4` fails `ret:-71` |
> | 6.12.93+rpt-rpi-v8 | raspberrypi/linux rpi-6.12.y (RPi OS Bookworm 2025-05) | ❌ byte-identical fingerprint |
> | 6.18.34+rpt-rpi-v8 | raspberrypi/linux rpi-6.18.y (RPi OS Trixie) | ❌ byte-identical fingerprint |
>
> **Update 2026-08-22 (later) — the "kernel tree" reading of that table is withdrawn.** I diffed the two trees at the same stable tag. `drivers/spi/spi-bcm2835.c`, `drivers/spi/spi.c`, `drivers/dma/bcm2835-dma.c`, `drivers/pinctrl/bcm/pinctrl-bcm2835.c` and `arch/arm/boot/dts/broadcom/bcm270x-rpi.dtsi` are **byte-identical** between OpenWrt 24.10's bcm27xx 6.6 tree and `raspberrypi/linux` rpi-6.6.y at 6.6.51: OpenWrt imports the rpi SPI commits verbatim. There is no `spi-bcm2835` delta and nothing to bisect.
>
> The difference is in the **driver package**, not the kernel. Morse's own OpenWrt feed — `MorseMicro/morse-feed`, pinned by OpenMANET 1.8.0 — applies `003_fix_spi_inter_transaction_delay.patch`, which raises the padding clocked after the CRC of a *non-block* CMD53 write from 4 bytes to a floor of **250**. Every failure here is a non-block write (`fn=1 0x00004050:4`, count 4), and the widest window ever tested here was 64. OpenMANET also runs `enable_ext_xtal_init=1`, which appends a further 4096 bytes to that window. That patch is in Morse's OpenWrt feed only — not in the `morse_driver` git tag.
>
> The 2-bit RX skew is still unexplained; padding cannot cause bit-level misframing. Full derivation, numbers and the next experiment are in [NOTES.md](NOTES.md).
>
> Four follow-up comments on issue #9 carry the measurements; per-test dmesg + environment snapshots are in [`logs/`](logs/). The narrative below is the earlier writeup that led here.

**Status: working.** `wlan1` comes up on stock Raspberry Pi OS, bound to `spi0.0`, with zero
SPI read or write failures. Three driver defects had to be fixed; the clean series is in
[`patches/upstream/`](patches/upstream/) and all three are described above and in
[NOTES.md](NOTES.md). This appears to be the
same wall as [MorseMicro/morse_driver issue #9](https://github.com/MorseMicro/morse_driver/issues/9),
which is open and unanswered — and which was hit on the officially supported
hardware (Raspberry Pi 4 + genuine Seeed WM1302 Pi HAT + a Morse-patched kernel).

Published in the hope that the measurements save someone else the same week.

## Hardware

| | |
|---|---|
| Host | Raspberry Pi 4 Model B rev 1.4 (BCM2711, `spi-bcm2835`) |
| Module | Seeed Wio-WM6108, chip ID `0x0306` = MM6108A1 |
| Carrier | SenseCAP M1 mPCIe slot, wired to the WM1302 Pi HAT pin map |
| OS | Raspberry Pi OS Trixie, stock kernel 6.18.34+rpt-rpi-v8 |
| Driver | `mm6108-2.0.1` and `1.17.9`, both from MorseMicro/morse_driver |

Pin map (WM1302 Pi HAT, which the M1 slot follows):

| signal | GPIO | note |
|---|---|---|
| MISO / MOSI / CLK / CS | 9 / 10 / 11 / 8 | `spi0.0` |
| RESET_N | 17 | active low |
| SPI_INT | 5 | module output |
| WAKE / BUSY | 23 / 24 | measured floating on this carrier |
| slot power enable | 18 | SenseCAP M1 specific, not part of the HAT map |

## The main finding: the chip's responses are 2 bits late

Every response arrives two bit times after the byte boundary. Measured from
userspace against `/dev/spidev0.0` with the driver unloaded, so it is
independent of the driver:

| sent | R1 returned (after re-aligning 2 bits) |
|---|---|
| CMD0, correct CRC7 | `0x01` (idle) |
| CMD0, **deliberately corrupted CRC7** | `0x09` (idle + CRC error) |
| CMD13 | `0x05` (idle + illegal command) |
| nothing clocked | all `0xff` |

The chip validates our CRC7 and flags illegal commands, so its **receive** path
decodes our byte stream correctly — only its transmit framing is offset. The
effect is fully deterministic (20/20 identical) and unchanged from 400 kHz to
50 MHz, so it is not a setup-time or propagation-delay effect.

`tools/` reproduces all of this. Start with `mmcspi.py`, then `discriminate.py`
for the CRC/illegal-command experiment that pins down which direction is broken.

## Left-shifting received buffers by 2 bits makes the read path work

Same idea as the driver's existing `is_rk3288` 1-bit `morse_shift_buffer()`
quirk, in the other direction. `patches/` adds a `spi_rx_lshift=N` module
parameter — plus `spi_tx_rshift`, `spi_pre_token_bytes`, and (since 2026-08-22)
`spi_init_train_bytes` / `spi_init_cs_flip` for probing the init sequence, and a
`morse_spi_find_data_ack()` that reports where in the ack window the chip
answered. With `spi_rx_lshift=2`:

```
morse_spi spi0.0: Morse Micro SPI device found, chip ID=0x0306
morse_spi spi0.0: Loaded firmware from morse/mm6108.bin, size 468304, crc32 0xbe7b5c8f
morse_spi spi0.0: Loaded BCF from morse/bcf_fgh100mhaamd.bin, size 1251, crc32 0x941b2a82
morse_spi_find_data_ack failed
morse_spi_cmd53_write failed
morse_spi spi0.0: spi: cmd53_write fn=1 0x00004050:4 r=0x10050002 b=0xffffffff (ret:-71)
```

`0x0306` decodes as `MORSE_DEVICE_ID(0x6, rev 3, silicon)` = MM6108A1, so the
realignment recovers real register data rather than noise.

## Where it dies

CMD53 writes get a correct `R1 = 0x00` and then no data-response token at all —
the ack window is `0xff` out to 71 bytes. Ruled out: SPI clock 400 kHz…50 MHz,
SPI modes 0–3, shifting transmits in either direction, a longer R1→token gap,
a real power cycle of the slot, and both driver generations.

`spi_post_write_status_bytes` 4…64 and `enable_ext_xtal_init` are **no longer
valid eliminations**: Morse's own OpenWrt patch puts the floor for that window at
250 bytes, and the xtal init sequence itself needs a working write path. See
[NOTES.md](NOTES.md) for the full log and the retraction.

## Things worth knowing regardless of this bug

**`morse_hw_reset()` releases RESET_N by floating the pin**, relying on an
external pull-up. On a BCM2711 the default pull on GPIO17 is *down*, so the
radio stays in reset and the bus reads all zeros. This is very easy to
misdiagnose as a dead module. The overlays here set that pin pull-up.

**Driver 1.17.9 builds against a stock 6.18 kernel with a one-line change.**
Mainline 6.18 changed the S1G definitions again, so `dot11ah/s1g_ieee80211.h`
needs the guard 2.0.1 received:

```c
#if KERNEL_VERSION(5, 10, 11) > MAC80211_VERSION_CODE || \
	KERNEL_VERSION(6, 18, 0) <= MAC80211_VERSION_CODE
```

**`spi.c` does not build on a mainline kernel.** `SPI_CONTROLLER_ENABLE_CS_GPIOD`
is a vendor-kernel flag, and `ccflags-y` carries `-Werror`, so the `#warning` in
the `#else` branch is fatal. Mainline also forces `SPI_CS_HIGH` on for `cs-gpios`
targets, which means `morse_spi_initsequence()`'s set-then-clear of that bit
leaves the bus with an inverted chip select. Both are handled in `patches/`.

**Regulatory:** the driver has no `TW` regdomain, but `SG` is 920–925 MHz /
4 MHz / 22 dBm, which matches the Taiwan NCC allocation exactly.

## OpenMANET ships an image built for exactly this wiring

[OpenMANET](https://github.com/OpenMANET/firmware/releases) publishes
`openmanet-<ver>-rpi4-mm6108-spi-squashfs-sysupgrade.img.gz`, and its device
tree is the WM1302 HAT pin map, not the EKH01 one:

```
reset-gpios   = <&gpio 17 0>      morse_reset { pins 17, input, pull-up }
spi-irq-gpios = <&gpio  5 0>      morse_irq   { pins  5, input, pull-up }
power-gpios   = <&gpio 23 0>, <&gpio 24 0>
cs-gpios      = <&gpio  8 1>      spi-max-frequency = 50 MHz
```

Note `morse_reset` is configured **pull-up** — independent confirmation of the
RESET_N floating problem described above.

1.8.0 (2026-08-16) is OpenWrt 24.10, kernel **6.6.138**, and carries morse
driver **`0-rel_mm6108_2_0_1_2026_Jun_11`** — nominally the same release built
here — plus an `mm6108.bin` identical to the one used here (crc32 `0xbe7b5c8f`).

It is *not* the single-variable experiment I first took it for. The archived
logs show it differs in more than the kernel:

- it loads **`bcf_default.bin`** (1298 bytes, crc32 `0xf72450a7`), not
  `bcf_fgh100mhaamd.bin` (1251 bytes, `0x941b2a82`) — an earlier claim that the
  BCF was identical was wrong;
- its driver is built by `MorseMicro/morse-feed`, which applies SPI patches that
  are not in the `morse_driver` git tag (see [NOTES.md](NOTES.md));
- its `dot11ah` is an **mm8108 2.0.0** build alongside the mm6108 2.0.1 driver;
- it runs `spi-max-frequency` at 50 MHz and `enable_ext_xtal_init=1`, both of
  which change how much padding the driver clocks per transaction.

On a carrier that gates slot power from a GPIO (the SenseCAP M1 uses GPIO18)
that line still has to be added — it is in no upstream overlay:

```
gpio=18=op,dh
```

## Other prebuilt images need their overlay replaced

The prebuilt images (Seeed's, and beyondlogic's newer 2.11.13 build) ship an
`mm610x-spi.dtbo` for Morse's own EKH01 board — RESET on gpio5, SPI_INT on
gpio25 — which does not match the WM1302 HAT map. On a HAT-wired carrier the
driver ends up driving the module's interrupt output as a reset line and waiting
for an interrupt on an unconnected pin. `overlays/openwrt/` has a corrected
overlay and a script that patches a freshly flashed boot partition.

Those images are Raspberry Pi 4 builds despite the board name:
`DISTRIB_TARGET='bcm27xx/bcm2711'`, `DISTRIB_ARCH='aarch64_cortex-a72'`, and the
boot partition carries `bcm2711-rpi-4-b.dtb`. The `ekh01` string only appears in
OpenWrt's per-board LED and network `case` lists, alongside the `raspberrypi,*`
entries.

## Testing on hardware

[TESTING.md](TESTING.md) holds three self-contained procedures, pending first:
the A/B that runs the userspace SPI probe on the OpenMANET card (the only
experiment left), the completed Raspberry Pi OS retest that eliminated six
hypotheses, and the completed OpenMANET card swap that produced the only passing
result so far. Each lists what every possible output means.

## Layout

```
NOTES.md                          full bring-up log, every hypothesis and result
issue9-reply.md                   the write-up posted to morse_driver issue #9
patches/                          spi.c patches against morse_driver mm6108-2.0.1
overlays/mm610x-spi-sensecap.dts  device tree overlay for Raspberry Pi OS
overlays/openwrt/                 corrected overlay + boot-partition patch script
tools/                            userspace SPI probes used for the measurements
```

## Licence

The patches are derived from MorseMicro/morse_driver and follow its licence.
Everything else here is published under the same terms so it can be folded back
upstream without friction.
