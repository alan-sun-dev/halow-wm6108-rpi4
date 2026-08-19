# 在 SenseCAP M1 上實測 OpenMANET 映像

*[English](TESTING.md)*

這份是寫來**在手機上看**的 —— 因為 Pi 跑 OpenWrt 的時候，存放這些筆記的系統是關著的。

## 卡片裡是什麼

`openmanet-1.8.0-rpi4-mm6108-spi-squashfs-sysupgrade.img.gz`
sha256 `461aea8cc2805f64e83e68d1f45acdedad7bef5560861926a5de79a3489d8316`
來源 <https://github.com/OpenMANET/firmware/releases>（tag 1.8.0）

OpenWrt 24.10、核心 6.6.138、morse 驅動 `0-rel_mm6108_2_0_1_2026_Jun_11`。
它的 overlay 本來就是 WM1302 HAT 腳位 —— RESET 在 gpio17（已設上拉）、
SPI_INT 在 gpio5、WAKE/BUSY 在 gpio23/24、CS 在 gpio8，50 MHz。

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
| `Morse Micro SPI device found, chip ID=0x0306`、韌體與 BCF 載入、出現 phy | **成功。** 2-bit 偏移是 6.18 核心的 `spi-bcm2835` 造成的，不是硬體。 |
| `failed to init SPI with CMD63` | 偏移仍在。**不是** SPI 控制器驅動的問題，是硬體層。 |
| 韌體與 BCF 載入後出現 `cmd53_write ... (ret:-71)`、`find_data_ack failed` | 與 morse_driver issue #9 相同，等於跨兩個作業系統、三個核心都重現。 |

這份映像裡的驅動是原版、**沒有 `spi_rx_lshift`**，所以偏移若還在，它會停在
CMD63、根本走不到寫入階段。三種結果都是有價值的答案。

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
