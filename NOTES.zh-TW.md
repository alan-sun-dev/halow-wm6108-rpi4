# Wio-WM6108（MM6108A1）在 SenseCAP M1 上的移植狀態，2026-08-19

*[English](NOTES.md)*

## 2026-08-22 追蹤：四次實測後的定案

同一顆板子（SenseCAP M1 mPCIe 插槽 + Wio-WM6108，WM1302 HAT 佈線）、同一個驅動 release（`mm6108-2.0.1` + `./patches`）、同一份韌體與 BCF（`mm6108.bin` crc32 `0xbe7b5c8f`、`bcf_fgh100mhaamd.bin` crc32 `0x941b2a82`）。**只變動核心與其 patch stack**：

| 核心 | 樹 / 打包來源 | 結果 |
|---|---|---|
| **6.6.138** | OpenWrt linux-6.6（OpenMANET 1.8.0）| ✅ `wlh0` 起在 SG 頻段 22 dBm |
| 6.6.51+rpt-rpi-v8 | raspberrypi/linux rpi-6.6.y（RPi OS Bookworm 2024-11-19）| ❌ CMD63 fail → `spi_rx_lshift=2` → CMD53 write 掛在 `0x00004050:4`、`ret:-71` |
| 6.12.93+rpt-rpi-v8 | raspberrypi/linux rpi-6.12.y（RPi OS Bookworm 2025-05）| ❌ 逐字元同指紋 |
| 6.18.34+rpt-rpi-v8 | raspberrypi/linux rpi-6.18.y（RPi OS Trixie）| ❌ 逐字元同指紋 |

**關鍵結論**：問題是 `spi-bcm2835`（或 SPI core）**在不同核心樹之間的差異**，不是版本回歸。兩條樹共用主線 stable-tag 編號，但 raspberrypi/linux 的 patch stack 弄壞了 MM6108 走 GPIO CS 的行為，OpenWrt 的沒有。**在 raspberrypi/linux 樹裡 bisect 版本是錯的策略** —— 該做的比對是兩條樹在同一 stable tag 上的 `drivers/spi/spi-bcm2835.c` 與相關 SPI-core 檔案。

**實用結論**：OpenMANET 1.8.0 是目前唯一實測能用的組合。任何 stock Raspberry Pi OS 都不能推薦，直到這個 bug 在上游被修好。想要 Debian 環境 + HaLow，選項是：
- (a) 拿 OpenMANET 當專用閘道器
- (b) Ubuntu Server 或用主線核心的 Debian image（都未實測，但因為不走 raspberrypi/linux，理論上應該通）
- (c) 自己編主線核心裝到 Bookworm 上

**收回**：下面的「接下來值得嘗試的方向」曾經建議「Raspberry Pi OS 上換一顆 6.6.x 核心應該就能動」—— 這個假設**錯了**。**任何** `+rpt-rpi-v8` 核心測過都是壞的。

**對外進度**：`MorseMicro/morse_driver` issue #9 目前有四則追加 comment（v1 初次、v2 OpenMANET 反例、v3 Bookworm 6.12.93 同指紋、v4 Bookworm 6.6.51 收回 + 重新定性為核心樹差異）。維護者到本次更新為止仍未回覆。

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
- 加寬 ACK 搜尋視窗（`spi_post_write_status_bytes` 4/8/16/32/64）—— 視窗到
  71 個位元組為止全是 0xff，晶片什麼都沒送。
- `enable_ext_xtal_init=1` —— 無變化。
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
