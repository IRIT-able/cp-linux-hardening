#!/usr/bin/env bash
# 30-ssh.sh - OpenSSH server settings. Catalog: "SSH".
# Never stops or removes sshd. Every edit is validated with "sshd -t" before it replaces the real file.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cp_init "SSH" "$@"

CFG=/etc/ssh/sshd_config
if [[ ! -f $CFG ]] || ! command -v sshd >/dev/null; then
  if is_protected_service ssh; then report "sshd is a required service but openssh-server is not installed - add openssh-server to INSTALL_PACKAGES"
  else ok "OpenSSH server is not installed; nothing to do"; fi
  cp_done; exit 0
fi
is_protected_service ssh || report "sshd is installed but not in REQUIRED_SERVICES - 50-services.sh will ask whether to disable it; settings are hardened anyway"

effective() { sshd -T 2>/dev/null | awk -v k="${1,,}" '$1==k {print $2; exit}'; }
file_value() { awk -v k="${1,,}" 'tolower($1)=="match"{exit} tolower($1)==k {print tolower($2); exit}' "$2"; }
sshd_check() { sshd -t -f "$1"; }

apply_setting() { # Key value : edit main file (validated), then any drop-in that still overrides it
  local k=$1 v=$2 tmp d
  tmp=$(mktemp) || return 1
  ssh_set_in "$CFG" "$k" "$v" >"$tmp"
  if ! sshd_check "$tmp"; then rm -f "$tmp"; echo "sshd -t rejected the edited config; $CFG left unchanged"; return 1; fi
  backup_file "$CFG"; cat "$tmp" >"$CFG"; rm -f "$tmp"
  for d in /etc/ssh/sshd_config.d/*.conf; do
    [[ -f $d ]] || continue
    [[ -n $(file_value "$k" "$d") && $(file_value "$k" "$d") != "${v,,}" ]] || continue
    backup_file "$d"
    tmp=$(mktemp); ssh_set_in "$d" "$k" "$v" >"$tmp"; cat "$tmp" >"$d"; rm -f "$tmp"
    if ! sshd -t; then echo "sshd -t failed after editing $d; restoring it"; cp -a "$CP_BACKUP$d" "$d"; return 1; fi
  done
  sshd -t
}

RELOAD=0
want() { # Key value source
  local k=$1 v=$2 src=$3 fv ev
  fv=$(file_value "$k" "$CFG"); ev=$(effective "$k")
  if [[ $fv == "${v,,}" && ( -z $ev || $ev == "${v,,}" ) ]]; then ok "$k $v"; return; fi
  fix "$k $v in $CFG (file: ${fv:-not set}, in effect: ${ev:-unknown}) [$src]" apply_setting "$k" "$v" && is_apply && RELOAD=1
}

section "Settings"
want PermitRootLogin no "answer keys"
want PermitEmptyPasswords no "OpenSSH default; not in the keys, untested for score"

if grep -Eiq '^[[:space:]]*Match[[:space:]]' "$CFG"; then
  report "$CFG has Match blocks - settings inside them can override the above for some users; read them:"
  sed -n '/^[[:space:]]*[Mm]atch[[:space:]]/,$p' "$CFG" | sed 's/^/      /' | tee -a "$CP_LOG"
fi

section "Other values in effect (report only - change by hand if the README or your checklist says so)"
for k in passwordauthentication pubkeyauthentication x11forwarding maxauthtries usepam permituserenvironment hostbasedauthentication ignorerhosts port allowusers denyusers; do
  v=$(effective "$k"); [[ -n $v ]] && info "$k $v"
done
[[ $(effective usepam) == no ]] && report "UsePAM is no - password and lockout policy do not apply to SSH logins"
[[ $(effective permituserenvironment) == yes ]] && report "PermitUserEnvironment is yes"
[[ $(effective hostbasedauthentication) == yes ]] && report "HostbasedAuthentication is yes"
[[ $(effective ignorerhosts) == no ]] && report "IgnoreRhosts is no"

if (( RELOAD )); then
  if sshd -t 2>>"$CP_LOG"; then
    if systemctl is-active --quiet ssh; then
      fix "reload sshd so the new settings take effect" systemctl reload ssh
    else
      info "sshd is not running right now (on Ubuntu 24.04 it starts on demand from ssh.socket); new settings apply at next start"
    fi
  else
    err "sshd -t fails - sshd NOT reloaded. Restore with: cp -a $CP_BACKUP/etc/ssh/. /etc/ssh/"
  fi
fi
cp_done
