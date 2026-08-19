#!/usr/bin/env python3
import spidev, subprocess, time
from mmcspi import bits, cmd, crc7_be, find_zero_runs, reset_module, sh

def r1_of(tail):
    s = bits(tail); i = s.find('0')
    if i < 0 or i + 8 > len(s): return None, None
    return int(s[i:i+8], 2), i

def raw_cmd(spi, opcode, arg=0, bad_crc=False, extra=16):
    buf = [0xFF]*(7+extra)
    buf[1] = 0x40 | opcode
    buf[2]=(arg>>24)&0xFF; buf[3]=(arg>>16)&0xFF; buf[4]=(arg>>8)&0xFF; buf[5]=arg&0xFF
    buf[6] = (crc7_be(0, buf[1:6]) | 0x01) ^ (0x7E if bad_crc else 0)
    return spi.xfer2(buf)[7:]

reset_module()
s = spidev.SpiDev(); s.open(0,0); s.mode=0; s.max_speed_hz=1000000
s.xfer2([0xFF]*18)
raw_cmd(s, 0)   # enter SPI mode

print("指令 / 參數變化對回應的影響：")
for label, kw in [
    ("CMD0  正確CRC",   dict(opcode=0)),
    ("CMD0  錯誤CRC",   dict(opcode=0, bad_crc=True)),
    ("CMD8  (illegal?)",dict(opcode=8, arg=0x1AA)),
    ("CMD13 狀態查詢",  dict(opcode=13)),
    ("CMD55",           dict(opcode=55)),
    ("CMD63 arg=0",     dict(opcode=63)),
    ("CMD63 arg=FFFF",  dict(opcode=63, arg=0xFFFFFFFF)),
]:
    tail = raw_cmd(s, **kw)
    r1, off = r1_of(tail)
    hexs = ' '.join(f'{b:02x}' for b in tail[:6])
    print(f"  {label:<18} R1=0x{r1:02x} @bit{off:<3} raw={hexs}" if r1 is not None else f"  {label:<18} 無回應")

# 完全不送命令，只給時脈
tail = s.xfer2([0xFF]*23)[7:]
r1, off = r1_of(tail)
print(f"  {'(只給時脈,無命令)':<18} " + (f"R1=0x{r1:02x} @bit{off}" if r1 is not None else "無回應 (全 0xff)"))
s.close()
