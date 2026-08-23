# Wio-WM6108（MM6108A1）在 SenseCAP M1 上的移植狀態，2026-08-19

*[English](NOTES.md)*

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

**板子 `E4:5F:01:52:55:04` 現在是乾淨且可運作的狀態**，位於 `192.168.200.182`：

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
