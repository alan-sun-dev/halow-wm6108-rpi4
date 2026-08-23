# Wio-WM6108 (MM6108A1) on SenseCAP M1 — bring-up state, 2026-08-19

*[中文版](NOTES.zh-TW.md)*

## 2026-08-23, session close — where things were left

The work is finished and submitted. Three defects, all in the driver's `spi.c`:
the build `#warning` under `-Werror`, the init training burst going out with CS
asserted, and the inter-transaction delay being scaled by clock rate when the
chip counts clocks. The clean series is `patches/upstream/000{1,2,3}-*.patch`
against tag `mm6108-2.0.1` — verified on hardware with no module parameters, and
submitted as [morse_driver#16](https://github.com/MorseMicro/morse_driver/pull/16).
`patches/morse-driver-2.0.1-rpi-spi.patch` remains the investigation's working
file (instrumentation, experiment parameters); it is not the one to send anyone.

**The series is verified under the repo's stock overlay** — RESET_N genuinely
firing, two chip selects, no module parameters beyond `country=` and `bcf=`,
confirmed on a cold boot with the module auto-loaded. Full capture in
[`logs/2026-08-23-stock-overlay-clean-series-environment.txt`](logs/2026-08-23-stock-overlay-clean-series-environment.txt).
That run also reproduced the original failure under the same device tree by
loading an unfixed build — `c0 7f`, CMD63 `-71` — so the A/B holds the device
tree constant and varies only the driver binary.

**Board `E4:5F:01:52:55:04` is now in a clean, working state**, at
`192.168.200.182`:

- `~/halow-test/morse_driver` is tag `mm6108-2.0.1` plus `patches/upstream/` and
  nothing else (`git diff --stat` → `spi.c` only, 62 insertions, 8 deletions)
- the stock overlay is installed; the experiment overlay is kept beside it as
  `mm610x-spi-sensecap.dtbo.experiment`, and the untouched original as `.orig`
- `config.txt` keeps `gpio=18=op,dh`, which README and TESTING both require
- the clean build is installed at
  `/lib/modules/6.6.51+rpt-rpi-v8/updates/{morse.ko.xz,dot11ah/dot11ah.ko.xz}`,
  byte-identical to the build, with the stale 2026-08-22 copies kept as
  `*.stale-20260822`
- `/etc/modprobe.d/morse.conf` carries `options morse country=SG
  bcf=bcf_fgh100mhaamd.bin`, so the auto-load is correct rather than missing its
  regdomain
- the probe instrumentation that was in the tree is saved at
  `~/halow-test/SAVED-probe-tree-20260823-0914.patch` and
  `~/halow-test/SAVED-morse-probe-build.ko`

**A correction.** An earlier version of this section said the loaded module "has
the probes but **not** the SPI fixes", on the evidence of `strings morse.ko |
grep -c SPI_NO_CS` returning 0. That check is worthless: `SPI_NO_CS` is a macro
constant and appears in no string literal anywhere in the patch, so a fixed build
scores 0 as well. The module in question did have the fixes. Related, from the
same day: a first attempt to read the device tree used `xxd`, which this image
does not have, with the error swallowed by `2>/dev/null` on the same line. Any
`grep -c` that returns 0 needs a positive control beside it — the readings in the
new log were all taken that way.

**Note on ordering.** "Once the chip has been addressed with CS asserted it does
not recover" applies to a training burst with no preceding reset. A failed probe
by an unfixed module does not poison the chip for a subsequent fixed one, because
probe resets before it bursts — measured 2026-08-23.

Association and data transfer are verified as of 2026-08-23, cross-implementation
against Morse's own OpenWrt build as the AP: WPA3-SAE with PMF, DHCP over the
air, 4 MiB checksummed in both directions, 200/200 pings at 0% loss, 88.9 MB of
SPI traffic with `errors 0`. See
[`logs/2026-08-23-association-verified-environment.txt`](logs/2026-08-23-association-verified-environment.txt),
which also lists what is still unknown — range, throughput ceiling, link margin
(RSSI reads 0 dBm), and two unexplained events.

## The two boards, side by side (2026-08-23)

Both are the same hardware running the same firmware bytes. Everything that
differs is in the last three rows, and those three rows are what this whole
investigation was about.

| | Station | AP |
|---|---|---|
| **Role** | HaLow client, the patched driver | HaLow AP, Morse's own build |
| Host | RPi 4B Rev 1.4 (`c03114`), 4 GB | RPi 4B Rev 1.4 (`c03114`) |
| Carrier / module | SenseCAP M1 + Wio-WM6108 (MM6108A1) | same |
| Serial | `100000004851d437` | `1000000093d173dd` |
| eth0 MAC | `e4:5f:01:52:55:04` | `e4:5f:01:52:57:e7` |
| HaLow netdev | `wlan1`, `9c:04:b6:ff:df:fe` | `wlh0`, `3c:1a:cc:70:3f:ca` |
| OS | Raspberry Pi OS Lite 64-bit, bookworm | OpenMANET 24.10 (OpenWrt `r28739-d9340319c6`, `bcm27xx/bcm2711`) |
| Kernel | `6.6.51+rpt-rpi-v8` | `6.6.138` |
| Driver | `mm6108-2.0.1` (`98e1936`) + `patches/upstream/` | Morse's OpenWrt build, compiled into the kernel |
| Driver version string | `0-rel_mm6108_2_0_1_2026_Jun_11` | identical |
| Load form | module, `srcversion 87374779AA811C291578351` | built in, nothing in `lsmod` |
| Parameters | `country=SG bcf=bcf_fgh100mhaamd.bin` via `modprobe.d` | UCI `radio1`, plus `enable_ext_xtal_init=1`, `enable_ps=0`, `enable_twt=0` |
| Supplicant | stock `wpa_supplicant` 2.10 under NetworkManager 1.42.4 | `hostapd_s1g` / `wpa_supplicant_s1g` (Morse builds) |
| `mm6108.bin` | 468304 bytes, md5 `27199922700526947ec1efdaaff8163d` | byte-identical |
| `bcf_fgh100mhaamd.bin` | 1251 bytes, md5 `4e128ad574304d1aec778c5ba5611f8f` | byte-identical |
| SPI controller | `brcm,bcm2835-spi`, `spi0.0` | same |
| DT node | `mm610x@0` | `mm6108@0` |
| Radio | managed, `country=SG` | AP, S1G 923.0 MHz / BW 2 MHz, mapped ch157, 22 dBm, SSID `BCM2711-57e7`, SAE + PMF, `wds=1` |
| **SPI clock** | **10 MHz** (`00 98 96 80`) | **50 MHz** (`02 fa f0 80`) |
| **`reset-gpios`** | pin 17 **flag 1** — RESET_N genuinely fires | pin 17 **flag 0** — RESET_N never fires |
| **Chip selects** | **two** (gpio 8, gpio 7), from `dtparam=spi=on` | **one** (gpio 8) |
| Pin pulls | `halow_pins`: 17 up, 5/23/24 down; no `spi0_pins` group, so MISO/MOSI/SCLK sit at the BCM2711 default (down) | `morse_reset` 17 up, `morse_irq` 5 up, `morse_wake` 23 up, `morse_busy` 24 down; `spi0_pins` 9/10/11 up |

**Why the AP never hit any of the three defects** is in those rows. 50 MHz is the
one clock at which the driver's delay scaling happens to produce a working value,
so defect 3 stays invisible. `reset-gpios` flag 0 means RESET_N never fires, so
the chip is never knocked out of SPI mode and defect 2 stays invisible. The
station runs 10 MHz with RESET_N actually firing, which exposes both — and the
series in `patches/upstream/` is what carries it through.

The pin-pull and chip-select differences were each eliminated as causes during
the A/B (see the sections below); they are listed here because they are real
configuration differences, not because they matter to the fault.

*Reading device-tree properties: values are big-endian. `od -An -tx1` prints the
bytes in order and is the safe form. `hexdump -e '1/4 "%08x "'` and `%d` print
host-endian, so every word comes out byte-reversed — `02 fa f0 80` (50000000)
displays as `80f0fa02`. `od` is absent from the OpenMANET image and `xxd` from
both; check the tool exists before believing an empty read.*

## Gotcha: a ghost station entry on the AP looks exactly like a working link

Hit on 2026-08-23 while reconnecting the station after the NetworkManager profile
had been deleted and recreated.

**Symptom.** Everything says the link is up and nothing passes.

  station   iw dev wlan1 link      -> Connected to 3c:1a:cc:70:3f:ca
            wpa_cli status         -> wpa_state=COMPLETED, key_mgmt=SAE,
                                      pairwise=CCMP, pmf=2
            NetworkManager         -> connected
            an address             -> 10.41.0.208/16
  AP        iw dev wlh0 station dump -> authorized: yes, associated: yes

  and yet   ip neigh               -> 10.41.254.1 FAILED   (ARP never resolves)
            ping both directions   -> 100% loss
            loss over three runs   -> 60%, then 86.7%, then 100%

Nothing in dmesg on either side. No SPI errors. The authentication layer
completes; data frames do not get through.

**Cause.** The AP was holding a stale entry for the station's MAC from the
previous association. Deleting the NetworkManager profile did send a deauth --
`wlan1: deauthenticating from 3c:1a:cc:70:3f:ca by local choice (Reason:
3=DEAUTH_LEAVING)` is in the station's dmesg -- and the AP did not act on it. Four
minutes later the entry was still there, `inactive time: 242070 ms`, `tx failed:
20`, with the AP pinging into the void. The next association was then built on
top of that entry.

**`wifi reload` does not clear it.** The interface is torn down and recreated --
`wlh0` even changes ifindex -- and the entry survives. This was measured, not
assumed: after a reload with the station provably disconnected, the AP's table
still had one entry for its MAC.

**What does clear it**, on an image with no `hostapd_cli`:

```sh
iw dev wlh0 station del 9c:04:b6:ff:df:fe
```

Table empties immediately, and the station associates and passes traffic on the
next attempt -- ARP resolved, 20/20 pings, 0% loss.

**How to recognise it.** Compare the two sides' byte counters rather than their
status flags, which both lie. The station had transmitted 22365 bytes while the
AP had received 9559 of them; the AP's `tx failed` was climbing with `tx retries`
at 0. An entry whose `inactive time` does not match what the station has actually
been doing is the tell.

Worth knowing generally: an S1G AP is built to tolerate clients that sleep for a
long time, so a long inactivity timeout is by design and a dead entry will not be
aged out quickly. Do not wait for it.

## Reading the link: RSSI, the numbers `iw` prints, and one way to brick the radio

Three traps, all found on 2026-08-23 while trying to work out whether 5% packet
loss was a signal problem. The first of them is a correction to what this section
said when it was first written.

### RSSI: it *is* populated — a zero means the signal is off the top of the scale

**This subsection previously concluded that the chip does not fill the RSSI
field. That was wrong, and it was wrong for the usual reason: the only two boards
available reported 0, and one observation repeated twice was treated as a
property of the hardware.**

A third node settled it. On 2026-08-23 a Heltec HT-H7608 (same MM6108 silicon,
Heltec's own OpenWrt build over SDIO, driver 1.15.3, a different `mm6108.bin`)
joined the same AP from a few metres away. The AP is the OpenMANET board — the
same driver family that reports 0 for our station. Its own hostapd log, within
the same minute:

```
authentication: STA=9c:04:b6:ff:df:fe ... rssi=0      <- our station, on the same bench
authentication: STA=0c:bf:74:2c:dd:05 ... rssi=-71    <- the Heltec, a few metres away
```

and `iw dev wlh0 station dump` agreed: ours pinned at `0 dBm`, the Heltec at
`-73`/`-75 dBm` and varying. Same AP, same receiving chip, same moment. The
measurement path works.

So the driver trace below is still correct — `SIGNAL_DBM` is declared at
`mac.c:7180`, `rx_status->signal` is assigned from `hdr_rx_status->rssi` at
`mac.c:6123`, nothing overwrites it — but the value arriving as 0 is not the
firmware refusing to measure. It is what the chip reports for that particular
link.

**The likely reason is saturation.** The two SenseCAP M1 boards sit on the same
bench. At 923 MHz over 0.3 m the free-space path loss is about 21 dB, so a 22 dBm
transmitter puts roughly **+1 dBm** into the receiver — above the top of the
scale. A reading clipped to 0 is exactly what that would look like, and it
explains every zero in this repo: the two boards have never been more than about
a metre apart.

**Not proven.** The test that would prove it is to attenuate the link and see the
value drop into range. Do not try to do that with `iw set txpower fixed` — see
the next subsection. Moving a board physically is the safe way, and it has not
been done.

**What to take from this practically:**

- `signal: 0 dBm` on this driver means "off the top of the scale", not "not
  measured". Two boards on one bench cannot produce a usable RSSI, and no
  question of the form "is this a signal problem?" can be answered in that
  arrangement.
- `msta->avg_rssi` is 0 at bench distance, so its consumers — mesh peer selection
  (`mesh.c:628`), `bss_stats`, and the rate-controller seed (`rc.c:293` →
  `mmrc_init_rates`) — get a 0. In the last one, with
  `MMRC_SHORT_RANGE_RSSI_LIMIT = -70`, a zero passes `rssi >= -70` and the table
  starts at MCS7, making the 1/2 MHz branch that would start at MCS3 unreachable.
  That is a real effect of the bench arrangement, not a driver defect.
- The unused chip facilities noted before are still unused, and still worth
  knowing about: `MORSE_CMD_ID_GET_RSSI` (`morse_commands.h:2825`, with
  `rssi0/1/2`) is defined and never called, `morse_skb_rx_status.noise_dbm` is
  never read, and `morse_cmd_evt_scan_result.rssi` is used only on the full-mac
  `wiphy.c` path.

The radiotap capture quoted before — thirty frames from our station, all
`0dBm` — is still an accurate capture. It was taken while both boards were on the
bench, so it shows the same clipped value, and it does not support the conclusion
that was drawn from it.

### `iw set txpower fixed` can leave the transmitter dead, and `wifi reload` will not fix it

Found by breaking the AP with it on 2026-08-23, while trying to test the
saturation hypothesis above.

`iw dev wlh0 set txpower fixed 1000` then `... 0` then `... 2200` on the
OpenMANET AP. Afterwards `iw dev wlh0 info` reported `txpower 22.00 dBm` and the
interface looked entirely healthy — but nothing could hear it. Both stations
dropped, and the AP's own hostapd log showed the shape of it clearly:

```
authentication: STA=9c:04:b6:ff:df:fe ... rssi=0
wlh0: STA 9c:04:b6:ff:df:fe IEEE 802.11: did not acknowledge authentication response
authentication: STA=0c:bf:74:2c:dd:05 ... rssi=-71
wlh0: STA 0c:bf:74:2c:dd:05 IEEE 802.11: did not acknowledge authentication response
```

Receive still worked for both stations. Transmit did not. `wifi reload` — which
tears down and recreates the interface — did **not** recover it. A full reboot
did.

Diagnosis note: the first read of this was "the station's receiver is broken",
because the station could not scan. The station was fine. What pointed the right
way was that the AP's station table emptied and *both* stations failed at once,
which no station-side fault explains.

### `iw` reports the dot11ah mapping, not the radio

This one is more dangerous, because the numbers look plausible.

| | what `iw dev wlan1 link` says | what the radio is doing |
|---|---|---|
| Frequency | 5785 MHz (channel 157) | **922–923 MHz** |
| Rate | VHT-MCS 7, 150.0 MBit/s, 40 MHz | **MCS 0 and MCS 5**, 1–2 MHz |

The dot11ah shim presents S1G as a 5 GHz-numbered band so that mac80211 and
stock userspace tools work unmodified. Everything `iw` prints about frequency and
bitrate is that mapping. A reported 150 Mbit/s on a link measuring 1.3 Mbit/s is
not a contradiction to investigate; it is the mapping.

Cross-check against `debugfs .../morse/mmrc_table`, which shows the real rate
selection, or capture radiotap. On this link mmrc had selected 2 MHz SGI MCS0
with 2 successes in 12 attempts, which matches the measured throughput and does
not match the 150 Mbit/s.

### How to capture radiotap, since neither attempt worked first time

- **The build must have monitor support.** `morse-$(CONFIG_MORSE_MONITOR) +=
  monitor.o` in the Makefile, and the build line in TESTING.md does not pass it.
  Check with `strings morse.ko | grep -c morse_mon` before concluding a capture
  found nothing. Our station build has it compiled out, so no monitor capture is
  possible there without a rebuild.
- **The `morse0` netdev being up is not enough.** Frames reach it only when
  `mors->monitor_mode` is true (`mac.c:6889`), which is set from
  `IEEE80211_CONF_MONITOR` (`mac.c:4033`) — that is, only while a monitor vif
  exists. Adding one is enough; it does not have to be the capture interface:

  ```sh
  iw phy phy3 interface add mon0 type monitor && ip link set mon0 up
  ip link set morse0 up
  tcpdump -i morse0 -c 30 -e -nn      # radiotap with the real MHz and MCS
  iw dev mon0 del; ip link set morse0 down
  ```

  Done on the AP this way, the AP kept serving — `type AP` and the SSID were
  unaffected throughout, and nothing persistent was changed.
- `mon0` itself only shows the AP's own beacons. `morse0` is the one carrying
  received frames with the chip's rx status.

## The AP's transmitter stalls, and the HaLow link is your way back in

Both found on 2026-08-23, hours apart, and the first one may explain several
things this file had recorded as unexplained.

### The OpenMANET AP stops transmitting, with nothing to show for it

Twice in one afternoon the AP went deaf-in-one-direction: it kept receiving
perfectly and stopped being heard by anyone.

The signature, from the AP's own hostapd log, with two independent stations:

```
authentication: STA=9c:04:b6:ff:df:fe ... rssi=0
wlh0: STA 9c:04:b6:ff:df:fe IEEE 802.11: did not acknowledge authentication response
authentication: STA=0c:bf:74:2c:dd:05 ... rssi=-67
wlh0: STA 0c:bf:74:2c:dd:05 IEEE 802.11: did not acknowledge authentication response
```

Both stations' frames arrive at the AP. Neither station hears the reply. From the
station side a scan returns zero BSSes, including the AP it was associated with a
minute earlier.

**Nothing in software shows it.** `iw dev wlh0 info` reports the interface up at
22 dBm on the right channel. `ip -s link show wlh0` reports TX 941 packets with
`errors 0 dropped 0`. `dmesg` has no morse or SPI error at all. The AP believes
it is transmitting.

The first occurrence followed `iw set txpower fixed` (see the previous section).
**The second followed nothing** — 22 minutes after a clean reboot, with no
intervention, after both stations had been kicked for inactivity and could not
get back in. So the txpower command is one way to provoke it, not the only cause.

`wifi reload` does not recover it, either time. A reboot does, both times.

**This is a candidate root cause for three things recorded earlier as
unexplained:** the 5% packet loss on a 100-ping run, the two re-associations with
no deauthentication or beacon-loss logged, and the first sustained download
truncating at 155648 of 4194304 bytes. All three are what an intermittently
silent transmitter would look like from the far end. Not established — the
correlation has not been tested — but any future work on those should suspect
this first.

Diagnosis note, because the first read was wrong: the symptom presents as "the
*station's* receiver is broken", since the station is the thing that cannot scan.
What points the right way is the AP's station table emptying and *both* stations
failing simultaneously. No station-side fault explains two independent stations
going deaf at the same instant.

### The HaLow link is an out-of-band path to the station

When the Pi's management Wi-Fi went away mid-experiment — it had roamed onto a
network segment that the laptop could not route to — the board was not lost. Its
HaLow interface was still associated, and the AP is reachable by a direct cable:

```
laptop --USB-Ethernet--> OpenMANET AP 10.41.254.1 --HaLow--> Pi 10.41.0.208
```

From the AP, with dropbear's client, which takes the password from the
environment:

```sh
DROPBEAR_PASSWORD='...' dbclient -y -y -l alan 10.41.0.208 'command'
```

That recovered a board that was otherwise headless and unreachable, with no
physical access and no Ethernet.

Worth keeping in mind generally: the HaLow network is on its own addressing and
its own radio, independent of the site LAN. Whatever happens to the management
network, that path stays up as long as the station is associated and the AP is
cabled to the laptop. It is slow and lossy, and it is enough for a shell.

A related trap that cost time in the same episode: the Pi's Wi-Fi MAC is *not*
its Ethernet MAC. `eth0` is `e4:5f:01:52:55:04`, `wlan0` is
`...:55:05`. Hunting the ARP table for the wrong one finds nothing and looks like
the board is off.

## 2026-08-23: IT WORKS — `wlan1` is up on stock Raspberry Pi OS

```
phy31 -> platform/soc/fe204000.spi/spi_master/spi0/spi0.0
wlan1 -> phy31, MAC 9c:04:b6:ff:df:fe
351 SPI write transactions, 0 write failures, 0 read failures
```

```sh
insmod morse.ko country=SG bcf=bcf_fgh100mhaamd.bin \
    spi_inter_block_delay_bytes=250 spi_post_write_status_bytes=250
```

No `spi_rx_lshift`. It is not needed any more.

There were **two independent defects**. The first — the chip never being put into
SPI mode — is in the section below. The second is this one.

### The inter-transaction delay is counted in clocks, not in time

The driver derives it from a time:

```c
inter_block_delay_bytes = MM6108_SPI_INTER_BLOCK_DELAY_NANO_S /
                          (SPI_CLK_PERIOD_NANO_S(max_speed_hz) * 8)
```

40000 ns is 250 bytes at 50 MHz and 50 bytes at 10 MHz. Both are 40 µs — so if
the chip needed a fixed *time*, the two would be equivalent.

**They are not.** At 10 MHz, 50 bytes fails and 250 bytes works. The chip needs a
fixed number of SPI clocks. The driver's model only produces a working value at
50 MHz, which is why every setup that works runs at 50 MHz and this one, at
10 MHz, did not.

Morse's OpenWrt feed patch puts a hard floor of 250 in three places. **All three
turned out to be separately necessary here, and each was found independently
before that patch was re-read:**

| | failure it fixes | fix |
|---|---|---|
| block-write delay | txn #52 of 58, `fn=2 0x00000000:14`, chip answers `0xeb` (CRC ERROR) at +261 — mid-block, having given up on the previous transaction, a 344-byte non-block write | `spi_inter_block_delay_bytes=250` |
| non-block write padding | `fn=2 0x00001000:80`, byte-mode; only 4 bytes are clocked after the CRC by default | `spi_post_write_status_bytes=250` |
| non-block **read** delay | `cmd53_read fn=2 0x00003110:92` → `failed to parse extended host table: -5`. A 92-byte read scales to 44 bytes | no parameter existed; added `spi_min_delay_bytes`, default 250 |

Fixing the first moved the failure to the second, and fixing that moved it to the
third. Each looked like a new problem and each was the same one from a different
side.

### A correction to the record

`spi_post_write_status_bytes` was tested at 4…64, and separately at 512, and
recorded as **eliminated** both times. Neither measurement was wrong and neither
conclusion was usable: the chip was not in SPI mode then, the very first write
failed, and no amount of padding could have mattered. It only becomes relevant
once the init defect is fixed and the driver reaches transaction 50.

**An elimination is only valid in the state it was measured in.** Fifteen
hypotheses were tested against a chip that was in the wrong mode throughout, and
at least one of them was a real contributor that the state masked.

### Caveat

~~`iw phy` and `iw dev` list nothing for phy31 — stock mac80211 has no S1G band
support.~~ **Wrong, corrected 2026-08-23.** `iw` lives in `/sbin`, off a non-root
`PATH`; the calls were returning *command not found* and the empty output was read
as a technical limit. Run properly it enumerates the phy completely — `wlan1` type
managed, full cipher list, IBSS/managed/AP/AP-VLAN/monitor/mesh, Band 2 with
per-channel regulatory state. **mac80211 registration is complete.**

~~The real gap is narrower: `iw dev wlan1 scan` returns success but generates no
SPI traffic at all.~~ **Also wrong, corrected again.** That counter was a
`dev_info` from the instrumented build; the clean series does not contain it, so
the log line was absent and absence was read as idleness — the same mistake in a
different disguise.

Measured with the SPI core's own statistics, which depend on nothing written here
(`/sys/bus/spi/devices/spi0.0/statistics/`):

| | messages | bytes |
|---|---|---|
| idle, 3 s | +17 | 4.6 KB (30 s watchdog) |
| `ip link set up` | +165 | 40 KB |
| `iw scan` ×3 | +31, +31, +36 | ~8 KB each |

`errors 0`, `timedout 0`. `morse_mac_ops_start`, `add_interface` and
`morse_ops_hw_scan` are all invoked, `morse_cmd_get_version()` returns 0. **The
scan reaches the chip and finds nothing because there is no HaLow network in
range.**

**CORRECTED 2026-08-23 (later): the last clause is wrong.** A HaLow AP was
broadcasting a few metres away throughout every scan quoted here — the second
SenseCAP M1, running OpenMANET. It was invisible because it was on `country=US`
and this station on `country=SG`; the dot11ah mapping resolves a mapped channel
to a different S1G frequency per country, so the station was scanning a plan the
AP was not on. With both set to `SG` the AP appears on the first scan and the
station associates. The honest claim was "no network on the channel plan being
scanned", and it was never checked against the AP on the same bench. Same failure
mode as the rest of this section: an empty result taken at face value.

What was untested is association and data transfer. **Both are verified as of
2026-08-23** — see
[`logs/2026-08-23-association-verified-environment.txt`](logs/2026-08-23-association-verified-environment.txt).

Six times in one session, "did not see it" was read as "is not there": RUN 5's
preamble sweep, the `mode=0x4` line, the 1.5 s power-up wait, `iw` not being on
`PATH`, "bringing wlan1 up produces register writes" (stale dmesg, never cleared),
and this. Two reached public comments. Corrected on issue #9 as comments
5381978970 and 5382020693. **The pattern is the finding worth keeping: when an
instrument reports nothing, check the instrument before believing it.**

Full detail: `logs/2026-08-23-WORKING-environment.txt`.

---

## 2026-08-23: SOLVED — the chip never entered SPI mode

The 2-bit skew is fixed. Root cause, in one sentence: **the MM6108 needs ~74
clocks with chip select deasserted to enter SPI mode, and on a `cs-gpios`
controller `morse_spi_initsequence()` never delivers them.**

Morse state the requirement directly, in their i.MX93 porting thread:

> in order to put it into SPI mode, the host needs to toggle the SPI clock line
> ~74 times while the CS pin is held high — ie, inverted compared to normal
> operation.

and, of a host that failed the same way this one did:

> The original configuration had the chip select driven low during
> initialization, preventing the device from responding to subsequent commands.

`morse_spi_initsequence()` tries to arrange that by flipping `SPI_CS_HIGH` around
the burst. It does not work, and the mode logging added to `patches/` shows why:

```
init: mode=0x4 cs_high_default=1 train=18 flip=1
init: CS deasserted for training, mode=0x4     <-- expected 0x0
init: CS polarity restored, mode=0x4
```

`0x4` is `SPI_CS_HIGH`, still set immediately after `spi->mode &= ~SPI_CS_HIGH;
spi_setup(spi);` — **`spi_setup()` forces it back on for a cs-gpios device.** The
74 clocks go out with the chip *selected*, it never enters SPI mode, and every
response afterwards sits two bit times off the byte grid.

### The fix

`SPI_NO_CS` achieves what the flip cannot — the controller leaves the CS line
alone, so the GPIO stays high for the whole burst. Guarded by `spi_init_no_cs`
(default on), with the old flip as a fallback.

**Order matters and this is what hid the answer:** the burst has to happen after
reset and before any other transaction. Once the chip has been addressed with CS
asserted it does not recover. An earlier userspace attempt did the training
*after* a first CMD0, saw no change, and looked like a negative result.

### Verified

Userspace, CS driven by hand with `SPI_NO_CS` set so the controller could not
interfere, full reset before each trial:

| sequence | response |
|---|---|
| CS held HIGH throughout, CMD0 | `ff ff ff ff` — silent, confirming CS really is under manual control |
| CS LOW, CMD0, no training | `ff c0 7f ff` — R1 @bit10, **skewed** |
| 80 clocks @ CS HIGH, then CMD0 | `ff 01 ff ff` — R1 @bit8, **aligned** |

6/6 reproducible. After a correct init, `CMD0`→`0x01`, bad CRC→`0x09`,
`CMD13`→`0x05`, `CMD63`→`0x01`, all on the byte boundary.

Then in the driver, one parameter, same binary, same board:

| `spi_init_no_cs` | result |
|---|---|
| `Y` (default) | `training with SPI_NO_CS, mode=0x44`; no skew, CMD63 passes, firmware and BCF load |
| `N` (old behaviour) | `CS deasserted for training, mode=0x4`; `c0 3f` / `c0 7f` returns |

**`spi_rx_lshift` is no longer needed.** Every earlier run required it even to
read the chip ID; these pass none and the read path works natively — 468 KB of
firmware transfers correctly.

### Still open: the CMD53 write path

A different problem, and now visible for the first time:

| | before | after |
|---|---|---|
| chip's answer | 519 bytes after CRC, all `0xff` — silent | answers; `b=0x001f0002` |
| failure point | `fn=1 0x00004050:4` | `fn=2 0x00000000:14` — the firmware download, much further in |

Morse's OpenWrt-only `find_data_ack` change (scan for an accept token instead of
stopping at the first non-`0xff` byte) is implemented behind `spi_ack_scan`,
default on. **On this board it changes nothing** — the scan runs the full 3440
bytes and finds no `0x05`. Recorded because it is vendor-sanctioned and would
otherwise be tried again.

### Why OpenMANET never needed the fix

Because it never resets the chip. Its `reset-gpios` flag is 0
(`GPIO_ACTIVE_HIGH`), so `morse_hw_reset()`'s `gpiod_set_value(reset, 1)` drives
the pin *high* — RESET_N never actually fires. Measured on this board, with the
module's power under our control on GPIO18:

| | response |
|---|---|
| cold power-up, no training at all | `ff 01 ff` — **aligned, already in SPI mode** (3/3) |
| same power-on, after a RESET_N pulse | `ff c0 7f` — **offset, knocked out of SPI mode** |
| training after that | `ff c0 7f` — not recovered (a CS-asserted command had already happened) |

Step 1 → 2 is the clean one: same power-on, nothing changed but a reset pulse,
and the chip goes from aligned to offset. **RESET_N takes the chip out of SPI
mode.** So OpenMANET stays in the mode it powered up in and the broken burst is
harmless there; this repo's overlay uses flag 1, the reset genuinely fires, and
the broken burst cannot put it back.

**Caveat:** the power-on state is not perfectly deterministic — 1 of 5 cold
power-ups came up already offset. Cause unknown. The chip *usually* powers up in
SPI mode, not always.

This also explains two community replies found early and not understood at the
time — *"the issue resolved after a physical power cycle rather than a soft
reboot"* and *"most of our deployments use a reset script to toggle the reset
line on boot"*. A physical power cycle puts the chip back into SPI mode; a soft
reboot does not, because the module keeps power and stays where the last RESET_N
pulse left it. And it explains why testing `reset-gpios` flag 0 on its own
changed nothing: by then the chip had long been taken out of SPI mode by earlier
boots, and was never power-cycled during that test.

**With the fix none of this matters.** The driver delivers the training correctly
straight after reset, so the chip ends up in SPI mode regardless of how it powered
up or how often it has been reset. OpenMANET works by *avoiding* the problem, not
by handling it — the fix makes it deterministic instead of lucky.

**A methodology note.** An earlier version of this test waited only 1.5 s after
re-applying power and produced a completely different picture — everything
offset, including sequences already verified to work. The module needs more than
1.5 s before it will accept anything. Re-running a known-good sequence first is
what caught it; without that check the artefact would have been archived as a
finding.

### Why it took fifteen eliminations

Every earlier hypothesis was about the bus — kernel tree, device tree, clock,
pulls, power sequencing, the driver's own padding. The answer was that the chip
was in the wrong *mode* the whole time, and nothing about the bus could reveal
that. The mode logging that exposes it was added late, and its significance only
became clear once Morse's own wording turned up in a forum thread about a
completely different SoC.

Full detail: `logs/2026-08-23-nocs-init-fix-environment.txt`.

---

## 2026-08-23: fourteen eliminations, and where this line ends

The device tree on the failing board now matches the working one **property for
property, all at once** — single `cs-gpios`, GPIO7 not claimed as a chip select,
`reset-gpios` flag 0, `spi0_pins` and the auxiliary pins pulled the same way, and
slot power applied by the VideoCore firmware rather than a DT hog. Verified in
effect after reboot. The failure is byte-identical: `c0 3f` / `c0 7f`, CMD63
`ret:-71`.

Four more eliminations beyond the ten below:

| Test | Why it looked plausible | Result |
|---|---|---|
| `gpio=18=op,dh` in config.txt | OpenMANET powers the slot from the **firmware stage**, seconds before the kernel; ours waited for gpiolib's hog. A chip that hasn't finished its power-on init emitting a misframed response would be deterministic, clock-independent and present from the first transaction — it fits every observed feature | unchanged |
| auxiliary pin pulls | our overlay pulls GPIO5 (SPI_INT) and GPIO23 (WAKE) **down**; OpenMANET pulls both **up** — a difference missed on the first pass | unchanged |
| `spi0_pins` pull-up **from boot** | RUN 6 flipped these at runtime, long after the SPI block was initialised. The idle level of SCLK at the moment the pin is muxed to ALT0 is a different thing, and only the overlay can set it | unchanged |
| all of the above simultaneously | each had only been tested alone, leaving "maybe it's a combination" open | unchanged |

### Correction: RUN 5's conclusion is withdrawn

RUN 5 swept 0…32 bytes of `0xff` before the command inside one CS assertion, saw
`@bit10` every time, and concluded it was *not* the host mis-sampling the start
of a transfer. **That inference is wrong.**

If the controller emits two extra clock edges after CS goes active and before the
first data bit, the chip takes those two bits and its byte grid is offset from
ours by two for the rest of the transfer. It still parses the command, because
MMC-SPI commands are self-framing on the `01` start bit and need no byte
alignment — which is exactly why it can validate our CRC7. Adding preamble does
not move that, because the spurious clocks come first. **The observation is what
the hypothesis predicts, not evidence against it.**

*(Note: this was not the answer either — the actual cause is in the top section of this file.)*

So "extra clocks at CS assert" is live again, and it is a host-side behaviour,
which fits the one stubborn fact: this is OS-dependent on identical hardware. The
measurement stands; only the conclusion was wrong.

### Where this line ends

Fourteen tests, no cause. The remaining candidates cannot be separated by more of
this kind of testing — every one of them is about what happens on the wire in the
first few microseconds of a transfer, and none of this can see that.

**The honest next step is a logic analyser** on SCLK / MOSI / MISO / CS. It shows
directly whether the controller clocks anything between CS going active and the
first data bit, and where the chip starts driving MISO. The pins are all on the
40-pin header.

---

## 2026-08-23: every device-tree difference the A/B found is eliminated

The A/B's four differences were closed with two overlay changes on the failing
side, and the failure is byte-identical throughout.

| Difference | Change | Result |
|---|---|---|
| `cs-gpios` two entries | `cs-gpios = <&gpio 8 1>` plus `spi0_cs_pins { brcm,pins = <8> }` — the second override is needed because the base rpi DT declares `<8 7>` | verified in effect (property 24 → 12 bytes, GPIO7 `MUX UNCLAIMED`); **skew unchanged** |
| `reset-gpios` flag 1 | `<&gpio 17 0>`, matching OpenMANET | verified in effect; **skew unchanged** |
| `spi-max-frequency` | — | already eliminated in RUN 4 |

The `reset-gpios` one deserves its epitaph. The flag is `GPIO_ACTIVE_LOW` and
`morse_hw_reset()` asserts with `gpiod_set_value(reset, 1)`, so flag 1 drives the
pin low and RESET_N really fires, while flag 0 drives it high — meaning on
OpenMANET the driver's reset pulse plausibly never happens. Since fixing
`reset_module()` in `tools/mmcspi.py` (making the reset actually occur) changed
CMD0's tail from `ff c0 7f` to `1f c0 7f`, "the reset pulse is what puts the chip
into the skewed state" was a real hypothesis. Dead.

**The failing board's `spi0` node now matches the working one on every difference
the A/B found, and it still fails identically.** The device-tree avenue is
exhausted — ten eliminations total.

### Board identity, recorded late

There are **two** SenseCAP M1 units and both have hostname `Sensecap`, so the
environment files — which recorded only the hostname — could not say which board
a run used. The archived boot dmesg settles it, via the MAC in the kernel command
line: `E4:5F:01:52:57:E7` for the 6.6.51 boot, the 6.12.93 boot, **and** both
OpenMANET runs. So **the same board both fails under Raspberry Pi OS and works
under OpenMANET** — the "same board" claim holds and is now backed by logs.

The second unit, `E4:5F:01:52:55:04`, runs the same card and shows a
byte-identical failure. A second board with a second module reproducing the skew
is corroboration, not a complication.

A trap worth knowing: `retest-*.log` lives on the SD card, not the board. Finding
those files on a machine proves only that the card has been in it since. Every
environment file records board MAC and serial from now on.

### What has never been compared

The base `bcm2711-rpi-4-b.dtb` (firmware partition on Raspberry Pi OS vs built by
OpenWrt), the **VideoCore firmware** (`start4.elf`, `fixup4.dat`), and the kernel
config. The VideoCore firmware is the interesting one: it configures the SoC clock
tree before the kernel starts, the symptom is a bit-level timing offset, and it is
guaranteed to differ between the two images.

---

## 2026-08-22: the A/B ran — the second chip select is the difference

Booted OpenMANET on the same board and captured its live device tree and pin mux
against the failing Raspberry Pi OS capture. Four differences, one of which had
never been looked at.

| | Raspberry Pi OS 6.6.51 (skew) | OpenMANET 6.6.138 (works) |
|---|---|---|
| `cs-gpios` | `<&gpio 8 1>, <&gpio 7 1>` — **two** | `<&gpio 8 1>` — **one** (property is exactly 12 bytes) |
| GPIO7 | `fe204000.spi … function gpio_out` | `(MUX UNCLAIMED) (GPIO UNCLAIMED)` |
| `reset-gpios` | `<&gpio 17 1>` | `<&gpio 17 0>` |
| `spi-max-frequency` | 10 MHz | 50 MHz |

Everything else matches: MISO/MOSI/SCLK `alt0`, GPIO8 `gpio_out`, and the spi0
node's `dmas`, `clocks`, `interrupts`, `reg` and `compatible` are identical. The
clock difference is already eliminated (RUN 4 swept 400 kHz…50 MHz).

**So what is left is the second chip select.** The failing side registers two and
has the controller holding GPIO7 as an output; the working side registers one and
never touches GPIO7. That variable was never examined — the earlier pin mux check
confirmed no pin was driven *twice*, which it isn't, and stopped there.

It is worth testing rather than just noting, because CS count is not inert in this
driver: one of the three rpi patches to `spi-bcm2835.c` that OpenWrt imports is
`950-0821`, "Support spi0-0cs and SPI_NO_CS mode".

This is the first hypothesis in the investigation that comes from a **measured
difference between a working and a failing configuration** rather than from
reasoning about what might matter.

**Next:** change `overlays/mm610x-spi-sensecap.dts` to declare a single chip
select — `cs-gpios = <&gpio 8 1>` on `&spi0`, leaving GPIO7 alone — rebuild,
reboot, and see whether `morse rx` still shows `c0 7f`. Try
`reset-gpios = <&gpio 17 0>` in the same pass or right after.

Detail, including what could not be captured on the OpenMANET side (no `python3`,
no `kmod-spi-dev`, so the userspace probe half of the A/B did not run), is in
`logs/2026-08-22-openmanet-1.8.0-ab-environment.txt`.

---

## 2026-08-22: the retest ran — eight eliminations, none of them the cause

Everything below was written before the hardware retest. The retest has now been
run, over SSH, and it kills the padding hypothesis too. Full detail in
`logs/2026-08-22-bookworm-6.6.51-retest-environment.txt`.

| Hypothesis | Test | Result |
|---|---|---|
| kernel-tree difference | source diff at the same stable tag | eliminated — byte-identical |
| ack window too narrow | `spi_post_write_status_bytes=512` | **eliminated** — `no non-0xff byte in the 519 bytes clocked after CRC` |
| skew caused by the init training burst | 7 runs sweeping `spi_init_train_bytes` 0/2/17/18/20 and `spi_init_cs_flip=N` | **eliminated** — `c0 3f` / `c0 7f` in all seven |
| GPIO8 double-driven | live pinmux | **eliminated** — 7/8 `gpio_out`, 9/10/11 `alt0` |
| clock-dependent | 400 kHz / 1 / 20 / 50 MHz | **eliminated** — identical at every rate |
| the driver is involved at all | spidev bound via `driver_override`, no driver loaded | **eliminated** — same `R1=0x01 @bit10` |
| host mis-samples the start of a transfer | 0…32 bytes of `0xff` before the command in one CS assertion | **eliminated** — `@bit10` every time |
| the pull on MISO/MOSI/SCLK | `pinctrl set 9\|10\|11 pu` at runtime, A/B against pull-down | **eliminated** — byte-identical in both directions |

The pull one is worth a paragraph, because the difference is real even though it
is not the cause. Decoding OpenMANET's own `mm610x-spi.dtbo` off a freshly
written card shows `spi0_pins { brcm,pins = 9 10 11; brcm,function = ALT0;
brcm,pull = 2 2 2 }` — **pull-up on all three SPI lines**. The overlay in this
repo never sets those pulls and inherits the BCM2711 default, which is
**pull-down**, confirmed on the running board. The reasoning was that an MMC-SPI
slave tri-states MISO before answering, so the pull sets the level during those
bit times. Flipping them at runtime changes nothing at all. Recorded so the same
difference does not get rediscovered and re-argued later. Full decode in
`logs/2026-08-22-openmanet-1.8.0-overlay-mm610x-spi.txt`.

That decode also confirms the image needs **no overlay swap**: reset on GPIO17
pull-up, IRQ on GPIO5, power-gpios 23/24, `cs-gpios` GPIO8 active-low,
`spi-max-frequency` 50 MHz — the WM1302 HAT map throughout.

Two facts worth carrying forward:

- **`spi_setup()` forces `SPI_CS_HIGH` back on** for a cs-gpios device, so
  `morse_spi_initsequence()`'s training burst goes out with the chip *selected*
  on every such host. A real driver defect — reported upstream — but not the
  cause here.
- **The default ack search window is 11 bytes**, not the 71 quoted below; 71 was
  the length of a hex dump.

`driver_override` is the way to get a spidev node here — dropping the overlay
from `config.txt` would take the GPIO18 slot power hog and the GPIO17 pull-up
with it. `tools/mmcspi.py`'s `reset_module()` was also fixed: it used libgpiod
v2 `gpioset` syntax and failed silently on Bookworm's v1.6.3, so no reset was
happening at all.

**What is left** is a genuine disagreement between chip and host about where byte
boundaries are, on a board where OpenMANET needs no compensation. The only
remaining experiment is the direct A/B: boot the OpenMANET card and run the same
spidev probe on it. That needs a physical card swap.

---

## 2026-08-22 (later): the kernel-tree conclusion is refuted — the split is in the driver package

Ran the tree diff the section below proposes. It comes up empty: **there is no
`spi-bcm2835` difference between the two kernel trees.**

Method: `raspberrypi/linux` at tag `stable_20241008` (= 6.6.51, the exact kernel
in the failing Bookworm image) against OpenWrt's tree, reconstructed as mainline
stable plus every patch in `target/linux/bcm27xx/patches-6.6/` that touches the
file in question.

| File | OpenWrt bcm27xx 6.6 vs raspberrypi/linux rpi-6.6.y @ 6.6.51 |
|---|---|
| `drivers/spi/spi-bcm2835.c` | byte-identical |
| `drivers/spi/spi.c` (SPI core) | byte-identical |
| `drivers/dma/bcm2835-dma.c` | byte-identical |
| `drivers/pinctrl/bcm/pinctrl-bcm2835.c` | byte-identical |
| `arch/arm/boot/dts/broadcom/bcm270x-rpi.dtsi` | byte-identical |

OpenWrt imports the rpi commits verbatim. The rpi tree's only changes to
`spi-bcm2835.c` are three commits — phys-addr slave DMA config, the
zero-length-transfer workaround, and `spi0-0cs`/`SPI_NO_CS` support — and OpenWrt
carries all three (950-0276 / 950-0467 / 950-0821), plus the SPI-core one
(950-0204, "Force CS_HIGH if GPIO descriptors are used"). Mainline's
`spi-bcm2835.c` is also unchanged between v6.6.51 and v6.6.138, and
`OpenMANET/firmware` at tag 1.8.0 carries the same three patches as upstream
openwrt-24.10.

So there is nothing to bisect, in either tree.

### Where the real difference is: an OpenWrt-only Morse driver patch

*(Superseded by the retest above: the patch is real and the divergence is worth
reporting, but widening the window to 519 bytes changes nothing on this board, so
it does not explain this failure.)*

`OpenMANET/firmware@1.8.0`'s `feeds.conf.default` pins `MorseMicro/morse-feed` at
`fc332b0`, and that feed applies
`essentials/morse_driver/patches/mm61x/003_fix_spi_inter_transaction_delay.patch`
to the driver before building it. The patch header describes this exact failure:

> Add more delay between SPI transactions when not in block mode. [...]
> Currently the driver has enough delay between blocks but not when the
> transaction isn't a block.

It raises the padding clocked after the CRC of a **non-block** CMD53 write from
`4` bytes to `max(250, count * inter_block_delay_bytes / MMC_SPI_BLOCKSIZE)`, and
applies the same floor to non-block reads.

The numbers line up exactly:

- `MM6108_SPI_INTER_BLOCK_DELAY_NANO_S` = 40000 ns, and
  `inter_block_delay_bytes = 40000 / (clk_period_ns * 8)` → **250 bytes at
  50 MHz**, 50 bytes at 10 MHz. Morse's `max(250, …)` is exactly one full
  inter-block delay at full clock, applied regardless of clock.
- Stock `mm6108-2.0.1` exposes that same line as a module parameter instead,
  `spi_post_write_status_bytes`, **default 4**.
- Every failure here is a non-block write: `cmd53_write fn=1 0x00004050:4`,
  count = 4.
- The widest window ever tested here was **64** bytes.

So the ack window was never opened wide enough. "Ruled out:
`spi_post_write_status_bytes` 4…64" below is not a valid elimination.

### Second driver-side difference: `enable_ext_xtal_init`

OpenMANET runs with `enable_ext_xtal_init='1'` in its UCI (see
`logs/2026-08-22-openmanet-1.8.0-environment.txt`). In `morse_spi_cmd53_write()`,
when that parameter is set *and* `cfg->xtal_init_bus_trans_delay_ms` is non-zero,
the driver appends a further `XTAL_TRANSFER_DELAY_BYTES` = **4096** bytes to the
transaction; `mm610x_enable_ext_xtal_delay()` sets that field only when the
parameter is on. The working machine therefore clocks an ack window two orders of
magnitude wider than anything tested here.

Note the ordering trap: `mm610x_ext_xtal_init()` performs its sequence with
`morse_reg32_write()` calls, i.e. it *needs* a working write path. Turning the
parameter on while writes are broken — tried, "no change" — cannot work on its
own. The padding has to be fixed first.

### The four-way comparison was not single-variable

Other differences between the passing OpenMANET run and the failing Raspberry Pi
OS runs, all from the archived logs:

- **Different BCF.** OpenMANET loaded `bcf_default.bin` (1298 bytes, crc32
  `0xf72450a7`); the builds here load `bcf_fgh100mhaamd.bin` (1251 bytes,
  `0x941b2a82`). The claim below that the BCF was identical is wrong — only
  `mm6108.bin` (`0xbe7b5c8f`) actually matches.
- **Different dot11ah build.** OpenMANET registers `Dot11ah driver registration.
  Version 0-rel_mm8108_2_0_0_2026_Apr_21` alongside the mm6108 2.0.1 main driver;
  both are mm6108 2.0.1 here.
- **Different overlay.** `spi-max-frequency` 50 MHz there against 10 MHz here —
  which by itself changes the computed `inter_block_delay_bytes` from 250 to 50 —
  plus `reset-gpios = <&gpio 17 0>` against `<&gpio 17 1>` here, and pinctrl
  attached to the controller rather than to the child device node.

### One thing that argues against the padding hypothesis

"The open problem" below records that the same transaction driven by hand from
userspace returns token `0x05` **two bytes after the CRC**. If that is what the
chip really does, a 4-byte window is already enough and padding is not the wall.
That observation and "all 0xff out to 71 bytes" from inside the driver cannot
both be describing the same chip state. Card state (idle vs initialised) is the
standing suspect and was never verified. So the padding hypothesis is a good fit
numerically but is not confirmed — it has to be measured, not assumed.

### Next experiments, in order

*(All of these have now been run — see the retest section at the top. Kept
because the reasoning behind each one is what the results have to be read
against.)*

`patches/` was extended on 2026-08-22 to make these measurable:
`spi_init_train_bytes` (default 18), `spi_init_cs_flip` (default Y),
`spi->mode` logging through `morse_spi_initsequence()`, and a rewritten
`morse_spi_find_data_ack()` failure path that reports the offset and value of
the first non-`0xff` byte (or says there was none in N bytes) and dumps from
that byte rather than from the head of the window.

**1. Does the ack window matter at all?** One insmod, everything else exactly as
the last failing run — 10 MHz, `spi_rx_lshift=2`, `bcf_fgh100mhaamd.bin`:

```
spi_post_write_status_bytes=512
```

Pass → padding was the wall. Still nothing in 512 bytes → the padding hypothesis
is dead, which also rules out Morse's own OpenWrt fix as the explanation and
sharpens the question to them.

**2. Is the 2-bit skew self-inflicted by the init burst?** The training clocks go
out with CS deliberately deasserted, via a `SPI_CS_HIGH` flip. If that flip goes
the wrong way on this kernel, the chip sees those clocks *selected* and starts
counting bits early — which would produce exactly a constant, clock-independent
bit offset. Sweep:

| `spi_init_cs_flip` | `spi_init_train_bytes` | reading |
|---|---|---|
| Y | 18 | baseline (stock behaviour) |
| Y | 0 / 2 / 17 / 20 | does the skew track the burst length? |
| N | 18 | does the skew depend on the flip rather than the clocks? |
| N | 0 | neither burst nor flip |

Watch the new `init: mode=0x…` lines to see which branch the kernel actually
takes, and `morse rx:` for whether the offset moves.

**3. Where else can a difference hide?** With the SPI source byte-identical
between the two trees, only the live configuration is left. Dump
`/proc/device-tree/soc/spi@7e204000/` (cs-gpios, pinctrl-0, dmas) and the GPIO
7…11 rows of `/sys/kernel/debug/pinctrl/*/pinmux-pins` on both Raspberry Pi OS
and OpenMANET and diff them. In particular, check whether GPIO8 is muxed ALT0
(native CE0) while also being used as a GPIO chip select.

**4. Only after 1 passes**, converge on OpenMANET's configuration one variable at
a time: overlay to `spi-max-frequency = <50000000>` (which makes the driver
compute the same 250-byte inter-block delay), then `enable_ext_xtal_init=1`,
then `bcf=bcf_default.bin`.

**Still unexplained: the 2-bit RX skew.** Padding is a byte-level effect and
cannot produce bit-level misframing, and OpenMANET needs no `spi_rx_lshift` at
all on the same hardware. Experiment 2 is the direct attack on it.

---

## 2026-08-22 follow-up: four end-to-end tests

Same board (SenseCAP M1 mPCIe slot with Wio-WM6108, WM1302 HAT pinout), nominally the same driver release (`mm6108-2.0.1` with the patches in `./patches`), same firmware (`mm6108.bin` crc32 `0xbe7b5c8f`). ~~Same BCF (`bcf_fgh100mhaamd.bin` crc32 `0x941b2a82`).~~ **Corrected 2026-08-22: the OpenMANET run loaded `bcf_default.bin` (crc32 `0xf72450a7`), and its driver is an OpenWrt-feed build carrying extra SPI patches — see the section above.** What changes across the four rows is the OS image, not the kernel alone:

| Kernel | Tree / packaging | Result |
|---|---|---|
| **6.6.138** | OpenWrt linux-6.6 (OpenMANET 1.8.0) | ✅ `wlh0` up as AP on SG @ 22 dBm |
| 6.6.51+rpt-rpi-v8 | raspberrypi/linux rpi-6.6.y (RPi OS Bookworm 2024-11-19) | ❌ CMD63 fail → `spi_rx_lshift=2` → CMD53 write fail at `0x00004050:4`, `ret:-71` |
| 6.12.93+rpt-rpi-v8 | raspberrypi/linux rpi-6.12.y (RPi OS Bookworm 2025-05) | ❌ byte-identical fingerprint to above |
| 6.18.34+rpt-rpi-v8 | raspberrypi/linux rpi-6.18.y (RPi OS Trixie) | ❌ byte-identical fingerprint |

**Key conclusion — SUPERSEDED, see the section above.** ~~the fault is a `spi-bcm2835` (or SPI-core) **tree difference**, not a version regression. Both trees share mainline stable-tag numbering, but `raspberrypi/linux`'s patch stack breaks MM6108 driven via GPIO CS, and OpenWrt's does not.~~ The comparison this paragraph asks for was done and the files are byte-identical; the split is in the driver package, not the kernel. The table above still stands as measurement — only its interpretation was wrong.

**Practical bottom line:** OpenMANET 1.8.0 remains the only tested working path. But the reasoning that followed from this — swap the kernel — no longer holds: options (b) and (c) below were expected to work *because* they avoid `raspberrypi/linux`, and that premise is now refuted. Replacing the kernel is unlikely to help on its own; fixing the driver's non-block write padding is the thing to try first.
- (a) OpenMANET as a dedicated gateway,
- ~~(b) Ubuntu Server or a mainline-kernel Debian image on the Pi (both untested but expected to work since they do not use `raspberrypi/linux`),~~
- ~~(c) build a mainline kernel and install on Bookworm.~~

The retraction: earlier "next things to try" below (§) suggested that some 6.6.x kernel on Raspberry Pi OS should work because it's the same LTS branch as OpenMANET. Wrong. Any `+rpt-rpi-v8` kernel tested carries the bug.

**Public status:** the fixes are submitted as [morse_driver#16](https://github.com/MorseMicro/morse_driver/pull/16) — three commits against `main`, no instrumentation, no `Signed-off-by` (that is Alan's to add). Both upstream issues also carry the working result — issue #9 comment 5381871720 (the delay defect, the three floors, and the ask to stop scaling by clock) and issue #15 comment 5381871843 (the init fix confirmed, and that it is not sufficient alone). `MorseMicro/morse_driver` **issue #15** now carries the `morse_spi_initsequence()` defect on its own — split out because it is wider than #9's subject and would be missed buried in a comment (`issue15-report.md` tracks it). Plus six comments on issue #9 (v1 initial, v2 OpenMANET pass, v3 Bookworm 6.12.93 fail, v4 Bookworm 6.6.51 fail + tree-split reframing, v5 retraction of that reframing + six eliminations, v6 the SPI-mode init root cause and fix). No maintainer response as of this update.

Full per-test evidence in `logs/`:
- `logs/2026-08-22-openmanet-1.8.0-*.log/.txt` — the passing case
- `logs/2026-08-22-bookworm-6.6.51-*.log/.txt`
- `logs/2026-08-22-bookworm-6.12.93-*.log/.txt`

Below is the earlier bring-up writeup that led to this conclusion. The "next things to try" section at the end is now historical — items (1) OpenMANET and (2) Seeed's prebuilt image were both examined; the OpenMANET test drove the conclusion above, and Seeed's release (`Wvirgil123/openwrt` v2.7-dev, kernel 5.15, EKH01 pinout) is another OpenWrt-tree data point but would need the same overlay swap the Heltec HT-HC01P image needs.

---

## Hardware: confirmed good
- Chip identified by the driver over SPI: **chip ID 0x0306 = MM6108A1**
  (`MORSE_DEVICE_ID(0x6, rev 3, silicon)` in hw.h). Not a guess - the driver's
  own `mm610x_chip_id_matches()` accepted it.
- Pin map (Seeed WM1302 Pi HAT, reused by the M1 carrier):
  MISO 9 / MOSI 10 / CLK 11 / CS 8, RESET_N 17, SPI_INT 5, WAKE 23, BUSY 24,
  slot power enable 18 (M1-specific).
- RESET_N is active low and `morse_hw_reset()` releases it by *floating* the
  pin, so GPIO17 must be configured pull-up or the BCM2711's default pull-down
  holds the radio in reset. Handled in the overlay.

## Software state
- Driver: MorseMicro/morse_driver tag `mm6108-2.0.1`, builds clean against
  kernel 6.18.34+rpt-rpi-v8 with the patches in ./patches.
- Firmware installed to /lib/firmware/morse: mm6108.bin + quectel BCFs.
  Chip OTP reports board serial "default", so the BCF must be named explicitly:
  `bcf=bcf_fgh100mhaamd.bin`.
- Regulatory: driver has no TW regdomain. `SG` is 920-925 MHz / 4 MHz / 22 dBm,
  which matches the Taiwan NCC allocation exactly. Built with
  CONFIG_MORSE_COUNTRY=SG, overridable with country=.

## What works
Reset, chip ID read, firmware load, BCF load - i.e. the whole CMD52/CMD53-read
path, but only with `spi_rx_lshift=2`.

## The open problem: a constant 2-bit skew on the chip's responses
Every response from the chip arrives 2 bit times late, off the byte grid.
Verified in userspace against /dev/spidev0.0, independent of the driver:
- CMD0 with a correct CRC7  -> R1 = 0x01 (idle)
- CMD0 with a corrupted CRC -> R1 = 0x09 (idle + CRC error)
- CMD13                     -> R1 = 0x05 (idle + illegal command)
- no command                -> nothing at all (all 0xff)
So the chip decodes our commands perfectly (it validates our CRC7); only its
*transmit* framing is 2 bits off ours. Clock-independent: identical at 400 kHz,
1 MHz, 20 MHz and 50 MHz, so it is not a propagation-delay effect.

`spi_rx_lshift=N` (added in the patch, mirrors the existing `is_rk3288` 1-bit
right-shift hack) re-aligns receives and makes reads work.

Writes still fail: CMD53 data-block writes get a correct R1, but no data
response token ever appears - dumped a 71-byte window, all 0xff. Yet the same
transaction driven by hand from userspace *does* return token 0x05
(SPI_RESPONSE_ACCEPTED) two bytes after the CRC. Difference between the two
paths is not yet understood; card state (idle vs initialised) is the main
suspect. `spi_tx_rshift=2` moves the failure to an earlier stage, so the TX
grid matters too.

## Eliminated (2026-08-19, all tested on hardware)
- SPI clock: 400 kHz, 1, 10, 20, 50 MHz - identical 2-bit skew at every speed.
- SPI mode 0/1/2/3 - mode 1 shows a 1-bit skew instead of 2, none is clean.
- TX bit alignment (`spi_tx_rshift`): shifting transmits breaks CMD63 outright,
  which proves the chip's *receive* byte grid already matches ours. Only its
  transmit path is late.
- Longer wait between the write command's R1 and the data token
  (`spi_pre_token_bytes` 4/8/16/32) - no change.
- ~~Wider ack search window (`spi_post_write_status_bytes` 4/8/16/32/64) - the
  window is all 0xff out to 71 bytes; the chip sends nothing at all.~~
  **Withdrawn 2026-08-22:** Morse's own OpenWrt patch puts the floor for this
  window at 250 bytes. 64 was never enough to be a valid test.
- ~~`enable_ext_xtal_init=1` - no change.~~ **Withdrawn 2026-08-22:** the xtal
  init sequence is itself made of register writes, so it cannot run while the
  write path is broken. Retest after the padding fix.
- Cold power cycle of the slot (GPIO18 low 3 s, not just a RESET_N pulse) -
  skew and write failure both survive it, so neither is a stuck-state artifact.
- Driver tag 1.16.4. It does not build against 6.18 without work, but the
  reason is not what it first looks like - see "Driver version is ruled out"
  below, which supersedes an earlier wrong conclusion here.

## Carrier wiring finding
With the module powered and out of reset, tested by flipping the BCM2711
internal pull up/down and reading the level back:
- GPIO5 (SPI_INT, mPCIe pin 10): actively driven high -> connected.
- GPIO23 (WAKE, mPCIe 33) and GPIO24 (BUSY, mPCIe 31): follow the internal
  pull both ways -> floating, i.e. not wired on the M1 carrier.
BUSY is a module output, so it should be driven if it were connected. The M1's
mPCIe slot looks like a subset of the WM1302 Pi HAT wiring - enough for the
LoRa concentrator it was built for, not the full HaLow handshake.
Note this does *not* explain the write failure: `gpios.busy`/`gpios.wake` are
referenced only from ps.c (power save), never from the transfer path. But
power-gpios should be dropped from the overlay so the driver does not arm
power-save against pins that are not there.

## Driver version is ruled out (2026-08-19, later)
1.17.9 *does* build on kernel 6.18. The earlier "needs a Morse-patched kernel"
conclusion was wrong: the only blocker is one version guard. 2.0.1 changed

    #if KERNEL_VERSION(5, 10, 11) > MAC80211_VERSION_CODE
to
    #if KERNEL_VERSION(5, 10, 11) > MAC80211_VERSION_CODE || \
        KERNEL_VERSION(6, 18, 0) <= MAC80211_VERSION_CODE

because mainline 6.18 changed the S1G definitions again. Copy that one line into
1.17.9's dot11ah/s1g_ieee80211.h, apply the same three spi.c patches, and it
builds (worktree at ~/halow/morse_1.17.9).

**1.17.9 then behaves exactly like 2.0.1**: needs spi_rx_lshift=2, reads chip ID
0x0306, loads firmware and BCF, and dies at the first CMD53 write with
find_data_ack failing. Two independent driver generations, identical symptom ->
this is not a driver regression, it is the bus/hardware interaction.

Also tried and ineffective: `spi_tx_lshift` 1/2/3 (the untested shift direction).

## From the datasheet (SKU 109990565)
- VBAT 3.0-3.6 V typ 3.3 V, but **VDD_IO is 1.62-3.6 V, typ 1.8/3.3 V** - the
  module has a separate I/O rail that can be 1.8 V. Where that rail is fed from
  on the M1's mPCIe slot is unverified and is a live suspect: the M1 carrier was
  built for a WM1303 LoRa concentrator, not for this module.
- The datasheet references an official pinout figure but the PDF only embeds a
  thumbnail; the readable version is on the Seeed product page.

## DECISIVE: this is an open upstream bug on officially supported hardware
MorseMicro/morse_driver **issue #9**, opened 2026-02-22, still open with no
maintainer reply:
  Raspberry Pi 4 Model B + **genuine Seeed WM1302 Pi HAT** + Wio-WM6108
  (FGH100M-H) + a **Morse-patched kernel 6.12.25-v8-morse+** + Raspberry Pi OS
  Trixie. Firmware and BCF load, then:
      morse_spi_cmd53_write failed
      cmd53_write fn=2 0x00000000:10 ... (ret:-71)
      morse_firmware_init failed: -5
  Reporter tried 50 MHz down to 2.5 MHz, SPI modes 0 and 3, several BCFs, and a
  reset script. No resolution.

So **the WM1302 Pi HAT would not have fixed this** - that configuration fails
the same way. The carrier board is not the problem, and neither is the kernel
patch set.

Every documented success is on a **Pi 5** (RP1 SPI controller), and even there
`cmd53_write ret:-71` shows up under sustained load. Nobody in the Morse
community thread reports success on a Pi 4 / bcm2835 SPI controller.

Seeed's own getting-started page supports exactly one configuration: Raspberry
Pi 4 Model B running their **pre-built OpenWrt image**, flashed to a microSD.
They also state the device "only supports the US and does not support other
countries or regions".

## Next things to try, in order of expected value
1. **OpenMANET's `rpi4-mm6108-spi` image** on a spare microSD. Its device tree
   is already the WM1302 HAT pin map with GPIO17 pulled up, and it carries the
   same driver release and firmware built here, so the only variable left is
   the kernel and its `spi-bcm2835` generation (6.6.138 there, 6.18.34 here).
   Only the slot power line (`gpio=18=op,dh`) has to be added. A tip from
   not5erpe on issue #9; the rpi4-mm6108-spi asset is by far the most
   downloaded of that release, which suggests the combination is in real use.
2. Seeed's own prebuilt image. It is the only configuration Seeed document, and it pulls in a completely different kernel - 5.15.189
   against the 6.18.34 here - so it also tests a different `spi-bcm2835`
   generation, which is a variable that cannot be changed on the running
   system. `overlays/openwrt/` has the corrected overlay and a script that
   patches a freshly flashed boot partition; the stock image will not work
   unmodified because its overlay is for Morse's EKH01 pin map.
   Note the driver in those images is stock, with no `spi_rx_lshift`, so if the
   skew is still present it will stop at CMD63 rather than reaching the write.
   Either outcome is a result worth having.
3. Establish whether the 2-bit skew comes from the BCM2835 SPI controller
   rather than the module - the driver already carries a 1-bit shift quirk for
   RK3288, so a controller-side skew has precedent.
4. Failing all of that, this module and a Pi 4 may simply not work together. Every
   documented success is on a Pi 5 / RP1, and a USB HaLow adapter would side-
   step the SPI transport entirely.

## Nothing here persists across a reboot
The device tree overlay was applied at runtime only; config.txt is untouched.
A reboot returns the machine to plain spidev0.0/0.1 with no morse driver.
Files installed outside ~/halow: /lib/firmware/morse/* only.
