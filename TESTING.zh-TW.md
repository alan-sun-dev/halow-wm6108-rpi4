# 實機測試流程

*[English](TESTING.md)*

兩份流程。第一份是待執行的；第二份保留下來，因為它是目前唯一產出通過結果的測試。

---

# 1. 在 Raspberry Pi OS 上重測：ACK 視窗與 init burst

**狀態：待執行。** 這是 2026-08-22 的發現所要求的測試。全程**不需要換卡也不需要
重刷**，直接在機器裡現有的那張 Raspberry Pi OS 卡上跑。

## 這在測什麼

兩個獨立的問題，依序：

1. **CMD53 寫入的 ACK 視窗到底有沒有夠寬過？** Morse 自家的 OpenWrt 建置，在非
   block 寫入的 CRC 之後會墊至少 250 個位元組。原版 `mm6108-2.0.1` 預設是 4，而
   這裡測過最寬的只有 64。
2. **2-bit RX 偏移是不是 init training burst 自己造成的？** 那串 clock 是故意在
   CS 未選取的狀態下送出的，靠翻 `SPI_CS_HIGH` 達成。如果這個翻轉在這顆核心上方向
   相反，晶片就會把它們當成「已選取」而開始數位元，回應框架從一開始就錯開 ——
   那正好就是量到的那種固定、與時脈無關的偏移。

兩者現在都是模組參數。推導過程見 [NOTES.zh-TW.md](NOTES.zh-TW.md)。

## 前置條件

三張 Raspberry Pi OS 卡（Bookworm 6.6.51、Bookworm 6.12.93、Trixie 6.18.34）
任一張都可以 —— 失敗指紋在三者上完全相同，用機器裡現有的那張就好。必須成立的是：

- 有對應的 `linux-headers-$(uname -r)`；
- `/lib/firmware/morse/` 裡有 `mm6108.bin` 與 `bcf_fgh100mhaamd.bin`；
- `/boot/firmware/config.txt` 有 `dtparam=spi=on` 與 `dtoverlay=mm610x-spi-sensecap`；
- 有一份 `mm6108-2.0.1` tag 的 `morse_driver` worktree（下面以
  `~/halow/morse_driver` 稱之）。

因為 overlay 寫在 `config.txt` 裡，模組開機時會自動載入並先失敗一次，所以下面
每一次執行都從 `rmmod` 開始。

## 用最新的 patch 重編

`patches/morse-driver-2.0.1-rpi-spi.patch` 在 2026-08-22 改過 —— 現在帶了新的參數
和改寫過的 ACK 視窗失敗輸出。從乾淨的 `spi.c` 重新套用：

```sh
cd ~/halow/morse_driver
git checkout -- spi.c
patch -p1 < ~/halow-wm6108-rpi4/patches/morse-driver-2.0.1-rpi-spi.patch

make KERNEL_SRC=/lib/modules/$(uname -r)/build \
     CONFIG_WLAN_VENDOR_MORSE=m CONFIG_MORSE_SPI=y \
     CONFIG_MORSE_USER_ACCESS=y CONFIG_MORSE_VENDOR_COMMAND=y -j4
```

## 跑測試用的小工具

每一次執行的形狀都一樣，先在 shell 裡定義一次：

```sh
run() {                      # 用法：run <標籤> [額外的模組參數...]
  local tag="$1"; shift
  sudo rmmod morse 2>/dev/null
  sudo dmesg -C
  sudo insmod morse.ko country=SG bcf=bcf_fgh100mhaamd.bin "$@"
  sleep 5
  dmesg > ~/retest-"$tag".log
  grep -iE 'morse|spi' ~/retest-"$tag".log | tail -30
}
```

其餘一律維持上一次失敗時的組態 —— overlay 10 MHz、`bcf_fgh100mhaamd.bin`、
`country=SG` —— 這樣每一次執行才只動一個變數。

## 第 0 步 —— 基準線，只用預設值

```sh
run baseline spi_rx_lshift=2
```

新參數的預設值等同原本行為，所以這一次**必須完全重現舊的失敗**。如果沒有，就停
下來：那代表 patch 改到了不該改的東西，後面所有結果都無法解讀。

預期會與 `logs/2026-08-22-bookworm-6.6.51-lshift-dmesg.log` 逐字相同：

```
morse_spi spi0.0: Loaded firmware from morse/mm6108.bin, size 468304, crc32 0xbe7b5c8f
morse_spi spi0.0: spi: cmd53_write fn=1 0x00004050:4 r=0x10050002 b=0xffffffff (ret:-71)
```

這個版本新增、就算在基準線這一次也值得讀的三行：

```
morse_spi spi0.0: init: mode=0x… cs_high_default=… train=18 flip=1
morse_spi spi0.0: init: CS deasserted for training, mode=0x…
morse_spi spi0.0: init: CS polarity restored, mode=0x…
```

它們會告訴你這顆核心實際走的是哪一條 `SPI_CS_HIGH` 分支 —— 在此之前那是推論，
不是量測。把它們記下來。

## 第 1 步 —— ACK 視窗到底有沒有關係？

相對基準線只動一個變數：

```sh
run window512 spi_rx_lshift=2 spi_post_write_status_bytes=512
```

| 你看到什麼 | 代表什麼 |
|---|---|
| 韌體與 BCF 載入，沒有 `cmd53_write … ret:-71`，出現 phy | **padding 就是那道牆。** Morse 只放在 OpenWrt 的 patch 就是修正，release tarball 的預設值 4 就是 bug。整串 issue #9 的敘事要改寫。 |
| `find_data_ack failed: first non-0xff 0x05 … at +N of 512`，且 N > 64 | 結論相同，而且現在知道驅動實際需要多少。**把 N 記下來。** |
| `find_data_ack failed: first non-0xff 0x… (code 0x…) at +N of 512`，但那個位元組不是 accept token | 晶片有回應，只是回了別的 —— 讀後面的 hex dump，這和「完全沒回應」是不同的失敗。 |
| `find_data_ack failed: no non-0xff byte in the 512 bytes clocked after CRC` | **padding 假說死掉。** 這是很強的否定結果：它同時排除了 Morse 自家的修正作為解釋，本身就值得回報。 |

如果這一步通過，可以直接跳到第 3 步 —— 但第 2 步還是要跑，因為偏移是另一個獨立的
缺陷，它不會因此消失。

## 第 2 步 —— 偏移是不是 init burst 自己造成的？

七次執行。每一次都讀 `morse rx:` 並記下偏移量 —— 基準特徵是 `c0 7f ff ff`，
也就是晚 2 個位元。

```sh
run flipY_train18 spi_rx_lshift=2                                        # = 基準線
run flipY_train0  spi_rx_lshift=2 spi_init_train_bytes=0
run flipY_train2  spi_rx_lshift=2 spi_init_train_bytes=2
run flipY_train17 spi_rx_lshift=2 spi_init_train_bytes=17
run flipY_train20 spi_rx_lshift=2 spi_init_train_bytes=20
run flipN_train18 spi_rx_lshift=2 spi_init_cs_flip=N
run flipN_train0  spi_rx_lshift=2 spi_init_cs_flip=N spi_init_train_bytes=0
```

| 你看到什麼 | 代表什麼 |
|---|---|
| 偏移量隨 `spi_init_train_bytes` 變動 | **抓到了。** 晶片在數那些 training clock，也就是 CS 翻轉在這顆核心上方向錯了。 |
| `spi_init_cs_flip=N` 時偏移消失，但 `train=0` 時不會 | 問題出在翻轉本身，不是那些 clock。 |
| 某一次執行原本會過，加了 `spi_rx_lshift=2` 反而壞掉 | 同一個發現的反面 —— 那一次沒有偏移，所以補償變成過度校正。把它拿掉 `spi_rx_lshift` 再跑一次。 |
| 七次的偏移都是 `c0 7f` | init 序列洗清嫌疑。偏移發生在驅動所有行為的上游，第 3 步變成下一條線索。 |

## 第 3 步 —— 把實際生效的組態拿去和 OpenMANET 比

既然兩條核心樹的 SPI 原始碼已知逐位元組相同，剩下能差的就只有執行時的組態。
在 Raspberry Pi OS 上擷取：

```sh
dtc -I fs -O dts /proc/device-tree/soc/spi@7e204000 2>/dev/null > ~/retest-dt-rpios.dts
sudo cat /sys/kernel/debug/pinctrl/*gpio/pinmux-pins | sed -n '/pin 7 /,/pin 12 /p'
```

然後在 OpenMANET 卡上做同樣的事（那邊可能沒有 `dtc`，直接 dump 原始屬性）：

```sh
for f in /proc/device-tree/soc/spi@7e204000/*; do echo "== $f"; hexdump -C "$f" | head -3; done
cat /sys/kernel/debug/pinctrl/*gpio/pinmux-pins | sed -n '/pin 7 /,/pin 12 /p'
```

要看的是：`cs-gpios`、`pinctrl-0`、`dmas`，尤其是 **GPIO8 有沒有同時被 mux 成
ALT0（native CE0）又被當成 GPIO chip select 用**。同一支腳被兩個東西驅動，可以解釋
很多事。

## 第 4 步 —— 只有在第 1 步通過之後才做

一次一個變數地往 OpenMANET 的組態收斂，這樣真正有影響的那一項才歸得了因：

1. overlay 改 `spi-max-frequency = <50000000>` —— 光這一項就會讓驅動算出的
   `inter_block_delay_bytes` 從 50 變成 250；
2. 再開 `enable_ext_xtal_init=1` —— 必須排在寫入通了之後，因為
   `mm610x_ext_xtal_init()` 本身就是一串暫存器寫入；
3. 再改 `bcf=bcf_default.bin` —— 那才是通過的那次 OpenMANET 實際載入的檔案。

## 歸檔結果

和 `logs/` 裡現有的條目同一種形狀：

```sh
cp ~/retest-*.log <repo>/logs/
uname -r; cat /etc/os-release; dpkg -l | grep linux-image
```

旁邊寫一份 `2026-XX-XX-<映像>-environment.txt`，記錄核心、映像、驅動 tag 與 patch、
韌體 CRC32、每一次執行完整的 `insmod` 指令，以及結果。現有的
`logs/2026-08-22-bookworm-6.6.51-environment.txt` 就是範本。

## 發射任何訊號之前

上面每一行指令都帶了 `country=SG`，而且**不是可選的**：驅動沒有 `TW` 區域，而
`SG`（920–925 MHz / 4 MHz / 22 dBm）是唯一符合台灣 NCC 開放頻段的內建區域。
**先確認 radio 有 attach，再開 AP。**

---

# 2. 已完成：在 SenseCAP M1 上實測 OpenMANET 映像

**狀態：已於 2026-08-22 完成 —— 通過。** `wlh0` 起在 SG 頻段、22 dBm。保留供
重現用；結果已歸檔在 `logs/2026-08-22-openmanet-1.8.0-*`。

這份是寫來**在手機上看**的 —— 因為 Pi 跑 OpenWrt 的時候，存放這些筆記的系統是關著的。

## 卡片裡是什麼

`openmanet-1.8.0-rpi4-mm6108-spi-squashfs-sysupgrade.img.gz`
sha256 `461aea8cc2805f64e83e68d1f45acdedad7bef5560861926a5de79a3489d8316`
來源 <https://github.com/OpenMANET/firmware/releases>（tag 1.8.0）

OpenWrt 24.10、核心 6.6.138、morse 驅動 `0-rel_mm6108_2_0_1_2026_Jun_11`。
它的 overlay 本來就是 WM1302 HAT 腳位 —— RESET 在 gpio17（已設上拉）、
SPI_INT 在 gpio5、WAKE/BUSY 在 gpio23/24、CS 在 gpio8，50 MHz。

注意那個驅動**不是**單純的 git tag：映像是透過 `MorseMicro/morse-feed` 建的，
而那個 feed 會套用不存在於 tarball 的 SPI patch。這件事後來很關鍵 ——
見 [NOTES.zh-TW.md](NOTES.zh-TW.md)。

`config.txt` 只加了一行，也是唯一的改動：

```
gpio=18=op,dh
```

那是 SenseCAP M1 的 mPCIe 插槽電源致能。它不屬於 HAT 的腳位定義，也不在任何
上游 overlay 裡，**沒有這一行插槽就沒電**，模組在匯流排上完全看不到。

## 換卡

1. 先正常關機：`sudo poweroff`。**不要直接拔電源** —— 原本那張卡上有可運作的
   LoRaWAN 閘道器。
2. 拔電源，打開外殼，換上新卡。
3. 接網路線 —— 先看下一節。
4. 上電。

**原本那張卡完全不會被修改。** 插回去就恢復原狀，一切照舊。

## 怎麼連進去

OpenMANET 開機後在 **192.168.1.1**，而且**它自己會跑 DHCP 伺服器**，所以不要
接進已經有 DHCP 的家用網路（會和你的 Unifi 打架）。用網路線**直接接一台筆電**，
筆電網卡設固定 IP：

    IP 192.168.1.100   遮罩 255.255.255.0

然後：

- 網頁介面：<http://192.168.1.1>
- SSH：`ssh root@192.168.1.1` —— 全新映像的 **root 沒有密碼**，直接進得去

## 建議：在那台筆電上跑 Claude Code，SSH 進來

反正你已經要拿一台筆電用網路線直連了，就在那台筆電上工作，不要試圖把 Claude Code
裝到 OpenWrt 上：

```sh
git clone https://github.com/alan-sun-dev/halow-wm6108-rpi4
cd halow-wm6108-rpi4
claude
```

然後從筆電 `ssh root@192.168.1.1` 跑下面的指令，即時一起判讀輸出。

這樣拿到的脈絡比記憶檔更完整 —— 記憶是壓縮過的摘要，這個倉庫是全部細節，
包含每個已排除的假設和實測數據。

**為什麼不要在 OpenWrt 上裝 Claude Code：**

- OpenWrt 用 **musl libc 而非 glibc**，Claude Code 發佈的原生執行檔與相依模組
  是對 glibc 建的，這是最根本的一道牆
- OpenWrt 不在支援平台清單裡
- 需要 Node.js，而 musl 上 `npm install` 原生相依套件很容易失敗
- 這份映像預設是 LAN `192.168.1.1` 的網路設備角色，要先自己設好 WAN 才能連外
- 還要重新登入帳號

就算全部克服，這台 Pi 4 還得同時跑 OpenWrt、Node.js 和你要測的 HaLow 驅動。
那些時間本來該花在讀 dmesg 上。

**真的要試的話，先跑完測試、把 dmesg 存下來，再去折騰安裝。** 萬一裝不起來，
至少該拿到的資料已經到手。卡上的 `/boot/claude-memory/` 有記憶檔副本，進去之後
直接跟它說「讀 /boot/claude-memory/ 底下的檔案」即可，不需要放在特定路徑。

## 三行關鍵指令

```sh
dmesg | grep -i morse
ls /sys/class/ieee80211/
iw dev
```

| 你看到什麼 | 代表什麼 |
|---|---|
| `Morse Micro SPI device found, chip ID=0x0306`、韌體與 BCF 載入、出現 phy | 這份映像上可用。*（實際結果就是這一項。）* |
| `failed to init SPI with CMD63` | 偏移仍在。 |
| 韌體與 BCF 載入後出現 `cmd53_write ... (ret:-71)`、`find_data_ack failed` | 與 morse_driver issue #9 相同。 |

這份映像裡的驅動就 `spi_rx_lshift` 而言是原版、**根本沒有這個參數**，所以偏移若
還在，它會停在 CMD63、根本走不到寫入階段。它沒有停 —— 這就是為什麼可以確定這份
映像上沒有偏移。

## 換回去之前先把輸出留下來

```sh
dmesg | grep -i -A2 -B2 morse > /tmp/morse.log
cat /tmp/morse.log
```

拍照或複製起來。**這整件事就是為了拿到這段輸出。**

## 發射任何訊號之前

這份映像預設是美規區域，902–928 MHz。台灣 NCC 只開放 **920–925 MHz**。
驅動的 `SG` 區域是 920–925 MHz / 4 MHz / 22 dBm，正好吻合：

```sh
uci set wireless.@wifi-device[0].country='SG'
uci commit wireless
wifi reload
```

**先確認 radio 有 attach，再設區域，最後才開 AP。**

## 怎麼回去

關機，把原本那張卡換回去，開機。LoRaWAN 閘道器、`~/halow` 底下的驅動工作、
完整的移植紀錄全都還在 —— 那張卡上什麼都沒被動過。
