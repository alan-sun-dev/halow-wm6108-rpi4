Three fixes for driving an MM6108 over SPI from a host that uses GPIO chip selects. They are independent defects but they compound, so all three are needed to get from "does not build" to "radio comes up".

Found while bringing up a Wio-WM6108 (FGH100M-H) on a Raspberry Pi 4 over `spi-bcm2835`. Background and the full measurement trail are in #9 and #15.

### 1/3 — the driver does not build

`SPI_CONTROLLER_ENABLE_CS_GPIOD` is a vendor-kernel flag. The `#else` branch raises a `#warning`, `ccflags-y` carries `-Werror`, and the build stops:

```
spi.c:1562:2: error: #warning "SPI_CONTROLLER_ENABLE_CS_GPIOD macro not defined" [-Werror=cpp]
```

This is not only mainline — `raspberrypi/linux` 6.6.51+rpt-rpi-v8 does not define it either, so the released driver cannot be built against a current Raspberry Pi OS without editing the source. Nothing needs to happen in that branch; a kernel without the flag already forces `SPI_CS_HIGH` for a `cs-gpios` device, which is what the flag existed to obtain.

### 2/3 — the chip is never put into SPI mode

The MM6108 needs ~74 clocks with chip select **deasserted**. `morse_spi_initsequence()` arranges that by flipping `SPI_CS_HIGH`, which does not work on a `cs-gpios` controller: `spi_setup()` forces the bit back on, so the burst goes out with the chip *selected*.

```
init: mode=0x4 cs_high_default=1
init: CS deasserted for training, mode=0x4     <-- expected 0x0
init: CS polarity restored, mode=0x4
```

The chip then answers two bit times off the byte grid — `c0 7f` where `01 ff` is expected — and probe fails at CMD63 with `-EPROTO`. It looks like a signal-integrity fault and is not one. `SPI_NO_CS` achieves what the flip cannot; the old path is kept as a fallback.

Ordering matters and is easy to miss: the burst must happen after reset and before any other transaction. Once the chip has been addressed with CS asserted it does not recover.

### 3/3 — the inter-transaction delays are counted in clocks, not time

`inter_block_delay_bytes` is derived from 40000 ns and converted using the SPI clock: 250 bytes at 50 MHz, 50 bytes at 10 MHz. Both are 40 µs, so a time-based requirement would behave identically.

It does not. At 10 MHz, 50 bytes fails and 250 works, at the same 40 µs — the chip counts SPI clocks. The existing model only lands on a working value at full clock, which is why configurations at 50 MHz work and this one, at 10 MHz, did not.

Three sites need the floor and each is separately necessary; fixing one moves the failure to the next:

- block-write delay — a 14-block write to fn=2 gets `0xeb` (`SPI_RESPONSE_CRC_ERR`) at offset +261, part-way through the block, because the chip is still busy with a preceding 344-byte non-block write
- non-block write padding — 4 bytes by default; fails on an 80-byte byte-mode write
- non-block read delay — a 92-byte read scales to 44 bytes; the extended host table read then fails and probe returns -5

The same floor is already in the OpenWrt feed (`003_fix_spi_inter_transaction_delay.patch`) but not in the released driver. A cleaner fix would drop the clock scaling entirely, since the requirement is a byte count rather than an interval; this keeps the existing shape to stay close to what is already shipping.

### Verified

Raspberry Pi 4 Model B Rev 1.4, SenseCAP M1 carrier, Wio-WM6108 (MM6108A1), Raspberry Pi OS Lite bookworm, kernel `6.6.51+rpt-rpi-v8`, SPI at 10 MHz. Built clean, no warnings, loaded with no module parameters beyond `country=` and `bcf=`:

```
cmd53 write failures: 0
cmd53 read failures:  0
probe failures:       0
phy33 -> platform/soc/fe204000.spi/spi_master/spi0/spi0.0
wlan1 -> phy33
```

Corroborated by the SPI core's own statistics under `/sys/bus/spi/devices/spi0.0/statistics/`, which do not depend on any instrumentation of mine:

```
errors 0    timedout 0
idle, 3 s          +17 messages, 4.6 KB   (30 s watchdog)
ip link set up     +165 messages, 40 KB
iw dev wlan1 scan  +31, +31, +36 messages, ~8 KB each
```

The interface opens, scans reach the chip and return no results because there is no HaLow network in range here. Association and data transfer are untested for want of a second HaLow device — nothing about the driver.

No bit-shift compensation of any kind, and none of `spi_inter_block_delay_bytes` or `spi_post_write_status_bytes` is needed — 3/3 makes them unnecessary.

Tested against tag `mm6108-2.0.1`; the series applies cleanly to `main`, whose only differences from that tag are outside the areas touched here.

### Not included

No `Signed-off-by` — happy to add one if the project wants a DCO line. Per-run logs, the userspace probes used to isolate each defect, and the working notes are at https://github.com/alan-sun-dev/halow-wm6108-rpi4.
