# Wio-WM6108（MM6108A1）在 SenseCAP M1 上的移植狀態，2026-08-19

*[English](NOTES.md)*

## 2026-08-25 —— HT-HC01P 移植到 Raspberry Pi OS，缺陷 B 在第二塊板子上重現

Heltec HT-HC01P（Pi HAT 上的 MM6108**A2**，SPI）現在跑的是 **Raspberry Pi OS
bookworm 6.6.51 + morse_driver 2.0.1 加本 repo 的三支 `patches/upstream/` 修正**，
以 SAE + PMF 關聯上 OpenMANET AP，拿到 DHCP，AP 端把這條鏈路評為 MCS7。這是這套
stack 的**第二塊獨立硬體** —— 不同模組、不同晶片版本、不同載板，同一個核心、同一組
修正。

移植是換 SD 卡完成的。Heltec 的 OpenWrt 安裝完整留在它自己那張卡上，沒有動過。

```
hc01p   Raspberry Pi 4B Rev 1.4，序號 100000004dd92ccc
        Raspberry Pi OS bookworm，核心 6.6.51+rpt-rpi-v8
        wlan0 192.168.108.13 (Sun)     wlan1 10.41.0.216/16 (HaLow)
        MAC 0c:bf:74:40:8e:91          SPI errors 0, timedout 0
```

### 值得做的那個實驗：缺陷 B 在第二塊板子、而且是在原廠設定下重現

在裝上能用的驅動之前，先用**只套 patch 1**的 2.0.1（不套 patch 2、不套 patch 3）
probe 了一次。結果跟事前寫下的預測完全一致：

```
Resetting Morse Chip / Done
morse_spi spi0.0: morse_spi_probe: failed to init SPI with CMD63 (ret:-71)
```

接著用同一份程式加四個 `dev_info`／`print_hex_dump`，確認這是**同一個機制**而不只是
同一個錯誤碼：

```
init: entry mode=0x4 cs_high_default=1 train=18
init: CS deasserted for training, mode=0x4      <-- 應該是 0x0
init: CS polarity restored, mode=0x4
cmd63 rx: ff ff ff ff ff ff ff ff c0 3f ff ff ff ff ff ff
cmd63 rx: ff ff ff ff ff ff ff ff c0 7f ff ff ff ff ff ff
cmd63 rx: ff ff ff ff ff ff ff ff c0 7f ff ff ff ff ff ff
```

跟 `issue15-report.md` 裡 Wio-WM6108 那份 trace 逐欄相同。`cs_high_default=1` 是關鍵
那一格：核心在函式執行**之前**就已經設好 `SPI_CS_HIGH`，所以那個翻轉在兩個方向上都
是空操作，training burst 是帶著晶片被選中送出去的。

**這次比第一次更有說服力的地方**：這裡的 device tree 是 Heltec 的，逐位元組相同 ——
`spi-max-frequency` 50 MHz、`reset-gpios` flag 0、單一 `cs-gpios`。那正是缺陷 3 不會
重現、舊的 `reset-gpios` 說法也不適用的那組參考設定，所以失敗只可能來自缺陷 B。在
SenseCAP M1 上那支 overlay 是 10 MHz + flag 1，三個缺陷同時在場。現在變因隔離乾淨了。

兩次重現之間換掉的軸：模組（Wio-WM6108／Heltec HT-HC01 V2）、晶片（MM6108**A1**／
**A2**）、載板（SenseCAP M1 mPCIe／Heltec Pi HAT）、chip select 數（二／一）、device
tree（本 repo 的／原廠的）。**沒有**換的是核心，兩次都是 6.6.51。所以這仍然是「一個
核心、兩種硬體」，對上游就要這樣講。

分析文件 §7 寫「若未修正的 2.0.1 在這片 HAT 的 6.6 上 probe 成功，L1 就被推翻」。它
沒有成功。**L1 從推論升格為實測。**

### 一個值得留著的解碼：晶片答對了，是主機把框抓錯

三次 CMD63 嘗試回來一次 `c0 3f`、兩次 `c0 7f`。位元組邊界抓早兩個 bit 的話，
`主機位元組 = 前一位元組的末 2 bit ++ 本位元組的前 6 bit`：

```
prev=ff cur=01  ->  11 000000 = c0 ,  01 111111 = 7f     「c0 7f」還原成 01
prev=ff cur=00  ->  11 000000 = c0 ,  00 111111 = 3f     「c0 3f」還原成 00
```

兩個都是合法的 R1，而 `00` 正是 CMD63 的**成功**回應 —— 晶片第一次就答對了，主機看
不見。再加上整個失敗的 probe 期間 SPI 控制器回報 `errors 0 timedout 0`，這正面回答了
「該不會是你接線有問題」這種讀法：電氣上什麼問題都沒有，是位元組框差了兩個 bit。

### B1 在第二台機器上確認，而且是編譯失敗

在套 patch 1 之前，先用原始的 `mm6108-2.0.1` 在這塊板子的 6.6.51 上編一次：

```
spi.c:1519:2: error: #warning "SPI_CONTROLLER_ENABLE_CS_GPIOD macro not defined" [-Werror=cpp]
make: *** [Makefile:199: all] Error 2
```

沒有 `morse.ko`。套上 patch 1 之後同一道指令零 error 零 warning。B1 不是「只影響
mainline」的註腳。

### 三支 patch 全套之後：probe、firmware、BCF、關聯

```
Loaded firmware from morse/mm6108.bin,   size 468304, crc32 0xbe7b5c8f
Loaded BCF from morse/bcf_HC01_V2_H.bin, size 1170,   crc32 0x389a48c4
SW version: 2.0.1    HW version: 0x00000406      <- MM6108A2，跟 V2 完全相符
```

同一台機器、同一天、同一個 device tree、同一顆 firmware、同一個 BCF。失敗與成功之間
唯一的變因是 `spi.c`。

關聯第一次就成功，沒有 `CONN_FAILED`、沒有 backoff：

```
SME: Trying to authenticate with 3c:1a:cc:70:3f:ca
PMKSA-CACHE-ADDED / Associated with 3c:1a:cc:70:3f:ca
WPA: Key negotiation completed [PTK=CCMP GTK=CCMP]     pmf=2, BIP, sae_group=19, sae_h2e=1
dhcp4: new lease, address=10.41.0.216
```

從 `nmcli connection up` 到 `activated` 約 2.4 秒。

### U1 結案，而且是靠 RF 對稱性那一關結掉的

`bcf_HC01_V2_H.bin`（為驅動 1.15.3 出的）**可以配 firmware 2.0 和驅動 2.0.1**。分析
文件點名的那個風險 —— 它的 `.board_config` 固定在 `0x8011fa80`，而驅動是照 **firmware**
TLV 決定的視窗放置各區段 —— 沒有發生。

只有 AP 端的檢查能確立這件事，因為錯的 BCF 在接收側會通過前面每一關。AP 端：

```
Station 0c:bf:74:40:8e:91   signal -1 dBm   rx packets 73   tx retries 0   tx failed 0
mmrc: MCS7 / 4 MHz / SGI，機率 100%，49/49，0 個 look-around 封包
```

作為對照，同一份 dump、同一時刻的 HT-H7608 是 `tx retries 438 / tx failed 32`，卡在
MCS0 的 1–2 MHz，181 個封包裡 137 個花在 look-around。那才是勉強的鏈路長什麼樣；這條
不是。

`-1 dBm` 落在削頂區 —— 這一關要的是**合理**的 RSSI 而不是精確的，真正扛住論證的是封包
計數。

Ping 全部 0% 遺失：Mac→station 4.5 ms、AP→station 5.4 ms、station→AP 3.5 ms、
station→station（到 `10.41.0.208`）9.3 ms。

### 持久化，以及把省電機制搬離模組參數

驅動安裝到 `/lib/modules/6.6.51+rpt-rpi-v8/updates/`，跑過 `depmod -a`，
`/etc/modprobe.d/morse.conf`：

```
options morse country=SG bcf=bcf_HC01_V2_H.bin macaddr_suffix=40:8e:91
```

**`enable_ps` 刻意不寫。** 驅動自己會印 *"enable_ps modparam must only be used for
testing - use iw set power_save"*，所以省電改由 `halow` NetworkManager profile 的
`wifi.powersave=2` 關掉 —— 就是另外三塊板子已經驗過會持久的那個機制。重開機之後：

```
enable_ps 模組參數 : 2        <- 驅動自己的預設值，我們的覆寫已經拿掉
iw get power_save  : off      <- 所以這只可能來自 NetworkManager
NM profile         : disable
```

而且是行為上的驗證，不只是讀回設定值：**20/20 ping，平均 4.487 ms，mdev 0.163 ms**。
一個有一半時間在睡的接收器做不出 0.163 ms 的抖動。同一塊板子在 OpenWrt 下開著省電時
是 105.4 ms／mdev 66.2。

無人介入的開機序列：

```
t = 7.77 s  dot11ah 註冊
t = 8.45 s  morse 註冊、讀 device tree、Resetting Morse Chip
t = 8.60 s  firmware 載入
t = 8.61 s  BCF 載入
```

之後 NetworkManager 自行關聯並取得租約。（Heltec 的 OpenWrt 是 6.65 s 載入 BCF；差別
在 systemd，不在驅動。）

### 三個比原計畫更好的做法

- **NetworkManager profile 綁在 MAC 上，不綁 `interface-name`。** HaLow 介面名稱在這
  塊板子上不穩定 —— `brcmfmac` 會跟它搶 `wlan0` —— 所以站台那塊板子
  `interface-name=wlan1` 的寫法在這裡是脆弱的。綁 `0C:BF:74:40:8E:91` 就完全不依賴名
  稱，而這只有在下一項成立時才可行。
- **`macaddr_suffix=40:8e:91` 是必要的，缺了它是個陷阱。** 沒有它驅動每次載入都會自己
  生一個**隨機** MAC —— 第一次 probe 出來是 `c2:d2:3d:87:dd:cd`。那會讓 AP 的 station
  表和 DHCP 租約每次開機都翻新。加上它模組就拿回自己的 `0c:bf:74:40:8e:91`，這也是為
  什麼 DHCP 給回了 OpenWrt 安裝時的同一個 `10.41.0.216`，以及為什麼 2026-08-24 那批
  AP 端數據仍然可以直接對照。
- **`ipv4.never-default yes` 一開始就設**，而不是等 HaLow profile 偷走預設路由之後才
  補 —— 站台那塊板子就是踩過才知道的。

### 過程中的坑，沒有一個跟 SPI 有關

- **`morse_driver` 有 git submodule。** `mmrc-submodule`
  （`MorseMicro/mm_rate_control`，commit `da14255`）。沒有跑
  `git submodule update --init --recursive` 的話編譯會死在
  `mmrc-submodule/src/core/mmrc.h: No such file or directory`，看起來很嚇人但跟任何事
  都無關。第一次 clone 是暫時性失敗，那個 repo 是公開的。
- **`insmod` 不解相依。** 手動載入 `morse.ko` 而沒有先 `modprobe mac80211 crc7`，會噴
  五十行 `Unknown symbol ieee80211_*`。同樣很像缺陷，同樣不是。
- **每次開機出現的 `Country TW ... is not supported / staying in SG` 是正確行為。**
  核心命令列上的 `cfg80211.ieee80211_regdom=TW` 是為了**brcmfmac** 那張網卡設的，而
  cfg80211 會把它送給每一個 phy。Morse 的法規資料庫沒有 `TW`，所以驅動拒絕並留在
  `SG` —— 那正是我們要的設定，因為 SG 的 920–925 MHz 區塊才對得上台灣 NCC 的配置。
  吵，但沒有錯。
- **這塊板子是從一張 128 GB SDXC 卡開機的。** NOTES 從早期就記著「128 GB SDXC 從來沒
  能讓 Pi 開機」。那次是在 *SenseCAP M1* 上，而且不確定是不是同一張卡，所以這不構成反
  證 —— 但那條敘述已經不是通則，不該再當通則引用。
- **拿板子的 log 跟別台對時間之前，先確認它的時區。** 這台開起來是 `BST`，而 AP 和筆電
  都在台北時間，7 小時的偏差一度讓一次重開機看起來像兩次。現已設為 `Asia/Taipei`。

### 證據

`logs/2026-08-25-hc01p-rpios-stage{2-devicetree,3a-defectB-reproduced,3a-defectB-mechanism,3b-driver-up,4a-station-associated,4b-persistent}.txt`。
Overlay：`overlays/mm610x-spi-hc01p.dts`。首次開機的佈署檔與儀器 diff：`port/hc01p/`。

## 2026-08-24 深夜 —— HT-H7608 的 HaLow 介面不屬於任何防火牆區域

自從設定以來第一次真正進到這台，做法是把 `en5` 移過去並加上 `10.42.0.100/24`。我的
SSH 金鑰不在這塊板子上，改用 `expect` 以 `root` 做密碼登入，密碼是 Heltec 的原廠預設值
（不寫在本檔）。無線電的
設定完全沒動；唯一的寫入是下面那個防火牆區域。

### 記錄寫著「它的 IP 層從不回應，而且那是正常的」。那不正常

那是一個設定缺漏，長這樣：

```
wlan0   UP   10.41.0.197/16        <- 位址在，介面也是 UP

nft, chain input:
        type filter hook input priority filter; policy drop;
        iifname "br-lan" jump input_lan          <- 唯一的放行路徑

firewall.@zone[0] name=lan  network=lan       input=ACCEPT
firewall.@zone[1] name=wan  network=wan wan6  input=REJECT

halow 出現在任何 zone 的次數 : 0
input chain 裡提到 wlan0 的規則 : 0
```

`network.halow` 既不在 lan 也不在 wan，所以從 `wlan0` 進來的封包直接落到
`policy drop`。這解釋了每一項觀察：ARP 通（第二層，根本不經過 input chain）、DHCP
client 通（出站），而 ICMP **和每一個 TCP 埠**都被靜默丟棄。這次是用 TCP 驗證的，不只
ping —— 22、23、80、443、7681、8080 從同一個 L2 上的 AP 測全部失敗。

所以「用它的 RSSI 和關聯事件，絕不要用它的 ping」這個建議依然正確，但理由要換：不是這塊
板子沒有可用的 IP 堆疊，是沒有人把它的 HaLow 網路放進任何區域。

**已修，但還沒端到端證實。** 我建了一個專屬區域，而不是把 `halow` 丟進 `lan` —— 因為
那裡的 `input=ACCEPT` 會把這塊板子**無認證的 ttyd**（見下）、LuCI 和 dnsmasq 一起開放
到整個 HaLow 網段：

```sh
# zone: name=halow network=halow input=REJECT output=ACCEPT forward=REJECT
# rule: Allow-Ping-halow  src=halow proto=icmp icmp_type=echo-request
# rule: Allow-SSH-halow   src=halow proto=tcp  dest_port=22
```

產生的規則是

```
iifname "wlan0" jump input_halow
chain input_halow {
        icmp type echo-request counter accept   # Allow-Ping-halow
        tcp dport 22           counter accept   # Allow-SSH-halow
        jump reject_from_halow
}
```

原設定備份在 `/etc/config/firewall.pre-halowzone-20260824`。日後要放寬成完全開放：
`uci set firewall.@zone[2].input='ACCEPT'`。

**同一晚稍後端到端證實了**，在鏈路修好之後（見下）：

```
iifname "wlan0" jump input_halow
        icmp type echo-request counter packets 1 accept
        tcp dport 22           counter packets 1 accept
station -> 10.41.0.197 : TCP22-OPEN
```

ICMP 計數器是 1 而不是 20，因為 fw4 的 input chain 在抵達區域 chain 之前就會放行
`ct state established` —— 該連線的第一個封包命中規則，其餘走快速路徑。真正決定性的是
TCP 計數器離開零：修好之前，SYN 根本到不了這塊板子。

### 鏈路嚴重劣化，而時間點指向那條網路線

```
TX Total 75880   TX ACK valid 26547 (35%)   TX ACK timeout 41237 (54%)
RX total 501823  RX pass FCS 501224         RX signal field error 50642 (10%)
signal −69 ~ −76 dBm
```

它發出去的東西超過一半拿不到 ACK。對照同一台 AP 同一時刻：station 讀 0 dBm、
HT-HC01P −14 ~ −22 dBm。

失敗特徵和今天早上的 HT-HC01P 一模一樣 —— `SME: Trying to authenticate … send auth
(try 1/3, 2/3, 3/3) … timed out`、`CONN_FAILED`、`TEMP-DISABLED` 退避 10 → 20 → 30
秒 —— **但這不是 BCF 問題**：這塊板子本來就在用 `bcf_HC01_V2_H.bin`。三分鐘內取樣
十二次，`COMPLETED` 出現零次。

讓那條線看起來像嫌疑犯的是順序：它先前撐了 **44522 秒**（十二小時以上不斷），然後變成
2001 秒 → 189 秒 → 10 秒 → 完全連不上，起點正是網路線被接上去的時候。那個嫌疑犯是錯的。

### 天線是別的頻段的，而那就是全部原因

**它標示 868 MHz。** 那是歐規 SRD 頻段。這條鏈路跑在 922 MHz，也就是台灣 NCC 的分配
所在 —— **920–925 MHz** —— 而驅動**根本沒有 `TW` regdomain**（`/usr/share/morse-regdb/channels.csv`
收錄 53 個國家碼，沒有 `TW`）。這正是這裡所有板子都設 `country=SG` 的理由：SG 的
920–925 MHz / 4 MHz / 22 dBm 區塊與台灣的分配完全吻合。附帶一提，同一張 SG 表裡**也**
有一組 866–868 MHz、duty cycle 只有 2.77% 的通道 —— 那正是那支天線被設計的頻段，而台灣
沒有把它分配給這個用途。

差 54 MHz、6.2%，而這類天線的可用頻寬通常只有 2–5%。

換掉它（同一次斷電裡也調整了板子位置）：

| | 868 MHz 天線 | 換天線後 | 調整位置後 | 關閉省電 |
|---|---|---|---|---|
| 它看 AP | −85 dBm | −69 dBm | −69 dBm | — |
| AP 看它 | −75（avg −71）| −75（avg −71）| −69（avg −62）| **−64（avg −64）** |
| `wpa_state` | SCANNING，12 次取樣 0 次 | **COMPLETED** | COMPLETED | COMPLETED |
| `RX total` | 553 秒 34 個 | 124 秒 276 個 | — | — |
| `RX signal field error` | **4410** | **10** | **每 45 秒 +0** | — |
| `TX ACK valid` | 790 之中 1 | 173 之中 51 | — | — |
| tx bitrate | — | 6.5 Mbit/s MCS0 | 260 Mbit/s MCS5 | **325 Mbit/s MCS7** |
| expected throughput | — | 0.292 Mbps | 11.718 Mbps | **14.648 Mbps** |
| 從 station ping | 從未回應 | 1/20，241 ms | 27/30，avg 383 ms | **30/30，avg 10.3 ms** |

signal field error 那一列是定案的關鍵：4410 個解不開的偵測對上 34 個解得開的 frame，
然後變成 10，最後完全沒有。接收機解不開東西，正是天線偏離共振點 54 MHz 會造成的結果。

**要註明的但書：** 換天線和調位置發生在同一次斷電裡，所以無法從這些數字分離兩者各自的
貢獻。兩者都改對了，但哪一個影響較大並未確立。

### 對今早那段「停在 1 MHz」的更正

今晚稍早這塊板子在 `morse_cli channel -a` 的**三個欄位**（Full、DTIM、Current）全部停在
`921500 kHz, 1 MHz`，從來沒有採用 AP 的 4 MHz。那看起來像是今早在 HT-HC01P 上記錄的
idle 停駐缺陷的更嚴重版本。**那根本不是缺陷。** 天線一換，同一塊板子立刻以
`922000 kHz, 4 MHz, primary 2 MHz` 起來，沒有任何額外操作。

所以停在 1 MHz 是**症狀而不是原因**：解不開 AP beacon 的 station 沒有依據去推導操作
參數，於是留在預設值。HT-HC01P 那一節維持原樣（在那裡 radio **確實**會在認證時切換），
但「這個驅動從不切換」這個一般化說法會是錯的。

### 省電在這塊板子上也值 13 倍

在鏈路健康之後才量，所以兩個效應是分開的：

```
省電 on    30/30，0% 遺失，RTT min 34.7 / avg 133.5 / max 224.7 ms, mdev 59.7
省電 off   30/30，0% 遺失，RTT min  7.7 / avg  10.3 / max  21.1 ms, mdev  3.5
```

平均延遲 133.5 → 10.3 ms，抖動 59.7 → 3.5。不像 station 那樣是黑洞，但方向相同。
`iw dev wlan0 set power_save off` 是**執行期設定**，重開機或 `wifi reload` 就沒了。

### OpenWrt 上的持久設定，以及為什麼不是 `enable_ps`

在 `morse.sh` 裡查證過才寫，不是假設 —— 因為同一天稍早才發現 `channel` 選項是惰性的。
**這是兩個獨立機制，只有其中一個是對的槓桿。**

`powersave` 是每介面的 uci 選項，在第 213 行註冊
（`config_add_boolean wds powersave enable`），在 `morse_iface_bringup()` 的
**`sta)` 分支**裡套用：

```sh
# 653-663 行
if grep -i '325b' /sys/kernel/debug/usb/devices ; then
        set_default powersave 0     # Morse USB MM8108 的 workaround，APP-3745
else
        set_default powersave 1     # <- 「省電開著」就是從這個預設值來的
fi
[ "$powersave" -gt 0 ] && powersave="on" || powersave="off"
iw dev "$ifname" set power_save "$powersave"
```

所以讓每一塊板子都付出一個數量級代價的，是這行 `set_default powersave 1`，不是驅動的
`enable_ps`。它在**每次介面起來時都會執行** —— 開機、`wifi reload`、重連 —— 這正是
持久化需要的。和 `morse_setup_sta()` 從不套用的 `channel` 不同，這一個在 STA 路徑上有
實際的呼叫。

`enable_ps` 是另一回事：它是列在 `MM_MOD_BOOL`（第 17 行）的模組參數。原則上可以由 uci
設定，但它只吃 0/1，而目前的實際值是 **2** —— 那是驅動自己的預設、不是 uci 設的 ——
而且改它需要重載模組。Morse 自己也只把它當成 USB 的 workaround 在用（第 145 行，
`#APP-4066`，`MOD_PARAMS="$MOD_PARAMS enable_ps=0"`）。不要動它。

兩塊 Heltec 板子都已套用並驗證：

```sh
uci set wireless.default_radio1.powersave='0'   # HT-H7608  （那台的 Morse 是 radio1）
uci set wireless.default_radio0.powersave='0'   # HT-HC01P  （這台的 Morse 是 radio0）
uci commit wireless && wifi reload
```

兩塊板子的 radio 編號**不一樣** —— 用 `uci show wireless` 找 `mode='sta'` 的那個
iface，不要直接複製上面的行。

| 板子 | 機制 | 省電 on | 省電 off |
|---|---|---|---|
| station `55:04`（RPi OS）| NetworkManager `wifi.powersave 2` | **入站 100% 遺失** | 30/30，avg 4.8 ms |
| HT-HC01P（OpenWrt）| uci `default_radio0.powersave 0` | 20/20，avg 105.4 ms，mdev 66.2 | 20/20，avg **8.4 ms**，mdev 2.7 |
| HT-H7608（OpenWrt）| uci `default_radio1.powersave 0` | 30/30，avg 133.5 ms，mdev 59.7 | 30/30，avg **10.3 ms**，mdev 3.5 |

三種主機、三套不同的設定系統、同一個根本原因。station 那台是嚴重的那一個 —— 在它身上
不是延遲，是不可達。

**持久性是怎麼證明的，而不是假設的：** `wifi reload` 會把 vif 拆掉重建，所以任何執行期
的 `iw set power_save off` 都會被清除。在 reload **之後**讀到 `off`，而腳本自己的預設是
`1`，那就只可能來自 uci。兩塊板子的備份都在
`/etc/config/wireless.pre-powersave-20260824`。

**接著在三塊板子上都做了完整重開機驗證。** `wifi reload` 不等於開機，所以每一項宣稱都用
硬的方式重測一次，從最便宜、最安全的板子開始：

| 板子 | 重開方式 | 開機後 | 鏈路 |
|---|---|---|---|
| station `55:04` | `systemctl reboot` | `power_save off`、`wifi.powersave disable`、`never-default yes`、預設路由只走 `wlan0` | 20 秒起來，0 dBm，MCS7，20/20 @ 5.8 ms |
| HT-HC01P | `reboot` | `power_save off`、`uci powersave 0`、`COMPLETED` | 10.41.0.216 回來，MCS7，4.9 ms |
| HT-H7608 | `reboot` | `power_save off`、`uci powersave 0`、**`fw4` 的 input chain 帶著 `wlan0` 的 jump 和 `input_halow` 兩條放行規則** | 10.41.0.197 回來，−67 dBm，MCS7，兩個來源各 10/10 @ 8.5 ms |

HT-H7608 是關鍵的那一台。它的乙太網路線已經移回 AP，所以 **HaLow 是它唯一的進入路徑**
—— 整個重開機過程和上面每一項檢查，都是走在 `halow` zone 存在的目的所在的那條鏈路上。
這也回答了加入該 zone 時留下的一個問題：`wifi reload` 之後 input chain 一度沒有 `wlan0`
的規則，看起來像是這個 zone 撐不過去。它撐得過 —— fw4 是在介面起來時才綁定 zone，開機
和 reload 都一樣。

一個副產品：那塊板子的速率控制器在網路線被拔掉之後一直停在 MCS1 / 0.585 Mbps，重開之後
回到 **MCS7 / 14.648 Mbps**。MMRC 需要成功的傳輸樣本才會往上爬，而 ping 的流量太稀薄
餵不飽它；重開只是把估計值重置了。在把低 MCS 讀成故障之前，值得知道這件事。

以及同一天內第四次看到介面名稱不穩定：HT-HC01P 這次起來是 `wlan1`、HT-H7608 是 `wlan0`，
跟上一次開機剛好相反。讀出名稱，絕不要假設。

一個附帶值得記的現象：HT-HC01P 的 HaLow 介面在這次 reload 之後變回 **`wlan0`**，先前是
`wlan1` —— 就是今早記錄的那個不穩定。用 `ls /var/run/wpa_supplicant_s1g/` 讀出名稱，
絕不要假設。

### 硬體與作業系統，實機確認

```
OpenWrt 23.05.5, 2.8.5-20251023, kernel 5.15.167, mips
radio0  mac80211  platform/10300000.wmac                    2.4 GHz AP HT-H7608-DD05, ch1 HT20, psk2
radio1  morse     platform/10130000.mmc/mmc_host/mmc0/...   SDIO
        bcf=bcf_HC01_V2_H.bin  country=SG  channel=42  mode=sta  encryption=sae  max_inactivity=30
br-lan  10.42.0.1/24, ports eth0.1, switch0 vlan1 ports "0 2 6t"
network.halow  proto=dhcp, device wlan0     network.wan proto=dhcp（未使用）
開放埠  22 dropbear / 80 / 443 LuCI / 53 dnsmasq / 7681 ttyd
```

`radio1.channel='42'` 和 HT-HC01P 一樣是惰性的，因為 `morse_setup_sta()` 從不呼叫
`morse_cli channel`。

**它和 HT-HC01P 用同一個 BCF 檔案** `bcf_HC01_V2_H.bin`。兩者都搭 HT-HC01 V2 模組，
一個走 SDIO、一個走 SPI。所以保全在 `firmware/heltec-hc01p/` 的那份涵蓋兩塊板子。

### 無認證的 `ttyd` 是兩塊 Heltec 板子都有，不是只有一塊

```
http://10.42.0.1:7681/token  ->  {"token": ""}   HTTP 200
```

這件事先前被記成 HT-HC01P 的問題。不是 —— HT-H7608 出貨同樣帶著無認證的 web root
shell，而且還多開了 80、443 和 53。兩塊板子上它都和乙太網路埠以及板子自己的 AP 橋接在
一起。

**決定，2026-08-24：維持 `ttyd` 出廠原狀，並且不再把它列為未解項目。** 這是 Heltec 在
兩塊板子上的原廠預設，不是這裡任何人設錯的，而且這些板子位於隔離的實驗網段上，不在
routed 或共用的網路上。只有在其中一塊被接上共用交換器、或被給予離開實驗網段的路由時
才需要重新檢視 —— 跟它們的 DHCP 伺服器適用的是同一個條件。

有一件事**不**留在未解狀態，因為今天的防火牆工作剛好涵蓋了它：**HT-H7608 的 `ttyd`
從 HaLow 網段碰不到。** 上面加的 `halow` zone 是 `input REJECT`、只放行 ICMP 和 TCP 22，
所以 7681、80、443、53 仍然侷限在 `br-lan` —— 它的乙太網路埠和它自己的 2.4 GHz AP，
跟接線之前一樣。HT-HC01P 則不同：它的 HaLow 網路位於接受 input 的區域裡（這正是我們能
從 HaLow ssh 進去的原因），所以它的 `ttyd` 很可能在那裡是開放的。沒有查證，因為上面
那個決定讓它變得無關緊要。

## 2026-08-24 傍晚 —— station 的省電是入站黑洞，不是 5% 遺失

未解清單原本寫的是：*「station 與 AP 的省電不匹配（`enable_ps=2` 對上 AP 的 0）作為舊
的 5% ping 遺失成因之一 —— 從未測試。」* 現在測了，答案比問題大。

station 在 16:13 自己重開了一次，回來時帶著 NetworkManager 預設開啟的省電 —— 正是本檔
在移除測距記錄器時警告過的狀態，因為已經沒有東西會再去重申 `power_save off`。在那個
狀態下：

| 方向 | 省電 ON | 省電 OFF |
|---|---|---|
| AP → station `10.41.0.208` | **0/5，100% 遺失** | 30/30，3.8–16.0 ms |
| 筆電 → station | **0/5，100% 遺失** | 10/10，4.4–9.1 ms |
| station → AP | 2/3，33% 遺失，54–160 ms | 10/10，2.8–7.8 ms |

同一個 L2 上兩個獨立來源、AP 上有正常的 ARP 項目、`icmp_echo_ignore_all=0`、
`rp_filter=0`、沒有任何防火牆規則 —— 入站方向一個封包都沒進去。這不是「5% 遺失的成因
之一」：**省電開著時，station 從網路側完全無法到達**，而它自己往外講話仍然正常。

**未解，記下來而不是抹平。** HT-HC01P 的 `iw power_save` 同樣是 on、`enable_ps` 同樣是
2，表現卻不同 —— 30/30 不掉封包，但延遲 22.5–232.9 ms，是 25 倍而不是黑洞。同一個驅動
家族、同一顆模組、同一台 AP，兩種故障模式。不要把任何一邊的結果推論到另一塊板子。

**在 station 上已改成持久設定。** `iw dev wlan1 set power_save off` 是執行期設定，
NetworkManager 下次重連就會撤銷 —— 這正是它再度發生的原因：

```sh
nmcli connection modify halow wifi.powersave 2        # 2 = disable
nmcli connection modify halow ipv4.never-default yes
nmcli connection up halow
```

第二行修的是同時發現的另一個問題。重開之後 station 的預設路由是
`via 10.41.254.1 dev wlan1 metric 600`，排在 Sun 的 601 前面，所以那塊板子的對外流量
被送去一台沒有對外網路的 AP。設了 `never-default` 之後，HaLow 的 profile 不再安裝預設
路由；`ip route get 1.1.1.1` 現在回傳 `via 192.168.108.1 dev wlan0`。

重新啟用後驗證：AP → station 20/20、平均 5.1 ms，另外兩個方向各 10/10，四個節點同時
可達。

## 2026-08-24 稍晚 —— HT-HC01P 關聯上了，而它的 BCF 是 Morse 的評估板

**已解決。** 這塊板子一直載入 `bcf_mf08551.bin`，而 `/lib/wifi/morse.sh:135` 把這個
檔案對應到 `morse,ekh01-03` / `morse,ekh03v3` —— **Morse 的 EKH01-03 評估板**。這塊板
的 `board_name` 是 `Heltec,Pi4-HT-HC01P-64bit`，而那段 case 敘述裡**沒有任何 Heltec
條目**；它的 `*)` 預設分支只在裝置路徑含 `usb` 時才設值，所以 SPI 板直接落空，沒有任何
東西會修正這個值。它被硬寫在出廠映像裡，`/etc/config/wireless` 和 `/etc/modules.d/morse`
兩處都是。Heltec 自己的 `bcf_HC01_V2_H.bin` 就放在 `/lib/firmware/morse/`，從來沒被用過。

```sh
uci set wireless.radio0.bcf='bcf_HC01_V2_H.bin'
uci commit wireless && wifi
```

**五秒內關聯**，第一次認證嘗試就成功，SAE、PMF、四向交握、DHCP 一次到位：

```
send auth to 3c:1a:cc:70:3f:ca (try 1/3)
wlan0: authenticated
RX AssocResp from 3c:1a:cc:70:3f:ca (capab=0x11 status=0 aid=3)
WPA: Key negotiation completed with 3c:1a:cc:70:3f:ca [PTK=CCMP GTK=CCMP]
CTRL-EVENT-CONNECTED
DHCPACK(br-lan) 10.41.0.216 0c:bf:74:40:8e:91 HT-HC01P-8E91
```

AP 現在讀它是 **−5 dBm**，而在此之前它什麼都收不到。IP 層雙向都通，包括跨到站台
`10.41.0.208`。跟 HT-H7608 不同，這塊板子不是只能當無線層的對照組。原設定備份在
`/etc/config/wireless.pre-bcf-20260824`；新 BCF 是 1170 B / crc32 `0x389a48c4`，舊的是
1150 B / `0xf1cf6f9f`。

**這是第六個出貨時帶著 Morse 參考板設定的實作**，跟下面 50 MHz 時脈和 flag 0 的 reset
腳位是同一個故事 —— 差別在於這次繼承來的檔案直接讓模組失去發射能力。繼承參考設定的代價
並不總是看不見的。

### 而且原廠的下載頁給的也是壞的那一份

修好之後，2026-08-24 發現。Heltec 為這個產品提供的 BCF 下載點是
<https://resource.heltec.cn/download/HT-HC01P/BCF/driver_1_15_3/bcf_HC0P.bin>，
而它**與 `bcf_mf08551.bin` byte 完全相同** —— 也就是剛剛才被確認為成因的那個
評估板檔案：

```
原廠下載      bcf_HC0P.bin        1150 B  sha256 57c50cb2…  Last-Modified 2025-06-10
映像內預設    bcf_mf08551.bin     1150 B  sha256 57c50cb2…  （相同）
能用的那一份  bcf_HC01_V2_H.bin   1170 B  sha256 5744fa28…  只在映像內
```

檔案自己會表明身分，所以這不是單憑雜湊推論：

```
bcf_HC0P.bin        .board_desc = "mf08551"     .build_ver = "a49f6ff 17ee8d5"
bcf_HC01_V2_H.bin   .board_desc = "HC01_V2_H"   .build_ver = "a49f6ff 17ee8d5 _Modified"
```

`mf08551` 是 Morse 的 EKH01-03 評估板。把它改名成 `bcf_HC0P.bin`、放進
`HT-HC01P/BCF/` 目錄，不會改變它是什麼。它也**不比映像新** —— 2025-06-10 對
2025-06-23 —— 而當一個原廠頁面看起來像是更新版時，這是第一件值得查的事。

所以「繼承參考設定」這條線比「映像裡的預設值是錯的」還要糟一階：**原廠公布的、
取得這個產品 BCF 的正式途徑，發出去的是同一個錯誤檔案**，而能用的那一份只存在於
已經出貨的映像內部。這就是為什麼本 repo 的 `firmware/heltec-hc01p/` 收的是二進位
檔本身，而不是一個連結。

### 症狀是單向鏈路，而要看出來得靠成對窗口

載錯 BCF 時，這個 station 收得完美，發射則像打進真空。三組成對的 40 秒控制／測試窗口，
控制組用 `disable_network 0` 讓 supplicant 真正靜音：

| 窗口 | HC01P `TX Total` | HC01P `TX ACK valid` | AP `RX total` | AP `RX pass FCS` | AP `RX sig field err` |
|---|---|---|---|---|---|
| control 1 | +0 | 0 | +53 | +52 | +12 |
| test 1 | +114 | **0** | +26 | +26 | +9 |
| control 2 | +0 | 0 | +24 | +24 | +3 |
| test 2 | +114 | **0** | +43 | +42 | +24 |
| control 3 | +0 | 0 | +25 | +25 | +9 |
| test 3 | +113 | **0** | +32 | +32 | +6 |

`DCF granted` 跟著 `TX Total` 走，每個窗口只有 2 個 `TX Revoked`，所以那些 frame 確實
發射出去了，MAC 並沒有被擋。但一個 ACK 都沒回來，而 AP 的接收計數器完全分不出測試組和
控制組。

**只做一個窗口會得到錯誤答案。** 第一次的單一量測看起來像是 AP 收得到但解不開 —— signal
field error 控制組 +4 對測試組 +12。三組成對窗口把它推翻了：12 / 3 / 9 對 9 / 24 / 6，
完全重疊。這是本檔案裡同一個陷阱的第十次。

### 過程中四個錯誤的判斷

- **「它從來不嘗試認證」。** 它一直都在試，每 10–60 秒一輪：
  `SME: Trying to authenticate … send auth (try 1/3, 2/3, 3/3) … authentication
  timed out`，然後 `CONN_FAILED`、`CTRL-EVENT-SSID-TEMP-DISABLED`，退避
  10 → 20 → 30 秒。hostapd 沒有它 MAC 的紀錄是因為 frame 沒到，不是因為沒發。先前未解
  清單裡的說法，來自只看了 AP 那一側。
- **「1.15.3 解不開 RSN 元素」。** 見下面 `rsn_beacon_mode` 段落的更正。HT-H7608 跑同一版
  1.15.3，整場都以 `auth_alg=sae` 掛在這台 AP 上。
- **「頻道錯了」。** 沒有錯。`morse_cli` 的 `Primary Channel Index` 數的是
  **operating channel 內部的 1 MHz 槽** —— 922.0 為中心的 4 MHz 裡是 920.5 / 921.5 /
  922.5 / 923.5 —— 所以 index 1 是 921.5，即 s1g channel 39。beacon 的 HT Operation 元素
  宣告映射後的 5 GHz channel 153，在 SG 表裡就是同一個 921.5，station 用 `chan=39` 認證
  是對的。
- **「uci 的 `channel` 和 `s1g_chanbw` 會限制 station 的掃描」。** 不會。
  `morse_setup_sta()` 從來不呼叫 `morse_cli channel`，只有 AP、mesh、adhoc 和 monitor
  路徑會。HT-H7608 的 `channel=42` 同樣從來沒被套用。

### 另一個真實的缺陷：radio 閒置在 1 MHz，而 primary 是 2 MHz

在沒有認證的期間，驅動把 radio 停在 **921.5 的 1 MHz**，儘管 AP 的 primary 頻寬是
2 MHz。在那個狀態下它偵測得到 AP 卻解不開：

| 30 秒窗口 | `RX total` | `RX pass FCS` | `RX signal field error` |
|---|---|---|---|
| 停在 1 MHz / 921.5 | **+0** | +0 | **+199** |
| 鏡射 AP 之後 | **+289** | +289 | **+3** |

30 秒 199 次無法解碼的偵測是 6.6/s，對上 AP 的 9.8 beacons/s；30 秒解出 289 個是 9.6/s，
正是 beacon 速率。鏡射用的是

```sh
morse_cli -i wlan0 channel -c 922000 -o 4 -p 2 -n 1
```

supplicant 一開始認證就會把它蓋掉 —— 而且蓋成正確的 922.0 / 4 MHz —— 所以這件事從來沒有
擋住關聯。它是 `scan_results` 時不時回傳空白的原因，也是為什麼從外部觸發
`iw dev wlan0 scan` 就能把 cache 填滿，而 supplicant 自己的掃描看起來什麼都沒找到。

### HaLow 介面名稱在開機之間不穩定

為了確認 BCF 能不能撐過重開機而做的那次重開，產生了這個看起來完全像電台掛掉的畫面：

```
$ iw dev wlan0 link
Device "wlan0" does not exist.
```

而 AP 在同一時刻回報同一個 MAC 已關聯、連線時間 194 秒。那次開機 HaLow 的 netdev 起來
時叫 **`wlan1`** —— log 裡是 `brcmfmac … phy1-ap0: renamed from wlan0` —— 因為 Broadcom
的 5 GHz 介面搶到了 `wlan0`。supplicant 的控制 socket 也跟著搬家。要讀出來，不要假設：

```sh
ls /var/run/wpa_supplicant_s1g/
```

### BCF 撐得過重開機

`uci commit` 連 `/etc/modules.d/morse` 一起改寫，所以 kmodloader 第一次嘗試就載入正確
檔案：**t = 6.65 秒**出現 `Loaded BCF from morse/bcf_HC01_V2_H.bin`，**t = 11.9 秒**完成
關聯，`10.41.0.216` 回來，−9 dBm，4 MHz，三個方向都 0% loss。修正前的那次開機是 6.64 秒
先載 `bcf_default.bin`，十一分鐘後才變成 `bcf_mf08551.bin`，那條路徑也一併消失了。

### 現在所有東西在哪

`en5` 接在 HT-HC01P 上，Mac 側是 `10.42.0.100/24`。**一次只能接一台的限制結束了** ——
HC01P 現在有 HaLow 位址，所以把 `en5` 接回 AP 之後，四個節點可以同時到達。換線前要先移除
alias，macOS 給了它 `/8` 的網路遮罩，否則會把 `10.41.0.0/16` 整段吃掉：

```sh
sudo ifconfig en5 -alias 10.42.0.100
```

第四個節點目前的狀態：**HT-HC01P**，`br-lan` 上 `10.42.0.1`，HaLow `10.41.0.216`，
驅動 1.15.3，`bcf_HC01_V2_H.bin`，**MM6108A2** 矽晶，以 SAE 加 PMF 關聯到
`BCM2711-57e7`。它的 `boardtype` 和 `country_code` 兩個 OTP bank 都沒有燒寫，所以晶片
無法自己挑 BCF。

未解，依序：

1. ~~**`ttyd` 沒有認證**~~ —— **2026-08-24 以決定結案，不是以修復結案。** 這是兩塊
   Heltec 板子的原廠預設，而它們位於隔離的實驗網段上，見上面那一節。若任一塊被接上共用
   交換器或 routed 網路，重新開啟。
2. **`openmanetd` 拿掉之後 AP 還會不會停擺？** 不變 —— 值得單純觀察，救援是
   `echo 1 > $P/reset`。
3. **HT-HC01P 的省電。** station 那邊已經定案（見上面那節：`halow` profile 設
   `wifi.powersave 2`），但 HC01P 仍然開著，代價是 22.5–232.9 ms，對比 station 的
   3.8–16.0 ms。為什麼在它身上退化成延遲、在 station 身上退化成完全的入站黑洞，原因
   不明。在它上面量任何東西之前先強制關掉省電。
4. **真實距離。** 不變：上一層樓仍然 −41 dBm，還有約 50 dB 餘裕。

## 2026-08-24 收尾 —— 現在所有東西在哪

session 結束時實際連上去確認的，不是憑記憶寫的。

**Station `E4:5F:01:52:55:04`**（serial `100000004851d437`、RPi OS bookworm 6.6.51）

```
wlan0  192.168.108.19/24 在 SSID `Sun`     wlan1  10.41.0.208/16、MTU 1500
驅動 srcversion 87374779AA811C291578351   （mm6108-2.0.1 + patches/upstream/）
DT spi-max-frequency  02 fa f0 80 = 50,000,000     spi_clock_speed 參數 0
modprobe.d/morse.conf：options morse country=SG bcf=bcf_fgh100mhaamd.bin
spi errors 0  timedout 0        已關聯 3c:1a:cc:70:3f:ca
NM autoconnect 優先序：sun 20、preconfigured（Unifi）10、halow 0
```

為距離測試裝的 `halow-rssilog.service` **已經移除** —— unit 和腳本都刪了，沒有任何東西
還在戳無線電。它的輸出留在板子上的 `/home/alan/rssi-logs/`（5 個檔、13776 行），另有備份。
**注意副作用：現在沒有東西會重新確保 `power_save off` 了**，NetworkManager 下次重連時
可能把它打開。之後要量 RSSI 或遺失率之前記得先強制關掉 —— 做法在 2026-08-23 的距離測試
log 裡。

**AP `E4:5F:01:52:57:E7`**（serial `1000000093d173dd`、OpenMANET 24.10 / 6.6.138）

```
br-lan 10.41.254.1/16      MTU：eth0 1500、br-lan 1500、wlh0 1500
無線電：922.0 MHz、4 MHz 操作、2 MHz 主頻寬   （uci channel=40 s1g_chanbw=4）
rsn_beacon_mode=2          2 台 station 關聯中
openmanetd / alfred / mesh11sd：全部開機停用
```

`eth0` 的 1500 目前是手動設的值，但把它設成 1460 的 `openmanetd` 已經開機停用，所以
重開機之後也會是 1500。

**筆電**：`en0` 192.168.108.200 在 `Sun`，`en5` 10.41.0.100/16 用線接 AP。

**第三、四台**：Heltec HT-H7608 關聯在 AP 上（只能當無線層對照，IP 層從來不通）；
Heltec HT-HC01P 在一台 Pi 4 上、`10.42.0.1`、目前沒接線，設定成 `BCM2711-57e7` 的
station 但關聯不上。

### 未解，依值得接手的順序

1. **HT-HC01P 關聯不上。** `rsn_beacon_mode=2` 已經把 RSN IE 放進 beacon 並在空中確認，
   它依然完全不嘗試認證，hostapd 也沒有它 MAC 的任何紀錄。需要碰得到那台：把 `en5`
   接到它、Mac 這側設 `10.42.0.100/24`，或者連它自己的 5 GHz AP `HC01P-mgmt`。第一件
   要看的是它現在掃描有沒有 RSN，用
   `wpa_cli_s1g -p /var/run/wpa_supplicant_s1g -i wlan0`。
2. **HT-HC01P 的 `ttyd` 沒有認證**，而且和它的網路孔、5 GHz AP 橋在一起，防火牆 lan
   zone 是 `input ACCEPT`。沒接線時曝險有限，但在它接上任何共用交換器之前必須先處理。
3. **HT-H7608 的矛盾。** 同樣 1.15.3 驅動，稍早卻用 `auth_alg=0` 加 RSN 四向交握關聯上
   了同一台 AP。未解，而且它讓「1.15.3 不行」這個推論不能一般化。
4. **`openmanetd` 拿掉之後，AP 還會不會停擺？** 已記錄三次，其中兩次前面什麼都沒發生。
   救法已知（`echo 1 > $P/reset`）而且便宜。值得單純觀察。
5. **station 與 AP 的省電設定不對盤**（`enable_ps=2` 對 AP 的 0）是不是舊那 5% ping
   遺失的成因 —— 從未測試，而且記錄器移除後 station 的省電狀態由 NetworkManager 決定。
6. **真正的距離極限。** 上一層樓時還有 −41 dBm、約 50 dB 餘裕，離極限還很遠。

## 2026-08-24 —— SPI 時脈才是天花板，而它藏住了頻寬那題的答案

**把 station 的 SPI 時脈從 10 MHz 拉到 50 MHz，吞吐量變成 2.6 倍、零 SPI 錯誤**，並且
修正了一個已經量過而且量錯的結論。在預設的 10 MHz 下，4 MHz 頻道測起來**比 2 MHz 還慢**，
差一點就被寫成「4 MHz 沒有幫助」；在 50 MHz 下它幾乎正好是兩倍。當時的瓶頸是匯流排，
加寬頻道只是多帶來重傳。

| SPI 時脈 | 2 MHz 空中 | 4 MHz 空中 |
|---|---|---|
| 10 MHz | 上 3.16 / 下 2.46 | 上 2.66 / 下 2.29 |
| **50 MHz** | 上 3.55 / 下 3.27 | **上 6.86 / 下 6.80** |

匯流排的時間花在哪：**station 的 SPI 匯流排上，83% 的位元組是那個 250 位元組的交易間
填充** —— 也就是本 repo 自己修缺陷 3 時裝上的東西。那個填充是正確的（晶片數的是 clock
不是時間），但也正因如此，它在 10 MHz 要花 200 µs、在 50 MHz 只要 40 µs。**跑在非參考
時脈上，等於把一個必要開銷乘以五倍。**

10 → 20 → 50 MHz 每一階都是零 SPI 錯誤，所以**SenseCAP M1 的 mPCIe 走線在 50 MHz 下是
乾淨的**，overlay 裡那個 10 MHz 是保守而非必要。兩項設定都已持久化並經冷開機驗證。

**對 PR 的一個後果**：在 50 MHz 下驅動那個錯誤公式剛好算出正確的 250，所以**缺陷 3 在
這套硬體上不再重現**，除非把時脈調回 10 MHz。修正本身不受影響，缺陷 2 也依然成立。
這件事該在上游明講 —— 一個驅動不該依賴特定時脈才算得出正確的延遲。詳見下面專節。

## 2026-08-23 傍晚 —— 第三塊板子、一個 MTU 黑洞，以及廠商文件說了什麼

四個結果。完整證據在
[`logs/2026-08-23-mtu-blackhole-third-implementation-and-vendor-docs.txt`](logs/2026-08-23-mtu-blackhole-third-implementation-and-vendor-docs.txt)。

**藏住缺陷的是那份參考設定。** 第三塊 SPI 板子加入了（Heltec HT-HC01P 接 RPi 4，
驅動 1.15.3），而且第一次讀了 Morse 官方的 Linux 移植指南。它的 EKH01 參考 overlay
寫的是 `spi-max-frequency = <50000000>` 和 `reset-gpios = <&gpio 5 0>` —— 50 MHz
加 flag 0。**所有檢視過的實作都從官方參考繼承了這兩個設定**，而它們正好讓缺陷 3
（壞掉的延遲換算只有在 50 MHz 才會算出可用值）隱形。這裡原本還寫著 flag 0 會讓
RESET_N 不觸發、因而藏住缺陷 2 —— **那是錯的，2026-08-24 更正**：驅動根本不讀那個
flag，真正藏住缺陷 2 的是 Morse 為 OpenWrt 提供的一份核心 patch，見「為什麼
OpenMANET 不需要這個修正」。缺陷 2
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
（`restart`）不夠，要走 bus reset。2026-08-24 查明原因：**這台 AP 的驅動是編進核心
的**，所以 `wifi reload` 卸載不掉它、永遠不會重跑 probe —— `Resetting Morse Chip` 在
47907 秒的 uptime 裡只出現一次，在開機時。只有 bus reset 那條路徑碰得到晶片。（原本
把它歸因於 `reset-gpios` flag 0，該解釋已撤回。）第三次跟第二次一樣，前面什麼
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
| **`reset-gpios`** | pin 17 flag 1 | pin 17 flag 0 —— **兩邊的 flag 都是惰性的**：2.0.1 沒有任何 `gpiod_` 呼叫，RESET_N 兩邊都會觸發 |
| **chip select 數** | **兩組**（gpio 8、gpio 7），來自 `dtparam=spi=on` | **一組**（gpio 8）|
| 腳位提升／下拉 | `halow_pins`：17 上拉，5/23/24 下拉；沒有 `spi0_pins` 群組，所以 MISO/MOSI/SCLK 維持 BCM2711 預設（下拉）| `morse_reset` 17 上拉、`morse_irq` 5 上拉、`morse_wake` 23 上拉、`morse_busy` 24 下拉；`spi0_pins` 9/10/11 上拉 |

**AP 為什麼從來沒踩到那三個缺陷。** 一半在那幾列裡，一半不在。50 MHz 是驅動的延遲
換算剛好會產生可用值的唯一時脈，所以缺陷 3 隱形，而 station 的 10 MHz 讓它現形。缺陷 2
**不是**這張表任何一列能解釋的：藏住它的是 OpenMANET 帶著、而 Raspberry Pi OS 沒有的
一份核心 patch，見「為什麼 OpenMANET 不需要這個修正」。上面那列的 `reset-gpios` 差異
什麼都沒解釋，因為驅動根本不讀那個 flag。`patches/upstream/` 那組修正是撐住 station
通過這兩個缺陷的東西。

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
值的時脈（缺陷 3）。

**2026-08-24 更正。** 這一段原本還聲稱 `reset-gpios` flag 0 也藏住了缺陷 2，理由是
`gpiod_set_value(reset, 1)` 把腳位拉高、RESET_N 從不觸發。那是錯的：`morse_driver`
2.0.1 全樹沒有任何 `gpiod_` 呼叫，flag 被解析後就丟棄，RESET_N 到處都會觸發。藏住
缺陷 2 的是 device tree 看不見的東西 —— 一份核心 patch。細節見「為什麼 OpenMANET
不需要這個修正」。

同一份文件的屬性表對 `reset-gpios` 只寫「GPIO descriptor connected to the MM6108
RESET line」，**對極性隻字未提**。

**2026-08-24 更新：還有第六個，而且不只是 device tree。** HT-HC01P 同樣出貨帶著 Morse
的參考**板級設定檔** —— `bcf_mf08551.bin`，也就是 EKH01-03 EVK 的 BCF —— 而 Heltec 自己
的 `bcf_HC01_V2_H.bin` 就擺在旁邊的 `/lib/firmware/morse/` 裡沒人用。這一個不是看不見的：
模組收得到 −56 dBm，而它發出去的東西沒有一個到得了 AP。完整經過在本檔案最上面的
2026-08-24 段落。

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

**2026-08-24 解決，而且上面那個標題講得比證據多。** 設 `rsn_beacon_mode=2` 是有效的。
HT-HC01P 之後讀到的是 `[WPA2-SAE-CCMP][SAE-H2E][ESS]` 而不是 `[WEP]`，beacon 的 RSN 元素
在那塊板子上也解得乾乾淨淨 —— group 與 pairwise 都是 CCMP、AKM `00-0f-ac-08`（SAE）、
RSN capabilities `0x00cc`，MFPC 和 MFPR 都有設。它只是不是擋住那塊板子的原因。擋住它的是
BCF，見本檔案最上面那一段。

**那個矛盾其實不是矛盾。** HT-H7608，同樣 1.15.3，在整個 2026-08-24 這一場裡都以
`auth_alg=sae` 和完成的四向交握掛在這台 AP 上。所以 `[WEP]` 那個觀察是真的，
`rsn_beacon_mode=2` 也確實解決它，但**1.15.3 是否非要它不可，仍然沒有被確立** —— H7608
從來沒有被直接掃描過，而引發原本那條註記的 `auth_alg=0` 只是單獨一行 log，從未再現。能說
的比標題窄：這台 AP 的 S1G beacon 預設省略 RSN IE，1.15.3 的 station 把它讀成 `[WEP]`，
而 `rsn_beacon_mode=2` 把那個元素放到它看得到的地方。

## SPI 時脈才是吞吐量的天花板，而 4 MHz 要等它拉高之後才划算

2026-08-24。完整方法與原始數據在
[`logs/2026-08-24-spi-clock-is-the-throughput-ceiling.txt`](logs/2026-08-24-spi-clock-is-the-throughput-ceiling.txt)。

**把 station 的 SPI 時脈從 10 MHz 拉到 50 MHz，吞吐量變成 2.6 倍，而且零 SPI 錯誤** ——
同時也推翻了一個**已經量過而且量錯**的結論。

| SPI 時脈 | 空中頻寬 | 上行 | 下行 |
|---|---|---|---|
| 10 MHz | 2 MHz | 3.16 | 2.46 |
| 10 MHz | 4 MHz | 2.66 | 2.29 ← *看起來像退步* |
| 50 MHz | 2 MHz | 3.55 | 3.27 |
| **50 MHz** | **4 MHz** | **6.86** | **6.80** ← 真正的答案 |

單位 Mbit/s，全部在同一位置（station 在 AP 旁邊的桌上）、每次 1 MiB 不可壓縮酬載走
SSH、每格三次（10 MHz 那兩列除外）。

**4 MHz 確實會讓吞吐量翻倍，但在主機匯流排是瓶頸的時候它顯示不出來。** 匯流排已經飽和時
把頻道加寬，只會多帶來重傳：10 MHz/4 MHz 時 AP 記錄到 1569 次 tx retries、155 次
tx failed，而 10 MHz/2 MHz 時是約 4 次和 0 次。用預設時脈量，「4 MHz 對這條鏈路沒有
幫助」差一點就被寫成結論。

### 匯流排的時間花在哪：我們自己的修正，被乘以五倍

空中那側全程都正常。負載下 4 MHz 時 mmrc 選中 4 MHz MCS7，airtime **755** 對比 2 MHz
MCS7 的 **1582** —— 訊框時間減半，正是頻寬加倍該有的樣子 —— 但應用層吞吐量沒有動。
**當你正在測試的那一層改善了、而你在意的數字沒有動，瓶頸就在別的地方。**

station 的 SPI 傳輸尺寸分佈說明了一切：

```
256-511 bytes    2,643,750 筆   <- 佔全部筆數的 97%
16-31               53,614
512-1023            13,422
2048-4095           12,368
1024-2047            3,220
4096-8191               75
                 ---------
合計             2,721,694 筆訊息、794,653,458 位元組
```

那個 256–511 的區間，就是**本 repo 自己修缺陷 3 時裝上的 250 位元組交易間填充**
（`spi.c` 裡的 `SPI_MIN_DELAY_BYTES`）。每筆 250 位元組，合計約 661 MB —— 佔那
794 MB 的 **約 83%。SPI 匯流排上每一個位元組裡有 83% 是填充。**

這個填充是正確且必要的：晶片數的是 **clock 數**而不是時間，這正是缺陷 3 的全部內容。
但也正因為它數 clock，它的實際耗時與時脈成反比：

```
250 位元組 = 2000 個 clock  ->  10 MHz 時 200 µs
                            ->  50 MHz 時  40 µs
```

跑在 10 MHz 等於把一個必要開銷乘以五倍。那時候兩端都出現流量控制 —— `Queue stop`
station 148、AP 134。

### 階梯測試，以及走線在 50 MHz 下是乾淨的

`spi_clock_speed` 是模組參數，依 `spi.c:1464` 的註解它會覆寫 device tree，所以不用
重編：

```sh
rmmod morse
modprobe morse country=SG bcf=bcf_fgh100mhaamd.bin spi_clock_speed=50000000
nmcli con up halow
```

| SPI 時脈 | 上行 | 下行 | SPI 錯誤 |
|---|---|---|---|
| 10 MHz | 2.66 | 2.29 | 0 |
| 20 MHz | 5.732 / 5.774 / 5.746 | 5.526 / 4.690 / 5.474 | 0 |
| 50 MHz | 6.666 / 7.047 / 6.866 | 7.164 / 7.017 / 6.218 | 0 |

`/sys/class/spi_master/spi0/statistics` 底下的 `errors` 和 `timedout` 在每一階都是 0，
`dmesg` 在任何速度下都沒有出現 write failure、read failure、CRC error、CMD53 或
CMD63。**所以 SenseCAP M1 的 mPCIe 走線在 50 MHz 下是乾淨的** —— 本 repo overlay 裡
那個 10 MHz 是保守而非必要，代價是 2.6 倍的吞吐量。曲線的形狀也有意義：10→20 MHz
超過兩倍，20→50 MHz 只多約 20%，那正是「匯流排不再是限制、空中介面重新接手」的樣子。

給個尺度：社群那串回報 20 英尺下 2 MHz 3.68 Mbps、4 MHz 8.33 Mbps，主機也是 50 MHz
SPI。這條鏈路現在是 2 MHz 3.55（他們的 96%）、4 MHz 6.86（82%）。

### 選 4 MHz 頻道：SG 的法規表

光設 `s1g_chanbw=4` 不夠，**頻道號碼也要跟著改**。維持 `channel=42` 會被拒絕，訊息值得
認得：

```
netifd: radio1: Couldn't find regulatory data for SG with ch=42 bw=4 op= chzn=
netifd: radio1: wifi-iface 0 mode=ap ignored; requires valid country/channel setup
```

表在 `/usr/share/morse-regdb/channels.csv`。SG 在 920–925 MHz 的全部條目：

| bw | s1g_chan | 中心 MHz | 對映 5G |
|---|---|---|---|
| 1 | 37 / 39 / 41 / 43 / 45 | 920.5 … 924.5 | 149 … 165 |
| 2 | 38 | 921.0 | 151 |
| 2 | 42 | 923.0 | 159 |
| **4** | **40** | **922.0** | 155 |

**SG 只有一個 4 MHz 頻道：channel 40，中心 922.0 MHz** —— 這也就是 Heltec HT-HC01P
出廠設成 channel 40 的原因。

```sh
uci set wireless.radio1.channel='40'
uci set wireless.radio1.s1g_chanbw='4'
uci commit wireless && wifi reload
```

用 `morse_cli -i wlh0 channel` 讀回無線電實際的狀態。`iw` 只會顯示 dot11ah 的對映，
4 MHz 在那裡呈現為 80 MHz 寬的對映頻道，2 MHz 則是 40 MHz。

### 對上游工作的一個後果：50 MHz 下缺陷 3 不再重現

**在 50 MHz 下，驅動那個錯誤的公式剛好會算出正確答案。**
`40000ns / (clk_period * 8)` 在 50 MHz 算出 250 位元組 —— 正確值 —— 這正是為什麼所有
跑參考時脈的廠商從來看不到缺陷 3。本 repo 會發現它，只因為我們跑在 10 MHz，同一個公式
在那裡算出 50，而 50 會失敗。

修正本身不受影響：`SPI_MIN_DELAY_BYTES` 是無條件的 250 下限，在 50 MHz 產生同樣的值、
依然正確。缺陷 2 也不受影響 —— 它講的是初始化爆發期間的 chip select 而不是時序，而且
在這裡依然會發生，因為本 repo 的 overlay 設 `reset-gpios` flag 1，RESET_N 真的會觸發。

**但任何人要從本 repo 重現缺陷 3，都必須先把時脈調回去：**

```sh
modprobe morse country=SG bcf=bcf_fgh100mhaamd.bin spi_clock_speed=10000000
```

這件事該在 PR 裡明講而不是藏起來：**暴露這個缺陷的組態是非預設時脈。** 那是支持修正的
論據，不是反對的 —— 一個驅動不該依賴特定時脈才算得出正確的延遲。

### 最終組態：時脈由 overlay 提供，不是模組參數

模組參數是為了不重編就能跑階梯測試。最終組態把時脈放回它該在的地方 —— device tree。
本 repo 的 `overlays/mm610x-spi-sensecap.dts` 現在是 `spi-max-frequency = <50000000>`，
並附註解說明理由與如何還原。

```
AP       channel 40 + s1g_chanbw 4   ->  922.0 MHz、4 MHz 操作、2 MHz 主頻寬
station  overlays/mm610x-spi-sensecap.dts -> 50 MHz，已編譯安裝
         /etc/modprobe.d/morse.conf 回到：options morse country=SG bcf=bcf_fgh100mhaamd.bin
```

原本的 10 MHz blob 保留在旁邊，檔名 `mm610x-spi-sensecap.dtbo.10mhz`（`.orig` 也是
10 MHz）。兩個都是**用 `fdtget` 驗過內容**而不是靠檔名相信 —— `.dtbo` 是 50000000、
`.10mhz` 是 10000000、`.orig` 是 10000000。

驗證是從冷開機做的，而且刻意驗 **blob 和實際節點**、不是驗原始檔：

```
modprobe.conf            options morse country=SG bcf=bcf_fgh100mhaamd.bin
spi_clock_speed 參數      0                 <- DT 在管
實際 DT 節點值            02 fa f0 80       = 50,000,000
dmesg 裡 "Overriding..."  0 次              <- 完全沒有參數介入
spi errors 0   timedout 0   driver failures 0
上行  7.463 / 7.372 / 7.401 Mbit/s
下行  6.303 / 6.979 / 6.919 Mbit/s
```

**缺陷 3 仍然重現得出來**，因為模組參數對 device tree 的覆寫是**雙向**的
（`spi->max_speed_hz = max_speed_hz`，無條件賦值）：

```sh
modprobe morse country=SG bcf=bcf_fgh100mhaamd.bin spi_clock_speed=10000000
```

所以 repo 保住了重現路徑，又不必留著那個慢的預設值。如果要連 device tree 一起還原，
把 `mm610x-spi-sensecap.dtbo.10mhz` 蓋回去再重開機即可。

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

**2026-08-24 重寫。** 原本站在這裡的解釋是錯的，取代它的說法證據更硬，而且對上游論點
更有利。錯的只有「OpenMANET 為什麼逃過一劫」這一段；下面的實測與 `patches/upstream/`
裡的修正都不受影響。

**它有 reset 晶片。** 它自己的開機 log：

```
[   10.066857] morse micro driver registration. Version 0-rel_mm6108_2_0_1_2026_Jun_11
[   10.074667] morse_spi spi0.0: morse_of_probe: Reading gpio pins configuration from device tree
[   10.083313] Resetting Morse Chip
[   10.894587] morse_spi spi0.0: Loaded firmware from morse/mm6108.bin, size 468304, crc32 0xbe7b5c8f
```

`Resetting Morse Chip` 是 `morse_hw_reset()` 裡的 `pr_info()`，印在 `gpio_request()`
成功之後、腳位被拉低之前。這台 AP 跑的**就是本 repo 讀的那一版驅動 2.0.1**，而且和
station 一樣在每次 probe 都打 RESET_N 脈衝。

**`reset-gpios` 那個 flag 是惰性的。** `morse_driver` 2.0.1 全樹沒有任何 `gpiod_`
呼叫 —— `git grep gpiod_` 零命中。`of.c` 用 `of_get_named_gpio()` 讀腳位，那個函式只
回傳編號、丟掉 flags；`hw.c` 的 `morse_hw_reset()` 用舊式整數 API，而
`gpio_direction_output()` 就是 `gpiod_direction_output_raw()`，按定義繞過極性反轉。
把 flag 從 0 改成 1 不可能改變驅動的行為。這正是為什麼「單獨測 `reset-gpios` flag 0
毫無效果」—— 下面記為需要解釋的怪事 —— 其實就是正確結果。

**OpenMANET 真正有的是一份核心 patch，而且是 Morse Micro 自己寫的。**
`OpenMANET/firmware` 的
`target/linux/bcm27xx/patches-6.6/991-0007-spi-support-control-cs-pin-on-init.patch`
（`MorseMicro/openwrt` 裡有同一份，檔名 `999-001-morse-spi_driver_gpio_descriptor.patch`），
作者 Sagar Bussa <sagar.bussa@morsemicro.com>，2025-03-13。它在核心的 SPI core 加了
一個旗標：

```diff
--- a/include/linux/spi/spi.h
+#define SPI_CONTROLLER_ENABLE_CS_GPIOD BIT(9)

--- a/drivers/spi/spi.c          /* spi_setup() */
   if (ctlr->use_gpio_descriptors && ctlr->cs_gpiods &&
-      ctlr->cs_gpiods[spi->chip_select] && !(spi->mode & SPI_CS_HIGH)) {
+      ctlr->cs_gpiods[spi->chip_select] && !(spi->mode & SPI_CS_HIGH) &&
+      !(ctlr->flags & SPI_CONTROLLER_ENABLE_CS_GPIOD)) {
           spi->mode |= SPI_CS_HIGH;

--- a/drivers/spi/spi.c          /* spi_set_cs() */
-      gpiod_set_value_cansleep(spi_get_csgpiod(spi, 0), activate);
+      gpiod_set_value_cansleep(spi_get_csgpiod(spi, 0),
+          (spi->controller->flags & SPI_CONTROLLER_ENABLE_CS_GPIOD) ? enable : activate);
```

它的 commit message 把用途講得很白：*「The Morse Micro driver requires control of the
chip select line during initialisation, to correctly sequence the line to enter SPI
mode. This patch adds a bit which instructs the bus to not force the chip select high
in during spi_setup.」*

核心有這份 patch 時，`morse_spi_initsequence()` 的 `SPI_CS_HIGH` 翻轉才真的會解除
CS，74 個訓練時脈才落得正確，晶片在每次 reset 之後都回得到 SPI 模式。沒有這份 patch
時，`spi_setup()` 會對 `cs-gpios` 裝置把 `SPI_CS_HIGH` 強制加回去，翻轉變成空操作，
訓練訊號在晶片被選中的狀態下送出去。**這就是 AP 與 station 之間的全部差別** —— 同樣的
SenseCAP M1 硬體、同樣的 MM6108A1、同樣的驅動 2.0.1、同樣的 `cs-gpios = <&gpio 8 1>`、
probe 時同樣會 reset。只有核心樹不同。

**第三方的獨立佐證。** `OpenMANET/packages` 帶著
`morse-micro/mm6108-driver/patches/021-spi-demote-cs-gpiod-warning-to-runtime.patch`，
它的檔頭寫著：*「`SPI_CONTROLLER_ENABLE_CS_GPIOD` 不是主線核心的旗標；它是由一份
Morse Micro 對 `include/linux/spi/spi.h` 的 patch 加上去的，而只有 bcm27xx 目標帶著
那份 patch……驅動的 `#warning` 退路在核心的 `-Werror` 下是致命的……沒有它，CS 可能
在 `spi_setup` 期間被強制拉高。」* 有人在 ramips 目標上踩到了缺陷 1，用和本 repo 一樣
的方式修掉，並在同一段文字裡描述了缺陷 2 的機制。

**這讓上游論點變強而不是變弱。** Morse Micro 自己對缺陷 2 的解法是修補核心的 SPI
core；本 repo 的解法是在驅動內用 `SPI_NO_CS`，不需要動核心，因此在原廠 Raspberry Pi
OS 核心上就能用。上面記為「一個本 repo 構成反例的廠商說法」的那句 *「patching the
kernel is practically required」*，現在背後有一份具名、有作者、Morse 自己寫的 patch。
反例依然成立，而且更銳利了。

**下面這組實測不受影響。** 在這塊板子上量的（模組電源在 GPIO18，我們控制得到）：

| | 回應 |
|---|---|
| 冷上電、完全不訓練 | `ff 01 ff` —— **對齊，本來就在 SPI 模式**（3/3） |
| 同一次上電，打 RESET_N 脈衝後 | `ff c0 7f` —— **偏移，被踢出 SPI 模式** |
| 之後補訓練 | `ff c0 7f` —— 救不回來（中間已有一次 CS 拉低的命令） |

第 1→2 步是最乾淨的：同一次上電、只多了一個 reset 脈衝，狀態就從對齊變偏移。
**RESET_N 會把晶片踢出 SPI 模式**，而只有訓練訊號能把它放回去。這就是為什麼壞掉的
訓練在未修補的核心上是致命的、在修補過的核心上完全看不出來 —— reset 兩邊都會發生。

**但要註明：上電後的狀態不是百分之百確定的** —— 五次冷上電裡有一次上電就已經偏移。
原因不明。晶片**通常**上電就在 SPI 模式，不是必然。

這也解釋了兩句我們很早就搜到、當時看不懂的社群回覆 —— *「實體斷電重來就好了，軟體
重開機不行」*、*「我們大部分佈署都用一個 reset script 在開機時 toggle reset 線」*。
實體斷電讓晶片重新進入 SPI 模式；軟體重開機不行，因為模組沒斷電，仍停在上一次
RESET_N 脈衝留下的狀態。至於為什麼單獨測 `reset-gpios` flag 0 毫無效果：驅動根本不讀
那個 flag，所以沒有東西可以改變。本檔案原本為那個結果給出的一長串解釋，就此撤回。

**有了修正，上面這些都不重要。** 驅動會在 reset 之後立刻用正確方式送訓練，所以不管
晶片上電時是什麼狀態、被 reset 過幾次、核心有沒有帶 Morse 那份 SPI core patch，都會
進到 SPI 模式。OpenMANET 的做法是**要求一個修補過的核心**；這個修正讓驅動在任何核心
上都是對的。

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

`reset-gpios` 這一項值得留個墓誌銘。當時的推論是：flag 是 `GPIO_ACTIVE_LOW`，而
`morse_hw_reset()` 用 `gpiod_set_value(reset, 1)` 宣告 reset，所以 flag 1 拉低、
flag 0 拉高，意思是 OpenMANET 上的 reset 脈衝很可能從來沒發生過。**2026-08-24 更正：
那個推論的前提是錯的** —— `morse_hw_reset()` 用的是舊式整數 API 而不是
`gpiod_set_value()`，flag 從頭到尾沒被讀過，OpenMANET 上的 reset 每次開機都確實發生。而今晚修好 `tools/mmcspi.py` 的 `reset_module()`、讓
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
