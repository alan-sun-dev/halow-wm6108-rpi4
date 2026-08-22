#!/usr/bin/env python3
"""
Show where the MM6108's SPI mode comes from and what takes it away.

The chip comes out of a cold power-up already in SPI mode; a RESET_N pulse takes
it back out; and a training burst only puts it back if nothing has addressed the
chip with CS asserted in between. That last rule is what makes the driver's
broken init burst fatal on some boards and invisible on others -- see
logs/2026-08-23-nocs-init-fix-environment.txt.

Prerequisites, same as mmcspi.py: morse unloaded and spidev bound to spi0.0 via
driver_override. This script drives the chip select itself, so it also needs
SPI_NO_CS -- that is what stops the controller asserting CS behind its back.

    sudo rmmod morse
    echo spidev | sudo tee /sys/bus/spi/devices/spi0.0/driver_override
    echo spi0.0 | sudo tee /sys/bus/spi/drivers/spidev/bind

TWO THINGS THAT WILL MISLEAD YOU IF YOU CHANGE THEM:

1. The wait after re-applying power. The module needs well over 1.5 s before it
   answers anything. An earlier version of this test used 1.5 s and showed
   everything offset, including sequences already known to work -- an artefact
   that looked exactly like a finding. 5 s is reliable.

2. Probe order. probe() addresses the chip with CS asserted, so a probe placed
   before a training burst destroys what the training was meant to demonstrate.
   Every sequence below is written with that in mind.

GPIO18 is the SenseCAP M1's slot power enable and is carrier-specific. On a board
without switchable module power, drop powercycle() and keep the reset tests.
"""
    sh("pinctrl set 18 op dh"); time.sleep(w)
def resetpulse():
    sh("pinctrl set 17 op dl"); time.sleep(0.05)
    sh("pinctrl set 17 ip pu"); time.sleep(0.3)
def r1_of(t):
    s=bits(t); i=s.find('0')
    return (int(s[i:i+8],2), i) if (i>=0 and i+8<=len(s)) else (None,None)
def cmd0(spi, extra=16):
    c=[0x40,0,0,0,0]
    return spi.xfer2([0xFF]+c+[crc7_be(0,c)|0x01]+[0xFF]*extra)[7:]
def probe(spi, tag):
    cs('low'); t=cmd0(spi); cs('high')
    r1,off=r1_of(t)
    v = "對齊 ✓ 在 SPI 模式" if off==8 else ("偏移 @bit%s 不在 SPI 模式"%off if off is not None else "無回應")
    print("  %-34s %s   %s" % (tag, ' '.join('%02x'%b for b in t[:4]), v))
def train(spi):
    cs('high'); spi.xfer2([0xFF]*10); time.sleep(0.002)

s=spidev.SpiDev(); s.open(0,0); s.mode=0; s.max_speed_hz=400000; s.no_cs=True

for run in (1,2):
    print("=== 第 %d 輪 ===" % run)
    powercycle();          probe(s, "1. 冷上電後")
    resetpulse();          probe(s, "2. 打了 RESET 脈衝之後")
    train(s);              probe(s, "3. 補上訓練之後")
    print()
