# DKMS lifecycle validation — protocol

Validates the `packaging/dkms/` layer of
[alan-sun-dev/morse_driver](https://github.com/alan-sun-dev/morse_driver)
through a complete lifecycle: add → build → install → cold boot → HaLow →
kernel upgrade → rebuild → boot → HaLow → uninstall → rollback.

**Run end to end on 2026-08-25** on a dedicated card in the HT-HC01P board.
Result: `logs/2026-08-25-dkms-lifecycle-full-run.txt`. Two findings overturned
what this document predicted; both are in "Results" at the bottom. Everything
except the running of it was prepared beforehand:
`dkms-lifecycle.sh` performs each leg and appends every recorded value to
`~/halow-test/dkms-lifecycle-record.txt` on the board — not `/tmp`, which a
reboot clears, and this test contains two reboots.

## Why a separate card

Three MM6108 radios exist here and all three are committed:

| radio | role | free? |
|---|---|---|
| MM6108A1 in SenseCAP M1 `57:E7` | **the AP** every other node associates to | no — losing it ends the link for everything |
| MM6108A1 in SenseCAP M1 `55:04` | station, soak testing the fork branch | no |
| MM6108A2 on the Heltec HAT | `hc01p`, soak testing the fork branch | no |

A DKMS install replaces the modules in `updates/`, which is exactly what both
soak tests are exercising, so the lifecycle cannot share a board with them. The
functional legs need a real radio, so it cannot be done in a VM or a container
either.

**What has to happen first:** a spare SD card, written with Raspberry Pi Imager
(`2024-11-19-raspios-bookworm-arm64-lite`, **no Imager customisation** — this
image's `raspberrypi-sys-mods` is too old for `custom.toml`), then
`port/hc01p/apply-to-card.sh` for the first-boot payload. The card goes into the
HT-HC01P board, whose soak pauses for the duration; its two existing cards stay
untouched and labelled.

Starting from `6.6.51` matters: the upgrade leg needs a real kernel bump to
perform, and `linux-image-rpi-v8` currently offers `1:6.12.96-1+rpt1` against the
image's `1:6.6.51-1+rpt3`.

## Stage 0 — prepare everything except the driver

`firstrun.sh` deliberately touches nothing Morse-related, so a freshly imaged
card boots to a reachable Pi with no driver at all. That is the right starting
point: DKMS should be the only thing that ever puts a module on this system.
Before the lifecycle starts the board still needs the parts that are **not**
DKMS's job:

- `mm610x-spi-hc01p.dtbo` in `/boot/firmware/overlays/` and `dtoverlay=` in
  `config.txt` — and **no `dtparam=spi=on`**, which would restore
  `spi0_cs_pins = <8 7>` and take GPIO 7, the HAT's MM_BUSY line;
- `mm6108.bin` and `bcf_HC01_V2_H.bin` in `/lib/firmware/morse/`;
- `/etc/modprobe.d/morse.conf` with `country=SG bcf=bcf_HC01_V2_H.bin
  macaddr_suffix=40:8e:91` — the suffix is not optional;
- the `halow` NetworkManager profile, bound to the MAC rather than to an
  interface name, with `wifi.powersave 2` and `ipv4.never-default yes`;
- `git`, `build-essential`, `bc`, `dkms`, and the matching kernel headers.

Record a `snapshot stage0` here. It should show no morse module anywhere.

## The legs

Predictions are written down before each leg is run, and the record keeps both.

| leg | command | what must be true afterwards |
|---|---|---|
| 1 add | `dkms-lifecycle.sh add` | `/usr/src/morse-<version>` staged with `mmrc-submodule` populated; `dkms status` shows `added` |
| 2 build | `... build` | `built`; `.ko.xz` under `.../<kernel>/aarch64/module/`; `srcversion` equals a manual build of the same commit |
| 3 install | `... install` | modules land in `/lib/modules/<kernel>/updates/`; `depmod` run; record the exact paths |
| 4 cold boot | reboot | `boot_id` changes; module autoloads from the DKMS-installed path |
| 5 HaLow | `... halow` | firmware + BCF load, SAE + PMF association, SPI `errors 0`, ping over the air |
| 6 kernel upgrade | `apt full-upgrade` detached, then reboot | **see the AUTOINSTALL note below — the prediction is that HaLow does NOT come up** |
| 7 rebuild | `... build-for <new kernel>` | module built and installed for the new kernel |
| 8 HaLow again | `... halow` | same checks pass on the new kernel |
| 9 uninstall | `... uninstall` | modules gone from every `updates/`, `dkms status` empty |
| 10 rollback | `... rollback-check` | nothing left behind; the board is back to stage 0 |

## The AUTOINSTALL contradiction, stated before the test rather than after

`AUTOINSTALL="no"` means Debian's `/etc/kernel/postinst.d/dkms` hook, which runs
`dkms autoinstall`, **skips this module**. So with the setting we are keeping for
the first pass there is no automatic rebuild to observe: after leg 6 the new
kernel will have no morse module and HaLow will not come up. That is the
prediction, and it is worth recording rather than avoiding — it measures exactly
what `AUTOINSTALL="no"` costs, on a board where it costs nothing to find out.

Leg 7 then demonstrates the **cross-kernel build path** by invoking it by hand.
That is the part that has to be shown safe. Only once it is should
`AUTOINSTALL="yes"` be trialled, as a second pass on the same card: set it,
upgrade a kernel again, and confirm the rebuild happens by itself and that a
failure to build cannot silently remove a working driver.

Note that `-Werror` stays as upstream has it throughout. It is the reason
`AUTOINSTALL="yes"` is a risk at all, and changing both at once would leave
neither tested.

## Rollback

Two different things can be rolled back and they should not be confused.

**Rolling back the DKMS install** is legs 9 and 10: `dkms uninstall --all`
removes the modules it placed in `updates/`, `dkms remove --all` drops the
build tree, and `/usr/src/morse-<version>` is removed by hand. Verified by
`rollback-check`, which looks for leftovers under every `updates/` directory —
matching `morse.ko*` and not `morse.ko`, because these images compress modules
and a search for `.ko` finds nothing on a system that has them.

**Rolling back the whole experiment** is putting the original card back in the
board. The test card is separate for exactly this reason; nothing about this
procedure can reach the two soaking cards or the labelled OpenWrt one.

## What this cannot establish

The A1 hardware. The test board is the HAT, so the lifecycle is validated on
MM6108A2 only. Repeating it on the SenseCAP carrier would need that board, which
is soaking, and a fourth card.

## Results, 2026-08-25

All ten legs ran. The lifecycle itself works: `dkms install` on 6.6.51 →
cold boot → autoload at t=7.6 s → SAE association → kernel upgrade to 6.12.96 →
module rebuilt and installed **automatically** → cold boot → autoload at
t=4.42 s → association → uninstall → reboot → nothing left. `srcversion` was
`89A7C1DAC9B51F941EFC8F2` at every stage, identical to a manual build, and SPI
`errors 0 / timedout 0` throughout.

**Two things this document got wrong.**

**1. `AUTOINSTALL="no"` does not disable autoinstall.** From `/usr/sbin/dkms`
(3.0.10, Debian bookworm) line 2225:

```sh
# if the module does not want to be autoinstalled, skip it.
if [[ ! $AUTOINSTALL ]]; then
    continue
fi
```

That tests for **empty**, not for `"no"`. Any non-empty value is truthy, so
`"no"` behaves exactly like `"yes"`. To genuinely disable it the variable must be
absent or empty. The staged `dkms.conf` did carry `AUTOINSTALL="no"` — checked on
disk, so this is dkms semantics and not a lost setting.

The upshot is mixed: the cross-kernel **automatic** rebuild was demonstrated,
successfully and unintentionally — dkms built and installed for both
`6.12.96+rpt-rpi-v8` and `6.12.96+rpt-rpi-2712` from the kernel postinst by
itself — but the safety measure we believed we had was never in effect.

**2. The upgrade leg failed for a reason that had nothing to do with DKMS, and
the failure was procedural.** `apt-get -y full-upgrade` was run detached, with no
tty and no conffile policy. dpkg hit a conffile prompt on
`/etc/initramfs-tools/initramfs.conf` and died with `end of file on stdin at
conffile prompt`. `initramfs-tools` never configured, so
`linux-image-6.12.96+rpt-rpi-v8` never configured, so **its postinst never ran and
no `modules.dep` was generated for the new kernel**. The board booted 6.12.96
with zero loadable modules — no `brcmfmac`, therefore no `wlan0`, therefore it
disappeared from the network for twenty minutes.

`-y` answers apt, not dpkg. Any unattended upgrade in this procedure needs

```sh
DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confold full-upgrade
```

and the repair for a system already in that state is the same options with
`dpkg --configure -a` followed by `apt-get --fix-broken install`.

The important consequence is evidential: the "no morse on the new kernel"
observation taken immediately after that reboot proved nothing about
`AUTOINSTALL`, because no module of any kind could load. An elimination is only
valid in the state it was measured in. The real answer came after the repair, and
it was the opposite.

**Recovery path that worked** — worth keeping, because the board was unreachable
on every wireless path: the `eth0` static `10.42.0.2/24` profile. Moving the
laptop's USB-Ethernet to the board's RJ45 reached it in one ping. That profile is
`ipv4.method=manual` on purpose; a DHCP-based one would have failed after ~45 s.

**Still not covered:** the MM6108**A1** hardware. This ran on the A2 HAT only.
