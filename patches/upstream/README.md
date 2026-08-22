# Upstream-ready patch series for MorseMicro/morse_driver

Three patches against tag `mm6108-2.0.1` (commit `98e1936`). Apply in order:

```sh
for f in patches/upstream/000*.patch; do patch -p1 < "$f"; done
```

| | what it fixes |
|---|---|
| `0001` | the driver does not build at all where `SPI_CONTROLLER_ENABLE_CS_GPIOD` is undefined — a `#warning` under `-Werror`. That includes raspberrypi/linux 6.6.51, not only mainline |
| `0002` | the chip is never put into SPI mode on a `cs-gpios` controller: `spi_setup()` undoes the `SPI_CS_HIGH` flip, so the 74-clock training burst goes out with the chip selected |
| `0003` | the inter-transaction delays are derived from a time and converted using the SPI clock, which only produces a working value at 50 MHz. The chip counts clocks, not microseconds |

## Verified

Raspberry Pi 4 Model B Rev 1.4 (BCM2711, `spi-bcm2835`, `cs-gpios`), SenseCAP M1
carrier, Wio-WM6108 (MM6108A1), Raspberry Pi OS Lite bookworm, kernel
`6.6.51+rpt-rpi-v8`, SPI at 10 MHz.

Built clean, no warnings, and loaded with **no module parameters** beyond
`country=` and `bcf=`:

```
cmd53 write failures: 0
cmd53 read failures:  0
probe failures:       0
phy33 -> platform/soc/fe204000.spi/spi_master/spi0/spi0.0
wlan1 -> phy33
```

None of `spi_rx_lshift`, `spi_inter_block_delay_bytes` or
`spi_post_write_status_bytes` is needed. `0003` makes the last two unnecessary by
flooring the values in the driver.

## How this differs from `../morse-driver-2.0.1-rpi-spi.patch`

That patch is the working file for this investigation and carries a lot that does
not belong upstream: hex dumps, `dev_info` tracing through the init sequence,
transaction accounting, and module parameters that exist to make hypotheses
testable (`spi_rx_lshift`, `spi_tx_rshift`, `spi_init_train_bytes`,
`spi_init_cs_flip`, `spi_ack_scan`, `spi_min_delay_bytes`). The series here is
the three fixes and nothing else.

## Note on 0003

The narrower fix would be to floor the values, which is what this does and what
Morse's own OpenWrt feed already carries in
`003_fix_spi_inter_transaction_delay.patch` — it is simply not in the released
driver. The better fix is to stop scaling by clock at all, because the
measurement says the requirement is a byte count rather than an interval. This
series keeps the existing shape to stay close to what is already shipping; see
[issue #9](https://github.com/MorseMicro/morse_driver/issues/9) for the argument.

## Signed-off-by

Not included. That is a certification the author makes personally — add it before
sending if the project wants a DCO line.
