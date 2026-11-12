#!/usr/bin/env bash
# 40-firewall.sh - UFW. Catalog: "Firewall".
# Ports for required services are allowed BEFORE the firewall is switched on.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cp_init "FIREWALL" "$@"

if ! command -v ufw >/dev/null; then
  if is_apply; then
    fix "install ufw" env DEBIAN_FRONTEND=noninteractive apt-get install -y ufw || { cp_done; exit 1; }
  else
    would "install ufw (not installed)"; cp_done; exit 0
  fi
fi

ports_for() { # required service -> ufw rule(s)
  case $(svc_key "$1") in
    ssh) local p; p=$(sshd -T 2>/dev/null | awk '$1=="port"{print $2}' | sort -u | tr '\n' ' '); for x in ${p:-22}; do echo "$x/tcp"; done ;;
    vsftpd|proftpd|pure-ftpd) echo "21/tcp" ;;
    apache2|nginx|lighttpd) echo "80/tcp"; echo "443/tcp" ;;
    smbd) echo "139/tcp"; echo "445/tcp" ;;
    named) echo "53" ;;
    postfix|exim4) echo "25/tcp" ;;
    cups) echo "631/tcp" ;;
    *) ;;
  esac
}

section "Allow rules for required services"
RULES=()
for s in "${REQUIRED_SERVICES[@]}"; do
  got=0
  while read -r r; do [[ -n $r ]] && { RULES+=("$r"); got=1; }; done < <(ports_for "$s")
  (( got )) || report "no known port for required service '$s' - add its port to UFW_ALLOW (x2go uses SSH, so needs nothing extra)"
done
RULES+=("${UFW_ALLOW[@]}")
existing=$(ufw show added 2>/dev/null)
for r in "${RULES[@]}"; do
  if grep -Eq "^ufw allow ${r//\//\\/}\$" <<<"$existing"; then ok "rule present: allow $r"
  else fix "ufw allow $r" ufw allow "$r"; fi
done

section "Firewall state"
if ufw status | grep -q '^Status: active'; then ok "ufw is active"
else fix "ufw enable" ufw --force enable; fi

if ufw status verbose 2>/dev/null | grep -q '^Status: active'; then
  def=$(ufw status verbose | awk -F'[:,]' '/^Default:/{print $2}')
  if [[ $def == *deny* || $def == *reject* ]]; then ok "default incoming policy:$def"
  else fix "ufw default deny incoming (was:$def) [Ubuntu default; not in the keys]" ufw default deny incoming; fi
  info "current rules:"; ufw status numbered | sed 's/^/      /' | tee -a "$CP_LOG"
  report "read the rules above: delete any 'ALLOW' the README does not need (ufw delete <number>)"
fi
cp_done
