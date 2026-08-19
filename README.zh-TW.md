# 在 Raspberry Pi 4 上以 SPI 驅動 Wio-WM6108（Morse Micro MM6108）

*[English README](README.md)*

Seeed **Wio-WM6108** Wi-Fi HaLow mini-PCIe 模組（Quectel FGH100M-H，Morse Micro
**MM6108A1**）在 Raspberry Pi 4 上以 SPI 驅動的移植紀錄、patch 與量測工具。

**狀態：模組是活的、也能自報身分，但無法使用。** 讀取路徑正常，第一筆 CMD53
資料寫入永遠等不到回應。這看起來就是
[MorseMicro/morse_driver issue #9](https://github.com/MorseMicro/morse_driver/issues/9)
撞到的同一道牆 —— 那個 issue 至今未解，而且對方用的是**官方支援的硬體**
（Raspberry Pi 4 + 原廠 Seeed WM1302 Pi HAT + 打過 Morse patch 的核心）。

公開出來，是希望這些量測能讓下一個人少花一個禮拜。

## 硬體

| | |
|---|---|
| 主機 | Raspberry Pi 4 Model B rev 1.4（BCM2711，`spi-bcm2835`）|
| 模組 | Seeed Wio-WM6108，chip ID `0x0306` = MM6108A1 |
| 載板 | SenseCAP M1 的 mPCIe 插槽，佈線沿用 WM1302 Pi HAT |
| 作業系統 | Raspberry Pi OS Trixie，原廠核心 6.18.34+rpt-rpi-v8 |
| 驅動 | MorseMicro/morse_driver 的 `mm6108-2.0.1` 與 `1.17.9` |

腳位對應（WM1302 Pi HAT，M1 插槽沿用同一套）：

| 訊號 | GPIO | 備註 |
|---|---|---|
| MISO / MOSI / CLK / CS | 9 / 10 / 11 / 8 | `spi0.0` |
| RESET_N | 17 | 低電位有效 |
| SPI_INT | 5 | 模組輸出 |
| WAKE / BUSY | 23 / 24 | 實測在這片載板上是浮接 |
| 插槽電源致能 | 18 | SenseCAP M1 特有，不屬於 HAT 的腳位定義 |

## 核心發現：晶片的回應固定晚 2 個 bit

每一筆回應都比位元組邊界晚兩個位元時間。這是在卸載驅動的狀態下，用
`/dev/spidev0.0` 從使用者空間直接量到的，與驅動無關：

| 送出 | 回傳的 R1（重新對齊 2 bit 之後）|
|---|---|
| CMD0，正確的 CRC7 | `0x01`（idle）|
| CMD0，**故意打壞 CRC7** | `0x09`（idle + CRC 錯誤）|
| CMD13 | `0x05`（idle + 非法指令）|
| 不送任何指令 | 全部 `0xff` |

晶片**驗證了我們的 CRC7**，也正確標示非法指令 —— 代表它的**接收**路徑完全正確地
解析了我們的位元組串流，偏移只發生在它的送出方向。這個現象是完全確定性的
（20 次測試 20 次相同），而且從 400 kHz 到 50 MHz 毫無變化，所以不是建立時間或
傳播延遲造成的。

`tools/` 裡的工具可以完整重現。先跑 `mmcspi.py`，再跑 `discriminate.py` ——
後者的 CRC／非法指令實驗就是用來釘死「壞的是哪個方向」的關鍵。

## 把接收緩衝區左移 2 bit，讀取路徑就全通了

概念和驅動裡既有的 `is_rk3288` 1-bit `morse_shift_buffer()` 補償相同，只是方向
相反。`patches/` 加入了 `spi_rx_lshift=N` 模組參數。設 `spi_rx_lshift=2` 之後：

```
morse_spi spi0.0: Morse Micro SPI device found, chip ID=0x0306
morse_spi spi0.0: Loaded firmware from morse/mm6108.bin, size 468304, crc32 0xbe7b5c8f
morse_spi spi0.0: Loaded BCF from morse/bcf_fgh100mhaamd.bin, size 1251, crc32 0x941b2a82
morse_spi_find_data_ack failed
morse_spi_cmd53_write failed
morse_spi spi0.0: spi: cmd53_write fn=1 0x00004050:4 r=0x10050002 b=0xffffffff (ret:-71)
```

`0x0306` 解出來是 `MORSE_DEVICE_ID(0x6, rev 3, silicon)` = MM6108A1，是驅動表上
的合法版本 —— 證明重新對齊拿到的是真實暫存器資料，不是雜訊。

## 卡在哪裡

CMD53 寫入會拿到正確的 `R1 = 0x00`，然後**完全等不到 data response token** ——
把 ACK 視窗開到 71 個位元組，全部是 `0xff`。

已排除：SPI 時脈 400 kHz 到 50 MHz、SPI mode 0–3、送出方向的雙向位移、
`spi_post_write_status_bytes` 4 到 64、加長 R1 到 token 的間隔、
`enable_ext_xtal_init`、插槽真正斷電重來，以及兩個世代的驅動。
完整紀錄見 [NOTES.zh-TW.md](NOTES.zh-TW.md)。

## 不管這個 bug 如何，這幾件事都值得知道

**`morse_hw_reset()` 是靠「浮接」腳位來釋放 RESET_N 的**，仰賴外部上拉。而
BCM2711 的 GPIO17 預設是**下拉**，所以模組會一直被壓在重置狀態，SPI 讀回全 0。
這非常容易被誤判成模組壞掉。本倉庫的 overlay 都有把該腳位設成上拉。

**驅動 1.17.9 只要改一行就能在原廠 6.18 核心上編譯。** mainline 6.18 又改了
S1G 的定義，所以 `dot11ah/s1g_ieee80211.h` 需要 2.0.1 才加上的那個守衛：

```c
#if KERNEL_VERSION(5, 10, 11) > MAC80211_VERSION_CODE || \
	KERNEL_VERSION(6, 18, 0) <= MAC80211_VERSION_CODE
```

**`spi.c` 在 mainline 核心上編不過。** `SPI_CONTROLLER_ENABLE_CS_GPIOD` 是廠商
核心才有的巨集，而 `ccflags-y` 帶了 `-Werror`，所以 `#else` 分支裡那個
`#warning` 會直接變成致命錯誤。另外 mainline 會對所有 `cs-gpios` 裝置強制開啟
`SPI_CS_HIGH`，這表示 `morse_spi_initsequence()` 那段「先設起再清掉」的操作，
會讓匯流排事後帶著**反相的晶片選擇訊號**。兩者都在 `patches/` 裡處理了。

**法規：** 驅動沒有 `TW` 區域，但 `SG` 是 920–925 MHz / 4 MHz / 22 dBm，與台灣
NCC 的開放頻段完全吻合。

## OpenMANET 有一份正好就是這套佈線的映像

[OpenMANET](https://github.com/OpenMANET/firmware/releases) 發佈的
`openmanet-<版本>-rpi4-mm6108-spi-squashfs-sysupgrade.img.gz`，其 device tree
用的是 WM1302 HAT 的腳位，不是 EKH01 那套：

```
reset-gpios   = <&gpio 17 0>      morse_reset { 腳位 17, 輸入, 上拉 }
spi-irq-gpios = <&gpio  5 0>      morse_irq   { 腳位  5, 輸入, 上拉 }
power-gpios   = <&gpio 23 0>, <&gpio 24 0>
cs-gpios      = <&gpio  8 1>      spi-max-frequency = 50 MHz
```

注意 `morse_reset` 設成**上拉** —— 這獨立驗證了前面講的 RESET_N 浮接問題。

1.8.0（2026-08-16）是 OpenWrt 24.10、核心 **6.6.138**，內附的 morse 驅動是
**`0-rel_mm6108_2_0_1_2026_Jun_11`** —— 與本倉庫編譯的是同一個 release ——
`mm6108.bin` 與 `bcf_fgh100mhaamd.bin` 也和這裡用的完全相同。

這讓它成為一個乾淨的**單變數實驗**：驅動相同、韌體相同、腳位相同，唯一改變的
是核心，連帶改變 `spi-bcm2835` 的世代 —— 那邊是 6.6.138，這裡是 6.18.34。
如果 2-bit 偏移在那上面依然存在，就代表偏移不是 SPI 控制器驅動造成的。

若載板是用 GPIO 控制插槽電源（SenseCAP M1 用 GPIO18），那一行仍然要自己補，
上游沒有任何 overlay 會處理它：

```
gpio=18=op,dh
```

## 其他預建映像必須換掉 overlay

預建映像（Seeed 官方版，以及 beyondlogic 較新的 2.11.13 版）內附的
`mm610x-spi.dtbo` 是給 Morse 自家 EKH01 板用的 —— RESET 在 gpio5、SPI_INT 在
gpio25 —— 和 WM1302 HAT 的腳位定義不同。在 HAT 佈線的載板上，驅動會把模組的
中斷輸出當成重置腳去驅動，並在一支沒接線的腳位上等中斷。`overlays/openwrt/`
提供修正過的 overlay，以及一支可以直接套用到剛燒好的開機分割區的腳本。

儘管板名叫 EKH01，那些映像確實是 Raspberry Pi 4 的建置：
`DISTRIB_TARGET='bcm27xx/bcm2711'`、`DISTRIB_ARCH='aarch64_cortex-a72'`，開機
分割區裡也有 `bcm2711-rpi-4-b.dtb`。`ekh01` 這個字串只出現在 OpenWrt 各板
LED 與網路設定的 `case` 清單裡，而且與 `raspberrypi,*` 並列。

## 實機測試

[TESTING.zh-TW.md](TESTING.zh-TW.md) 是一份自足的操作流程：換上 OpenMANET 卡、
判讀結果。寫成可以在手機上照著做，因為測試進行時，存放這些筆記的機器是關著的。

## 目錄結構

```
NOTES.zh-TW.md                    完整移植紀錄，每個假設與結果
issue9-reply.md                   貼到 morse_driver issue #9 的技術回覆
patches/                          針對 morse_driver mm6108-2.0.1 的 spi.c patch
overlays/mm610x-spi-sensecap.dts  Raspberry Pi OS 用的 device tree overlay
overlays/openwrt/                 修正過的 overlay + 開機分割區套用腳本
tools/                            量測用的使用者空間 SPI 探測工具
```

## 授權

patch 衍生自 MorseMicro/morse_driver，沿用其授權。其餘內容以相同條款發佈，
以便能無阻礙地回饋上游。
