# 實驗室硬體清單與驗證矩陣

*[English](HARDWARE.md)*

2026-08-29 對照 repo 證據重新檢視。每一列都註明量測出處。沒有量過的一律寫
**TBD**，不填看起來合理的值。

## 範圍：這個實驗室裡的東西全部走 SPI

**目前實驗室沒有任何 SDIO 的 HaLow 平台。** 範圍內的 MM6108 矽晶全部掛在 SPI 上，
走 `spi-bcm2835`，裝置名稱是 `spi0.0`，device tree 節點是
`compatible = "morse,mm610x-spi"`。

所以這個實驗室要回答的工程問題**不是匯流排之爭**，而是：

> 兩種不同的 MM6108 **SPI** 實作，在不同的載板、GPIO 對應、device tree、
> 校正／BCF、晶片版本與復原架構之下，行為有何差異？

repo 裡有三處提到 SDIO，沒有一處是現行的 HaLow 平台，而且各自在自己的脈絡下都正確：

- **Raspberry Pi 自己的** 2.4/5 GHz `brcmfmac` 無線電走 SDIO（`fe300000.mmc`）。
  那不是 HaLow，跟 Morse 晶片毫無關係。
- **HT-H7608** 是一台 MIPS OpenWrt 機器，它的 Morse 無線電**確實**走 SDIO
  （`platform/10130000.mmc/mmc_host/mmc0/…`，見 NOTES.md「Hardware and OS,
  confirmed live」）。**本矩陣將它排除。** 它是錯的區域機種
  （`Region: 863~870MHz`），已於 2026-08-26 恢復原廠設定並移出檯面。
- TESTING.md 裡的 `rmmod mm6108_sdio` 是面對來路不明的原廠映像時的防禦性指令，
  不是對本實驗室的描述。

會讓人以為這個實驗室同時有兩種匯流排，最可能的來源就是 H7608——因為它跟 HT-HC01P
**用的是同一顆 HT-HC01 V2 模組、同一份 BCF**，一個走 SDIO、一個走 SPI。那是關於
Heltec 兩款產品的事實，不是關於現在檯面上有什麼的事實。

除非真的有一台 SDIO 機器進入實驗室，否則不要在這個檔案裡加 SDIO 那一列。

## 清單：範圍內的五個節點

| # | 節點 | 模組 | 版本 | 匯流排 | 角色 | 狀態 |
|---|---|---|---|---|---|---|
| 1 | SenseCAP M1（`57:E7`） | Seeed Wio-WM6108 / FGH100M-H | MM6108**A1** | SPI | 本網段的 AP／閘道 | 服役中——**請勿干擾** |
| 2 | SenseCAP M1（`55:04`） | Seeed Wio-WM6108 / FGH100M-H | MM6108**A1** | SPI | 長時間運行的參考／soak 站台 | 服役中——**請勿干擾** |
| 3 | SenseCAP M1——新增 #1 | Seeed Wio-WM6108 / FGH100M-H | MM6108**A1** | SPI | 可重現性／全新安裝驗證 | **待安裝全新 OS** |
| 4 | SenseCAP M1——新增 #2 | Seeed Wio-WM6108 / FGH100M-H | MM6108**A1** | SPI | console server 原型 | **待安裝全新 OS** |
| 5 | RAK Hotspot v2（改裝） | Heltec **HT-HC01P** | MM6108**A2** | SPI | 第二個 SPI 平台；DKMS／核心迴歸；破壞性復原測試 | 服役中 |

節點 3 與 4 的硬體配置與節點 2 相同。它們的 hostname 與 MAC 位址是 **TBD**——
還沒有安裝任何東西，在板子自己報出來之前，這裡不記錄任何值。

節點 5 在較早的筆記裡有兩個名字：`dkmstest` 與 `hc01p` 是同一台 RAK 機殼，
上面裝著 Heltec 的 HAT 與模組。

## 從其他網段連進這些節點

這個實驗室在三種位址族上回應，而每一種由不同的東西決定能不能通。這件事重要，是因
為「連不到節點」在這裡出現過三種完全不同的成因，而分辨它們的方式是看**失敗的形
狀**，不是看有沒有失敗。

| 節點 | 位址 | 從 `192.168.108.0/24` 以外連入時，由什麼決定 |
|---|---|---|
| 1——AP | `192.168.108.5` | 它自己的 OpenWrt 防火牆：`wan` zone `input REJECT`，加上一條**不限來源**的 `Allow-Ping`——所以 ICMP 一直都能從任何有路由的地方通，而 TCP 一直都被拒絕 |
| 1——AP 的 HaLow 側 | `10.41.254.1` | 只在 `br-lan` 上；從家用 LAN 連不到 |
| 2——station | `10.41.0.208` | **唯一的入口。**`wlan0` 是 dormant、`eth0` 是 down，這台在家用網段上根本沒有位址。流量由 AP 的 `wan → lan` 規則轉發 |
| 5——dkmstest | `192.168.108.13`（wlan0）與 `10.41.0.216`（HaLow） | 節點本身沒有防火牆；能不能通取決於**回程路由**，見下 |

**Reject 和 timeout 的意義不同。** 從 `192.168.108.5` 收到 TCP RST，是 AP 的 `wan`
zone 正常運作，表示你站在自己路由器的 WAN 面；完全 timeout 表示你根本沒有路徑。兩者
都不代表節點掛了。

**真正的陷阱是回程路徑，不是防火牆。** 兩台 Pi 的預設路由都走 HaLow
（`default via 10.41.254.1 dev wlan1`，metric 100）。因此一台在家用網段上回應的節
點，會把回覆從 AP 送出去，而 AP 在 `eth0` 上做 masquerade——用戶端對
`192.168.108.13` 開的連線卻收到來自 `192.168.108.5` 的回覆，於是丟棄。症狀是：一台
開著、沒有防火牆、卻完全沉默的節點。station 不受影響，因為它沒有家用網段介面，而它
的閘道**就是** AP。

修法是在任何會在家用網段上回應的節點，為每個管理網段加一條靜態路由。節點 5 把它們
放在 `sun`（wlan0）這個 NetworkManager profile 上。

### 2026-09-02 開放的管理網段

`192.168.200.0/24` 與 `192.168.101.0/24`，僅限 ping 與 SSH。AP 上三條 uci 規則，備份
在 `/etc/config/firewall.bak-20260902`：

| 規則 | zone | 效果 |
|---|---|---|
| `Allow-SSH-mgmt-subnets` | `wan` input | TCP 22 連到 AP 自己 |
| `Allow-mgmt-subnets-ping-halow` | `wan → lan` | ICMP echo-request 進入 `10.41.0.0/16` |
| `Allow-mgmt-subnets-ssh-halow` | `wan → lan` | TCP 22 進入 `10.41.0.0/16` |

以及節點 5 上兩條靜態路由，即時生效並已持久化：
`192.168.200.0/24` 與 `192.168.101.0/24` `via 192.168.108.1 dev wlan0`。

原有的 `192.168.108.0/24` 規則未更動。注意這裡的不對稱：家用網段有一條
`Allow-house-to-halow` 是 `proto all`，而這兩個新網段只開放 ICMP echo 與 TCP 22——其
他一律丟棄，`iperf` 也包含在內。

**已驗證：規則存在。未驗證：有沒有任何東西能用到它們。** 這些規則是從一台位在
`192.168.108.202` 的筆電裝上去的，所以沒有任何封包比對到它們，三個 counter 全是 0。
仍然未知的部分在上游、在 UniFi 上，不在這裡的任何節點上：那兩個網段有沒有到
`192.168.108.0/24` 的路由、house-wide 那條 `10.41.0.0/16 → 192.168.108.5` 靜態路由是
否涵蓋它們、以及 VLAN 間的政策是否允許。檢查方式是在有人從那兩個網段嘗試時，於 AP
上執行：

```
nft list ruleset | grep mgmt-subnets
```

counter 離開 0，表示封包已經抵達 AP，剩下的問題不在這裡；counter 停在 0，表示它從來
沒有到達。

## Wio-WM6108 對 HT-HC01P：兩種 SPI 實作

第一欄以節點 2（soak 站台）為準，第二欄以節點 5 為準。

| | **Seeed Wio-WM6108 / FGH100M-H** | **Heltec HT-HC01P** |
|---|---|---|
| 模組／供應商 | Seeed Wio-WM6108（FGH100M-H），mini-PCIe 形式 | Heltec HT-HC01P，HT-HC01 V2 模組裝在 Heltec Pi HAT 上 |
| MM6108 版本 | **A1**——chip ID `0x0306` | **A2**——chip ID `0x0406` |
| SPI 主控介面 | `spi-bcm2835`、`spi0.0`、BCM2711 | 完全相同：`spi-bcm2835`、`spi0.0`、BCM2711 |
| 載板／主機平台 | Pi 4B rev 1.4 上的 SenseCAP M1 mPCIe 插槽，依 Seeed WM1302 Pi HAT 腳位對應 | RAK Hotspot v2 機殼、Pi 4B、Heltec Pi HAT |
| 驗證時使用的 SPI 時脈 | **50 MHz**——實機 DT 讀出 `02 fa f0 80` | **50 MHz**——overlay `spi-max-frequency = <50000000>` |
| Device tree／overlay | `overlays/mm610x-spi-sensecap.dts`，以 `dtoverlay=mm610x-spi-sensecap` 載入 | `overlays/mm610x-spi-hc01p.dts`——Heltec 的 `mm610x-spi.dtbo` + `morse-ps.dtbo` 合併，並改寫成原廠核心可用的形式 |
| DT 節點名稱 | `mm610x@0` | `mm6108@0` |
| Chip select 處理 | **兩個 chip select**——GPIO 8（`spi0 CS0`）與 GPIO 7（`spi0 CS1`），來自 `dtparam=spi=on`，在這片板子上無害 | **收斂成一個**——`cs-gpios = <&gpio 8 1>`，`spi0_cs_pins` 縮成 `<8>`，因為**這片 HAT 的 GPIO 7 是 MM_BUSY**；沿用原廠的 `<8 7>` 群組會把 power-save 交握線 mux 掉 |
| RESET_N | **GPIO 17**，低態有效，`reset-gpios = <&gpio 17 1>`。overlay 必須強制**上拉**：`morse_hw_reset()` 釋放時是讓線浮接而不是驅動為高，而 BCM2711 的 GPIO 9–27 預設下拉，會讓無線電永遠停在 reset | **GPIO 5**，`reset-gpios = <&gpio 5 0>`，停在**浮接輸入、不加 bias**——上拉由 HAT 自己提供，逐位元組比對可運作的 OpenWrt 板 |
| IRQ | **GPIO 5**——實機 consumer 為 `mm610x_spi_irq_gpio` | **GPIO 25**，level-low——實機 IRQ 55 `Morse SPI IRQ`，`pinctrl-bcm2835 25 Level` |
| WAKE／BUSY | **GPIO 23／GPIO 24**——`morse-wakeup-ctrl` 與 `morse-async-wakeup-ctrl` | **GPIO 3／GPIO 7**——`power-gpios = <&gpio 3 0>, <&gpio 7 0>`；不是電源軌 |
| 其他載板腳位 | **GPIO 18** `halow-slot-power`，M1 自己的 mPCIe 插槽電源致能，以 hog 拉高，並由 `gpio=18=op,dh` 再強制一次 | **GPIO 4** JTAG reset，以 hog 驅動為低（Heltec 的 `morse-ps.dtbo`） |
| BCF | `morse/bcf_fgh100mhaamd.bin`——1251 B，md5 `4e128ad574304d1aec778c5ba5611f8f`，crc32 `0x941b2a82` | `morse/bcf_HC01_V2_H.bin`——1170 B，crc32 `0x389a48c4`。**原廠映像用錯了檔案**：`bcf_mf08551.bin` 是 Morse EKH01-03 評估板的 BCF，在 2026-08-24 換掉之前，它讓這顆模組的發射器形同失效 |
| 韌體 | `morse/mm6108.bin`，468304 B，crc32 `0xbe7b5c8f` | **逐位元組相同**：`morse/mm6108.bin`，468304 B，crc32 `0xbe7b5c8f` |
| MAC 供給行為 | **不需任何參數就保有自己的位址。** `options morse country=SG bcf=bcf_fgh100mhaamd.bin`，`wlan1` 穩定為 `9c:04:b6:ff:df:fe` | **必須有 `macaddr_suffix=40:8e:91`。** 沒有它，驅動每次載入都會**隨機**產生一個 MAC（第一次探測出現的是 `c2:d2:3d:87:dd:cd`），會把 AP 的 station 表和 DHCP 租約每次開機都攪動一次 |
| 已驗證的核心版本 | **`6.6.51+rpt-rpi-v8`**（RPi OS Lite bookworm）。`6.12.93` 與 `6.18.34` 是在修正系列**之前**跑的，失敗指紋相同——那是缺陷重現，不是驗證。**A1 在 `6.12.96` 上未測試：TBD** | **`6.6.51+rpt-rpi-v8` 與 `6.12.96+rpt-rpi-v8`**，同一片板子、同一份 DT、同一份韌體、同一份 BCF，只換核心 |
| 最長不中斷關聯 | **123 小時 23 分**（5 天 3 小時 23 分），2026-08-27 18:03:59 → 2026-09-01 21:27:00，結束於一次只有本站看得到的 beacon loss，12 秒後恢復。前一個紀錄是 28 小時 34 分 | **6 天 20 小時 28 分且仍在持續**（2026-09-02）——整份 journal 只有一次 `CTRL-EVENT-CONNECTED`，完全沒有 `DISCONNECTED`，跑在 6.12.96 上由 DKMS 安裝的模組。這是兩片板子產生過最長的關聯 |
| 本地復原路徑 | USB-C gadget（NCM + ACM），走 **Pi 自己的** USB-C，`192.168.45.0/24`。M1 面板上的 USB-C 只有 HAT 的 **5 V**，沒有 D+/D−。家用 Wi-Fi `wlan0` 存在但狀態是 **`disconnected`**，`192.168.108.19` 在 2026-08-28、2026-08-29 與 2026-09-02 都沒有回應——它曾經關聯上的時候是 −86 dBm，慢到無法承載一次 checkpoint。**HaLow 是唯一的遠端路徑。**`eth0-bench` profile 存在，但**沒有文件、無法重現：TBD** | USB-C gadget 走 `192.168.44.0/24`，目前以線接在 MacBook 上，**另外還有真正的 USB 序列 console**（Mac 上的 `/dev/cu.usbmodem*`）。也可以從家用 Wi-Fi 與 HaLow 進入 |
| 在實驗室中的角色 | 節點 1 是 AP；節點 2 是長期可靠度參考，也是承載 soak 儀器的板子。它已不再是可靠度證據的唯一來源——自 2026-09-02 起，較長的關聯紀錄在節點 5 手上 | 第二個 SPI 平台：DKMS 與核心迴歸的測試床，也是破壞性復原測試預定執行的板子 |

## 同一個晶片家族、同一條 SPI 匯流排，不代表兩者等價

上表兩欄都是 MM6108 矽晶、都跑在 `spi-bcm2835` 的 50 MHz 上，而它們**不可互換**。
真實、量測過、而且會影響結果的差異：

- **載板設計**——Seeed HAT 上的 mPCIe 插槽，對上 Heltec Pi HAT。
- **GPIO 對應**——每一條控制線都不同。reset 17 對 5、IRQ 5 對 25、wake 23 對 3、
  busy 24 對 7。兩份 overlay 只有 SPI 那四條是共通的。
- **reset 的電氣行為**——同一段驅動程式碼（釋放時浮接），在一片板子上需要**強制
  上拉**，在另一片上則要**完全不加 bias**，因為上拉一個來自 SoC、一個來自 HAT。
- **chip select 處理**——兩個 chip select 在 M1 上無害，在 Heltec HAT 上具破壞性，
  因為第二個會落在 MM_BUSY 上。
- **device tree 整合**——Heltec 把腳位停放掛在 `&leds` 底下；本 repo 的版本掛在
  `spi0` 自己的 `pinctrl-0`，這樣就不必依賴一個不相干的節點被 probe。
- **板級校正／BCF**——不同檔案、不同大小、不同 CRC，而且其中一片出貨時指向的是
  評估板的 BCF。
- **晶片版本 A1 對 A2**——`0x0306` 對 `0x0406`。SPI probe 路徑會在讀到真正的 ID
  **之前**先呼叫 `morse_chip_cfg_init(mors, MM6108A2_ID)`。
- **MAC 供給**——一個保有自己的位址，一個若不特別指定就每次載入隨機產生。
- **開機與復原行為**——一台有序列 console 和一台筆電接著；另一台唯一的遠端路徑
  就是受測的那條無線電鏈路。

兩者之間還有一個持久的**行為**差異，重複量測過而且仍未解釋：在同一台 AP、同一分鐘
之內，A1 站台每個封包要付 **1.17–1.64 次 retry**，A2 板子付 **0.00**。

## 驗證矩陣

| | 6.6.51 | 6.12.96 | 6.12.93 | 6.18.34 |
|---|---|---|---|---|
| **A1——Wio-WM6108 / SenseCAP M1** | ✅ 服役中，soak 進行中 | **TBD——未測試** | ❌ 修正前的缺陷重現 | ❌ 修正前的缺陷重現 |
| **A2——HT-HC01P / RAK** | ✅ 已驗證 | ✅ 已驗證 | — | — |

**A1 / 6.12.96** 這一格是本矩陣的空洞。節點 2 只裝了 6.6.51 的核心，所以要補上它
需要一片不是 soak 節點的板子——那正是節點 3 存在的理由。

## TBD

| 欄位 | 節點 | 為何仍開著 |
|---|---|---|
| hostname | 3、4 | 尚未安裝 |
| HaLow MAC | 3、4 | 尚未安裝 |
| eth0 MAC | 3、4 | 未從板子上記錄 |
| 序號 | 3、4 | 未從板子上記錄 |
| A1 在 6.12.96 | 2、3 | 從未跑過；節點 2 只有 6.6.51 的核心 |
| 乙太網路救援程序 | 2、5 | 能力是真的，程序沒有寫下來 |
| HAT 按鈕／風扇／LED 腳位 | 1–4 | 軟體上未宣告；需要一片不是 soak 節點的板子 |
| 從 `192.168.200.0/24` 與 `192.168.101.0/24` 的可達性 | 1、2、5 | 規則與路由已於 2026-09-02 安裝，並在實際 ruleset 中確認存在；但從未從那兩個網段實際使用過，三個 counter 仍是 0，且那些 VLAN 的上游 UniFi 路由狀態未知 |
| ATECC608A 加密晶片 | 1–4 | header I²C 是關的；掃描它的代價是一次重開機 |

未宣告不等於不存在。上面每一個 TBD 說的都是「還沒**量過**」，不是「硬體不在」。

## 證據

| 主張 | 出處 |
|---|---|
| WM6108 走 SPI | `overlays/mm610x-spi-sensecap.dts`（`morse,mm610x-spi`、`spi0`、`spi-max-frequency`）；站台 `config.txt` 的 `dtoverlay=mm610x-spi-sensecap`；實機 DT `spi-max-frequency` = `02 fa f0 80`；實機 `/sys/kernel/debug/gpio` 顯示 `spi0 CS0/CS1`、`mm610x_spi_irq_gpio`、`halow-slot-power`、`morse-wakeup-ctrl` |
| HC01P 走 SPI | `overlays/mm610x-spi-hc01p.dts`；`logs/2026-08-25-hc01p-rpios-stage3b-driver-up.txt`——`morse_spi spi0.0`、GPIO 25 上的 `Morse SPI IRQ`、`/sys/class/spi_master/spi0` 計數器；`heltec-hc01p-hardware-inventory.md` §3 |
| A1 chip ID `0x0306` | `README.md`「Hardware」；`heltec-hc01p-linux-port-analysis.md`（`MM6108A1_ID … 0x306`） |
| A2 chip ID `0x0406` | `logs/2026-08-25-hc01p-rpios-stage3b-driver-up.txt`；`heltec-hc01p-hardware-inventory.md`（`morse_cli hw_version: "MM6108A2"`） |
| 兩者都是 50 MHz | 站台實機 DT 讀值；`overlays/mm610x-spi-hc01p.dts`；`logs/2026-08-24-spi-clock-is-the-throughput-ceiling.txt` |
| BCF／韌體位元組 | `logs/2026-08-25-hc01p-rpios-stage3b-driver-up.txt`；NOTES.md「The two boards, side by side」；`firmware/heltec-hc01p/` |
| MAC 供給行為 | `heltec-hc01p-linux-port-analysis.md` §Stage 4；站台實機 `modprobe.d/morse.conf` |
| A2 跑過兩個核心 | `logs/2026-08-25-hc01p-rpios-kernel-6.12-second-kernel.txt`；`port/hc01p/README.md` |
| H7608 是唯一的 SDIO Morse 裝置，且已移出檯面 | NOTES.md 2026-08-24（`radio1 morse … SDIO`）與 2026-08-26（錯的區域機種、恢復原廠設定） |
