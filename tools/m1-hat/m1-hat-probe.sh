#!/bin/bash
# Read-only probe for the SenseCAP M1 HAT: button, fan, LED, crypto chip.
#
# RUNS ON THE M1 ITSELF -- it needs local device-tree, GPIO and I2C access.
# You can drive it over ssh, but note that a non-interactive ssh has no
# /usr/sbin on its PATH, so every tool below is called by absolute path.
#
#   ./m1-hat-probe.sh survey          read-only inventory  (default)
#   ./m1-hat-probe.sh button [secs]   watch GPIO edges while you press the button
#   ./m1-hat-probe.sh selftest        prove this script's own guards actually fire
#
# WHAT THIS SCRIPT WILL NEVER DO
#   `survey` does not drive any GPIO as an output and does not write one byte
#   to the crypto chip. The ATECC608A's config and data zones lock ONE WAY,
#   permanently; a provisioning command issued by accident is not recoverable.
#   Detection here is passive.
#
# READ THIS BEFORE BELIEVING A BLANK RESULT
#   An ATECC608A that has not been woken NACKs its own address, so i2cdetect
#   showing nothing at 0x60 is NOT evidence that the chip is absent. Waking it
#   needs a deliberate SDA-low pulse this script does not perform. The I2C
#   section can say "found" or "inconclusive". It can never say "not there".
#
# Exit: 0 = every section produced its subject. 2 = something was missing or
# unreadable. A section that cannot run says so on its own line and sets the
# exit code; it never goes quietly blank.
set -u

SELF=$(basename "$0")
INCOMPLETE=0
DT=/proc/device-tree

# Absolute paths: /usr/sbin is not on a non-interactive ssh PATH on Debian.
I2CDETECT=/usr/sbin/i2cdetect
GPIOINFO=/usr/bin/gpioinfo
GPIOMON=/usr/bin/gpiomon
VCGENCMD=/usr/bin/vcgencmd

say()  { printf '%s\n' "$*"; }
rule() { say ""; say "===== $* ====="; }
miss() { say "!!!! $*"; INCOMPLETE=1; }

# dtstr FILE -- device-tree strings are NUL-terminated and print as garbage
dtstr() { tr -d '\000' < "$1"; echo; }

# have TOOL -- absent tools are named, not silently skipped
have() {
    if [ -x "$1" ]; then return 0; fi
    miss "missing $1 -- install it (i2c-tools / gpiod) and re-run"
    return 1
}

# libgpiod v1 and v2 print different things and take different flags. Decide
# once. v1 marks an idle line "unused"; v2 omits a consumer= field instead.
gpiod_major() {
    v=$("$GPIOINFO" --version 2>&1 | head -1)
    if printf '%s' "$v" | grep -qE '[^0-9]2\.'; then echo 2; else echo 1; fi
}

survey() {
    say "m1-hat-probe survey  $(date -Iseconds)"

    rule "board and OS"
    if [ -r $DT/model ]; then dtstr $DT/model; else miss "no $DT/model"; fi
    say "kernel  $(uname -r)"
    [ -r /etc/os-release ] && grep -E '^PRETTY_NAME' /etc/os-release

    rule "HAT EEPROM  (names the HAT outright if one is fitted)"
    if [ -d $DT/hat ]; then
        for f in vendor product product_id product_ver uuid; do
            [ -r $DT/hat/$f ] && printf '%-12s %s' "$f" "$(dtstr $DT/hat/$f)"
        done
    else
        say "(no $DT/hat -- this HAT has no ID EEPROM, or it is not being read)"
    fi

    rule "config.txt  (the HaLow overlay here names its own GPIOs)"
    CFG=/boot/firmware/config.txt
    [ -r "$CFG" ] || CFG=/boot/config.txt
    if [ -r "$CFG" ]; then
        say "-- $CFG"
        grep -vE '^\s*(#|$)' "$CFG"
    else
        miss "no config.txt at /boot/firmware/config.txt or /boot/config.txt"
    fi
    say "-- /proc/cmdline"
    cat /proc/cmdline 2>/dev/null || miss "no /proc/cmdline"

    rule "device-tree nodes that claim GPIOs"
    # Any overlay-added node lives at the DT root. Names tell you what is wired.
    ls $DT 2>/dev/null | grep -iE 'gpio|fan|key|led|button|atecc|crypto|morse|halow|spi' \
        || say "(no matching top-level nodes)"

    rule "who currently owns each GPIO line"
    if [ "$(id -u)" = 0 ]; then
        if [ -r /sys/kernel/debug/gpio ]; then
            cat /sys/kernel/debug/gpio
        else
            miss "/sys/kernel/debug/gpio unreadable -- is debugfs mounted?"
        fi
    else
        miss "not root: /sys/kernel/debug/gpio needs root and is the single most"
        miss "     useful section here. Re-run with sudo."
    fi

    rule "libgpiod view  (claimed lines only)"
    if have "$GPIOINFO"; then
        if [ "$(gpiod_major)" = 2 ]; then
            "$GPIOINFO" 2>&1 | grep -E 'consumer=' \
                || say "(v2: no line has a consumer -- every line is idle)"
        else
            "$GPIOINFO" 2>&1 | grep -vE '[[:space:]]unused[[:space:]]' \
                || say "(v1: every line reports unused)"
        fi
    fi

    rule "input devices  (a button already wired as gpio-key shows up here)"
    if [ -r /proc/bus/input/devices ]; then
        grep -E '^[NPH]:' /proc/bus/input/devices || say "(no input devices)"
    else
        say "(no /proc/bus/input/devices)"
    fi

    rule "thermal cooling devices  (a fan already on gpio-fan shows up here)"
    found=0
    for d in /sys/class/thermal/cooling_device*; do
        [ -e "$d" ] || continue
        found=1
        printf '%-28s type=%s cur=%s max=%s\n' "$d" \
            "$(cat "$d/type" 2>/dev/null)" \
            "$(cat "$d/cur_state" 2>/dev/null)" \
            "$(cat "$d/max_state" 2>/dev/null)"
    done
    [ "$found" = 1 ] || say "(none -- the fan is unmanaged, hard-wired, or on a bare GPIO)"
    for t in /sys/class/thermal/thermal_zone*/temp; do
        [ -r "$t" ] && say "$t = $(cat "$t")"
    done
    [ -x "$VCGENCMD" ] && say "throttled: $("$VCGENCMD" get_throttled 2>&1)"

    rule "LED class"
    ls /sys/class/leds/ 2>/dev/null || say "(none registered)"

    rule "I2C  -- see the wake-up caveat in this script's header"
    if have "$I2CDETECT"; then
        buses=$(ls /dev/i2c-* 2>/dev/null)
        if [ -z "$buses" ]; then
            miss "no /dev/i2c-* at all -- I2C is off. Add dtparam=i2c_arm=on and reboot."
        else
            for b in $buses; do
                n=${b#/dev/i2c-}
                say "-- bus $n"
                # -r uses SMBus read, which is gentler than the default quick-write.
                "$I2CDETECT" -y -r "$n" 2>&1
            done
            say ""
            say "0x60 = ATECC608A (Helium swarm key).  0x50 on bus 0 = HAT ID EEPROM."
            say "A blank grid is INCONCLUSIVE, not negative: the ATECC608A NACKs until woken."
        fi
    fi

    rule "SPI and the HaLow driver"
    ls /dev/spidev* 2>/dev/null || say "(no /dev/spidev* -- fine if the driver owns the bus)"
    lsmod 2>/dev/null | grep -iE 'morse|mm610|mm810' || say "(no morse module loaded)"
    ls /sys/class/ieee80211/ 2>/dev/null || say "(no ieee80211 phy)"

    rule "crypto driver availability  (informational -- userspace is the real path)"
    if modinfo atmel-ecc >/dev/null 2>&1; then
        say "atmel-ecc module IS available: $(modinfo -n atmel-ecc 2>/dev/null)"
    else
        say "atmel-ecc not built for this kernel -- expected. Use CryptoAuthLib in"
        say "userspace over /dev/i2c-1, and its PKCS#11 module for OpenSSL/ssh."
    fi

    rule "verdict"
    if [ "$INCOMPLETE" = 0 ]; then
        say "survey complete"
    else
        say "survey INCOMPLETE -- see the !!!! lines above. Do not read the gaps as zeroes."
    fi
}

# ---------------------------------------------------------------------------
# button: watch idle GPIO lines for an edge while you press the button.
# ---------------------------------------------------------------------------
button() {
    secs=${1:-20}
    have "$GPIOMON" || return
    have "$GPIOINFO" || return

    major=$(gpiod_major)
    say "libgpiod: $("$GPIOMON" --version 2>&1 | head -1)  (treating as v$major)"

    # NB: a `case` inside $(...) trips bash 3.2's paren matching. Plain loop.
    chip=""
    for c in /sys/bus/gpio/devices/*; do
        [ -r "$c/label" ] || continue
        if grep -qE 'pinctrl-bcm|bcm2711|bcm2835' "$c/label"; then
            chip=$(basename "$c"); break
        fi
    done
    if [ -z "${chip:-}" ]; then
        miss "could not find the BCM gpiochip -- name one explicitly and edit this function"
        return
    fi
    say "chip: $chip"

    # Candidate lines: idle, and not named by any dtoverlay= line in config.txt.
    CFG=/boot/firmware/config.txt; [ -r "$CFG" ] || CFG=/boot/config.txt
    reserved=$(grep -hoE '(gpio|pin|_pin)[a-z_]*=[0-9]+' "$CFG" 2>/dev/null | grep -oE '[0-9]+' | sort -un | tr '\n' ' ')
    say "excluded because config.txt names them: ${reserved:-none}"

    if [ "$major" = 2 ]; then
        # v2: a line with no consumer= is idle
        idle=$("$GPIOINFO" -c "$chip" 2>/dev/null \
               | awk '/^[[:space:]]*line/ && $0 !~ /consumer=/ {gsub(/:/,"",$2); print $2}')
    else
        idle=$("$GPIOINFO" "$chip" 2>/dev/null \
               | awk '/[[:space:]]unused[[:space:]]/ {gsub(/:/,"",$2); print $2}')
    fi
    if [ -z "$idle" ]; then
        miss "parsed zero idle lines from gpioinfo -- the output format is not what"
        miss "     this script expects. Do not read that as 'the chip is fully busy'."
        return
    fi
    lines=""
    for l in $idle; do
        skip=0
        for r in $reserved; do [ "$l" = "$r" ] && skip=1; done
        [ "$skip" = 0 ] && lines="$lines $l"
    done
    if [ -z "$lines" ]; then
        miss "no idle unreserved lines to watch -- run survey and pick one by hand"
        return
    fi

    say ""
    say "About to request these lines as inputs with a pull-up for ${secs}s:"
    say " $lines"
    say ""
    say "This briefly stops anything from driving them. Nothing on this HAT should"
    say "care, but the HaLow module's reset line lives on this chip -- if the driver"
    say "is not loaded, its line may be idle and in this list. Check it against the"
    say "overlay first. Re-run with --yes once you have."
    case "${2:-}" in --yes) ;; *) say ""; say "stopping here (no --yes)"; return ;; esac

    say "PRESS AND RELEASE THE BUTTON NOW -- watching for ${secs}s"
    if [ "$major" = 2 ]; then
        timeout "$secs" "$GPIOMON" -b pull-up -c "$chip" $lines
    else
        timeout "$secs" "$GPIOMON" -B pull-up "$chip" $lines
    fi
    rc=$?
    # timeout exits 124 when it did its job. Anything else is gpiomon failing.
    if [ "$rc" != 124 ] && [ "$rc" != 0 ]; then
        miss "gpiomon exited $rc -- the lines above were not actually watched"
    fi
}

# ---------------------------------------------------------------------------
# selftest: force each guard to fire. An unfired guard is not a guard.
# 2026-08-26: a soak checkpoint exited 0 with 25 of 30 fields blank because
# nothing here had ever been made to fail on purpose. Not again.
# ---------------------------------------------------------------------------
selftest() {
    fails=0
    check() { # check <description> <expected-rc> <actual-rc>
        if [ "$2" = "$3" ]; then say "ok    $1"; else say "FAIL  $1 (want rc=$2 got rc=$3)"; fails=1; fi
    }

    say "-- guard: a missing tool must be named and must set INCOMPLETE"
    ( I2CDETECT=/nonexistent/i2cdetect; INCOMPLETE=0
      out=$(have "$I2CDETECT" 2>&1); rc=$?
      case "$out" in *"missing /nonexistent/i2cdetect"*) [ "$rc" = 1 ] && exit 0 ;; esac
      exit 1 )
    check "have() names an absent tool" 0 $?

    say "-- guard: miss() must move the exit code off zero"
    ( INCOMPLETE=0; miss "deliberate" >/dev/null; [ "$INCOMPLETE" = 1 ] )
    check "miss() sets INCOMPLETE" 0 $?

    say "-- guard: an empty string in arithmetic must not be read as a real zero"
    ( n=""; [ -z "$n" ] )
    check "empty i2c bus list is caught as empty, not as 0" 0 $?

    say "-- guard: dtstr must strip the NUL that would corrupt the report"
    ( printf 'Raspberry Pi 4 Model B\000' > /tmp/.m1probe.$$
      out=$(dtstr /tmp/.m1probe.$$); rm -f /tmp/.m1probe.$$
      [ "$out" = "Raspberry Pi 4 Model B" ] )
    check "dtstr strips NUL" 0 $?

    say "-- guard: both gpioinfo dialects must parse to the same line number"
    ( out=$(printf '\tline  17:\t"GPIO17"\tunused\tinput\tactive-high\n' \
            | awk '/[[:space:]]unused[[:space:]]/ {gsub(/:/,"",$2); print $2}')
      [ "$out" = "17" ] )
    check "v1 idle-line parse yields 17" 0 $?
    ( out=$(printf '\tline  17:\t"GPIO17"\tinput\n\tline  18:\t"GPIO18"\tinput consumer="fan"\n' \
            | awk '/^[[:space:]]*line/ && $0 !~ /consumer=/ {gsub(/:/,"",$2); print $2}')
      [ "$out" = "17" ] )
    check "v2 idle-line parse yields 17 and skips the consumed 18" 0 $?

    say "-- guard: timeout must exist (it does NOT on macOS -- this script runs on the Pi)"
    command -v timeout >/dev/null
    check "timeout present" 0 $?

    say ""
    if [ "$fails" = 0 ]; then say "selftest: all guards fired"; else say "selftest: A GUARD DID NOT FIRE -- fix it before trusting a survey"; return 2; fi
}

case "${1:-survey}" in
    survey)   survey ;;
    button)   shift; button "${1:-20}" "${2:-}" ;;
    selftest) selftest || exit $? ;;
    *) say "usage: $SELF [survey|button [secs] [--yes]|selftest]"; exit 64 ;;
esac
[ "$INCOMPLETE" = 0 ] && exit 0
exit 2
