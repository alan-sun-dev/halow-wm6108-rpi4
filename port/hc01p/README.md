# HT-HC01P → Raspberry Pi OS

**Done, 2026-08-25.** The board runs Raspberry Pi OS bookworm with morse_driver
2.0.1 plus this repo's three `patches/upstream/` fixes, associated to the
OpenMANET AP with SAE + PMF at `10.41.0.216`, and it comes up unattended from a
cold start. **Verified on two kernels — 6.6.51 and 6.12.96** — with the same
driver source; it currently runs 6.12.96 and both are installed. Full account in [NOTES.md](../../NOTES.md) under 2026-08-25; the
verdict tables in
[`heltec-hc01p-linux-port-analysis.md`](../../heltec-hc01p-linux-port-analysis.md)
record what was predicted against what happened.

The port swapped **SD cards**. Heltec's OpenWrt install is intact on its own,
labelled card — it is the only other copy of `bcf_HC01_V2_H.bin`, and Heltec's
own download page serves a different, broken file (see
[`firmware/heltec-hc01p/`](../../firmware/heltec-hc01p/)). While this card is in
the slot the OpenWrt node is simply gone; that is expected, not a fault.

## Installed configuration

```
image      2024-11-19-raspios-bookworm-arm64-lite
kernel     6.12.96+rpt-rpi-v8 running; 6.6.51+rpt-rpi-v8 also installed
overlay    dtoverlay=mm610x-spi-hc01p       (NOT dtparam=spi=on — see below)
cmdline    cfg80211.ieee80211_regdom=TW     (for the brcmfmac interface only)
driver     /lib/modules/<both kernels>/updates/{morse,dot11ah}.ko
firmware   /lib/firmware/morse/mm6108.bin              468304 B  crc32 0xbe7b5c8f
BCF        /lib/firmware/morse/bcf_HC01_V2_H.bin         1170 B  crc32 0x389a48c4
modprobe   options morse country=SG bcf=bcf_HC01_V2_H.bin macaddr_suffix=40:8e:91
NM         sun    wlan0 → house SSID, priority 20
           halow  bound to MAC 0C:BF:74:40:8E:91, sae, pmf 3,
                  wifi.powersave 2, ipv4.never-default yes
           eth0-bench  DHCP plus a fixed 10.42.0.2/24, priority 100
```

Four things in there are load-bearing and easy to get wrong:

- **No `dtparam=spi=on`.** The overlay enables `&spi0` itself. The `dtparam` would
  bring back the stock `spi0_cs_pins` group of `<8 7>`, and GPIO 7 is MM_BUSY on
  this HAT.
- **`spi-max-frequency` stays at 50 MHz.** Lowering it is what breaks this driver,
  not what makes it safe — the delay formula only lands on the right value there.
- **`macaddr_suffix` is not optional.** Without it the driver invents a random MAC
  at every load.
- **`enable_ps` is deliberately absent** from `morse.conf`. The driver logs that
  the modparam is for testing only; power save is disabled by the NetworkManager
  profile instead, the mechanism already proven persistent on the other boards.

## Reaching it

1. **House Wi-Fi** — primary. `ssh alan@hc01p.local`, or find it by the Pi 4's
   `wlan0` MAC `e4:5f:01:40:8e:93`.
2. **Ethernet** — backup, needs no house network. Move `en5` to this Pi's RJ45,
   then `sudo ifconfig en5 alias 10.42.0.100 netmask 255.255.255.0` on the Mac
   (the `netmask` keyword is required; without it macOS assigns /8 and swallows
   `10.41.0.0/16`), and `ssh alan@10.42.0.2`. Untested as of 2026-08-25 — the
   Wi-Fi path has never needed it, and `en5` is the scarce resource.
3. **HaLow** — `ssh alan@10.41.0.216` from a host on the `10.41.0.0/16` segment.

## Files here

**The two secrets are not in git.** `boot/firstrun.sh` and
`boot/sun.nmconnection` carry `__PASSWORD_HASH__` and `__WIFI_PSK__`
placeholders; copy `secrets.env.example` to `secrets.env` (gitignored) and fill it
in, and `apply-to-card.sh` substitutes them into the copies it writes to the card,
never into the working tree. It refuses to finish if a placeholder would survive
onto the card.

```
boot/firstrun.sh                 first-boot provisioning, deletes itself
boot/authorized_keys             the Mac's ed25519 public key
boot/sun.nmconnection            wlan0 → house SSID
boot/eth0.nmconnection           eth0 → DHCP + 10.42.0.2/24
secrets.env.example              template for the two values kept out of git
apply-to-card.sh                 copies the above onto /Volumes/bootfs, substitutes
                                 the secrets, edits cmdline.txt
instrument-initsequence.patch    4 log calls used to prove defect B is the same
                                 mechanism here as on the Wio-WM6108.
                                 Instrumentation only — never send this upstream.
```

## Rebuilding the driver on the board

The 2024-11-19 image already ships matching `linux-headers`, so nothing has to be
transplanted. `git`, `build-essential` and `bc` were the only additions. To build
for a kernel other than the running one, point `KERNEL_SRC` at it — that is how
the 6.12 module was built while still running 6.6.51, which keeps the risky step
(the reboot) separate from the step that can fail loudly (the build).

```sh
cd ~/halow-test/morse_driver          # tag mm6108-2.0.1, commit 98e1936
git submodule update --init --recursive   # mmrc-submodule, or the build fails oddly
for p in ~/halow-test/000*.patch; do git apply "$p"; done
make KERNEL_SRC=/lib/modules/$(uname -r)/build \
     CONFIG_WLAN_VENDOR_MORSE=m CONFIG_MORSE_SPI=y \
     CONFIG_MORSE_USER_ACCESS=y CONFIG_MORSE_VENDOR_COMMAND=y \
     CONFIG_MORSE_DEBUGFS=y -j4
sudo install -m 644 morse.ko dot11ah/dot11ah.ko /lib/modules/$(uname -r)/updates/
sudo depmod -a
```

Build logs go in `~/halow-test/buildlogs/` on the board, **not `/tmp`** — a reboot
clears `/tmp` and the evidence for the 6.12 run had to be regenerated once because
of that.

**On upgrading.** The original advice here was "do not `apt full-upgrade`",
to keep this board on the station board's kernel while the port was being
established. That is done and recorded, so the freeze has been lifted — the board
was deliberately taken to 6.12.96 to test the patched driver on a second kernel,
and it works. Two things worth keeping from how that was done:

- `apt upgrade` holds the kernel back on its own (a kernel bump needs a *new*
  package), so it is the safe way to take security updates without touching the
  module. Run it detached — `systemd-run --unit=... apt-get -y upgrade` — because
  the NetworkManager upgrade restarts the service and a dropped SSH session must
  not be able to interrupt dpkg.
- Before a kernel change, copy the running `kernel8.img` and `initramfs8` to
  suffixed names on the FAT boot partition. If the new kernel will not boot, the
  card can be mounted on a laptop and `config.txt` pointed back with
  `kernel=kernel8-6.6.51.img` / `initramfs initramfs8-6.6.51`. `rpi-eeprom` is
  held (`apt-mark hold`) so the bootloader stays out of the experiment.

**The station board stays on 6.6.51** so the same-kernel comparison still exists.
