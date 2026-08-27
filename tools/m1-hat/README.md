# Probing the SenseCAP M1 HAT: button, fan, LED, crypto chip

The M1 is a Raspberry Pi 4 Model B plus a Seeed HAT. The HAT carries a
mini-PCIe socket (originally a WM1302 LoRa concentrator, here a WM6108 HaLow
module), a fan, a button, an LED, a DC/DC, and a crypto authentication chip.
Everything on the HAT reaches the Pi through the 40-pin header, and the header
carries only SPI, I²C, GPIO and power — so all four devices are, in principle,
ordinary Linux GPIO/I²C devices.

The question this tool answers is not *can they be driven* but **which pins are
they on**, without guessing and without touching anything that latches.

## Run it

On the M1 itself — it needs local device-tree, GPIO and I²C access:

```sh
sudo ./m1-hat-probe.sh survey      # read-only inventory
./m1-hat-probe.sh button 20 --yes  # watch idle lines while you press
./m1-hat-probe.sh selftest         # prove the script's own guards fire
```

`survey` needs root for `/sys/kernel/debug/gpio`, which is the single most
useful section: it names every claimed line and its owner. Without root that
section says so rather than printing nothing.

Exit `0` every section produced its subject, `2` something was missing. A
section that cannot run prints a `!!!!` line and never goes quietly blank.

## The one-shot answer usually comes from `config.txt`

The pre-flashed image has a device-tree overlay for the HaLow module, and that
overlay names its own reset and IRQ GPIOs. Those, plus whatever
`/sys/kernel/debug/gpio` shows as claimed, leave a small set of free lines —
and the button, fan and LED are in it. Reading the overlay beats probing.

Seeed's own `reset_lgw.sh` for the WM1302 Pi HAT used GPIO 17 / 18 / 5. If the
HaLow overlay reuses one of those, that is a conflict to settle before
anything else.

## Once the pins are known

| device | how to drive it |
|---|---|
| button | `dtoverlay=gpio-shutdown,gpio_pin=N` for a real power key, or `dtoverlay=gpio-key,gpio=N,keycode=K` to hand a long-press to userspace |
| fan | `dtoverlay=gpio-fan,gpiopin=N,temp=55000` — registers a thermal cooling device, no daemon needed |
| LED | `dtoverlay=gpio-led` or plain libgpiod |

The button is worth wiring as a `gpio-key` rather than a shutdown key: a
long-press that restores a known-good HaLow configuration is the unattended
recovery path for a node whose radio does not come up, which is the largest
open risk in this project.

## Two traps

**The crypto chip is almost certainly locked.** It is a Microchip ATECC608A
(Helium hotspots use it to hold the swarm key). Its config and data zones lock
**one way, permanently**, and Seeed locked them at the factory to provision the
miner identity. You can read the public key and sign with the key that is
already in there; you almost certainly cannot put your own key in. Establish
the lock state before investing in it. This script only ever reads —
`survey` issues no write to that chip, and you should not either until you
know what is already inside it.

**A blank `i2cdetect` is not evidence.** An ATECC608A that has not been woken
NACKs its own address. Waking it needs a deliberate SDA-low pulse that
`i2cdetect` does not send. So nothing at `0x60` means *inconclusive*, never
*absent*. The script says as much in the output rather than letting a blank
grid read as a negative result — which is the same failure that made a soak
checkpoint exit 0 with 25 of its 30 fields empty on 2026-08-26.

For the driver itself, the kernel's `atmel-ecc` only exposes ECDH and is not
built on Raspberry Pi OS. The real path is Microchip's CryptoAuthLib in
userspace over `/dev/i2c-1`, whose PKCS#11 module lets OpenSSL and `ssh` use
the chip's keys directly — the interesting use here being an mTLS identity for
the console server that never has a private key on the SD card.
