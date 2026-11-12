#!/usr/bin/env bash
# 110-apps-desktop.sh - display manager, browser, and application configs.
# Catalog: "Display manager", "Browser", "Application-specific configs".
# NO answer key scored anything here. This module is almost entirely report-only; the one change it makes
# is switching off the LightDM guest session. Treat every line as a prompt for a human, not a known fix.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cp_init "DISPLAY-MANAGER" "$@"

val() { # file key -> last active value of "key=value" / "key value"
  awk -v k="$2" 'BEGIN{IGNORECASE=1} /^[[:space:]]*[#;]/ {next}
       { line=$0; sub(/^[[:space:]]+/,"",line); n=split(line,a,/[[:space:]]*=[[:space:]]*|[[:space:]]+/); if (tolower(a[1])==tolower(k)) v=a[2] }
       END{print v}' "$1" 2>/dev/null
}
show() { # label file key recommended
  local v; v=$(val "$2" "$3")
  report "$1: $3 = ${v:-(not set)}   usual hardening: $4   [$2]"
}

section "Display manager"
dm=$(basename "$(cat /etc/X11/default-display-manager 2>/dev/null)" 2>/dev/null)
info "display manager: ${dm:-unknown} (the README may say it must stay as it is)"
for G in /etc/gdm3/custom.conf /etc/gdm3/daemon.conf; do   # Ubuntu uses custom.conf, Debian daemon.conf
  [[ -f $G ]] || continue
  if grep -Eiq '^[[:space:]]*AutomaticLoginEnable[[:space:]]*=[[:space:]]*true' "$G"; then
    report "GDM auto-login is on for '$(val "$G" AutomaticLogin)' in $G. CyberPatriot images log you in automatically on purpose - do not change this unless the README says so"
  else ok "GDM auto-login is off in $G"; fi
done
if [[ -d /etc/lightdm ]]; then
  LFILES=(/etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.d/*.conf /usr/share/lightdm/lightdm.conf.d/*.conf)
  guest_off=0
  for f in "${LFILES[@]}"; do
    [[ -f $f ]] || continue
    grep -Eiq '^[[:space:]]*allow-guest[[:space:]]*=[[:space:]]*false' "$f" && guest_off=1
    grep -Eiq '^[[:space:]]*allow-guest[[:space:]]*=[[:space:]]*true' "$f" && report "$f switches the guest session ON - edit that line to allow-guest=false"
    al=$(val "$f" autologin-user); [[ -n $al ]] && report "$f: LightDM auto-login for '$al' - images do this on purpose; leave unless the README says otherwise"
    [[ $(val "$f" greeter-show-manual-login) == false ]] && report "$f: greeter-show-manual-login=false"
  done
  write_guest() { mkdir -p /etc/lightdm/lightdm.conf.d && printf '[Seat:*]\nallow-guest=false\n' >/etc/lightdm/lightdm.conf.d/50-cp-no-guest.conf; }
  if (( guest_off )); then ok "LightDM guest session is off"
  else fix "switch off the LightDM guest session (new file /etc/lightdm/lightdm.conf.d/50-cp-no-guest.conf) [LightDM documentation; not in the keys, untested for score]" write_guest; fi
fi

CP_CAT="BROWSER"
section "Firefox (report only)"
for f in /etc/firefox/policies/policies.json /usr/lib/firefox/distribution/policies.json; do
  [[ -f $f ]] && { report "Firefox policy file exists: $f - read it for odd settings (proxies, disabled updates, homepages)"; sed 's/^/      /' "$f" | head -40 | tee -a "$CP_LOG"; }
done
report "Firefox settings are per user and are done in the browser: Settings > Privacy & Security (block pop-ups, warn on add-on installs, block dangerous downloads, HTTPS-only). No key has scored these yet."
snap list firefox >/dev/null 2>&1 && report "Firefox is installed as a snap. The CP17 README required the Mozilla PPA version instead - read the README before changing anything"

CP_CAT="APP-CONFIG"
section "Application settings for installed servers (report only; change them by hand, then restart the service)"
reviewed() { # service label : only review settings of services the README requires
  is_protected_service "$1" && return 0
  info "$2 is installed but not in REQUIRED_SERVICES - its settings are not reviewed (disable it in 50-services.sh instead)"
  return 1
}
if [[ -f /etc/vsftpd.conf ]] && reviewed vsftpd vsftpd; then
  F=/etc/vsftpd.conf
  vs_get() { awk -F= -v k="$1" '$1==k {v=$2} END{print toupper(v)}' "$F"; }
  vs_apply() { # key=value ... ; restart, and put the old file back if vsftpd does not come up
    local kv
    backup_file "$F"
    for kv in "$@"; do kv_eq_set "$F" "${kv%%=*}" "${kv#*=}"; done
    systemctl restart vsftpd; sleep 1
    if ! systemctl is-active --quiet vsftpd; then
      echo "vsftpd did not start with the new settings; restoring $F"
      cp -a "$CP_BACKUP$F" "$F"; systemctl restart vsftpd
      return 1
    fi
  }
  if [[ ${FTP_MODE,,} == anonymous-only ]]; then
    # README: "allow users to log in only as anonymous". Upload/mkdir off is standard vsftpd hardening.
    # None of this is in an answer key: UNTESTED for score.
    todo=()
    [[ $(vs_get anonymous_enable) == YES ]] || todo+=("anonymous_enable=YES")
    [[ $(vs_get local_enable) == NO ]] || todo+=("local_enable=NO")
    [[ $(vs_get anon_upload_enable) == YES ]] && todo+=("anon_upload_enable=NO")
    [[ $(vs_get anon_mkdir_write_enable) == YES ]] && todo+=("anon_mkdir_write_enable=NO")
    # Anonymous users see anon_root. The Mint image had it set to "/", exposing the whole disk.
    cur_root=$(awk -F= '$1=="anon_root" {v=$2} END{print v}' "$F")
    # On the CP19 Mint image only anon_root=/var/ftp scored (/srv/ftp did not), and /var/ftp did not exist.
    # So FTP_ANON_ROOT is made a link to FTP_ROOT, where the README says the files are, and anon_root points at it.
    want_root=${FTP_ANON_ROOT:-$FTP_ROOT}
    if [[ -n $want_root && -d $FTP_ROOT && $cur_root != "$want_root" ]]; then
      if [[ ! -e $want_root ]]; then
        fix "link $want_root -> $FTP_ROOT so the anonymous root the scorer expects exists" ln -s "$FTP_ROOT" "$want_root"
      fi
      { [[ -e $want_root ]] || ! is_apply; } && todo+=("anon_root=$want_root")
    fi
    if (( ${#todo[@]} )); then fix "vsftpd anonymous-only: ${todo[*]} in $F, then restart vsftpd [README; untested for score]" vs_apply "${todo[@]}"
    else ok "vsftpd is anonymous-only with anonymous uploads off"; fi
  else
    info "FTP_MODE is not set in config.conf - if the README says who may log in to FTP, set FTP_MODE=\"anonymous-only\" or edit $F by hand"
    report "vsftpd: anonymous_enable=$(vs_get anonymous_enable) local_enable=$(vs_get local_enable) anon_upload_enable=$(vs_get anon_upload_enable) anon_mkdir_write_enable=$(vs_get anon_mkdir_write_enable)"
  fi
  report "vsftpd, decide by hand: write_enable=$(vs_get write_enable) (NO if nobody uploads), ssl_enable=$(vs_get ssl_enable), xferlog_enable=$(vs_get xferlog_enable), anon_umask=$(vs_get anon_umask) and local_umask=$(vs_get local_umask) (077 or 022 is usual; 000 makes uploads world-writable)"
  ar=$(awk -F= '$1=="anon_root" {v=$2} END{print v}' "$F"); ar=${ar:-/srv/ftp}
  [[ -d $ar ]] && info "FTP root $ar: $(stat -c '%A %U:%G' "$ar") - anonymous login fails if the ftp user can write to this directory itself"
fi
for F in /etc/apache2/conf-enabled/security.conf /etc/apache2/apache2.conf; do
  [[ -f $F ]] || continue
  is_protected_service apache2 || continue
  show apache2 "$F" ServerTokens "Prod"
  show apache2 "$F" ServerSignature "Off"
  show apache2 "$F" TraceEnable "Off"
done
[[ -d /etc/apache2 ]] && is_protected_service apache2 && grep -rnE '^[[:space:]]*Options.*\bIndexes\b' /etc/apache2/apache2.conf /etc/apache2/sites-enabled 2>/dev/null | while IFS= read -r l; do info "apache2 directory listing enabled: $l"; done
if [[ -f /etc/nginx/nginx.conf ]] && reviewed nginx nginx; then show nginx /etc/nginx/nginx.conf server_tokens "off;"; fi
if [[ -f /etc/samba/smb.conf ]] && reviewed smbd samba; then
  F=/etc/samba/smb.conf
  report "samba: check these lines by eye - usual hardening: guest ok = no, map to guest = never, restrict anonymous = 2, server min protocol = SMB2   [$F]"
  grep -nEi '^[[:space:]]*(guest ok|map to guest|public|writable|writeable|read only|server min protocol|restrict anonymous)[[:space:]]*=' $F | while IFS= read -r l; do info "samba: $l"; done
fi
for F in /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/mariadb.conf.d/50-server.cnf /etc/mysql/my.cnf; do
  [[ -f $F ]] || continue
  is_protected_service mysql || continue
  show mysql "$F" bind-address "127.0.0.1"
  show mysql "$F" local-infile "0"
  show mysql "$F" skip-grant-tables "must NOT be present"
done
for F in /etc/php/*/apache2/php.ini /etc/php/*/fpm/php.ini /etc/php/*/cli/php.ini; do
  [[ -f $F ]] || continue
  show php "$F" expose_php "Off"
  show php "$F" allow_url_include "Off"
  show php "$F" allow_url_fopen "Off"
  show php "$F" display_errors "Off"
done
for F in /etc/postgresql/*/main/pg_hba.conf; do
  [[ -f $F ]] && grep -nE '^[^#]*\btrust\b' "$F" | while IFS= read -r l; do info "postgresql trusts without a password: $F:$l"; done
done
info "nothing listed above is installed? Then there was nothing to check."
cp_done
