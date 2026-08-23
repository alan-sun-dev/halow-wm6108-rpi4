# Wio-WM6108（MM6108A1）在 SenseCAP M1 上的移植狀態，2026-08-19

*[English](NOTES.md)*

## 2026-08-23 傍晚 —— 第三塊板子、一個 MTU 黑洞，以及廠商文件說了什麼

四個結果。完整證據在
[`logs/2026-08-23-mtu-blackhole-third-implementation-and-vendor-docs.txt`](logs/2026-08-23-mtu-blackhole-third-implementation-and-vendor-docs.txt)。

**藏住缺陷的是那份參考設定。** 第三塊 SPI 板子加入了（Heltec HT-HC01P 接 RPi 4，
驅動 1.15.3），而且第一次讀了 Morse 官方的 Linux 移植指南。它的 EKH01 參考 overlay
寫的是 `spi-max-frequency = <50000000>` 和 `reset-gpios = <&gpio 5 0>` —— 50 MHz
加 flag 0。**所有檢視過的實作都從官方參考繼承了這兩個設定**，而它們正好讓缺陷 3
（壞掉的延遲換算只有在 50 MHz 才會算出可用值）和缺陷 2（flag 0 讓 RESET_N 從不觸發）
都看不見。同一份文件裡，chip select、deassert、74 個 clock、初始化序列、交易間延遲、
CMD53/CMD63、疑難排解 —— 出現次數全部是 **0**，而且是帶正對照統計的。完整表格見下面
「五個實作、一份參考設定」。

**一個靜默的 MTU 黑洞一直在殺掉大量上行**，而且很可能一直在扭曲本檔案裡的每一個吞吐量
數字。AP 的 `wlh0` 是 MTU 1500，橋接夥伴 `eth0` 卻是 1460，所以從 HaLow 側來的超尺寸
訊框被橋接器丟掉，沒有 ICMP、沒有計數器。上行 8 KiB **34.7 秒回傳 0 位元組**；一個
`ip link set wlan1 mtu 1460` 讓它變成 **0.32 秒**。**源頭是 `openmanetd`** —— 用「停用
三個候選 daemon、重開機得到 1500、再一個一個啟動回來」的方式確認。停用它之後整條路徑
都是 1500，而且 AP 一切正常。它很可能就是本檔案裡記為未解釋的「上行速率變動 4 倍」和
「4194304 中截斷在 155648」的成因 —— 指向，但未確立。下面有專節。

**上一層樓的距離與吞吐量。** −41.3 dBm（30 取樣）、60/60 ping 0% 遺失、**下行
2.77 Mbit/s、上行 1.48 Mbit/s**，2 MHz。負載下速率控制器停在 2 MHz **MCS7**、成功率
90.5%，那是這個頻寬能給的最高一檔 —— 所以限制是**頻寬**，不是鏈路品質，而 `SG`
regdomain 允許到 4 MHz。第三方數據顯示 4 MHz 是 2 MHz 的 2.3 倍。上一層樓時家裡的
Wi-Fi 搆不到而 HaLow 搆得到，於是頻外通道反過來扛起了它自己正在被量測的那條鏈路的
管理流量。

**一個跨版本的安全解析差異。** 1.15.3 的 station 看不見這台 AP 的 RSN 元素，因此拒絕
嘗試 SAE —— 它把 AP 讀成 `[WEP]` 然後停在 `SCANNING`。2.0.1 在同一台 AP、同一時刻看到
的是 `Authentication suites: SAE`。AP 的 `rsn_beacon_mode` 預設是
`RSN_BEACON_DISABLED`；設成 `2` 就會把 RSN IE 放進 beacon。但光是這樣還沒讓那台
1.15.3 關聯上，原因仍未解決。

## 2026-08-23 稍晚 —— RSSI 那題有答案了，AP 停擺也有軟體解法

兩個結果，都是同一個下午量出來的。完整方法、原始取樣、以及過程中踩到的工具陷阱在
[`logs/2026-08-23-rssi-range-test-and-ap-stall-recovery.txt`](logs/2026-08-23-rssi-range-test-and-ap-stall-recovery.txt)。

**`signal: 0 dBm` 就是飽和 —— 用搬動板子證實的，不是論證出來的。** station 被搬到三個
距離，每個位置取樣 30 次、共 60 秒，而且每次搬動之前先把預測值寫下來。2 m 無遮蔽那點
與自由空間預測只差 **0.1 dB**（實測 −15.7，預測 −15.8）；0.3 m 的桌面那點是削頂的，而
削頂顯示在級距上（16.5 dB 的真實路徑損耗只讓讀值走了 11.7 dB）。附帶產物：室內**木牆
在 923 MHz 衰減 8 dB**，兩種獨立算法一致到 0.1 dB。細節見下面「判讀鏈路」。

**AP 發射器停擺可以不用重開機救回來。** `wifi reload` ✗ → debugfs `restart` ✗ →
debugfs **`reset` ✓**。前兩次之後記在這裡的「只有重開機救得回來」是錯的。完整重載韌體
（`restart`）不夠，要走 bus reset。可能的原因是這台 AP 的 `reset-gpios` flag 是 0，
RESET_N 從來不會觸發，只有 bus reset 那條路徑碰得到晶片。第三次跟第二次一樣，前面什麼
都沒發生。細節見下面「AP 的發射器會停擺」。

**兩個值得帶著走的診斷更正。** Heltec 的 *ping* 不能當對照組 —— 鏈路健康時它也是不通
的；只有它的 RSSI 讀值和關聯事件可以。還有 station 的**省電預設是開的**，這會讓停擺
看起來像連 beacon 都停了（其實沒有）；任何量測都要先把它關掉。

**兩塊板子現在在哪裡。** 家裡多了第二個 SSID `Sun` / `192.168.108.0/24`，而它和舊的
`Unifi` / `192.168.200.0/24` **兩個都在廣播** —— 遷移進行中，還沒完成。station `55:04`
在 `Sun` 上、位於 **`192.168.108.19`**（它的 `sun` NetworkManager profile 的
autoconnect-priority 已調到 20，高於 `preconfigured` 的 10，後者保留當退路）。AP 不變，
仍在 `10.41.254.1`。筆電可以用金鑰認證**直接**連到 station 的 HaLow 位址
`10.41.0.208` —— 為什麼這比先前記的做法簡單，見下面「HaLow 鏈路是頻外管理通道」。

為了搬移測試，station 上裝了一支暫時的記錄器 —— `halow-rssilog.service`，開機自動啟動，
寫到 `/home/alan/rssi-logs/`，並且每 60 秒重新確保 `power_save off`。搬移測試做完之後
記得移除，指令在上面那個 log 檔的最後。

## 2026-08-23 收尾 —— 目前留下的狀態

工作已完成並送出上游。三個缺陷全在驅動的 `spi.c`：`-Werror` 下編不過的 `#warning`、
初始化訓練 clock 在 CS 被選取的狀態下送出、以及交易間延遲被按時脈換算（但晶片是數
clock 數的）。乾淨的 series 是 `patches/upstream/000{1,2,3}-*.patch`，對著 tag
`mm6108-2.0.1`，在硬體上以「不帶模組參數」驗證過，已送出為
[morse_driver#16](https://github.com/MorseMicro/morse_driver/pull/16)。
`patches/morse-driver-2.0.1-rpi-spi.patch` 仍是調查用的工作檔（儀器與實驗參數），
不要拿它給任何人。

**這個 series 已在 repo 的原廠 overlay 下驗證過** —— RESET_N 真的會觸發、兩組 chip
select、除了 `country=` 與 `bcf=` 之外不帶任何模組參數，並且是在冷開機、由核心自動
載入的情況下確認的。完整紀錄在
[`logs/2026-08-23-stock-overlay-clean-series-environment.txt`](logs/2026-08-23-stock-overlay-clean-series-environment.txt)。
同一輪也在相同的 device tree 下載入未修正的建置，重現了原始失敗 —— `c0 7f`、CMD63
`-71` —— 所以這個 A/B 固定了 device tree，只變動驅動 binary。

**板子 `E4:5F:01:52:55:04` 現在是乾淨且可運作的狀態。** 寫下這段時它在
`192.168.200.182`；當天稍晚的那一輪之後，它已經在 SSID `Sun` 上、位於
`192.168.108.19` —— 見本檔案最上面那節。其餘狀態：

- `~/halow-test/morse_driver` 是 tag `mm6108-2.0.1` 加上 `patches/upstream/`，沒有
  別的（`git diff --stat` 只動 `spi.c`，62 行新增、8 行刪除）
- 已裝回原廠 overlay；實驗版以 `mm610x-spi-sensecap.dtbo.experiment` 保留在旁邊，
  最初的原始備份仍是 `.orig`
- `config.txt` 保留 `gpio=18=op,dh`，README 與 TESTING 都要求這一行
- 乾淨建置已安裝到
  `/lib/modules/6.6.51+rpt-rpi-v8/updates/{morse.ko.xz,dot11ah/dot11ah.ko.xz}`，
  與建置產物逐位元相同；2026-08-22 的舊版以 `*.stale-20260822` 保留
- `/etc/modprobe.d/morse.conf` 寫入 `options morse country=SG
  bcf=bcf_fgh100mhaamd.bin`，讓自動載入帶著正確的 regdomain，而不是漏掉它
- 原本在樹裡的探針儀器存放於
  `~/halow-test/SAVED-probe-tree-20260823-0914.patch` 與
  `~/halow-test/SAVED-morse-probe-build.ko`

**一則更正。** 本節先前的版本寫著載入中的模組「有探針但**沒有** SPI 修正」，依據是
`strings morse.ko | grep -c SPI_NO_CS` 回 0。那個檢查是無效的：`SPI_NO_CS` 是巨集常數，
在整份 patch 裡沒有出現在任何字串常數中，所以修正版同樣會回 0。那個模組其實是有修正的。
同一天的相關失誤：第一次讀 device tree 用了 `xxd`，這個 image 根本沒裝，而錯誤又被同一行
的 `2>/dev/null` 吞掉。**任何回 0 的 `grep -c`，旁邊都需要一個對照組** —— 新紀錄裡的每
一筆讀值都是這樣取的。

**關於順序。**「一旦晶片被以 CS asserted 的狀態定址過就回不來」這句，適用範圍是**沒有
前置 reset** 的訓練 burst。未修正的模組 probe 失敗，並不會讓後續修正版的模組跟著失敗，
因為 probe 會先 reset 再送 burst —— 2026-08-23 實測確認。

連線與資料傳輸已於 2026-08-23 驗證，而且是跨實作的 —— 對端是 Morse 自家 OpenWrt 建置
當 AP：WPA3-SAE 含 PMF、DHCP 透過空中鏈路取得、雙向各 4 MiB 並比對校驗碼、200/200 次
ping 零遺失、累計 88.9 MB 的 SPI 流量且 `errors 0`。見
[`logs/2026-08-23-association-verified-environment.txt`](logs/2026-08-23-association-verified-environment.txt)，
裡面也列出仍然未知的部分 —— 距離、吞吐上限、鏈路餘裕（RSSI 讀值為 0 dBm），以及兩個
未解釋的事件。

## 兩塊板子的對照（2026-08-23）

兩台是相同硬體、跑相同的韌體位元組。所有差異都集中在最後三列，而那三列正是整個
調查在講的事。

| | Station | AP |
|---|---|---|
| **角色** | HaLow 用戶端，修正後的驅動 | HaLow 基地台，Morse 自家建置 |
| 主機 | RPi 4B Rev 1.4（`c03114`），4 GB | RPi 4B Rev 1.4（`c03114`）|
| 載板／模組 | SenseCAP M1 + Wio-WM6108 (MM6108A1) | 同左 |
| 序號 | `100000004851d437` | `1000000093d173dd` |
| eth0 MAC | `e4:5f:01:52:55:04` | `e4:5f:01:52:57:e7` |
| HaLow 網卡 | `wlan1`，`9c:04:b6:ff:df:fe` | `wlh0`，`3c:1a:cc:70:3f:ca` |
| 作業系統 | Raspberry Pi OS Lite 64-bit，bookworm | OpenMANET 24.10（OpenWrt `r28739-d9340319c6`，`bcm27xx/bcm2711`）|
| 核心 | `6.6.51+rpt-rpi-v8` | `6.6.138` |
| 驅動 | `mm6108-2.0.1`（`98e1936`）+ `patches/upstream/` | Morse 的 OpenWrt 建置，編進核心 |
| 驅動版本字串 | `0-rel_mm6108_2_0_1_2026_Jun_11` | 完全相同 |
| 載入形式 | 核心模組，`srcversion 87374779AA811C291578351` | 內建，`lsmod` 查不到 |
| 參數 | 由 `modprobe.d` 帶 `country=SG bcf=bcf_fgh100mhaamd.bin` | UCI `radio1`，另有 `enable_ext_xtal_init=1`、`enable_ps=0`、`enable_twt=0` |
| Supplicant | 原廠 `wpa_supplicant` 2.10，由 NetworkManager 1.42.4 驅動 | `hostapd_s1g` / `wpa_supplicant_s1g`（Morse 專用建置）|
| `mm6108.bin` | 468304 bytes，md5 `27199922700526947ec1efdaaff8163d` | 逐位元組相同 |
| `bcf_fgh100mhaamd.bin` | 1251 bytes，md5 `4e128ad574304d1aec778c5ba5611f8f` | 逐位元組相同 |
| SPI 控制器 | `brcm,bcm2835-spi`，`spi0.0` | 同左 |
| DT 節點名 | `mm610x@0` | `mm6108@0` |
| 射頻 | managed，`country=SG` | AP，S1G 923.0 MHz / BW 2 MHz，對映 ch157，22 dBm，SSID `BCM2711-57e7`，SAE + PMF，`wds=1` |
| **SPI 時脈** | **10 MHz**（`00 98 96 80`）| **50 MHz**（`02 fa f0 80`）|
| **`reset-gpios`** | pin 17 **flag 1** —— RESET_N 真的會觸發 | pin 17 **flag 0** —— RESET_N 從來不觸發 |
| **chip select 數** | **兩組**（gpio 8、gpio 7），來自 `dtparam=spi=on` | **一組**（gpio 8）|
| 腳位提升／下拉 | `halow_pins`：17 上拉，5/23/24 下拉；沒有 `spi0_pins` 群組，所以 MISO/MOSI/SCLK 維持 BCM2711 預設（下拉）| `morse_reset` 17 上拉、`morse_irq` 5 上拉、`morse_wake` 23 上拉、`morse_busy` 24 下拉；`spi0_pins` 9/10/11 上拉 |

**AP 為什麼從來沒踩到那三個缺陷**，答案就在那幾列裡。50 MHz 是驅動的延遲換算剛好會
產生可用值的唯一時脈，所以缺陷 3 隱形；`reset-gpios` flag 0 讓 RESET_N 永遠不觸發，
晶片不會被踢出 SPI 模式，所以缺陷 2 隱形。Station 是 10 MHz 且 RESET_N 真的會拉，
兩個缺陷都會現形 —— 而 `patches/upstream/` 那組修正就是撐住它的東西。

腳位拉電阻與 chip select 數的差異，在 A/B 過程中都已個別排除為成因（見下方各節）；
列在這裡是因為它們是真實存在的組態差異，不是因為它們和故障有關。

*讀 device-tree 屬性要注意位元組序：DT 是大端。`od -An -tx1` 依序印出原始位元組，
是安全的形式。`hexdump -e '1/4 "%08x "'` 和 `%d` 印的是主機端序，每個字都會反轉 ——
`02 fa f0 80`（50000000）會顯示成 `80f0fa02`。OpenMANET 映像沒有 `od`，兩台都沒有
`xxd`；在相信一個空的讀值之前，先確認工具存在。*

## 五個實作、一份參考設定 —— 而藏住缺陷的正是那份參考

2026-08-23 新增，在第三塊 SPI 板子加入、並且第一次讀了 Morse 官方文件之後。這一節解釋
的是**為什麼別人都沒有回報 `patches/upstream/` 裡的那三個缺陷**。

| | 本 repo 的 station | OpenMANET AP | HT-HC01P | **Morse EKH01 參考** | MMECH06（論壇） |
|---|---|---|---|---|---|
| 驅動 | 2.0.1 + 我們的修正 | 2.0.1 | 1.15.3 | — | 1.16.4 |
| **SPI 時脈** | **10 MHz** | 50 MHz | 50 MHz | **50 MHz** | 50 MHz |
| **`reset-gpios` flag** | **1** | 0 | 0 | **0** | — |
| reset 腳位 | 17 | 17 | 5 | 5 | 5 |
| chip select | 兩個（8、7） | 一個（8） | 一個（8） | 一個（8，flag 1） | 一個（8，flag 1） |

第四欄不是另一家廠商，是 **Morse 自己的官方 Linux 移植指南**（`MM_APPNOTE-24` v2）
第 6.1 節、EKH01 EVK 的參考 overlay，逐字引用：

```dts
mm6108: mm6108@0 {
    compatible = "morse,mm610x-spi";
    reg = <0>;    /* CE0 */
    reset-gpios = <&gpio 5 0>;
    power-gpios = <&gpio 3 0>, <&gpio 7 0>;   /* WAKE, BUSY */
    spi-irq-gpios = <&gpio 25 0>;
    spi-max-frequency = <50000000>;
    status = "okay";
};
cs-gpios = <&gpio 8 1>;
```

所以本 repo 一再在各家廠商身上看到的模式，不是巧合。**大家都是從官方參考繼承來的**，
而那兩個設定正好藏住了三個缺陷中的兩個：50 MHz 是驅動那個壞掉的延遲換算唯一會算出可用
值的時脈（缺陷 3），而 `reset-gpios` flag 0 讓 `gpiod_set_value(reset, 1)` 把腳位拉
**高**，RESET_N 從來不觸發，晶片也就永遠不會被踢出 SPI 模式（缺陷 2）。

同一份文件的屬性表對 `reset-gpios` 只寫「GPIO descriptor connected to the MM6108
RESET line」，**對極性隻字未提**。

### 這份移植指南沒有寫的東西

對全部 22 頁抽出的文字做關鍵字統計，同一次帶正對照（`Morse` 115 次、`SPI` 21 次，
所以搜尋確實在工作）：

| 關鍵字 | 出現次數 |
|---|---|
| chip select / chip-select | **0** |
| deassert | **0** |
| 74 | **0** |
| init sequence / initialisation / training | **0** |
| delay / inter-block / inter-transaction | **0** |
| CMD53 / CMD63 | **0** |
| probe fail / troubleshoot | **0** |

這份指南涵蓋核心修補、編譯驅動、韌體、hostapd 與 wpa_supplicant、四個 device tree
屬性、bring-up 指令、以及 `test_mode` 表格。它**沒有疑難排解章節，也沒有記載任何與那
三個缺陷相關的底層 SPI 行為**。

這對上游很重要。「晶片需要約 74 個 clock 且 chip select 必須**解除**」這個要求，公開
出處只有一篇論壇討論串 —— 就是本 repo 已經引用的那篇 i.MX93。**照著官方文件做移植的
人，不可能知道這件事**，而 released 驅動也沒有正確實作它。

### 一個本 repo 構成反例的廠商說法

出自社群的 "HaLow for Raspberry Pi OS" 討論串，逐字引用：

> "From 1.15.3, patching the kernel is practically required, so sticking as close
> to one of these versions as possible will make integration significantly
> smoother."

它給的理由是 mesh、channel switch announcement 和 SPI 支援，做法是 cherry-pick 一整條
Morse 的核心分支（`morse/mm/rpi-6.12.21/1.16.x`）。

**本 repo 跑在原廠 Raspberry Pi OS 6.6.51、核心未經修補**，驅動是 2.0.1 加上三個
`spi.c` 修正、沒有別的，而它能完成 WPA3-SAE 關聯、跑 DHCP、雙向搬 4 MiB 並校驗、
回報 `errors 0`。這裡從來沒有用過 mesh 和 CSA，所以那個說法沒有被全面推翻 —— 但對
6.6.51 上的 station 而言，核心修補**不是**必要的，而且這是量出來的，不是論證出來的。

那串討論裡**沒有任何人**回報本 repo 追過的失敗特徵（`c0 7f`、CMD63 `-71`、
`SPI_NO_CS`、`spi_inter_block_delay_bytes`）—— 這正是上面那張表所預測的。

### 值得收著的第三方吞吐量數據

同一串（castironclay，約 20 英尺無遮蔽，量測工具未說明）：

| 頻寬 | 吞吐量 |
|---|---|
| 1 MHz | 0.82 Mbps |
| 2 MHz | **3.68 Mbps** |
| 4 MHz | **8.33 Mbps** |
| 8 MHz | 5.16 Mbps —— 他們註明兩台裝置當時「供電略為不足」 |

本 repo 在上一層樓、2 MHz 量到 **2.77 Mbit/s**，同一個量級、略低，合理的解釋是我們的
SPI 跑 10 MHz 而他們跑 50 MHz，以及我們是用 TCP over SSH 量的。他們的 4 MHz 是 2 MHz
的 **2.3 倍**，這是目前最好的證據支持「把這條鏈路改到 4 MHz 大約可以翻倍」。而他們的
8 MHz 比 4 MHz **還慢**，是「頻寬不是越寬越好」的一個警告。

Morse 標稱 MM6108 可達 32.3 Mbps，但那是在 **8 MHz** 下，而這裡的 `SG` regdomain
不允許（`(920 - 925 @ 4)` —— 總共 5 MHz 頻譜、最大 4 MHz），所以那不是對等的數字。
Morse 自家人員在論壇上說 SPI 主機在他們的 EKH01 套件上「up to 21 Mbps with iperf」，
並指出 SPI 吞吐量主要取決於主機側因素。驅動內建匯流排吞吐量分析工具 `test_mode=6`，
可以把匯流排能力和鏈路效能分開量；`test_mode=4` 是晶片重置，`test_mode=5` 做區塊讀寫。

### 第三塊板子本身

Heltec HT-HC01P HAT 接在 Raspberry Pi 4B 上，跑 Heltec 原廠映像：

```
映像    OpenWrt 23.05.5，DISTRIB_DESCRIPTION "23.05.5 2.8.5-20251107"
核心    5.15.167        板子  RPi 4 Model B Rev 1.4，serial 100000004dd92ccc
eth0    e4:5f:01:40:8e:91      HaLow wlan0  0c:bf:74:40:8e:91
驅動    0-rel_1_15_3_2025_Apr_16          bcf  bcf_mf08551.bin
```

**映像名稱裡的 `2.8.5` 是 Heltec 韌體包的版本，不是 Morse 驅動版本。** 驅動是
1.15.3 —— 比本 repo 修補的 2.0.1 **還舊**。特別寫下來是因為那個名字看起來很像驅動
版本，很容易導向完全相反的結論。

安全性注記，因為它出廠就是這樣：那份映像在 `0.0.0.0:7681` 跑 `ttyd` 而且**沒有任何
認證**（`/token` 回 `{"token": ""}`），它和乙太網路孔、Pi 內建的 5 GHz AP 一起橋在
`br-lan` 上，防火牆的 lan zone 是 `input ACCEPT`，而它的 dnsmasq 在 lan 上提供 DHCP
且沒有 `ignore` 旗標。任何在它 Wi-Fi 範圍內、知道原廠密碼的人，都能不需憑證拿到 root
shell。在關掉 DHCP 伺服器、設好 root 密碼、處理掉 ttyd 之前，不要把它的網路孔接到共用
交換器上。

那份映像的工具狀況：`od`、`dtc`、`fdtget`、`wpa_cli` **都沒有**；`hexdump`、`xxd`、
`strings`、`wpa_cli_s1g` 有。相信一個空的讀取結果之前先確認工具存在 —— 上面那份
device tree 就是在 `od` 沒有輸出、正對照顯示原因之後，改用 `hexdump` 讀到的。

### `rsn_beacon_mode`：為什麼 1.15.3 的 station 看不見這台 AP 的安全設定

HT-HC01P 當 OpenMANET AP 的 station 時關聯不上。它掃得到 AP（−52 dBm），卻從來沒有
嘗試認證；AP 的 hostapd 也從來沒記錄過它的 MAC。supplicant 自己的視角道破了原因：

```
bssid              frequency  signal  flags        ssid
3c:1a:cc:70:3f:ca  5785       -51     [WEP][ESS]   BCM2711-57e7
```

`[WEP]` 的意思是 privacy bit 有設，但**解析不到 RSN 元素**。一個要求 `key_mgmt=SAE`
的網路設定沒辦法跟它匹配，所以 wpa_supplicant 永遠停在 `wpa_state=SCANNING`，連試都
不會試。同一台 AP、同一時刻，兩個 station 看到的：

| station | 它的掃描結果 |
|---|---|
| 本 repo 的，驅動 **2.0.1** | `RSN: Version 1, Group CCMP, Pairwise CCMP, Authentication suites: SAE` |
| HT-HC01P，驅動 **1.15.3** | `capability: ESS Privacy (0x0011)`，**完全沒有 RSN 元素** |

兩邊都是 `country=SG`，都有 5785 MHz [157] 22 dBm 可用、都不是 passive-scan，而且
統計是帶正對照做的，所以那個 0 是有意義的。

beacon 裡為什麼沒有 RSN，出自 `beacon.c`：

```c
static enum morse_mac_rsn_beacon_mode
rsn_beacon_mode __read_mostly = RSN_BEACON_DISABLED;

enum morse_mac_rsn_beacon_mode {
    RSN_BEACON_DISABLED = 0x00,   /* 預設 */
    RSN_BEACON_LONG     = 0x01,
    RSN_BEACON_ALL      = 0x02
};
```

S1G 的 beacon 預設省略 RSN IE，station 應該從 probe response 學到安全設定。2.0.1 會把
它呈現出來，1.15.3 不會。

在 AP 上它是一個 **uci 選項而不是 sysfs 檔案** —— 那台的驅動編進 OpenMANET 核心裡，
`/sys/module/morse` 根本不存在。它列在 `/lib/netifd/wireless/morse.sh` 的
`MM_MOD_INT` 裡：

```sh
uci set wireless.radio1.rsn_beacon_mode='2'
uci commit wireless && wifi reload
```

已套用並在 AP 開機參數傾印中確認（`rsn_beacon_mode : 2`），也在空中確認 —— 本 repo 的
station 現在會在 beacon 裡看到 RSN 元素，而不是只在 probe response 裡。

**仍未解決。** 改完之後三分鐘內 HT-HC01P 依然沒有關聯，hostapd 依然沒有它 MAC 的任何
紀錄（正對照：log 裡有 46 行 hostapd 訊息）。是它的 supplicant 需要踢一下，還是 1.15.3
即使 RSN IE **在** beacon 裡也用不了，目前不知道 —— 要查得碰得到那台，而當時碰不到。

**還有一個矛盾，記下來而不是抹平：** 另一台 Heltec（HT-H7608，同樣 1.15.3）在同一天
稍早**確實**關聯上了同一台 AP，用的是 `auth_alg=0` 加上 RSN 四向交握 —— 那是快取
PMKSA 或 WPA2-PSK 的形狀。這跟「1.15.3 無法關聯這台 AP」對不起來。當時那台碰不到，
無法查證。**不要**用 HC01P 這個結果去推論整個 1.15.3。

## 陷阱：AP 上的殘留關聯項目，看起來和正常連線一模一樣

2026-08-23 在刪掉又重建 NetworkManager profile、重新連線時遇到的。

**症狀。** 每一項都說鏈路是通的，但什麼都過不去。

  station   iw dev wlan1 link      -> Connected to 3c:1a:cc:70:3f:ca
            wpa_cli status         -> wpa_state=COMPLETED、key_mgmt=SAE、
                                      pairwise=CCMP、pmf=2
            NetworkManager         -> connected
            位址                    -> 10.41.0.208/16
  AP        iw dev wlh0 station dump -> authorized: yes、associated: yes

  然而      ip neigh               -> 10.41.254.1 FAILED（ARP 永遠解析不出來）
            雙向 ping              -> 100% 遺失
            連續三輪的遺失率        -> 60%、86.7%、100%

兩邊 dmesg 都沒有東西，SPI 也沒有錯誤。認證層完成了，資料訊框過不去。

**成因。** AP 留著上一次關聯遺留下來、對應這個 station MAC 的舊項目。刪除
NetworkManager profile 時 station 確實有送 deauth —— station 的 dmesg 裡有
`wlan1: deauthenticating from 3c:1a:cc:70:3f:ca by local choice (Reason:
3=DEAUTH_LEAVING)` —— 但 AP 沒有處理它。四分鐘後那筆還在，`inactive time:
242070 ms`、`tx failed: 20`，AP 一直對著空氣重送。接下來的關聯就疊在這筆上面。

**`wifi reload` 清不掉它。** 介面確實被拆掉重建 —— `wlh0` 的 ifindex 都變了 ——
而那筆項目還在。這是實測的，不是推測：在 station 已確認斷開的狀態下重載，AP 的表裡
仍然有一筆它的 MAC。

**真正能清掉的做法**（這個映像沒有 `hostapd_cli`）：

```sh
iw dev wlh0 station del 9c:04:b6:ff:df:fe
```

表立刻清空，station 下一次嘗試就關聯成功並且通了 —— ARP 解析出來、20/20 次 ping、
零遺失。

**怎麼辨識。** 比對兩邊的位元組計數，不要看狀態旗標 —— 兩邊的旗標都在說謊。當時
station 已送出 22365 bytes，AP 只收到其中 9559；AP 的 `tx failed` 在增加而
`tx retries` 是 0。一筆 `inactive time` 和 station 實際行為對不上的項目，就是線索。

一般性的認知：S1G 的 AP 本來就設計成容忍終端長時間休眠，所以老化逾時設得長是刻意的，
一筆死掉的項目不會很快被清掉。不要等它。

## 陷阱：只殺單一方向大量傳輸的靜默 MTU 黑洞

2026-08-23 量測上一層樓的吞吐量時發現。它是**測試網路的性質，不是驅動的問題**，而且它
很可能一直在扭曲本檔案裡的每一個吞吐量數字。

**症狀。** 大量傳輸一個方向正常、另一個方向卡死，而且哪裡都沒有錯誤訊息。小量傳輸兩個
方向都正常。全程 `ssh host echo hi` 都能在 0.56 秒內完成，所以鏈路和登入都是健康的。

| 要求的大小 | 上行（Pi → 筆電） | 下行（筆電 → Pi） |
|---|---|---|
| 1024 B | 1024 B / 0.29 s | 1024 B / 0.31 s |
| 8192 B | **0 B / 34.71 s** | 8192 B / 0.51 s |
| 32768 B | **0 B / 34.96 s** | 32768 B / 0.67 s |
| 524288 B | 從未完成 | 524288 B / 1.81 s |

門檻落在 1 KiB 到 8 KiB 之間 —— 那是**封包尺寸**的邊界，不是速率問題。這就是判讀的關鍵。

**成因。**

```
AP    br-lan  mtu 1460     eth0  mtu 1460     wlh0  mtu 1500
Pi    wlan1   mtu 1500
Mac   en5     mtu 1500
```

`wlh0` 是 1500，但它的橋接夥伴 `eth0` 是 1460，而 Linux 橋接器取所有 port 的最小值，
所以 `br-lan` 是 1460。從 HaLow 側進來、大於 1460 的訊框無法轉送到有線側，橋接器直接
丟棄。**橋接是 L2，不會送 ICMP fragmentation-needed**，所以兩端永遠不會被告知。兩端都
是依自己那張 1500 的介面協商 MSS，於是 TCP 永無止境地重傳滿載封包。

DF ping 掃描證實了它，而且形狀本身值得理解：

```
Pi -> AP    到 1500 位元組訊框全部通過   <- 目的地就是 AP 本身；
                                          訊框根本不需要走出 eth0
Mac -> Pi   1460 通過、1468 以上失敗     <- 失敗的是「回程」，不是去程
```

**修法。** station 上一個指令，原本卡 35 秒的傳輸變成 0.32 秒完成，其他什麼都沒動：

```sh
ip link set wlan1 mtu 1460
nmcli connection modify halow 802-11-wireless.mtu 1460   # 要持久的話
```

### 根因：是 `openmanetd`，而且已經確認

`/etc/` 底下 grep 不到任何 `1460`、`uci show network` 也沒有 mtu 選項 —— 那個值是執行
時被套用的，`dmesg` 顯示 `br-lan` 在開機第 43.9 秒就已經是 1460。做法是把三個候選
daemon 全部停用、重開機，然後一個一個啟動回來：

| 步驟 | `eth0` | `br-lan` |
|---|---|---|
| `openmanetd`、`alfred`、`mesh11sd` 全停用後重開機 | **1500** | **1500** |
| 啟動 `mesh11sd`，等 20 秒 | 1500 | 1500 |
| 啟動 `alfred`，等 20 秒 | 1500 | 1500 |
| **啟動 `openmanetd`，等 20 秒** | **1460** | **1460** |

單一變數，而且 1500 在開機後 65、90、115、140 秒四個時間點都穩定 —— 遠超過以前會改變
的第 43.9 秒。**設定它的就是 `openmanetd`**，推測是替 batman-adv 的封裝預留 40 位元組，
而那個 mesh 在這塊板子上**根本沒有在跑**（`alfred` 是對著 `br-ahwlan` 和 `bat0` 啟動
的，兩個介面都不存在，這就是 log 裡一直刷 `can't get interface: No such device` 的原因）。

**停掉 `openmanetd` 不會把它改回來** —— 那是單向的設定。要嘛在停用它的狀態下重開機，
要嘛在停掉它之後手動設回去：

```sh
/etc/init.d/openmanetd disable      # 用不到 mesh 的話，alfred、mesh11sd 一併停用
ip link set eth0 mtu 1500           # 只有要修正執行中的系統才需要這行
```

做完之後 `eth0`、`br-lan`、`wlh0` 全部是 1500，DF ping 掃描到完整 1500 位元組訊框全部
通過（每個尺寸 6 個封包、0% 遺失），而原本回傳 **0 位元組 / 34.7 秒**的 8 KiB 上行變成
**8192 位元組 / 0.32 秒**。少了那三個 daemon，AP 一切正常 —— SSID 在、兩台 station
關聯著、`rsn_beacon_mode` 也撐過了重開機。

從源頭修比在 station 端夾 1460 更快，因為滿載訊框的每封包開銷較低：256 KiB 上行
2.450 Mbit/s、512 KiB 下行 2.880 Mbit/s 且 md5 一致。*但這組數字不是跟樓上那次
1.48 / 2.77 Mbit/s 的乾淨對照 —— 當時板子已經搬回桌上，位置和 MTU 兩個變數同時變了。*

如果某台 station 改不了、AP 必須維持小 MTU，網路層級的做法是用 DHCP 通告真實值：
`uci add_list dhcp.lan.dhcp_option='26,1460'`。

**它很可能解釋了什麼。** 本檔案裡記為「未解釋」的兩項，正是靜默 MTU 黑洞會產生的現象 ——
「上行速率變動 4 倍，0.23–0.90 Mbit/s」，以及「第一次持續下載在 4194304 中的第 155648
個位元組截斷」。**強烈指向，但未確立**：這兩件事都還沒有在 MTU 修好之後重現過。那 5% 的
ping 遺失**不能**用這個解釋，小封包不受影響。

## 判讀鏈路：RSSI、`iw` 印出的數字，以及一種弄壞電台的方法

三個陷阱，都是 2026-08-23 在追「5% 封包遺失是不是訊號問題」時發現的。其中第一個是對
本節初版內容的更正。

### RSSI **有**被填 —— 讀到 0 是因為訊號超出量測範圍上限

**本小節先前的結論是「晶片不填 RSSI 欄位」。那是錯的，而且錯在同一個老毛病：手上
只有兩塊板子、兩塊都報 0，就把一個重複兩次的觀察當成硬體的性質。**

第三個節點解決了這件事。2026-08-23，一台 Heltec HT-H7608（同樣的 MM6108 矽晶、
Heltec 自家 OpenWrt 建置、走 SDIO、驅動 1.15.3、不同的 `mm6108.bin`）從幾公尺外連上
同一台 AP。那台 AP 就是 OpenMANET 板 —— 和「對我們的 station 報 0」的是同一個驅動
家族。它自己的 hostapd 日誌，同一分鐘內：

```
authentication: STA=9c:04:b6:ff:df:fe ... rssi=0      <- 我們的 station，同一張桌上
authentication: STA=0c:bf:74:2c:dd:05 ... rssi=-71    <- Heltec，幾公尺外
```

`iw dev wlh0 station dump` 也一致：我們的固定在 `0 dBm`，Heltec 是 `-73`／`-75 dBm`
且會變動。同一台 AP、同一顆接收晶片、同一時刻。量測路徑是好的。

所以下面那段驅動追蹤仍然正確 —— `mac.c:7180` 有宣告 `SIGNAL_DBM`、`mac.c:6123` 有把
`hdr_rx_status->rssi` 填進 `rx_status->signal`、之後沒有被覆寫 —— 但收到 0 並不是
韌體拒絕量測，那就是晶片對那條鏈路回報的值。

**原因就是飽和，而且現在是量出來的，不是論證出來的。** 兩塊 SenseCAP M1 放在同一張
桌上。923 MHz、間距 0.3 m 的自由空間損耗約 21 dB，22 dBm 的發射端會在接收端產生約
**+1 dBm** —— 已經超出量測範圍的頂端。削頂成 0 正是這種情況會有的樣子，而且它解釋了
本 repo 裡每一個 0：這兩塊板子從來沒有相距超過一公尺過。

同一天稍晚，station 那塊板子被搬離 AP，在三個距離各取樣 30 次、每次間隔 2 秒。每次搬動
**之前**先寫下預測值，用 923 MHz 的 FSPL(dB) = 20·log10(d_m) + 31.75 對上 AP 的
22 dBm：

| 位置 | 預測 | AP 側實測 | station 側 |
|---|---|---|---|
| 0.3 m，板對板 | **+0.7 dBm** | −3（範圍 −2…−4） | 0 dBm |
| 2 m，無遮蔽 | **−15.8 dBm** | **−15.7**（範圍 −14…−19） | −12.1 dBm |
| 4 m，隔一道木牆 | −21.8 dBm + 牆 | **−29.9**（範圍 −28…−32） | −27.1 dBm |
| **上一層樓** | — | **−41.3**（範圍 −38…−44） | −37.7 dBm |

2 m 無遮蔽那點與自由空間預測只差 **0.1 dB**，所以只要訊號落在量測範圍內，這條量測路徑
就是準的。0.3 m 那點是削頂的，而且削頂不只是從絕對值推論出來的，它直接顯示在**級距**
上：0.3 m 到 2 m 的真實路徑損耗是 16.5 dB，讀值卻只走了 11.7 dB（−4 → −15.7）。近端被
壓縮了 4–5 dB，這正是讀值頂到刻度上限的行為。

附帶得到一個數字：**室內木牆在 923 MHz 衰減 8 dB**。兩種獨立算法一致 —— 絕對值算
（實測 −29.9 對自由空間 −21.8）與級距算（2 m → 4 m 距離上該是 6.02 dB，讀值走了
14.2 dB，多出 8.2 dB）。

每個位置的鏈路品質都不受影響：20/20 ping、0% 遺失，隔牆 4 m 時 RTT 8.3–8.8 ms，
上一層樓時 60/60、0% 遺失。給個概念：−30 dBm 之下，MCS0 靈敏度約在 −95 dBm，還剩
大約 65 dB 餘裕；上一層樓還剩約 50 dB。

**樓板很便宜，管理網路很貴。** 上一層樓時 HaLow 鏈路完全正常，家裡的 Wi-Fi 卻完全
搆不到，所以 HaLow 反而成了唯一一條路 —— 頻外通道扛起了「它自己正在被量測的那條鏈路」
的管理流量。那個位置的吞吐量（在下面說的 MTU 修正之後）是**下行 2.77 Mbit/s、
上行 1.48 Mbit/s**，2 MHz 頻寬。

*量測遺失率時的一個陷阱：在那個位置第一次跑 ping 得到 12% 遺失，那是錯的 —— 因為當時
管理用的 SSH 連線正走在同一條 HaLow 鏈路上。淨空之後重跑，60 個序號一個不漏。
不要在一條你同時當終端機在用的鏈路上量遺失率。*

這個測試是**用搬動板子**做的。**不要用 `iw set txpower fixed` 去衰減** —— 見下一小節
它會造成什麼後果。測量期間必須把 station 的省電關掉
（`iw dev wlan1 set power_save off`）；開著的話接收端有一部分時間是關的，所有讀數都是
透過那個狀態取得的。完整方法與原始取樣見
[`logs/2026-08-23-rssi-range-test-and-ap-stall-recovery.txt`](logs/2026-08-23-rssi-range-test-and-ap-stall-recovery.txt)。

**實務上該記住的：**

- 這個驅動報 `signal: 0 dBm` 的意思是「超出量測上限」，不是「沒有量測」。兩塊板子放在
  同一張桌上就拿不到可用的 RSSI，任何「這是不是訊號問題」的提問在那個擺法下都無法回答。
- 桌面距離下 `msta->avg_rssi` 是 0，所以它的使用者 —— mesh 鄰居挑選（`mesh.c:628`）、
  `bss_stats`、以及速率控制的種子（`rc.c:293` → `mmrc_init_rates`）—— 都拿到 0。最後
  這項裡 `MMRC_SHORT_RANGE_RSSI_LIMIT = -70`，0 會通過 `rssi >= -70`，評分表從 MCS7
  起跳，讓原本會從 MCS3 起跳的 1/2 MHz 分支走不到。這是**桌面擺法**造成的真實效應，
  不是驅動缺陷。這段是從原始碼讀出來的，**尚未**經過觀察確認：搬移測試後在 −30 dBm
  下，AP 的 mmrc 表確實顯示選中 2 MHz LGI MCS0，但那張表剛被重置、裡面每個 attempt
  計數都是 0，所以那是它的初始狀態，兩個方向都不構成證據。要驗證 seeding 行為得另外
  設計實驗。
- 先前記下的那些「晶片有但驅動沒用」的設施仍然沒用，也仍然值得知道：
  `MORSE_CMD_ID_GET_RSSI`（`morse_commands.h:2825`，含 `rssi0/1/2`）定義了但從未呼叫、
  `morse_skb_rx_status.noise_dbm` 從未被讀取、`morse_cmd_evt_scan_result.rssi` 只在
  full-mac 的 `wiphy.c` 路徑使用。

先前引用的那段 radiotap 擷取 —— 我們 station 的三十個訊框全是 `0dBm` —— 本身是準確的
擷取。它是在兩塊板子都在桌上時取的，所以顯示的是同一個削頂值，**它不足以支撐當時從它
推出的結論**。

### `iw set txpower fixed` 可能讓發射器停擺，而且 `wifi reload` 救不回來

2026-08-23 為了測上面那個飽和假設，把 AP 弄壞才發現的。

對 OpenMANET AP 下 `iw dev wlh0 set txpower fixed 1000`，接著 `... 0`，再 `... 2200`。
事後 `iw dev wlh0 info` 顯示 `txpower 22.00 dBm`，介面看起來完全正常 —— 但沒有任何人
收得到它。兩個 station 同時掉線，而 AP 自己的 hostapd 日誌把樣貌講得很清楚：

```
authentication: STA=9c:04:b6:ff:df:fe ... rssi=0
wlh0: STA 9c:04:b6:ff:df:fe IEEE 802.11: did not acknowledge authentication response
authentication: STA=0c:bf:74:2c:dd:05 ... rssi=-71
wlh0: STA 0c:bf:74:2c:dd:05 IEEE 802.11: did not acknowledge authentication response
```

兩個 station 的接收它都還收得到，發射則不行。`wifi reload` —— 會拆掉並重建介面 ——
**救不回來**，必須完整重開機。

診斷筆記：最初的判讀是「station 的接收壞了」，因為 station 掃不到東西。station 是好的。
指向正確方向的線索是：**AP 的 station 表整個清空、而且兩個 station 同時失效** —— 這是
任何 station 端的故障都解釋不了的。

### `iw` 報的是 dot11ah 的對映，不是實際的無線電

這個更危險，因為那些數字看起來很合理。

| | `iw dev wlan1 link` 說的 | 無線電實際在做的 |
|---|---|---|
| 頻率 | 5785 MHz（channel 157）| **922–923 MHz** |
| 速率 | VHT-MCS 7、150.0 MBit/s、40 MHz | **MCS 0 與 MCS 5**、1–2 MHz |

dot11ah 這層 shim 把 S1G 呈現成一個以 5 GHz 編號的頻段，好讓 mac80211 和原廠的
使用者空間工具不用改就能運作。`iw` 印出來關於頻率和速率的一切都是那層對映。在一條
實測 1.3 Mbit/s 的鏈路上看到 150 Mbit/s，不是需要追查的矛盾，那就是對映本身。

要交叉查證，看 `debugfs .../morse/mmrc_table`（真正的速率選擇），或直接抓 radiotap。
當時 mmrc 選的是 2 MHz SGI MCS0，12 次嘗試成功 2 次 —— 這和實測吞吐吻合，和
150 Mbit/s 不吻合。

### 怎麼抓 radiotap（兩次嘗試都是第一次失敗，所以寫下來）

- **建置必須有 monitor 支援。** Makefile 裡是
  `morse-$(CONFIG_MORSE_MONITOR) += monitor.o`，而 TESTING.md 的建置指令沒有帶這個
  變數。在斷定「抓不到東西」之前，先用 `strings morse.ko | grep -c morse_mon` 確認。
  我們 station 的建置沒有編進去，所以那邊不重建就抓不了。
- **`morse0` 網卡拉起來還不夠。** 訊框只有在 `mors->monitor_mode` 為真時才會送到它
  （`mac.c:6889`），而該旗標來自 `IEEE80211_CONF_MONITOR`（`mac.c:4033`）—— 也就是
  必須存在一個 monitor vif。加一個就夠了，那個 vif 不必是抓包的介面：

  ```sh
  iw phy phy3 interface add mon0 type monitor && ip link set mon0 up
  ip link set morse0 up
  tcpdump -i morse0 -c 30 -e -nn      # radiotap，含真實的 MHz 與 MCS
  iw dev mon0 del; ip link set morse0 down
  ```

  在 AP 上這樣做，AP 服務沒有中斷 —— 全程 `type AP` 與 SSID 都不受影響，也沒有更動
  任何持久設定。
- `mon0` 本身只看得到 AP 自己發的 beacon。`morse0` 才是帶著晶片 rx status 的接收訊框。

## AP 的發射器會停擺，而 HaLow 鏈路是你回去的路

都是 2026-08-23 發現的，相隔數小時，而第一件事可能解釋了本檔案先前記為「未解釋」的
好幾個現象。

### OpenMANET AP 會停止發射，而且完全看不出來

一個下午內兩次，AP 變成單向失聰：接收完全正常，但沒有任何人聽得到它。

特徵，取自 AP 自己的 hostapd 日誌，兩個獨立的 station：

```
authentication: STA=9c:04:b6:ff:df:fe ... rssi=0
wlh0: STA 9c:04:b6:ff:df:fe IEEE 802.11: did not acknowledge authentication response
authentication: STA=0c:bf:74:2c:dd:05 ... rssi=-67
wlh0: STA 0c:bf:74:2c:dd:05 IEEE 802.11: did not acknowledge authentication response
```

兩個 station 的訊框都到得了 AP，兩個都收不到回覆。從 station 那端看，掃描回傳零個
BSS —— 包括它一分鐘前還連著的那台 AP。

**軟體層面完全看不出來。** `iw dev wlh0 info` 顯示介面正常、22 dBm、頻道正確。
`ip -s link show wlh0` 顯示 TX 941 packets、`errors 0 dropped 0`。`dmesg` 沒有任何
morse 或 SPI 錯誤。AP 自己認為它在發射。

第一次發生在 `iw set txpower fixed` 之後（見前一節）。**第二次前面什麼都沒有** ——
乾淨重開機後 22 分鐘，沒有任何介入，在兩個 station 都因閒置被踢掉之後就再也連不回來。
**第三次前面同樣什麼都沒有**，發生在 2026-08-23 稍晚，那一段期間只下過唯讀指令。所以
那個 txpower 指令是誘發它的一種方式，不是唯一成因；三次裡有兩次完全沒有觸發原因。

### 救援階梯 —— `reset` 有效，而且它跟 `restart` 不是同一件事

前兩次之後這裡記的是「只有重開機救得回來」。**那是錯的。** 第三次是在**沒有重開機**的
情況下救回來的，而且各階不能互相取代：

| 手段 | 結果 |
|---|---|
| `wifi reload` | 救不回來 |
| debugfs `restart`（`echo 1 >`） | **救不回來** |
| debugfs `reset`（`echo 1 >`） | **救得回來** |
| 重開機 | 救得回來 |

```sh
# 先找 phy —— 驅動每次重新初始化它就會被重新編號
#（這次 bus reset 前是 phy0，之後變 phy2）
P=$(find /sys/kernel/debug/ieee80211 -maxdepth 2 -name morse)
echo 1 > $P/reset
```

從 2.0.1 原始碼的 `debug.c` 和 `mac.c` 看，這兩個入口是不同深度的復原：`restart` 排入
`mors->recovery.driver_restart` → `morse_mac_restart()`，重載韌體並重新初始化 MAC，失敗
時它會自己升級成 bus reset；`reset` 則直接排入 `mors->recovery.bus_reset` →
`morse_bus_reset()`。

`restart` 乾淨完成，但沒有用：

```
morse_spi spi0.0: morse_mac_restart: Restarting HW
morse_spi spi0.0: Loaded firmware from morse/mm6108.bin, size 468304, crc32 0xbe7b5c8f
morse_spi spi0.0: Loaded BCF from morse/bcf_fgh100mhaamd.bin, size 1251, crc32 0x941b2a82
ieee80211 phy0: Hardware restart was requested
```

**透過 SPI 完整重載韌體並不足夠** —— 這件事本身就值得知道：卡住的東西能撐過把韌體
映像重新寫進晶片。接著 `reset` 完全恢復了：雙向 20/20、0% 遺失、RTT 8.5 ms，之後在
1 Hz 連續監測的 18 分鐘內都維持著（486 次回應、41 次遺失，其中 40 次是為了把板子搬到
下一個測量位置而刻意斷電的那段）。

`wifi reload` 做不到的可能原因：**這台 AP 的 `reset-gpios` flag 是 0**，所以 RESET_N
在這塊板子上從來不會觸發。拆掉並重建介面沒辦法讓晶片經歷一次硬體重置，而 bus reset
那條路徑碰得到它。這正是讓這台 AP 對 station 遇到的三個 SPI 缺陷全都免疫的同一個
device-tree 屬性 —— 在這裡它反過來害了自己。

### 停擺時主機側看得到什麼：什麼都沒有

第三次發生時量的，兩個讀數器都在量測失敗案例的同時、用已知正常的案例驗證過：

| 測試 | 結果 |
|---|---|
| station 送 5 個 ping → AP 的 rx 計數 | **+774 bytes** —— 上行送達 |
| AP 送 5 個 ping → station 的 rx 計數 | **+0 bytes** —— 下行不送達 |
| 兩側閒置 6 秒、不產生流量 | +152 / +154 —— 兩個讀數器都是活的 |

停擺 49 分鐘後，AP 的 debugfs `page_stats`：

```
Beacon Tx: 29040        <- 49 分鐘 / 100 ms beacon = 29400；量測當下 beacon
Data Tx: 5659              仍然持續被交給晶片
Page write fail: 0
No page: 0
Queue stop: 0
Tx aged out: 0
TX ps filtered: 0
TX status invalid: 0
```

`dmesg` 從開機第 16 秒之後就沒再出現任何一行。溫度 46 °C。`ip -s link` 報
`errors 0 dropped 0`。受影響的那個 station，mmrc 整張表只有 **2 次 total attempts**
—— 速率控制器幾乎沒被要求送過任何東西。主機側每一個計數器都是乾淨的，所以故障點在
驅動看得見的範圍之外。

### Heltec 是無線層的對照組，絕不是 IP 層的

診斷過程中用過「AP 也 ping 不到 Heltec，所以是 AP 全機故障」這個推論，**它不成立**。
即使現在鏈路健康、AP 讀到它的訊號在 −69…−76 且持續更新，AP 依然 ping 不到
`10.41.0.197` —— 它的 IP 層因為自己不相干的原因不通。

真正有份量的是無線層的證據：`restart` 之後，Heltec 在 AP 的 hostapd log 裡完成了完整
握手 —— `authenticated` → `associated` → `AP-STA-CONNECTED` →
`EAPOL-4WAY-HS-COMPLETED` —— 那需要 AP 發射得出去，而同一時間另一台 station 的 ping
仍然全滅。要用它當對照，就用 `station dump` 裡的 RSSI 和它的關聯事件。不要用 ping。

**這是本檔案先前三個「未解釋」項目的候選共同成因**：100 次 ping 測試中的 5% 遺失、
兩次沒有任何 deauth 或 beacon-loss 日誌的重新關聯、以及第一次持續下載在
4194304 bytes 中的第 155648 個位元組截斷。這三個從遠端看起來，都正是「發射器間歇性
靜默」會有的樣子。**尚未確立** —— 這個關聯性還沒被測試 —— 但之後要追那三件事，應該
先懷疑這個。

診斷筆記，因為第一次判讀是錯的：症狀看起來像「**station** 的接收壞了」，因為掃不到
東西的是 station。指向正確方向的線索是 AP 的 station 表整個清空、而且**兩個** station
同時失效。沒有任何 station 端的故障能解釋兩個獨立的 station 在同一瞬間一起失聰。

### station 的省電會遮蔽它，也會污染任何透過它取得的量測

station 這側的省電**預設是開的** —— `iw dev wlan1 get power_save` 回報 `on`，morse 模組
的 `enable_ps` 參數讀出來是 `2`。AP 那側則是反過來設的：`enable_ps=0`、
`enable_dynamic_ps_offload=0`、`enable_twt=0`。

AP 停擺期間，station 的 rx 計數在 8 秒內成長了 **0 個封包**，讀起來像是「連 beacon 都
沒有進來」。一個指令就把它變成 **8 秒 +154 個封包**，其他什麼都沒動：

```sh
iw dev wlan1 set power_save off
```

station 本來是睡著的。看起來像發射器死掉的那部分現象，其實是接收端自己關著。

這件事有兩層影響：

- **對量測。** 任何在省電開啟時取得的 RSSI 或遺失率，都是透過一個有一部分時間是關閉的
  接收端取得的。上面那個搬移測試就是為此把它強制關掉，而且每 60 秒重新確保一次，因為
  NetworkManager 會在重新連線時把它打開回去。
- **對診斷。** 它讓一個 AP 側的故障看起來比實際更嚴重，也就是為什麼第三次發生時第一次
  判讀是「發射器完全死了，連 beacon 都沒有」。beacon 一直都發得出去。

把省電關掉**並沒有**讓下行恢復 —— 單播路徑一直到 bus reset 之後才復原。這兩個效應是
獨立的，只是疊在一起。

station 與 AP 的省電設定不對盤，目前**尚未**被測試是否造成任何後果。它是先前記錄的
5% 封包遺失的合理候選成因之一，值得專門設計一次實驗。

### HaLow 鏈路是通往 station 的頻外管理通道

實驗途中 Pi 的管理用 Wi-Fi 消失了 —— 它漫遊到了筆電無法路由過去的網段 —— 但那塊板子
並沒有失聯。它的 HaLow 介面還關聯著，而那台 AP 有直連的網路線：

```
筆電 --USB 網路卡--> OpenMANET AP 10.41.254.1 --HaLow--> Pi 10.41.0.208
```

從 AP 上用 dropbear 的用戶端，密碼可以從環境變數帶入：

```sh
DROPBEAR_PASSWORD='...' dbclient -y -y -l alan 10.41.0.208 'command'
```

這救回了一塊原本無頭、無法觸及、沒有實體存取也沒有網路線的板子。

**還有一個更簡單的形式，而且應該優先用它。** AP 的 `br-lan` 同時橋接 `eth0` 和 `wlh0`，
而筆電的 USB 網路卡就在同一個 `10.41.0.0/16` 裡。所以筆電可以**直接**連到 station 的
HaLow 位址，用一般的金鑰認證 —— 不需要先跳到 AP、不需要 dropbear 用戶端，也不需要把
密碼放進命令列：

```sh
ssh alan@10.41.0.208
```

2026-08-23 端到端驗證過。上面那個兩段式的 `dbclient` 做法仍然有效，是筆電沒有接線到
AP 時的後備。

一般性的心得：HaLow 網路有自己的定址、自己的無線電，獨立於場地的 LAN。不管管理網路
發生什麼事，只要 station 還關聯著、AP 還用線接著筆電，這條路就是通的。它慢、會掉封包，
但要一個 shell 綽綽有餘。

同一次事件中另一個浪費時間的陷阱：Pi 的 Wi-Fi MAC **不是**它的乙太網路 MAC。
`eth0` 是 `e4:5f:01:52:55:04`，`wlan0` 是 `...:55:05`。拿錯的那個去翻 ARP 表會什麼都
找不到，看起來就像板子關機了。

## 2026-08-23：成功了 —— `wlan1` 在原廠 Raspberry Pi OS 上起來了

```
phy31 -> platform/soc/fe204000.spi/spi_master/spi0/spi0.0
wlan1 -> phy31, MAC 9c:04:b6:ff:df:fe
351 筆 SPI 寫入交易，0 筆寫入失敗，0 筆讀取失敗
```

```sh
insmod morse.ko country=SG bcf=bcf_fgh100mhaamd.bin \
    spi_inter_block_delay_bytes=250 spi_post_write_status_bytes=250
```

**沒有用 `spi_rx_lshift`** —— 不再需要了。

一共有**兩個獨立的缺陷**。第一個（晶片從未被切進 SPI 模式）在下一節。第二個是這個。

### 交易間的延遲是以 clock 數計算的，不是以時間

驅動是從時間推算的：

```c
inter_block_delay_bytes = MM6108_SPI_INTER_BLOCK_DELAY_NANO_S /
                          (SPI_CLK_PERIOD_NANO_S(max_speed_hz) * 8)
```

40000 ns 在 50 MHz 是 250 個位元組，在 10 MHz 是 50 個。兩者都是 40 µs —— 如果晶片要
的是固定**時間**，兩者應該等價。

**它們不等價。** 10 MHz 下 50 個位元組會失敗、250 個會成功。**晶片要的是固定的 SPI
clock 數。** 驅動的模型只有在 50 MHz 時剛好算出可用的值 —— 這就是為什麼所有能動的組態
都跑 50 MHz，而我們這台跑 10 MHz 就不行。

Morse 的 OpenWrt feed patch 在**三個地方**都設了 250 的硬下限。**這三個在這裡各自都是
必要的，而且每一個都是在重讀那個 patch 之前獨立發現的：**

| | 它修的失敗 | 修法 |
|---|---|---|
| block 寫入延遲 | 第 52/58 筆 `fn=2 0x00000000:14`，晶片在 +261 回 `0xeb`（CRC ERROR）—— 在 block 中途，因為它還在處理前一筆 344 位元組的非 block 寫入 | `spi_inter_block_delay_bytes=250` |
| 非 block 寫入的墊底 | `fn=2 0x00001000:80`，byte 模式；預設 CRC 之後只墊 4 個位元組 | `spi_post_write_status_bytes=250` |
| 非 block **讀取**延遲 | `cmd53_read fn=2 0x00003110:92` → `failed to parse extended host table: -5`。92 位元組的讀取只算出 44 | 沒有現成參數，新增 `spi_min_delay_bytes`，預設 250 |

修好第一個，失敗跳到第二個；修好第二個，跳到第三個。每一個看起來都像新問題，其實是同一
個問題的不同側面。

### 一則對紀錄的更正

`spi_post_write_status_bytes` 先前測過 4…64、後來又測過 512，兩次都記成**已消除**。
兩次量測都沒錯，但兩次結論都不可用：那時晶片不在 SPI 模式、第一筆寫入就失敗，墊多少都
不會有差別。它要等到 init 缺陷修好、驅動能跑到第 50 筆交易，才變得相關。

**一個消除只在它被量測的那個狀態下成立。** 十五個假設是對著一顆全程處於錯誤模式的晶片
測的，而其中至少有一個是被那個狀態掩蓋掉的真實成因。

### 但書

~~`iw phy` 和 `iw dev` 都列不出 phy31 —— 原廠 mac80211 沒有 S1G 頻段支援。~~
**這是錯的，2026-08-23 更正。** `iw` 裝在 `/sbin`，不在一般使用者的 `PATH` 裡；那些呼叫
其實回的是 *command not found*，而我把空輸出讀成技術限制。用完整路徑跑，它**完整列出**
這個 phy —— `wlan1` type managed、完整的加密演算法清單、IBSS/managed/AP/AP-VLAN/
monitor/mesh、Band 2 含每個頻道的法規狀態。**mac80211 的註冊是完整的。**

~~真正的缺口比原本說的窄：`iw dev wlan1 scan` 回傳成功，卻完全沒有產生任何 SPI 交易。~~
**這句也是錯的，再次更正。** 那個計數器是儀器化版本裡的 `dev_info`；乾淨的 patch 系列
沒有它，所以 log 行不存在 —— 而我把「行不存在」讀成「匯流排閒置」。同一個錯誤換個外衣。

改用 SPI core 自己的統計（不依賴本倉庫寫的任何東西，`/sys/bus/spi/devices/spi0.0/statistics/`）：

| | 訊息 | 位元組 |
|---|---|---|
| 靜置 3 秒 | +17 | 4.6 KB（30 秒 watchdog） |
| `ip link set up` | +165 | 40 KB |
| `iw scan` ×3 | +31、+31、+36 | 各約 8 KB |

`errors 0`、`timedout 0`。`morse_mac_ops_start`、`add_interface`、`morse_ops_hw_scan`
三個回呼都有被呼叫，`morse_cmd_get_version()` 回傳 0。**掃描確實到達晶片，找不到東西是
因為附近沒有 HaLow 網路。**

**2026-08-23 後續更正：上面最後那句是錯的。** 這裡引用的每一次掃描，全程都有一台
HaLow AP 在幾公尺外廣播 —— 就是第二塊 SenseCAP M1，跑著 OpenMANET。它之所以看不見，
是因為它在 `country=US` 而這台 station 在 `country=SG`；dot11ah 的對映會讓同一個對映
頻道號在不同 country 下對應到不同的 S1G 頻率，所以 station 掃的是 AP 根本不在的頻道
計畫。兩邊都設成 `SG` 之後，第一次掃描就看到 AP，而且成功關聯。誠實的說法應該是
「掃描的頻道計畫上沒有網路」，而且根本沒有拿同一張桌上的那台 AP 去對照過。這和本節其他
地方是同一個失敗模式：把空的結果照單全收。

當時未驗證的是關聯與資料傳輸。**兩者都已於 2026-08-23 驗證** —— 見
[`logs/2026-08-23-association-verified-environment.txt`](logs/2026-08-23-association-verified-environment.txt)。

同一個 session 裡有**六次**把「沒看到」讀成「不存在」：RUN 5 的墊底掃描、`mode=0x4` 那行、
1.5 秒上電等待、`iw` 不在 `PATH`、「拉起 wlan1 會產生暫存器寫入」（dmesg 沒清）、以及這次。
其中兩次跑進了公開留言。已在 issue #9 以 comment 5381978970 與 5382020693 更正。
**這個模式本身才是值得留下的發現：當一個儀器回報「什麼都沒有」，先檢查儀器，再相信它。**

完整細節：`logs/2026-08-23-WORKING-environment.txt`。

---

## 2026-08-23：已解決 —— 晶片從來沒有進入 SPI 模式

2-bit 偏移修好了。根本原因一句話：**MM6108 必須先收到約 74 個「CS 未選取」狀態下的
clock 才會進入 SPI 模式，而在 `cs-gpios` 控制器上，`morse_spi_initsequence()` 從來
沒有真的送出那些 clock。**

Morse 在他們的 i.MX93 移植討論串裡直接寫明了這個要求：

> in order to put it into SPI mode, the host needs to toggle the SPI clock line
> ~74 times while the CS pin is held high — ie, inverted compared to normal
> operation.

以及，對一台失敗方式與我們相同的主機：

> The original configuration had the chip select driven low during
> initialization, preventing the device from responding to subsequent commands.

`morse_spi_initsequence()` 想用翻轉 `SPI_CS_HIGH` 來達成這件事。它沒有用，而
`patches/` 裡加的 mode 記錄顯示了原因：

```
init: mode=0x4 cs_high_default=1 train=18 flip=1
init: CS deasserted for training, mode=0x4     ← 預期是 0x0
init: CS polarity restored, mode=0x4
```

`0x4` 就是 `SPI_CS_HIGH`，在 `spi->mode &= ~SPI_CS_HIGH; spi_setup(spi);` 之後**它還
在**——**`spi_setup()` 對 `cs-gpios` 裝置會把它強制設回去。** 那 74 個 clock 因此是在
晶片**被選取**的狀態下送出的，它從未進入 SPI 模式，之後每一筆回應都偏離位元組格線
兩個 bit。

### 修正

`SPI_NO_CS` 做得到翻轉做不到的事 —— 控制器完全不碰 CS 線，GPIO 在整段訓練期間保持
高電位。用 `spi_init_no_cs`（預設開啟）控制，原本的翻轉保留為後備。

**順序是關鍵，而這正是答案藏了一小時的原因：** 訓練必須在 reset 之後、任何其他交易
之前。一旦晶片被以 CS 選取的方式接觸過，就救不回來了。我先前一次使用者空間的嘗試把
訓練放在第一次 CMD0 **之後**，沒有改善，看起來像否定結果 —— 其實不是。

### 驗證

使用者空間，手動控制 CS 並設 `SPI_NO_CS` 讓控制器無法干擾，每次試驗前都完整 reset：

| 序列 | 回應 |
|---|---|
| CS 全程 HIGH 送 CMD0 | `ff ff ff ff` —— 沉默，證明 CS 確實在手動控制下 |
| CS LOW 送 CMD0，無訓練 | `ff c0 7f ff` —— R1 @bit10，**偏移** |
| CS HIGH 打 80 clock 後送 CMD0 | `ff 01 ff ff` —— R1 @bit8，**對齊** |

6/6 可重現。正確初始化之後，`CMD0`→`0x01`、錯誤 CRC→`0x09`、`CMD13`→`0x05`、
`CMD63`→`0x01`，全部落在位元組邊界上。

接著在驅動裡，同一個二進位、同一塊板子、只差一個參數：

| `spi_init_no_cs` | 結果 |
|---|---|
| `Y`（預設） | `training with SPI_NO_CS, mode=0x44`；無偏移、CMD63 通過、韌體與 BCF 載入 |
| `N`（原行為） | `CS deasserted for training, mode=0x4`；`c0 3f` / `c0 7f` 回來了 |

**`spi_rx_lshift` 不再需要。** 先前每一次執行連讀 chip ID 都得靠它；現在完全不加，
讀取路徑原生正確 —— 468 KB 的韌體傳輸無誤。

### 仍未解決：CMD53 寫入路徑

這是另一個問題，而且現在才第一次看得清楚：

| | 修正前 | 修正後 |
|---|---|---|
| 晶片的回應 | CRC 後 519 個位元組全 `0xff` —— 沉默 | **有回應**；`b=0x001f0002` |
| 失敗點 | `fn=1 0x00004050:4` | `fn=2 0x00000000:14` —— 韌體下載階段，走得深得多 |

Morse 只放在 OpenWrt 的 `find_data_ack` 修改（掃描到 accept token 才停，而不是遇到
第一個非 `0xff` 就放棄）已實作在 `spi_ack_scan` 之下，預設開啟。**在這塊板子上它毫無
作用** —— 掃完 3440 個位元組都找不到 `0x05`。記下來是因為它有原廠背書，否則會有人再
試一次。

### 為什麼 OpenMANET 不需要這個修正

因為它從來不 reset 晶片。它的 `reset-gpios` flag 是 0（`GPIO_ACTIVE_HIGH`），所以
`morse_hw_reset()` 的 `gpiod_set_value(reset, 1)` 是把腳位拉**高** —— RESET_N 根本
沒有真的觸發。在這塊板子上實測（模組電源在 GPIO18，我們控制得到）：

| | 回應 |
|---|---|
| 冷上電、完全不訓練 | `ff 01 ff` —— **對齊，本來就在 SPI 模式**（3/3） |
| 同一次上電，打 RESET_N 脈衝後 | `ff c0 7f` —— **偏移，被踢出 SPI 模式** |
| 之後補訓練 | `ff c0 7f` —— 救不回來（中間已有一次 CS 拉低的命令） |

第 1→2 步是最乾淨的：同一次上電、只多了一個 reset 脈衝，狀態就從對齊變偏移。
**RESET_N 會把晶片踢出 SPI 模式。** 所以 OpenMANET 一直留在上電時的模式，壞掉的訓練
無所謂；本倉庫的 overlay 用 flag 1，reset 真的觸發，壞掉的訓練就補不回來。

**但要註明：上電後的狀態不是百分之百確定的** —— 五次冷上電裡有一次上電就已經偏移。
原因不明。晶片**通常**上電就在 SPI 模式，不是必然。

這也解釋了兩句我們很早就搜到、當時看不懂的社群回覆 —— *「實體斷電重來就好了，軟體
重開機不行」*、*「我們大部分佈署都用一個 reset script 在開機時 toggle reset 線」*。
實體斷電讓晶片重新進入 SPI 模式；軟體重開機不行，因為模組沒斷電，仍停在上一次
RESET_N 脈衝留下的狀態。它同時解釋了為什麼單獨測 `reset-gpios` flag 0 毫無效果：那時
晶片早就被先前幾次開機的 reset 踢出 SPI 模式了，而那次測試從未斷過電。

**有了修正，上面這些都不重要。** 驅動會在 reset 之後立刻用正確方式送訓練，所以不管
晶片上電時是什麼狀態、被 reset 過幾次，都會進到 SPI 模式。OpenMANET 是**繞過**了這個
問題，不是處理了它 —— 修正把原本靠運氣的事變成確定的。

**一則方法論註記。** 這個測試的早期版本在重新供電後只等 1.5 秒，結果得到一幅完全不同
的圖像 —— 全部偏移，連先前驗證過能成功的序列也偏移。模組需要超過 1.5 秒才會接受任何
東西。是「先重跑一次已知能成功的序列」抓到了這件事；沒有那道檢查，這個假象就會被當成
發現歸檔進來。

### 為什麼繞了十五個消除

先前每一個假設都是關於**匯流排**的 —— 核心樹、device tree、時脈、上下拉、供電時序、
驅動自己的 padding。而答案是晶片從頭到尾都處在**錯誤的模式**，任何關於匯流排的檢查都
照不到那裡。揭露它的 mode 記錄加得很晚，而它的意義要等到 Morse 自己的說法出現在一個
完全不同 SoC 的討論串裡，才變得清楚。

完整細節：`logs/2026-08-23-nocs-init-fix-environment.txt`。

---

## 2026-08-23：十四項消除，以及這條路線的終點

失敗那塊板子的 device tree 現在**逐項、而且同時**與正常那台一致 —— 單一
`cs-gpios`、GPIO7 不被當 chip select、`reset-gpios` flag 0、`spi0_pins` 與輔助腳位
的上下拉相同、插槽供電由 VideoCore 韌體而非 DT hog 施加。重開機後逐項確認生效。
失敗指紋逐位元組不變：`c0 3f` / `c0 7f`、CMD63 `ret:-71`。

在下面那十項之外，又消除了四項：

| 測試 | 為什麼看起來合理 | 結果 |
|---|---|---|
| `config.txt` 加 `gpio=18=op,dh` | OpenMANET 是在**韌體階段**供電，比核心早好幾秒；我們要等 gpiolib 的 hog。一顆還沒完成內部上電初始化的晶片送出偏移的回應，會是確定性的、與時脈無關的、從第一筆交易就存在 —— 符合所有觀察到的特徵 | 不變 |
| 輔助腳位的上下拉 | 我們的 overlay 把 GPIO5（SPI_INT）和 GPIO23（WAKE）拉**低**，OpenMANET 兩支都拉**高** —— 第一輪比對漏掉的差異 | 不變 |
| `spi0_pins` **從開機**就 pull-up | RUN 6 是在執行期改的，那時 SPI 區塊早已初始化。SCLK 被 mux 成 ALT0 **那一刻**的閒置電位是另一回事，而那只有 overlay 設得到 | 不變 |
| 以上全部同時套用 | 每一項先前都只單獨測過，留下「會不會是組合效應」的空間 | 不變 |

### 更正：RUN 5 的結論收回

RUN 5 在同一次 CS assertion 內於命令前墊 0…32 個 `0xff`，每次都是 `@bit10`，我當時
的結論是「**不是**主機在傳輸開頭取樣錯誤」。**那個推論是錯的。**

假設控制器在 CS 拉低之後、第一個資料位元之前多打了兩個 clock：晶片收下那兩個 bit，
它的位元組格線從此和我們錯開兩位。它仍然解析得出命令，因為 MMC-SPI 的命令是靠
`01` start bit 自我定界、不需要位元組對齊 —— **這正是它能驗證我們 CRC7 的原因**。
墊再多 `0xff` 也不會改變，因為那兩個多餘的 clock 在最前面。**我們的觀察正是這個假設
會預測的結果，而不是反證。**

*（註：這條後來也不是答案 —— 真正的原因見本檔最上面那一節。）*

所以「CS assert 時多出 clock」這條線是活的，而且它是主機側行為 —— 符合那個最頑固的
事實：同一組硬體上，這件事與作業系統相關。量測本身成立，錯的只是結論。

### 這條路線的終點

十四個測試，沒有找到成因。剩下的候選**無法再用這類測試分辨** —— 它們全都是關於
「傳輸開始後的頭幾微秒，線上到底發生什麼」，而這些方法都看不到那裡。

**誠實的下一步是邏輯分析儀**，接 SCLK / MOSI / MISO / CS。它能直接顯示 CS 拉低到第一
個資料位元之間控制器有沒有送出 clock、以及晶片從第幾個 clock 開始驅動 MISO。這些腳位
全都在 40-pin 排針上。

---

## 2026-08-23：A/B 找到的 device-tree 差異全部消除

A/B 找到的四個差異，用兩次 overlay 改動全部關掉了，失敗指紋從頭到尾逐位元組不變。

| 差異 | 改動 | 結果 |
|---|---|---|
| `cs-gpios` 兩個項目 | `cs-gpios = <&gpio 8 1>` 外加 `spi0_cs_pins { brcm,pins = <8> }` —— 後者必要，因為 base rpi DT 宣告的是 `<8 7>` | 確認生效（屬性 24 → 12 bytes、GPIO7 變 `MUX UNCLAIMED`）；**偏移不變** |
| `reset-gpios` flag 1 | 改成 `<&gpio 17 0>`，和 OpenMANET 一致 | 確認生效；**偏移不變** |
| `spi-max-frequency` | —— | RUN 4 已消除 |

`reset-gpios` 這一項值得留個墓誌銘。那個 flag 是 `GPIO_ACTIVE_LOW`，而
`morse_hw_reset()` 用 `gpiod_set_value(reset, 1)` 宣告 reset —— flag 1 會把腳位拉
**低**、RESET_N 真的觸發；flag 0 則拉**高**，意思是 **OpenMANET 上驅動的 reset 脈衝
很可能從來沒有真的發生過**。而今晚修好 `tools/mmcspi.py` 的 `reset_module()`、讓
reset 真的發生之後，CMD0 的尾巴從 `ff c0 7f` 變成了 `1f c0 7f` —— 所以「reset 脈衝
本身把晶片推進偏移狀態」是個有根據的假設。現在它死了。

**失敗那塊板子的 `spi0` 節點，現在在 A/B 找到的每一項差異上都與正常那台一致，而它
依然以完全相同的方式失敗。** DT 這條路走完了 —— 累計十項消除。

### 板子身分，補記

有**兩台** SenseCAP M1，而且主機名都叫 `Sensecap`，所以只記主機名的 environment
檔沒辦法分辨某次測試跑在哪一台。存檔的開機 dmesg 解決了這件事 —— kernel command
line 裡有 MAC：6.6.51 開機、6.12.93 開機、**以及兩次 OpenMANET**，全都是
`E4:5F:01:52:57:E7`。

所以**同一塊板子確實在 Raspberry Pi OS 下失敗、在 OpenMANET 下正常** —— "same
board" 成立，而且現在有 log 佐證，不是靠記憶。

第二台 `E4:5F:01:52:55:04` 跑同一張卡，失敗指紋逐位元組相同。第二塊板子配第二個
模組重現同樣的偏移，是佐證而不是麻煩。

一個值得記住的陷阱：`retest-*.log` 存在 SD 卡上，不在板子上。在某台機器上看到那些
檔案，只證明卡後來被插進過那台，不證明測試是在那裡跑的。往後每份 environment 檔都
會記板子的 MAC 與序號。

### 從來沒有比對過的東西

基礎的 `bcm2711-rpi-4-b.dtb`（Raspberry Pi OS 用韌體分割區的，OpenWrt 用自己編的）、
**VideoCore 韌體**（`start4.elf`、`fixup4.dat`）、以及核心 config。VideoCore 韌體是
其中最有意思的：它在核心啟動之前就設定好 SoC 的時脈樹，而我們的症狀是位元層級的
時序偏移，而且它是兩份映像之間必然不同、卻從未被檢視過的東西。

---

## 2026-08-22：A/B 做完了 —— 差異在第二個 chip select

在同一塊板子上開起 OpenMANET，把它的 live device tree 與 pinmux 擷取下來，對照
失敗那側的擷取。四個差異，其中一個從來沒被檢查過。

| | Raspberry Pi OS 6.6.51（有偏移） | OpenMANET 6.6.138（正常） |
|---|---|---|
| `cs-gpios` | `<&gpio 8 1>, <&gpio 7 1>` —— **兩個** | `<&gpio 8 1>` —— **一個**（屬性長度正好 12 bytes） |
| GPIO7 | `fe204000.spi … function gpio_out` | `(MUX UNCLAIMED) (GPIO UNCLAIMED)` |
| `reset-gpios` | `<&gpio 17 1>` | `<&gpio 17 0>` |
| `spi-max-frequency` | 10 MHz | 50 MHz |

其餘全部相同：MISO/MOSI/SCLK 都是 `alt0`、GPIO8 都是 `gpio_out`，spi0 節點的
`dmas`、`clocks`、`interrupts`、`reg`、`compatible` 也一致。時脈那項已經被消除
（RUN 4 掃過 400 kHz…50 MHz）。

**所以剩下的就是第二個 chip select。** 失敗那側註冊了兩個、而且 SPI 控制器把
GPIO7 當輸出佔住；正常那側只註冊一個、完全不碰 GPIO7。這個變數從來沒被檢查過 ——
先前的 pinmux 檢查確認的是「沒有腳位被**雙重**驅動」，那確實沒有，然後就停在那裡。

它值得測而不只是記下來，因為 CS 的數量在這個驅動裡**不是無關緊要的**：OpenWrt
import 的三個 rpi `spi-bcm2835.c` patch 裡，有一個就叫 `950-0821`
"Support spi0-0cs and SPI_NO_CS mode"。

這是整個調查裡**第一個來自「可運作與失敗組態之間的實測差異」**的假設，而不是從
「什麼可能有關」推理出來的。

**下一步：** 把 `overlays/mm610x-spi-sensecap.dts` 改成只宣告一個 chip select ——
在 `&spi0` 上寫 `cs-gpios = <&gpio 8 1>`、不要碰 GPIO7 —— 重編、重開機，看
`morse rx` 還會不會出現 `c0 7f`。同一輪或緊接著試 `reset-gpios = <&gpio 17 0>`。

細節（包含 OpenMANET 那側**沒能**擷取到的部分：沒有 `python3`、沒有
`kmod-spi-dev`，所以 A/B 的 userspace 探測那一半沒跑成）在
`logs/2026-08-22-openmanet-1.8.0-ab-environment.txt`。

---

## 2026-08-22：重測跑完了 —— 八項消除，沒有一項是成因

以下所有內容都寫在硬體重測之前。重測已經透過 SSH 跑完，而且它連 padding 假說一起
殺掉了。完整細節在 `logs/2026-08-22-bookworm-6.6.51-retest-environment.txt`。

| 假設 | 測試 | 結果 |
|---|---|---|
| 核心樹差異 | 同 stable tag 的原始碼 diff | 消除 —— 逐位元組相同 |
| ACK 視窗太窄 | `spi_post_write_status_bytes=512` | **消除** —— `no non-0xff byte in the 519 bytes clocked after CRC` |
| 偏移由 init training burst 造成 | 七次掃描 `spi_init_train_bytes` 0/2/17/18/20 與 `spi_init_cs_flip=N` | **消除** —— 七次都是 `c0 3f` / `c0 7f` |
| GPIO8 被雙重驅動 | 實機 pinmux | **消除** —— 7/8 `gpio_out`、9/10/11 `alt0` |
| 與時脈相關 | 400 kHz / 1 / 20 / 50 MHz | **消除** —— 每個速率都一樣 |
| 驅動本身有涉入 | 用 `driver_override` 綁 spidev，完全不載入驅動 | **消除** —— 同樣的 `R1=0x01 @bit10` |
| 主機在傳輸開頭取樣錯誤 | 同一次 CS assertion 內在命令前墊 0…32 個 `0xff` | **消除** —— 每次都在 `@bit10` |
| MISO/MOSI/SCLK 的上下拉 | 執行期用 `pinctrl set 9\|10\|11 pu` 對照 pull-down | **消除** —— 兩個方向逐位元組相同 |

pull 這一項值得多寫一段，因為**差異是真的存在**，只是不是成因。把剛燒好的卡上
OpenMANET 自己的 `mm610x-spi.dtbo` 解出來看，裡面是
`spi0_pins { brcm,pins = 9 10 11; brcm,function = ALT0; brcm,pull = 2 2 2 }`
—— **三支 SPI 線全部 pull-up**。而本倉庫的 overlay 從來沒設過那些 pull，沿用
BCM2711 的預設 **pull-down**，在運行中的板子上確認過。當初的推理是：MMC-SPI 從機
在回應前會 tri-state MISO，那幾個 bit 的電位由上下拉決定。執行期翻過去，毫無變化。
記下來是為了避免這個差異日後又被重新發現、重新爭論一次。完整解碼在
`logs/2026-08-22-openmanet-1.8.0-overlay-mm610x-spi.txt`。

那份解碼同時確認了這個映像**不需要換 overlay**：reset 在 GPIO17 且設 pull-up、
IRQ 在 GPIO5、power-gpios 23/24、`cs-gpios` GPIO8 active-low、
`spi-max-frequency` 50 MHz —— 從頭到尾都是 WM1302 HAT 腳位。

兩個要帶著走的事實：

- **`spi_setup()` 會把 `SPI_CS_HIGH` 設回去**（對 cs-gpios 裝置），所以
  `morse_spi_initsequence()` 的 training burst 在**所有這類主機上**都是在晶片被
  選取的狀態下送出的。這是真實的驅動缺陷 —— 已回報上游 —— 但不是這裡的成因。
- **預設的 ACK 搜尋視窗是 11 個位元組**，不是下面寫的 71；71 是 hex dump 的長度。

要取得 spidev 節點應該用 `driver_override` —— 從 `config.txt` 拿掉 overlay 會連
GPIO18 的插槽供電 hog 和 GPIO17 的上拉一起拿掉。另外 `tools/mmcspi.py` 的
`reset_module()` 也修好了：它原本用 libgpiod v2 的 `gpioset` 語法，在 Bookworm 的
v1.6.3 上會靜默失敗，等於 reset 從來沒發生過。

**剩下的**是晶片與主機對「位元組邊界在哪」的真實歧見，而同一片板子在 OpenMANET 上
完全不需要補償。唯一還有價值的實驗是直接 A/B：開 OpenMANET 卡、跑同一支 spidev
探測。那需要實體換卡。

---

## 2026-08-22 後續：核心樹結論被推翻 —— 分歧在驅動的打包

把下面那一節建議的 tree diff 實際做了。結果是空的：**兩條核心樹之間沒有
`spi-bcm2835` 差異。**

方法：`raspberrypi/linux` 的 `stable_20241008` tag（= 6.6.51，正是失敗的那份
Bookworm 映像所用的核心），對上重建出來的 OpenWrt 樹 —— 也就是 mainline stable
加上 `target/linux/bcm27xx/patches-6.6/` 裡所有會動到該檔案的 patch。

| 檔案 | OpenWrt bcm27xx 6.6 vs raspberrypi/linux rpi-6.6.y @ 6.6.51 |
|---|---|
| `drivers/spi/spi-bcm2835.c` | 逐位元組相同 |
| `drivers/spi/spi.c`（SPI core） | 逐位元組相同 |
| `drivers/dma/bcm2835-dma.c` | 逐位元組相同 |
| `drivers/pinctrl/bcm/pinctrl-bcm2835.c` | 逐位元組相同 |
| `arch/arm/boot/dts/broadcom/bcm270x-rpi.dtsi` | 逐位元組相同 |

OpenWrt 是原封不動 import rpi 的 commit。rpi 樹對 `spi-bcm2835.c` 的改動總共只有
三個 commit —— phys-addr slave DMA 設定、zero-length transfer 的 workaround、以及
`spi0-0cs`/`SPI_NO_CS` 支援 —— OpenWrt 三個全帶（950-0276 / 950-0467 / 950-0821），
SPI core 那個也在（950-0204，"Force CS_HIGH if GPIO descriptors are used"）。
mainline 的 `spi-bcm2835.c` 從 v6.6.51 到 v6.6.138 也一行都沒改，而
`OpenMANET/firmware` 在 1.8.0 tag 上帶的正是與上游 openwrt-24.10 相同的那三個 patch。

所以兩條樹都沒有東西可以 bisect。

### 真正的差異：一個只存在於 OpenWrt 的 Morse 驅動 patch

*（已被上面的重測取代：這個 patch 確實存在、這個分歧也確實值得回報，但把視窗開到 519 個位元組在這片板子上毫無改變，所以它解釋不了這次的失敗。）*

`OpenMANET/firmware@1.8.0` 的 `feeds.conf.default` 把 `MorseMicro/morse-feed` 釘在
`fc332b0`，而那個 feed 在建置前會對驅動套用
`essentials/morse_driver/patches/mm61x/003_fix_spi_inter_transaction_delay.patch`。
patch 的說明幾乎就是在描述這個症狀：

> Add more delay between SPI transactions when not in block mode. [...]
> Currently the driver has enough delay between blocks but not when the
> transaction isn't a block.

它把**非 block** 的 CMD53 write 在 CRC 之後要墊的位元組數，從 `4` 改成
`max(250, count * inter_block_delay_bytes / MMC_SPI_BLOCKSIZE)`，非 block 的讀取
也套用同一個下限。

數字完全對得上：

- `MM6108_SPI_INTER_BLOCK_DELAY_NANO_S` = 40000 ns，而
  `inter_block_delay_bytes = 40000 / (時脈週期 ns * 8)` → **50 MHz 時剛好 250 個
  位元組**，10 MHz 時是 50 個。Morse 的 `max(250, …)` 就是「滿速下的一整個
  inter-block delay」，而且不隨時脈縮放。
- 原版 `mm6108-2.0.1` 把同一行改成模組參數 `spi_post_write_status_bytes`，
  **預設值 4**。
- 這裡每一次失敗都是非 block write：`cmd53_write fn=1 0x00004050:4`，count = 4。
- 而這裡測過最寬的視窗是 **64** 個位元組。

也就是說，ACK 視窗從來沒有開得夠寬。下面那句「已排除：`spi_post_write_status_bytes`
4/8/16/32/64」不是一個有效的排除。

### 第二個驅動側差異：`enable_ext_xtal_init`

OpenMANET 的 UCI 裡設了 `enable_ext_xtal_init='1'`（見
`logs/2026-08-22-openmanet-1.8.0-environment.txt`）。在 `morse_spi_cmd53_write()`
裡，只要這個參數有開**且** `cfg->xtal_init_bus_trans_delay_ms` 不為零，驅動就會再
往該筆交易追加 `XTAL_TRANSFER_DELAY_BYTES` = **4096** 個位元組；而
`mm610x_enable_ext_xtal_delay()` 只在該參數開啟時才會設那個欄位。所以那台能動的
機器，ACK 視窗比這裡測過的任何一組都寬兩個數量級。

注意這裡有個先後順序的陷阱：`mm610x_ext_xtal_init()` 本身是用
`morse_reg32_write()` 做的，也就是它**需要一條能用的寫入路徑**。在寫入已壞的情況下
單獨打開這個參數（試過，「無變化」）本來就不可能有用 —— 得先把 padding 修好。

### 那組四方比較並不是單變數

從存檔的 log 裡看，通過的 OpenMANET 那次與失敗的 Raspberry Pi OS 各次，還有這些
差異：

- **BCF 不同。** OpenMANET 載入的是 `bcf_default.bin`（1298 位元組，crc32
  `0xf72450a7`）；這裡的建置載入的是 `bcf_fgh100mhaamd.bin`（1251 位元組，
  `0x941b2a82`）。下面說「BCF 相同」是錯的 —— 真正相同的只有 `mm6108.bin`
  （`0xbe7b5c8f`）。
- **dot11ah 版本不同。** OpenMANET 註冊的是 `Dot11ah driver registration.
  Version 0-rel_mm8108_2_0_0_2026_Apr_21`，與 mm6108 2.0.1 主驅動並存；這裡兩者
  都是 mm6108 2.0.1。
- **overlay 不同。** 那邊 `spi-max-frequency` 是 50 MHz，這裡是 10 MHz —— 光這一項
  就讓算出來的 `inter_block_delay_bytes` 從 250 變成 50 —— 另外還有
  `reset-gpios = <&gpio 17 0>` 對上這裡的 `<&gpio 17 1>`，以及 pinctrl 是掛在
  controller 上而不是掛在子裝置節點上。

### 有一項證據對 padding 假說不利

下面「未解的問題」那一節記著：同一筆交易在使用者空間手動打的時候，會在 **CRC 之後
兩個位元組**回傳 token `0x05`。如果晶片真的是這樣，4 個位元組的視窗本來就夠，
padding 就不是那道牆。這個觀察和驅動裡「71 個位元組全是 0xff」不可能同時在描述
同一個晶片狀態。卡片狀態（idle vs 已初始化）一直是嫌疑，但從未被驗證。所以
padding 假說數字上吻合得很漂亮，卻**還沒被證實** —— 它必須被量，而不是被假設。

### 接下來的實驗，依序

*（這些現在全部跑完了 —— 見最上面的重測那一節。保留下來，是因為每一項背後的推理正是解讀結果時要對照的東西。）*

`patches/` 在 2026-08-22 擴充過，就是為了讓這些可量測：新增
`spi_init_train_bytes`（預設 18）與 `spi_init_cs_flip`（預設 Y）兩個模組參數、
在 `morse_spi_initsequence()` 全程印出 `spi->mode`，並改寫
`morse_spi_find_data_ack()` 的失敗路徑 —— 現在會報出**第一個非 `0xff` 位元組的
offset 與值**（或明講「N 個位元組裡一個都沒有」），而且 hex dump 從那個位元組開始
印，而不是從視窗開頭印。

**1. ACK 視窗到底有沒有關係？** 一次 insmod，其餘完全維持上一次失敗的狀態 ——
10 MHz、`spi_rx_lshift=2`、`bcf_fgh100mhaamd.bin`：

```
spi_post_write_status_bytes=512
```

通過 → padding 就是那道牆。到 512 個位元組還是什麼都沒有 → padding 假說死掉，
連帶排除 Morse 自家的 OpenWrt 修正作為解釋，也讓要問維護者的問題更銳利。

**2. 2-bit 偏移是不是 init burst 自己造成的？** 那串 training clock 是故意在 CS
未選取的狀態下打出去的，靠翻 `SPI_CS_HIGH` 達成。如果這個翻轉在這顆核心上方向
相反，晶片就會把那些 clock 當成「已選取」收下，從一開始就多數了位元 —— 那正好會
產生一個固定、與時脈無關的位元偏移。掃描矩陣：

| `spi_init_cs_flip` | `spi_init_train_bytes` | 讀什麼 |
|---|---|---|
| Y | 18 | 基準（原本的行為） |
| Y | 0 / 2 / 17 / 20 | 偏移量會不會跟著 burst 長度動？ |
| N | 18 | 偏移取決於翻轉本身而不是 clock？ |
| N | 0 | 兩者都不是 |

看新增的 `init: mode=0x…` 判斷核心實際走了哪個分支，看 `morse rx:` 判斷偏移有沒有
移動。

**3. 差異還可能藏在哪？** 既然兩條樹的 SPI 原始碼逐位元組相同，剩下的就只有實際
生效的組態。在 Raspberry Pi OS 與 OpenMANET 兩邊各 dump 一份
`/proc/device-tree/soc/spi@7e204000/`（cs-gpios、pinctrl-0、dmas）以及
`/sys/kernel/debug/pinctrl/*/pinmux-pins` 裡 GPIO 7…11 的部分，然後 diff。
特別要看 GPIO8 有沒有同時被 mux 成 ALT0（native CE0）又被當成 GPIO chip select 用。

**4. 只有在第 1 項通過之後**，再一次一個變數地往 OpenMANET 的組態收斂：overlay 改
`spi-max-frequency = <50000000>`（這會讓驅動算出同樣的 250 位元組 inter-block
delay）→ `enable_ext_xtal_init=1` → `bcf=bcf_default.bin`。

**仍未解釋：2-bit RX 偏移。** 墊底是位元組層級的效果，造不出位元層級的框架錯位；
而且同一組硬體上，OpenMANET 完全不需要 `spi_rx_lshift`。第 2 項就是對它的正面攻擊。

---

## 2026-08-22 追蹤：四次實測後的定案

同一顆板子（SenseCAP M1 mPCIe 插槽 + Wio-WM6108，WM1302 HAT 佈線）、名義上同一個驅動 release（`mm6108-2.0.1` + `./patches`）、同一份韌體（`mm6108.bin` crc32 `0xbe7b5c8f`）。~~同一份 BCF（`bcf_fgh100mhaamd.bin` crc32 `0x941b2a82`）。~~ **2026-08-22 更正：OpenMANET 那次載入的是 `bcf_default.bin`（crc32 `0xf72450a7`），而且它的驅動是帶著額外 SPI patch 的 OpenWrt feed 建置 —— 見上一節。** 四列之間變動的是整份作業系統映像，不是只有核心：

| 核心 | 樹 / 打包來源 | 結果 |
|---|---|---|
| **6.6.138** | OpenWrt linux-6.6（OpenMANET 1.8.0）| ✅ `wlh0` 起在 SG 頻段 22 dBm |
| 6.6.51+rpt-rpi-v8 | raspberrypi/linux rpi-6.6.y（RPi OS Bookworm 2024-11-19）| ❌ CMD63 fail → `spi_rx_lshift=2` → CMD53 write 掛在 `0x00004050:4`、`ret:-71` |
| 6.12.93+rpt-rpi-v8 | raspberrypi/linux rpi-6.12.y（RPi OS Bookworm 2025-05）| ❌ 逐字元同指紋 |
| 6.18.34+rpt-rpi-v8 | raspberrypi/linux rpi-6.18.y（RPi OS Trixie）| ❌ 逐字元同指紋 |

**關鍵結論 —— 已被推翻，見上一節。** ~~問題是 `spi-bcm2835`（或 SPI core）**在不同核心樹之間的差異**，不是版本回歸。兩條樹共用主線 stable-tag 編號，但 raspberrypi/linux 的 patch stack 弄壞了 MM6108 走 GPIO CS 的行為，OpenWrt 的沒有。~~ 這一段要求的比對已經做了，檔案逐位元組相同；分歧在驅動的打包，不在核心。上面那張表作為**量測**依然成立 —— 錯的只是它的解讀。

**實用結論**：OpenMANET 1.8.0 仍是目前唯一實測能用的組合。但由此推出的「換核心就好」已不再成立：下面 (b)(c) 之所以被期待可行，前提正是「因為不走 raspberrypi/linux」，而那個前提現在已被推翻。單純換核心大概率沒有用；該先試的是修驅動在非 block 寫入時的 padding。
- (a) 拿 OpenMANET 當專用閘道器
- ~~(b) Ubuntu Server 或用主線核心的 Debian image（都未實測，但因為不走 raspberrypi/linux，理論上應該通）~~
- ~~(c) 自己編主線核心裝到 Bookworm 上~~

**收回**：下面的「接下來值得嘗試的方向」曾經建議「Raspberry Pi OS 上換一顆 6.6.x 核心應該就能動」—— 這個假設**錯了**。**任何** `+rpt-rpi-v8` 核心測過都是壞的。

**對外進度**：修正已送出為 [morse_driver#16](https://github.com/MorseMicro/morse_driver/pull/16) —— 三個 commit 對著 `main`，不含任何儀器，也沒有 `Signed-off-by`（那要你自己補）。兩個上游 issue 也都已載明可運作的結果 —— issue #9 的 comment 5381871720（延遲缺陷、三個下限、以及建議別再按時脈換算）與 issue #15 的 comment 5381871843（初始化修正已確認，但單獨不足）。`MorseMicro/morse_driver` 的 **issue #15** 已獨立承載 `morse_spi_initsequence()` 這個缺陷 —— 另開的原因是它比 #9 的主題廣，埋在留言裡會被錯過（`issue15-report.md` 追蹤其內容）。另外 issue #9 有六則追加 comment（v1 初次、v2 OpenMANET 反例、v3 Bookworm 6.12.93 同指紋、v4 Bookworm 6.6.51 收回 + 重新定性、v5 收回該定性 + 六項消除、v6 SPI 模式初始化的根本原因與修正）。維護者到本次更新為止仍未回覆。

完整證據在 `logs/`：
- `logs/2026-08-22-openmanet-1.8.0-*.log/.txt` —— 通過的案例
- `logs/2026-08-22-bookworm-6.6.51-*.log/.txt`
- `logs/2026-08-22-bookworm-6.12.93-*.log/.txt`

以下為達成此結論之前的原始移植紀錄。文末的「接下來值得嘗試的方向」現在已成歷史 —— (1) OpenMANET 已測、驅動了整個結論；(2) Seeed 的預建映像（`Wvirgil123/openwrt` v2.7-dev、核心 5.15、EKH01 腳位）是另一個 OpenWrt 樹的資料點候選，但和 Heltec HT-HC01P 映像一樣，都需要先把 overlay 改成 WM1302 HAT 腳位才能在 SenseCAP M1 上跑。

---

## 硬體：已確認正常
- 驅動透過 SPI 讀到的晶片識別：**chip ID 0x0306 = MM6108A1**
  （hw.h 裡的 `MORSE_DEVICE_ID(0x6, rev 3, silicon)`）。這不是推測 —— 是驅動
  自己的 `mm610x_chip_id_matches()` 接受了它。
- 腳位對應（Seeed WM1302 Pi HAT，M1 載板沿用）：
  MISO 9 / MOSI 10 / CLK 11 / CS 8、RESET_N 17、SPI_INT 5、WAKE 23、BUSY 24、
  插槽電源致能 18（M1 特有）。
- RESET_N 是低電位有效，而 `morse_hw_reset()` 是靠**浮接**該腳位來釋放的，
  所以 GPIO17 必須設成上拉，否則 BCM2711 預設的下拉會把模組一直壓在重置狀態。
  overlay 裡已處理。

## 軟體狀態
- 驅動：MorseMicro/morse_driver 的 `mm6108-2.0.1`，套上 ./patches 之後可在
  核心 6.18.34+rpt-rpi-v8 上乾淨編譯。
- 韌體裝在 /lib/firmware/morse：mm6108.bin 與 quectel 的各 BCF。晶片 OTP 回報
  的 board serial 是 "default"，所以 **BCF 必須用參數明確指定**：
  `bcf=bcf_fgh100mhaamd.bin`。
- 法規：驅動沒有 TW 區域。`SG` 是 920–925 MHz / 4 MHz / 22 dBm，與台灣 NCC 的
  開放頻段完全吻合。編譯時用 CONFIG_MORSE_COUNTRY=SG，載入時可用 country= 覆寫。

## 目前能動的部分
重置、讀 chip ID、載入韌體、載入 BCF —— 也就是整條 CMD52／CMD53 讀取路徑，
但**必須加上 `spi_rx_lshift=2`**。

## 未解的問題：晶片回應固定偏移 2 個 bit
晶片的每一筆回應都晚兩個位元時間，沒有對齊位元組邊界。這是在使用者空間對
/dev/spidev0.0 直接量的，與驅動無關：

- CMD0 + 正確 CRC7   → R1 = 0x01（idle）
- CMD0 + 打壞的 CRC  → R1 = 0x09（idle + CRC 錯誤）
- CMD13              → R1 = 0x05（idle + 非法指令）
- 不送指令           → 完全沒有回應（全 0xff）

所以晶片**完全正確地解析了我們的指令**（它驗了我們的 CRC7），只有它的**送出**
框架偏移了 2 個 bit。與時脈無關：400 kHz、1 MHz、20 MHz、50 MHz 完全相同，
因此不是傳播延遲造成的。

`spi_rx_lshift=N`（patch 新增，對應驅動既有的 `is_rk3288` 1-bit 右移 hack）
把接收重新對齊之後，讀取就正常了。

寫入依然失敗：CMD53 資料區塊寫入會拿到正確的 R1，但永遠等不到 data response
token —— dump 了 71 個位元組的視窗，全部是 0xff。然而同一筆交易在使用者空間
手動打的時候，**確實**會在 CRC 之後兩個位元組回傳 token 0x05
（SPI_RESPONSE_ACCEPTED）。兩條路徑的差異目前還沒釐清，最大嫌疑是卡片狀態
（idle 或已初始化）。`spi_tx_rshift=2` 會讓失敗點提前，所以送出方向的位元組
框架也有影響。

## 已排除（2026-08-19，全部是實機測試）
- SPI 時脈：400 kHz、1、10、20、50 MHz —— 每個速度下偏移都是相同的 2 bit。
- SPI mode 0/1/2/3 —— mode 1 是 1-bit 偏移而非 2-bit，沒有一個是乾淨的。
- 送出方向的位元對齊（`spi_tx_rshift`）：位移送出資料會直接打掛 CMD63，
  這反證了晶片的**接收**位元組框架本來就和我們一致，只有送出路徑會延遲。
- 加長寫入指令 R1 與資料 token 之間的等待（`spi_pre_token_bytes` 4/8/16/32）
  —— 無變化。
- ~~加寬 ACK 搜尋視窗（`spi_post_write_status_bytes` 4/8/16/32/64）—— 視窗到
  71 個位元組為止全是 0xff，晶片什麼都沒送。~~ **2026-08-22 收回：** Morse 自家
  的 OpenWrt patch 把這個視窗的下限訂在 250 個位元組，64 根本不足以構成有效測試。
- ~~`enable_ext_xtal_init=1` —— 無變化。~~ **2026-08-22 收回：** xtal 初始化序列
  本身就是由暫存器寫入組成的，寫入路徑壞掉時它根本跑不起來。修好 padding 之後
  要重測。
- 插槽冷斷電（GPIO18 拉低 3 秒，不只是脈衝 RESET_N）—— 偏移和寫入失敗都照舊，
  所以兩者都不是卡在某個殘留狀態。
- 驅動 tag 1.16.4。它在 6.18 上確實編不過，但原因不是乍看的那樣 —— 見下方
  「驅動版本已排除」，該段推翻了這裡先前的錯誤結論。

## 載板佈線的發現
在模組通電、重置已釋放的狀態下，用切換 BCM2711 內部上下拉再讀回電位的方式測試：
- GPIO5（SPI_INT，mPCIe pin 10）：被主動拉高 → 有接線。
- GPIO23（WAKE，mPCIe 33）與 GPIO24（BUSY，mPCIe 31）：兩種上下拉都跟著走
  → 浮接，也就是 M1 載板沒有接這兩支。

BUSY 是模組的輸出，有接的話應該會被驅動。M1 的 mPCIe 插槽看起來是 WM1302 Pi HAT
佈線的子集 —— 夠它原本要接的 LoRa 集中器用，但不足以支撐完整的 HaLow 交握。

但要注意這**不能**解釋寫入失敗：`gpios.busy` / `gpios.wake` 只被 ps.c（省電）
引用，完全不在傳輸路徑上。不過 overlay 裡的 `power-gpios` 還是該拿掉，免得
驅動對不存在的腳位啟用省電。

## 驅動版本已排除（2026-08-19，稍後）
1.17.9 **確實**能在核心 6.18 上編譯。先前「需要打過 Morse patch 的核心」這個
結論是錯的：唯一的阻礙是一個版本守衛。2.0.1 把

    #if KERNEL_VERSION(5, 10, 11) > MAC80211_VERSION_CODE

改成

    #if KERNEL_VERSION(5, 10, 11) > MAC80211_VERSION_CODE || \
        KERNEL_VERSION(6, 18, 0) <= MAC80211_VERSION_CODE

因為 mainline 6.18 又改了 S1G 的定義。把這一行複製到 1.17.9 的
dot11ah/s1g_ieee80211.h，再套上同樣那三個 spi.c patch，它就編得過了。

**接著 1.17.9 的行為與 2.0.1 完全相同**：一樣需要 spi_rx_lshift=2、一樣讀到
chip ID 0x0306、一樣載入韌體與 BCF，然後在第一筆 CMD53 寫入因 find_data_ack
失敗而中止。兩個獨立世代的驅動，症狀完全一致 → 這不是驅動的回歸問題，而是
匯流排／硬體層的互動。

另外也試過但無效：`spi_tx_lshift` 1/2/3（先前未測試的位移方向）。

## 來自 datasheet（SKU 109990565）
- VBAT 3.0–3.6 V 典型 3.3 V，但 **VDD_IO 是 1.62–3.6 V，典型 1.8/3.3 V** ——
  模組有一條獨立的 I/O 電源軌，而且可以是 1.8 V。M1 的 mPCIe 插槽在那條軌上
  餵什麼、有沒有餵，尚未驗證，是個未排除的嫌疑：M1 載板是為 WM1303 LoRa
  集中器設計的，不是為這顆模組。
- datasheet 有引用一張官方 pinout 圖，但 PDF 裡只嵌了縮圖；清晰版在 Seeed 的
  產品頁上。

## 決定性事實：這是官方支援硬體上的上游未解 bug
MorseMicro/morse_driver **issue #9**，2026-02-22 開啟，至今未有維護者回覆：

  Raspberry Pi 4 Model B + **原廠 Seeed WM1302 Pi HAT** + Wio-WM6108
  （FGH100M-H）+ **打過 Morse patch 的核心 6.12.25-v8-morse+** + Raspberry Pi
  OS Trixie。韌體與 BCF 都載入成功，然後：

      morse_spi_cmd53_write failed
      cmd53_write fn=2 0x00000000:10 ... (ret:-71)
      morse_firmware_init failed: -5

  回報者試過 50 MHz 降到 2.5 MHz、SPI mode 0 與 3、多個 BCF、以及重置腳本，
  全部無解。

所以**買 WM1302 Pi HAT 並不會解決這個問題** —— 那個組態失敗的方式一模一樣。
載板不是元兇，核心 patch 也不是。

所有有記載的成功案例都在 **Pi 5**（RP1 SPI 控制器）上，而且連 Pi 5 在持續負載
下也會出現 `cmd53_write ret:-71`。Morse 社群討論串裡**沒有任何人**回報在
Pi 4 / bcm2835 SPI 控制器上成功。

Seeed 自己的 getting-started 頁面只支援一種組態：Raspberry Pi 4 Model B 跑他們
的**預建 OpenWrt 映像**，燒錄到 microSD。他們同時註明本裝置「只支援美國，
不支援其他國家或地區」。

## 接下來值得嘗試的方向，依期望值排序
1. **OpenMANET 的 `rpi4-mm6108-spi` 映像**。它的 device tree 本來就是 WM1302 HAT
   腳位、GPIO17 也已設上拉，內附的驅動 release 與韌體都和這裡編的相同，所以
   唯一剩下的變數就是核心與其 `spi-bcm2835` 世代（那邊 6.6.138，這裡 6.18.34）。
   只需要補上插槽電源那一行（`gpio=18=op,dh`）。這條線索來自 issue #9 上
   not5erpe 的建議；該版本裡 rpi4-mm6108-spi 是下載數遠高於其他資產的檔案，
   顯示這個組合確實有人在用。
2. Seeed 自己的預建映像。那是 Seeed 唯一有文件的組態，而且
   它會帶進一個完全不同的核心 —— 5.15.189，相對於這裡的 6.18.34 —— 等於順便
   測了不同世代的 `spi-bcm2835`，而這是在現行系統上無法改變的變數。
   `overlays/openwrt/` 有修正過的 overlay 和一支套用到剛燒好開機分割區的腳本；
   **原版映像不改是不會動的**，因為它的 overlay 是給 Morse EKH01 腳位用的。
   注意那些映像裡的驅動是原版、沒有 `spi_rx_lshift`，所以如果偏移依然存在，
   它會停在 CMD63 而根本到不了寫入階段。**兩種結果都是有價值的答案。**
3. 釐清那個 2-bit 偏移是來自 BCM2835 SPI 控制器還是模組本身 —— 驅動本來就為
   RK3288 帶了 1-bit 位移的補償，控制器側造成偏移是有前例的。
4. 若以上都不成，這顆模組配 Pi 4 可能就是不能用。所有有記載的成功都在
   Pi 5 / RP1 上，而 USB 介面的 HaLow 裝置可以完全繞開 SPI 傳輸層。

## 這裡的所有變更都不會在重開機後留存
device tree overlay 只在執行期套用，config.txt 未曾更動。重開機後機器會回到
單純的 spidev0.0/0.1，沒有載入 morse 驅動。裝在 ~/halow 之外的檔案只有
/lib/firmware/morse/* 而已。
