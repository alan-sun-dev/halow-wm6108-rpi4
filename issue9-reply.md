Hitting what looks like the same wall on a Raspberry Pi 4, from a completely different direction. I have some measurements that may help narrow this down.

## Setup

- Raspberry Pi 4 Model B rev 1.4 — BCM2711, `spi-bcm2835` controller
- Wio-WM6108 (Quectel FGH100M-H); the driver reads chip ID `0x0306` = MM6108A1
- Carrier: a SenseCAP M1 mPCIe slot, wired to the same pin map as the WM1302 Pi HAT (MISO 9 / MOSI 10 / CLK 11 / CS 8, RESET_N 17, SPI_INT 5)
- Raspberry Pi OS Trixie, **stock** kernel 6.18.34+rpt-rpi-v8 — no Morse kernel patches
- Driver tags `mm6108-2.0.1` and `1.17.9`, firmware and BCF from the matching `morse-firmware` tags

Different carrier, different kernel, no Morse kernel patches, two driver generations — and the failure is identical to the one reported above. That seems worth noting, because it rules out the carrier board and the kernel patch set as the cause.

## The chip's responses come back 2 bits late, off the byte grid

Measured from userspace against `/dev/spidev0.0` with the morse driver unloaded, so this is independent of the driver:

| sent | R1 returned (after re-aligning by 2 bits) |
|---|---|
| CMD0, correct CRC7 | `0x01` (idle) |
| CMD0, **deliberately corrupted CRC7** | `0x09` (idle + CRC error) |
| CMD13 | `0x05` (idle + illegal command) |
| nothing clocked | all `0xff` |

The chip validates our CRC7 and flags illegal commands, so its **receive** path is decoding our byte stream correctly. Only its transmit framing is offset. Raw bytes for CMD0:

```
raw : ff c0 7f ff ff ff ff ff
bits: 11000000 01111111 11111111 ...
             ^ a 7-zero run starting at bit 2  ->  R1 = 0x01, shifted 2 bits
```

It is fully deterministic — 20 out of 20 transactions returned `R1=0x01 @bit10` — and identical at 400 kHz, 1 MHz, 10 MHz, 20 MHz and 50 MHz, so it is not a setup-time or propagation-delay effect. SPI modes 0/2/3 give a 7-zero run; mode 1 gives an 8-zero run at a 1-bit offset.

## Left-shifting every received buffer by 2 bits makes the entire read path work

Same idea as the existing `is_rk3288` 1-bit `morse_shift_buffer()` quirk, in the opposite direction. With that applied in `morse_spi_xfer()`:

```
morse_spi spi0.0: Morse Micro SPI device found, chip ID=0x0306
morse_spi spi0.0: Loaded firmware from morse/mm6108.bin, size 468304, crc32 0xbe7b5c8f
morse_spi spi0.0: Loaded BCF from morse/bcf_fgh100mhaamd.bin, size 1251, crc32 0x941b2a82
morse_spi_find_data_ack failed
morse_spi_cmd53_write failed
morse_spi spi0.0: spi: cmd53_write fn=1 0x00004050:4 r=0x10050002 b=0xffffffff (ret:-71)
```

`0x0306` decodes as `MORSE_DEVICE_ID(0x6, rev 3, silicon)` = MM6108A1 and is accepted by `mm610x_chip_id_matches()`, so the realignment is recovering real register data, not noise.

## Where it dies: CMD53 writes get a correct R1 and then no data-response token at all

I dumped the full transaction buffer. R1 comes back as `0x00`, and from the data token onward every single byte is `0xff`. I extended the ack search window out to 71 bytes — nothing. The chip accepts the command and then never emits a data-response token.

## Ruled out

- SPI clock: 400 kHz, 1, 10, 20, 50 MHz
- SPI mode 0/1/2/3
- Shifting the **transmit** buffer in either direction by 1–3 bits. Right-shifting breaks CMD63 outright, which is further evidence that the chip's receive framing already matches ours
- `spi_post_write_status_bytes` = 4/8/16/32/64
- Extending the gap between the write command's R1 and the data token from 4 to 8/16/32 bytes
- `enable_ext_xtal_init=1`
- A real power cycle of the slot supply, not just a RESET_N pulse
- Driver `1.17.9` vs `mm6108-2.0.1` — byte-for-byte the same symptom

## Question for the maintainers

Is the BCM2835 SPI controller (Pi 4 and earlier) known not to work with the MM6108? Every success I can find in the community forum is on a Pi 5 / RP1, and the report at the top of this issue is a Pi 4 with the official WM1302 Pi HAT and a Morse-patched kernel. Since `is_rk3288` already exists as a controller-specific bit-alignment workaround, is there a known set of controllers that need this, and is there anything on the chip side — a fixed output-delay or drive-strength setting in the BCF, say — that is meant to be configured for it?

## Three side notes that may help others

**1.** `1.17.9` builds against a stock 6.18 kernel with a one-line change. Mainline 6.18 changed the S1G definitions again, so `dot11ah/s1g_ieee80211.h` needs the same guard `2.0.1` received:

```c
#if KERNEL_VERSION(5, 10, 11) > MAC80211_VERSION_CODE || \
	KERNEL_VERSION(6, 18, 0) <= MAC80211_VERSION_CODE
```

**2.** `morse_hw_reset()` releases RESET_N by *floating* the pin (`gpio_direction_input`), relying on an external pull-up. On a BCM2711 the default pull on GPIO17 is **down**, so the radio is held in reset forever and the SPI bus reads all zeros unless the device tree overlay explicitly configures that pin as pull-up. This is easy to misdiagnose as a dead module — worth a line in the device tree documentation.

**3.** On a mainline kernel, `spi.c` fails to build:

```
spi.c: error: #warning "SPI_CONTROLLER_ENABLE_CS_GPIOD macro not defined" [-Werror=cpp]
```

`SPI_CONTROLLER_ENABLE_CS_GPIOD` is a vendor-kernel flag; mainline 6.18 only has `HALF_DUPLEX`/`NO_RX`/`NO_TX`/`MUST_RX`/`MUST_TX`/`GPIO_SS`/`SUSPENDED`/`MULTI_CS`. Because `ccflags-y` carries `-Werror`, the `#warning` in the `#else` branch is fatal rather than advisory. Also worth checking: on mainline, `spi_add_device()` forces `SPI_CS_HIGH` on for any `cs-gpios` target so gpiolib applies the active-low inversion once, which means `morse_spi_initsequence()`'s set-then-clear of `SPI_CS_HIGH` leaves the bus with an inverted chip select afterwards. Flipping *away* from whatever state the core hands you, then restoring it, works on both vendor and mainline kernels.

---

Full measurements, the patches, both device tree overlays and the userspace probes used above are at <https://github.com/alan-sun-dev/halow-wm6108-rpi4>, in case any of it is useful for narrowing this down.

---

## Update, 2026-08-22 — the same hardware works on kernel 6.6.138

The identical hardware — same Wio-WM6108, same SenseCAP M1 carrier, same wiring — runs cleanly under **OpenMANET 1.8.0** (OpenWrt 24.10, kernel **6.6.138**, driver release `0-rel_mm6108_2_0_1_2026_Jun_11`).

Firmware and BCF are the same binaries the failing setup loads (crc32 `0xbe7b5c8f` for `mm6108.bin`, `0x941b2a82` for `bcf_fgh100mhaamd.bin`), and the driver release is the same tag I was building from source on the Pi OS side. The only variable that moves is the kernel and its `spi-bcm2835`.

Full boot dmesg and environment snapshot are in the repo:

- [logs/2026-08-22-openmanet-1.8.0-full-dmesg.log](https://github.com/alan-sun-dev/halow-wm6108-rpi4/blob/main/logs/2026-08-22-openmanet-1.8.0-full-dmesg.log)
- [logs/2026-08-22-openmanet-1.8.0-environment.txt](https://github.com/alan-sun-dev/halow-wm6108-rpi4/blob/main/logs/2026-08-22-openmanet-1.8.0-environment.txt)

| Kernel | RX byte alignment | CMD53 write | `wlh0` up |
|---|---|---|---|
| 6.18.34+rpt-rpi-v8 (Raspberry Pi OS Trixie) | needs `spi_rx_lshift=2` even to read chip ID cleanly | `find_data_ack failed`, `ret:-71` | no |
| **6.6.138 (OpenMANET 24.10, bcm27xx/bcm2711)** | works untouched, no realignment needed | passes, `morse_mac_init` completes | **yes**, AP on SG regulatory band, 22 dBm |

Two things fall out of this:

1. The 2-bit RX offset is a `spi-bcm2835` (or SPI core) regression on the newer kernel, **not** a property of the module or the board. On 6.6.138 no realignment is needed at all.
2. That makes the failure at the top of this thread (Pi 4 + WM1302 Pi HAT + Morse-patched **6.12.25**) most likely the same regression already present in an even older kernel packaging — not a hardware limitation of BCM2835 with the MM6108.

So the presumption in my earlier question ("is the BCM2835 controller known not to work with the MM6108?") is refuted by the new data point: it works, on the right kernel.

### Related SPI regressions in the same kernel window

Not the same bug, but the pattern of the kernel window is suggestive:

- [raspberrypi/linux#6854](https://github.com/raspberrypi/linux/issues/6854) — Pi 5 SPI throughput drops ~9% and gains timing jitter moving from 6.6.31 → 6.12.25. Open since May 2025, no maintainer response. Different platform (RP1), different symptom (perf, not correctness), but the same kernel window.
- [linux-spi list, msg 47394](https://www.spinics.net/lists/linux-spi/msg47394.html) — SPI kernel panic on TI am335x (`spi-omap2-mcspi`) at 6.6.71 and 6.12.8, traced to a specific `OMAP2_MCSPI_MAX_FREQ` fallback commit. Different driver, but a distinct SPI driver on a distinct SoC hitting an issue at overlapping stable tags makes a shared SPI-core-layer or bus-code change a plausible common cause.

None of these three are the same bug in isolation, but "something touching SPI landed between 6.6 and 6.12 and hurt more than one platform" is the shape they share.

### Offer

Happy to bisect the exact commit range if that would be useful — rebuilding Raspberry Pi OS's `rpi-6.6.y` on the affected card would tell us whether the regression is in mainline `spi-bcm2835`, in the SPI core, or in the raspberrypi/linux tree specifically.

---

## Update 2, 2026-08-22 — 6.12.93 also fails, identically

Rebuilt on stock **Raspberry Pi OS Bookworm** — kernel `6.12.93+rpt-rpi-v8`, no out-of-tree patches — using the same board, same driver release, and the same firmware/BCF binaries as the OpenMANET result above. The fingerprint is identical to the 6.18.34 failure:

- Without `spi_rx_lshift`: CMD63 fails, same `c0 7f ff ff` 2-bit RX offset on the wire.
- With `spi_rx_lshift=2`: firmware and BCF load (CRC32s match OpenMANET's copies byte-for-byte), then CMD53 write dies at:

  ```
  morse_spi spi0.0: spi: cmd53_write fn=1 0x00004050:4 r=0x10050002 b=0xffffffff (ret:-71)
  ```

  Register address, response bytes, and error code are verbatim to the 6.18.34 log — same bug.

New evidence in the repo:

- [logs/2026-08-22-bookworm-6.12.93-boot-dmesg.log](https://github.com/alan-sun-dev/halow-wm6108-rpi4/blob/main/logs/2026-08-22-bookworm-6.12.93-boot-dmesg.log)
- [logs/2026-08-22-bookworm-6.12.93-lshift-dmesg.log](https://github.com/alan-sun-dev/halow-wm6108-rpi4/blob/main/logs/2026-08-22-bookworm-6.12.93-lshift-dmesg.log)
- [logs/2026-08-22-bookworm-6.12.93-environment.txt](https://github.com/alan-sun-dev/halow-wm6108-rpi4/blob/main/logs/2026-08-22-bookworm-6.12.93-environment.txt)

| Kernel | RX byte alignment | CMD53 write | Outcome |
|---|---|---|---|
| **6.6.138** (OpenMANET 24.10, stock) | clean, no `spi_rx_lshift` needed | passes | ✅ `wlh0` up on SG @ 22 dBm |
| 6.12.25 (Morse-patched, top of thread) | (not measured) | fails `ret:-71` | ❌ probe fails |
| **6.12.93** (Raspberry Pi OS Bookworm, stock) | needs `spi_rx_lshift=2` | fails `ret:-71` at `0x00004050:4` | ❌ probe fails |
| **6.18.34+rpt-rpi-v8** (Raspberry Pi OS Trixie, stock) | needs `spi_rx_lshift=2` | fails `ret:-71` at `0x00004050:4` | ❌ probe fails |

Two takeaways:

1. **The regression window is now `6.6.138 → 6.12.93`** — twelve minor kernel releases narrower than after the last update.
2. **The failure at the top of this thread is not caused by the reporter's out-of-tree patches.** Stock 6.12 is already broken. That first datapoint can be trusted at face value.

If Morse's officially-supported kernel list runs 4.9 → 6.12, this bug is *inside* the supported range, not beyond it.

Bisecting the exact commit is still on offer — the 6.6 → 6.12 window in `raspberrypi/linux` is smaller than 6.6 → 6.18 and probably tractable in a day of builds if it would be useful.
