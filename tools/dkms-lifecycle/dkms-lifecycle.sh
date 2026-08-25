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
#   ./dkms-lifecycle.sh preflight <kernelrelease>   GATE: run before any reboot
#                                                   into a new kernel. Exits
#                                                   non-zero if it is not safe.
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


preflight() {
    K=${1:?usage: preflight <kernelrelease>}
    rule "PREFLIGHT GATE for $K"
    say "Nothing may reboot into a new kernel until every line below says PASS."
    fail=0
    chk() { # chk <label> <PASS|FAIL> <detail>
        say "  [$2] $1 -- $3"
        [ "$2" = PASS ] || fail=1
    }

    # 1. dpkg must be clean. A half-configured kernel package is how a machine
    #    ends up booting a kernel whose postinst never ran.
    # Settled states are ii (installed), hi (installed and HELD -- a hold is
    # deliberate, e.g. rpi-eeprom here, and is not a fault), rc (removed, config
    # left), pn/un (not installed). Anything else is half-done.
    broken=$(dpkg -C 2>/dev/null | grep -c .)
    notok=$(dpkg -l 2>/dev/null | awk 'NR>5 && $1 !~ /^(ii|hi|rc|pn|un)$/ {n++} END{print n+0}')
    held=$(apt-mark showhold 2>/dev/null | tr '\n' ' ')
    if [ "$broken" -eq 0 ] && [ "$notok" -eq 0 ]; then
        chk "dpkg clean" PASS "dpkg -C empty, no half-configured packages; held: ${held:-none}"
    else
        chk "dpkg clean" FAIL "dpkg -C lines=$broken, half-configured packages=$notok"
        dpkg -l 2>/dev/null | awk 'NR>5 && $1 !~ /^(ii|hi|rc|pn|un)$/ {print "      " $1, $2}' | while read -r l; do say "$l"; done
    fi

    # 2. modules.dep must exist for the target kernel, with a control entry that
    #    proves it is a real dependency file and not an empty stub.
    DEP=/lib/modules/$K/modules.dep
    if [ -s "$DEP" ]; then
        n=$(wc -l < "$DEP")
        ctl=$(grep -c 'mac80211\|brcmfmac' "$DEP")
        if [ "$ctl" -gt 0 ]; then
            chk "modules.dep for $K" PASS "$n lines, $ctl control entries"
        else
            chk "modules.dep for $K" FAIL "$n lines but no mac80211/brcmfmac -- suspect stub"
        fi
    else
        chk "modules.dep for $K" FAIL "missing or empty: $DEP"
    fi

    # 3. initramfs: initramfs-tools writes /boot/initrd.img-<K>, and on
    #    Raspberry Pi OS raspi-firmware then copies it to the FAT partition as
    #    initramfs8 (or initramfs_2712). The firmware loads THAT copy, so both
    #    must exist and be identical, or the kernel boots against a stale one.
    IMG=/boot/initrd.img-$K
    if [ -s "$IMG" ]; then
        case "$K" in
            *-2712) FW=/boot/firmware/initramfs_2712 ;;
            *)      FW=/boot/firmware/initramfs8 ;;
        esac
        if [ ! -d /boot/firmware ]; then
            chk "initramfs for $K" PASS "$IMG present ($(stat -c %s "$IMG") bytes); no /boot/firmware on this system"
        elif [ ! -s "$FW" ]; then
            chk "initramfs for $K" FAIL "$IMG exists but $FW is missing"
        elif sudo cmp -s "$IMG" "$FW"; then
            chk "initramfs for $K" PASS "$IMG == $FW ($(stat -c %s "$IMG") bytes)"
        else
            chk "initramfs for $K" FAIL "$FW differs from $IMG -- firmware would load a stale initramfs"
        fi
    else
        chk "initramfs for $K" FAIL "missing or empty: $IMG"
    fi

    # 4. headers, or the next kernel cannot be built for at all
    if [ -d "/lib/modules/$K/build" ]; then
        chk "kernel headers for $K" PASS "$(readlink -f /lib/modules/$K/build)"
    else
        chk "kernel headers for $K" FAIL "/lib/modules/$K/build missing"
    fi

    # 5. DKMS must report the package installed for THIS kernel, and both
    #    modules must actually be on disk for it.
    st=$(sudo $DKMS status 2>/dev/null | grep ", $K," | grep -c installed)
    [ "$st" -gt 0 ] && chk "dkms status for $K" PASS "installed" \
                    || chk "dkms status for $K" FAIL "no 'installed' line for $K"
    for m in morse dot11ah; do
        f=$(find /lib/modules/"$K"/updates -name "$m.ko*" 2>/dev/null | head -1)
        [ -n "$f" ] && chk "$m installed for $K" PASS "$f" \
                    || chk "$m installed for $K" FAIL "not found under /lib/modules/$K/updates"
    done

    # 6. modinfo -k is the check that ties file, source and kernel together.
    #    vermagic must name the target kernel, not the running one.
    for m in morse dot11ah; do
        out=$(sudo modinfo -k "$K" "$m" 2>&1)
        if echo "$out" | grep -q '^filename:'; then
            fn=$(echo "$out" | awk '/^filename:/{print $2}')
            sv=$(echo "$out" | awk '/^srcversion:/{print $2}')
            vm=$(echo "$out" | awk -F': *' '/^vermagic:/{print $2}')
            case "$vm" in
                "$K"*) chk "modinfo -k $K $m" PASS "srcversion $sv, vermagic $vm" ;;
                *)     chk "modinfo -k $K $m" FAIL "vermagic '$vm' does not start with $K" ;;
            esac
            say "      filename: $fn"
        else
            chk "modinfo -k $K $m" FAIL "$(echo "$out" | head -1)"
        fi
    done

    say ""
    if [ "$fail" -eq 0 ]; then
        say "GATE: PASS -- safe to reboot into $K"
    else
        say "GATE: FAIL -- do NOT reboot into $K. Fix the FAIL lines first."
    fi
    return $fail
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

preflight) preflight "${2:-}" || exit 1 ;;

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
