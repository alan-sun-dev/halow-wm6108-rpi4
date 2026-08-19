#!/usr/bin/env python3
import spidev, subprocess, time
from mmcspi import bits, cmd, crc7_be, find_zero_runs, reset_module, sh

def r1_of(tail):
    """Find an R1 byte at any bit offset: a 0 start bit after a run of 1s."""
    s = bits(tail)
    i = s.find('0')
    if i < 0 or i + 8 > len(s):
        return None, None
    return int(s[i:i+8], 2), i

reset_module()
s = spidev.SpiDev(); s.open(0, 0); s.mode = 0; s.max_speed_hz = 1000000
s.xfer2([0xFF] * 18)

print("CMD0 (GO_IDLE / 進 SPI 模式):")
for i in range(3):
    r1, off = r1_of(cmd(s, 0)[7:])
    print(f"   #{i}  R1=0x{r1:02x} @bit{off}" if r1 is not None else f"   #{i}  無回應")

print("CMD63 (Morse init) 連送 20 次，看 idle bit 會不會清掉:")
seen = {}
for i in range(20):
    r1, off = r1_of(cmd(s, 63)[7:])
    key = (r1, off)
    seen[key] = seen.get(key, 0) + 1
    if i < 6 or r1 == 0:
        print(f"   #{i:>2} R1=0x{r1:02x} @bit{off}" if r1 is not None else f"   #{i:>2} 無回應")
print("   統計:", {f"R1=0x{k[0]:02x}@bit{k[1]}": v for k, v in seen.items()})
s.close()
