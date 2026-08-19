# Wio-WM6108 (Morse Micro MM6108) over SPI on a Raspberry Pi 4

*[中文版 README](README.zh-TW.md)*

Bring-up notes, patches and measurement tools for a Seeed **Wio-WM6108** Wi-Fi
HaLow mini-PCIe module (Quectel FGH100M-H, Morse Micro **MM6108A1**) driven over
SPI from a Raspberry Pi 4.

**Status: the radio is alive and identifies itself, but is not usable.** Reads
work; the first CMD53 data write never gets acknowledged. This appears to be the
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
parameter. With `spi_rx_lshift=2`:

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
SPI modes 0–3, shifting transmits in either direction, `spi_post_write_status_bytes`
4…64, a longer R1→token gap, `enable_ext_xtal_init`, a real power cycle of the
slot, and both driver generations. See [NOTES.md](NOTES.md) for the full log.

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
driver **`0-rel_mm6108_2_0_1_2026_Jun_11`** — the same release built here — plus
`mm6108.bin` and `bcf_fgh100mhaamd.bin` identical to the ones used here.

That makes it a clean single-variable experiment. Same driver, same firmware,
same pin map; the only thing that changes is the kernel, and with it the
`spi-bcm2835` generation: 6.6.138 there against 6.18.34 here. If the 2-bit skew
survives that, the skew is not coming from the SPI controller driver.

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
