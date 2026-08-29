# Lab hardware inventory and validation matrix

*[中文版](HARDWARE.zh-TW.md)*

Last reviewed 2026-08-29 against repository evidence. Every row cites where it
was measured. Anything not measured says **TBD**, not a plausible value.

## Scope: everything in this lab is SPI

**There is no SDIO HaLow platform in the current lab.** All MM6108 silicon in
scope is attached over SPI, on `spi-bcm2835`, as `spi0.0`, through a
`compatible = "morse,mm610x-spi"` device-tree node.

So the engineering question this lab answers is **not bus-versus-bus**. It is:

> How do two different MM6108 **SPI** implementations behave across different
> carrier boards, GPIO mappings, device trees, calibration/BCF, chip revisions
> and recovery architectures?

Three places in this repository mention SDIO, none of them a current HaLow
platform, all of them correct in their own context:

- The **Raspberry Pi's own** 2.4/5 GHz `brcmfmac` radio is on SDIO
  (`fe300000.mmc`). It is not HaLow and it shares nothing with the Morse chip.
- The **HT-H7608** is a MIPS OpenWrt appliance whose Morse radio *is* on SDIO
  (`platform/10130000.mmc/mmc_host/mmc0/…`, NOTES.md "Hardware and OS, confirmed
  live"). **It is excluded from this matrix.** It was the wrong regional SKU
  (`Region: 863~870MHz`) and was factory-reset off the bench on 2026-08-26.
- `rmmod mm6108_sdio` in TESTING.md is a defensive line for unknown vendor
  images, not a description of this lab.

The H7608 is the likeliest source of any impression that this lab runs both
buses, because it carries the **same HT-HC01 V2 module and the same BCF** as the
HT-HC01P — one wired SDIO, one wired SPI. That is a fact about Heltec's two
products, not about what is on the bench now.

Do not add an SDIO row to this file unless a real SDIO machine joins the lab.

## Inventory: the five nodes in scope

| # | node | module | rev | bus | role | status |
|---|---|---|---|---|---|---|
| 1 | SenseCAP M1 (`57:E7`) | Seeed Wio-WM6108 / FGH100M-H | MM6108**A1** | SPI | AP / gateway for the segment | in service — **do not disturb** |
| 2 | SenseCAP M1 (`55:04`) | Seeed Wio-WM6108 / FGH100M-H | MM6108**A1** | SPI | long-running reference / soak station | in service — **do not disturb** |
| 3 | SenseCAP M1 — new #1 | Seeed Wio-WM6108 / FGH100M-H | MM6108**A1** | SPI | reproducibility / fresh-install validation | **fresh OS install pending** |
| 4 | SenseCAP M1 — new #2 | Seeed Wio-WM6108 / FGH100M-H | MM6108**A1** | SPI | console-server prototype | **fresh OS install pending** |
| 5 | RAK Hotspot v2, modified | Heltec **HT-HC01P** | MM6108**A2** | SPI | second SPI platform; DKMS / kernel regression; destructive recovery | in service |

Nodes 3 and 4 are the same hardware configuration as node 2. Their hostnames and
MAC addresses are **TBD** — nothing has been installed, and no value is recorded
here until the boards report one themselves.

Node 5 is one machine with two names in the older notes: `dkmstest` and
`hc01p` are the same RAK chassis carrying the Heltec HAT and module.

## Wio-WM6108 versus HT-HC01P: two SPI implementations

Node 2 (the soak station) is the reference for column one; node 5 for column two.

| | **Seeed Wio-WM6108 / FGH100M-H** | **Heltec HT-HC01P** |
|---|---|---|
| Module / vendor | Seeed Wio-WM6108 (FGH100M-H), mini-PCIe form | Heltec HT-HC01P, HT-HC01 V2 module on a Heltec Pi HAT |
| MM6108 revision | **A1** — chip ID `0x0306` | **A2** — chip ID `0x0406` |
| SPI host interface | `spi-bcm2835`, `spi0.0`, BCM2711 | identical: `spi-bcm2835`, `spi0.0`, BCM2711 |
| Carrier / host platform | SenseCAP M1 mPCIe slot on a Pi 4B rev 1.4, wired to the Seeed WM1302 Pi HAT pin map | RAK Hotspot v2 chassis, Pi 4B, Heltec Pi HAT |
| SPI clock, validated | **50 MHz** — live DT reads `02 fa f0 80` | **50 MHz** — overlay `spi-max-frequency = <50000000>` |
| Device tree / overlay | `overlays/mm610x-spi-sensecap.dts`, loaded as `dtoverlay=mm610x-spi-sensecap` | `overlays/mm610x-spi-hc01p.dts` — Heltec's `mm610x-spi.dtbo` + `morse-ps.dtbo` merged and re-expressed for a stock kernel |
| DT node name | `mm610x@0` | `mm6108@0` |
| Chip-select handling | **two chip selects** — GPIO 8 (`spi0 CS0`) and GPIO 7 (`spi0 CS1`), inherited from `dtparam=spi=on` and harmless here | **narrowed to one** — `cs-gpios = <&gpio 8 1>` and `spi0_cs_pins` reduced to `<8>`, because **GPIO 7 is MM_BUSY on this HAT**; leaving the stock `<8 7>` group would mux away the power-save handshake line |
| RESET_N | **GPIO 17**, active low, `reset-gpios = <&gpio 17 1>`. The overlay must force a **pull-up**: `morse_hw_reset()` floats the line rather than driving it high, and BCM2711 defaults GPIO 9–27 to pull-down, which would hold the radio in reset forever | **GPIO 5**, `reset-gpios = <&gpio 5 0>`, parked as a **floating input, no bias** — the HAT supplies its own pull-up, matching the working OpenWrt board byte for byte |
| IRQ | **GPIO 5** — live consumer `mm610x_spi_irq_gpio` | **GPIO 25**, level-low — live IRQ 55 `Morse SPI IRQ` on `pinctrl-bcm2835 25 Level` |
| WAKE / BUSY | **GPIO 23 / GPIO 24** — `morse-wakeup-ctrl` and `morse-async-wakeup-ctrl` | **GPIO 3 / GPIO 7** — `power-gpios = <&gpio 3 0>, <&gpio 7 0>`; not a power rail |
| Other carrier pins | **GPIO 18** `halow-slot-power`, the M1's own mPCIe slot power enable, hogged high and also forced by `gpio=18=op,dh` | **GPIO 4** JTAG reset, hogged output-low (Heltec's `morse-ps.dtbo`) |
| BCF | `morse/bcf_fgh100mhaamd.bin` — 1251 B, md5 `4e128ad574304d1aec778c5ba5611f8f`, crc32 `0x941b2a82` | `morse/bcf_HC01_V2_H.bin` — 1170 B, crc32 `0x389a48c4`. **The shipped image used the wrong one**: `bcf_mf08551.bin`, Morse's EKH01-03 evaluation-board BCF, which cost the module its transmitter until it was replaced on 2026-08-24 |
| Firmware | `morse/mm6108.bin`, 468304 B, crc32 `0xbe7b5c8f` | **byte-identical**: `morse/mm6108.bin`, 468304 B, crc32 `0xbe7b5c8f` |
| MAC provisioning | **Keeps its own address with no parameter.** `options morse country=SG bcf=bcf_fgh100mhaamd.bin`, and `wlan1` is stably `9c:04:b6:ff:df:fe` | **Requires `macaddr_suffix=40:8e:91`.** Without it the driver invents a *random* MAC at every load (first probe came up `c2:d2:3d:87:dd:cd`), churning the AP station table and the DHCP lease |
| Validated kernels | **`6.6.51+rpt-rpi-v8`** (RPi OS Lite bookworm). `6.12.93` and `6.18.34` were exercised **before** the fix series and failed identically — defect reproduction, not validation. **`6.12.96` on A1 is untested: TBD** | **`6.6.51+rpt-rpi-v8` and `6.12.96+rpt-rpi-v8`**, same board, same DT, same firmware, same BCF, only the kernel changed |
| Local recovery path | USB-C gadget (NCM + ACM) on the **Pi's own** USB-C, `192.168.45.0/24`. The M1's panel USB-C is HAT **5 V only** and carries no D+/D−. House Wi-Fi `wlan0` exists but is **`disconnected`**, and `192.168.108.19` did not answer on either 2026-08-28 or 2026-08-29 — when it has associated it did so at −86 dBm and was too slow to carry a checkpoint. **HaLow is the only remote path.** An `eth0-bench` profile exists but is **not documented or reproducible: TBD** | USB-C gadget on `192.168.44.0/24`, currently cabled to the MacBook, **plus a real USB serial console** (`/dev/cu.usbmodem*` on the Mac). Also reachable on house Wi-Fi and over HaLow |
| Role in the lab | node 1 is the AP; node 2 is the long-running reliability reference and the only board accumulating soak evidence | second SPI platform: DKMS and kernel-regression bed, and the board destructive recovery testing is meant to run on |

## Same chip family and same bus does not mean equivalent

Both columns above are MM6108 silicon on `spi-bcm2835` at 50 MHz, and they are
**not interchangeable**. The differences that are real, measured, and load-bearing:

- **Carrier board design** — an mPCIe slot on a Seeed HAT versus a Heltec Pi HAT.
- **GPIO mapping** — every control line differs. Reset 17 vs 5, IRQ 5 vs 25,
  wake 23 vs 3, busy 24 vs 7. The two overlays share only the SPI four.
- **Reset electrical behaviour** — the same driver code (float-on-release) needs
  a *forced pull-up* on one board and *no bias at all* on the other, because the
  pull comes from the SoC in one case and from the HAT in the other.
- **Chip-select handling** — two chip selects are harmless on the M1 and
  destructive on the Heltec HAT, where the second one lands on MM_BUSY.
- **Device-tree integration** — Heltec attach their pin parking to `&leds`; this
  repo's version hangs it off `spi0`'s own `pinctrl-0` so that nothing depends on
  an unrelated node being probed.
- **Board calibration / BCF** — different files, different sizes, different
  CRCs, and one of the two shipped pointing at an evaluation board's BCF.
- **Chip revision A1 vs A2** — `0x0306` vs `0x0406`. The SPI probe path calls
  `morse_chip_cfg_init(mors, MM6108A2_ID)` *before* reading the real ID.
- **MAC provisioning** — one keeps its address, one invents a random one per load
  unless told not to.
- **Boot and recovery behaviour** — one has a serial console and a laptop
  attached; the other's only remote path is the radio under test.

There is also a durable *behavioural* difference between the two, measured
repeatedly and still unexplained: on the same AP in the same minute the A1
station pays **1.17–1.64 retries per packet** where the A2 board pays **0.00**.

## Validation matrix

| | 6.6.51 | 6.12.96 | 6.12.93 | 6.18.34 |
|---|---|---|---|---|
| **A1 — Wio-WM6108 / SenseCAP M1** | ✅ in service, soaking | **TBD — untested** | ❌ pre-fix defect reproduction | ❌ pre-fix defect reproduction |
| **A2 — HT-HC01P / RAK** | ✅ verified | ✅ verified | — | — |

The **A1 / 6.12.96** cell is the open hole in this matrix. Node 2 has only
6.6.51 kernels installed, so closing it needs a board that is not the soak node —
which is what node 3 exists for.

## TBD

| field | node | why it is open |
|---|---|---|
| hostname | 3, 4 | not installed |
| HaLow MAC | 3, 4 | not installed |
| eth0 MAC | 3, 4 | not recorded from the boards |
| serial number | 3, 4 | not recorded from the boards |
| A1 on 6.12.96 | 2, 3 | never run; node 2 has only 6.6.51 kernels |
| Ethernet rescue procedure | 2, 5 | the capability is real, the procedure is unwritten |
| HAT button / fan / LED pins | 1–4 | undeclared in software; needs a board that is not the soak node |
| ATECC608A crypto chip | 1–4 | header I²C is off; scanning it costs a reboot |

Undeclared is not absent. Every TBD above says nothing has been *measured*, not
that the hardware is missing.

## Evidence

| claim | where |
|---|---|
| WM6108 is SPI | `overlays/mm610x-spi-sensecap.dts` (`morse,mm610x-spi`, `spi0`, `spi-max-frequency`); station `config.txt` line `dtoverlay=mm610x-spi-sensecap`; live DT `spi-max-frequency` = `02 fa f0 80`; live `/sys/kernel/debug/gpio` showing `spi0 CS0/CS1`, `mm610x_spi_irq_gpio`, `halow-slot-power`, `morse-wakeup-ctrl` |
| HC01P is SPI | `overlays/mm610x-spi-hc01p.dts`; `logs/2026-08-25-hc01p-rpios-stage3b-driver-up.txt` — `morse_spi spi0.0`, `Morse SPI IRQ` on GPIO 25, `/sys/class/spi_master/spi0` counters; `heltec-hc01p-hardware-inventory.md` §3 |
| A1 chip ID `0x0306` | `README.md` "Hardware"; `heltec-hc01p-linux-port-analysis.md` (`MM6108A1_ID … 0x306`) |
| A2 chip ID `0x0406` | `logs/2026-08-25-hc01p-rpios-stage3b-driver-up.txt`; `heltec-hc01p-hardware-inventory.md` (`morse_cli hw_version: "MM6108A2"`) |
| 50 MHz on both | station live DT read; `overlays/mm610x-spi-hc01p.dts`; `logs/2026-08-24-spi-clock-is-the-throughput-ceiling.txt` |
| BCF / firmware bytes | `logs/2026-08-25-hc01p-rpios-stage3b-driver-up.txt`; NOTES.md "The two boards, side by side"; `firmware/heltec-hc01p/` |
| MAC provisioning | `heltec-hc01p-linux-port-analysis.md` §Stage 4; live station `modprobe.d/morse.conf` |
| Two kernels on A2 | `logs/2026-08-25-hc01p-rpios-kernel-6.12-second-kernel.txt`; `port/hc01p/README.md` |
| H7608 is the only SDIO Morse device, and is off the bench | NOTES.md 2026-08-24 ("radio1 morse … SDIO") and 2026-08-26 (wrong regional SKU, factory reset) |
