#!/bin/bash
# First-boot provisioning for the HT-HC01P port board (Raspberry Pi OS Lite
# bookworm 2024-11-19, kernel 6.6.51).  Runs once from cmdline.txt via
#   systemd.run=/boot/firmware/firstrun.sh systemd.run_success_action=reboot
#   systemd.unit=kernel-command-line.target
# and deletes itself and its payload afterwards.
#
# Deliberately does NOT touch SPI or anything Morse-related: stage 1's gate is
# "the Pi boots and is reachable", nothing more.
set +e

HASH='__PASSWORD_HASH__'   # substituted by apply-to-card.sh from secrets.env
NEWUSER=alan
FW=/boot/firmware

log() { echo "firstrun: $*" >&2; }

# ---------------------------------------------------------------- hostname
OLD_HOSTNAME=$(cat /etc/hostname 2>/dev/null | tr -d " \t\n\r")
echo hc01p >/etc/hostname
sed -i "s/127\.0\.1\.1.*$OLD_HOSTNAME/127.0.1.1\thc01p/g" /etc/hosts
grep -q "127.0.1.1" /etc/hosts || echo -e "127.0.1.1\thc01p" >>/etc/hosts

# ---------------------------------------------------------------- user
# The image may ship a uid-1000 user to rename, or none at all.  Handle both.
FIRSTUSER=$(getent passwd 1000 | cut -d: -f1)
if [ -z "$FIRSTUSER" ]; then
    log "no uid-1000 user, creating $NEWUSER"
    useradd -m -u 1000 -s /bin/bash "$NEWUSER"
    for g in adm dialout cdrom sudo audio video plugdev games users input render netdev gpio i2c spi lpadmin; do
        getent group "$g" >/dev/null 2>&1 && usermod -aG "$g" "$NEWUSER"
    done
    echo "$NEWUSER:$HASH" | chpasswd -e
elif [ "$FIRSTUSER" != "$NEWUSER" ]; then
    log "renaming $FIRSTUSER to $NEWUSER"
    if [ -x /usr/lib/userconf-pi/userconf ]; then
        /usr/lib/userconf-pi/userconf "$NEWUSER" "$HASH"
    else
        usermod -l "$NEWUSER" "$FIRSTUSER"
        usermod -m -d "/home/$NEWUSER" "$NEWUSER"
        groupmod -n "$NEWUSER" "$FIRSTUSER"
        echo "$NEWUSER:$HASH" | chpasswd -e
    fi
else
    echo "$NEWUSER:$HASH" | chpasswd -e
fi

# passwordless sudo, matching the station board
if [ -f /etc/sudoers.d/010_pi-nopasswd ]; then
    sed -i "s/^[a-z][a-z0-9-]* /$NEWUSER /" /etc/sudoers.d/010_pi-nopasswd
else
    echo "$NEWUSER ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/010_${NEWUSER}-nopasswd
    chmod 440 /etc/sudoers.d/010_${NEWUSER}-nopasswd
fi

# make sure the interactive first-boot wizard never runs
[ -x /usr/bin/cancel-rename ] && /usr/bin/cancel-rename "$NEWUSER"
systemctl disable userconfig.service >/dev/null 2>&1

# ---------------------------------------------------------------- ssh
install -d -m 700 -o "$NEWUSER" -g "$NEWUSER" "/home/$NEWUSER/.ssh"
if [ -f "$FW/authorized_keys" ]; then
    install -m 600 -o "$NEWUSER" -g "$NEWUSER" \
        "$FW/authorized_keys" "/home/$NEWUSER/.ssh/authorized_keys"
fi
systemctl enable ssh >/dev/null 2>&1
touch "$FW/ssh"          # sshswitch.service picks this up too, then removes it

# ---------------------------------------------------------------- networking
NMDIR=/etc/NetworkManager/system-connections
install -d -m 755 "$NMDIR"
for f in sun eth0; do
    [ -f "$FW/$f.nmconnection" ] && \
        install -m 600 -o root -g root "$FW/$f.nmconnection" "$NMDIR/$f.nmconnection"
done

# Raspberry Pi OS keeps the WLAN rfkill-blocked until a country is chosen.
# The country itself comes from cfg80211.ieee80211_regdom=TW in cmdline.txt;
# NetworkManager is not running yet under kernel-command-line.target, so the
# unblock has to be done on the files it reads at boot.
if [ -x /usr/sbin/rfkill ]; then /usr/sbin/rfkill unblock all; fi
for f in /var/lib/systemd/rfkill/*:wlan; do [ -e "$f" ] && echo 0 >"$f"; done
if [ -f /var/lib/NetworkManager/NetworkManager.state ]; then
    sed -i 's/^WirelessEnabled=.*/WirelessEnabled=true/' /var/lib/NetworkManager/NetworkManager.state
else
    install -d -m 755 /var/lib/NetworkManager
    printf '[main]\nNetworkingEnabled=true\nWirelessEnabled=true\nWWANEnabled=true\n' \
        >/var/lib/NetworkManager/NetworkManager.state
fi

# ---------------------------------------------------------------- cleanup
rm -f "$FW/firstrun.sh" "$FW/authorized_keys" "$FW/sun.nmconnection" "$FW/eth0.nmconnection"
sed -i 's| systemd\.run.*||g' "$FW/cmdline.txt"
sync
exit 0
