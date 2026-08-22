import spidev, subprocess, time, sys
sys.path.insert(0, '/home/alan/halow-test/halow-wm6108-rpi4/tools')
from mmcspi import bits, crc7_be
def sh(c): return subprocess.run(c, shell=True, capture_output=True, text=True)
def cs(l): sh("pinctrl set 8 op %s" % ('dh' if l=='high' else 'dl'))
def reset():
    sh("pinctrl set 17 op dl"); time.sleep(0.05)
    sh("pinctrl set 17 ip pu"); time.sleep(0.25)
def r1_of(t):
    s=bits(t); i=s.find('0')
    return (int(s[i:i+8],2), i) if (i>=0 and i+8<=len(s)) else (None,None)
def cmd(spi, op, arg=0, bad=False, extra=16):
    c=[0x40|op,(arg>>24)&0xFF,(arg>>16)&0xFF,(arg>>8)&0xFF,arg&0xFF]
    crc=(crc7_be(0,c)|0x01) ^ (0x7E if bad else 0)
    return spi.xfer2([0xFF]+c+[crc]+[0xFF]*extra)[7:]
def init(spi):
    reset(); cs('high'); spi.xfer2([0xFF]*10); time.sleep(0.002); cs('low')

s=spidev.SpiDev(); s.open(0,0); s.mode=0; s.max_speed_hz=400000; s.no_cs=True

print("=== 可重現性：連續 6 次獨立的 reset+訓練+CMD0 ===")
ok=0
for i in range(6):
    init(s); t=cmd(s,0); cs('high')
    r1,off=r1_of(t)
    aligned = (off==8)
    ok += aligned
    print("  #%d  %s   R1=0x%02x @bit%-3d %s" % (i+1, ' '.join('%02x'%b for b in t[:4]), r1, off, "對齊" if aligned else "偏移"))
print("  → %d/6 對齊\n" % ok)

print("=== 完整命令序列（做完正確初始化之後）===")
init(s)
for label, kw in [("CMD0  正確CRC", dict(op=0)),
                  ("CMD0  錯誤CRC", dict(op=0, bad=True)),
                  ("CMD13 狀態",     dict(op=13)),
                  ("CMD63 morse init", dict(op=63)),
                  ("CMD63 arg=FFFF", dict(op=63, arg=0xFFFFFFFF))]:
    t=cmd(s, **kw); r1,off=r1_of(t)
    print("  %-18s %s   R1=%s @bit%s" % (label, ' '.join('%02x'%b for b in t[:5]),
          ('0x%02x'%r1) if r1 is not None else '--', off))
cs('high')
