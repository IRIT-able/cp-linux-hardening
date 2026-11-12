#!/usr/bin/env bash
# 50-services.sh - required services stay up, requested software gets installed, unneeded services are offered for disabling.
# Catalog: "Services & daemons". Which services are unneeded is a README decision: nothing is disabled
# unless it is in DISABLE_SERVICES or you answer yes for it.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cp_init "SERVICES" "$@"

unit_exists() { systemctl cat "$1" >/dev/null 2>&1; }
resolve_unit() { # config name -> an existing unit name, or nothing
  local n=${1%.service} k c
  k=$(svc_key "$n")
  for c in "$k" "$n" mariadb mysql; do   # canonical name first: "sshd" is only an alias of ssh.service
    [[ $c == mariadb || $c == mysql ]] && [[ $k != mysql ]] && continue
    unit_exists "$c.service" && { echo "$c"; return; }
  done
}

# ---------- required services ----------
section "Required services (config: ${REQUIRED_SERVICES[*]:-none listed})"
(( ${#REQUIRED_SERVICES[@]} )) || report "REQUIRED_SERVICES is empty - if the README lists critical services, add them before applying"
for s in "${REQUIRED_SERVICES[@]}"; do
  u=$(resolve_unit "$s")
  if [[ -z $u ]]; then report "required service '$s' has no systemd unit - install its package (INSTALL_PACKAGES) or check the name"; continue; fi
  act=$(systemctl is-active "$u" 2>/dev/null); en=$(systemctl is-enabled "$u" 2>/dev/null)
  if [[ $u == ssh ]] && systemctl is-enabled --quiet ssh.socket 2>/dev/null; then
    ok "ssh is socket-activated (ssh.socket enabled) - this is the Ubuntu 24.04 default"; continue
  fi
  if [[ $act == active && ( $en == enabled || $en == alias || $en == static ) ]]; then ok "$u is active and enabled"
  else fix "enable and start required service $u (was: $act/$en)" systemctl enable --now "$u"; fi
done

# ---------- software the README asks for ----------
section "Packages to install (config: ${INSTALL_PACKAGES[*]:-none})"
APT_UPDATED=0
need_install=0
for p in "${INSTALL_PACKAGES[@]}"; do pkg_installed "$p" || need_install=1; done
(( need_install )) && fix_os_sources   # a package cannot be installed while the sources are switched off
for p in "${INSTALL_PACKAGES[@]}"; do
  if pkg_installed "$p"; then ok "$p is installed"; continue; fi
  if is_apply && (( ! APT_UPDATED )); then apt-get update >>"$CP_LOG" 2>&1 || report "apt-get update had errors (see log) - sources may need repair"; APT_UPDATED=1; fi
  if is_apply && ! apt_safe install "$p"; then continue; fi
  fix "install $p" env DEBIAN_FRONTEND=noninteractive apt-get install -y "$p"
done

# ---------- services that are usually unneeded ----------
section "Network services that are not in REQUIRED_SERVICES"
KNOWN=(nginx apache2 lighttpd tomcat9 vsftpd proftpd pure-ftpd tftpd-hpa atftpd squid smbd nmbd snmpd rpcbind
       nfs-server nfs-kernel-server named bind9 dnsmasq dovecot postfix exim4 sendmail mysql mariadb postgresql
       redis-server mongod memcached slapd inetd xinetd openbsd-inetd telnet nis ypbind rsync x11vnc xrdp
       tightvncserver vncserver tor minidlna transmission-daemon ircd-hybrid inspircd znc pptpd ssh)
disable_unit() {
  systemctl disable --now "$1" || return 1
  if unit_exists "$1.socket"; then systemctl disable --now "$1.socket"; fi
  return 0
}
seen=" "
for s in "${DISABLE_SERVICES[@]}" "${KNOWN[@]}"; do
  s=${s%.service}
  [[ $seen == *" $s "* ]] && continue; seen+="$s "
  unit_exists "$s.service" || continue
  act=$(systemctl is-active "$s" 2>/dev/null); en=$(systemctl is-enabled "$s" 2>/dev/null)
  sock=""; unit_exists "$s.socket" && sock=$(systemctl is-active "$s.socket" 2>/dev/null)
  [[ $act == active || $en == enabled || $sock == active ]] || continue
  [[ $en == alias ]] && continue
  if is_protected_service "$s"; then
    in_list "$s" "${DISABLE_SERVICES[@]}" && err "$s is in both REQUIRED_SERVICES and DISABLE_SERVICES - left running"
    continue
  fi
  if in_list "$s" "${DISABLE_SERVICES[@]}"; then
    fix "disable and stop $s (listed in DISABLE_SERVICES)" disable_unit "$s"
  elif ! is_apply; then
    report "$s is $act/$en and not required. If the README does not need it, add it to DISABLE_SERVICES (or answer yes in --apply)"
  elif confirm "Disable and stop $s? (README does not list it as required)"; then
    fix "disable and stop $s" disable_unit "$s"
  fi
done

section "Everything listening on the network (read this list)"
ss -tulnp 2>/dev/null | sed 's/^/      /' | tee -a "$CP_LOG"
info "for each line ask: does the README need this? Unknown program names are covered by 100-persistence.sh"
cp_done
