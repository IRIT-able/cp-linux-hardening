#!/usr/bin/env bash
# collect.sh - PRACTICE ONLY. Bundles the latest run log plus read-only diagnostics and uploads them to the
# host PC so the scripts can be debugged. Changes nothing on this machine. Never use it in a competition.
#   sudo ./collect.sh [host-url]        default http://172.16.14.1:8001
# Not collected: password hashes, forensics question files, anything from home directories.
set -u
HOST_URL=${1:-http://172.16.14.1:8001}
if (( EUID != 0 )); then echo "Run as root:  sudo $0"; exit 1; fi
D=$(mktemp -d) || exit 1
OUT="$D/cp-collect-$(date +%H%M%S).txt"
sec() { printf '\n########## %s\n' "$*" >>"$OUT"; }
run() { sec "$*"; "$@" >>"$OUT" 2>&1; }
show() { local f; for f in "$@"; do [[ -f $f ]] && { sec "$f"; cat "$f" >>"$OUT" 2>&1; }; done; }

LOG=$(ls -t /root/cp-log-*.txt 2>/dev/null | head -1)
sec "LATEST LOG: ${LOG:-none}"; [[ -n $LOG ]] && cat "$LOG" >>"$OUT"

show /etc/os-release
show /etc/passwd /etc/group
run passwd -S -a
show /etc/login.defs /etc/pam.d/common-auth /etc/pam.d/common-password /etc/pam.d/common-account
run ls -la /usr/share/pam-configs
show /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources
run ls -la /etc/apt/sources.list.d /etc/apt/apt.conf.d
sec "dpkg: browsers, wireshark, servers"; dpkg -l 2>/dev/null | grep -iE 'firefox|chromium|wireshark|vsftpd|nginx|squid|dovecot|openssh|samba|pwquality|unattended|mintupdate' >>"$OUT"
run snap list
show /etc/vsftpd.conf /etc/crontab /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.d/*.conf /etc/sysctl.conf /etc/ufw/sysctl.conf
run ls -la /srv/ftp
run ss -tulnp
run systemctl list-units --type=service --state=running --no-pager
run systemctl list-unit-files --state=enabled --no-pager
run ufw status verbose
run ls -la /etc/sudoers.d /etc/cron.d /etc/systemd/system /opt
sec "Desktop file names (names only)"; ls -1 /home/*/Desktop >>"$OUT" 2>&1
run systemctl is-enabled mintupdate-automation-upgrade.timer
run which mintupdate-automation mintupdate-cli

echo "collected $(wc -c <"$OUT") bytes -> uploading to $HOST_URL"
if curl -fsS -T "$OUT" "$HOST_URL/$(basename "$OUT")"; then echo "uploaded."; else echo "UPLOAD FAILED - the file is at $OUT"; exit 1; fi
rm -rf "$D"
