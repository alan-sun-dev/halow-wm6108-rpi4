#!/usr/bin/env python3
"""
Shared MMC-over-SPI helpers for poking an MM6108 directly through /dev/spidev0.0.

Run this file to sweep SPI modes and clock rates and print what the chip
returns for CMD0 and CMD63. Import it from the other scripts for the helpers.

Requires the morse driver to be unloaded and spidev bound to the chip select:

    sudo rmmod morse
    echo spidev | sudo tee /sys/bus/spi/devices/spi0.0/driver_override
    echo spi0.0 | sudo tee /sys/bus/spi/drivers/spidev/bind

`driver_override` binds spidev to the existing spi0.0 device, so the overlay
stays loaded and the slot power hog on GPIO18 and the pull-up on GPIO17 are
preserved. Do not drop the overlay from config.txt to get a spidev node — that
takes the module's power and reset with it.

Run these as root: reset_module() drives GPIO17.
"""
import spidev, subprocess, time, sys

CRC7_TAB = []
for i in range(256):
    c = i
    for _ in range(8):
        c = ((c << 1) ^ 0x12) if (c & 0x80) else (c << 1)
        c &= 0xFF
    CRC7_TAB.append(c)

def crc7_be(crc, data):
    for b in data:
        crc = CRC7_TAB[(crc ^ b) & 0xFF]
    return crc

RESET_GPIO = 17

def sh(c, check=False):
    """Run a shell command. Returns the CompletedProcess; check=True raises."""
    p = subprocess.run(c, shell=True, capture_output=True, text=True)
    if check and p.returncode != 0:
        raise RuntimeError(f"{c!r} failed ({p.returncode}): "
                           f"{(p.stderr or p.stdout).strip()}")
    return p

def reset_module():
    """
    RESET_N low ~20 ms, then release it by floating the pin with a pull-up —
    the same thing morse_hw_reset() does.

    This uses `pinctrl` (raspi-utils, in the Raspberry Pi OS base image) rather
    than libgpiod, on purpose. gpioset's command line changed incompatibly
    between libgpiod v1 and v2, and an earlier version of this function used the
    v2 form, which fails on Bookworm's v1.6.3 — silently, because sh() captured
    and discarded stderr. The reset never happened and every measurement taken
    afterwards was against a chip in an unknown state.

    So: one tool that can both drive the pin and hand it back as an input with a
    pull-up, and a hard failure if it is not there.
    """
    sh(f"pinctrl set {RESET_GPIO} op dl", check=True)
    time.sleep(0.02)
    sh(f"pinctrl set {RESET_GPIO} ip pu", check=True)
    time.sleep(0.15)

    level = sh(f"pinctrl get {RESET_GPIO}").stdout
    if "hi" not in level:
        raise RuntimeError(
            f"GPIO{RESET_GPIO} reads back as {level.strip()!r} after release — "
            "expected 'hi'. RESET_N is still asserted, so the chip is held in "
            "reset. Check that the overlay configuring this pin pull-up is "
            "loaded, and that the slot has power.")

def bits(data):
    return ''.join(f'{b:08b}' for b in data)

def find_zero_runs(data):
    s = bits(data)
    runs, i = [], 0
    while i < len(s):
        if s[i] == '0':
            j = i
            while j < len(s) and s[j] == '0': j += 1
            runs.append((i, j - i)); i = j
        else: i += 1
    return runs

def cmd(spi, opcode, arg=0, extra=16):
    buf = [0xFF] * (7 + extra)
    buf[1] = 0x40 | opcode
    buf[2] = (arg >> 24) & 0xFF; buf[3] = (arg >> 16) & 0xFF
    buf[4] = (arg >> 8) & 0xFF;  buf[5] = arg & 0xFF
    buf[6] = crc7_be(0, buf[1:6]) | 0x01
    return spi.xfer2(buf)



if __name__ == "__main__":
    for mode in (0, 1, 2, 3):
        for speed in (400000, 1000000):
            reset_module()
            s = spidev.SpiDev(); s.open(0, 0)
            s.mode = mode; s.max_speed_hz = speed; s.bits_per_word = 8
            s.xfer2([0xFF] * 18)                 # training clocks
            r0 = cmd(s, 0)                       # CMD0  GO_IDLE / enter SPI mode
            r63 = cmd(s, 63)                     # CMD63 morse init
            s.close()
            tail0, tail63 = r0[7:], r63[7:]
            print(f"mode{mode} {speed//1000:>4}kHz")
            print(f"   CMD0 : {' '.join(f'{b:02x}' for b in tail0)}")
            print(f"          zero-runs {find_zero_runs(tail0)}")
            print(f"   CMD63: {' '.join(f'{b:02x}' for b in tail63)}")
            print(f"          zero-runs {find_zero_runs(tail63)}")
