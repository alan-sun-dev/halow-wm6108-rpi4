# HT-HC01P hardware / driver / device-tree inventory

*This file is the HT-HC01P's own inventory. The lab-wide inventory and the
validation matrix across all five nodes are in [HARDWARE.md](HARDWARE.md).*

**Subject:** Raspberry Pi 4B + Heltec HT-HC01P Pi HAT (Morse Micro MM6108**A2**), running
Heltec's OpenWrt image with Morse driver 1.15.3. This is the machine that currently
works, and it was not modified.

**Collected:** 2026-08-24, from the Mac over `en5` → `10.42.0.1`.
**Raw transcript:** [`heltec-hc01p-raw-evidence.txt`](heltec-hc01p-raw-evidence.txt) — 136 commands, every one with its full output.

## 0. What was and was not done

Read-only throughout. No package installed, no file written on the board, no reboot,
no `wifi reload`, no module load or unload, no GPIO write, no BCF or device-tree change,
and **no scan was triggered** (a scan transmits, so even that was avoided).

The three `.dtbo` files were *read out* of `/boot/overlays/` and decompiled on a
different host — the station Pi at `192.168.108.19`, which has `dtc` — so that nothing
had to be installed on the HT-HC01P.

Tools **UNAVAILABLE** on this image: `dtc`, `fdtget`, `od`, `wpa_cli`, `md5sum`, `cksum`,
`raspi-gpio`, `gpiodetect`. Present and used instead: `hexdump`, `xxd`, `sha256sum`,
`gpioinfo`, `iw`, `morse_cli`, `wpa_cli_s1g`, `uci`, `logread`, `zcat /proc/config.gz`.

## 1. Platform identity

| | |
|---|---|
| model | `Heltec Automation HT-HC01P` / `Raspberry Pi 4 Model B Rev 1.4` |
| `board_name` | `Heltec,Pi4-HT-HC01P-64bit` |
| distribution | OpenWrt 23.05.5, `2.8.5-20251107` (Heltec's package version, **not** the driver version) |
| kernel | `5.15.167 aarch64`, built by `halow-raspi@ubuntu`, OpenWrt GCC 12.3.0 |
| hostname | `HT-HC01P-8E91` |
| eth0 / br-lan MAC | `e4:5f:01:40:8e:91` |
| HaLow MAC | `0c:bf:74:40:8e:91` |

**The wireless stack is backported, not in-tree.** `/proc/config.gz` says
`# CONFIG_CFG80211 is not set`, yet `cfg80211` and `mac80211` are loaded modules. They come
from OpenWrt's `mac80211` backports package. Anything inferred from this kernel about
mac80211 behaviour does not transfer to a Raspberry Pi OS kernel, which uses its own
in-tree stack.

## 2. Identifying the Morse interface without guessing the name (requirement 11)

The HaLow netdev is **`wlan1` on this boot** and was `wlan0` on the previous boot. The name
is not stable: `brcmfmac … phy1-ap0: renamed from wlan0` appears in the log, i.e. the
Broadcom 5 GHz interface and the Morse interface race for `wlan0`.

Reliable identification, in order of preference:

```sh
# 1. by driver — the definitive test
for n in /sys/class/net/*; do
  [ "$(basename "$(readlink -f "$n/device/driver")")" = morse_spi ] && basename "$n"
done

# 2. by sysfs device path (the SPI controller address is fixed by the SoC)
ls -l /sys/class/net/*/device | grep fe204000.spi

# 3. by the supplicant control socket that the Morse supplicant creates
ls /var/run/wpa_supplicant_s1g/
```

Measured on this board:

```
wlan1     driver=morse_spi  devpath=/sys/devices/platform/soc/fe204000.spi/spi_master/spi0/spi0.0
phy1-ap0  driver=brcmfmac   devpath=/sys/devices/platform/soc/fe300000.mmc/mmc_host/mmc1/mmc1:0001/mmc1:0001:1
morse0    driver=(none)     virtual, DOWN, MAC 12:00:00:00:00:00
```

`morse0` is a virtual netdev the driver creates and keeps down; it is **not** the data
interface. Note also that `iw dev` reports the Morse phy as `phy#0` here but the phy number
is not stable either — use the sysfs path.

## 3. Device tree

### 3.1 Which overlays supply it

`/boot/distroconfig.txt` (included from `config.txt`):

```
dtoverlay=sdio,poll_once=on
dtparam=sdio_overclock=42
dtoverlay=uart5
dtoverlay=mm_wlan          <-- FILE DOES NOT EXIST, silently ignored
dtoverlay=morse-ps
dtparam=spi=on
dtparam=act_led_trigger=none
dtoverlay=ramoops
dtoverlay=sysinfo,board-name="Heltec,Pi4-HT-HC01P-64bit",model="Heltec Automation HT-HC01P"
dtoverlay=mm610x-spi
```

`ls /boot/overlays/mm_wlan.dtbo` → `No such file or directory`. Only `mm610x-spi.dtbo`
(1819 B, sha256 `c392208debc49b134c379e4bcc8d26c6c7727f890c66f0282b06c638aac1320b`) and
`morse-ps.dtbo` (1260 B, sha256 `6f72450fda84336d7377961124f52d54fac773d673587620fab5f1f4511f855c`)
exist. One of the three configured overlays is a no-op.

### 3.2 Live MM6108 node

`/proc/device-tree/soc/spi@7e204000/mm6108@0`, raw bytes decoded:

| property | raw | meaning |
|---|---|---|
| `compatible` | `6d6f7273652c6d6d363130782d73706900` | `"morse,mm610x-spi"` |
| `reg` | `00000000` | chip select index **0** |
| `spi-max-frequency` | `02faf080` | **50,000,000** Hz |
| `reset-gpios` | `00000007 00000005 00000000` | `<&gpio 5 0>` |
| `spi-irq-gpios` | `00000007 00000019 00000000` | `<&gpio 25 0>` |
| `power-gpios` | `00000007 00000003 00000000` `00000007 00000007 00000000` | `<&gpio 3 0>, <&gpio 7 0>` |
| `status` | `6f6b617900` | `"okay"` |

Phandle `0x07` resolves to `/proc/device-tree/soc/gpio@7e200000`, `compatible =
"brcm,bcm2711-gpio"`, `#gpio-cells = <2>` — so every entry is `<controller, number, flags>`.

### 3.3 Live SPI controller node

`/proc/device-tree/soc/spi@7e204000`:

| property | raw | meaning |
|---|---|---|
| `compatible` | `6272636d2c62636d323833352d73706900` | `"brcm,bcm2835-spi"` |
| `cs-gpios` | `00000007 00000008 00000001` | **`<&gpio 8 1>` — one chip select, GPIO 8, flag 1 (`GPIO_ACTIVE_LOW`)** |
| `pinctrl-0` | `000000f3 000000f4` | `<&spi0_pins &spi0_cs_pins>` |
| `pinctrl-names` | `default` | |
| `interrupts` | `00000000 00000076 00000004` | GIC SPI 118 → IRQ 18 |
| `status` | `okay` | |

Both `spidev@0` and `spidev@1` are present but `status = "disabled"`.

Resolving the two pinctrl phandles inside the GPIO controller node:

```
spi0_pins     (phandle 0xf3)  brcm,pins = <9 10 11>   brcm,function = <4>  (ALT0)   brcm,pull = <2 2 2>
spi0_cs_pins  (phandle 0xf4)  brcm,pins = <8>         brcm,function = <1>  (GPIO_OUT) brcm,pull = <2>
```

Note the stock Raspberry Pi `spi0_cs_pins` group lists pins 8 **and** 7; the Heltec overlay
replaces it with pin 8 only, because pin 7 is needed for MM_BUSY.

### 3.4 `mm610x-spi.dtbo`, decompiled

```dts
fragment@0 {                       /* target: &spi0 */
    pinctrl-0 = <&spi0_pins &spi0_cs_pins>;
    cs-gpios  = <&gpio 8 1>;
    status    = "okay";
    mm6108@0 {
        compatible        = "morse,mm610x-spi";
        reg               = <0x00>;
        reset-gpios       = <&gpio 5 0>;
        power-gpios       = <&gpio 3 0>, <&gpio 7 0>;
        spi-irq-gpios     = <&gpio 25 0>;
        spi-max-frequency = <0x2faf080>;   /* 50 MHz */
        status            = "okay";
    };
    spidev@0 { reg = <0x00>; status = "disabled"; };
    spidev@1 { reg = <0x01>; status = "disabled"; };
};
fragment@1 {                       /* target: &gpio */
    spi0_cs_pins { brcm,pins = <0x08>; brcm,function = <0x01>; brcm,pull = <0x02>; };
    spi0_pins    { brcm,pull = <0x02 0x02 0x02>; };
};
```

This is byte-for-byte the Morse EKH01 reference from `MM_APPNOTE-24` apart from the
`power-gpios` pins, and it is the same 50 MHz / `reset-gpios` flag 0 / `cs-gpios <&gpio 8 1>`
combination recorded in NOTES.md as the configuration every implementation inherits.

### 3.5 `morse-ps.dtbo`, decompiled — this is where RESET_N is actually decided

```dts
fragment@0 {                       /* target: &gpio */
    gpio_mm_ps    { mm-async-wakeup7-high { pins="gpio7"; function="gpio_in"; bias-pull-down; output-high; }; };
    gpio_mm_reset { mm-reset5-float       { pins="gpio5"; function="gpio_in"; bias-disable;   output-high; }; };
    gpio_mm_jtag  { jtag-reset4-low       { pins="gpio4"; function="gpio_out"; bias-pull-low; output-low;  }; };
};
fragment@1 {                       /* target: &leds  <-- why pinmux shows "leds" as the owner */
    pinctrl-names = "default";
    pinctrl-0 = <&gpio_mm_ps &gpio_mm_reset &gpio_mm_jtag>;
};
```

**MM_RESET (GPIO 5) is deliberately parked as an input with no bias — high-impedance,
floating.** MM_BUSY (GPIO 7) is an input with a pull-down. A JTAG reset on GPIO 4 is held
low. Because fragment@1 targets `&leds`, the pinmux owner of pins 5 and 7 reads as `leds`,
which is confusing but harmless.

## 4. GPIO map (requirement 2)

Every row is from live data on this board. Nothing here is taken from a datasheet or a
web page.

```text
Signal        Raspberry Pi GPIO   Active level                       Evidence
SPI CLK       GPIO 11             n/a (ALT0 function)                pinmux "pin 11 ... function alt0"; line name SPI_SCLK; spi0_pins brcm,function=<4>
SPI MOSI      GPIO 10             n/a (ALT0 function)                pinmux "pin 10 ... function alt0"; line name SPI_MOSI
SPI MISO      GPIO 9              n/a (ALT0 function)                pinmux "pin 9 ... function alt0";  line name SPI_MISO
SPI CS        GPIO 8              active LOW (DT flag 1)             cs-gpios=<&gpio 8 1>; spi0_cs_pins function=<1> gpio_out, pull=<2> up; pinmux "pin 8 ... function gpio_out ... in hi"
RESET_N       GPIO 5              hardware active LOW;               reset-gpios=<&gpio 5 0>; morse-ps mm-reset5-float => gpio_in, bias-disable;
                                  DT flag is 0 and is IGNORED        /sys/kernel/debug/gpio "gpio-5 (MM_RESET)" with no consumer; pins "pin 5 ... gpio_in in hi"
                                  by the driver (see section 10)
IRQ/INT       GPIO 25             LEVEL LOW                          /proc/interrupts "47: pinctrl-bcm2835 25 Level  Morse SPI IRQ" (7707 taken);
                                                                     pins "pin 25 ... irq 47 (level-low)"; gpio "gpio-25 |mm610x_spi_irq_gpio in lo IRQ"
WAKE          GPIO 3              driven by the driver, out, low     power-gpios[0]; of.c maps power-gpios index 0 -> gpios->wake;
                                                                     gpio "gpio-3 (MM_WAKE |morse-wakeup-ctrl) out lo"
BUSY          GPIO 7              input, EDGE RISING, pull-down      power-gpios[1]; of.c maps index 1 -> gpios->busy;
                                                                     /proc/interrupts "46: pinctrl-bcm2835 7 Edge  async_wakeup_from_chip" (4968 taken);
                                                                     gpio "gpio-7 (MM_BUSY |morse-async-wakeup-c) in lo IRQ"
POWER/ENABLE  none                UNKNOWN / not present              the mm6108@0 node has no enable-gpios, no regulator phandle, no vdd supply;
                                                                     `power-gpios` in Morse's binding is WAKE+BUSY, not a power switch
```

Two things worth calling out because they are easy to get wrong:

- **`power-gpios` is not a power rail.** `of.c` in the driver reads index 0 into
  `gpios->wake` and index 1 into `gpios->busy`. The name is misleading; it is the
  power-*save* handshake pair.
- **The board provides no host-controlled power enable at all.** If the module needs a
  power cycle, it needs the Pi power-cycled.

Both GPIO views agree, and they answer different questions — keep them apart:
`/sys/kernel/debug/pinctrl/…/pins` reports the **mux function**, `gpioinfo` and
`/sys/kernel/debug/gpio` report **whether the GPIO subsystem has claimed the line**.
Pin 8 is `function gpio_out` in the first and `unused` in the second.

## 5. SPI runtime configuration (requirement 3)

```text
SPI controller driver   spi-bcm2835, built in (CONFIG_SPI_BCM2835=y), polling_limit_us=30
SPI device              spi0.0
                        modalias = spi:mm610x-spi
                        of_node  = /sys/firmware/devicetree/base/soc/spi@7e204000/mm6108@0
max_speed_hz            50,000,000  (DT spi-max-frequency 0x02faf080)
current configured      50,000,000  (module parameter spi_clock_speed = 50000000, same value)
mode                    not exposed in sysfs on this kernel -- UNKNOWN by direct read.
                        Inferred from the DT: cs-gpios flag 1 => SPI_CS_HIGH is managed by
                        gpiolib inversion, not by the device's mode word.
chip select             index 0, GPIO 8, active low
IRQ                     47, GPIO 25, level-low, named "Morse SPI IRQ"
                        (the controller's own IRQ 18 fe204000.spi has taken 0 interrupts)
driver binding          /sys/bus/spi/drivers/morse_spi/spi0.0
```

Error counters after 24.5 MB of traffic, from `/sys/class/spi_master/spi0/statistics/`:

```
bytes 24515891   bytes_rx 24515891   bytes_tx 24515891
messages 103138  transfers 103138    transfers_split_maxsize 0
errors 0         timedout 0          spi_async 0   spi_sync 103138
```

Transfer-size histogram (this is a useful fingerprint of the padding behaviour):

```
16-31     36713
256-511   56565
512-1023   9785
4096-8191     72
2048-4095      2
1024-2047      1
```

The 256–511 bucket dominating is consistent with a ~250-byte inter-transaction pad on
every block, which is what the 50 MHz clock produces from the driver's delay formula.

`/proc/device-tree` and `/sys/firmware/devicetree/base` are the same tree — the second is a
symlink target of the first; both were read and agree.

## 6. Morse driver state (requirement 4)

```text
kernel version        5.15.167 aarch64
morse driver          0-rel_1_15_3_2025_Apr_16   (module "morse", 348160 bytes)
dot11ah               0-rel_1_15_3_2025_Apr_16   (module "dot11ah", 73728 bytes)
loaded modules        morse, dot11ah, mac80211, cfg80211, crc7, brcmfmac, batman_adv
firmware filename     morse/mm6108.bin
BCF filename          morse/bcf_HC01_V2_H.bin
chip ID / silicon     HW version register 0x00000406
identification        = MM6108A2   (morse_cli hw_version: "MM6108A2")
interface name        wlan1 on this boot -- unstable, see section 2
phy name              phy0 on this boot -- also unstable
SPI error counters    errors 0, timedout 0 (see section 5)
driver errors in dmesg  none
```

Module parameters at load, from `/etc/modules.d/morse`:

```
morse bcf=bcf_HC01_V2_H.bin country=SG enable_sgi_rc=1 macaddr_suffix=40:8e:91
```

Notable live parameter values (full list in the raw evidence):

```
spi_clock_speed 50000000     tx_max_power_mbm 2200     enable_ps 2
enable_hw_scan Y             enable_1mhz_probes Y      enable_sched_scan Y
enable_otp_check 1           enable_ext_xtal_init N    spi_use_edge_irq N
fixed_bw 2  fixed_mcs 4  fixed_ss 1  enable_fixed_rate N   (fixed rate disabled, so the
                                                            fixed_* values are inert)
```

The only dmesg lines matching `error|fail|warn` that concern Morse are the two informational
`Loaded firmware` / `Loaded BCF` lines, which match because they print a CRC32. There are no
Morse errors, no SPI timeouts, and no command failures.

`vendor_info` from debugfs, which also shows the peer:

```
MM vendor-specific information
    SW version: 1.15.3        HW version: 0x00000406     <- this board, MM6108A2
    Rate control: MMRC
AP [3c:1a:cc:70:3f:ca]:
    SW version: 2.0.1         HW version: 0x00000306     <- the OpenMANET AP, MM6108A1
```

That is a live, on-air demonstration that a 1.15.3 MM6108A2 station and a 2.0.1 MM6108A1 AP
interoperate.

## 7. BCF (requirement 5)

**Confirmed: the BCF in use is `bcf_HC01_V2_H.bin`.**

```text
full path       /lib/firmware/morse/bcf_HC01_V2_H.bin
file size       1170 bytes
sha256          5744fa288d79cd2a8ad8e146bec9aff8d06a6f87c160a0a44358ceb6cd53ba9f
crc32           0x389a48c4          (as printed by the driver at load)
permissions     -rw------- (0600), owner root -- one of the files Heltec added
specified by    /etc/config/wireless      line 8: option bcf 'bcf_HC01_V2_H.bin'
                /etc/modules.d/morse      line 2: morse bcf=bcf_HC01_V2_H.bin ...
loaded at boot  [6.649261] morse_spi spi0.0: Loaded BCF from morse/bcf_HC01_V2_H.bin,
                           size 1170, crc32 0x389a48c4
live param      /sys/module/morse/parameters/bcf = bcf_HC01_V2_H.bin
```

The other BCFs present, none of them modified:

```text
bcf_mf08551.bin        1150 B  57c50cb2c1d51187667677b392684285c616ddbf3fe262c3aeece342f446773e
                       Morse EKH01-03 / EKH03v3 evaluation board. This was the shipped
                       default (still in /etc/config/wireless.bak and .pre-bcf-20260824)
                       and it is what left the module receiving but not transmitting.
bcf_default.bin        symlink -> bcf_failsafe.bin
bcf_failsafe.bin       1085 B  25c7bd8de4826d461d722eca1a837b0a22adfaeed3d45e5e68ab659d6844abfe
bcf_boardtype_0801.bin symlink -> bcf_mf08651_us.bin
bcf_mf08651_us.bin     1539 B  c6e20c1b74488381e016e871a2c09dfa9af7167ab64178590d92a91eeb94f644
bcf_HD01_v2.bin        1251 B  55089af7d08597a16ddd4002ca4b23f24729aa5bd0f1b75b6e04bc5270d23ba6
bcf_mf04151.bin        1170 B  5462d251bf80c6b1368d5c9585039be2c941bb311e6ea64c6c9116efaeb019f3
bcf_mf10220.bin        1150 B  5d6e3c651cb6e34dde4a88dcaa4b6aaaad12b2a2d822fae83f3bfe7ac415cb98
bcf_mf15457.bin        1608 B  2eadef88f4ae8dc156bbc45de067ae184ad8e6d0af03d738e91be45d01b29f21
bcf_mf16858.bin        1158 B  873e20b43893568650f27a3e3c5c1928e8a8cba47e139ed883cec28b7c749eef
bcf_mf28251_telec.bin   871 B  329b3e2ae7abcf72e6dfc506f8f2281448fbbdc14159bb7fa83da42c44c722d5
bcf_mf08651_4v3_us.bin 1435 B  687c6e9d1a937ab27864d39f0081c40bb7d61f03a901b96b9bcc43dcb5a4c3a0
bcf_mf08651_jp.bin      813 B  45a0e622c6e612d3a27083ab280887154676078d9909fea70c311e8f336bdca3
bcf_aw_hm593.bin       1466 B  6450dcabbc34b4e8e53ed017a0c7d851f94915e52a706f88617f5bbc17282dcb
bcf_aw_hm593_4v3.bin   1505 B  f675c4ea7a9140d07c3be87abc25fb87f2a553919e9aeefc7d68b46e470467bb
bcf_ekh04_v6.bin       1132 B  f63ae9dbc5ecf35f364b15185f21f3006a0f1f12c1921c77f7a7c5cf76b33615
bcf_mm_hl1.bin         1544 B  b66d4fdab77fb095bcea61ecf7f6db4b28a8cb22f333a8a564068eca392882d9
bcf_mm_hl1_4v3.bin     1548 B  6b9f1aca9ef41382982ffeba2b5d794ba223f6395cf50a37c103757bf66b46c6
```

The chip cannot choose for itself: `morse_cli boardtype` → **"Board type is not set"**, and
`/sys/bus/spi/devices/spi0.0/board_type` → `0`. `country_code` OTP is unset too. OTP banks
read `0x0 / 0xff000000 / 0x401fff / 0x10 / 0x0 / 0x69877e9f / 0x0 / 0x0`. That is why the
`bcf_boardtype_%04x.bin` mechanism cannot fire and the BCF has to be named explicitly.

## 8. Firmware (requirement 6)

```text
location        /lib/firmware/morse/mm6108.bin
size            444304 bytes
sha256          1c12fc426bf0700134cd66e352c2f246fc124911631b82a992374ce8f3116d1c
crc32           0x1c6a0f92        (printed by the driver)
version         1.15.3 -- from debugfs vendor_info "SW version: 1.15.3", and
                morse_cli version "FW Version: rel_1_15_3_2025_Apr_16"
loaded          [6.640157] morse_spi spi0.0: Loaded firmware from morse/mm6108.bin,
                           size 444304, crc32 0x1c6a0f92
debugfs         /sys/kernel/debug/ieee80211/phy0/morse/firmware_path = morse/mm6108.bin
```

Also present but unused: `mm6108-dvt.bin` (448400 B,
`916e8ee1718cb2b8a2b88a698daa10786fbe0cfa14fb2db6d3a642afeb8d403b`) and `mm6108-tlm.bin`
(437724 B, `175cc190038a6b12d8fcccf6dffac74c3df4942167d925c236df9bcf715bc163`).

For comparison, the `morse-firmware` release used with driver 2.0.1 on the other bench
machine ships `mm6108.bin` at **468304 bytes**, sha256
`db3a23cb9a756243e1081df32bc66195f0e46918140f644f356de8fc90675a75`. **Different file.** The
firmware travels with the driver version, not with the board.

## 9. Working wireless configuration (requirement 7)

Recorded, not changed.

```text
country                  SG  (module parameter, supplicant conf, and uci all agree)
regulatory               phy0 is self-managed; "country SG: DFS-invalid",
                         920-925 MHz @ 4 MHz, 22 dBm
operating frequency      922000 kHz          <- "Full" channel
channel                  s1g channel 40 (SG 4 MHz), mapped 5 GHz channel 155
S1G channel bandwidth    4 MHz operating
primary channel bw       2 MHz
primary channel index    1
current channel          921000 kHz, 2 MHz operating, 2 MHz primary, index 1
                         (morse_cli channel -a reports Full / DTIM / Current separately;
                          Current is the AP's 2 MHz primary, s1g channel 38)
tx power                 22.00 dBm (iw), tx_max_power_mbm 2200
power save               ON   ("iw dev wlan1 get power_save" -> "Power save: on",
                          enable_ps=2). This is the likely cause of the asymmetric ping.
interface mode           managed / station (mode=station, "wlan1 not an AP")
SAE / PMF                key_mgmt=SAE, pairwise CCMP, group CCMP,
                         mgmt_group_cipher=BIP, pmf=2, sae_group=19, sae_h2e=1,
                         sae_pk=0, bss_max_idle_period=292, wpa_state=COMPLETED
associated to            3c:1a:cc:70:3f:ca, SSID BCM2711-57e7, ip 10.41.0.216
```

Supplicant config in use (`/var/run/wpa_supplicant-wlan1.conf`):

```
country=SG
ctrl_interface=/var/run/wpa_supplicant_s1g
sae_pwe=1
network={
        scan_ssid=1
        ssid="BCM2711-57e7"
        key_mgmt=SAE
        sae_password="..."
        pairwise=CCMP
        proto=RSN
        ieee80211w=2
}
```

The SG regulatory table it is working against, `/usr/share/morse-regdb/channels.csv`:

```
bw=1 : chan 37/39/41/43/45 @ 920.5/921.5/922.5/923.5/924.5   (5g map 149/153/157/161/165)
bw=2 : chan 38 @ 921.0, chan 42 @ 923.0                      (5g map 151/159)
bw=4 : chan 40 @ 922.0                                       (5g map 155)
tx_power_max 22.15 dBm, duty cycle 100% in the 920-925 band
```

## 10. RESET_N polarity — the explicit answer (requirement 10)

**Device tree, as it exists on the working machine:**

```dts
reset-gpios = <&gpio 5 0>;
```

- GPIO controller: `gpio@7e200000`, `brcm,bcm2711-gpio`, `#gpio-cells = <2>`
- GPIO number: **5**
- Flag cell: **0**

**What flag 0 means in Linux device-tree GPIO semantics.** The second cell is a bitfield,
and bit 0 is `GPIO_ACTIVE_LOW` (`include/dt-bindings/gpio/gpio.h`: `GPIO_ACTIVE_HIGH 0`,
`GPIO_ACTIVE_LOW 1`). So flag 0 declares the line **active high**. It does *not* say
anything about the electrical level at reset; it says how a *logical* value passed to the
gpiod API should be translated to a physical level. Flag 0 → logical 1 drives physically
high. Flag 1 → logical 1 drives physically low.

**But that translation only happens for consumers that use the gpiod (descriptor) API, and
morse_driver does not.** Verified against the 2.0.1 source at tag `mm6108-2.0.1`
(`98e1936`):

- `git grep gpiod_ HEAD -- '*.c' '*.h'` → **0 files**. There is no descriptor API call
  anywhere in the driver.
- `of.c: morse_of_probe()` reads the pin with `of_get_named_gpio(np, "reset-gpios", 0)`,
  which returns **only the number**. The flags variant `of_get_named_gpio_flags()` is never
  called, and neither `GPIO_ACTIVE_LOW` nor `OF_GPIO_ACTIVE_LOW` appears in the tree.
- `hw.c: morse_hw_reset(int reset_pin)` uses the legacy integer API, and the legacy API is
  raw — `gpio_direction_output()` maps to `gpiod_direction_output_raw()`, which bypasses
  any active-low inversion.

```c
int morse_hw_reset(int reset_pin)
{
        int ret = gpio_request(reset_pin, "morse-reset-ctrl");
        if (ret < 0) { ...skip reset... }
        pr_info("Resetting Morse Chip\n");
        gpio_direction_output(reset_pin, 0);   /* drive the pin PHYSICALLY LOW */
        mdelay(20);
        gpio_direction_input(reset_pin);       /* release it to float, comment in source:
                                                * "setting gpio as float to avoid forcing
                                                *  3.3V High" */
        pr_info("Done\n");
        gpio_free(reset_pin);
        return ret;
}
```

**So, concretely, on this board:**

1. The DT flag `0` is **read and discarded**. Changing it to `1` would change nothing in
   morse_driver's behaviour. (It would matter to any *other* consumer of that line, and to
   `gpioinfo`'s "active-low" column, but the driver is the only consumer.)
2. The kernel drives GPIO 5 **low for 20 ms**, then switches it to an input so the line
   floats back high through whatever pull the HAT provides. MM6108's RESET_N is active low,
   so this is a genuine reset pulse — asserted low, released.
3. Between resets the line is not driven at all. `morse-ps.dtbo` parks it as
   `function = "gpio_in"; bias-disable;` and `/sys/kernel/debug/gpio` confirms
   `gpio-5 (MM_RESET)` has **no consumer** right now, `gpioinfo` says `unused input`, and
   the pin reads high.
4. This did happen on this machine and the chip survived it: `Resetting Morse Chip` appears
   in the log at the driver reload, followed by a successful firmware load and association.

**This contradicted a claim recorded in NOTES.md** ("its `reset-gpios` flag is 0, so
`gpiod_set_value(reset, 1)` drives the pin *high* and RESET_N never fires"). That sentence
cannot describe morse_driver 2.0.1, which contains no `gpiod_set_value` at all.

**Settled 2026-08-24 and NOTES.md is now corrected.** The OpenMANET AP's own boot log shows
`Resetting Morse Chip` — so it *does* reset, running the same 2.0.1 — and what actually lets
it survive that is a Morse-authored kernel patch,
`991-0007-spi-support-control-cs-pin-on-init.patch`, which adds
`SPI_CONTROLLER_ENABLE_CS_GPIOD` to the SPI core so the driver's CS-deassert during the
training burst genuinely works. Full account in the analysis document, §5.

## 11. Kernel configuration relevant to the port

```text
CONFIG_SPI=y                 CONFIG_SPI_MASTER=y      CONFIG_SPI_BCM2835=y
CONFIG_SPI_BCM2835AUX=y      CONFIG_SPI_GPIO=y        CONFIG_SPI_BITBANG=y
CONFIG_SPI_DYNAMIC=y         CONFIG_SPI_SPIDEV=m
CONFIG_GPIOLIB=y             CONFIG_OF_GPIO=y         CONFIG_GPIO_CDEV=y
CONFIG_GPIO_SYSFS=y          CONFIG_GPIO_RASPBERRYPI_EXP=y
CONFIG_OF_OVERLAY=y          CONFIG_OF_DYNAMIC=y      CONFIG_OF_RESOLVE=y
# CONFIG_CFG80211 is not set        <-- backports supply cfg80211/mac80211 instead
```

`/proc/cmdline` carries nothing SPI- or Morse-related.
