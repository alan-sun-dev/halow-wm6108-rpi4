#!/usr/bin/env python3
import spidev, subprocess, time
from mmcspi import bits, cmd, crc7_be, find_zero_runs, reset_module, sh

def crc16x(data):
    crc = 0
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if (crc & 0x8000) else (crc << 1) & 0xFFFF
    return crc

def lshift(data, n):
    if not n: return list(data)
    s = bits(data)[n:] + '1'*n
    return [int(s[i:i+8],2) for i in range(0,len(s),8)]

reset_module()
s = spidev.SpiDev(); s.open(0,0); s.mode=0; s.max_speed_hz=1000000
s.xfer2([0xFF]*18)
cmd(s, 0)      # enter SPI mode

payload = [0xde, 0xad, 0xbe, 0xef]
addr, fn, cnt = 0x4050, 1, len(payload)
arg = (1<<31) | (fn<<28) | (0<<27) | (1<<26) | (addr<<9) | cnt

buf  = [0xFF]
buf += [0x40|53]
buf += [(arg>>24)&0xFF, (arg>>16)&0xFF, (arg>>8)&0xFF, arg&0xFF]
buf += [crc7_be(0, buf[1:6]) | 0x01]
buf += [0xFF]*8                       # R1 window + MISO-ready
tok_at = len(buf)
buf += [0xFE] + payload               # data token + data
c = crc16x(payload)
buf += [(c>>8)&0xFF, c&0xFF]
ack_at = len(buf)
buf += [0xFF]*40                      # generous ACK window

rx = s.xfer2(list(buf))
s.close()

for name, d in (("原始", rx), ("左移2bit", lshift(rx, 2))):
    print(f"{name}:")
    print("   命令段     :", ' '.join(f'{b:02x}' for b in d[:7]))
    print(f"   R1 視窗    :", ' '.join(f'{b:02x}' for b in d[7:tok_at]))
    print(f"   資料段回傳 :", ' '.join(f'{b:02x}' for b in d[tok_at:ack_at]))
    print(f"   ACK 視窗   :", ' '.join(f'{b:02x}' for b in d[ack_at:ack_at+24]))
    nz = [(i, b) for i, b in enumerate(d[ack_at:ack_at+40]) if b != 0xFF]
    print(f"   ACK 視窗非 0xFF 的位元組: {nz if nz else '(全部都是 0xff)'}")
