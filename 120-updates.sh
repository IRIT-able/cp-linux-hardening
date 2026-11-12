#!/usr/bin/env bash
# 120-updates.sh - automatic update settings and installing updates. Catalog: "Updates & auto-updates".
# Runs last: the full upgrade takes a long time. The keys give these settings as GUI steps only, so the
# file-level equivalents used here are standard Ubuntu configuration that has NOT been checked against the scorer.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cp_init "UPDATES" "$@"

AUTO=/etc/apt/apt.conf.d/20auto-upgrades
periodic_get() { apt-config dump 2>/dev/null | awk -F'"' -v k="APT::Periodic::$1 " 'index($0,k)==1 {print $2}'; }
periodic_set() { # key value
  local k="APT::Periodic::$1" v=$2 f hit=0
  for f in /etc/apt/apt.conf.d/*; do
    [[ -f $f ]] || continue
    if grep -Eq "^[[:space:]]*${k}[[:space:]]" "$f"; then
      backup_file "$f"; sed -E -i "s|^[[:space:]]*${k}[[:space:]].*|${k} \"${v}\";|" "$f"; hit=1
    fi
  done
  if (( ! hit )) || ! grep -q "^${k} " "$AUTO" 2>/dev/null; then
    backup_file "$AUTO"; printf '%s "%s";\n' "$k" "$v" >>"$AUTO"
  fi
}
want_periodic() { # key source
  local cur; cur=$(periodic_get "$1")
  if [[ $cur == 1 ]]; then ok "APT::Periodic::$1 = 1 (daily)"
  else fix "APT::Periodic::$1 \"1\" (was ${cur:-not set}) [$2]" periodic_set "$1" 1; fi
}

section "Automatic update checks (apt)"
want_periodic Update-Package-Lists "file behind 'check for updates: Daily'; needs testing against the scorer"
want_periodic Unattended-Upgrade "Ubuntu documentation; not in the keys"
pkg_installed unattended-upgrades || report "unattended-upgrades is not installed, so updates are checked but not installed automatically (apt install unattended-upgrades)"

if (( IS_MINT )); then
  section "Linux Mint Update Manager (phase 2 - untested)"
  if systemctl is-enabled --quiet mintupdate-automation-upgrade.timer 2>/dev/null; then
    ok "Update Manager automatic upgrades are enabled"
  elif command -v mintupdate-automation >/dev/null; then
    fix "mintupdate-automation upgrade enable [command behind 'Apply updates automatically'; UNTESTED]" mintupdate-automation upgrade enable
  else
    report "do this by hand: Update Manager > Edit > Preferences > Automation > Apply updates automatically"
  fi
  report "also by hand: Update Manager > Edit > Preferences > Options/Automation > 'Refresh the list of updates automatically' (one key scored this by name)"
  report "if Update Manager says 'Your APT configuration is corrupt': click OK, Restore the default settings, OK - needed before any update can score"
fi

section "Package sources"
fix_os_sources
mapfile -t SRC < <(grep -rhE '^[[:space:]]*deb[[:space:]]' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; grep -rhE '^(URIs|Suites):' /etc/apt/sources.list.d/*.sources 2>/dev/null)
(( ${#SRC[@]} )) || report "no active package sources found at all - updates cannot work; restore them in Software & Updates / Software Sources"
printf '%s\n' "${SRC[@]}" | grep -q -- '-security' || report "no '-security' source is enabled - turn on 'Important security updates' in Software & Updates"
printf '%s\n' "${SRC[@]}" | grep -q -- '-updates'  || report "no '-updates' source is enabled - turn on 'Recommended updates' in Software & Updates (Debian: add the bookworm-updates suite)"
[[ $OS_ID == debian ]] && grep -rqE '^[[:space:]]*deb[[:space:]]+cdrom:' /etc/apt/sources.list 2>/dev/null && report "/etc/apt/sources.list still has the installer's 'deb cdrom:' line - comment it out or apt-get update fails"
for l in "${SRC[@]}"; do
  case $l in
    *ubuntu.com*|*linuxmint.com*|*debian.org*|*launchpad*|*canonical.com*|*mozilla*|*google.com*|Suites:*) ;;
    *) report "third-party package source (is it in the README?): $l" ;;
  esac
done

section "Install updates"
if ! is_apply; then
  apt-get update >>"$CP_LOG" 2>&1 || report "apt-get update reported errors (see log) - fix the sources first"
  n=$(apt-get -s full-upgrade 2>/dev/null | grep -c '^Inst ')
  if (( n )); then would "install $n pending package update(s) with apt-get full-upgrade (asks first; can take 10-30 minutes)"
  else ok "no pending package updates"; fi
else
  apt-get update >>"$CP_LOG" 2>&1 || report "apt-get update reported errors (see log) - fix the sources first"
  n=$(apt-get -s full-upgrade 2>/dev/null | grep -c '^Inst ')
  if (( n == 0 )); then ok "no pending package updates"
  elif ! apt_safe full-upgrade; then err "full-upgrade would remove a required package - not run; upgrade packages one at a time by hand"
  elif confirm "Install $n package update(s) now? It can take 10-30 minutes; do it last."; then
    info "running apt-get full-upgrade, keeping your current config files (--force-confold)..."
    DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade 2>&1 | tee -a "$CP_LOG" | grep -E '^(Setting up|E:|W:)'
    if (( PIPESTATUS[0] == 0 )); then changed "installed $n package update(s)"; else err "apt-get full-upgrade failed (see log)"; fi
    command -v sshd >/dev/null && { sshd -t 2>>"$CP_LOG" || err "sshd -t fails after the upgrade - check /etc/ssh/sshd_config"; }
  fi
fi
if command -v snap >/dev/null; then
  pend=$(snap refresh --list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ' ')
  [[ -n $pend ]] && report "snap packages with updates: $pend- update with: snap refresh"
fi
[[ -f /var/run/reboot-required ]] && report "a reboot is required to finish updates - reboot only when the team agrees (scoring continues after reboot)"
cp_done
