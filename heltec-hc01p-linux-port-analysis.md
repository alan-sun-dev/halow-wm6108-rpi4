# HT-HC01P → Raspberry Pi OS / morse_driver 2.0.1 — feasibility analysis

```
HT-HC01P (MM6108A2) + Heltec Pi HAT + Raspberry Pi 4B
                      ↓
        Raspberry Pi OS / Debian Linux
                      ↓
     MorseMicro/morse_driver tag mm6108-2.0.1
```

**Sources.** Live inventory of the working machine —
[`heltec-hc01p-hardware-inventory.md`](heltec-hc01p-hardware-inventory.md), raw transcript in
[`heltec-hc01p-raw-evidence.txt`](heltec-hc01p-raw-evidence.txt) — and the driver source at
tag `mm6108-2.0.1`, commit `98e1936c04ef9a62212c1c64b970218ecf08d15d`, read directly. Where a
statement comes from source it cites file and line. Where it comes from measurement it says
which measurement. Nothing here is from a README or a forum post.

**Nothing was ported in this round.** No change was made to the working machine.

> ## Status 2026-08-25 — the port is done, stages 0 to 4
>
> The HT-HC01P runs Raspberry Pi OS bookworm 6.6.51 with morse_driver 2.0.1 plus
> this repo's three `patches/upstream/` fixes: associated to the OpenMANET AP with
> SAE + PMF, `10.41.0.216` by DHCP, MCS7 / 4 MHz at the AP, SPI `errors 0`, and it
> comes up unattended from a cold start. Full account in NOTES.md, 2026-08-25.
>
> What this document predicted, and what happened:
>
> | | prediction | outcome |
> |---|---|---|
> | **L1** | defect B bites on 6.x | **measured.** Unpatched 2.0.1 fails at CMD63 `-71`, `mode=0x4` throughout, `c0 7f`. Same fingerprint as the Wio-WM6108, on Heltec's own device tree |
> | **U1** | BCF/firmware pairing unknown | **settled, works.** RF symmetry confirmed from the AP |
> | **U2** | SPI `mode` word unknown | **read: `0x4`**, i.e. `SPI_CS_HIGH`, already set before `morse_spi_initsequence()` runs |
> | **B1** | build blocker | **confirmed on a second machine** as a build failure, then fixed by patch 1 |
> | **B3** | GPIO 7 muxed as CS1 | **handled and verified:** pin 7 is `gpio_in`, GPIO-unclaimed; pin 8 is the only chip select |
> | **U3** | power-save handshake untested | **still open.** Power save is disabled, deliberately, and the WAKE/BUSY handshake has still never been exercised on 2.0.1 |
>
> Two things this document did not anticipate, both in NOTES.md: `macaddr_suffix`
> is mandatory or the driver invents a random MAC on every load, and
> `morse_driver` carries a git submodule that must be initialised or the build
> fails in a way that looks unrelated.
>
> **U4 revisited, 2026-08-25: 6.12.96 was tested too, and it works.** The board was
> upgraded to `6.12.96+rpt-rpi-v8`; pristine 2.0.1 fails to build there with the
> identical `spi.c:1519` error, the patched driver builds clean and runs, and the
> link comes up unattended with SAE + PMF, `errors 0`, MCS7. The driver source is
> byte-identical across both builds (`srcversion 87374779AA811C291578351`), so the
> kernel is the only variable. **`SPI_CONTROLLER_ENABLE_CS_GPIOD` was also counted
> directly in both kernels' `spi.h` — 0 occurrences in each** — which turns the
> "it is a Morse vendor-kernel flag" claim from inference into a measurement. This
> removes the "one kernel, two hardwares" caveat that the rest of this document and
> the upstream report were carefully hedged around. 6.6.51 remains the reference on
> the station board so both comparisons exist.

---

## 1. Verdict summary

### VERIFIED — established from source or live measurement

| # | Finding | Basis |
|---|---|---|
| V1 | **MM6108A2 is supported by 2.0.1.** `mm610x_chip_id_matches()` returns true for `MM6108A0_ID`, `MM6108A1_ID` and `MM6108A2_ID`. | `mm6108.c`, `hw.h:149-151` |
| V2 | **The board's chip ID is exactly the A2 constant.** `MORSE_DEVICE_ID(id,rev,type) = id \| rev<<8 \| type<<12`; `MM6108XX_ID 0x6`, A2 rev 4, `CHIP_TYPE_SILICON 0x0` → `0x406`. The chip reports `HW version: 0x00000406`. | `hw.h:105,143-151`; debugfs `vendor_info` |
| V3 | **The SPI probe path assumes A2.** `spi.c:1481` calls `morse_chip_cfg_init(mors, MM6108A2_ID)` before reading the real ID, then `morse_chip_cfg_set_and_validate()` reads `MORSE_REG_CHIP_ID` over the bus and returns `-ENODEV` on mismatch. A2 is the default, not an afterthought. | `spi.c:1481`, `hw.c` |
| V4 | **The compatible string matches.** 2.0.1's `of_device_id` table contains `"morse,mm610x-spi"`, which is exactly what the HAT's DT node declares. | `spi.c:194-198`; live DT |
| V5 | **The DT properties 2.0.1 requires are all present.** `reset-gpios` and `spi-irq-gpios` are hard-required by the SPI probe (`spi.c:1495`, `1500` bail out); `power-gpios` is optional and only degrades power save. The HAT supplies all three. | `spi.c:1493-1502`, `of.c`; live DT |
| V6 | **`power-gpios` is WAKE + BUSY, not a power rail.** `of.c` reads index 0 into `gpios->wake` and index 1 into `gpios->busy`. There is no power-enable GPIO on this board. | `of.c: morse_of_probe()` |
| V7 | **The DT `reset-gpios` flag is ignored by the driver.** `git grep gpiod_` over the whole 2.0.1 tree returns **zero** hits; `of_get_named_gpio()` discards flags; `morse_hw_reset()` uses the legacy integer API, which is raw. Flag 0 vs 1 changes nothing for morse_driver. | `of.c`, `hw.c:213`, tree-wide grep |
| V8 | **The driver drives RESET_N low for 20 ms then floats it, and this chip survives that.** `gpio_direction_output(pin,0); mdelay(20); gpio_direction_input(pin);`. `Resetting Morse Chip` is in this board's own log, followed by a clean firmware load and association. | `hw.c:213`; live dmesg |
| V9 | **A 1.15.3 A2 station and a 2.0.1 A1 AP interoperate on air today.** debugfs `vendor_info` shows both ends: local `SW 1.15.3 / HW 0x406`, peer `SW 2.0.1 / HW 0x306`, associated with SAE + PMF. | debugfs `vendor_info`, `wpa_cli_s1g status` |
| V10 | **The bus is clean at 50 MHz on this hardware.** 24.5 MB, 103138 messages, `errors 0`, `timedout 0`. | `/sys/class/spi_master/spi0/statistics/` |
| V11 | **`bcf_HC01_V2_H.bin` is not in the official firmware release.** `morse-firmware` at tag `mm6108-2.0.1` ships `bcf/{azurewave,morsemicro,netprisma,quectel}` — no Heltec directory, no HC01 file. | file listing of the 2.0 firmware tree |
| V12 | **Driver 2.0.1 wants a different `mm6108.bin`.** Release 2.0 ships 468304 B / sha256 `db3a23cb…`; this board runs 444304 B / sha256 `1c12fc42…` from 1.15.3. | both trees hashed |
| V13 | **Defect A is a build blocker on the target kernel and a no-op on the current one.** The `SPI_CONTROLLER_ENABLE_CS_GPIOD` block is inside `#if KERNEL_VERSION(6,1,21) <= LINUX_VERSION_CODE`. The board runs 5.15.167 → compiled out. Raspberry Pi OS bookworm is 6.6.x or 6.12.x → compiled in, and the `#else` arm is `#warning`, with `ccflags-y += -Wall -Werror` in the Makefile. | `spi.c:1553-1562`, `Makefile:16` |
| V14 | **Defect C does not reproduce at 50 MHz.** The delay is `40000 ns / (clk_period_ns × 8)`; at 50 MHz that is `40000/160 = 250`, the correct value. The board's transfer histogram is dominated by the 256–511 byte bucket, consistent with a 250-byte pad. | `spi.c:1499-1503`; SPI histogram |
| V15 | **The stock Raspberry Pi `spi0_cs_pins` group would collide with MM_BUSY.** Upstream it is `brcm,pins = <8 7>`; GPIO 7 is MM_BUSY on this HAT. Heltec's overlay narrows the group to `<8>`. | decompiled `mm610x-spi.dtbo`; live pinctrl |
| V16 | **The HaLow interface name is not deterministic** and must be discovered via `/sys/class/net/*/device/driver == morse_spi`. | two boots observed, `brcmfmac … renamed from wlan0` |

### LIKELY — reasoned from evidence, not directly measured on this board

| # | Finding | Reasoning |
|---|---|---|
| L1 | **MEASURED 2026-08-25, no longer a likelihood — see the status block above.** **Defect B (the 74-clock training sequence with CS deasserted) will bite on the target and does not bite today.** Pristine `morse_spi_initsequence()` flips `SPI_CS_HIGH` to deassert CS for the training burst. On a controller using GPIO chip selects — which this HAT is, `cs-gpios = <&gpio 8 1>` — `spi_setup()` on recent kernels forces `SPI_CS_HIGH` back on so gpiolib applies the inversion once, making the flip a no-op. This repo measured exactly that failure on raspberrypi/linux 6.6.51 (`ff 01 ff` → `ff c0 7f`, a two-bit offset on every response). The board in front of us runs 5.15.167 and works, and since `morse_hw_reset()` genuinely pulses RESET_N at every probe, the training must be succeeding there — so the difference is the kernel, not the board. | source + this repo's prior measurement |
| L2 | **This reconciles the "RESET_N" story better than the version in NOTES.md.** The evidence does not support "flag 0 means RESET_N never fires" (V7 — there is no gpiod call to invert). What it supports is: RESET_N *does* fire everywhere, and what differs is whether the training burst afterwards puts the chip back into SPI mode. On the SenseCAP M1 under 6.6.51 it did not, so the reset was fatal; here under 5.15 it does, so the reset is harmless. Same driver behaviour, different outcome. | see §5 |
| L3 | **The Heltec overlay can be reused nearly verbatim on Raspberry Pi OS.** It targets `&spi0` and `&gpio` with standard bcm2711 groups, and the target kernel has the same `brcm,bcm2835-spi` driver and the same pin groups. | decompiled overlay; both are RPi 4B |
| L4 | **Power save is the cause of the asymmetric ping** (12–36 ms towards the AP, 18–199 ms back). `iw` reports `Power save: on` and `enable_ps=2`. | live readback; not yet tested by toggling |

### UNKNOWN — must be tested, do not assume

| # | Question | How to settle it |
|---|---|---|
| U1 | **SETTLED 2026-08-25: yes.** Loaded by 2.0.1 against firmware 2.0 (`crc32 0x389a48c4`), and the AP sees the station at `-1 dBm` with `rx packets` climbing and `tx retries 0` — the transmitter works, which is the only thing that could have failed. The `.board_config` window concern below did not materialise. Original question: **Does `bcf_HC01_V2_H.bin` (shipped for 1.15.3) work with 2.0 firmware and driver 2.0.1?** Narrowed 2026-08-24 by opening the file (see `firmware/heltec-hc01p/README.md`): it is an ELF32 RISC-V object whose `.chips` section reads **`mm610x`** — it is tagged to the chip *family*, not to a driver or firmware release — and it carries a `.regdom_SG` section, so the regulatory domain this project uses is present. Nothing in it names 1.15.3. What remains is one specific risk: `.board_config` has a fixed load address `0x8011fa80`, while the driver copies sections into a window whose address and size come from **firmware** TLVs (`MORSE_FW_INFO_TLV_BCF_ADDR` / `_SIZE`, `firmware.c:110-128`). A 2.0 firmware advertising a different window would place it wrong. | Load it and check for **RF symmetry**: the AP must see the station at a sane RSSI, not just the station see the AP. That asymmetry is exactly the failure signature already characterised on this board, and every earlier gate passes on the receive side regardless. |
| U2 | **ANSWERED 2026-08-25: `0x4`.** Read exactly as suggested, with a `dev_info` on the ported system: `init: entry mode=0x4 cs_high_default=1`. `SPI_CS_HIGH` is already set by the core before `morse_spi_initsequence()` runs, and stays set through both `spi_setup()` calls — which is defect B, observed directly on this HAT. | done; instrumentation kept at `port/hc01p/instrument-initsequence.patch` |
| U3 | **Whether 2.0.1's power-save handshake works with this HAT's WAKE/BUSY wiring.** The HAT supplies both, and 1.15.3 uses them (IRQ 46 `async_wakeup_from_chip`, 4968 interrupts taken), but 2.0.1's PS code has not been exercised on this board. | Bring the link up with `enable_ps=0` first; enable PS only after STA mode is proven. |
| U4 | **DECIDED AND USED: 6.6.51**, from the 2024-11-19 image, which ships matching `linux-headers` so nothing had to be copied from the station board. **Which Raspberry Pi OS kernel to target.** This repo has measured 6.6.51 (2024-11-19 image) and 6.12.x, both failing *without* the three patches and 6.6.51 working *with* them — but on the Wio-WM6108, not on this HAT. | Use 6.6.51 for maximum overlap with work already done. |
| U5 | **Whether the `dtoverlay=mm_wlan` line matters.** The overlay file does not exist on the working image, so it is a no-op there — but it may exist in a Heltec source tree and do something the working board is getting from elsewhere. | Nothing on the working board depends on it; treat as absent unless a symptom appears. |

### BLOCKER — will stop the port unless handled

| # | Blocker | Handling |
|---|---|---|
| B1 | **CONFIRMED ON THIS BOARD 2026-08-25 and handled.** Pristine 2.0.1 on this Pi's 6.6.51: `spi.c:1519:2: error: #warning "SPI_CONTROLLER_ENABLE_CS_GPIOD macro not defined" [-Werror=cpp]`, `make ... Error 2`, no `morse.ko`. With patch 1 the same command builds with zero errors and zero warnings. **`morse_driver` 2.0.1 does not build on a kernel ≥ 6.1.21 that lacks `SPI_CONTROLLER_ENABLE_CS_GPIOD`** — the `#else` arm is a `#warning` and the Makefile passes `-Werror`. Raspberry Pi OS kernels do not define that macro. | Apply this repo's `patches/upstream/` patch 1. Already written and already carried in `patches/morse-driver-2.0.1-rpi-spi.patch`. |
| B2 | **`bcf_HC01_V2_H.bin` exists only on the working board.** It is not in the official firmware release, not in Debian, and not downloadable from Morse. **Worse, confirmed 2026-08-24: Heltec's own download page for this product serves the wrong file.** `https://resource.heltec.cn/download/HT-HC01P/BCF/driver_1_15_3/bcf_HC0P.bin` is byte-identical to `bcf_mf08551.bin` (sha256 `57c50cb2…`, 1150 B) and its `.board_desc` reads `mf08551` — Morse's EKH01-03 evaluation board, i.e. exactly the file that produced the receive-only radio. Losing our copy means losing the transmitter, and the obvious place to re-obtain it hands back the broken one. | **Done 2026-08-24** — preserved at `firmware/heltec-hc01p/bcf_HC01_V2_H.bin` with provenance and structure notes in that directory's README. 1170 bytes, sha256 `5744fa288d79cd2a8ad8e146bec9aff8d06a6f87c160a0a44358ceb6cd53ba9f`, verified three ways on the day of the copy. Verify the hash after every further copy. |
| B3 | **Enabling SPI on Raspberry Pi OS the ordinary way muxes GPIO 7 as a second chip select, and GPIO 7 is MM_BUSY.** `dtparam=spi=on` brings in the stock `spi0_cs_pins` with `brcm,pins = <8 7>`. | **Done and verified 2026-08-25** in `overlays/mm610x-spi-hc01p.dts`, which narrows both `spi0_cs_pins` to `<8>` and `cs-gpios` to a single entry (the base DTB declares `<&gpio 8 1>, <&gpio 7 1>`). Live check: pin 7 is `function gpio_in`, `GPIO UNCLAIMED`; pin 8 is `gpio_out` and the only `spi0 CS0`. The port overlay must override `spi0_cs_pins` to `brcm,pins = <8>`, exactly as Heltec's does. |

---

## 2. Requirement 8 — point-by-point compatibility

**MM6108A2 chip ID supported by 2.0.1** — **VERIFIED, yes.**

```c
/* hw.h */
#define MORSE_DEVICE_ID(chip_id, chip_rev, chip_type) \
        ((chip_id) | ((chip_rev) << 8) | ((chip_type) << 12))
#define MM6108XX_ID 0x6
#define CHIP_TYPE_SILICON 0x0
#define MM6108A1_ID MORSE_DEVICE_ID(MM6108XX_ID, 3, CHIP_TYPE_SILICON)   /* 0x306 */
#define MM6108A2_ID MORSE_DEVICE_ID(MM6108XX_ID, 4, CHIP_TYPE_SILICON)   /* 0x406 */

/* mm6108.c */
static bool mm610x_chip_id_matches(u32 chip_id)
{
        return chip_id == MM6108A0_ID || chip_id == MM6108A1_ID || chip_id == MM6108A2_ID;
}
```

The board reports `0x00000406`. It matches the A2 constant exactly, and `spi.c:1481`
initialises the chip config as A2 in the first place.

**SPI probe path** — `morse_spi_probe()` in order: allocate `mspi`; compute
`inter_block_delay_bytes` from `spi->max_speed_hz`; `morse_chip_cfg_init(MM6108A2_ID)`;
`morse_of_probe()` for the GPIOs; require `reset-gpios` and `spi-irq-gpios`;
`morse_spi_reset()` unless reattaching; set `SPI_CONTROLLER_ENABLE_CS_GPIOD` on ≥6.1.21;
`morse_spi_xfer_init()`; `morse_spi_initsequence()`; up to 3 × `SD_IO_MORSE_INIT` (CMD63)
with `SD_IO_RESET` between attempts; `morse_chip_cfg_set_and_validate()` (reads the real chip
ID); then firmware load. Every step in that chain is satisfied by this HAT's device tree.

**Device-tree property requirements** — required: `compatible = "morse,mm610x-spi"`, `reg`,
`reset-gpios`, `spi-irq-gpios`. Effectively required: `spi-max-frequency` (it feeds the delay
computation; leaving it out would give a nonsense delay). Optional: `power-gpios` — missing
or incomplete only logs *"optional property power-gpios incomplete, powersave won't be
supported"*. The HAT supplies all of them.

**RESET handling** — see §5 below, it needs its own section.

**IRQ handling** — the driver takes the interrupt from `spi-irq-gpios` (GPIO 25) rather than
the SPI controller's own IRQ; on the live board that is IRQ 47, `Morse SPI IRQ`,
**level-low**, 7707 taken, while the controller IRQ 18 has taken zero. `spi_use_edge_irq=N`
matches the level trigger. `morse_spi_remove_irq()` does `free_irq()` + `gpio_free()`, so
the line is released on unload. Nothing here is kernel-version sensitive.

**WAKE / BUSY requirements** — optional for basic operation, required for power save.
`morse_hw_ps_gpios_are_supported()` gates it. On this HAT both are wired (GPIO 3 out, GPIO 7
in with an edge-rising IRQ) and 1.15.3 uses them actively. Recommendation: start the port
with `enable_ps=0` so that a power-save bug cannot masquerade as a link bug, then enable it.

**CONFIG_MORSE_SPI** — a Kconfig bool (`config MORSE_SPI / bool "SPI support"`) that becomes
`-DCONFIG_MORSE_SPI` in `ccflags`. For an out-of-tree build it must be passed explicitly on
the make line; it is not inferred from the device tree.

**Firmware compatibility** — the driver builds the path as `MORSE_FW_DIR "/" MM6108_FW_BASE
… MORSE_FW_EXT` = `morse/mm6108.bin`, overridable with the `fw_bin_file` parameter. Driver
2.0.1 must be paired with the 2.0 firmware (468304 B, `db3a23cb…`), **not** the 444304 B
1.15.3 firmware on this board. The firmware carries TLV metadata that tells the driver where
and how large the BCF window is, which is the mechanism that makes U1 a real question.

**BCF compatibility** — the name comes from the `bcf` module parameter and is resolved as
`morse/<name>`; if unset the driver tries `bcf_boardtype_%04x.bin` from the OTP board ID and
then `bcf_%s.bin` from the board serial. **Neither fallback can work here** — the OTP board
type is unset (`morse_cli boardtype` → "Board type is not set", sysfs `board_type` = 0), so
the name must be given explicitly, exactly as Heltec does. Same parameter name in 2.0.1, so
`bcf=bcf_HC01_V2_H.bin` carries over unchanged.

**dot11ah requirements** — `dot11ah` is a separate module built from the `dot11ah/`
subdirectory of the same repository and is a hard dependency (`lsmod` shows `dot11ah 73728 1
morse`). It must be built and installed alongside. It is the piece that maps S1G channels
onto the mapped 5 GHz channels that `iw` reports, which is why `iw` shows this station on
"channel 153 (5765 MHz), width 80 MHz".

**Raspberry Pi `spi-bcm2835` compatibility** — the HAT's controller node is
`brcm,bcm2835-spi`, the same driver Raspberry Pi OS uses, built in on both. Two caveats:
B3 above (the CS pin group), and the fact that `spi-bcm2835` has `polling_limit_us=30`, so
short transfers are polled rather than DMA'd — the 16–31 byte bucket holds 36713 of this
board's transfers, all of which take that path. Nothing to change, but it explains where the
CPU time goes.

---

## 3. Requirement 9 — do the three known SPI defects apply to the HT-HC01P?

### A. `SPI_CONTROLLER_ENABLE_CS_GPIOD` build issue — **YES on the target, NO today. BLOCKER (B1).**

```c
#if KERNEL_VERSION(6, 1, 21) <= LINUX_VERSION_CODE
#ifdef SPI_CONTROLLER_ENABLE_CS_GPIOD
        spi->controller->flags |= SPI_CONTROLLER_ENABLE_CS_GPIOD;
#else
#warning "SPI_CONTROLLER_ENABLE_CS_GPIOD macro not defined"
#endif
#endif
```

with `Makefile:16  ccflags-y += $(DEBFLAGS) -Wall -Werror`.

The board runs **5.15.167**, so the outer `#if` is false and the code never compiles — which
is why Heltec never hit this. Raspberry Pi OS bookworm is 6.6.x or 6.12.x, where the outer
`#if` is true, the macro is not defined by the kernel, and `-Werror` turns the `#warning`
into a hard build failure. Not a runtime problem — the driver simply does not build.

This is board-independent: it depends only on the kernel version and the macro's absence, so
it applies to the HT-HC01P port identically to the Wio-WM6108 one. This repo's patch already
replaces the `#warning` with a comment explaining why nothing is needed on such kernels.

### B. 74 clocks with CS deasserted, and `SPI_CS_HIGH` on a `cs-gpios` controller — **LIKELY YES on the target (L1).**

The HT-HC01P is squarely in the affected class: it uses a **GPIO chip select**,
`cs-gpios = <&gpio 8 1>`, with the pin muxed as `gpio_out` by `spi0_cs_pins`. That is the
configuration in which flipping `SPI_CS_HIGH` fails to deassert CS, because `spi_setup()`
forces the bit back on so gpiolib can apply the active-low inversion exactly once — leaving
the training burst to go out with the chip *selected*.

Two things keep this from being a certainty rather than a likelihood:

1. The failing measurement in this repo was taken on raspberrypi/linux **6.6.51** with a
   Wio-WM6108 on a SenseCAP M1 carrier. It has not been reproduced on 5.15 or on this HAT.
2. This board works today *despite* `morse_hw_reset()` genuinely pulsing RESET_N at every
   probe (V8). If the training burst were failing here, the chip would not come back — so on
   5.15 the training is evidently working.

Together those point at the kernel version as the discriminator, which is what makes the
defect **likely to appear the moment this HAT is moved to a 6.x kernel** — the port's whole
point. Carry patch 2.

Note the one hardware difference that does **not** matter: the SenseCAP M1 declares two chip
selects (GPIO 8 and 7), this HAT one (GPIO 8). The mechanism depends on CS being a GPIO
descriptor at all, not on how many there are.

### C. Inter-transaction delay as clocks rather than elapsed time — **applies in principle, invisible at 50 MHz (V14).**

```c
mspi->inter_block_delay_bytes =
        mors->cfg->get_spi_inter_block_delay_ns(burst_enabled) /
        (SPI_CLK_PERIOD_NANO_S(mspi->spi->max_speed_hz) * 8);
```

At `spi-max-frequency = 50 MHz` the clock period is 20 ns, so `40000 / (20 × 8) = 250` — the
value the chip actually needs. The formula is wrong in model but right in result. It only
produces a broken value below full clock (50 bytes at 10 MHz), which is why this defect has
never been visible on any board that inherited the reference 50 MHz.

**The 250-byte minimum padding still applies to this hardware**, and the live SPI histogram
supports it: 56565 of 103138 transfers land in the 256–511 byte bucket, which is what a
~250-byte pad on top of a 256-byte block looks like. Carry patch 3 as a correctness fix — it
is a no-op at 50 MHz and the only thing standing between the port and a broken bus if anyone
ever lowers the clock.

**Practical consequence for the port plan:** keep `spi-max-frequency = <50000000>`. Do not
"start conservative at 10 MHz" — on this driver that is the setting that breaks, not the safe
one.

---

## 4. Requirement 10 — RESET_N, explicitly

**The device tree on the working machine says:**

```dts
reset-gpios = <&gpio 5 0>;
```

GPIO controller `gpio@7e200000` (`brcm,bcm2711-gpio`, `#gpio-cells = <2>`), **GPIO number 5**,
**flag cell 0**.

**Linux device-tree GPIO semantics.** The flags cell is a bitfield; bit 0 is
`GPIO_ACTIVE_LOW` (`include/dt-bindings/gpio/gpio.h` defines `GPIO_ACTIVE_HIGH 0` and
`GPIO_ACTIVE_LOW 1`). It declares the line's **logical polarity for consumers of the
descriptor API** — with flag 0, `gpiod_set_value(desc, 1)` drives the pin physically high;
with flag 1, the same call drives it physically low. It says nothing on its own about what
the hardware's reset input expects, and it is *not* a statement of the pin's idle level.

**What Linux actually does here, which is not what the flag suggests.** morse_driver never
uses the descriptor API:

- tree-wide `git grep gpiod_` over 2.0.1 → **zero hits**;
- `of.c` reads the pin with `of_get_named_gpio()`, which returns the number and drops the
  flags — `of_get_named_gpio_flags()` is never called, and `GPIO_ACTIVE_LOW` /
  `OF_GPIO_ACTIVE_LOW` appear nowhere;
- `hw.c: morse_hw_reset()` uses the legacy integer API, and the legacy calls are the *raw*
  ones (`gpio_direction_output()` → `gpiod_direction_output_raw()`), which bypass polarity
  inversion by definition.

So the sequence on every probe and every unload is, in physical terms:

```
gpio_request(5, "morse-reset-ctrl")
gpio_direction_output(5, 0)   ->  GPIO 5 driven LOW      (RESET_N asserted; it is active low)
mdelay(20)
gpio_direction_input(5)       ->  GPIO 5 released to float, rises through the HAT's pull
gpio_free(5)
```

with the source's own comment on the third line: *"setting gpio as float to avoid forcing
3.3V High"*.

**Between resets the line is not driven at all.** `morse-ps.dtbo` parks it as
`function = "gpio_in"; bias-disable;`, and the live state agrees:
`/sys/kernel/debug/gpio` shows `gpio-5 (MM_RESET)` with **no consumer**, `gpioinfo` shows
`unused input`, and the pin reads high.

**Answers to the three parts of the question:**

| | |
|---|---|
| GPIO number | **5** |
| DT flag | **0** (`GPIO_ACTIVE_HIGH`) |
| Active polarity, as the hardware needs it | **active LOW** — RESET_N |
| Does the flag control that? | **No.** It is parsed away and never reaches a descriptor. Setting it to 1 would change nothing in morse_driver. |
| How the kernel asserts RESET_N | by driving GPIO 5 physically low for 20 ms via the raw legacy API |
| How it de-asserts | by switching the pin to an input and letting it float high — deliberately, so the SoC never forces 3.3 V into the module |

---

## 5. A correction this analysis forces, and its limits

NOTES.md currently records, under *"Why OpenMANET never needed the fix"*:

> its `reset-gpios` flag is 0, so `gpiod_set_value(reset, 1)` drives the pin *high* and
> RESET_N never fires

**That mechanism cannot be right for morse_driver 2.0.1**, because there is no
`gpiod_set_value` — or any other `gpiod_` call — anywhere in the tree (V7). The measurement
that section rests on is not in dispute: a cold power-up gives `ff 01 ff` and a RESET_N pulse
in the same power-on turns it into `ff c0 7f`. What is wrong is the explanation of why some
implementations escape it.

**What the evidence supports instead.** RESET_N fires on *every* implementation, including
this one, because the driver always drives the pin low regardless of the flag. What differs
is whether the training burst immediately afterwards succeeds in putting the chip back into
SPI mode:

- HT-HC01P, kernel 5.15.167, GPIO chip select: reset fires, training works, chip comes up —
  observed directly, `Resetting Morse Chip` followed by a clean load.
- Wio-WM6108 on SenseCAP M1, raspberrypi/linux 6.6.51, GPIO chip selects: reset fires,
  training goes out with CS still asserted, chip stays out of SPI mode, every response two
  bits off — this repo's own measurement.

Same driver code, same reset, different kernel, different outcome. That makes defect B the
load-bearing one and demotes the reset-flag story to a red herring — which also explains why
*"testing flag 0 alone changed nothing"*, already recorded in NOTES.md as an unexplained
result. It is no longer unexplained.

**Settled the same day, and the answer is better than the guess above.** The check was run:
OpenMANET's `morse-feed` at the pinned `fc332b0` applies 18 patches to the driver and **not
one of them touches `morse_hw_reset()`, `gpiod_`, or `reset-gpios`** — the only GPIO patch
adds a separate 4v3 FEM line, also through the legacy `gpio_*` API. The AP runs
`rel_mm6108_2_0_1_2026_Jun_11`, i.e. this exact source, and its own boot log carries
`Resetting Morse Chip`. So it resets, with the same code, and the flag is inert there too.

What OpenMANET has instead is a **kernel** patch, written by Morse Micro:
`OpenMANET/firmware`,
`target/linux/bcm27xx/patches-6.6/991-0007-spi-support-control-cs-pin-on-init.patch`
(Sagar Bussa <sagar.bussa@morsemicro.com>, 2025-03-13; identical copy in `MorseMicro/openwrt`).
It adds `SPI_CONTROLLER_ENABLE_CS_GPIOD` to `include/linux/spi/spi.h` and two conditions to
`drivers/spi/spi.c`: `spi_setup()` stops forcing `SPI_CS_HIGH` for a `cs-gpios` device, and
`spi_set_cs()` honours the driver's CS_HIGH flip. Its commit message says why in as many
words — *"The Morse Micro driver requires control of the chip select line during
initialisation, to correctly sequence the line to enter SPI mode."*

That is the whole difference between the AP and the station: same SenseCAP M1, same MM6108A1,
same driver 2.0.1, same `cs-gpios = <&gpio 8 1>`, same reset at probe — different kernel tree.
And it upgrades L1 from a likelihood to a mechanism: on a Raspberry Pi OS kernel, which does
not carry that patch, the CS-deassert in `morse_spi_initsequence()` cannot work.

**Independent confirmation.** `OpenMANET/packages` carries
`morse-micro/mm6108-driver/patches/021-spi-demote-cs-gpiod-warning-to-runtime.patch`: *"…not
a mainline kernel flag; it is added by a Morse Micro patch … that only the bcm27xx target
carries … the driver's `#warning` fallback is fatal under the kernel's `-Werror` … Without it
CS may be forced high during `spi_setup`."* A third party hit B1 on a ramips target and fixed
it the same way this repo did.

**Consequence for the upstream report.** Morse Micro's own answer to defect B is to patch the
kernel's SPI core. This repo's `SPI_NO_CS` fix does it in the driver and needs no kernel
patch, so it works on a stock Raspberry Pi OS kernel. The community claim that *"patching the
kernel is practically required"* now has a specific named patch behind it — and this repo is
still the counter-example.

---

## 6. Minimal-change Linux port plan

Principles, as set: leave the working machine untouched; second SD card; morse_driver 2.0.1;
the correct HC01P BCF; STA mode only; no AP, mesh, BATMAN or NAT in stage 1; success is
scan → SAE/PMF → DHCP → ping.

### Stage 0 — preserve what cannot be recovered

1. ~~Copy `bcf_HC01_V2_H.bin` off the board and verify it.~~ **Done 2026-08-24.** It is at
   `firmware/heltec-hc01p/bcf_HC01_V2_H.bin`, 1170 bytes,
   `sha256 5744fa288d79cd2a8ad8e146bec9aff8d06a6f87c160a0a44358ceb6cd53ba9f`, checked
   against the inventory value, against a fresh `sha256sum` on the board, and against the
   local copy. **This is the single irreplaceable artefact (B2).**
2. Keep `heltec-hc01p-raw-evidence.txt` as the reference for what "working" looks like.
3. Do not reflash the working SD card. Physically label it.

### Stage 1 — base system  ✅ done 2026-08-25

4. Raspberry Pi OS Lite arm64, **2024-11-19 image, kernel 6.6.51** (U4) — the one this repo
   has already characterised, so any failure can be compared against known results rather
   than investigated from scratch.
5. Boot it, confirm the Pi is healthy, `dtparam=spi=on` **not yet** — the overlay will bring
   SPI up with the right CS group.

*Done as recorded.* Two notes for anyone repeating it: the 2024-11-19 image
**already ships `linux-headers-6.6.51+rpt-rpi-v8` at the matching version**, so no
build environment has to be transplanted — only `git`, `build-essential` and `bc`
were added, and `apt` was checked first to be sure nothing upgraded the kernel.
And the image's `raspberrypi-sys-mods` is too old for Imager's `custom.toml`, so
first-boot provisioning went through `firstrun.sh` plus a `cmdline.txt` line; the
payload is in `port/hc01p/`.

*Gate: the Pi boots and is reachable. Nothing Morse-related yet.*

### Stage 2 — device tree  ✅ done 2026-08-25

6. Write `overlays/mm610x-spi-hc01p.dts` from the decompiled Heltec overlay, keeping every
   value: `reg = <0>`, `spi-max-frequency = <50000000>`, `reset-gpios = <&gpio 5 0>`,
   `power-gpios = <&gpio 3 0>, <&gpio 7 0>`, `spi-irq-gpios = <&gpio 25 0>`,
   `cs-gpios = <&gpio 8 1>`, both `spidev` nodes disabled.
7. **Override `spi0_cs_pins` to `brcm,pins = <8>`** — without this GPIO 7 is muxed as CS1 and
   MM_BUSY is lost (B3).
8. Optionally replicate `morse-ps.dtbo`'s pin parking (GPIO 5 `gpio_in`/`bias-disable`,
   GPIO 7 `gpio_in`/`bias-pull-down`). Not required for probe, but it is the state the
   working machine boots into.
9. `dtc` it, install the `.dtbo`, add the `dtoverlay=` line, reboot.

*Gate: `/proc/device-tree/soc/spi@7e204000/mm6108@0/` exists with the same property bytes as
recorded in the inventory, and `pinctrl` shows pin 8 `gpio_out` with pin 7 free.*

### Stage 3 — driver and firmware  ✅ done 2026-08-25

10. Clone `morse_driver` at tag `mm6108-2.0.1` and apply this repo's three patches
    (`patches/morse-driver-2.0.1-rpi-spi.patch`, or `patches/upstream/` individually).
    Patch 1 is mandatory or the build fails (B1); patches 2 and 3 are the runtime fixes.
11. Build with `CONFIG_MORSE_SPI=y` (and `CONFIG_MORSE_DEBUGFS` — `vendor_info` and
    `firmware_path` were the most useful instruments in this whole inventory). Build
    `dot11ah` from the same tree.
12. Install firmware from `morse-firmware` release 2.0: `mm6108.bin`, 468304 B,
    `db3a23cb…`, into `/lib/firmware/morse/`.
13. Install the preserved `bcf_HC01_V2_H.bin` into `/lib/firmware/morse/` and re-verify its
    hash.
14. `/etc/modprobe.d/morse.conf`:
    `options morse country=SG bcf=bcf_HC01_V2_H.bin enable_ps=0`
    — `enable_ps=0` deliberately, so power save cannot be confused with a link fault (U3).

    *Revised in practice.* `enable_ps=0` was used for the bring-up runs, but the
    driver logs *"enable_ps modparam must only be used for testing - use iw set
    power_save"* every time it sees it, so the installed configuration drops it and
    disables power save through the `halow` NetworkManager profile's
    `wifi.powersave=2` instead — the mechanism already proven persistent on the
    other three boards. Verified after a reboot: modparam back at the driver
    default `2`, `iw get power_save` **off**, and 20 pings at avg 4.487 ms with
    **mdev 0.163 ms**.

    **`macaddr_suffix=40:8e:91` also belongs in this file and is not optional.**
    Without it the driver invents a random MAC at every load, which churns the AP's
    station table and the DHCP lease on every boot. With it the module gets back
    its own `0c:bf:74:40:8e:91`. The installed line is:
    `options morse country=SG bcf=bcf_HC01_V2_H.bin macaddr_suffix=40:8e:91`

*Gate: `modprobe morse` gives `Morse Micro SPI device found, chip ID=0x0406`, then
`Loaded firmware from morse/mm6108.bin` and `Loaded BCF from morse/bcf_HC01_V2_H.bin`, and
`/sys/class/spi_master/spi0/statistics/errors` stays 0.*

If the chip ID line does not appear, or appears with a wrong ID, that is defect B — check
before anything else, because it is the failure this hardware is most likely to hit on 6.6.

### Stage 4 — STA mode  ✅ done 2026-08-25

15. Find the interface by driver, never by name (V16):
    `for n in /sys/class/net/*; do [ "$(basename "$(readlink -f "$n/device/driver")")" = morse_spi ] && basename "$n"; done`
16. Scan and confirm the AP is visible with an RSN element, not `[WEP]`.
17. `wpa_supplicant` with the same network block the working board uses: `key_mgmt=SAE`,
    `sae_password`, `proto=RSN`, `pairwise=CCMP`, `ieee80211w=2`, `sae_pwe=1`,
    `country=SG`, `scan_ssid=1`. Stock `wpa_supplicant` 2.10 was sufficient for the other
    station in this project; no Morse-specific supplicant is needed for STA.
18. DHCP, then ping.

*Success criteria, in order, each one checked before the next:*

```
scan          the AP appears with [WPA2-SAE-CCMP][SAE-H2E][ESS]
authenticate  "authenticated" on the first attempt, no CONN_FAILED backoff
associate     RX AssocResp status=0
key           EAPOL 4-way completed, PTK=CCMP GTK=CCMP, pmf=2
DHCP          a lease on the HaLow segment
ping          0% loss, both directions
RF symmetry   the AP's station dump shows a sane RSSI for this MAC
```

That last line is not decoration. It is the check that settles U1: a wrong or incompatible
BCF produces a station that receives perfectly and transmits nothing, and every earlier gate
still passes on the *receive* side. If the AP cannot see it, suspect the BCF before anything
else.

### Explicitly out of scope for stage 1

AP mode, mesh, BATMAN, NAT, bridging, `openmanetd`, power save, and any throughput work.
Power save in particular should stay off until the link is proven, then be enabled as its
own experiment (U3, L4).

---

## 7. What would falsify the main conclusions

- ~~**V7/§5** would fall if a `gpiod_` call exists in a build of the driver that this project
  actually runs but has not read — specifically OpenMANET's built-in copy.~~ **Checked
  2026-08-24: no such call exists.** The feed's 18 driver patches leave `morse_hw_reset()`
  untouched, and the AP's own log shows it resetting. V7 stands.
- ~~**L1** would fall if a 6.6-kernel build of unpatched 2.0.1 on this HAT probes cleanly.~~
  **Run 2026-08-25, and it did not probe cleanly.** Patch 1 only, patches 2 and 3 absent
  (verified by grep count before building): `failed to init SPI with CMD63 (ret:-71)`, and with
  instrumentation `mode=0x4` at all three points plus `c0 7f` where `01 ff` was expected. L1
  stands and is now measured rather than reasoned. At the time of that run the kernel was the
  one thing held constant, making it *one kernel on two hardwares*. **That caveat was removed
  later the same day**: the board was moved to 6.12.96 and the whole sequence re-run — pristine
  2.0.1 fails to build with the identical error, the patched driver builds clean and the link
  comes up. It is now two kernels on two hardwares, and the macro's absence was counted in both
  kernels' headers rather than inferred.
- ~~**U1** would be settled either way by the RF-symmetry check at stage 4.~~ **Settled 2026-08-25:
  the AP sees the station at `-1 dBm`, `rx packets` climbing, `tx retries 0 / tx failed 0`, and
  mmrc holds MCS7 at 100% over 49/49 attempts. The BCF is compatible.**
