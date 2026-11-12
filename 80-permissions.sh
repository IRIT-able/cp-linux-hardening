#!/usr/bin/env bash
# 80-permissions.sh - permissions and ownership. Catalog: "File permissions & ownership".
# Auto-fixes only: the account database files, and world-writable regular files under /etc, /usr, /boot.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cp_init "PERMISSIONS" "$@"

check_file() { # path max-mode owner group source
  local p=$1 max=$2 o=$3 g=$4 src=$5 cur own
  [[ -e $p ]] || return 0
  cur=$(stat -c %a "$p"); own=$(stat -c %U:%G "$p")
  if (( (8#$cur & ~8#$max) != 0 )); then fix "chmod $max $p (was $cur) [$src]" chmod "$max" "$p"
  else ok "$p mode $cur"; fi
  [[ $own == "$o:$g" ]] || fix "chown $o:$g $p (was $own) [$src]" chown "$o:$g" "$p"
}

section "Account database and key system files"
STD="Ubuntu default; not in the keys"
check_file /etc/shadow   640 root shadow "answer key"
check_file /etc/gshadow  640 root shadow "$STD"
check_file /etc/passwd   644 root root   "$STD"
check_file /etc/group    644 root root   "$STD"
check_file /etc/shadow-  640 root shadow "$STD"
check_file /etc/gshadow- 640 root shadow "$STD"
check_file /etc/passwd-  644 root root   "$STD"
check_file /etc/group-   644 root root   "$STD"
check_file /etc/sudoers  440 root root   "$STD"
check_file /etc/crontab  644 root root   "$STD"
[[ -f /etc/ssh/sshd_config ]] && check_file /etc/ssh/sshd_config 644 root root "$STD"
for k in /etc/ssh/ssh_host_*_key; do [[ -f $k ]] && check_file "$k" 600 root root "$STD"; done

section "World-writable files in system directories"
n=0
while IFS= read -r -d '' f; do
  is_protected_path "$f" && continue
  n=$((n+1))
  fix "chmod o-w $f (was $(stat -c %a "$f"), world-writable)" chmod o-w "$f"
done < <(find /etc /usr /boot -xdev -type f -perm -0002 -print0 2>/dev/null)
(( n )) || ok "no world-writable files under /etc, /usr, /boot"
while IFS= read -r -d '' f; do
  is_protected_path "$f" && continue
  report "world-writable: $f ($(stat -c '%a %U' "$f")) - fix by hand if it is not meant to be: chmod o-w"
done < <(find /opt /srv /var /home /root -xdev \( -path /var/tmp -o -path /var/crash -o -path /var/lib/php/sessions -o -path '*/.cache' \) -prune -o -type f -perm -0002 -print0 2>/dev/null)
while IFS= read -r -d '' d; do
  is_protected_path "$d" && continue
  [[ $d == /tmp/mintUpdate ]] && continue   # created like this by Mint's Update Manager
  report "world-writable directory without the sticky bit: $d ($(stat -c %a "$d"))"
done < <(find / -xdev -type d -perm -0002 ! -perm -1000 -print0 2>/dev/null)

section "SUID / SGID programs outside the usual set (report only)"
# Usual set for Ubuntu 22.04/24.04 and Mint 21 desktops. NOT verified against a clean image: expect a few false alarms.
USUAL=" /usr/bin/sudo /usr/bin/su /usr/bin/passwd /usr/bin/chsh /usr/bin/chfn /usr/bin/gpasswd /usr/bin/newgrp
 /usr/bin/mount /usr/bin/umount /usr/bin/fusermount /usr/bin/fusermount3 /usr/bin/pkexec /usr/bin/chage /usr/bin/expiry
 /usr/bin/crontab /usr/bin/ssh-agent /usr/bin/wall /usr/bin/write /usr/bin/write.ul /usr/bin/bsd-write /usr/bin/dotlockfile
 /usr/bin/at /usr/bin/ntfs-3g /usr/bin/vmware-user-suid-wrapper /usr/bin/plocate /usr/bin/mlocate /usr/bin/dotlock.mailutils
 /usr/sbin/pppd /usr/sbin/unix_chkpwd /usr/sbin/pam_extrausers_chkpwd /usr/sbin/mount.nfs /usr/sbin/mount.cifs
 /usr/sbin/postdrop /usr/sbin/postqueue /usr/sbin/exim4 /usr/sbin/pam-tmpdir-helper
 /usr/lib/dbus-1.0/dbus-daemon-launch-helper /usr/lib/openssh/ssh-keysign /usr/lib/policykit-1/polkit-agent-helper-1
 /usr/libexec/polkit-agent-helper-1 /usr/lib/eject/dmcrypt-get-device /usr/lib/snapd/snap-confine /usr/lib/xorg/Xorg.wrap
 /usr/lib/x86_64-linux-gnu/utempter/utempter /usr/libexec/camel-lock-helper-1.2 /usr/lib/evolution/camel-lock-helper-1.2
 /usr/lib/chromium/chrome-sandbox /usr/sbin/mount.ecryptfs_private /usr/lib/chromium-browser/chrome-sandbox /opt/google/chrome/chrome-sandbox /usr/lib/x86_64-linux-gnu/libexec/kf5/kio/kdesud "
while IFS= read -r -d '' f; do
  is_protected_path "$f" && continue
  [[ $USUAL == *" $f "* || $USUAL == *" $f"$'\n'* ]] && continue
  owner=$(pkg_owner "$f")
  case $(basename "$f") in
    bash|sh|dash|zsh|find|vim*|vi|nano|less|more|python*|perl*|ruby*|awk|gawk|mawk|sed|cp|mv|cat|tar|nmap|nc*|env|tee|dd|systemctl|docker)
      report "DANGEROUS SUID/SGID: $f ($(stat -c %A "$f")) - remove the bit: chmod u-s,g-s $f" ;;
    *) report "unusual SUID/SGID: $f ($(stat -c %A "$f"), package: ${owner:-NONE}) - if it should not have it: chmod u-s,g-s $f" ;;
  esac
done < <(find / -xdev \( -perm -4000 -o -perm -2000 \) -type f -print0 2>/dev/null)

section "Files with no owner (report only)"
# -prune: report the top of an ownerless tree once, not every file inside it.
while IFS= read -r f; do
  case $f in
    /home/*) report "no valid owner: $f - usually the home of an account that was deleted without its files. After forensics: rm -r $f" ;;
    *) report "no valid owner or group: $f" ;;
  esac
done < <(find /etc /home /opt /srv /var /usr/local -xdev \( -nouser -o -nogroup \) -print -prune 2>/dev/null | head -40)

section "Home directories (report only)"
for h in /home/*; do
  [[ -d $h ]] || continue
  u=$(basename "$h"); own=$(stat -c %U "$h"); m=$(stat -c %a "$h")
  [[ $own == "$u" || $own == root || $own == UNKNOWN ]] || report "$h is owned by $own"
  (( 8#$m & 8#002 )) && report "$h is world-writable ($m)"
done
cp_done
