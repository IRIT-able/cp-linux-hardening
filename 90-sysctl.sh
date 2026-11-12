#!/usr/bin/env bash
# 90-sysctl.sh - kernel network and memory settings. Catalog: "Kernel / sysctl".
# Edits /etc/sysctl.conf (the file the keys edit; it is applied last, so it wins) and runs "sysctl --system".
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cp_init "SYSCTL" "$@"

F=/etc/sysctl.conf
[[ -f $F ]] || { is_apply && touch "$F"; }
NEED_LOAD=0

want() { # key value source [explicit]
  # "explicit" (the three settings the keys scored) also writes the line when the running value is already
  # right but the file does not say so, because the scorer may read the file. Extras are left alone in that case.
  local k=$1 v=$2 src=$3 explicit=${4:-} cur fv
  cur=$(sysctl -n "$k" 2>/dev/null)
  if [[ -z $cur ]]; then info "$k does not exist on this kernel (e.g. IPv6 disabled) - skipped"; return; fi
  fv=$(kv_eq_get "$F" "$k")
  if [[ $cur == "$v" && ( $fv == "$v" || ( -z $fv && -z $explicit ) ) ]]; then ok "$k = $v"; return; fi
  fix "$k = $v in $F (file: ${fv:-not set}, running: $cur) [$src]" kv_eq_set "$F" "$k" "$v" && is_apply && NEED_LOAD=1
  local other
  other=$(grep -El "^[[:space:]]*${k//./\\.}[[:space:]]*=" /etc/sysctl.d/*.conf 2>/dev/null | grep -v '99-sysctl.conf' | tr '\n' ' ')
  [[ -n $other ]] && info "$k is also set in: $other(sysctl.conf is applied last and wins)"
  local uv
  uv=$(grep -E "^[[:space:]]*${k//.//}[[:space:]]*=" /etc/ufw/sysctl.conf 2>/dev/null | tail -1 | cut -d= -f2 | tr -d '[:space:]')
  if [[ -n $uv && $uv != "$v" ]]; then
    report "$k is set to $uv in /etc/ufw/sysctl.conf, which ufw applies when it starts - change that line to ${k//.//}=$v"
  fi
}

section "Settings scored in the answer keys"
want net.ipv4.tcp_syncookies 1 "answer keys" explicit
want kernel.randomize_va_space 2 "answer key" explicit
want net.ipv4.tcp_rfc1337 1 "answer key (CP19 Mint Training 2: TIME-WAIT assassination protection)" explicit
if [[ ${ALLOW_IP_FORWARD,,} == yes ]]; then
  skip "IP forwarding left alone (ALLOW_IP_FORWARD=yes)"
else
  want net.ipv4.ip_forward 0 "answer key" explicit
  command -v docker >/dev/null && report "docker is installed; it needs IP forwarding - if the README requires docker set ALLOW_IP_FORWARD=\"yes\""
fi

section "Extra hardening suggested in Ubuntu's stock /etc/sysctl.conf (not in the keys; untested for score)"
if [[ ${SYSCTL_EXTRA,,} == yes ]]; then
  S="Ubuntu sysctl.conf comments"
  [[ ${ALLOW_IP_FORWARD,,} == yes ]] || want net.ipv6.conf.all.forwarding 0 "$S"
  want net.ipv4.conf.all.rp_filter 1 "$S"
  want net.ipv4.conf.default.rp_filter 1 "$S"
  want net.ipv4.conf.all.accept_redirects 0 "$S"
  want net.ipv4.conf.default.accept_redirects 0 "$S"
  want net.ipv6.conf.all.accept_redirects 0 "$S"
  want net.ipv4.conf.all.send_redirects 0 "$S"
  want net.ipv4.conf.all.accept_source_route 0 "$S"
  want net.ipv6.conf.all.accept_source_route 0 "$S"
  want net.ipv4.conf.all.log_martians 1 "$S"
else
  skip "extras not applied (SYSCTL_EXTRA is not yes)"
fi

if (( NEED_LOAD )); then
  fix "load the settings (sysctl --system)" sysctl --system
  for k in net.ipv4.tcp_syncookies kernel.randomize_va_space net.ipv4.ip_forward; do info "now running: $k = $(sysctl -n $k 2>/dev/null)"; done
fi
cp_done
