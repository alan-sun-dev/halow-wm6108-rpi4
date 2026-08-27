# Wio-WM6108 (MM6108A1) on SenseCAP M1 — bring-up state, 2026-08-19

*[中文版](NOTES.zh-TW.md)*

## 2026-08-27 (night, later) — the pin map is measured, and all four HAT devices are undeclared

`m1-hat-probe.sh survey` was run on the station. Read-only throughout: no
reboot, no module reload, nothing written. The soak was unharmed and is the
check that says so — `wlan1` `up`, `spi_errors` 0, uptime 17 h 04 m across the
run. Output in `logs/2026-08-27-station-m1-hat-survey.txt`.

`selftest` was run on the station first, before the survey, because a guard
verified only on the laptop is verified on the wrong machine. **All seven fired,
including `timeout present`** — the one that legitimately FAILs on macOS.

### The pin map, no longer a recollection

`/sys/kernel/debug/gpio` settles it:

| GPIO | consumer |
|---|---|
| 5 | `mm610x_spi_irq_gpio` — the HaLow interrupt |
| 7 / 8 | `spi0 CS1` / `spi0 CS0` |
| **18** | **`halow-slot-power`** — mPCIe slot power, also forced high at firmware time by `gpio=18=op,dh` in `config.txt` |
| 23 | `morse-wakeup-ctrl` |
| 24 | `morse-async-wakeup-ctrl`, input with an IRQ |

The recollection recorded a few hours ago — that Seeed's `reset_lgw.sh` used
GPIO 17 / 18 / 5, and that a HaLow overlay reusing one would be a conflict — is
**half right and the half that mattered is wrong**. 18 and 5 are indeed in use,
and the interesting part is *how*: Seeed's LoRa slot power-enable and interrupt
lines were inherited by the HaLow module in the same socket. **GPIO 17 is
claimed by nothing. There is no conflict.** Recorded because a guess that half
survives contact is the kind that gets trusted next time.

`config.txt` also confirms in passing what was corrected on 2026-08-26:
`otg_mode=1` sits under `[cm4]` and `dtoverlay=dwc2,dr_mode=host` under `[cm5]`,
neither applying here, while the working `dtoverlay=dwc2,dr_mode=peripheral`
sits under `[all]`.

### Nothing in software declares the button, fan, LED or crypto chip

- No HAT ID EEPROM: `/proc/device-tree/hat` does not exist.
- `/sys/class/leds` holds `ACT`, `PWR`, `mmc0` — **every one of them internal to
  the Pi.** The HAT's panel LED is registered nowhere.
- The only input devices are the two HDMI jacks. No `gpio-key`.
- No thermal cooling device at all. No `gpio-fan`. The board was at 44.8 °C with
  `throttled=0x0`.
- **The header I²C bus is switched off.** `dtparam=i2c_arm=on` is present in
  `config.txt` but **commented out**, and there is no `/dev/i2c-*`. The only
  I²C adapters registered are the SoC's own `fef04500` and `fef09500`.

**Undeclared is not absent.** This says that nothing in software touches those
four devices; it says nothing about whether the hardware is fitted. They sit on
the unclaimed lines — 2, 3, 4, 6, 9–17, 19–22, 25–27.

### An eighth way one of our tools lied by being quiet

The I²C section originally tested for `i2cdetect` first, found it missing on
this board, printed that, and stopped. Which meant it never reported the larger
and more useful fact underneath: **the bus is not enabled at all.** A missing
scanner had masked a switched-off bus.

Fixed in place — existence of the bus is now established first and
independently, the scanner second, and when the bus is absent the section prints
the `config.txt` i²c line verbatim and says plainly that enabling it costs a
reboot. Re-run on the station to prove the new path reports correctly, which it
does. This is the eighth instrument of our own caught saying nothing when it had
something to say, and the first one where the silence was structural rather than
a shell trap.

### Both remaining questions are now blocked on hardware, not on knowledge

- **The crypto chip cannot be reached, scanned, or ruled out** without
  `dtparam=i2c_arm=on` and a **reboot** — which ends the soak.
- **The button, fan and LED pins** need `button` mode, which requests GPIO lines
  on the same gpiochip as the HaLow interrupt. It **must not** run on the soak
  node.

`dkmstest` cannot answer either question: it is the RAK chassis with a Heltec
HAT and does not carry this hardware. The AP is a SenseCAP M1 and does, but it
is the infrastructure the station depends on, and it runs OpenWrt.

So both questions unblock when the two additional M1s arrive, and that is now a
concrete use for them rather than a general argument for a uniform fleet.

## 2026-08-27 (night) — the panel USB-C is 5V only, and the board on the bench answers an open hardware question

A product listing prompted this: Signal & Steel sell a Sensecap M1 with the
WM1302 concentrator swapped for a WM6108 and OpenMANET pre-flashed. The
question asked of it was narrow — can its USB-C be the gadget port that local
access was settled on the day before? Answering it turned out to be about
hardware already on this bench.

**Nothing below was measured.** No probe was run against any board. Everything
here comes from Seeed's own HAT block diagram and panel drawings, and the one
inference in it is labelled as one.

### That listing is this hardware

The first line of this file has said `on SenseCAP M1` since 2026-08-19, and
"Board identity, recorded late" further down records **two** SenseCAP M1 units:
`E4:5F:01:52:57:E7`, now the AP, and `E4:5F:01:52:55:04`, the station. The
side-by-side table gives both the same `Carrier / module` row — `SenseCAP M1 +
Wio-WM6108 (MM6108A1)`. What is for sale is a pre-modded, pre-flashed version of
what was built here twice by hand. It is not a third platform to evaluate, and
everything below can be checked on a board already in the building.

### The exposed USB-C carries only power, and that was never the one being used

Seeed's block diagram puts that connector **on the HAT, not on the Pi**, with
exactly two lines leaving it, both labelled `5V`: one into the 40-pin header to
feed the Pi, one into a DC/DC. **No D+/D- is drawn at all.** The header carries
only SPI, GPIO, POWER and I²C, so no USB could reach the SoC through it even if
the connector had data pins. The panel drawing labels it `USB Type-C (Power)`
and the silkscreen reads `5V-3A`. Three independent statements of one fact.

So the gadget port in `tools/usb-gadget/` is, and always was, the **Pi 4B's
own** USB-C on the opposite edge of the board — which is why the entry of
2026-08-26 could record `otg_mode`, `dwc2` and a working NCM+ACM link on this
same hardware without any contradiction.

### This closes the hardware item left open on 2026-08-26

That entry ends: *"the Pi 4's USB-C is power and gadget, so plugging in a laptop
interrupts the board's power unless it is fed over the GPIO header. Acceptable
on a bench, wrong for a deployed console server."*

**The way to feed it over the GPIO header is already soldered to the board.**
Power the unit through the HAT's `5V-3A` connector, which reaches the Pi's 5V
rail through the header, and the Pi's own USB-C stops carrying power. A
technician's cable then interrupts nothing. No new parts, and it can be tried on
the station or the AP today.

**Untested.** Both 5V sources still land on the same rail when a laptop is
attached, which is the ordinary situation for any externally powered Pi in
peripheral mode but has not been checked here. `vcgencmd get_throttled` is the
instrument, as it was when the MacBook was measured as an adequate supply.

### What the metal enclosure costs, if a deployed unit is in one

The rear panel exposes RP-SMA, button, LED, USB-C and RJ45, and nothing else.
Two consequences, neither of which affects a bench board out of its case:

- **The Pi's USB-C is not exposed.** It sits on the Pi's long edge beside the
  two micro-HDMIs, facing the metal sleeve. Reaching it in a cased unit is
  mechanical work, not configuration.
- **No USB-A is exposed either.** *Inference, not observation:* on a Pi 4B the
  RJ45 and both USB-A stacks share one short edge, so the vent slots beside the
  ETH cutout should sit over the USB-A ports, and removing that panel should
  expose all four. If it holds, that is where the console server's USB-serial
  adapter goes — the item the maturity review counts as never once attempted.
  USB-A is host-only and can never be a gadget port, so the two capabilities
  come from two different edges of one board.

### The rest of the HAT, and why the LED is the piece worth taking

The HAT also carries a button, a fan, an LED and a crypto chip, all reaching the
Pi through the same header, so all of them are ordinary GPIO or I²C devices.
**Their pins are unknown.** The fast way to find them is not probing but reading
the shipped HaLow overlay, since what it does not name is the candidate set.
*Recollection to verify rather than trust:* Seeed's `reset_lgw.sh` for this HAT
used GPIO 17 / 18 / 5, and a HaLow overlay reusing one of those is a conflict to
settle before anything else.

The **button** is not a power switch and cuts nothing; it was the Helium
"long-press five seconds to enter config mode" key. As `dtoverlay=gpio-key` it
becomes an input event, and a long-press that restores a known-good HaLow
configuration is a trigger for exactly the unattended recovery this project does
not have. `gpio-shutdown` is the lesser use.

The **fan** is switched from a header line through a transistor, so
`dtoverlay=gpio-fan,gpiopin=N,temp=55000` registers it as a thermal cooling
device and the kernel starts and stops it on temperature with no daemon.

The **LED** is the piece worth acting on soonest. Its four Helium states — off,
fast flash, slow flash, steady — were painted entirely by a userspace daemon
that the OpenMANET image no longer carries. The hardware is one unowned
single-colour LED on a GPIO with no legacy semantics to respect, and it is **the
only visible light on the box**, since the Pi's own ACT and PWR are sealed
inside. Registered with `dtoverlay=gpio-led` and bound to the kernel's `netdev`
trigger on `wlan1`, the panel light *becomes* the HaLow association state: dark
means not associated, blinking means traffic. That is readable from the front of
a rack with nothing running, and it is the cheap half of the largest open risk
here — a node whose radio does not come up currently shows nothing at all.
`device_name` cannot be set from the overlay, so it needs a small systemd unit
or udev rule. `active_low` depends on polarity and is unverified.

### The crypto chip, and one instrument that lies by being blank

It is a Microchip ATECC608A holding the Helium swarm key, on I²C at `0x60`. Its
config and data zones **lock one way, permanently**, and Seeed locked them at the
factory to provision the miner identity, so the realistic ceiling is a key that
can sign but cannot be replaced. Establish the lock state before spending
anything on it, and **issue no write** until then. The kernel's `atmel-ecc`
exposes only ECDH and is not built on Raspberry Pi OS; the real path is
CryptoAuthLib in userspace over `/dev/i2c-1`, whose PKCS#11 module lets OpenSSL
and `ssh` use the chip's key — the interesting use being an mTLS identity for
the console server with no private key on the SD card.

**A blank `i2cdetect` at `0x60` is inconclusive, never negative.** An ATECC608A
that has not been woken NACKs its own address, and `i2cdetect` sends no wake
pulse. This is the same shape as the soak checkpoint that exited 0 with 25 of
its 30 fields empty: an instrument whose silence reads as an answer.

### The tool

`tools/m1-hat/m1-hat-probe.sh`, committed as `1cc5bfe`. `survey` is read-only —
model, HAT ID EEPROM, `config.txt` in full, device-tree nodes matching
gpio/fan/key/led/crypto/morse, `/sys/kernel/debug/gpio`, libgpiod, input
devices, thermal cooling devices, LED class, every I²C bus, SPI and the morse
module, and whether `atmel-ecc` exists. It drives no GPIO as an output and
writes nothing to the crypto chip. `button` does nothing without `--yes`, lists
the lines it intends to request first, and excludes any pin named by a
`dtoverlay=` line in `config.txt`, because the HaLow module's reset line is on
the same gpiochip and may be idle whenever the driver is not loaded.

Every one of the six ways our own tools lied on 2026-08-27 is guarded against:
absolute paths for `/usr/sbin/i2cdetect` because a non-interactive ssh PATH
lacks it; `timeout` exit 124 treated as success and anything else as `gpiomon`
failing; an empty I²C bus list tested as empty rather than falling into
arithmetic; and a missing tool, a missing file or a non-root run printing a
`!!!!` line and pushing the exit code to 2 rather than leaving a section blank.

`selftest` exists because a guard that has never fired is not a guard. Six of
them, all made to fail on purpose, including both libgpiod dialects parsed from
synthetic v1 and v2 output down to the same line number. It has been run: the
only FAIL is `timeout present`, on the laptop, which is the guard correctly
reporting that macOS is not where this belongs. `survey` was also run to
completion on the laptop — thirteen sections, every one printing something,
exit 2.

**Next, and it needs no new hardware:** run `sudo m1-hat-probe.sh survey` on the
station. It is read-only, so it does not disturb the soak — no reboot, no
module reload, no write. `/sys/kernel/debug/gpio` is the section that matters
and it is the one that needs root.

## 2026-08-27 (evening) — a maturity review, and the things the repositories say that the notes do not

A read-only review of both repositories against the target this work actually
serves: a HaLow-backhauled out-of-band console server. Nothing was changed, no
node was rebooted, and the soak node was not disturbed. The rule applied
throughout was that a claim with no artefact behind it is **not present**, not
done.

Full review, with the scoring table and the sequence:
<https://claude.ai/code/artifact/74bc6d49-96bb-4957-ae60-a0c30efff6a6>

### Where it actually is

| | area | classification |
|---|---|---|
| A | driver portability | **established** |
| B | DKMS / kernel lifecycle | usable but incomplete |
| C | wireless link — function | **established** |
| C | wireless link — reliability | **experimental** |
| D | test / observability tooling | usable but incomplete |
| E | out-of-band recovery | usable but incomplete |
| F | console-server productization | **not started** |
| G | mesh / OpenMANET readiness | **not started** |

Splitting C is the point of the table. Association, DHCP, bidirectional traffic
and zero SPI counters are proven on two boards and two kernels. *Reliability* is
a different claim and rests on **ten checkpoints across three files, with a
longest recorded association of about 16.5 hours**, sampled rather than
monitored, with no reconnect counter. "No reproducible driver failure" is true
and is bounded by that.

### Four things reading the repositories established that the notes had not

**Mesh capability is already there, and one command showed it.** The morse phy
lists `mesh point` among its supported interface modes, `mesh.c`/`mesh.h` are in
the driver, and the loaded module carries 284 mesh symbols. So the first two
bullets of any "mesh phase 1" are answered for free. The same output also bounds
what mesh could add: `#{managed, AP, mesh point} <= 2, total <= 2, #channels <= 1`.
**The open question was never *can it*. It is *is it worth it*, and nothing in
the current deployment argues yes.**

**The console server has never been executed once.** Not a judgement — a count.
References to `ser2net`, `conserver`, `ttyUSB`, WireGuard, rsyslog or Prometheus
across both repositories: **zero**. No USB serial adapter has ever been attached
to any node; `ser2net` is not installed. Every result this project has produced
so far is infrastructure for an application that has not been run.

**The Ethernet recovery that saved a broken upgrade is not reproducible.** The
nodes carry an `eth0-bench` autoconnect profile, so the capability is real. But
there is **no configuration, no procedure and no artefact in either repository**,
which means it exists as experience and cannot be recreated on a new board. That
is the gap to close on paper, and it is more urgent than it looks, because the
other local path — USB-C — needs a person at the rack *and* interrupts board
power on a Pi 4.

**The pre-reboot gate's verified surface is smaller than its size.** One of its
ten checks was found this morning to have never executed on any board. How many
of the other nine are in the same state is not known, and that uncertainty is
now part of the deployment risk rather than a tooling footnote.

### The biggest deployment risk, stated plainly

**There is no tested unattended recovery for a node whose HaLow does not come
up.** The gate is manual and runs before the reboot; USB-C needs physical
presence and cuts power; Ethernet recovery is not reproducible. The missing test
is specific: *make the module fail to load at boot on a node you may not
physically touch, then prove you can still get in and roll back.*

Related uncertainty, not resolved: `apt-daily-upgrade.timer` is enabled and
active on the DKMS board, but `unattended-upgrades` could not be confirmed
present. The risk of a kernel installing and rebooting with nobody running the
gate is therefore probably lower than assumed — **probably is not established**,
and confirming it belongs inside that same test.

### Proposed sequence, awaiting approval

```
NOW    1 console-server functional prototype -- real adapter, real console
       2 boot-failure remote recovery and rollback + Ethernet rescue as an artefact
       3 long soak with reconnect counting (parallel, near-zero cost)
NEXT   4 formal OOB management design incl. rescue procedure
       5 observability / health telemetry, driven by the prototype
       6 security model for the parts that now exist
LATER  7 AP/STA deployment architecture (needs >2 nodes)
       8 automated regression framework
       9 release / packaging quality, closing the A1 / 6.12.96 cell
DEFER  10 mesh phase 1 -- research branch, never a dependency
       11 OpenMANET reference analysis
       12 central server / LLM integration
```

Two departures from the ordering as it was proposed: the formal OOB design moves
**later**, because most of it is already built and merely unwritten while the
part that remains cannot be written correctly until the prototype shows what a
node needs when it goes dark; and the longer soak moves **earlier**, because it
costs almost no engineering time and currently backs the thinnest evidence here.

A `.deb` is not worth building yet. DKMS plus an install script is right for this
stage: a package is a distribution promise made to nobody, against a matrix that
still has a hole in it.

**Nothing has been started.** Three decisions are open: whether the ordering
holds, which board hosts the prototype (recommendation: the DKMS board or a third
card — **not the A1 soak node**, which is the only thing accumulating reliability
evidence), and when to run the destructive recovery test, which needs the
dedicated card and someone present.

## 2026-08-27 — a gate that had never run, and the house Wi-Fi ruled out by measurement

### The station's HaLow link degraded overnight, and the driver had nothing to do with it

The A1 station did not reboot: uptime 2771 s, association 2761 s, `boot_id`
unchanged from the previous evening. What changed is the air. Against the
previous session's −52…−45 dBm the station read −56 dBm and the AP saw it at
−60…−65, and the AP's own estimate of the link fell from 4.394 Mbit/s to
1.410 Mbit/s *within* this session.

Everything on the driver side stayed at zero: `spi_errors 0`, `spi_timedout 0`,
`dmesg_failures 0`, `sta_tx_failed 0`, `power_save off`. **The degradation is
entirely in the RF path.** For a console-server backhaul that is the good half
of the news and the bad half at once — the driver holds, but a link in this
state makes `ssh` take 20 s at the fifth attempt and starts losing 15 % of a
20-packet ping.

The comparison that makes it concrete puts both stations under the same load,
from the AP, one hop, in adjacent minutes:

| | A1 station `9c:04:…:fe` | `dkmstest` `0c:bf:…:91` |
|---|---|---|
| tx packets | +64 | +65 |
| **tx retries** | **+88 (1.38/pkt)** | **+0** |
| packet loss | 0 % | 0 % |
| RTT avg / max | **19.3 / 46.6 ms** | 4.8 / 13.7 ms |
| signal | −60 → −63 dBm | −46 → −41 dBm |

**An earlier reading of `dkmstest` as "0 retries" was not evidence of health.**
It had carried 58 packets in its whole association. Equal load is what makes
the two columns comparable, and it had to be created deliberately.

**Narrowed later the same morning — see the last section of this entry.** Eleven
hours of equal-load rounds show the retry cost never moved; what swung was the
AP's rate estimate, not the price of moving a packet.

### The house Wi-Fi is not the cause — four paired rounds say so

The obvious suspect was the station's own 2.4/5 GHz radio. The physical
argument said no (brcmfmac on SDIO, morse on SPI, 922 MHz versus 2.4/5 GHz), but
the argument had never been measured. `dkmstest` is the control: it shares the
AP and the medium and is untouched by anything done on the station.

| | A1 retries/pkt | `dkmstest` (control) | A1 RTT avg |
|---|---|---|---|
| wlan0 **down**, round 1 | 1.23 | 0.00 | 18.7 ms |
| wlan0 **down**, round 2 | 1.22 | 0.00 | 16.9 ms |
| wlan0 **up**, round 3 | 1.20 | 0.00 | 17.0 ms |
| wlan0 **up**, round 4 | 1.40 | 0.00 | 14.2 ms |
| wlan0 **up**, baseline | 1.38 | 0.00 | 19.3 ms |

The two "down" samples fall inside the range of the three "up" samples. The
control reads 0.00 in every round, so neither the AP nor the method drifted.
**Turning the house Wi-Fi off changes nothing.**

**There is a trap in doing this at all, and it nearly cost the board.** The
HaLow interface is a mac80211 device, so NetworkManager lists `wlan1` as type
`wifi` exactly like `wlan0`. Any global "turn off Wi-Fi" — `nmcli radio wifi
off`, a `rfkill block wlan` — takes the HaLow link down with it, and HaLow is
this station's only usable path: the USB gadget cable has been removed and the
house Wi-Fi is the −86 dBm path that answers and then stalls. The interface must
be named, never a class of interfaces.

`wlan0` was therefore taken down by name (`nmcli device set wlan0 managed no`
then `ip link set wlan0 down`), which also stops NetworkManager's scan loop —
a marginal interface retrying forever is *noisier* than a downed one, so an
interface left "trying" is not the off state anyone means.

**Read retries, not dBm.** Between rounds 3 and 4 the station's reported signal
wandered from −65 to −54 with nothing moved and no change in retry rate. Given
that RSSI saturation on this part is already proven, the retry counter is the
more stable instrument for judging this link. **This turned out not to go far
enough — `ap_expected_thr` and the idle MCS are no more trustworthy than RSSI.
See the last section of this entry.**

### The preflight gate's dpkg check had never once run

`tools/dkms-lifecycle/dkms-lifecycle.sh preflight` is what stands between this
project and rebooting a board into a kernel with no modules. Its "dpkg clean"
check had only ever been tested against synthetic input. Run against a real
dpkg database — a throwaway package driven into three genuinely broken states on
`dkmstest` — it turned out that **one of its two arms had never executed on any
board, in any state**.

`dpkg -C` (`--audit`) needs root. As an ordinary user it prints nothing on
stdout and exits 2 with `unable to check lock file for dpkg database directory
/var/lib/dpkg: Permission denied` on stderr. The check ran

```sh
broken=$(dpkg -C 2>/dev/null | grep -c .)
```

with no `sudo`, with stderr discarded, and with the exit status thrown away by
the pipeline. `broken` was therefore always 0. It went unnoticed because the
other arm — a `dpkg -l` status filter, which needs no root — catches the same
states.

**Until it does not.** A package whose files-list is deleted keeps status `ii`,
so the `dpkg -l` arm sees nothing either. On that board the gate said:

```
[PASS] dpkg clean -- dpkg -C empty, no half-configured packages
gate exit=0
```

while `sudo dpkg -C` was reporting the package missing its list control file and
needing reinstallation. **A gate that passes a broken system is worse than no
gate**, and the PASS text asserted "dpkg -C empty" — a claim it had never
established. This is the same shape as the module-glob defect found on
2026-08-26: right format, plausible conclusion, check never performed.

The audit now runs under `sudo`, is captured whole, and its status is tested
*before* any pipeline touches it. `dpkg -C` exits 0 whether or not it finds
problems, so a non-zero status means the audit could not be performed — which
is not the same as clean and must not read as PASS. Verified on `dkmstest`
against a real dpkg database:

| state | before | after |
|---|---|---|
| clean | PASS | **PASS** |
| `iU` — unpacked, postinst never ran | FAIL, evidence `dpkg -C lines=0` | **FAIL**, both arms report |
| `iF` — postinst ran and failed | FAIL, same false evidence | **FAIL**, both arms report |
| **`ii` but files-list deleted** | **PASS — a broken system let through** | **FAIL**, audit text quoted |
| audit cannot run at all | silently counted as clean | **FAIL — "the audit was NOT performed"** |

That last row is new: "could not check" and "checked, found nothing" used to
produce the same answer. The detail lines also lost their indentation, because
`while read -r l` strips the leading whitespace `awk` had just added; `IFS=`
fixes it.

The fixed script is on `dkmstest` only. **The station still runs the old copy**
(`md5 d75872…`).

### A better instrument for the AP/station MCS asymmetry

The open question of why the AP sits one to two MCS below the station had
stalled because `iw survey dump` returns empty at both ends, leaving no noise
floor to compare. debugfs has `mmrc_table` — the rate controller's own per-rate
success statistics — **at both ends**. From the AP, both peers, the same minute:

```
Peer dkmstest   selected 4MHz SGI MCS7   117 success / 117 attempts = 100%,
                                         no other rate ever tried
Peer A1 station selected 4MHz LGI MCS0   MCS0 30/48=63%   MCS1 45/96=47%
                                         MCS2 30/102=29%  MCS3 33/102=32%
                                         MCS4  8/42=19%   MCS5  0/14=0%
```

The AP has walked all the way down to the bottom rate and still gets 63–75 %
first-attempt success there, while the station selects MCS2 in the other
direction with received signal symmetric within a few dB. The algorithm is not
misbehaving; the channel is. Note the honest limit: the two tables' cumulative
totals cover different traffic histories, so what compares directly is the
*currently selected* rate, and the AP's two peers side by side.

### The timed probe guard fired for real, for the first time

Yesterday's fix to `soak-checkpoint.sh` — reject a management path that answers
but crawls — had only been control-tested with `PROBE_MAX=0`. Today the default
run failed outright:

```
!!!! management path 192.168.108.19 answers but took 22s (limit 8s) -- too slow to carry a checkpoint, skipping
!!!! management path 10.41.0.208 is down: Timeout, server 10.41.0.208 not responding.
!!!! no management path to the station: tried 192.168.108.19 10.41.0.208
checkpoint_status  FAILED
```

Exactly the intended behaviour: it refused to write a checkpoint it could not
stand behind. `STATION=10.41.0.208` produced a complete one
(`logs/2026-08-27-a1-soak-checkpoints.txt`).

Also traced while doubting it: `spi_errors` comes from
`/sys/class/spi_master/spi0/spi0.0/statistics/errors`, the SPI controller's own
counters, not the morse debugfs tree — which has no such file. The number is
real.

### Six ways a tool lied today, all of them ours

None were found by reading code. All were found by running it somewhere new.

- **macOS has no `timeout`.** A reachability sweep reported five of five hosts
  unreachable; it was measuring `command not found`. All five were up.
- **An empty string in `$(( ))` is 0.** A counter-delta script printed
  `delta 0` for every field after fetching no data at all. Guard for the empty
  value *before* the arithmetic, or the absence of data reads as "nothing
  changed".
- **A non-interactive ssh PATH has no `/usr/sbin`.** `iw: command not found`
  left the "power save" and "station dump" headings with nothing under them —
  the same banner-with-no-content shape `soak-checkpoint.sh` was fixed for last
  month. That tool writes `/sbin/iw` in full and was right; the hand-typed
  version was not.
- **`pkill -f <pattern>` matches its own command line.** `pkill -f "sleep 900"`
  killed the shell running it, because the pattern is in that shell's argv. The
  `ps | grep` version of this has now appeared three times; `pkill` is the same
  bug with a delete key attached.
- **Killing a watchdog's `sleep` triggers it.** `sh -c "sleep 720; restore"`
  runs `restore` the moment the sleep dies. To cancel one of these, kill the
  parent shell. This project arms timed auto-restores routinely, so "disarming"
  one by killing the visible `sleep` process does the opposite of what it looks
  like.
- **`| tail -1` threw away the error and kept the hint.** A restore script
  logged `Hint: use 'journalctl -xe ...'` and nothing about what actually
  failed.

### `nmcli connection up` is not a restore path on a weak link

The `wlan0` restore script was proven before being relied on — armed on a 60 s
timer and made to fire while nothing was broken. It failed, and the way it
failed matters: `nmcli connection up sun` **deactivates before reactivating**,
and at −86 dBm the reassociation does not come back. It left `wlan0` `DORMANT`,
cycling scanning → associating → disconnected for minutes. The first, manual run
had succeeded — taking 29 s — so a single successful run proved nothing.

The working form hands the device back and lets NetworkManager's own autoconnect
do the associating:

```sh
ip link set wlan0 up
nmcli device set wlan0 managed yes
```

That restored the link in 10 s, twice. **On a marginal link, "down" is reliable
and "up" is not** — which is the whole argument for staging changes and for
timed auto-restore, and the reason to make the restore fire once before
depending on it.

HaLow was never disturbed: association ran 4803 s unbroken across the whole
experiment, `spi_errors` and `spi_timedout` both 0, and the station was left
with both interfaces up, both default routes back, and no background jobs.

### Ten hours later: the retry cost never moved, and three claims above narrow

A checkpoint at 10:19, association unbroken at 39,024 s, showed the link
apparently recovered: `ap_expected_thr` 1.410 → **7.910 Mbit/s**,
`sta_tx_bitrate` MCS1 → MCS3, `sta_rx_bitrate` MCS0 → MCS4, `ping_20x` 15 % loss
→ 0 %. Reported signal went from −56 to −55 dBm. **One dB, and the AP's estimate
of the link multiplied by 5.6.**

Two more equal-load rounds in that state put the recovery somewhere other than
where it looked. Every equal-load round run today — same 60 packets, same AP,
same single hop:

| time | condition | A1 retries/pkt | `dkmstest` |
|---|---|---|---|
| 00:10 | wlan0 up (baseline) | 1.38 | 0.00 |
| 00:39 | wlan0 **down** | 1.23 | 0.00 |
| 00:41 | wlan0 **down** | 1.22 | 0.00 |
| 00:45 | wlan0 up | 1.20 | 0.00 |
| 00:47 | wlan0 up | 1.40 | 0.00 |
| 10:20 | after "recovery" | **1.64** | 0.00 |
| 10:22 | after "recovery" | **1.17** | 0.02 |

Range 1.17–1.64, mean ≈ 1.32. Across eleven hours, a house radio switched off
and back on, a 10 dB swing in reported RSSI and a 5.6× swing in the AP's
throughput estimate, **the cost of actually moving a packet did not change.**
The control column stays at zero throughout.

Three statements earlier in this entry are therefore narrower than they were
written:

- **"The link degraded overnight" is too strong.** What degraded was the AP's
  rate estimate and the idle MCS. The load-bearing number — retries per packet —
  reads the same before, during and after. What is durable is that this station
  costs ~1.3 retries per packet while `dkmstest` costs none. **That standing
  difference, not the swing, is the finding.**
- **The 15 % ping loss at 00:14 is confounded.** `mgmt_medium` said plainly that
  the checkpoint was riding the link under test, so that ping shared a medium
  with the ssh carrying it. The 10:19 checkpoint ran out-of-band over house
  Wi-Fi, which had become usable again. 15 % → 0 % compares two different
  measurements. **The tool labelled this correctly; the reading of it did not.**
- **"Read retries, not dBm" was not broad enough.** `ap_expected_thr` and the
  idle MCS deserve the same distrust as RSSI — all three moved while the retry
  cost held. Under load, retries per packet is the only one of the four that
  stayed still.

The management path also chose itself differently: at 10:19 the timed probe
accepted `192.168.108.19`, so `mgmt_medium` reads `out-of-band (house Wi-Fi)`.
The −86 dBm path is not permanently unusable — it is intermittently unusable,
which is why the probe has to be timed on every run rather than decided once.

## 2026-08-26 (evening) — local access over USB-C, and three of our own tools caught lying

This project's driver work exists to serve something else: a **console server**
wired to Cisco switches, shipping configuration and logs to a central server for
diagnosis, with **HaLow as the backhaul** — chosen for fast deployment and
because that traffic deliberately does not ride the production network. That
reframes the bench work. Console text and log shipping need almost no
bandwidth; what matters is that a link stays up, and that a person standing at
the rack can get in when it does not.

### Why the local access path is USB-C and not a Wi-Fi AP

The obvious answer was `hostapd` on each Pi's idle radio. It was rejected, and
the reason is worth recording because the RF argument is the weakest one:

- **It does not interfere with HaLow at all.** The Pi's radio is 2.4/5 GHz on
  SDIO; HaLow is 922 MHz on SPI. Separate radios, separate buses, no overlap.
  On this hardware the constraint that does exist is
  `#{managed, AP, mesh point} <= 2, total <= 2, #channels <= 1` — station and AP
  can coexist but only on one channel.
- **The real objections are policy and multiplication.** An unmanaged AP in a
  datacentre is a rogue-AP finding before it is an RF problem, and N console
  servers means N SSIDs, N credentials, N attack surfaces. This project has
  already found unauthenticated `ttyd` shipped as a vendor default; repeating
  that shape in our own work would be worse.

Wired Ethernet was reconsidered and repositioned rather than dismissed: as **a
point-to-point cable to a technician's laptop** it has every property that made
it attractive and none of the provisioning cost, because it needs no switch
port. USB-C then beat it on one specific ground the user raised — it leaves
`eth0` free for an uplink.

Bluetooth was examined as a *control* channel rather than a data path — "press
a button without a button" — and deferred. The pattern is real and precedented
(Dell iDRAC Quick Sync 2, UniFi's BLE adoption, Aruba's AP utilities, ESP32's
`wifi_prov_mgr`), but a physical button or a cable **is itself authentication**,
and a BLE endpoint that can enable an AP is reachable from the corridor. It
earns its place only where the box cannot be physically reached.

### What one USB-C cable now gives, on both boards

`tools/usb-gadget/`. A composite gadget: **NCM** (a USB Ethernet link) plus
**ACM** (`/dev/ttyGS0`, a serial console — a console server with no console of
its own was a real gap). Verified on macOS against a Pi 4 Model B, hands-free
across a reboot:

| | |
|---|---|
| laptop address | `192.168.44.x` by DHCP, automatic |
| **default route** | **unchanged** — the laptop's own internet is untouched |
| **DNS** | **unchanged** — none is offered on this link |
| route to `10.41.0.0/16` | handed out via DHCP option 121 |
| `traceroute` to a node two hops away | `192.168.44.1` 0.9 ms → `10.41.0.208` 7.0 ms |

Suppressing the default route is the point: in dnsmasq an option **with no
value** means *do not send it*, so `dhcp-option=3` and `dhcp-option=6` leave the
laptop alone while option 121 still makes the cable useful. `.local` names keep
working — mDNS is multicast and needs no DNS server.

`dkmstest` uses `192.168.44.0/24` and the station `192.168.45.0/24`, so both can
be plugged into one laptop; a fleet would standardise on one.

**Two obstacles that would otherwise cost an hour each.** NetworkManager ships
`85-nm-unmanaged.rules`, which marks *every* USB gadget interface unmanaged —
its own comment gives the reason as "whatever created it might want to set it up
itself (e.g. activate an `ipv4.method=shared` connection)", which is exactly
what we want NM to do. And a gadget netdev **asserts no carrier until it is
administratively up**, while NM will not touch a carrier-less device; it reports
`unavailable` and stops. The script breaks the loop by running
`ip link set usb0 up` itself.

**A correction worth keeping.** The `otg_mode=1` and `dtoverlay=dwc2,dr_mode=host`
lines already in `config.txt` sit under `[cm4]` and `[cm5]` and **do not apply to
a Pi 4 Model B**. Reading them out with `grep -n` and missing the section headers
produced exactly the wrong conclusion — that the board already had dwc2 in host
mode and needed one word changed. It had no dwc2 overlay at all.

**Still unresolved, and it is hardware:** the Pi 4's USB-C is power *and* gadget,
so plugging in a laptop interrupts the board's power unless it is fed over the
GPIO header. Acceptable on a bench, wrong for a deployed console server.
Measured on a MacBook Air, `vcgencmd get_throttled` stayed `0x0` across a full
boot with the HaLow HAT and both radios up, so laptop power itself is adequate.

### Installing it on the board with no way back

The station is one floor up and its only working path is the link under test, so
everything was staged first and the reboot done once. The path used was neither
HaLow-direct nor the other node, but **the AP as a jump host**:

```sh
PX="ssh -o BatchMode=yes -o UserKnownHostsFile=$KH root@192.168.108.5 nc %h %p"
ssh -o ProxyCommand="$PX" alan@10.41.0.208
```

**`ssh -J` does not work here** — the AP's dropbear has no `-W`/direct-tcpip, and
it fails with a misleading `Host key verification failed`. busybox `nc` as a
plain connect does.

It came back clean: `boot_id 1ce7f475… → 2ea29cc0…`, `/sys/class/udc/fe980000.usb`
present, `/dev/ttyGS0` present, HaLow re-associated, `spi_errors 0`,
`spi_timedout 0`, both modules loaded. Its `usb0` reads `unavailable` rather
than `unmanaged`, which is how you confirm the udev override took on a board
with nothing plugged in.

### Three of our own tools, caught lying

All three were found by *using* the tools on a board they had not been used on
before. None of them were found by reading the code.

**The preflight gate reported PASS on the wrong file.** Its module check globbed
`"$m.ko*"`, which also matches the backups this project leaves beside the live
module. The station's directory holds `morse.ko.xz`,
`morse.ko.xz.mm6108-2.0.1` and `morse.ko.xz.stale-20260822`; `head -1` picked
the one from 2026-08-22 and the gate reported PASS naming it. **Right answer,
wrong evidence — worse than a FAIL, because nobody re-examines a PASS.**

**The same gate could never pass on a hand-installed board.** `dkms status` has
no entry there, so it FAILed on a check that structurally cannot succeed, and
the next step would have been to override it and reboot a board with no recovery
path anyway. **A gate that is always overridden is not a gate.** It now
separates "dkms manages this module but has no build for the kernel about to
boot" (still FAIL) from "dkms does not manage it at all" (`[N/A ]`, the file and
`modinfo` checks being the authority) — verified on hardware that the dangerous
case still fails:

| | | |
|---|---|---|
| station + 6.6.51 | dkms unmanaged here | `[N/A ]` → **PASS** |
| `dkmstest` + 6.6.51 | dkms manages, no build | `[FAIL]` → **FAIL** |
| `dkmstest` + 6.12.96 | installed | `[PASS]` → **PASS** |

**"Reachable" is not "usable", and the soak tool could not tell.** After the
station's reboot its house Wi-Fi came back — SSID `Sun` at **−86 dBm**. The
preflight probe added to that tool this morning is `ssh <host> true`; it
succeeded, so the tool preferred that path over the working one and then hung
for minutes mid-checkpoint, twice, leaving a banner and a timestamp in the log
with nothing under them. The probe is now **timed**, and a path slower than
`PROBE_MAX` (8 s) is skipped like an unreachable one. Control-tested with
`PROBE_MAX=0`, which correctly rejects a healthy 1 s path.

**This corrects an entry from earlier the same day.** "The station has no
out-of-band path" is too strong. It re-associates to `Sun` after a reboot and
holds `192.168.108.19`, but at −86 dBm it alternates between timing out and
being too slow to carry a checkpoint. **Unusable is a different statement from
absent**, and the difference is what let the tool pick it.

### One operational trap the new setup introduces

Option 121 advertises `10.41.0.0/16` **via whichever node is plugged into the
laptop**. When that node briefly could not reach a station on that segment — a
transient ARP failure, cleared by traffic from the far side — the laptop got
`Network is unreachable` for the *entire* HaLow range while the AP could reach
everything on it. If the whole segment goes dark from the laptop, suspect the
USB-connected node before the segment.

## 2026-08-26 (afternoon) — the AP was moved, the DKMS card identified, and a documented measurement that could not have happened

### Moving the root of the bench, with the one node that has no way back

The AP was powered off, physically moved, and brought back. It is the NAT
router, the DHCP server and the only AP on the bench, and since this morning
the station one floor up has had **no out-of-band path at all** — if the AP had
come back differently, that board would have needed a walk upstairs.

Two things were done first.

**The two HaLow nodes were pinned to their addresses.** `/tmp/dhcp.leases` is
on tmpfs, so a power cycle loses every lease, and both nodes held addresses
from the dynamic pool (`start=100 limit=150`, 12 h). dnsmasq usually returns
the same address for the same MAC, but usually is not a configuration
guarantee, and `10.41.0.208` is the one machine that cannot be recovered
remotely. Applied detached with a 900 s auto-rollback, per the rule that
anything written to the AP must be able to undo itself:

```
dhcp-host=9c:04:b6:ff:df:fe,10.41.0.208,Sensecap
dhcp-host=0c:bf:74:40:8e:91,10.41.0.216,dkmstest
```

Those two lines are read from **what dnsmasq generated**, not from `uci show` —
the `proto`-less firewall rule of 2026-08-26 is the reason that distinction is
now a habit.

**A size check worth doing.** After `uci commit` the live `/etc/config/dhcp` was
*smaller* than its backup — 936 bytes against 1183 — which is the wrong
direction after adding two sections. Comparing option by option (the AP has no
`diff`; the files were pulled to the laptop) showed uci's canonical rewrite had
stripped 247 bytes of trailing `#` comments from five lines whose values are
unchanged. Nothing was lost. The check took a minute and would have caught a
real loss.

**A closing checkpoint was taken before power-off**, so the soak has a defined
end: 18 h 55 m uptime, 16.5 h association, `spi_errors 0`, `spi_timedout 0`
across 1.752 GB and 5.85 M SPI messages, 20/20 pings.

### What came back

Everything, unchanged. The AP had genuinely rebooted — uptime 10 minutes
against 2 days 16 hours before, which is the check that matters, not the fact
that ssh answered.

| | before the move | after |
|---|---|---|
| station, AP-side signal | −56 dBm | −54 dBm |
| station, own view | −53 dBm | −48 dBm |
| `dkmstest`, AP-side signal | −43 dBm | −37 dBm |
| `dkmstest`, own view | −42 dBm | −33 dBm |
| SSID / frequency / bandwidth | `BCM2711-57e7` / 922.0 MHz / 4 MHz | identical |
| both nodes' addresses | .208 / .216 | .208 / .216, now by configuration |
| station uptime | 18 h 55 m | 19 h 16 m — it never rebooted |

**No conclusion is drawn from those signal columns.** Every one of them moved
in the "better" direction, and all four differences are smaller than the ~8 dB
this same bench was measured drifting between two samples four minutes apart
earlier the same day. Single samples cannot resolve a change this size.

**The AP's clock is right, which was not expected.** The box has no RTC, and
the standing advice has been that `logread` timestamps are unusable after a
boot. With a working WAN it now syncs at startup: the AP and the laptop agreed
to the second. The no-RTC limitation is real but only bites when the AP has no
internet.

### A latency finding that dissolved on the second sample

The first checkpoint after the move read **53.7 ms average, 116 ms max, stddev
32.2** against 13.1 ms / 4.9 before it — a clear "the move made it worse" if
written up. Three more runs, taken minutes later:

```
station : 14.362 / 13.427 / 16.438 ms
dkmstest: 13.472 / 14.641 ms
```

and the AP's own interface counters moved **+62 B tx / +42 B rx in 10 s**, so
the link was idle while they were taken. The first sample was the link settling
in the minute after both nodes re-associated. Same lesson as the RSSI column
above, one layer up.

### Throughput after the move: unchanged, and measured over the right link

`iperf` between `dkmstest` and the AP, one HaLow hop, 10 s per direction, TCP —
the same shape as the 2026-08-26 morning baseline:

| | baseline (before) | after the move |
|---|---|---|
| uplink, node → AP | 8.92 Mbit/s | **9.20 Mbit/s** |
| downlink, AP → node | 8.73 Mbit/s | **8.60 Mbit/s** |

`tx failed 0`, `spi_errors 0`, `spi_timedout 0` after ~25 MB. Both runs show
the same first-half/second-half shape (12.0 → 8.4 up, 13.8 → 7.3 down) — TCP's
window opening, not a link effect.

**The test target had to be chosen carefully.** From `dkmstest`, the AP has two
addresses: `10.41.254.1` routes over `wlan1`, and `192.168.108.5` routes over
`wlan0`, the house Wi-Fi. Aiming at the wrong one would have benchmarked the
house Wi-Fi and reported it as a HaLow figure. `ip route get` before the run
settles it in one command.

### A documented measurement that could not have been taken

The morning's throughput table records a station column — 3.56 Mbit/s up,
5.34 Mbit/s down — under the heading "measured with `iperf` 2.1.8 between each
station and the AP". **The station has never had `iperf` installed.** Checked
with the positive control in the same pass: its apt history holds exactly one
`Install:` line (build tools, 2026-08-22) and zero mentions of iperf; its
`dpkg.log` has 14 `status installed` lines and no iperf; and no binary exists
under any of the usual paths, nor `nc`, nor `socat`. `iperf` was installed on
`dkmstest` alone, on 2026-08-25 23:55.

So the station column was produced some other way, and the sentence describing
how the table was measured is wrong for half of it. The numbers are not
retracted — there is no evidence against them — but **their provenance is
unknown, and they must not be compared against an `iperf` run as though the
method matched.** Only the `dkmstest` column is comparable, which is why only
that row is repeated above.

### Five ways a command lied on the way through this

All caught, all cheap, all the same family as the rest of this file:

- **`ps w | grep -c "[s]tatic-leases"` returned 1 for a process that was not
  running.** The pattern matched the ssh session's *own* `ash -c` command line,
  which contained the pattern as text. Printing the matches instead of counting
  them showed one line, and it was the grep's own invocation.
- **`nohup … &` inside an ssh command did not survive the session**, twice, with
  no error and no output — the script simply never ran. `start-stop-daemon -S -b`
  (OpenWrt) and `setsid nohup … < /dev/null &` (Debian) both work, and the proof
  is a printed process line plus a listening socket, not the absence of an error.
- **`diff` does not exist on the AP.** The command returned 127 and the shell
  printed `diff: not found`, which is only visible because stderr was not
  redirected that time.
- **`diff` on two empty files exits 0.** An unquoted `$SSHOPTS` in zsh — which
  does not word-split — made both `cat`s fail, and the comparison of two 0-byte
  files "passed". The byte counts printed next to it are what caught it; this is
  the same shape as the empty-string sha256 recorded on 2026-08-25.
- **`command -v iperf` on the station said nothing, and this time it was true** —
  but only after checking `/usr/bin`, `/usr/sbin`, `/sbin`, `/usr/local/bin` and
  `dpkg -l` directly, because `dkms` had failed the identical test an hour
  earlier for the opposite reason: it is at `/usr/sbin/dkms`, off a non-root
  `PATH`, and the package was installed all along. Third time on this project
  after `iw` and `modinfo`.

### The `dkmstest` card, identified

The board is running the **DKMS-installed** build, confirmed three independent
ways: the modules load from `/lib/modules/6.12.96+rpt-rpi-v8/updates/dkms/`,
`/var/lib/dkms/morse/mm8108-2.0.0+rpi-portability/6.12.96+rpt-rpi-v8` exists,
and `dkms status` reports `installed`. 128 GB card, PARTUUID `f3449563`.

**DKMS has built the module for one kernel only.** Four are installed
(`6.12.96` and `6.6.51`, each `+rpt-rpi-v8` and `+rpt-rpi-2712`); `dkms status`
lists `6.12.96+rpt-rpi-v8` alone. Booting this card into `6.6.51+rpt-rpi-v8`
would find no morse module at all — which is a ready-made, un-engineered test
case for the `preflight` gate, needing nothing broken on purpose.

**`apt-daily-upgrade.timer` fires daily on this board.** Left alone — it
installs security updates only and does not reboot — but it is worth knowing it
exists on a board that is soaking, given that an unattended `apt full-upgrade`
once left this same hardware unable to load any module at all.

### The SSH host key that was never new

`10.41.0.216` presented a key that did not match `known_hosts_soak`. The
two-address check used on 2026-08-25 says "same host, new install" — but
reading the whole file says something better: the presented key
`SHA256:T7zNvr…` was **already trusted there**, recorded under two other names
for the same board, `192.168.108.13` and `10.42.0.2`. What was stale was the
`10.41.0.216` line itself, holding `SHA256:xBXal2…` — the key of that board's
**OpenWrt** install, which used the same HaLow address before the card was
swapped. The address was reused; the old entry was never cleared.

Replaced (old file kept as `known_hosts_soak.bak-20260826`) and verified by
logging in with `StrictHostKeyChecking=yes`, so the key was checked rather than
accepted. **Before deciding a key is new, look at what else in the file already
holds it.**
### The preflight gate, exercised against four kernels — the failure scenario needed nothing broken

The `preflight` gate has guarded every kernel reboot in this project since
2026-08-25, and until today its FAIL path had been seen only in passing. The
open question was whether it actually stops a reboot into a kernel DKMS never
built for. Testing that normally means breaking a build on purpose. It did not
have to: **`dkmstest` already carries four installed kernels and a DKMS package
built for exactly one of them.**

```
6.12.96+rpt-rpi-v8     <- running; dkms status: installed
6.12.96+rpt-rpi-2712      no module
6.6.51+rpt-rpi-v8         no module
6.6.51+rpt-rpi-2712       no module
```

Four runs, read-only, on the soaking board:

| target | checks | verdict | exit |
|---|---|---|---|
| `6.12.96+rpt-rpi-v8` | 10 PASS, 0 FAIL | **PASS** | 0 |
| `6.6.51+rpt-rpi-v8` | 4 PASS, 6 FAIL | FAIL | 1 |
| `6.12.96+rpt-rpi-2712` | 5 PASS, 5 FAIL | FAIL | 1 |
| `9.9.9-does-not-exist` | 1 PASS, 9 FAIL | FAIL | 1 |
| no argument | usage error | — | 1 |

The first row is the positive control, run in the same pass: without it, four
FAILs prove only that the gate can say no.

**What was genuinely new, and what was not.** The 2026-08-25 session had
already run the gate against `6.6.51+rpt-rpi-v8` and against a nonexistent
kernel, and both FAILed — so that much is a reproduction, not a first. Two
things are new:

- **Check 0 (`/lib/modules/$K exists`) had never executed.** It was added in
  `819a108` at 18:33:08 on 2026-08-25 — **41 seconds after that session's last
  gate run**. Today is the first time it has run, and the nonexistent-kernel
  case is what fires it.
- **The 2712 case isolates the thing the gate is actually for.** The 6.6.51 run
  is a blunt instrument: its initramfs check fails too, so it cannot separate
  "no module was ever built" from "this boot would be wrong anyway". The 2712
  kernel has its own initramfs slot, so that line PASSes and **the only five
  failures are the DKMS and module ones.** That is the clean demonstration.

**A structural point about the initramfs check, which is not a bug.**
`/boot/firmware/initramfs8` holds one image at a time — the running kernel's.
So for any *other* `+rpt-rpi-v8` kernel that check must FAIL, and correctly:
the firmware really would load a stale initramfs. The remedy for that
particular line is to make the target kernel the default so raspi-firmware
regenerates the FAT copy — **not** to build a module. Worth knowing before
someone reads it as a DKMS fault.

**`preflight` with no argument refuses rather than guessing**, exiting 1 on a
usage error. It does not fall back to `uname -r`; a gate that defaults to the
running kernel answers the wrong question at the one moment it matters.

**The one check still never seen firing on hardware is `dpkg clean`** — the
check with the most history behind it, since an unattended `apt full-upgrade`
once died on a conffile prompt, `linux-image`'s postinst never ran, and no
module of any kind could load. Faking that on a soaking board is not worth it,
so the awk was exercised on synthetic `dpkg -l` input: `notok=0` on clean
input, `notok=2` when `iF` and `iU` lines are added, and a held package (`hi`)
correctly not counted as a fault. The check discriminates; it has still never
run against real damaged dpkg output, and that stays open.
### The station's throughput, and an asymmetry that tracks the PHY rate — with two of its own claims corrected

`iperf` was installed on the station (2.1.8+dfsg-1, the same version
`dkmstest` runs, so the two boards are method-identical). The simulate step
first, because this board is soaking: `0 upgraded, 1 newly installed, 0 to
remove and 208 not upgraded`, and `dpkg -C` empty afterwards. The 208 pending
upgrades were deliberately left alone. One HaLow hop to `10.41.254.1`, checked
with `ip route get`, 10 s per direction, TCP.

**Two claims made from the first measurements were wrong and are withdrawn
below: a "10% frame failure rate", and a "3x asymmetry". Both came from one
short window and neither survived repetition.** What did survive is better.

#### The link was measured in two different states, hours apart, without moving anything

| | state A | state B |
|---|---|---|
| AP's view of the station | −52 dBm | **−45 dBm** |
| AP → station rate | MCS3, 117.0 Mbit/s, **long GI** | MCS4, **195.0 Mbit/s, short GI** |
| station → AP rate | MCS6, 292.6 Mbit/s | MCS6, 292.6 Mbit/s — unchanged |
| downlink, 6 runs | 1.63–2.67, mean **2.29 Mbit/s** | 4.82–5.29, mean **5.14 Mbit/s** |
| uplink, 2 runs | mean **6.84 Mbit/s** | mean **7.85 Mbit/s** |
| measured throughput ratio | **2.99x** | **1.53x** |
| PHY rate ratio 292.6 / (AP's rate) | **2.50x** | **1.50x** |

**The throughput asymmetry equals the PHY rate asymmetry, in both states.**
That is the finding. The direction is stable — uplink is always faster — but
the *magnitude* is not a property of the link, it is a readout of whatever MCS
the AP has settled on at that moment.

Nothing was moved between the two states. The signal drifted 7 dB on its own,
which is the same order as the ~8 dB this board was measured drifting between
two samples four minutes apart earlier the same day. The reverse direction sat
at MCS6 throughout.

#### Withdrawn: "10% of the AP's frames to the station fail"

That figure came from a single run — `tx_packets +2,616, tx_failed +261` — and
**it has not reproduced in seventeen subsequent measurements**, all taken the
same way from the AP's own counters:

| condition | packets | failed | |
|---|---|---|---|
| ping, 56 / 500 / 1400 B payload at 5 pps | 102 / 101 / 101 | 0 / 0 / 0 | 0.0% |
| UDP offered 1M | 896 | 0 | 0.0% |
| UDP offered 2M / 3M / 4M / 6M / 10M | 1788 / 2309 / 1908 / 2162 / 2368 | 12 / 11 / 22 / 17 / 7 | 0.7 / 0.5 / **1.2** / 0.8 / 0.3% |
| TCP, state A, 2 runs | 3550 / 2927 | 19 / 28 | 0.5 / 1.0% |
| TCP, state B, 6 runs | 5800–6524 each | 0 in every one | **0.0%** |
| *the original run* | *2,616* | *261* | *10.0%* |

The outlier run was also the slowest downlink ever recorded here
(1.63 Mbit/s against 2.15–2.67 for its neighbours), so it was anomalous on two
axes at once. **What happened during it is not known**, and no mechanism is
claimed for it.

The load ramp was built to test the theory that failures scale with offered
traffic. **They do not**: from 1 Mbit/s offered to 10 Mbit/s — well past
saturation, since 10M offered delivers only 2.64 — the failure rate stays
between 0.0% and 1.2% with no trend. The aggregation theory that motivated the
ramp is unsupported.

A failure rate under 1.2% cannot account for a 1.5x throughput ratio, let
alone 3x. **Frame loss was never the mechanism.** The rate is.

#### What does hold up

- **Frames are not dropped in the driver.** The AP's `page_stats` reads
  `Tx aged out: 0`, `Page write fail: 0`, `No page: 0`, `TX ps filtered: 0`,
  `TX status dropped: 0`, `TX dropped due to duty cycle: 0`. `Queue stop` is
  non-zero (1148) and that is ordinary flow control under load.
- **The control still does its job.** `dkmstest`, beside the AP, ran
  `tx_packets +9,239, tx_retries +678, tx_failed +0` at 8.81 Mbit/s in the same
  minutes as the outlier. Whatever that outlier was, it was not the AP's
  transmitter — which is the hypothesis this bench has already spent a day on
  once, and the reason the control was run at all.
- **The board is untouched by any of it.** Through ~150 MB of test traffic the
  association never dropped (14,129 s and counting), `spi_errors 0`,
  `spi_timedout 0`, `dmesg` failures 0, and the station's own `tx_failed` for
  the entire association is 3.

#### Still open, and now a sharper question

**Why does the AP pick an MCS one to two steps below the station's, when both
radios report `txpower 22.00 dBm` and the two ends see each other within 2 dB
(−45 / −50)?** The AP is not choosing badly by its own evidence: at state B its
main rate MCS4 succeeds 40,135 of 45,227 attempts (88.7%) while its MCS5 probes
succeed 26 of 275 (9.5%). From where it sits, MCS4 is the rate that works.

With power and signal symmetric, the difference has to be at the receivers, and
that is where the tools run out: **`iw dev … survey dump` returns nothing on
both ends** — no noise floor, no channel-busy time. Verified by exit code
rather than assumed: it exits 0 with empty output on the AP and on the station,
i.e. the morse driver does not implement the survey callback.

The obvious next measurement is cheap and has not been taken: wait for the
signal to drift back toward −52 and re-run both directions. If the ratio
returns to ~2.5x, "throughput ratio = PHY rate ratio" goes from two points to a
relationship.

## 2026-08-26 (midday) — the soak checkpoint tool was failing silently, and the station has no out-of-band path left

### A measurement tool that reported nothing, and said nothing about it

`tools/soak/soak-checkpoint.sh` returned **exit 0 with 25 of its 30 fields
blank**. The output has the right banner, the right timestamp and a plausible
set of AP-side counters; what is missing is the entire station-side block —
module versions, SPI statistics, RSSI, association uptime, dmesg counts. In
other words, everything about the board the soak is measuring. The failed run
is kept verbatim in `logs/2026-08-26-a1-soak-checkpoints.txt`.

Two lines caused it:

```sh
STATION=${STATION:-192.168.108.19}   # a management path that no longer exists
s() { ssh ... alan@"$STATION" "$@" 2>/dev/null; }
```

The address had gone away (below), and the `2>/dev/null` — put there to keep
ssh's banner noise out of the log — swallowed `Operation timed out` with it.
The block's exit status was never checked.

**This is the same failure mode this project has recorded some twenty times,
committed this time inside the tool built to guard against it.** The tool is
read-only by design, which is what made it feel safe; being read-only says
nothing about whether it is *reading*. A checkpoint missing its subject must
not be able to look like a checkpoint.

**The fixed tool fails loudly and exits non-zero.** What changed, none of it
touching the measurement fields:

- **Preflight.** Both the station and the AP are probed before anything is
  measured. Unreachable → `!!!!` line, `checkpoint_status FAILED`, exit 2.
- **stderr is captured and printed**, not discarded.
- **The remote block ends in a sentinel** (`__station_block_end__`), plus a
  field count. Without one, a block that dies halfway through is
  indistinguishable from a block that had nothing to say.
- **The AP block checks its dump actually contains the station's MAC**, rather
  than emitting empty `ap_*` fields when it does not.
- `AP` now defaults to `192.168.108.5`. `10.41.254.1` is the AP's HaLow side
  only and the laptop has not been able to reach it since the re-architecture —
  a second silent-empty source that was live at the same time.
- Exit codes: **0** complete, **2** incomplete or unreachable. `!!!!` lines go
  to stdout as well as stderr, so they land in the log beside the fields they
  invalidate.

**Five failure paths were then exercised on the real bench, not read off the
source** — the point of the exercise being that a guard nobody has seen fire is
a guard nobody has tested:

| forced condition | result |
|---|---|
| station given explicitly, unreachable | `FAILED`, exit 2 |
| AP unreachable | `FAILED`, exit 2 |
| no management path at all | `FAILED`, exit 2 |
| station block truncated to 5 lines, sentinel removed | two `!!!!` lines, `INCOMPLETE`, exit 2 |
| AP dump not listing the station's MAC | `!!!!` not associated, `INCOMPLETE`, exit 2 |

The truncation case was forced with an `ssh` shim earlier on `PATH` that
returns five lines and exits 0 — a way to test the "died halfway" branch
without breaking anything on the bench.

### The station has no out-of-band management path any more

`wlan0` is disconnected, and **neither house SSID is in its scan at all** — a
scan from the board returns `chome` −68, `HITRON-07B8-5G` −69, `family-2.4G`
−81 and six others, but no `Sun` and no `Unifi`. Both profiles are present
and set to autoconnect; there is nothing for them to connect to from where the
board now sits. It associated twice early in this boot and has not since.

**So the station is reachable over HaLow and nothing else.** Two consequences:

- **The link under test now carries its own instrument.** Every checkpoint's
  `ping_20x` shares a medium with the ssh session collecting the other 25
  fields. The tool records this in a `mgmt_medium` field on every run rather
  than leaving it to be remembered — this project has already published one
  wrong loss figure measured over the link carrying the measurement.
- **There is no recovery path if HaLow drops.** The AP's transmitter is known
  to stall silently on this bench, and the recovery for that is issued *to the
  AP*, so it is still available — but a station-side fault now needs physical
  access.

### Two discontinuities that break comparison with the 2026-08-25 checkpoints

**The station rebooted 2026-08-25 20:16**, during the AP re-architecture:
`boot_id ff3c110f…` → `1ce7f475…`. The continuous-uptime clock restarts there.
Association is 48,773 s (13.5 h) against an uptime of 57,341 s (15.9 h), so the
link also re-established about 2.4 h into the boot — consistent with the
profile bounce recorded that evening.

**A single RSSI sample does not establish degradation.** Two checkpoints four
minutes apart read **−55 dBm at VHT-MCS 4/1** and **−47 dBm at MCS 4/3**; the
2026-08-25 file reads `0` (saturated, when the board was on the bench) and the
notes record −44 one floor up. The reading moves ~8 dB between consecutive
samples, which is what a real path one floor up does, and it is not evidence of
a fault on its own. What is stable across all of it: `spi_errors 0`,
`spi_timedout 0`, `sta_tx_failed 0`, `dmesg_failures 0` across 1.50 GB and
4.96 M SPI messages, and 20/20 pings.

## 2026-08-26 — the HT-H7608 is an 863-870 MHz unit, and the HaLow segment is routable from the house LAN

### The H7608 is the wrong regional SKU

The label on the back of the HT-H7608 reads **`Region: 863~870MHz V2.0`**. Heltec
ship the HT-H7608 in two variants — **863-870 MHz** (1 MHz channels, 16 dBm) and
**902-928 MHz** (1-8 MHz, 28 dBm). This bench runs at **922.0 MHz**, which is in
the second variant's range and 52 MHz above the first's.

**This corrects an earlier conclusion in this file and in the project notes.** On
2026-08-24 its antenna was found to be marked 868 MHz and was swapped for a
900 MHz one, and that was written up as "a wrong-band antenna". The antenna was
not wrong — **it matched the unit**. The unit is the EU-band SKU.

**What the SKU does not explain.** The product page's "1 MHz only" is an SKU
specification, not a hardware lock: `morse_cli` on the box reports it operating at
`922000 kHz`, `Operating BW: 4 MHz`, and it moved **3.27 Mbit/s** uplink under
iperf with `tx failed 0` while it was working. An earlier claim here that it was
"specification-incompatible and could only do 1 MHz" was wrong and is withdrawn —
it was reasoning from a datasheet against a measurement that had not been taken
yet.

**What actually looks broken is separate.** Across one evening the same box, not
moved, went:

| | signal | rate | uplink |
|---|---|---|---|
| early | −61…−65 dBm | MCS7 tx / MCS1 rx | not measured |
| later | −73 dBm | MCS0 both | **30.3 Kbit/s**, second half 0 bytes, `tx failed 121` |
| later still | — | — | **would not associate at all**; the AP logged no attempt from it |
| after a reboot | −58 dBm | MCS7 tx / MCS3 rx | **3.27 Mbit/s**, `tx failed 0` |

**A front-end band mismatch is a fixed property — it would be consistently poor,
not intermittently perfect.** Something physical and intermittent is also wrong
(a loose SMA connector is the obvious candidate). The two problems are independent:
the SKU explains why it is slower than the other nodes even at its best; it does
not explain the flapping.

The AP's `expected throughput` for it read `14.648 Mbps` before any traffic and
`0.292 Mbps` after — that figure is a rate-control estimate, and it is worthless
until traffic has actually flowed. The same trap was recorded on 2026-08-24 with
the identical `0.292` value.

**Disposition:** its config was backed up (`sysupgrade -b`, 18,217 bytes, sha256
`850527…`, kept out of git — the archive contains `/etc/config/wireless` with
PSKs in plaintext), then it was factory reset with `firstboot`. It released its
DHCP lease and left the AP cleanly. It is no longer part of this bench. Note that
a reset **re-enables its DHCP server**, so its Ethernet must not go on the house
switch. None of the driver validation work depended on it.

### The HaLow segment is now reachable from the house LAN

Two changes, so any device on the house network can reach `10.41.0.0/16`:

- **On the AP**, a scoped forward rule — `src=wan dest=lan src_ip=192.168.108.0/24
  dest_ip=10.41.0.0/16 target=ACCEPT`, rather than opening wan→lan wholesale.
- **On the UniFi gateway**, a static route: `10.41.0.0/16` via `192.168.108.5`,
  device *Gateway*, metric 1. Putting it on the gateway rather than on each
  client means phones and laptops get it too.

**A gotcha worth keeping:** a `uci` firewall rule with no `proto` set produces
**tcp and udp only**. The first version of that rule passed SSH and blocked ping,
which is a confusing state to debug. `uci set …proto='all'` fixes it.

### Both nodes now default out over HaLow

`dkmstest` was changed to match the station: `ipv4.never-default no` and
`ipv4.route-metric 100` against the house Wi-Fi's 601. That also removed an
asymmetric path — traffic had been arriving over HaLow and leaving over Wi-Fi.

| | station `10.41.0.208` | `dkmstest` `10.41.0.216` |
|---|---|---|
| location | one floor up | beside the AP |
| HaLow signal | −44 dBm | −34 dBm |
| ping `1.1.1.1` | ~48 ms | 31.7 ms |
| association held | 43,202 s (12 h) | 41,604 s (11.6 h) before the profile bounce |
| SPI errors / timedout | 0 / 0 | 0 / 0 |

Both had held a single association for about twelve hours with zero SPI errors
before either was touched.

## 2026-08-25 (evening) — the AP became a router, and the HaLow segment got internet

The OpenMANET AP was a LAN appliance with no WAN: `br-lan` bridged `eth0`,
`wlh0` and `phy1-ap0` together on `10.41.0.0/16`, reachable only over a USB
Ethernet cable to the laptop. The HaLow segment was an island. That is now
changed, so that nodes behind a HaLow link can reach the internet.

```
                       UniFi 192.168.108.1 ──> internet
                               │
                  eth0 = WAN, static 192.168.108.5/24, NAT
                               │
                    ┌──────────┴──────────┐
                    │   AP (57:E7)        │
                    │   br-lan 10.41.254.1│  ← wlh0 + phy1-ap0 only
                    └──────────┬──────────┘
                         HaLow │ 922 MHz, 4 MHz
              ┌────────────────┼────────────────┐
        station .208       H7608 .197      hc01p .216
        one floor up
        default route via HaLow
```

**Reach the AP at `ssh root@192.168.108.5`.** `10.41.254.1` is now the HaLow-side
address only and is not reachable from the laptop. `br-lan` keeps serving DHCP to
the three HaLow nodes, so their addresses are unchanged.

The `wan` firewall zone is `input REJECT`, so two explicit rules carry all
management access and **must not be deleted**: `Allow-SSH-house` (tcp/22 from
`192.168.108.0/24`) and `Allow-Ping-mgmt`. NAT is the stock `masq='1'` on that
zone, which was already configured — nothing had to be added for it.

### The station now defaults out over HaLow, and that is the better path

`ipv4.never-default yes` had been set on the `halow` profile precisely because
the AP had no internet; with the AP routing, that setting became the only thing
in the way. It is now `no`, with `ipv4.route-metric 100` against the house
Wi-Fi's 601, so HaLow wins and Wi-Fi is the backup.

Measured from the station, one floor from the AP, both paths to `1.1.1.1`:

| out via | loss | avg | max | mdev |
|---|---|---|---|---|
| **HaLow** | 0% | **34.9 ms** | 40.4 ms | **4.8** |
| house Wi-Fi | 0% | 115.1 ms | 328 ms | 111.7 |

A real HTTPS fetch over HaLow returned `HTTP 200`, 47,826 bytes, in 2.4 s. The
house Wi-Fi on that board had degraded to **−84 dBm at 1.0 Mbit/s with 10% loss**
while HaLow sat at −49 dBm, so on that floor HaLow is not the fallback — it is
the good link.

### HaLow throughput at both ends of the range, 2026-08-26

Measured with `iperf` 2.1.8 between each station and the AP, so the data path is
one HaLow hop and nothing else. 10 s per direction, TCP.

| | `dkmstest` (A2, beside the AP) | station `55:04` (A1, one floor up) |
|---|---|---|
| signal | **−29 dBm** | −49 dBm |
| uplink, station → AP | **8.92 Mbit/s** | 3.56 Mbit/s |
| downlink, AP → station | **8.73 Mbit/s** | 5.34 Mbit/s |
| the AP's own `expected throughput` | 14.648 Mbps | 5.859 Mbps |
| measured against that estimate | −40% | −9% |

**One floor costs roughly half the throughput** — 60% of the uplink and 39% of
the downlink — for 20 dB of signal.

The near figures are close to the ceiling of this link: both directions land at
about the same place (8.9 up, 8.7 down) and the first five seconds of each run
are faster than the second five (10.9 → 8.8 and 13.2 → 8.8), which is TCP's
window still opening. Steady state is ~8.8 Mbit/s, symmetric.

The gap against the AP's own estimate is larger close in (−40%) than far out
(−9%). The estimate is a rate-control figure for the air interface; TCP, headers
and medium access take a bigger proportional bite when the air is fast.

Both were measured on the **DKMS-installed** module on `6.12.96+rpt-rpi-v8`, so
this is also a throughput data point for the packaged build: `SPI errors 0`,
`timedout 0` across 125,975 messages, `tx failed 0` at both ends, and neither
station's association dropped. `dkmstest` ended the run with 729 tx retries, the
highest of the three nodes — that is the node that just moved 25 MB, and with
`tx failed 0` it means every retry eventually succeeded.

The station one floor up shares the channel and was saturated for the ~20 s of
the test; it recovered immediately, back to 34.3 ms average with 1.8 ms mdev to
`1.1.1.1`.

### Two failed attempts, and the real cause

The first two attempts left the AP unreachable and were rolled back. Both
diagnoses along the way were wrong and are worth recording as such:

- **"the firewall rejects it"** — no. The pre-existing `Allow-Ping` rule accepts
  echo-request, and the nft counters showed **1 packet of 45** reaching the input
  chain at all. Packets were not being rejected; they were not arriving.
- **"reverse-path filtering"** — no. `rp_filter` is `0` on `all`, `default` and
  `eth0`.

The actual cause was an address-plan error. The transition address was
`10.41.0.254/16`, which is **inside br-lan's own `10.41.0.0/16`**:

```
10.41.0.0/16 dev br-lan  src 10.41.254.1
10.41.0.0/16 dev eth0    src 10.41.0.254     <- two routes, one subnet
```

The AP could not tell which interface reached `10.41.0.100`, and most replies
left via `br-lan` — over the air, in the wrong direction. Moving the transition
address to `10.42.0.254/24`, which overlaps nothing, made it work on the first
try. **Any second address on this box must avoid both `10.41.0.0/16` and
`192.168.108.0/24`.**

### What made this safe

Every attempt ran detached with a timed auto-rollback: copy `network` and
`firewall` aside, apply, and unless a confirm file appears within N minutes,
copy the backups back and `reload_config`. It fired twice, and it is the only
reason the AP never needed recovering by hand — it sits on a desk, but its
`eth0` was the only way in. Backups remain on the AP as
`/etc/config/{network,firewall}.bak3` and `.bak4`.

The HaLow side was never disturbed by any of it: across all three attempts the
station's association never dropped, and SPI `errors`/`timedout` stayed at 0.

### Not done

Devices *behind* a HaLow node still cannot get out — only the nodes themselves
can. That needs `hostapd` + DHCP + NAT on the station, or the HT-H7608, which
does exactly this in its own web UI and is the device the vendor diagram shows
in that role.

## 2026-08-25 — the HT-HC01P is ported to Raspberry Pi OS, and defect B reproduces on a second board

The Heltec HT-HC01P (MM6108**A2** on a Pi HAT, SPI) now runs **Raspberry Pi OS
bookworm 6.6.51 with morse_driver 2.0.1 plus this repo's three `patches/upstream/`
fixes**, associated to the OpenMANET AP with SAE + PMF, DHCP, and a link the AP
rates at MCS7. It is the **second independent hardware** on this stack — different
module, different silicon revision, different carrier, same kernel and same three
patches.

The port swapped SD cards. Heltec's OpenWrt install is untouched on its own card.

```
hc01p   Raspberry Pi 4B Rev 1.4, serial 100000004dd92ccc
        Raspberry Pi OS bookworm, kernel 6.6.51+rpt-rpi-v8
        wlan0 192.168.108.13 on Sun     wlan1 10.41.0.216/16 HaLow
        MAC 0c:bf:74:40:8e:91           SPI errors 0, timedout 0
```

### The experiment that was worth doing: defect B on a second board, in the vendor's own configuration

Before installing the working driver, 2.0.1 was built with **patch 1 only** — no
patch 2, no patch 3 — and probed once. It failed exactly as predicted:

```
Resetting Morse Chip / Done
morse_spi spi0.0: morse_spi_probe: failed to init SPI with CMD63 (ret:-71)
```

Then the same binary plus four `dev_info`/`print_hex_dump` calls, to see whether
it was the same *mechanism* and not merely the same error code:

```
init: entry mode=0x4 cs_high_default=1 train=18
init: CS deasserted for training, mode=0x4      <-- expected 0x0
init: CS polarity restored, mode=0x4
cmd63 rx: ff ff ff ff ff ff ff ff c0 3f ff ff ff ff ff ff
cmd63 rx: ff ff ff ff ff ff ff ff c0 7f ff ff ff ff ff ff
cmd63 rx: ff ff ff ff ff ff ff ff c0 7f ff ff ff ff ff ff
```

Field for field the same as the Wio-WM6108 trace already in `issue15-report.md`.
`cs_high_default=1` is the load-bearing one: the core has **already** set
`SPI_CS_HIGH` before the function runs, so the flip is a no-op in both directions
and the training burst goes out with the chip selected.

**What makes this run stronger than the first one:** the device tree here is
Heltec's, byte for byte — `spi-max-frequency` 50 MHz, `reset-gpios` flag 0,
one `cs-gpios`. That is the reference configuration in which defect 3 cannot
reproduce and the old `reset-gpios` story does not apply, so the failure can only
be defect B. On the SenseCAP M1 the overlay was 10 MHz with flag 1 and all three
defects were in play at once. The variable is isolated now.

Axes changed between the two reproductions: module (Wio-WM6108 / Heltec HT-HC01
V2), silicon (MM6108**A1** / **A2**), carrier (SenseCAP M1 mPCIe / Heltec Pi HAT),
chip-select count (two / one), device tree (this repo's / the vendor's). Not
changed at the time: the kernel, 6.6.51 in both — **and that limitation was removed
later the same day, see "The second kernel" below.**

Analysis document §7 said L1 would fall if unpatched 2.0.1 probed cleanly on this
HAT under 6.6. It did not. **L1 is measured, not reasoned.**

### A decode worth keeping: the chip answers correctly, the host frames it wrong

The three CMD63 attempts returned `c0 3f` once and `c0 7f` twice. A byte frame
taken two bits early gives `host_byte = last2(prev) ++ first6(cur)`:

```
prev=ff cur=01  ->  11 000000 = c0 ,  01 111111 = 7f     "c0 7f" is an aligned 01
prev=ff cur=00  ->  11 000000 = c0 ,  00 111111 = 3f     "c0 3f" is an aligned 00
```

Both are valid R1 bytes, and `00` is CMD63 *success*. The chip replied correctly
on the first attempt and the host could not see it. Combined with the SPI
controller reporting `errors 0 timedout 0` for the whole failed probe, this
answers the "surely your wiring is bad" reading directly: nothing is wrong
electrically, the byte grid is two bits off.

### B1 confirmed on a second machine, as a build failure

Before patch 1 was applied at all, pristine `mm6108-2.0.1` was built on this
board's 6.6.51:

```
spi.c:1519:2: error: #warning "SPI_CONTROLLER_ENABLE_CS_GPIOD macro not defined" [-Werror=cpp]
make: *** [Makefile:199: all] Error 2
```

No `morse.ko`. With patch 1 the same command builds with zero errors and zero
warnings. B1 is not a mainline-only footnote.

### With all three patches: probe, firmware, BCF, association

```
Loaded firmware from morse/mm6108.bin,   size 468304, crc32 0xbe7b5c8f
Loaded BCF from morse/bcf_HC01_V2_H.bin, size 1170,   crc32 0x389a48c4
SW version: 2.0.1    HW version: 0x00000406      <- MM6108A2, matches V2 exactly
```

Same machine, same day, same device tree, same firmware, same BCF. The only
variable between the failing and working runs is `spi.c`.

Association was clean on the first attempt — no `CONN_FAILED`, no backoff:

```
SME: Trying to authenticate with 3c:1a:cc:70:3f:ca
PMKSA-CACHE-ADDED / Associated with 3c:1a:cc:70:3f:ca
WPA: Key negotiation completed [PTK=CCMP GTK=CCMP]     pmf=2, BIP, sae_group=19, sae_h2e=1
dhcp4: new lease, address=10.41.0.216
```

`nmcli connection up` to `activated` in about 2.4 s.

### U1 is settled, and the RF-symmetry gate is what settled it

`bcf_HC01_V2_H.bin` — shipped for driver 1.15.3 — **works with firmware 2.0 and
driver 2.0.1**. The specific risk flagged in the analysis (its `.board_config`
sits at a fixed `0x8011fa80` while the driver places sections in a window sized by
*firmware* TLVs) did not materialise.

Only the AP-side check can establish that, because a wrong BCF passes every
earlier gate on the receive side. From the AP:

```
Station 0c:bf:74:40:8e:91   signal -1 dBm   rx packets 73   tx retries 0   tx failed 0
mmrc: MCS7 / 4 MHz / SGI, probability 100%, 49/49 attempts, 0 look-around packets
```

For scale, in the same dump at the same moment the HT-H7608 reads `tx retries 438
/ tx failed 32` and sits at MCS0 1–2 MHz with 137 of 181 packets spent on
look-around. That is what a marginal link looks like; this is not one.

`-1 dBm` is in the clipping region — the gate asks for a *sane* RSSI, not a
precise one, and the packet counts are what carry the argument.

Pings, 0% loss in every direction: Mac→station 4.5 ms, AP→station 5.4 ms,
station→AP 3.5 ms, station→station (to `10.41.0.208`) 9.3 ms.

### Persistence, and the power-save mechanism moved off the module parameter

Driver installed to `/lib/modules/6.6.51+rpt-rpi-v8/updates/`, `depmod -a`, and
`/etc/modprobe.d/morse.conf`:

```
options morse country=SG bcf=bcf_HC01_V2_H.bin macaddr_suffix=40:8e:91
```

**`enable_ps` is deliberately absent.** The driver itself logs *"enable_ps
modparam must only be used for testing - use iw set power_save"*, so power save is
disabled by the `halow` NetworkManager profile's `wifi.powersave=2` instead — the
same mechanism already proven persistent on the other three boards. After a
reboot:

```
enable_ps modparam : 2        <- the driver's own default, our override is gone
iw get power_save  : off      <- so this can only come from NetworkManager
NM profile         : disable
```

and behaviourally, not just by readback: **20/20 pings, avg 4.487 ms, mdev
0.163 ms**. A receiver that is asleep part of the time cannot produce 0.163 ms of
jitter. The same board under OpenWrt with power save on was 105.4 ms / mdev 66.2.

Unattended boot sequence:

```
t = 7.77 s  dot11ah registered
t = 8.45 s  morse registered, device tree read, Resetting Morse Chip
t = 8.60 s  firmware loaded
t = 8.61 s  BCF loaded
```

then NetworkManager associates and takes the lease with no intervention.
(Heltec's OpenWrt loaded its BCF at 6.65 s; the difference is systemd, not the
driver.)

### Three choices that improved on the plan

- **The NetworkManager profile is bound to the MAC, not to `interface-name`.**
  The HaLow interface name is not stable on this board — `brcmfmac` races it for
  `wlan0` — so the station board's `interface-name=wlan1` idiom is fragile here.
  Binding to `0C:BF:74:40:8E:91` removes the dependency entirely, which only works
  because of the next item.
- **`macaddr_suffix=40:8e:91` is required, and its absence is a trap.** Without it
  the driver invents a *random* MAC at every load — the first probe came up as
  `c2:d2:3d:87:dd:cd`. That churns the AP's station table and the DHCP lease on
  every boot. With it the module gets back its own `0c:bf:74:40:8e:91`, which is
  also why DHCP returned the same `10.41.0.216` the OpenWrt install had, and why
  the AP-side history from 2026-08-24 remains directly comparable.
- **`ipv4.never-default yes` was set from the start** rather than after the HaLow
  profile stole the default route, which is how the station board learned it.

### Gotchas found on the way, none of them about SPI

- **`morse_driver` has a git submodule.** `mmrc-submodule`
  (`MorseMicro/mm_rate_control`, commit `da14255`). Without
  `git submodule update --init --recursive` the build dies on
  `mmrc-submodule/src/core/mmrc.h: No such file or directory`, which looks
  alarming and has nothing to do with anything. The first clone attempt failed
  transiently; the repo is public.
- **`insmod` does not resolve dependencies.** Loading `morse.ko` by hand without
  `modprobe mac80211 crc7` first produces fifty lines of
  `Unknown symbol ieee80211_*`. Also looks like a defect and is not one.
- **`Country TW ... is not supported / staying in SG` at every boot is correct
  behaviour.** `cfg80211.ieee80211_regdom=TW` is on the kernel command line for
  the *brcmfmac* interface, and cfg80211 offers it to every phy. The Morse regdb
  has no `TW`, so the driver refuses and stays on `SG` — which is the setting we
  want, since SG's 920–925 MHz block is what matches the Taiwan NCC allocation.
  Noisy, not wrong.
- **The board booted from a 128 GB SDXC card.** NOTES has carried "a 128 GB SDXC
  card never booted the Pi" since the early days. That was a *SenseCAP M1*, and it
  may not even have been this card, so this is not a refutation — but the claim is
  no longer general and should not be repeated as one.
- **Check the board's timezone before reading its logs against another host's.**
  This one came up as `BST` while the AP and the laptop are on Taipei time, and a
  7-hour skew briefly made one reboot look like two. Now set to `Asia/Taipei`.

### The Ethernet backup path was broken in the way that is hardest to catch

The direct-cable fallback — laptop straight to the Pi's RJ45, no house network
involved — was configured at stage 1 and left untested, because testing it costs
the `en5` cable. Tested 2026-08-25, and it failed.

It was set up as `ipv4.method=auto` with a manual `10.42.0.2/24` and
`may-fail=yes`, on the assumption that NetworkManager would take a DHCP lease when
one was offered and fall back to the static address when none was. **It does not
work that way.** With `method=auto`, no lease means IPv4 configuration is
unavailable and the whole activation fails, and the manual address is irrelevant to
that decision:

```
device (eth0): state change: ip-config -> failed (reason 'ip-config-unavailable')
device (eth0): Activation: failed for connection 'eth0-bench'
dhcp4 (eth0): state changed no lease
device (eth0): Activation: starting connection 'eth0-bench'      <- loops, 4 times
```

**The dangerous part is that it works first.** The address *is* applied during the
`ip-config` phase, so for the first ~45 s the link pings at 0.6 ms and SSH works —
and then the DHCP attempt times out, the address is withdrawn and the path dies.
Four retries later NM gives up and the interface sits `disconnected` with no
address. A short "does it work" test passes; the path is useless when it is
actually needed. That is worse than having no backup path at all, because it gets
recorded as verified.

Fix: `ipv4.method=manual`. There is no DHCP attempt, so there is nothing to fail.
Verified afterwards on all three levels rather than by ping alone — NM reports
`connected` with **0 failed activations**, 180/180 pings at 0.640 ms avg and
0.863 ms max over three minutes (four times the window that killed the old one),
and after a reboot `eth0`, `sun` and `halow` all come up unattended.

The cost, stated because it is a real trade: this interface will not take a lease
if it is ever plugged into a real network. For an emergency path whose whole point
is to work when nothing else does, determinism is the right choice; if DHCP is ever
wanted, add a *second* higher-priority profile and let NM fall through rather than
changing this one.

**A measurement discarded rather than explained away.** The first three-minute
ping after the fix read 8.3% loss with a 3517 ms maximum, which looks like the fix
did not work. That window overlapped a reboot — ~15 lost packets against ~20 s of
downtime. It is confounded and proves nothing in either direction, so it was thrown
out and re-run clean rather than reasoned about. Eleventh instance of the theme in
[[feedback-verify-instruments]], and the first where the faulty instrument was
something built here.

### The second kernel: 6.12.96, and what it removes from the caveat

**The one honest weakness in the above — "one kernel, two hardwares" — is gone.**
The board was upgraded to **6.12.96+rpt-rpi-v8** and everything was re-run.

| | 6.6.51 | 6.12.96 |
|---|---|---|
| pristine `mm6108-2.0.1` builds | ❌ `spi.c:1519 #warning … [-Werror=cpp]` | ❌ **same line, same error** |
| with patches 1+2+3 | ✅ 0 errors, 0 warnings | ✅ **0 errors, 0 warnings** |
| probe / SAE / DHCP | ✅ | ✅ |
| SPI `errors` / `timedout` | 0 / 0 | 0 / 0 |

The driver source is identical across both — `srcversion 87374779AA811C291578351`
in both builds — so the only variable between the two columns is the kernel.

**A claim that was previously inference is now a direct check.** The macro the
whole of defect 1 turns on is absent from *both* kernels' headers:

```
SPI_CONTROLLER_ENABLE_CS_GPIOD  occurrences in include/linux/spi/spi.h
  6.6.51  : 0
  6.12.96 : 0
```

So `SPI_CONTROLLER_ENABLE_CS_GPIOD` is confirmed as a Morse vendor-kernel addition
by counting it in two Raspberry Pi OS kernels, not by reasoning about it. B1 is not
a single-kernel accident.

**Separately settled: 2.0.1 has no API breakage on 6.12.** That was genuinely
unknown — the station board's earlier 6.12.93 test ran the *unpatched* driver and
only established that it fails the same way. The patched driver compiles clean and
runs.

On 6.12 the unattended boot reaches `Loaded BCF` at **t = 5.28 s** and association
completes by t ≈ 8 s, first attempt, no `CONN_FAILED`. The AP reads the station at
`-1 dBm` with `rx packets` climbing, `tx retries 0 / tx failed 0`, and mmrc holding
**MCS7 / 4 MHz at 100% over 50/50** with zero look-around packets. 20/20 pings at
mdev 0.21 ms.

**How the upgrade was done, because the ordering matters.** `apt upgrade` first
(199 packages, kernel automatically held back because a kernel bump needs a *new*
package) to separate userspace changes from the kernel change; that alone survived
a reboot with the module untouched. Then `apt full-upgrade` with **`rpi-eeprom`
held** — the bootloader has nothing to do with this experiment and holding it keeps
the variable single. Before rebooting, the running `kernel8.img` and `initramfs8`
were copied to `kernel8-6.6.51.img` / `initramfs8-6.6.51` **on the FAT boot
partition**, which is readable from the laptop, so a kernel that would not boot is
recoverable by adding two lines to `config.txt` from another machine. Nothing was
removed: both `linux-image` packages and both `/lib/modules` trees remain, and the
driver is installed under `updates/` for both kernels.

One thing worth not repeating: the build logs were written to `/tmp`, which the
reboot cleared, so the evidence had to be regenerated. Build logs now live in
`~/halow-test/buildlogs/` on the board.

**The station board `55:04` stays on 6.6.51 deliberately**, so the "same kernel,
two hardwares" pairing still exists as well. Both comparisons are now available.

### Evidence

`logs/2026-08-25-hc01p-rpios-stage{2-devicetree,3a-defectB-reproduced,3a-defectB-mechanism,3b-driver-up,4a-station-associated,4b-persistent}.txt`
and `logs/2026-08-25-hc01p-rpios-kernel-6.12-second-kernel.txt`.
Overlay: `overlays/mm610x-spi-hc01p.dts`. First-boot payload and the
instrumentation diff: `port/hc01p/`.

## 2026-08-24, night — the HT-H7608's HaLow interface is in no firewall zone

Reached over its Ethernet port for the first time since it was set up, by moving
`en5` to it and adding `10.42.0.100/24`. My SSH key is not on this board; password
auth via `expect` was used as `root` with the vendor default password (kept out of
this file; it is Heltec's documented default). Nothing about the radio was
changed; the one write is the firewall zone described below.

### The record said its IP layer never answers, "and that is normal". It is not normal

It is a configuration gap, and this is what it looks like:

```
wlan0   UP   10.41.0.197/16        <- the address is there, the interface is up

nft, chain input:
        type filter hook input priority filter; policy drop;
        iifname "br-lan" jump input_lan          <- the only accept path

firewall.@zone[0] name=lan  network=lan       input=ACCEPT
firewall.@zone[1] name=wan  network=wan wan6  input=REJECT

`halow` appearing in any zone: 0 matches
rules mentioning wlan0 in the input chain: 0
```

`network.halow` is in neither zone, so inbound traffic on `wlan0` falls through to
`policy drop`. That accounts for every observation: ARP works (layer 2, never
reaches the input chain), the DHCP client works (outbound), and ICMP **and every
TCP port** are dropped in silence. Verified with TCP, not only with ping — 22, 23,
80, 443, 7681 and 8080 all fail from the AP, which is on the same L2.

So "use its RSSI and association events, never its ping" stays good advice, but the
reason changes: it is not that the board has no working IP stack, it is that nobody
put its HaLow network in a zone.

**Fixed, but not yet proven end to end.** A dedicated zone was added rather than
putting `halow` into `lan`, because `input=ACCEPT` there would expose this board's
**unauthenticated ttyd** (below), LuCI and dnsmasq to the whole HaLow segment:

```sh
# zone: name=halow network=halow input=REJECT output=ACCEPT forward=REJECT
# rule: Allow-Ping-halow  src=halow proto=icmp icmp_type=echo-request
# rule: Allow-SSH-halow   src=halow proto=tcp  dest_port=22
```

which produces

```
iifname "wlan0" jump input_halow
chain input_halow {
        icmp type echo-request counter accept   # Allow-Ping-halow
        tcp dport 22           counter accept   # Allow-SSH-halow
        jump reject_from_halow
}
```

Original saved at `/etc/config/firewall.pre-halowzone-20260824`. To widen it to
full access later: `uci set firewall.@zone[2].input='ACCEPT'`.

**Proven end to end later the same night**, once the link was repaired (below):

```
iifname "wlan0" jump input_halow
        icmp type echo-request counter packets 1 accept
        tcp dport 22           counter packets 1 accept
station -> 10.41.0.197 : TCP22-OPEN
```

The ICMP counter reads 1 rather than 20 because fw4's input chain accepts
`ct state established` before reaching the zone chain — the first packet of the
flow hits the rule and the rest take the fast path. The TCP counter moving off
zero is the decisive part: before the fix a SYN never reached the board at all.

### The link has degraded badly, and the timing points at the cable

```
TX Total 75880   TX ACK valid 26547 (35%)   TX ACK timeout 41237 (54%)
RX total 501823  RX pass FCS 501224         RX signal field error 50642 (10%)
signal −69 to −76 dBm
```

Over half of what it transmits gets no ACK. For scale, on the same AP at the same
moment: the station reads 0 dBm and the HT-HC01P −14 to −22 dBm.

The failure signature is identical to the HT-HC01P's this morning — `SME: Trying to
authenticate … send auth (try 1/3, 2/3, 3/3) … timed out`, `CONN_FAILED`,
`TEMP-DISABLED` backing off 10 → 20 → 30 s — but **this is not a BCF problem**: this
board already runs `bcf_HC01_V2_H.bin`. Twelve sampling points over three minutes
found `COMPLETED` zero times.

What made the cable look like the suspect was the sequence: it held **44522 s** —
more than twelve hours unbroken — and then went 2001 s → 189 s → 10 s → nothing,
starting when the Ethernet cable was connected. That was the wrong suspect.

### The antenna was for the wrong band, and that was the whole thing

> **Superseded 2026-08-26 — read that heading as wrong.** The antenna was not
> "for the wrong band"; it was the antenna that came with the unit, and the
> **unit itself is the 863-870 MHz SKU**, per the label on its back:
> `Region: 863~870MHz V2.0`. Swapping to a 900 MHz antenna did help, which is why
> this section concluded what it did — but the conclusion "the antenna was the
> whole thing" was wrong, and the box was never right for this bench. See
> 2026-08-26 at the top of this file.

**It is marked 868 MHz.** That is the EU SRD band. This link runs at 922 MHz, which
is where Taiwan's NCC allocation sits — 920–925 MHz — and the driver has **no `TW`
regdomain at all** (53 country codes in `/usr/share/morse-regdb/channels.csv`, `TW`
is not among them), which is why everything here runs `country=SG`: SG's
920–925 MHz / 4 MHz / 22 dBm block fits the Taiwan allocation exactly. Note that the
same SG table *also* carries an 866–868 MHz group at 2.77% duty cycle — the band
that antenna was designed for, and one Taiwan does not allocate for this.

54 MHz away, 6.2%, on an antenna type whose usable bandwidth is typically 2–5%.

Swapping it, with the board also repositioned in the same step:

| | 868 MHz antenna | after swap | after repositioning | power save off |
|---|---|---|---|---|
| its view of the AP | −85 dBm | −69 dBm | −69 dBm | — |
| AP's view of it | −75 (avg −71) | −75 (avg −71) | −69 (avg −62) | **−64 (avg −64)** |
| `wpa_state` | SCANNING, 0 of 12 samples | **COMPLETED** | COMPLETED | COMPLETED |
| `RX total` | 34 in 553 s | 276 in 124 s | — | — |
| `RX signal field error` | **4410** | **10** | **+0 per 45 s** | — |
| `TX ACK valid` | 1 of 790 | 51 of 173 | — | — |
| tx bitrate | — | 6.5 Mbit/s MCS0 | 260 Mbit/s MCS5 | **325 Mbit/s MCS7** |
| expected throughput | — | 0.292 Mbps | 11.718 Mbps | **14.648 Mbps** |
| ping from the station | never answered | 1/20, 241 ms | 27/30, avg 383 ms | **30/30, avg 10.3 ms** |

The signal-field-error column is the one that settles it: 4410 undecodable
detections against 34 decoded frames, then 10, then none at all. A receiver that
cannot decode is what an antenna 54 MHz off resonance produces.

**Caveat, stated because it matters:** the antenna swap and the repositioning
happened in the same power-down, so their individual contributions cannot be
separated from these numbers. Both were changed for the better; which mattered more
is not established.

### A correction to what was written this morning about the 1 MHz parking

Earlier tonight the board sat at `921500 kHz, 1 MHz` in **all three** of
`morse_cli channel -a`'s blocks — Full, DTIM and Current — and never adopted the
AP's 4 MHz. That looked like a worse form of the idle-parking defect recorded this
morning for the HT-HC01P. **It was not a defect at all.** The moment the antenna was
changed, the same board came up at `922000 kHz, 4 MHz, primary 2 MHz` without any
intervention.

So parking at 1 MHz is a **symptom, not a cause**: a station that cannot decode the
AP's beacons has nothing to derive the operating parameters from, so it stays at the
default. The HT-HC01P entry stands as written — there the radio *did* switch during
authentication — but the general claim "the driver never switches" would have been
wrong.

### Power save is worth 13× on this board too

Measured after the link was healthy, so the two effects are separated:

```
power save on    30/30, 0% loss, RTT min 34.7 / avg 133.5 / max 224.7 ms, mdev 59.7
power save off   30/30, 0% loss, RTT min  7.7 / avg  10.3 / max  21.1 ms, mdev  3.5
```

Average latency 133.5 → 10.3 ms, jitter 59.7 → 3.5. Not the black hole the station
showed with its own power save on, but the same direction. `iw dev wlan0 set
power_save off` is **runtime only** and does not survive a reboot or `wifi reload`.

### The persistent setting on OpenWrt, and why it is not `enable_ps`

Checked in `morse.sh` rather than assumed, because the `channel` option turned out
to be inert earlier the same day. **These are two independent mechanisms and only
one of them is the right lever.**

`powersave` is a per-interface uci option, registered at line 213
(`config_add_boolean wds powersave enable`) and applied inside
`morse_iface_bringup()`'s **`sta)` branch**:

```sh
# lines 653-663
if grep -i '325b' /sys/kernel/debug/usb/devices ; then
        set_default powersave 0     # Morse USB MM8108 workaround, APP-3745
else
        set_default powersave 1     # <- this default is where "power save on" comes from
fi
[ "$powersave" -gt 0 ] && powersave="on" || powersave="off"
iw dev "$ifname" set power_save "$powersave"
```

So the default that has been costing an order of magnitude on every board is that
`set_default powersave 1`, not the driver's `enable_ps`. It runs on every interface
bring-up — boot, `wifi reload`, reconnect — which is exactly what persistence needs.
Unlike `channel`, which `morse_setup_sta()` never applies, this one has a real call
in the STA path.

`enable_ps` is a different thing: a module parameter listed in `MM_MOD_BOOL`
(line 17). It is settable from uci in principle, but it takes 0/1 while the live
value is **2** — the driver's own default, not something uci set — and changing it
means reloading the module. Morse themselves only reach for it as a USB workaround
(line 145, `#APP-4066`, `MOD_PARAMS="$MOD_PARAMS enable_ps=0"`). Leave it alone.

Applied and verified on both Heltec boards:

```sh
uci set wireless.default_radio1.powersave='0'   # HT-H7608  (Morse is radio1 there)
uci set wireless.default_radio0.powersave='0'   # HT-HC01P  (Morse is radio0 there)
uci commit wireless && wifi reload
```

The radio index is **not** the same on the two boards — check `uci show wireless`
for the `mode='sta'` iface rather than copying the line.

| board | mechanism | power save on | power save off |
|---|---|---|---|
| station `55:04` (RPi OS) | NetworkManager `wifi.powersave 2` | **100% inbound loss** | 30/30, avg 4.8 ms |
| HT-HC01P (OpenWrt) | uci `default_radio0.powersave 0` | 20/20, avg 105.4 ms, mdev 66.2 | 20/20, avg **8.4 ms**, mdev 2.7 |
| HT-H7608 (OpenWrt) | uci `default_radio1.powersave 0` | 30/30, avg 133.5 ms, mdev 59.7 | 30/30, avg **10.3 ms**, mdev 3.5 |

Three hosts, three different configuration systems, one root cause. The station's
case is the severe one — there it is not latency, it is unreachability.

**How persistence was proven, not assumed:** `wifi reload` tears the vif down and
rebuilds it, so any runtime `iw set power_save off` is wiped. Reading `off` *after*
a reload, when the script's own default is `1`, can only come from uci. Backups at
`/etc/config/wireless.pre-powersave-20260824` on both boards.

**And then across a full reboot, on all three boards.** A `wifi reload` is not a
boot, so each claim was retested the hard way, cheapest and safest board first:

| board | rebooted via | after boot | link |
|---|---|---|---|
| station `55:04` | `systemctl reboot` | `power_save off`, `wifi.powersave disable`, `never-default yes`, default route only via `wlan0` | up at 20 s, 0 dBm, MCS7, 20/20 at 5.8 ms |
| HT-HC01P | `reboot` | `power_save off`, `uci powersave 0`, `COMPLETED` | 10.41.0.216 back, MCS7, 4.9 ms |
| HT-H7608 | `reboot` | `power_save off`, `uci powersave 0`, **`fw4` input chain carries the `wlan0` jump and both `input_halow` accept rules** | 10.41.0.197 back, −67 dBm, MCS7, 10/10 at 8.5 ms from two sources |

The HT-H7608 is the one that mattered. Its Ethernet had already been moved back to
the AP, so **HaLow was its only path in** — the whole reboot, and every check above,
went over the link the `halow` zone exists to permit. It also answers a question
left open when the zone was added: after a `wifi reload` the input chain briefly had
no `wlan0` rule, which looked like the zone might not survive. It does — fw4 binds
the zone when the interface comes up, at boot as well as at reload.

A by-product: that board's rate control had been sitting at MCS1 / 0.585 Mbps after
the cable was unplugged, and came back at **MCS7 / 14.648 Mbps** after the reboot.
MMRC needs successful transmissions to climb and ping traffic is too thin to feed
it; the reboot simply reset the estimate. Worth knowing before reading a low MCS as
a fault.

And a fourth sighting of the interface-name instability in one day: the HT-HC01P
came up `wlan1` and the HT-H7608 `wlan0`, the opposite of the boot before. Read the
name, never assume it.

A by-product worth noting: the HT-HC01P's HaLow interface came back as **`wlan0`**
after this reload, having been `wlan1` before it — the same instability recorded
this morning. Read the name from `ls /var/run/wpa_supplicant_s1g/`, never assume it.

### Hardware and OS, confirmed live

```
OpenWrt 23.05.5, 2.8.5-20251023, kernel 5.15.167, mips
radio0  mac80211  platform/10300000.wmac                    2.4 GHz AP HT-H7608-DD05, ch1 HT20, psk2
radio1  morse     platform/10130000.mmc/mmc_host/mmc0/...   SDIO
        bcf=bcf_HC01_V2_H.bin  country=SG  channel=42  mode=sta  encryption=sae  max_inactivity=30
br-lan  10.42.0.1/24, ports eth0.1, switch0 vlan1 ports "0 2 6t"
network.halow  proto=dhcp, device wlan0     network.wan proto=dhcp (unused)
open ports  22 dropbear / 80 / 443 LuCI / 53 dnsmasq / 7681 ttyd
```

`radio1.channel='42'` is inert for the same reason it is on the HT-HC01P —
`morse_setup_sta()` never calls `morse_cli channel`.

**It uses the same BCF file as the HT-HC01P**, `bcf_HC01_V2_H.bin`. Both carry the
HT-HC01 V2 module; one is SDIO and one is SPI. So the copy preserved in
`firmware/heltec-hc01p/` covers both boards.

### `ttyd` with no authentication is on both Heltec boards, not one

```
http://10.42.0.1:7681/token  ->  {"token": ""}   HTTP 200
```

This was recorded as an HT-HC01P problem. It is not — the HT-H7608 ships the same
unauthenticated web root shell, and additionally exposes 80, 443 and 53. On both
boards it is bridged with the Ethernet port and the board's own AP.

**Decision, 2026-08-24: leave `ttyd` as shipped, and stop carrying this as an open
item.** It is Heltec's factory default on both boards, not a misconfiguration
anyone here introduced, and these boards sit on an isolated bench segment rather
than a routed or shared network. Revisit only if one is ever put on a shared
switch or given a route off the bench — the same condition that already applies to
their DHCP servers.

One thing that is *not* left open, because today's firewall work happens to cover
it: **the HT-H7608's `ttyd` is not reachable from the HaLow segment.** The `halow`
zone added above is `input REJECT` with only ICMP and TCP 22 allowed, so 7681, 80,
443 and 53 remain confined to `br-lan` — its Ethernet port and its own 2.4 GHz AP,
exactly as before the board was cabled. The HT-HC01P is different: its HaLow
network sits in a zone that accepts input, which is why it can be reached over
HaLow at all, so its `ttyd` is very likely exposed there. Not checked, because the
decision above makes it moot.

## 2026-08-24, evening — station power save is an inbound black hole, not a 5% loss

The open item read: *"The station/AP power-save mismatch (`enable_ps=2` against the
AP's 0) as a contributor to the old 5% ping loss — never tested."* Now tested, and
the answer is bigger than the question.

The station rebooted on its own at 16:13 and came back with NetworkManager's
default power save on — precisely the state this file warned about when the
range-test logger was removed, since nothing re-asserts `power_save off` any more.
In that state:

| direction | power save ON | power save OFF |
|---|---|---|
| AP → station `10.41.0.208` | **0/5, 100% loss** | 30/30, 3.8–16.0 ms |
| laptop → station | **0/5, 100% loss** | 10/10, 4.4–9.1 ms |
| station → AP | 2/3, 33% loss, 54–160 ms | 10/10, 2.8–7.8 ms |

Two independent sources on the same L2, a valid ARP entry on the AP,
`icmp_echo_ignore_all=0`, `rp_filter=0`, no firewall rules — and not one inbound
packet got through. This is not a contributor to a 5% loss: **with power save on
the station is unreachable from the network side entirely**, while still able to
talk outbound.

**Unexplained, and recorded rather than smoothed over.** The HT-HC01P has the same
`iw power_save on` and the same `enable_ps=2`, and behaves differently — 30/30 with
no loss at 22.5–232.9 ms, twenty-five times the latency but no black hole. Same
driver family, same module, same AP, different failure mode. Do not generalise
either result to the other board.

**Fixed persistently on the station.** `iw dev wlan1 set power_save off` is a
runtime setting that NetworkManager undoes at the next reconnect, which is exactly
how this recurred:

```sh
nmcli connection modify halow wifi.powersave 2        # 2 = disable
nmcli connection modify halow ipv4.never-default yes
nmcli connection up halow
```

The second line fixes a separate problem found at the same time. After the reboot
the station's default route was `via 10.41.254.1 dev wlan1 metric 600`, ahead of
Sun at 601, so the board's internet traffic was going to an AP that has no
internet. With `never-default` the HaLow profile stops installing a default route;
`ip route get 1.1.1.1` now returns `via 192.168.108.1 dev wlan0`.

Verified after reactivation: 20/20 AP → station at 5.1 ms average, 10/10 in both
other directions, all four nodes reachable at once.

## 2026-08-24, later — the HT-HC01P associates, and its BCF was Morse's evaluation board

**Solved.** The board had been running `bcf_mf08551.bin`, which
`/lib/wifi/morse.sh:135` maps to `morse,ekh01-03` / `morse,ekh03v3` — **Morse's
EKH01-03 evaluation board**. This board reports `board_name`
`Heltec,Pi4-HT-HC01P-64bit`, and that case statement contains **no Heltec entry
at all**; its `*)` default sets a BCF only when the device path contains `usb`,
so an SPI board falls straight through and nothing ever corrects the value. It is
hardcoded in the shipped image, in both `/etc/config/wireless` and
`/etc/modules.d/morse`. Heltec's own `bcf_HC01_V2_H.bin` ships in
`/lib/firmware/morse/` and was never used.

```sh
uci set wireless.radio0.bcf='bcf_HC01_V2_H.bin'
uci commit wireless && wifi
```

Associated **within five seconds**, on the first authentication attempt, with
SAE, PMF, a 4-way handshake and DHCP:

```
send auth to 3c:1a:cc:70:3f:ca (try 1/3)
wlan0: authenticated
RX AssocResp from 3c:1a:cc:70:3f:ca (capab=0x11 status=0 aid=3)
WPA: Key negotiation completed with 3c:1a:cc:70:3f:ca [PTK=CCMP GTK=CCMP]
CTRL-EVENT-CONNECTED
DHCPACK(br-lan) 10.41.0.216 0c:bf:74:40:8e:91 HT-HC01P-8E91
```

The AP reads it at **−5 dBm** where it had been receiving nothing at all, and the
IP layer works in both directions including station-to-station to `10.41.0.208`.
Unlike the HT-H7608, this board is not a radio-layer-only control. Original
configuration saved at `/etc/config/wireless.pre-bcf-20260824`; the new BCF is
1170 B / crc32 `0x389a48c4` against the old 1150 B / `0xf1cf6f9f`.

**This is a sixth implementation shipping Morse's reference-board
configuration**, and the same story as the 50 MHz clock and the flag-0 reset line
below — except that here the inherited file cost the module its transmitter
outright. Inheriting the reference is not always invisible.

### And the vendor's download page serves the broken file too

Found 2026-08-24, after the fix. Heltec publish a BCF for this product at
<https://resource.heltec.cn/download/HT-HC01P/BCF/driver_1_15_3/bcf_HC0P.bin>.
It is **byte-identical to `bcf_mf08551.bin`** — the evaluation-board file that had
just been established as the cause:

```
Heltec download   bcf_HC0P.bin        1150 B  sha256 57c50cb2…  Last-Modified 2025-06-10
in-image default  bcf_mf08551.bin     1150 B  sha256 57c50cb2…  (identical)
the working one   bcf_HC01_V2_H.bin   1170 B  sha256 5744fa28…  in-image only
```

The files identify themselves, so this is not an inference from the hash alone:

```
bcf_HC0P.bin        .board_desc = "mf08551"     .build_ver = "a49f6ff 17ee8d5"
bcf_HC01_V2_H.bin   .board_desc = "HC01_V2_H"   .build_ver = "a49f6ff 17ee8d5 _Modified"
```

`mf08551` is Morse's EKH01-03 evaluation board. Renaming it `bcf_HC0P.bin` and
filing it under `HT-HC01P/BCF/` does not change what it is. It is also **not
newer** than the shipped image — 2025-06-10 against 2025-06-23 — which is the
first thing worth checking when a vendor page looks like an upgrade.

So the reference-configuration story is one step worse than "the image ships the
wrong default": **the vendor's published route to obtaining a BCF for this product
hands out the same wrong file**, and the working one exists only inside images
already in the field. That is why `firmware/heltec-hc01p/` in this repo carries the
binary rather than a link.

### The symptom was a one-way link, and paired windows were needed to see it

With the wrong BCF the station received perfectly and transmitted into a void.
Three paired 40 s control/test windows, the supplicant gated with
`disable_network 0` so the control was genuinely silent:

| window | HC01P `TX Total` | HC01P `TX ACK valid` | AP `RX total` | AP `RX pass FCS` | AP `RX sig field err` |
|---|---|---|---|---|---|
| control 1 | +0 | 0 | +53 | +52 | +12 |
| test 1 | +114 | **0** | +26 | +26 | +9 |
| control 2 | +0 | 0 | +24 | +24 | +3 |
| test 2 | +114 | **0** | +43 | +42 | +24 |
| control 3 | +0 | 0 | +25 | +25 | +9 |
| test 3 | +113 | **0** | +32 | +32 | +6 |

`DCF granted` tracked `TX Total` and `TX Revoked` was 2 per window, so the frames
really were being transmitted and the MAC was not blocked. Not one ACK ever came
back, and the AP's receive counters do not separate test from control at all.

**One window would have given the wrong answer.** The first single measurement
looked like the AP was seeing the frames and failing to decode them — signal
field errors +4 in control against +12 in test. Three paired rounds destroyed
that: 12 / 3 / 9 against 9 / 24 / 6, fully overlapping. Tenth instance of the
same trap in this file.

### Four things that were wrong on the way

- **"It never attempts authentication."** It always did, every 10–60 s:
  `SME: Trying to authenticate … send auth (try 1/3, 2/3, 3/3) … authentication
  timed out`, then `CONN_FAILED` and `CTRL-EVENT-SSID-TEMP-DISABLED` backing off
  10 → 20 → 30 s. hostapd logged nothing from its MAC because the frames never
  arrived, not because none were sent. The claim in the previous open list came
  from only ever looking at the AP side.
- **"1.15.3 cannot parse the RSN element."** Corrected in the `rsn_beacon_mode`
  section below. The HT-H7608 runs the same 1.15.3 and sat associated to this AP
  with `auth_alg=sae` throughout this session.
- **"The channel is wrong."** It was not. `morse_cli`'s `Primary Channel Index`
  counts **1 MHz slots inside the operating channel** — 920.5 / 921.5 / 922.5 /
  923.5 within the 4 MHz centred on 922.0 — so index 1 is 921.5, s1g channel 39.
  The beacon's HT Operation element advertises mapped 5 GHz channel 153, the same
  921.5 in the SG table, and the station authenticating on `chan=39` was right.
- **"uci `channel` and `s1g_chanbw` constrain a station's scan."** They do not.
  `morse_setup_sta()` never calls `morse_cli channel`; only the AP, mesh, adhoc
  and monitor paths do. The HT-H7608's `channel=42` was never applied either.

### A separate real defect: the radio idles at 1 MHz against a 2 MHz primary

While not authenticating, the driver parks the radio at **1 MHz on 921.5** even
though the AP's primary bandwidth is 2 MHz. In that state it detects the AP and
cannot decode it:

| 30 s window | `RX total` | `RX pass FCS` | `RX signal field error` |
|---|---|---|---|
| parked at 1 MHz / 921.5 | **+0** | +0 | **+199** |
| after mirroring the AP | **+289** | +289 | **+3** |

199 undecodable detections in 30 s is 6.6/s against the AP's 9.8 beacons/s; 289
decoded is 9.6/s, the beacon rate. The mirror was

```sh
morse_cli -i wlan0 channel -c 922000 -o 4 -p 2 -n 1
```

The supplicant overwrites it the moment it authenticates — which it does
correctly, at 922.0 and 4 MHz — so this never blocked association. It is why
`scan_results` kept coming back empty at random, and why an externally triggered
`iw dev wlan0 scan` would fill the cache when the supplicant's own scan appeared
to have found nothing.

### The HaLow interface name is not stable across boots

A reboot to confirm the BCF persists produced this, which reads exactly like a
dead radio:

```
$ iw dev wlan0 link
Device "wlan0" does not exist.
```

while the AP simultaneously reported that same MAC associated with 194 seconds of
connected time. The HaLow netdev had come up as **`wlan1`** that boot —
`brcmfmac … phy1-ap0: renamed from wlan0` — because the Broadcom 5 GHz interface
won the race for `wlan0`. The supplicant control socket moves with it. Read the
name, never assume it:

```sh
ls /var/run/wpa_supplicant_s1g/
```

### The BCF survives a reboot

`uci commit` rewrites `/etc/modules.d/morse` as well, so kmodloader loads the
right file on its first attempt: `Loaded BCF from morse/bcf_HC01_V2_H.bin` at
**t = 6.65 s**, associated at **t = 11.9 s**, `10.41.0.216` back, −9 dBm, 4 MHz,
0% loss in all three directions. The boot before the fix had loaded
`bcf_default.bin` at 6.64 s and only reached `bcf_mf08551.bin` eleven minutes
later, so that path is gone too.

### Where everything is now

`en5` is cabled to the HT-HC01P with the Mac side at `10.42.0.100/24`. **The
one-cable-at-a-time constraint is over** — the HC01P now has a HaLow address, so
with `en5` back on the AP all four nodes are reachable at once. Remove the alias
first; macOS gave it a `/8` netmask, which would otherwise swallow
`10.41.0.0/16`:

```sh
sudo ifconfig en5 -alias 10.42.0.100
```

Fourth node as it now stands: **HT-HC01P**, `10.42.0.1` on `br-lan`, HaLow
`10.41.0.216`, driver 1.15.3, `bcf_HC01_V2_H.bin`, **MM6108A2** silicon,
associated to `BCM2711-57e7` with SAE and PMF. Its `boardtype` and
`country_code` OTP banks are both unset, so the chip cannot select its own BCF.

Still open, in order:

1. ~~**`ttyd` has no authentication**~~ — **closed as a decision, not a fix,
   2026-08-24.** It is the vendor default on both Heltec boards and they are on an
   isolated bench segment; see the section above. Reopen if either board is put on
   a shared switch or routed network.
2. **Does the AP stall recur now that `openmanetd` is gone?** Unchanged — worth
   simply watching; recovery is `echo 1 > $P/reset`.
3. **Power save on the HT-HC01P.** Settled for the station (section above:
   `wifi.powersave 2` on the `halow` profile), but the HC01P still runs with it on
   and pays 22.5–232.9 ms against the station's 3.8–16.0 ms. Why it degrades to
   latency there and to a total inbound black hole on the station is unexplained.
   Force power save off before measuring anything on it.
4. **Real range.** Unchanged: −41 dBm one floor up with ~50 dB of headroom.

## 2026-08-24, session close — where everything is now

Verified live at the end of the session, not recalled.

**Station `E4:5F:01:52:55:04`** (serial `100000004851d437`, RPi OS bookworm 6.6.51)

```
wlan0  192.168.108.19/24 on SSID `Sun`     wlan1  10.41.0.208/16, MTU 1500
driver srcversion 87374779AA811C291578351  (mm6108-2.0.1 + patches/upstream/)
DT spi-max-frequency  02 fa f0 80 = 50,000,000     spi_clock_speed param 0
modprobe.d/morse.conf: options morse country=SG bcf=bcf_fgh100mhaamd.bin
spi errors 0  timedout 0        associated to 3c:1a:cc:70:3f:ca
NM autoconnect priority: sun 20, preconfigured (Unifi) 10, halow 0
```

The `halow-rssilog.service` installed for the range test **has been removed** —
unit and script deleted, nothing left polling the radio. Its output is kept on
the board at `/home/alan/rssi-logs/` (5 files, 13776 lines) and backed up off it.
Note the consequence: **nothing re-asserts `power_save off` any more**, so
NetworkManager may turn it back on at the next reconnect. Force it off before any
future RSSI or loss measurement — the recipe is in the 2026-08-23 range-test log.

**AP `E4:5F:01:52:57:E7`** (serial `1000000093d173dd`, OpenMANET 24.10 / 6.6.138)

```
br-lan 10.41.254.1/16      MTUs eth0 1500, br-lan 1500, wlh0 1500
radio: 922.0 MHz, 4 MHz operating, 2 MHz primary   (uci channel=40 s1g_chanbw=4)
rsn_beacon_mode=2          2 stations associated
openmanetd / alfred / mesh11sd: all boot-disabled
```

`eth0` at 1500 is currently a hand-set value, but `openmanetd` — the thing that
was setting 1460 — is disabled at boot, so a reboot lands on 1500 too.

**Laptop**: `en0` 192.168.108.200 on `Sun`, `en5` 10.41.0.100/16 cabled to the AP.

**Third and fourth nodes**: Heltec HT-H7608 associated to the AP (radio-layer
control only, its IP layer never answers); Heltec HT-HC01P on a Pi 4 at
`10.42.0.1`, currently uncabled, configured as a station of `BCM2711-57e7` but
not associating.

### Open, in the order they are worth picking up

1. **The HT-HC01P will not associate.** `rsn_beacon_mode=2` put the RSN IE in the
   beacon and confirmed it on air, and it still never attempts authentication —
   hostapd logs nothing from its MAC. Needs access to that board: reach it by
   cabling `en5` to it and setting the Mac side to `10.42.0.100/24`, or by
   joining its own 5 GHz AP `HC01P-mgmt`. First thing to look at is whether its
   scan now shows RSN, with `wpa_cli_s1g -p /var/run/wpa_supplicant_s1g -i wlan0`.
2. **`ttyd` on the HT-HC01P has no authentication** and is bridged with its
   Ethernet port and 5 GHz AP, with the firewall's lan zone at `input ACCEPT`.
   Low exposure while it is uncabled; fix before it ever touches a shared switch.
3. **The HT-H7608 contradiction.** Same 1.15.3 driver, associated to this AP
   earlier with `auth_alg=0` plus an RSN 4-way. Unexplained, and it argues
   against generalising the HC01P result.
4. **Does the AP stall recur now that `openmanetd` is gone?** Three occurrences
   are recorded, two after no trigger. The recovery is known (`echo 1 > $P/reset`)
   and cheap. Worth simply watching.
5. **The station/AP power-save mismatch** (`enable_ps=2` against the AP's 0) as a
   contributor to the old 5% ping loss — never tested, and now that the logger is
   gone the station's power save is whatever NetworkManager last left it.
6. **Real range.** The link was still at −41 dBm one floor up with ~50 dB of
   headroom, so the limit is nowhere near found.

## 2026-08-24 — the SPI clock was the ceiling, and it hid the answer to the bandwidth question

**Raising the station's SPI clock from 10 MHz to 50 MHz gave 2.6× the throughput
with zero SPI errors**, and corrected a conclusion that had already been measured
and was wrong. At the stock 10 MHz clock a 4 MHz channel benchmarked *slower*
than 2 MHz and was about to be written up as "4 MHz does not help"; at 50 MHz it
is almost exactly double. The bus was the binding constraint and a wider channel
only added retries.

| SPI clock | 2 MHz air | 4 MHz air |
|---|---|---|
| 10 MHz | up 3.16 / down 2.46 | up 2.66 / down 2.29 |
| **50 MHz** | up 3.55 / down 3.27 | **up 6.86 / down 6.80** |

Where the bus time went: **83% of every byte on the station's SPI bus was the
250-byte inter-transaction padding** that this repo's own defect-3 fix installs.
The padding is correct — the chip counts clocks, not time — but for that same
reason its wall-clock cost is 200 µs at 10 MHz against 40 µs at 50 MHz. Running
at the non-reference clock multiplied a necessary overhead by five.

No SPI errors at any rung of 10 → 20 → 50 MHz, so **the SenseCAP M1 mPCIe wiring
is clean at 50 MHz** and the overlay's 10 MHz was conservative rather than
necessary. Both settings are now persistent and verified across a cold boot.

**One consequence for the PR:** at 50 MHz the driver's broken delay formula
happens to produce the correct 250, so **defect 3 no longer reproduces on this
hardware** unless the clock is set back to 10 MHz. The fix is unaffected and
defect 2 still applies. Say it plainly upstream — a driver should not need one
particular clock rate to compute a correct delay. Section below.

## 2026-08-23, evening — a third board, an MTU black hole, and what the vendor documents say

Four results. Full evidence in
[`logs/2026-08-23-mtu-blackhole-third-implementation-and-vendor-docs.txt`](logs/2026-08-23-mtu-blackhole-third-implementation-and-vendor-docs.txt).

**The reference configuration is what hides the defects.** A third SPI board
joined the bench (Heltec HT-HC01P on an RPi 4, driver 1.15.3), and Morse's
official Linux Porting Guide was read for the first time. Its EKH01 reference
overlay specifies `spi-max-frequency = <50000000>` and `reset-gpios = <&gpio 5
0>` — 50 MHz and flag 0. **Every implementation examined inherits those two
settings from the official reference**, and they are exactly what makes defect 3
invisible (the broken delay model only lands on a working value at 50 MHz). It
was recorded here that flag 0 also hid defect 2 by stopping RESET_N from firing;
**that was wrong, corrected 2026-08-24** — the flag is never read by the driver,
and what actually hides defect 2 is a kernel patch Morse ships for OpenWrt. See
"Why OpenMANET never needed the fix". The same document contains
**zero** mentions of chip select, deassert, 74 clocks, initialisation sequence,
inter-transaction delays, CMD53/CMD63 or troubleshooting — counts taken with
positive controls. Full table in "Five implementations, one reference
configuration", below.

**A silent MTU black hole was killing bulk uplink**, and had probably been
distorting every throughput figure in this file. The AP's `wlh0` is MTU 1500
while its bridge partner `eth0` is 1460, so oversized frames from the HaLow side
are dropped by the bridge with no ICMP and no counter. Uplink of 8 KiB returned
**0 bytes after 34.7 s**; one `ip link set wlan1 mtu 1460` turned that into
**0.32 s**. **The source is `openmanetd`** — identified by disabling three
candidate daemons, rebooting to 1500, and starting them back one at a time until
one moved it. Disabling it leaves the whole path at 1500 and the AP serving
normally. It is the likely cause of the "uplink varies 4x" and the
155648-of-4194304 truncated download recorded here as unexplained — indicated,
not established. Own section below.

**Range and throughput across one floor.** −41.3 dBm (30 samples), 60/60 pings at
0% loss, **2.77 Mbit/s down and 1.48 Mbit/s up** at 2 MHz. Under load the rate
controller sits at 2 MHz **MCS7** with 90.5% success, which is the top rate the
channel offers — so the limit is channel width, not link quality, and the `SG`
regdomain permits 4 MHz. Third-party numbers put 4 MHz at 2.3× the 2 MHz figure.
One floor up the house Wi-Fi did not reach and HaLow did, so the out-of-band path
ended up carrying management for the link it was measuring.

**A cross-version security-parsing difference.** A 1.15.3 station cannot see this
AP's RSN element and therefore refuses to attempt SAE — it reads the AP as
`[WEP]` and sits in `SCANNING`. 2.0.1 sees `Authentication suites: SAE` on the
same AP at the same moment. The AP's `rsn_beacon_mode` defaults to
`RSN_BEACON_DISABLED`; setting it to `2` puts the RSN IE in beacons. That did not
by itself get the 1.15.3 board associated, and why is still open.

## 2026-08-23, later — the RSSI question is answered, and the AP stall has a software fix

Two results, both measured the same afternoon. Full method, raw samples and the
tooling traps are in
[`logs/2026-08-23-rssi-range-test-and-ap-stall-recovery.txt`](logs/2026-08-23-rssi-range-test-and-ap-stall-recovery.txt).

**`signal: 0 dBm` is saturation — proven by moving a board, not argued.** The
station was carried to three distances and sampled 30 times over 60 s at each,
with predictions written down before each move. The 2 m line-of-sight point lands
**0.1 dB** from the free-space prediction (−15.7 measured, −15.8 predicted); the
0.3 m bench point is clipped, and the clipping shows up as compression in the
step (16.5 dB of true path loss producing 11.7 dB of movement). A by-product: an
interior **wooden wall costs 8 dB** at 923 MHz here, computed two independent
ways that agree to 0.1 dB. Detail in "Reading the link", below.

**The AP transmitter stall is recoverable without rebooting.** `wifi reload` ✗ →
debugfs `restart` ✗ → debugfs **`reset` ✓**. The claim recorded here after the
first two occurrences — that only a reboot recovers it — is wrong. A full
firmware reload (`restart`) is not enough; the bus reset is. The reason,
established 2026-08-24: **the driver is built into the OpenMANET kernel**, so
`wifi reload` cannot unload it and never re-runs probe — `Resetting Morse Chip`
appears exactly once in 47907 s of uptime, at boot. Nothing short of the bus
reset path reaches the chip. (An earlier note blamed `reset-gpios` flag 0; that
explanation is withdrawn.) The third occurrence, like the second, followed
nothing. Detail in "The AP's transmitter stalls", below.

**Two diagnostic corrections worth carrying forward.** The Heltec's *ping* is not
a control — it fails even when the link is healthy; only its RSSI reading and its
association events are. And the station's **power save is on by default**, which
made the stall look like beacons had stopped when they had not; force it off for
any measurement.

**Where the boards are now.** The house has a second SSID, `Sun` /
`192.168.108.0/24`, and both it and the old `Unifi` / `192.168.200.0/24` are
broadcasting — the migration is in progress, not finished. Station `55:04` is on
`Sun` at **`192.168.108.19`** (its `sun` NetworkManager profile was raised to
autoconnect-priority 20, above `preconfigured`'s 10, which is kept as a
fallback). The AP is unchanged at `10.41.254.1`. The laptop can reach the station
over HaLow directly at `10.41.0.208` with key authentication — see "The HaLow
link is an out-of-band path", below, for why that is simpler than the recipe
recorded earlier.

A temporary logger is installed on the station for the range work —
`halow-rssilog.service`, enabled at boot, writing to `/home/alan/rssi-logs/`. It
also re-asserts `power_save off` every 60 s. Remove it when the range work is
done; the command is at the end of the log file above.

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

**Board `E4:5F:01:52:55:04` is now in a clean, working state.** It was at
`192.168.200.182` when this was written; as of the later session that day it is
on SSID `Sun` at `192.168.108.19` — see the top of this file. Its state
otherwise:

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
| **`reset-gpios`** | pin 17 flag 1 | pin 17 flag 0 — **and the flag is inert either way**: 2.0.1 has no `gpiod_` call, so RESET_N fires on both |
| **Chip selects** | **two** (gpio 8, gpio 7), from `dtparam=spi=on` | **one** (gpio 8) |
| Pin pulls | `halow_pins`: 17 up, 5/23/24 down; no `spi0_pins` group, so MISO/MOSI/SCLK sit at the BCM2711 default (down) | `morse_reset` 17 up, `morse_irq` 5 up, `morse_wake` 23 up, `morse_busy` 24 down; `spi0_pins` 9/10/11 up |

**Why the AP never hit any of the three defects.** Half of it is in those rows and
half is not. 50 MHz is the one clock at which the driver's delay scaling happens
to produce a working value, so defect 3 stays invisible, and the station's 10 MHz
exposes it. Defect 2 is **not** explained by any row of this table: it is hidden
by a kernel patch that OpenMANET carries and Raspberry Pi OS does not — see "Why
OpenMANET never needed the fix". The `reset-gpios` difference in the row above
explains nothing, because the driver never reads the flag. The series in
`patches/upstream/` is what carries the station through both.

The pin-pull and chip-select differences were each eliminated as causes during
the A/B (see the sections below); they are listed here because they are real
configuration differences, not because they matter to the fault.

*Reading device-tree properties: values are big-endian. `od -An -tx1` prints the
bytes in order and is the safe form. `hexdump -e '1/4 "%08x "'` and `%d` print
host-endian, so every word comes out byte-reversed — `02 fa f0 80` (50000000)
displays as `80f0fa02`. `od` is absent from the OpenMANET image and `xxd` from
both; check the tool exists before believing an empty read.*

## Five implementations, one reference configuration — and it is the reference that hides the defects

Added 2026-08-23, after a third SPI board joined the bench and Morse's own
documents were read. This is the section that explains *why* nobody else reports
the three defects in `patches/upstream/`.

| | this repo's station | OpenMANET AP | HT-HC01P | **Morse EKH01 reference** | MMECH06 (forum) |
|---|---|---|---|---|---|
| driver | 2.0.1 + our fixes | 2.0.1 | 1.15.3 | — | 1.16.4 |
| **SPI clock** | **10 MHz** | 50 MHz | 50 MHz | **50 MHz** | 50 MHz |
| **`reset-gpios` flag** | **1** | 0 | 0 | **0** | — |
| reset GPIO | 17 | 17 | 5 | 5 | 5 |
| chip selects | two (8, 7) | one (8) | one (8) | one (8, flag 1) | one (8, flag 1) |

The fourth column is not another vendor. It is **Morse's own official Linux
Porting Guide** (`MM_APPNOTE-24`, v2), section 6.1, the EKH01 EVK reference
overlay, quoted verbatim:

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

So the pattern this repo kept finding across vendors is not a coincidence.
**Everyone inherits it from the official reference**, and those two settings are
precisely what hides one of the three defects: 50 MHz is the one clock at which
the driver's broken delay model lands on a working value (defect 3).

**Correction, 2026-08-24.** This paragraph used to claim that a `reset-gpios` flag
of 0 hid defect 2 as well, via `gpiod_set_value(reset, 1)` driving the pin high so
RESET_N never fired. That is wrong: `morse_driver` 2.0.1 contains no `gpiod_` call
at all, so the flag is parsed and discarded and RESET_N fires everywhere. Defect 2
is hidden by something the device tree cannot show — a kernel patch. Details in
"Why OpenMANET never needed the fix".

The property table in the same document describes `reset-gpios` only as "GPIO
descriptor connected to the MM6108 RESET line" and **says nothing about
polarity**.

**Update 2026-08-24: there is a sixth, and it is not only the device tree.** The
HT-HC01P also ships Morse's reference *board configuration file* —
`bcf_mf08551.bin`, the EKH01-03 EVK's BCF — while Heltec's own
`bcf_HC01_V2_H.bin` sits unused beside it in `/lib/firmware/morse/`. That one was
not invisible: the module received at −56 dBm and nothing it transmitted ever
reached the AP. Full account in the 2026-08-24 section at the top of this file.

### What the porting guide does not say

Keyword counts over the extracted text of all 22 pages, taken with positive
controls in the same pass (`Morse` 115 hits, `SPI` 21 hits, so the search works):

| term | hits |
|---|---|
| chip select / chip-select | **0** |
| deassert | **0** |
| 74 | **0** |
| init sequence / initialisation / training | **0** |
| delay / inter-block / inter-transaction | **0** |
| CMD53 / CMD63 | **0** |
| probe fail / troubleshoot | **0** |

The guide covers kernel patching, driver compilation, firmware, hostapd and
wpa_supplicant, the four device-tree properties, bring-up commands and the
`test_mode` table. It has **no troubleshooting section and documents none of the
low-level SPI behaviour the three defects concern**.

That matters upstream. The requirement that the chip needs ~74 clocks with chip
select *deasserted* is stated publicly only in a forum thread — the i.MX93 one
this repo already cites. **A developer porting by the official document has no
way to learn it**, and the released driver does not implement it correctly.

### A vendor claim this repo is a counter-example to

From the community build thread "HaLow for Raspberry Pi OS", verbatim:

> "From 1.15.3, patching the kernel is practically required, so sticking as close
> to one of these versions as possible will make integration significantly
> smoother."

The stated reasons are mesh, channel switch announcements and SPI support, and
the recipe cherry-picks a whole Morse kernel branch (`morse/mm/rpi-6.12.21/1.16.x`).

**This repo runs on stock Raspberry Pi OS 6.6.51 with an unpatched kernel**,
driver 2.0.1 plus the three `spi.c` fixes and nothing else, and associates with
WPA3-SAE, runs DHCP, moves 4 MiB checksummed both ways and reports `errors 0`.
Mesh and CSA were never exercised here, so the claim is not refuted in general —
but for a station on 6.6.51 the kernel patches are **not** required, and that is
measured rather than argued.

Nobody in that thread reports this repo's failure signature (`c0 7f`, CMD63
`-71`, `SPI_NO_CS`, `spi_inter_block_delay_bytes`), which is exactly what the
table above predicts.

### Third-party throughput numbers worth having

From the same thread (castironclay, ~20 ft line of sight, measurement tool not
stated):

| channel width | throughput |
|---|---|
| 1 MHz | 0.82 Mbps |
| 2 MHz | **3.68 Mbps** |
| 4 MHz | **8.33 Mbps** |
| 8 MHz | 5.16 Mbps — they note both devices were "ever so slightly under powered" |

This repo measured **2.77 Mbit/s at 2 MHz** one floor up (see below), the same
ballpark and a little lower, plausibly because our SPI runs at 10 MHz where
theirs runs at 50, and because ours was TCP through SSH. Their 4 MHz figure is
2.3× their 2 MHz figure, which is the best available evidence that moving this
link to 4 MHz roughly doubles it. Their 8 MHz being *slower* than 4 MHz is a
caution against assuming wider is always better.

Morse quote the MM6108 at up to 32.3 Mbps, but that is at **8 MHz**, which the
`SG` regdomain here does not permit (`(920 - 925 @ 4)` — 5 MHz of spectrum, 4 MHz
maximum). It is not a comparable number. Morse's own staff put SPI-attached hosts
at "up to 21 Mbps with iperf" on their EKH01 kit and say SPI throughput is
dominated by host-side factors. The driver ships a bus throughput profiler,
`test_mode=6`, for separating bus capability from link performance; `test_mode=4`
is a chip reset and `test_mode=5` does block reads and writes.

### The third board itself

Heltec HT-HC01P HAT on a Raspberry Pi 4B, Heltec's factory image:

```
image      OpenWrt 23.05.5, DISTRIB_DESCRIPTION "23.05.5 2.8.5-20251107"
kernel     5.15.167          board  RPi 4 Model B Rev 1.4, serial 100000004dd92ccc
eth0       e4:5f:01:40:8e:91      HaLow wlan0  0c:bf:74:40:8e:91
driver     0-rel_1_15_3_2025_Apr_16          bcf  bcf_mf08551.bin
```

**The `2.8.5` in the image name is Heltec's firmware package version, not the
Morse driver version.** The driver is 1.15.3 — *older* than the 2.0.1 this repo
patches. Worth stating because the image name reads like a driver version and
invites exactly the wrong conclusion.

Security note, because it is shipped this way: that image runs `ttyd` on
`0.0.0.0:7681` with **no authentication** (`/token` returns `{"token": ""}`),
bridged into `br-lan` with the Ethernet port and the Pi's built-in 5 GHz AP, with
the firewall's lan zone at `input ACCEPT`, and its dnsmasq serving DHCP on lan
with no `ignore` flag. Anyone in range of its Wi-Fi who knows the factory
password gets a root shell with no credentials. Do not put its Ethernet on a
shared switch before disabling the DHCP server, setting a root password and
dealing with ttyd.

Tooling on that image: `od`, `dtc`, `fdtget` and `wpa_cli` are **absent**;
`hexdump`, `xxd`, `strings` and `wpa_cli_s1g` are present. Check before believing
an empty read — the device tree above was read with `hexdump` after `od` returned
nothing and the positive control showed why.

### `rsn_beacon_mode`: why a 1.15.3 station cannot see this AP's security

The HT-HC01P would not associate as a station of the OpenMANET AP. It scanned,
found the AP at −52 dBm, and never attempted authentication; hostapd never logged
its MAC at all. The supplicant's own view named it:

```
bssid              frequency  signal  flags        ssid
3c:1a:cc:70:3f:ca  5785       -51     [WEP][ESS]   BCM2711-57e7
```

`[WEP]` means the privacy bit is set but **no RSN element could be parsed**. A
network block requiring `key_mgmt=SAE` cannot match that, so wpa_supplicant sits
in `wpa_state=SCANNING` forever and never tries. The same AP, at the same moment,
seen by the two stations:

| station | what its scan shows |
|---|---|
| this repo's, driver **2.0.1** | `RSN: Version 1, Group CCMP, Pairwise CCMP, Authentication suites: SAE` |
| HT-HC01P, driver **1.15.3** | `capability: ESS Privacy (0x0011)` and **no RSN element at all** |

Both `country=SG`, both with 5785 MHz [157] at 22 dBm available and not
passive-scan, and the counts were taken with positive controls so the zero is
meaningful.

The reason the beacon has no RSN, from `beacon.c`:

```c
static enum morse_mac_rsn_beacon_mode
rsn_beacon_mode __read_mostly = RSN_BEACON_DISABLED;

enum morse_mac_rsn_beacon_mode {
    RSN_BEACON_DISABLED = 0x00,   /* default */
    RSN_BEACON_LONG     = 0x01,
    RSN_BEACON_ALL      = 0x02
};
```

S1G beacons omit the RSN IE by default and a station is expected to learn the
security configuration from probe responses. 2.0.1 surfaces it; 1.15.3 does not.

On the AP it is a **uci option, not a sysfs file** — the driver is built into the
OpenMANET kernel and `/sys/module/morse` does not exist there. It is listed in
`MM_MOD_INT` in `/lib/netifd/wireless/morse.sh`:

```sh
uci set wireless.radio1.rsn_beacon_mode='2'
uci commit wireless && wifi reload
```

Confirmed applied in the AP's boot-time parameter dump (`rsn_beacon_mode : 2`)
and confirmed on air — this repo's station now sees the RSN element in the beacon
rather than only in probe responses.

**Resolved 2026-08-24, and the heading above claims more than the evidence
supports.** Setting `rsn_beacon_mode=2` did work. The HT-HC01P afterwards reads
`[WPA2-SAE-CCMP][SAE-H2E][ESS]` rather than `[WEP]`, and the beacon's RSN element
parses cleanly on that board — group and pairwise CCMP, AKM `00-0f-ac-08` (SAE),
RSN capabilities `0x00cc` with MFPC and MFPR both set. It was simply not what was
blocking the board. Its BCF was; see the section at the top of this file.

**The inconsistency was not one.** The HT-H7608, same 1.15.3, sat associated to
this AP with `auth_alg=sae` and a completed 4-way throughout the 2026-08-24
session. So the `[WEP]` observation is real and `rsn_beacon_mode=2` fixes it, but
**whether 1.15.3 strictly requires it is still not established** — the H7608 was
never scanned directly, and the `auth_alg=0` line that prompted the original note
was a single log entry that was never reproduced. What can be said is narrower
than the heading: this AP's S1G beacons omit the RSN IE by default, a 1.15.3
station reads that as `[WEP]`, and `rsn_beacon_mode=2` puts the element where it
can see it.

## The SPI clock was the throughput ceiling, and 4 MHz only pays once it is raised

2026-08-24. Full method and raw runs in
[`logs/2026-08-24-spi-clock-is-the-throughput-ceiling.txt`](logs/2026-08-24-spi-clock-is-the-throughput-ceiling.txt).

**Raising the station's SPI clock from 10 MHz to 50 MHz gave 2.6× the throughput
with zero SPI errors** — and it changed the answer to a question that had already
been measured wrong.

| SPI clock | air BW | uplink | downlink |
|---|---|---|---|
| 10 MHz | 2 MHz | 3.16 | 2.46 |
| 10 MHz | 4 MHz | 2.66 | 2.29 ← *looks like a regression* |
| 50 MHz | 2 MHz | 3.55 | 3.27 |
| **50 MHz** | **4 MHz** | **6.86** | **6.80** ← the real answer |

Mbit/s, all at the same position with the station on the bench beside the AP,
1 MiB of incompressible payload each way over SSH, three runs per cell except the
two 10 MHz rows.

**4 MHz does roughly double the throughput, and it could not show that while the
host bus was the binding constraint.** Widening the channel with the bus already
saturated only adds retries: at 10 MHz/4 MHz the AP logged 1569 tx retries and
155 tx failed, against ~4 and 0 at 10 MHz/2 MHz. Measured at the stock clock,
"4 MHz does not help on this link" was about to be written down as a finding.

### Where the bus time was going: our own fix, multiplied by five

The air side was fine throughout. Under load at 4 MHz mmrc selected 4 MHz MCS7
with airtime **755** against **1582** at 2 MHz MCS7 — frame time halved, exactly
as a doubled channel should — while application throughput did not move. When the
layer under test improves and the number you care about does not, the bottleneck
is elsewhere.

The station's SPI transfer histogram says where:

```
256-511 bytes    2,643,750 transfers   <- 97% of all transfers
16-31               53,614
512-1023            13,422
2048-4095           12,368
1024-2047            3,220
4096-8191               75
                 ---------
total            2,721,694 messages, 794,653,458 bytes
```

That 256–511 bucket is the **250-byte inter-transaction padding this repo's own
defect-3 fix installs** (`SPI_MIN_DELAY_BYTES` in `spi.c`). At 250 bytes each it
is roughly 661 MB of the 794 MB on the bus — **about 83% of every byte the SPI
bus moved was padding.**

The padding is correct and necessary; the chip counts *clocks*, not time, which
is the entire content of defect 3. But because it counts clocks, its wall-clock
cost scales inversely with the clock rate:

```
250 bytes = 2000 clocks  ->  200 µs at 10 MHz
                         ->   40 µs at 50 MHz
```

Running at 10 MHz multiplied a necessary overhead by five. `Queue stop` was
non-zero on both ends at that point — 148 on the station, 134 on the AP.

### The ladder, and that the wiring is clean at 50 MHz

`spi_clock_speed` is a module parameter and, per the comment at `spi.c:1464`,
overrides the device tree, so no rebuild is needed:

```sh
rmmod morse
modprobe morse country=SG bcf=bcf_fgh100mhaamd.bin spi_clock_speed=50000000
nmcli con up halow
```

| SPI clock | uplink | downlink | SPI errors |
|---|---|---|---|
| 10 MHz | 2.66 | 2.29 | 0 |
| 20 MHz | 5.732 / 5.774 / 5.746 | 5.526 / 4.690 / 5.474 | 0 |
| 50 MHz | 6.666 / 7.047 / 6.866 | 7.164 / 7.017 / 6.218 | 0 |

`errors` and `timedout` under `/sys/class/spi_master/spi0/statistics` stayed at 0
at every rung, and `dmesg` produced no write failure, read failure, CRC error,
CMD53 or CMD63 at any speed. **The SenseCAP M1 mPCIe wiring is clean at 50 MHz** —
the 10 MHz in this repo's overlay was conservative rather than necessary, and it
cost a factor of 2.6. The shape of the curve is informative too: 10→20 MHz more
than doubles, 20→50 MHz adds about 20%, which is what it looks like when the bus
stops being the binding constraint and the air interface takes over.

For scale, the community build thread reports 3.68 Mbps at 2 MHz and 8.33 Mbps at
4 MHz at ~20 ft on a 50 MHz SPI host. This link now measures 3.55 at 2 MHz (96%
of theirs) and 6.86 at 4 MHz (82%).

### Selecting a 4 MHz channel: the SG regulatory table

Setting `s1g_chanbw=4` alone is not enough — the channel number must change too.
Keeping `channel=42` gets a refusal worth recognising:

```
netifd: radio1: Couldn't find regulatory data for SG with ch=42 bw=4 op= chzn=
netifd: radio1: wifi-iface 0 mode=ap ignored; requires valid country/channel setup
```

The table is a CSV at `/usr/share/morse-regdb/channels.csv`. Every SG row in the
920–925 MHz allocation:

| bw | s1g_chan | centre MHz | maps to 5G ch |
|---|---|---|---|
| 1 | 37 / 39 / 41 / 43 / 45 | 920.5 … 924.5 | 149 … 165 |
| 2 | 38 | 921.0 | 151 |
| 2 | 42 | 923.0 | 159 |
| **4** | **40** | **922.0** | 155 |

**There is exactly one 4 MHz channel in SG: channel 40, centred 922.0 MHz** —
which is why the Heltec HT-HC01P shipped configured for channel 40.

```sh
uci set wireless.radio1.channel='40'
uci set wireless.radio1.s1g_chanbw='4'
uci commit wireless && wifi reload
```

Read back what the radio actually did with `morse_cli -i wlh0 channel`. `iw`
shows only the dot11ah mapping, where 4 MHz appears as an 80 MHz-wide mapped
channel and 2 MHz as 40 MHz.

### Consequence for the upstream work: defect 3 stops reproducing at 50 MHz

**At 50 MHz the driver's broken formula happens to be right.**
`40000ns / (clk_period * 8)` evaluates to 250 bytes at 50 MHz — the correct
value — which is exactly why every vendor running the reference clock never sees
defect 3. This repo found it only because it was running at 10 MHz, where the
same formula gives 50, and 50 fails.

The fix is unaffected: `SPI_MIN_DELAY_BYTES` is an unconditional floor of 250, so
it produces the same value at 50 MHz and stays correct. Defect 2 is unaffected
too — it is about chip select during the init burst, not timing, and it still
applies here because this repo's overlay sets `reset-gpios` flag 1 so RESET_N
actually fires.

**But anyone reproducing defect 3 from this repo must set the clock back first:**

```sh
modprobe morse country=SG bcf=bcf_fgh100mhaamd.bin spi_clock_speed=10000000
```

Worth saying plainly in the PR rather than hiding: the configuration that exposes
the defect is the non-default clock. That argues *for* the fix, not against it —
a driver should not depend on one particular clock rate to compute a correct
delay.

### Final configuration: the overlay carries it, not a module parameter

The module parameter was the way to run the ladder without a rebuild. The
settled configuration puts the clock where it belongs — in the device tree, so
`overlays/mm610x-spi-sensecap.dts` in this repo now reads
`spi-max-frequency = <50000000>` with a comment explaining why and how to undo
it.

```
AP       channel 40 + s1g_chanbw 4   ->  922.0 MHz, 4 MHz operating, 2 MHz primary
station  overlays/mm610x-spi-sensecap.dts -> 50 MHz, compiled and installed
         /etc/modprobe.d/morse.conf back to: options morse country=SG bcf=bcf_fgh100mhaamd.bin
```

The previous 10 MHz blob is kept beside the installed one as
`mm610x-spi-sensecap.dtbo.10mhz` (`.orig` is also 10 MHz), and both were checked
with `fdtget` rather than trusted by filename — `.dtbo` 50000000, `.10mhz`
10000000, `.orig` 10000000.

Verified from a cold boot, and deliberately verified on the *blob* and the *live
node* rather than on the source file:

```
modprobe.conf            options morse country=SG bcf=bcf_fgh100mhaamd.bin
spi_clock_speed param    0                 <- the DT is in charge
live DT node             02 fa f0 80       = 50,000,000
"Overriding the device tree" in dmesg   0  <- no parameter involved
spi errors 0   timedout 0   driver failures 0
uplink   7.463 / 7.372 / 7.401 Mbit/s
downlink 6.303 / 6.979 / 6.919 Mbit/s
```

**Reproducing defect 3 still works**, because the module parameter overrides the
device tree in *both* directions (`spi->max_speed_hz = max_speed_hz`,
unconditional):

```sh
modprobe morse country=SG bcf=bcf_fgh100mhaamd.bin spi_clock_speed=10000000
```

so the repo keeps its reproduction path without keeping the slow default. If a
full device-tree reproduction is wanted, install
`mm610x-spi-sensecap.dtbo.10mhz` over the active one and reboot.

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

## Gotcha: a silent MTU black hole that kills bulk transfer in one direction only

Found 2026-08-23 while measuring throughput one floor up. It is a property of the
test network, not of the driver, and it has probably been distorting every
throughput number in this repo.

**Symptom.** Bulk transfer works one way and hangs the other, with no error
anywhere. Small transfers work both ways. A trivial `ssh host echo hi` completes
in 0.56 s throughout, so the link and the login are healthy.

| size requested | uplink (Pi → laptop) | downlink (laptop → Pi) |
|---|---|---|
| 1024 B | 1024 B in 0.29 s | 1024 B in 0.31 s |
| 8192 B | **0 B in 34.71 s** | 8192 B in 0.51 s |
| 32768 B | **0 B in 34.96 s** | 32768 B in 0.67 s |
| 524288 B | never completed | 524288 B in 1.81 s |

A threshold between 1 KiB and 8 KiB is a **packet-size** boundary, not a rate
problem. That is the tell.

**Cause.**

```
AP    br-lan  mtu 1460     eth0  mtu 1460     wlh0  mtu 1500
Pi    wlan1   mtu 1500
Mac   en5     mtu 1500
```

`wlh0` is 1500 but its bridge partner `eth0` is 1460, and a Linux bridge takes
the minimum of its ports, so `br-lan` is 1460. Frames larger than 1460 arriving
from the HaLow side cannot be forwarded to the wired side, and the bridge drops
them. **A bridge is L2 and sends no ICMP fragmentation-needed**, so neither
endpoint is ever told. Both negotiated MSS from their own 1500-byte interfaces,
so TCP retransmits full-size segments forever.

A DF ping sweep confirms it, and its shape is worth understanding:

```
Pi -> AP    all sizes OK up to a 1500-byte frame    <- the AP is the destination;
                                                      the frame never egresses eth0
Mac -> Pi   OK at frame 1460, FAIL at 1468 and up   <- it is the REPLY being dropped
```

**Fix.** One command on the station, and the transfer that had hung for 35 s
completes in 0.32 s with nothing else changed:

```sh
ip link set wlan1 mtu 1460
nmcli connection modify halow 802-11-wireless.mtu 1460   # to persist
```

### Root cause: `openmanetd` sets it, and it is identified

Nothing in `/etc/` sets 1460 and `uci show network` has no mtu option — the value
is applied at runtime, `dmesg` showing `br-lan` already at 1460 by second 43.9 of
boot. It was pinned down by disabling the three candidate daemons, rebooting, and
then starting them back one at a time:

| step | `eth0` | `br-lan` |
|---|---|---|
| reboot with `openmanetd`, `alfred`, `mesh11sd` all disabled | **1500** | **1500** |
| start `mesh11sd`, wait 20 s | 1500 | 1500 |
| start `alfred`, wait 20 s | 1500 | 1500 |
| **start `openmanetd`, wait 20 s** | **1460** | **1460** |

Single variable, and the 1500 held at 65 s, 90 s, 115 s and 140 s of uptime —
well past the 43.9 s mark where it used to change. **`openmanetd` is what sets
it**, presumably reserving 40 bytes for batman-adv encapsulation on a mesh that
is not running on this board at all (`alfred` is launched against `br-ahwlan` and
`bat0`, neither of which exists, which is what fills the log with `can't get
interface: No such device`).

**Stopping `openmanetd` does not undo it** — the change is one-way. Either reboot
with it disabled, or set the MTU back by hand once it is stopped:

```sh
/etc/init.d/openmanetd disable      # and alfred, mesh11sd if the mesh is unused
ip link set eth0 mtu 1500           # only needed to fix the running system
```

With that done, `eth0`, `br-lan` and `wlh0` are all 1500, a DF ping sweep passes
at every size up to a full 1500-byte frame (6 packets each, 0% loss), and the
8 KiB uplink that returned **0 bytes in 34.7 s** returns **8192 bytes in 0.32 s**.
The AP keeps serving normally without those three daemons — SSID up, both
stations associated, `rsn_beacon_mode` preserved across the reboot.

Fixing it at the source rather than clamping the station is also faster, because
full-size frames carry less per-packet overhead: uplink of 256 KiB moved at
2.450 Mbit/s and 512 KiB downlink at 2.880 Mbit/s with md5 verified. *Those
figures are not a clean before/after against the 1.48 / 2.77 Mbit/s recorded one
floor up — the board had been carried back to the bench by then, so position and
MTU both changed.*

If a station cannot be changed and the AP must keep the small MTU, the
network-wide form is to advertise the real value over DHCP:
`uci add_list dhcp.lan.dhcp_option='26,1460'`.

**What this probably explains.** Two entries recorded in this file as unexplained
are exactly what a silent MTU black hole produces — "uplink varies 4x,
0.23–0.90 Mbit/s", and "the first sustained download truncated at 155648 of
4194304 bytes". **Strongly indicated, not established**: neither has been
reproduced with the MTU restored. The 5% ping loss is *not* explained by this;
small packets pass.

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

**The reason is saturation, and this is now measured rather than argued.** The
two SenseCAP M1 boards sat on the same bench. At 923 MHz over 0.3 m the
free-space path loss is about 21 dB, so a 22 dBm transmitter puts roughly
**+1 dBm** into the receiver — above the top of the scale. A reading clipped to 0
is exactly what that looks like, and it explains every zero in this repo: the two
boards had never been more than about a metre apart.

Later the same day the station board was carried away from the AP and the reading
was sampled at three distances, 30 samples over 60 s at each. Predictions were
written down before each move, from FSPL(dB) = 20·log10(d_m) + 31.75 at 923 MHz
against the AP's 22 dBm:

| position | predicted | AP-side measured | station-side |
|---|---|---|---|
| 0.3 m, board to board | **+0.7 dBm** | −3 (range −2…−4) | 0 dBm |
| 2 m, line of sight | **−15.8 dBm** | **−15.7** (range −14…−19) | −12.1 dBm |
| 4 m, one wooden wall | −21.8 dBm + wall | **−29.9** (range −28…−32) | −27.1 dBm |
| **one floor up** | — | **−41.3** (range −38…−44) | −37.7 dBm |

The 2 m line-of-sight point lands **0.1 dB** from the free-space prediction, so
the measurement path is accurate once the signal is inside the scale. The 0.3 m
point is clipped, and the clipping is visible in the step rather than only
inferred from the absolute value: true path loss from 0.3 m to 2 m is 16.5 dB
while the reading moved just 11.7 dB (−4 → −15.7). The near end is compressed by
4–5 dB, which is what a reading pressed against its ceiling does.

As a by-product, **an interior wooden wall costs 8 dB at 923 MHz** here. Two
independent computations agree: absolute (−29.9 measured against −21.8 free
space) and by the step (2 m → 4 m is 6.02 dB of distance, the reading moved
14.2 dB, excess 8.2 dB).

Link quality was unaffected at every position — 20/20 pings, 0% loss, RTT
8.3–8.8 ms at 4 m through the wall, and 60/60 with 0% loss one floor up. For
orientation: at −30 dBm, with MCS0 sensitivity around −95 dBm, roughly 65 dB of
headroom remains; one floor up there is still about 50 dB.

**The floor is cheap and the management network is not.** One floor up the HaLow
link was fine while the house Wi-Fi did not reach at all, so HaLow became the
only way to the board — the out-of-band path carrying the management traffic for
the link it was measuring. Throughput there, after the MTU fix described below,
was **2.77 Mbit/s down and 1.48 Mbit/s up** at 2 MHz.

*One trap when measuring loss at range: a first ping run at that position
reported 12% loss and was wrong, because the management SSH session was running
over the same HaLow link at the time. A clean run returned all 60 sequence
numbers. Do not measure loss on a link you are also using as your terminal.*

The test was run by moving a board. **Do not attenuate with `iw set txpower
fixed`** — see the next subsection for what that does. Station power save must be
forced off for the duration (`iw dev wlan1 set power_save off`); with it on, the
receiver is off part of the time and every figure is taken through it. Full
method and raw samples in
[`logs/2026-08-23-rssi-range-test-and-ap-stall-recovery.txt`](logs/2026-08-23-rssi-range-test-and-ap-stall-recovery.txt).

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
  That is a real effect of the bench arrangement, not a driver defect. This is
  read from the source and has **not** been confirmed by observation: at −30 dBm
  after the range test the AP's mmrc table did show 2 MHz LGI MCS0 selected, but
  that table had just been reset and every attempt counter in it was 0, so it is
  the table's initial state and not evidence either way. Testing the seeding
  needs its own design.
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
get back in. **The third also followed nothing**, later on 2026-08-23, with only
read-only commands issued that session. So the txpower command is one way to
provoke it, not the only cause, and two of three occurrences had no trigger at
all.

### The recovery ladder — `reset` works, and it is not the same thing as `restart`

"A reboot is the only way back" was recorded here after the first two
occurrences. That is wrong. The third occurrence was recovered **without
rebooting**, and the rungs are not interchangeable:

| rung | outcome |
|---|---|
| `wifi reload` | does not recover |
| debugfs `restart` (`echo 1 >`) | **does not recover** |
| debugfs `reset` (`echo 1 >`) | **recovers** |
| reboot | recovers |

```sh
# find the phy first — it is renumbered whenever the driver re-initialises
# (phy0 before the bus reset in this session, phy2 after)
P=$(find /sys/kernel/debug/ieee80211 -maxdepth 2 -name morse)
echo 1 > $P/reset
```

From `debug.c` and `mac.c` in the 2.0.1 source, the two entries are different
depths of recovery: `restart` schedules `mors->recovery.driver_restart` →
`morse_mac_restart()`, which reloads the firmware and re-inits the MAC, and
escalates to a bus reset by itself if that fails; `reset` schedules
`mors->recovery.bus_reset` → `morse_bus_reset()` directly.

`restart` completed cleanly and did not help:

```
morse_spi spi0.0: morse_mac_restart: Restarting HW
morse_spi spi0.0: Loaded firmware from morse/mm6108.bin, size 468304, crc32 0xbe7b5c8f
morse_spi spi0.0: Loaded BCF from morse/bcf_fgh100mhaamd.bin, size 1251, crc32 0x941b2a82
ieee80211 phy0: Hardware restart was requested
```

**A full firmware reload over SPI is not enough**, which is worth knowing on its
own — whatever is stuck survives writing the firmware image into the chip again.
`reset` then restored it completely: 20/20 each way, 0% loss, RTT 8.5 ms, and the
link held for the remaining 18 minutes of 1 Hz monitoring (486 replies, 41
losses, 40 of them the deliberate power-off while a board was carried to the next
measurement position).

Why `wifi reload` cannot do it, established 2026-08-24: **the driver is built into
the OpenMANET kernel.** `lsmod` lists no `morse`, `/sys/module/morse` does not
exist, and `morse_spi` appears under `/sys/bus/spi/drivers/` as a built-in. So
`wifi reload` cannot `rmmod` it, never re-enters probe, and therefore never calls
`morse_hw_reset()` — `Resetting Morse Chip` appears exactly **once** in this AP's
log, at boot, across 47907 s of uptime that includes the stall episodes. Tearing
down and recreating the interface cannot put the chip through a hardware reset;
the bus reset path is what reaches it.

An earlier version of this paragraph blamed `reset-gpios` flag 0 "so RESET_N never
fires on this board". That is withdrawn — the flag is never read by the driver.

### What the host sees while it is stalled: nothing at all

Measured during the third occurrence, with both readers validated against a
known-good case in the same breath as the failing one:

| test | result |
|---|---|
| station sends 5 pings → AP rx counter | **+774 bytes** — uplink delivers |
| AP sends 5 pings → station rx counter | **+0 bytes** — downlink does not |
| both sides idle 6 s, no traffic | +152 / +154 — both readers are live |

debugfs `page_stats` on the AP, 49 minutes into the stall:

```
Beacon Tx: 29040        <- 49 min at 100 ms beacon = 29400; beacons are still
Data Tx: 5659              being handed to the chip at the moment of measurement
Page write fail: 0
No page: 0
Queue stop: 0
Tx aged out: 0
TX ps filtered: 0
TX status invalid: 0
```

`dmesg` had not produced a line since second 16 of boot. Thermal 46 °C.
`ip -s link` reported `errors 0 dropped 0`. For the affected station, mmrc's
entire table showed **2 total attempts** — the rate controller had barely been
asked to send anything. Every host-side counter is clean, so the failure is
downstream of anything the driver can see.

### The Heltec is a radio-layer control, never an IP-layer one

"The AP cannot ping the Heltec either, therefore the failure is AP-wide" was used
during this diagnosis and **does not hold**. The AP cannot ping the Heltec at
`10.41.0.197` even now, with the link healthy and the AP reading its signal at
−69…−76 and updating — its IP layer is unreachable for its own unrelated reasons.

What did carry weight is radio-layer evidence: immediately after the `restart`,
the Heltec completed a full handshake in the AP's hostapd log — `authenticated` →
`associated` → `AP-STA-CONNECTED` → `EAPOL-4WAY-HS-COMPLETED` — which requires the
AP to transmit, while the other station's pings were still failing. Use its RSSI
in `station dump` and its association events as the control. Not its ping.

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

### Station power save masks it, and corrupts any measurement taken through it

The station's power save is **on by default** — `iw dev wlan1 get power_save`
returns `on`, and the morse module's `enable_ps` parameter reads `2`. The AP is
configured the other way: `enable_ps=0`, `enable_dynamic_ps_offload=0`,
`enable_twt=0`.

While the AP was stalled, the station's rx counter grew by **0 packets in 8 s**,
which reads as "not even beacons are arriving". One command changed that to
**+154 packets in 8 s** with nothing else touched:

```sh
iw dev wlan1 set power_save off
```

The station had been asleep. Part of what looked like a dead transmitter was the
receiver being off.

This matters twice:

- **For measurement.** Any RSSI or loss figure taken with power save on is taken
  through a receiver that is off part of the time. The range test above was run
  with it forced off, re-asserted every 60 s because NetworkManager can turn it
  back on across a reconnect.
- **For diagnosis.** It made an AP-side fault look worse than it was, and it is
  why the first read of the third occurrence was "the transmitter is completely
  dead, beacons included". The beacons were going out the whole time.

Power save off did **not** restore the downlink — the unicast path stayed dead
until the bus reset. The two effects are independent and were stacked on top of
each other.

The station/AP power-save mismatch is untested as a cause of anything. It is a
plausible contributor to the 5% packet loss recorded earlier and deserves its own
experiment.

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

**There is a simpler form, and it is the one to reach for first.** The AP's
`br-lan` bridges `eth0` and `wlh0`, and the laptop's USB-Ethernet sits in the
same `10.41.0.0/16`. So the laptop can reach the station's HaLow address
*directly*, with ordinary key authentication — no hop through the AP, no dropbear
client, and no password in a command line:

```sh
ssh alan@10.41.0.208
```

Verified end to end on 2026-08-23. The two-hop `dbclient` recipe above still
works and is the fallback if the laptop is not cabled to the AP.

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

**Rewritten 2026-08-24.** The explanation that stood here was wrong, and what
replaces it is both better evidenced and better for the upstream argument. What
was wrong was only the *reason OpenMANET escapes*; the measurement below and the
fix in `patches/upstream/` are untouched.

**It does reset the chip.** Its own boot log:

```
[   10.066857] morse micro driver registration. Version 0-rel_mm6108_2_0_1_2026_Jun_11
[   10.074667] morse_spi spi0.0: morse_of_probe: Reading gpio pins configuration from device tree
[   10.083313] Resetting Morse Chip
[   10.894587] morse_spi spi0.0: Loaded firmware from morse/mm6108.bin, size 468304, crc32 0xbe7b5c8f
```

`Resetting Morse Chip` is the `pr_info()` inside `morse_hw_reset()`, printed after
`gpio_request()` succeeds and immediately before the pin is driven low. The AP runs
**the same driver version this repo reads**, `2.0.1`, and pulses RESET_N at probe
exactly as the station does.

**The `reset-gpios` flag is inert.** `morse_driver` 2.0.1 contains no `gpiod_` call
anywhere — `git grep gpiod_` over the tree returns zero hits. `of.c` reads the pin
with `of_get_named_gpio()`, which returns the number and discards the flags, and
`hw.c: morse_hw_reset()` uses the legacy integer API, whose `gpio_direction_output()`
is `gpiod_direction_output_raw()` and bypasses polarity inversion by construction.
Changing the flag from 0 to 1 cannot change what the driver does. That is why
"testing `reset-gpios` flag 0 on its own changed nothing", recorded below as an
oddity needing an explanation, was simply the correct result.

**What OpenMANET actually has is a kernel patch, written by Morse Micro.**
`OpenMANET/firmware`, `target/linux/bcm27xx/patches-6.6/991-0007-spi-support-control-cs-pin-on-init.patch`
— identical copy in `MorseMicro/openwrt` as
`999-001-morse-spi_driver_gpio_descriptor.patch` — from Sagar Bussa
<sagar.bussa@morsemicro.com>, 2025-03-13. It adds a flag to the kernel's SPI core:

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

Its commit message states the purpose outright: *"The Morse Micro driver requires
control of the chip select line during initialisation, to correctly sequence the
line to enter SPI mode. This patch adds a bit which instructs the bus to not force
the chip select high in during spi_setup."*

With that patch in the kernel, `morse_spi_initsequence()`'s `SPI_CS_HIGH` flip
genuinely deasserts CS, the 74 training clocks land correctly, and the chip returns
to SPI mode after every reset. Without it, `spi_setup()` forces `SPI_CS_HIGH` back
on for a `cs-gpios` device, the flip is a no-op, and the burst goes out with the
chip selected. **That is the entire difference between the AP and the station** —
same SenseCAP M1 hardware, same MM6108A1, same driver 2.0.1, same
`cs-gpios = <&gpio 8 1>`, same reset at probe. Only the kernel tree differs.

**Independent confirmation, from a third party.** `OpenMANET/packages` carries
`morse-micro/mm6108-driver/patches/021-spi-demote-cs-gpiod-warning-to-runtime.patch`,
whose header reads: *"`SPI_CONTROLLER_ENABLE_CS_GPIOD` is not a mainline kernel
flag; it is added by a Morse Micro patch to `include/linux/spi/spi.h` that only the
bcm27xx target carries … the driver's `#warning` fallback is fatal under the
kernel's `-Werror` … Without it CS may be forced high during `spi_setup`."* Someone
else hit defect 1 on a ramips target and fixed it the same way this repo did, and
described defect 2's mechanism in the same breath.

**This strengthens the upstream case rather than weakening it.** Morse Micro's own
answer to defect 2 is to patch the kernel's SPI core. This repo's answer is
`SPI_NO_CS` inside the driver, which needs no kernel patch and therefore works on a
stock Raspberry Pi OS kernel. The community claim that *"patching the kernel is
practically required"* — recorded above as a vendor claim this repo is a
counter-example to — turns out to have a specific, named, Morse-authored patch
behind it. The counter-example still stands, and it is now a sharper one.

**The measurement that started this is unaffected.** Taken on this board, with the
module's power under our control on GPIO18:

| | response |
|---|---|
| cold power-up, no training at all | `ff 01 ff` — **aligned, already in SPI mode** (3/3) |
| same power-on, after a RESET_N pulse | `ff c0 7f` — **offset, knocked out of SPI mode** |
| training after that | `ff c0 7f` — not recovered (a CS-asserted command had already happened) |

Step 1 → 2 is the clean one: same power-on, nothing changed but a reset pulse,
and the chip goes from aligned to offset. **RESET_N takes the chip out of SPI
mode**, and only the training burst can put it back. That is why a broken burst is
fatal on an unpatched kernel and invisible on a patched one — the reset happens
either way.

**Caveat:** the power-on state is not perfectly deterministic — 1 of 5 cold
power-ups came up already offset. Cause unknown. The chip *usually* powers up in
SPI mode, not always.

This also explains two community replies found early and not understood at the
time — *"the issue resolved after a physical power cycle rather than a soft
reboot"* and *"most of our deployments use a reset script to toggle the reset
line on boot"*. A physical power cycle puts the chip back into SPI mode; a soft
reboot does not, because the module keeps power and stays where the last RESET_N
pulse left it. As for why testing `reset-gpios` flag 0 on its own changed nothing:
the flag is never read by the driver, so there was nothing for it to change. The
elaborate explanation this file used to give for that result is withdrawn.

**With the fix none of this matters.** The driver delivers the training correctly
straight after reset, so the chip ends up in SPI mode regardless of how it powered
up, how often it has been reset, or whether the kernel carries Morse's SPI-core
patch. OpenMANET works by requiring a patched kernel; the fix makes the driver
correct on any kernel.

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
