#!/usr/bin/env python3
import spidev, subprocess, time
from mmcspi import bits, cmd, crc7_be, find_zero_runs, reset_module, sh

def realign(data, off):
    s = bits(data)[off:]
    return [int(s[i:i+8], 2) for i in range(0, len(s) - 7, 8)]

for mode in (0, 1):
    reset_module()
    s = spidev.SpiDev(); s.open(0, 0); s.mode = mode; s.max_speed_hz = 1000000
    s.xfer2([0xFF] * 18)
    r0  = cmd(s, 0)
    r63 = cmd(s, 63)
    s.close()
    for name, r in (("CMD0", r0), ("CMD63", r63)):
        tail = r[7:]
        runs = [x for x in find_zero_runs(tail) if x[1] >= 7]
        print(f"mode{mode} {name}: raw {' '.join(f'{b:02x}' for b in tail[:10])}  runs={runs}")
        for start, length in runs:
            off = start % 8
            print(f"    以 bit{start} 為位元組邊界 (左移 {off}) -> "
                  f"{' '.join(f'{b:02x}' for b in realign(tail, off)[:8])}")
