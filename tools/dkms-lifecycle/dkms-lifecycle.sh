#!/bin/bash
# DKMS lifecycle validation harness for the morse_driver portability fork.
#
# Runs ON THE TEST BOARD. Each leg is a separate invocation because the
# lifecycle contains two reboots; drive it from the laptop, one leg at a time,
# and read the record between legs.
#
#   ./dkms-lifecycle.sh snapshot <label>   record state, no change
#   ./dkms-lifecycle.sh add
#   ./dkms-lifecycle.sh build
#   ./dkms-lifecycle.sh install
#   ./dkms-lifecycle.sh halow
#   ./dkms-lifecycle.sh build-for <kernelrelease>   cross-kernel rebuild
#   ./dkms-lifecycle.sh uninstall
#   ./dkms-lifecycle.sh rollback-check
#
# Everything is appended to ~/halow-test/dkms-lifecycle-record.txt, never /tmp:
# this survives the reboots the test depends on.
set -u

REC=~/halow-test/dkms-lifecycle-record.txt
DKMS=/usr/sbin/dkms          # not on a non-root PATH on Debian
SRC=${SRC:-~/halow-test/fork-build}
mkdir -p ~/halow-test

say() { printf '%s\n' "$*" | tee -a "$REC"; }
rule() { say ""; say "===== $* ====="; say "at $(date -Iseconds)  kernel $(uname -r)  uptime $(cut -d. -f1 /proc/uptime)s"; }

halow_iface() {
    for i in /sys/class/net/*/device/driver; do
        case "$(readlink -f "$i")" in *morse_spi*) echo "$i" | cut -d/ -f5; return;; esac
    done
}

snapshot() {
    rule "SNAPSHOT ${1:-unlabelled}"
    say "kernel running : $(uname -r)"
    say "kernels present: $(ls -d /lib/modules/*/ | tr '\n' ' ')"
    say "boot_id        : $(cat /proc/sys/kernel/random/boot_id)"
    say "held packages  : $(apt-mark showhold | tr '\n' ' ')"

    say "-- loaded module --"
    if [ -d /sys/module/morse ]; then
        say "  version    : $(cat /sys/module/morse/version 2>/dev/null)"
        say "  srcversion : $(cat /sys/module/morse/srcversion 2>/dev/null)"
        say "  lsmod      : $(lsmod | grep -E '^morse|^dot11ah' | tr '\n' '|')"
    else
        say "  (morse not loaded)"
    fi

    say "-- module files on disk (all kernels) --"
    # .ko may be .ko.xz; match both or the search silently finds nothing
    find /lib/modules -path '*/updates/*' \( -name 'morse.ko*' -o -name 'dot11ah.ko*' \) 2>/dev/null |
        sort | while read -r f; do say "  $f  $(stat -c '%s bytes %y' "$f" | cut -d. -f1)"; done
    say "-- modules.dep --"
    grep -hE 'morse|dot11ah' /lib/modules/*/modules.dep 2>/dev/null | cut -d: -f1 | sort -u |
        while read -r l; do say "  $l"; done

    say "-- dkms --"
    if [ -x "$DKMS" ]; then
        say "  version: $($DKMS --version 2>/dev/null)"
        sudo $DKMS status 2>/dev/null | while read -r l; do say "  status: $l"; done
        find /var/lib/dkms -path '*module*' \( -name '*.ko' -o -name '*.ko.xz' \) 2>/dev/null |
            while read -r f; do say "  built: $f ($(stat -c %s "$f") bytes)"; done
        ls -d /usr/src/morse-* 2>/dev/null | while read -r d; do say "  staged: $d"; done
    else
        say "  dkms not installed"
    fi

    say "-- link --"
    IF=$(halow_iface)
    if [ -n "${IF:-}" ]; then
        say "  iface $IF  mac $(cat /sys/class/net/"$IF"/address)  addr $(ip -4 -br addr show "$IF" | awk '{print $3}')"
        say "  $(/sbin/iw dev "$IF" link | head -1)"
        say "  power_save: $(/sbin/iw dev "$IF" get power_save 2>/dev/null)"
    else
        say "  no interface bound to morse_spi"
    fi
    say "  SPI errors/timedout/messages: $(cat /sys/class/spi_master/spi0/spi0.0/statistics/errors 2>/dev/null)/$(cat /sys/class/spi_master/spi0/spi0.0/statistics/timedout 2>/dev/null)/$(cat /sys/class/spi_master/spi0/spi0.0/statistics/messages 2>/dev/null)"
}

pkg_version() {
    ls -d /usr/src/morse-* 2>/dev/null | head -1 | sed 's|.*/morse-||'
}

case "${1:-}" in
snapshot)  snapshot "${2:-}" ;;

add)
    rule "LEG 1 — stage + dkms add"
    sudo "$SRC/packaging/dkms/prepare-source.sh" 2>&1 | tee -a "$REC"
    V=$(pkg_version); say "package version: $V"
    sudo $DKMS add "morse/$V" 2>&1 | tee -a "$REC"
    snapshot "after add" ;;

build)
    rule "LEG 2 — dkms build (running kernel)"
    V=$(pkg_version)
    sudo $DKMS build "morse/$V" 2>&1 | tail -20 | tee -a "$REC"
    snapshot "after build" ;;

install)
    rule "LEG 3 — dkms install"
    V=$(pkg_version)
    sudo $DKMS install "morse/$V" 2>&1 | tail -20 | tee -a "$REC"
    say "-- what install put where --"
    find /lib/modules -path '*/updates/*' \( -name 'morse.ko*' -o -name 'dot11ah.ko*' \) 2>/dev/null |
        while read -r f; do say "  $f -> $(readlink -f "$f")"; done
    snapshot "after install" ;;

halow)
    rule "FUNCTIONAL — HaLow"
    IF=$(halow_iface)
    if [ -z "${IF:-}" ]; then say "FAIL: no morse_spi interface"; exit 1; fi
    say "-- boot log --"
    sudo dmesg | grep -iE 'morse micro driver registration|Loaded firmware|Loaded BCF|Resetting Morse|authenticated|associated' |
        while read -r l; do say "  $l"; done
    say "-- failure lines (with a positive control) --"
    say "  matches cmd63|eproto|crc error|read fail|write fail|probe fail: $(sudo dmesg | grep -icE 'cmd63|eproto|crc error|read fail|write fail|probe fail')"
    say "  positive control, morse_spi lines: $(sudo dmesg | grep -c morse_spi)"
    say "-- ping the AP over the air --"
    GW=$(ip -4 route show dev "$IF" | awk '/scope link/{print $1}' | head -1)
    say "  $(ping -c 20 -i 0.3 10.41.254.1 2>&1 | tail -2 | tr '\n' ' ')"
    snapshot "functional check" ;;

build-for)
    K=${2:?usage: build-for <kernelrelease>}
    rule "LEG 4 — rebuild for another kernel: $K"
    V=$(pkg_version)
    sudo $DKMS install "morse/$V" -k "$K" 2>&1 | tail -20 | tee -a "$REC"
    snapshot "after cross-kernel install for $K" ;;

uninstall)
    rule "LEG 5 — uninstall and remove"
    V=$(pkg_version)
    sudo $DKMS uninstall "morse/$V" --all 2>&1 | tail -10 | tee -a "$REC"
    sudo $DKMS remove "morse/$V" --all 2>&1 | tail -10 | tee -a "$REC"
    snapshot "after uninstall+remove" ;;

rollback-check)
    rule "ROLLBACK VERIFICATION"
    say "expected: no morse/dot11ah under any updates/, no dkms morse entry,"
    say "          /usr/src/morse-* may remain until removed by hand"
    N=$(find /lib/modules -path '*/updates/*' \( -name 'morse.ko*' -o -name 'dot11ah.ko*' \) 2>/dev/null | wc -l)
    say "module files still present: $N"
    find /lib/modules -path '*/updates/*' \( -name 'morse.ko*' -o -name 'dot11ah.ko*' \) 2>/dev/null |
        while read -r f; do say "  LEFTOVER $f"; done
    say "dkms status: $(sudo $DKMS status 2>/dev/null | grep morse || echo '(none)')"
    say "staged tree: $(ls -d /usr/src/morse-* 2>/dev/null || echo '(none)')"
    snapshot "after rollback" ;;

*) sed -n '2,20p' "$0"; exit 1 ;;
esac

say ""
say "record: $REC"
