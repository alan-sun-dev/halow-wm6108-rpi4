# morse_spi_initsequence(): the CS-deassert for the 74-clock training burst is silently undone on any cs-gpios controller

Posted 2026-08-23 as <https://github.com/MorseMicro/morse_driver/issues/15>.
Split out of issue #9 because it is a distinct defect with a wider blast radius.
This file tracks what is actually on that issue — keep it that way.

---

Splitting this out of #9 because it is a distinct defect with a wider blast radius than that thread's subject, and it is easy to miss buried in a comment there.

## Summary

`morse_spi_initsequence()` needs to clock ~74 cycles with chip select **deasserted**, to put the MM6108 into SPI mode. It arranges that by flipping `SPI_CS_HIGH` around the burst:

```c
spi->mode |= SPI_CS_HIGH;
if (spi_setup(spi) != 0) { ... } else {
        memset(mspi->data, 0xFF, MM610X_BUF_SIZE);
        morse_spi_xfer(mspi, 18);
        spi->mode &= ~SPI_CS_HIGH;
        spi_setup(spi);
}
```

**On a `cs-gpios` controller this does not work.** `spi_setup()` forces `SPI_CS_HIGH` back on, so the flip is a no-op and the burst is clocked out with the chip *selected* — the opposite of what the sequence is for.

## Evidence

Logging `spi->mode` through the function on a Raspberry Pi 4 (`spi-bcm2835`, `cs-gpios`, kernel 6.6.51):

```
init: mode=0x4 cs_high_default=1 train=18 flip=1
init: CS deasserted for training, mode=0x4     <-- expected 0x0
init: CS polarity restored, mode=0x4
```

`0x4` is `SPI_CS_HIGH`. It is still set immediately after `spi->mode &= ~SPI_CS_HIGH; spi_setup(spi);`.

Note the driver already tries to accommodate two different core behaviours here — the `SPI_CONTROLLER_ENABLE_CS_GPIOD` path — but the flip is undone either way once the core owns the CS polarity for a GPIO chip select.

## Who this affects

Measured on `6.6.51+rpt-rpi-v8`. By inspection the same applies to any host where the SPI core forces `SPI_CS_HIGH` for a `cs-gpios` device, so that gpiolib applies the active-low inversion exactly once — mainline, and `raspberrypi/linux` kernels carrying `950-0204` ("spi: Force CS_HIGH if GPIO descriptors are used") — but I have only verified the one kernel. It is not carrier-specific or board-specific.

## Consequence

The chip never enters SPI mode. Every response afterwards sits two bit times off the byte grid — `c0 7f` where `01 ff` is expected — and probe dies at CMD63 with `-EPROTO`. It looks exactly like a signal-integrity or hardware problem and is neither. I spent a long time eliminating clock rates, pin pulls, device-tree differences, kernel trees and power sequencing before finding it; full history is in #9.

## Why it is often invisible

The chip comes out of a **cold power-up already in SPI mode**, and **RESET_N takes it back out**. Measured with the module's supply under my control:

| | response |
|---|---|
| cold power-up, no training at all | `ff 01 ff` — aligned, already in SPI mode (3/3) |
| same power-on, after a RESET_N pulse | `ff c0 7f` — offset, knocked out |

So a device tree with `reset-gpios` flag 0 — where `gpiod_set_value(reset, 1)` drives the pin *high* and RESET_N never actually fires — never leaves SPI mode, and the broken burst is harmless. With flag 1, the correct polarity for an active-low reset, the reset fires and the chip cannot get back.

This is also, I think, the mechanism behind the advice in the community forum that a physical power cycle resolves things where a soft reboot does not: a power cycle puts the chip back into SPI mode, a soft reboot leaves the module powered and wherever the last reset left it.

## Suggested fix

`SPI_NO_CS` achieves what the flip cannot — the controller leaves the CS line alone, so the GPIO stays at its inactive level for the whole burst:

```c
const u32 saved_mode = spi->mode;

spi->mode |= SPI_NO_CS;
if (spi_setup(spi) == 0 && (spi->mode & SPI_NO_CS)) {
        memset(mspi->data, 0xFF, MM610X_BUF_SIZE);
        morse_spi_xfer(mspi, train);      /* CS stays deasserted */
        spi->mode = saved_mode;
        spi_setup(spi);
        return;
}
/* fall back to the existing flip if the controller rejects SPI_NO_CS */
spi->mode = saved_mode;
spi_setup(spi);
```

**Ordering matters:** the burst has to happen after reset and before any other transaction. Once the chip has been addressed with CS asserted it does not recover, and a later burst does not fix it. An early attempt of mine did the training after a first CMD0, saw no change, and read as a negative result.

## Verification

Userspace first, `SPI_NO_CS` set and CS driven by hand so the controller could not interfere, full reset before each trial:

| sequence | response |
|---|---|
| CS held HIGH throughout, CMD0 | `ff ff ff ff` — silent, confirming the manual CS control is real |
| CS LOW, CMD0, no training | `ff c0 7f ff` — R1 at bit 10 |
| 80 clocks @ CS HIGH, then CMD0 | `ff 01 ff ff` — R1 at bit 8 |

6/6 reproducible. After a correct init, `CMD0` → `0x01`, corrupted CRC → `0x09`, `CMD13` → `0x05`, `CMD63` → `0x01`, all byte-aligned.

Then in the driver, one boolean, same binary, same board:

| | result |
|---|---|
| fix on | `training with SPI_NO_CS, mode=0x44`; no offset, CMD63 passes, firmware and BCF load |
| fix off | `CS deasserted for training, mode=0x4`; the offset returns |

With the fix the read path works with no compensation at all — 468 KB of firmware and the BCF transfer correctly.

## How to check on your own board

Add one `dev_info` printing `spi->mode` after the flip in `morse_spi_initsequence()`. If it still reads `SPI_CS_HIGH`, the burst is going out with the chip selected. The visible symptom is a response of `c0 7f` where `01 ff` is expected, and `failed to init SPI with CMD63 (ret:-71)`.

---

Patch, per-run logs and the full derivation: https://github.com/alan-sun-dev/halow-wm6108-rpi4 — the fix is in `patches/` behind a `spi_init_no_cs` module parameter, and `logs/2026-08-23-nocs-init-fix-environment.txt` has the reasoning.

Happy to send this as a PR if that is easier.

---

## Follow-up comment, 2026-08-23

Confirmed working, and worth recording what it took beyond this fix.

With `SPI_NO_CS` for the training burst, the chip enters SPI mode reliably and the read path works with no bit-shift compensation at all. That part is settled — a single boolean in one driver binary flips the 2-bit offset on and off.

It was not sufficient on its own. There is a second, unrelated defect: `morse_spi_set_inter_block_delay()` derives the inter-transaction delay from a time rather than a clock count, so it produces 250 bytes at 50 MHz but only 50 at 10 MHz — and the chip counts clocks. Details and measurements are in MorseMicro/morse_driver#9.

With both fixed: `wlan1` up on stock Raspberry Pi OS, 351 SPI transactions, zero read or write failures.

The two are independent and both are needed, so anyone testing this fix at a clock below 50 MHz will still see failures — just further along, and in the write path rather than at CMD63.
