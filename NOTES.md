# Wio-WM6108 (MM6108A1) on SenseCAP M1 — bring-up state, 2026-08-19

*[中文版](NOTES.zh-TW.md)*

## 2026-08-23: SOLVED — the chip never entered SPI mode

The 2-bit skew is fixed. Root cause, in one sentence: **the MM6108 needs ~74
clocks with chip select deasserted to enter SPI mode, and on a `cs-gpios`
controller `morse_spi_initsequence()` never delivers them.**

Morse state the requirement directly, in their i.MX93 porting thread:

> in order to put it into SPI mode, the host needs to toggle the SPI clock line
> ~74 times while the CS pin is held high — ie, inverted compared to normal
> operation.

and, of a host that failed the same way this one did:

> The original configuration had the chip select driven low during
> initialization, preventing the device from responding to subsequent commands.

`morse_spi_initsequence()` tries to arrange that by flipping `SPI_CS_HIGH` around
the burst. It does not work, and the mode logging added to `patches/` shows why:

```
init: mode=0x4 cs_high_default=1 train=18 flip=1
init: CS deasserted for training, mode=0x4     <-- expected 0x0
init: CS polarity restored, mode=0x4
```

`0x4` is `SPI_CS_HIGH`, still set immediately after `spi->mode &= ~SPI_CS_HIGH;
spi_setup(spi);` — **`spi_setup()` forces it back on for a cs-gpios device.** The
74 clocks go out with the chip *selected*, it never enters SPI mode, and every
response afterwards sits two bit times off the byte grid.

### The fix

`SPI_NO_CS` achieves what the flip cannot — the controller leaves the CS line
alone, so the GPIO stays high for the whole burst. Guarded by `spi_init_no_cs`
(default on), with the old flip as a fallback.

**Order matters and this is what hid the answer:** the burst has to happen after
reset and before any other transaction. Once the chip has been addressed with CS
asserted it does not recover. An earlier userspace attempt did the training
*after* a first CMD0, saw no change, and looked like a negative result.

### Verified

Userspace, CS driven by hand with `SPI_NO_CS` set so the controller could not
interfere, full reset before each trial:

| sequence | response |
|---|---|
| CS held HIGH throughout, CMD0 | `ff ff ff ff` — silent, confirming CS really is under manual control |
| CS LOW, CMD0, no training | `ff c0 7f ff` — R1 @bit10, **skewed** |
| 80 clocks @ CS HIGH, then CMD0 | `ff 01 ff ff` — R1 @bit8, **aligned** |

6/6 reproducible. After a correct init, `CMD0`→`0x01`, bad CRC→`0x09`,
`CMD13`→`0x05`, `CMD63`→`0x01`, all on the byte boundary.

Then in the driver, one parameter, same binary, same board:

| `spi_init_no_cs` | result |
|---|---|
| `Y` (default) | `training with SPI_NO_CS, mode=0x44`; no skew, CMD63 passes, firmware and BCF load |
| `N` (old behaviour) | `CS deasserted for training, mode=0x4`; `c0 3f` / `c0 7f` returns |

**`spi_rx_lshift` is no longer needed.** Every earlier run required it even to
read the chip ID; these pass none and the read path works natively — 468 KB of
firmware transfers correctly.

### Still open: the CMD53 write path

A different problem, and now visible for the first time:

| | before | after |
|---|---|---|
| chip's answer | 519 bytes after CRC, all `0xff` — silent | answers; `b=0x001f0002` |
| failure point | `fn=1 0x00004050:4` | `fn=2 0x00000000:14` — the firmware download, much further in |

Morse's OpenWrt-only `find_data_ack` change (scan for an accept token instead of
stopping at the first non-`0xff` byte) is implemented behind `spi_ack_scan`,
default on. **On this board it changes nothing** — the scan runs the full 3440
bytes and finds no `0x05`. Recorded because it is vendor-sanctioned and would
otherwise be tried again.

### Why it took fifteen eliminations

Every earlier hypothesis was about the bus — kernel tree, device tree, clock,
pulls, power sequencing, the driver's own padding. The answer was that the chip
was in the wrong *mode* the whole time, and nothing about the bus could reveal
that. The mode logging that exposes it was added late, and its significance only
became clear once Morse's own wording turned up in a forum thread about a
completely different SoC.

Full detail: `logs/2026-08-23-nocs-init-fix-environment.txt`.

---

## 2026-08-23: fourteen eliminations, and where this line ends

The device tree on the failing board now matches the working one **property for
property, all at once** — single `cs-gpios`, GPIO7 not claimed as a chip select,
`reset-gpios` flag 0, `spi0_pins` and the auxiliary pins pulled the same way, and
slot power applied by the VideoCore firmware rather than a DT hog. Verified in
effect after reboot. The failure is byte-identical: `c0 3f` / `c0 7f`, CMD63
`ret:-71`.

Four more eliminations beyond the ten below:

| Test | Why it looked plausible | Result |
|---|---|---|
| `gpio=18=op,dh` in config.txt | OpenMANET powers the slot from the **firmware stage**, seconds before the kernel; ours waited for gpiolib's hog. A chip that hasn't finished its power-on init emitting a misframed response would be deterministic, clock-independent and present from the first transaction — it fits every observed feature | unchanged |
| auxiliary pin pulls | our overlay pulls GPIO5 (SPI_INT) and GPIO23 (WAKE) **down**; OpenMANET pulls both **up** — a difference missed on the first pass | unchanged |
| `spi0_pins` pull-up **from boot** | RUN 6 flipped these at runtime, long after the SPI block was initialised. The idle level of SCLK at the moment the pin is muxed to ALT0 is a different thing, and only the overlay can set it | unchanged |
| all of the above simultaneously | each had only been tested alone, leaving "maybe it's a combination" open | unchanged |

### Correction: RUN 5's conclusion is withdrawn

RUN 5 swept 0…32 bytes of `0xff` before the command inside one CS assertion, saw
`@bit10` every time, and concluded it was *not* the host mis-sampling the start
of a transfer. **That inference is wrong.**

If the controller emits two extra clock edges after CS goes active and before the
first data bit, the chip takes those two bits and its byte grid is offset from
ours by two for the rest of the transfer. It still parses the command, because
MMC-SPI commands are self-framing on the `01` start bit and need no byte
alignment — which is exactly why it can validate our CRC7. Adding preamble does
not move that, because the spurious clocks come first. **The observation is what
the hypothesis predicts, not evidence against it.**

*(Note: this was not the answer either — the actual cause is in the top section of this file.)*

So "extra clocks at CS assert" is live again, and it is a host-side behaviour,
which fits the one stubborn fact: this is OS-dependent on identical hardware. The
measurement stands; only the conclusion was wrong.

### Where this line ends

Fourteen tests, no cause. The remaining candidates cannot be separated by more of
this kind of testing — every one of them is about what happens on the wire in the
first few microseconds of a transfer, and none of this can see that.

**The honest next step is a logic analyser** on SCLK / MOSI / MISO / CS. It shows
directly whether the controller clocks anything between CS going active and the
first data bit, and where the chip starts driving MISO. The pins are all on the
40-pin header.

---

## 2026-08-23: every device-tree difference the A/B found is eliminated

The A/B's four differences were closed with two overlay changes on the failing
side, and the failure is byte-identical throughout.

| Difference | Change | Result |
|---|---|---|
| `cs-gpios` two entries | `cs-gpios = <&gpio 8 1>` plus `spi0_cs_pins { brcm,pins = <8> }` — the second override is needed because the base rpi DT declares `<8 7>` | verified in effect (property 24 → 12 bytes, GPIO7 `MUX UNCLAIMED`); **skew unchanged** |
| `reset-gpios` flag 1 | `<&gpio 17 0>`, matching OpenMANET | verified in effect; **skew unchanged** |
| `spi-max-frequency` | — | already eliminated in RUN 4 |

The `reset-gpios` one deserves its epitaph. The flag is `GPIO_ACTIVE_LOW` and
`morse_hw_reset()` asserts with `gpiod_set_value(reset, 1)`, so flag 1 drives the
pin low and RESET_N really fires, while flag 0 drives it high — meaning on
OpenMANET the driver's reset pulse plausibly never happens. Since fixing
`reset_module()` in `tools/mmcspi.py` (making the reset actually occur) changed
CMD0's tail from `ff c0 7f` to `1f c0 7f`, "the reset pulse is what puts the chip
into the skewed state" was a real hypothesis. Dead.

**The failing board's `spi0` node now matches the working one on every difference
the A/B found, and it still fails identically.** The device-tree avenue is
exhausted — ten eliminations total.

### Board identity, recorded late

There are **two** SenseCAP M1 units and both have hostname `Sensecap`, so the
environment files — which recorded only the hostname — could not say which board
a run used. The archived boot dmesg settles it, via the MAC in the kernel command
line: `E4:5F:01:52:57:E7` for the 6.6.51 boot, the 6.12.93 boot, **and** both
OpenMANET runs. So **the same board both fails under Raspberry Pi OS and works
under OpenMANET** — the "same board" claim holds and is now backed by logs.

The second unit, `E4:5F:01:52:55:04`, runs the same card and shows a
byte-identical failure. A second board with a second module reproducing the skew
is corroboration, not a complication.

A trap worth knowing: `retest-*.log` lives on the SD card, not the board. Finding
those files on a machine proves only that the card has been in it since. Every
environment file records board MAC and serial from now on.

### What has never been compared

The base `bcm2711-rpi-4-b.dtb` (firmware partition on Raspberry Pi OS vs built by
OpenWrt), the **VideoCore firmware** (`start4.elf`, `fixup4.dat`), and the kernel
config. The VideoCore firmware is the interesting one: it configures the SoC clock
tree before the kernel starts, the symptom is a bit-level timing offset, and it is
guaranteed to differ between the two images.

---

## 2026-08-22: the A/B ran — the second chip select is the difference

Booted OpenMANET on the same board and captured its live device tree and pin mux
against the failing Raspberry Pi OS capture. Four differences, one of which had
never been looked at.

| | Raspberry Pi OS 6.6.51 (skew) | OpenMANET 6.6.138 (works) |
|---|---|---|
| `cs-gpios` | `<&gpio 8 1>, <&gpio 7 1>` — **two** | `<&gpio 8 1>` — **one** (property is exactly 12 bytes) |
| GPIO7 | `fe204000.spi … function gpio_out` | `(MUX UNCLAIMED) (GPIO UNCLAIMED)` |
| `reset-gpios` | `<&gpio 17 1>` | `<&gpio 17 0>` |
| `spi-max-frequency` | 10 MHz | 50 MHz |

Everything else matches: MISO/MOSI/SCLK `alt0`, GPIO8 `gpio_out`, and the spi0
node's `dmas`, `clocks`, `interrupts`, `reg` and `compatible` are identical. The
clock difference is already eliminated (RUN 4 swept 400 kHz…50 MHz).

**So what is left is the second chip select.** The failing side registers two and
has the controller holding GPIO7 as an output; the working side registers one and
never touches GPIO7. That variable was never examined — the earlier pin mux check
confirmed no pin was driven *twice*, which it isn't, and stopped there.

It is worth testing rather than just noting, because CS count is not inert in this
driver: one of the three rpi patches to `spi-bcm2835.c` that OpenWrt imports is
`950-0821`, "Support spi0-0cs and SPI_NO_CS mode".

This is the first hypothesis in the investigation that comes from a **measured
difference between a working and a failing configuration** rather than from
reasoning about what might matter.

**Next:** change `overlays/mm610x-spi-sensecap.dts` to declare a single chip
select — `cs-gpios = <&gpio 8 1>` on `&spi0`, leaving GPIO7 alone — rebuild,
reboot, and see whether `morse rx` still shows `c0 7f`. Try
`reset-gpios = <&gpio 17 0>` in the same pass or right after.

Detail, including what could not be captured on the OpenMANET side (no `python3`,
no `kmod-spi-dev`, so the userspace probe half of the A/B did not run), is in
`logs/2026-08-22-openmanet-1.8.0-ab-environment.txt`.

---

## 2026-08-22: the retest ran — eight eliminations, none of them the cause

Everything below was written before the hardware retest. The retest has now been
run, over SSH, and it kills the padding hypothesis too. Full detail in
`logs/2026-08-22-bookworm-6.6.51-retest-environment.txt`.

| Hypothesis | Test | Result |
|---|---|---|
| kernel-tree difference | source diff at the same stable tag | eliminated — byte-identical |
| ack window too narrow | `spi_post_write_status_bytes=512` | **eliminated** — `no non-0xff byte in the 519 bytes clocked after CRC` |
| skew caused by the init training burst | 7 runs sweeping `spi_init_train_bytes` 0/2/17/18/20 and `spi_init_cs_flip=N` | **eliminated** — `c0 3f` / `c0 7f` in all seven |
| GPIO8 double-driven | live pinmux | **eliminated** — 7/8 `gpio_out`, 9/10/11 `alt0` |
| clock-dependent | 400 kHz / 1 / 20 / 50 MHz | **eliminated** — identical at every rate |
| the driver is involved at all | spidev bound via `driver_override`, no driver loaded | **eliminated** — same `R1=0x01 @bit10` |
| host mis-samples the start of a transfer | 0…32 bytes of `0xff` before the command in one CS assertion | **eliminated** — `@bit10` every time |
| the pull on MISO/MOSI/SCLK | `pinctrl set 9\|10\|11 pu` at runtime, A/B against pull-down | **eliminated** — byte-identical in both directions |

The pull one is worth a paragraph, because the difference is real even though it
is not the cause. Decoding OpenMANET's own `mm610x-spi.dtbo` off a freshly
written card shows `spi0_pins { brcm,pins = 9 10 11; brcm,function = ALT0;
brcm,pull = 2 2 2 }` — **pull-up on all three SPI lines**. The overlay in this
repo never sets those pulls and inherits the BCM2711 default, which is
**pull-down**, confirmed on the running board. The reasoning was that an MMC-SPI
slave tri-states MISO before answering, so the pull sets the level during those
bit times. Flipping them at runtime changes nothing at all. Recorded so the same
difference does not get rediscovered and re-argued later. Full decode in
`logs/2026-08-22-openmanet-1.8.0-overlay-mm610x-spi.txt`.

That decode also confirms the image needs **no overlay swap**: reset on GPIO17
pull-up, IRQ on GPIO5, power-gpios 23/24, `cs-gpios` GPIO8 active-low,
`spi-max-frequency` 50 MHz — the WM1302 HAT map throughout.

Two facts worth carrying forward:

- **`spi_setup()` forces `SPI_CS_HIGH` back on** for a cs-gpios device, so
  `morse_spi_initsequence()`'s training burst goes out with the chip *selected*
  on every such host. A real driver defect — reported upstream — but not the
  cause here.
- **The default ack search window is 11 bytes**, not the 71 quoted below; 71 was
  the length of a hex dump.

`driver_override` is the way to get a spidev node here — dropping the overlay
from `config.txt` would take the GPIO18 slot power hog and the GPIO17 pull-up
with it. `tools/mmcspi.py`'s `reset_module()` was also fixed: it used libgpiod
v2 `gpioset` syntax and failed silently on Bookworm's v1.6.3, so no reset was
happening at all.

**What is left** is a genuine disagreement between chip and host about where byte
boundaries are, on a board where OpenMANET needs no compensation. The only
remaining experiment is the direct A/B: boot the OpenMANET card and run the same
spidev probe on it. That needs a physical card swap.

---

## 2026-08-22 (later): the kernel-tree conclusion is refuted — the split is in the driver package

Ran the tree diff the section below proposes. It comes up empty: **there is no
`spi-bcm2835` difference between the two kernel trees.**

Method: `raspberrypi/linux` at tag `stable_20241008` (= 6.6.51, the exact kernel
in the failing Bookworm image) against OpenWrt's tree, reconstructed as mainline
stable plus every patch in `target/linux/bcm27xx/patches-6.6/` that touches the
file in question.

| File | OpenWrt bcm27xx 6.6 vs raspberrypi/linux rpi-6.6.y @ 6.6.51 |
|---|---|
| `drivers/spi/spi-bcm2835.c` | byte-identical |
| `drivers/spi/spi.c` (SPI core) | byte-identical |
| `drivers/dma/bcm2835-dma.c` | byte-identical |
| `drivers/pinctrl/bcm/pinctrl-bcm2835.c` | byte-identical |
| `arch/arm/boot/dts/broadcom/bcm270x-rpi.dtsi` | byte-identical |

OpenWrt imports the rpi commits verbatim. The rpi tree's only changes to
`spi-bcm2835.c` are three commits — phys-addr slave DMA config, the
zero-length-transfer workaround, and `spi0-0cs`/`SPI_NO_CS` support — and OpenWrt
carries all three (950-0276 / 950-0467 / 950-0821), plus the SPI-core one
(950-0204, "Force CS_HIGH if GPIO descriptors are used"). Mainline's
`spi-bcm2835.c` is also unchanged between v6.6.51 and v6.6.138, and
`OpenMANET/firmware` at tag 1.8.0 carries the same three patches as upstream
openwrt-24.10.

So there is nothing to bisect, in either tree.

### Where the real difference is: an OpenWrt-only Morse driver patch

*(Superseded by the retest above: the patch is real and the divergence is worth
reporting, but widening the window to 519 bytes changes nothing on this board, so
it does not explain this failure.)*

`OpenMANET/firmware@1.8.0`'s `feeds.conf.default` pins `MorseMicro/morse-feed` at
`fc332b0`, and that feed applies
`essentials/morse_driver/patches/mm61x/003_fix_spi_inter_transaction_delay.patch`
to the driver before building it. The patch header describes this exact failure:

> Add more delay between SPI transactions when not in block mode. [...]
> Currently the driver has enough delay between blocks but not when the
> transaction isn't a block.

It raises the padding clocked after the CRC of a **non-block** CMD53 write from
`4` bytes to `max(250, count * inter_block_delay_bytes / MMC_SPI_BLOCKSIZE)`, and
applies the same floor to non-block reads.

The numbers line up exactly:

- `MM6108_SPI_INTER_BLOCK_DELAY_NANO_S` = 40000 ns, and
  `inter_block_delay_bytes = 40000 / (clk_period_ns * 8)` → **250 bytes at
  50 MHz**, 50 bytes at 10 MHz. Morse's `max(250, …)` is exactly one full
  inter-block delay at full clock, applied regardless of clock.
- Stock `mm6108-2.0.1` exposes that same line as a module parameter instead,
  `spi_post_write_status_bytes`, **default 4**.
- Every failure here is a non-block write: `cmd53_write fn=1 0x00004050:4`,
  count = 4.
- The widest window ever tested here was **64** bytes.

So the ack window was never opened wide enough. "Ruled out:
`spi_post_write_status_bytes` 4…64" below is not a valid elimination.

### Second driver-side difference: `enable_ext_xtal_init`

OpenMANET runs with `enable_ext_xtal_init='1'` in its UCI (see
`logs/2026-08-22-openmanet-1.8.0-environment.txt`). In `morse_spi_cmd53_write()`,
when that parameter is set *and* `cfg->xtal_init_bus_trans_delay_ms` is non-zero,
the driver appends a further `XTAL_TRANSFER_DELAY_BYTES` = **4096** bytes to the
transaction; `mm610x_enable_ext_xtal_delay()` sets that field only when the
parameter is on. The working machine therefore clocks an ack window two orders of
magnitude wider than anything tested here.

Note the ordering trap: `mm610x_ext_xtal_init()` performs its sequence with
`morse_reg32_write()` calls, i.e. it *needs* a working write path. Turning the
parameter on while writes are broken — tried, "no change" — cannot work on its
own. The padding has to be fixed first.

### The four-way comparison was not single-variable

Other differences between the passing OpenMANET run and the failing Raspberry Pi
OS runs, all from the archived logs:

- **Different BCF.** OpenMANET loaded `bcf_default.bin` (1298 bytes, crc32
  `0xf72450a7`); the builds here load `bcf_fgh100mhaamd.bin` (1251 bytes,
  `0x941b2a82`). The claim below that the BCF was identical is wrong — only
  `mm6108.bin` (`0xbe7b5c8f`) actually matches.
- **Different dot11ah build.** OpenMANET registers `Dot11ah driver registration.
  Version 0-rel_mm8108_2_0_0_2026_Apr_21` alongside the mm6108 2.0.1 main driver;
  both are mm6108 2.0.1 here.
- **Different overlay.** `spi-max-frequency` 50 MHz there against 10 MHz here —
  which by itself changes the computed `inter_block_delay_bytes` from 250 to 50 —
  plus `reset-gpios = <&gpio 17 0>` against `<&gpio 17 1>` here, and pinctrl
  attached to the controller rather than to the child device node.

### One thing that argues against the padding hypothesis

"The open problem" below records that the same transaction driven by hand from
userspace returns token `0x05` **two bytes after the CRC**. If that is what the
chip really does, a 4-byte window is already enough and padding is not the wall.
That observation and "all 0xff out to 71 bytes" from inside the driver cannot
both be describing the same chip state. Card state (idle vs initialised) is the
standing suspect and was never verified. So the padding hypothesis is a good fit
numerically but is not confirmed — it has to be measured, not assumed.

### Next experiments, in order

*(All of these have now been run — see the retest section at the top. Kept
because the reasoning behind each one is what the results have to be read
against.)*

`patches/` was extended on 2026-08-22 to make these measurable:
`spi_init_train_bytes` (default 18), `spi_init_cs_flip` (default Y),
`spi->mode` logging through `morse_spi_initsequence()`, and a rewritten
`morse_spi_find_data_ack()` failure path that reports the offset and value of
the first non-`0xff` byte (or says there was none in N bytes) and dumps from
that byte rather than from the head of the window.

**1. Does the ack window matter at all?** One insmod, everything else exactly as
the last failing run — 10 MHz, `spi_rx_lshift=2`, `bcf_fgh100mhaamd.bin`:

```
spi_post_write_status_bytes=512
```

Pass → padding was the wall. Still nothing in 512 bytes → the padding hypothesis
is dead, which also rules out Morse's own OpenWrt fix as the explanation and
sharpens the question to them.

**2. Is the 2-bit skew self-inflicted by the init burst?** The training clocks go
out with CS deliberately deasserted, via a `SPI_CS_HIGH` flip. If that flip goes
the wrong way on this kernel, the chip sees those clocks *selected* and starts
counting bits early — which would produce exactly a constant, clock-independent
bit offset. Sweep:

| `spi_init_cs_flip` | `spi_init_train_bytes` | reading |
|---|---|---|
| Y | 18 | baseline (stock behaviour) |
| Y | 0 / 2 / 17 / 20 | does the skew track the burst length? |
| N | 18 | does the skew depend on the flip rather than the clocks? |
| N | 0 | neither burst nor flip |

Watch the new `init: mode=0x…` lines to see which branch the kernel actually
takes, and `morse rx:` for whether the offset moves.

**3. Where else can a difference hide?** With the SPI source byte-identical
between the two trees, only the live configuration is left. Dump
`/proc/device-tree/soc/spi@7e204000/` (cs-gpios, pinctrl-0, dmas) and the GPIO
7…11 rows of `/sys/kernel/debug/pinctrl/*/pinmux-pins` on both Raspberry Pi OS
and OpenMANET and diff them. In particular, check whether GPIO8 is muxed ALT0
(native CE0) while also being used as a GPIO chip select.

**4. Only after 1 passes**, converge on OpenMANET's configuration one variable at
a time: overlay to `spi-max-frequency = <50000000>` (which makes the driver
compute the same 250-byte inter-block delay), then `enable_ext_xtal_init=1`,
then `bcf=bcf_default.bin`.

**Still unexplained: the 2-bit RX skew.** Padding is a byte-level effect and
cannot produce bit-level misframing, and OpenMANET needs no `spi_rx_lshift` at
all on the same hardware. Experiment 2 is the direct attack on it.

---

## 2026-08-22 follow-up: four end-to-end tests

Same board (SenseCAP M1 mPCIe slot with Wio-WM6108, WM1302 HAT pinout), nominally the same driver release (`mm6108-2.0.1` with the patches in `./patches`), same firmware (`mm6108.bin` crc32 `0xbe7b5c8f`). ~~Same BCF (`bcf_fgh100mhaamd.bin` crc32 `0x941b2a82`).~~ **Corrected 2026-08-22: the OpenMANET run loaded `bcf_default.bin` (crc32 `0xf72450a7`), and its driver is an OpenWrt-feed build carrying extra SPI patches — see the section above.** What changes across the four rows is the OS image, not the kernel alone:

| Kernel | Tree / packaging | Result |
|---|---|---|
| **6.6.138** | OpenWrt linux-6.6 (OpenMANET 1.8.0) | ✅ `wlh0` up as AP on SG @ 22 dBm |
| 6.6.51+rpt-rpi-v8 | raspberrypi/linux rpi-6.6.y (RPi OS Bookworm 2024-11-19) | ❌ CMD63 fail → `spi_rx_lshift=2` → CMD53 write fail at `0x00004050:4`, `ret:-71` |
| 6.12.93+rpt-rpi-v8 | raspberrypi/linux rpi-6.12.y (RPi OS Bookworm 2025-05) | ❌ byte-identical fingerprint to above |
| 6.18.34+rpt-rpi-v8 | raspberrypi/linux rpi-6.18.y (RPi OS Trixie) | ❌ byte-identical fingerprint |

**Key conclusion — SUPERSEDED, see the section above.** ~~the fault is a `spi-bcm2835` (or SPI-core) **tree difference**, not a version regression. Both trees share mainline stable-tag numbering, but `raspberrypi/linux`'s patch stack breaks MM6108 driven via GPIO CS, and OpenWrt's does not.~~ The comparison this paragraph asks for was done and the files are byte-identical; the split is in the driver package, not the kernel. The table above still stands as measurement — only its interpretation was wrong.

**Practical bottom line:** OpenMANET 1.8.0 remains the only tested working path. But the reasoning that followed from this — swap the kernel — no longer holds: options (b) and (c) below were expected to work *because* they avoid `raspberrypi/linux`, and that premise is now refuted. Replacing the kernel is unlikely to help on its own; fixing the driver's non-block write padding is the thing to try first.
- (a) OpenMANET as a dedicated gateway,
- ~~(b) Ubuntu Server or a mainline-kernel Debian image on the Pi (both untested but expected to work since they do not use `raspberrypi/linux`),~~
- ~~(c) build a mainline kernel and install on Bookworm.~~

The retraction: earlier "next things to try" below (§) suggested that some 6.6.x kernel on Raspberry Pi OS should work because it's the same LTS branch as OpenMANET. Wrong. Any `+rpt-rpi-v8` kernel tested carries the bug.

**Public status:** five comments now on `MorseMicro/morse_driver` issue #9 (v1 initial, v2 OpenMANET pass, v3 Bookworm 6.12.93 fail, v4 Bookworm 6.6.51 fail + tree-split reframing, v5 retraction of that reframing + six eliminations from the instrumented retest). No maintainer response as of this update.

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
- ~~Wider ack search window (`spi_post_write_status_bytes` 4/8/16/32/64) - the
  window is all 0xff out to 71 bytes; the chip sends nothing at all.~~
  **Withdrawn 2026-08-22:** Morse's own OpenWrt patch puts the floor for this
  window at 250 bytes. 64 was never enough to be a valid test.
- ~~`enable_ext_xtal_init=1` - no change.~~ **Withdrawn 2026-08-22:** the xtal
  init sequence is itself made of register writes, so it cannot run while the
  write path is broken. Retest after the padding fix.
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
