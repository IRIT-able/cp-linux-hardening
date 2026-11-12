#!/usr/bin/env bash
# 60-software.sh - prohibited software: hacking tools, games, file sharing, insecure remote access.
# Catalog: "Unauthorized software & hacking tools".
# Nothing in REQUIRED_PACKAGES / INSTALL_PACKAGES / required services is ever removed. Every purge is
# simulated first and refused if apt would take a protected package with it. "apt autoremove" is never run.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cp_init "SOFTWARE" "$@"

# dpkg glob patterns. The first block of each list is what the answer keys scored.
HACKING=(wireshark 'wireshark-*' tshark ophcrack 'ophcrack-*' doona xprobe netcat-traditional
         john john-data hydra hydra-gtk nmap zenmap ncat ndiff aircrack-ng nikto sqlmap kismet 'kismet-*'
         'ettercap-*' medusa hashcat 'hashcat-*' fcrackzip pdfcrack rarcrack sucrack lcrack dsniff p0f
         yersinia reaver pixiewps crunch cewl metasploit-framework nbtscan masscan hping3 rfdump wifite
         bettercap beef-xss burpsuite dirb gobuster wfuzz responder driftnet sslstrip weevely chntpw
         cmospwd 'bruteforce-*' mdk3 mdk4 arp-scan netdiscover armitage 'proxychains*' tor
         torbrowser-launcher logkeys)
GAMES=(aisleriot zangband
       gnome-mines gnome-sudoku gnome-mahjongg gnome-chess gnome-robots gnome-tetravex gnome-klotski
       gnome-nibbles gnome-taquin quadrapassel four-in-a-row hitori iagno lightsoff swell-foop tali
       five-or-more kpat kmines 'freeciv*' 'wesnoth*' 'nethack*' angband crawl moria 'minetest*'
       'supertux*' 'openarena*' '0ad*' endless-sky pysolfc xonotic teeworlds frozen-bubble
       extremetuxracer neverball hedgewars widelands 'steam*' lutris)
SHARING=('transmission-*' qbittorrent 'deluge*' vuze frostwire 'amule*' ktorrent rtorrent nicotine)
REMOTE=(telnetd inetutils-telnetd rsh-server rsh-redone-server nis x11vnc tightvncserver vnc4server
        'tigervnc-*server' rsh-client)

section "Required software is present"
for p in "${REQUIRED_PACKAGES[@]}"; do
  if [[ -n $(pkgs_matching "$p") ]]; then ok "required package $p is installed"
  elif command -v snap >/dev/null && snap list "$p" >/dev/null 2>&1; then ok "required software $p is installed as a snap (check the README: some require the apt version)"
  else report "REQUIRED_PACKAGES entry '$p' is not an installed package - wrong name? Find it with: dpkg -l | grep -i $p"; fi
done

purge_one() { DEBIAN_FRONTEND=noninteractive apt-get purge -y "$1"; }
handle() { # label, patterns...
  local label=$1 p; shift
  while read -r p; do
    [[ -z $p ]] && continue
    if is_protected_pkg "$p"; then info "$p ($label) is installed but required by the config - kept"; continue; fi
    if in_list "$p" "${REMOVE_PACKAGES[@]}"; then
      if ! is_apply; then would "purge $p ($label; listed in REMOVE_PACKAGES)"; continue; fi
      forensics_gate "purge $p" || continue
      apt_safe purge "$p" || continue
      fix "purge $p ($label)" purge_one "$p"
    elif ! is_apply; then
      report "$p ($label) is installed. Unless the README needs it, add it to REMOVE_PACKAGES (or answer yes in --apply)"
    else
      forensics_gate "purge $p" || continue
      confirm "Purge $p ($label)?" || continue
      apt_safe purge "$p" || continue
      fix "purge $p ($label)" purge_one "$p"
    fi
  done < <(pkgs_matching "$@")
}

section "Prohibited software found"
handle "hacking tool" "${HACKING[@]}"
handle "game" "${GAMES[@]}"
handle "file sharing" "${SHARING[@]}"
handle "insecure remote access" "${REMOTE[@]}"
# Packages the team listed that are not on the built-in lists.
extra=()
for p in "${REMOVE_PACKAGES[@]}"; do pkg_installed "$p" && extra+=("$p"); done
(( ${#extra[@]} )) && handle "listed in REMOVE_PACKAGES" "${extra[@]}"

section "Files listed in REMOVE_FILES"
for f in "${REMOVE_FILES[@]}"; do
  [[ $f == /* ]] || { err "REMOVE_FILES: '$f' is not an absolute path"; continue; }
  if is_protected_path "$f" || is_pkg_file "$f"; then err "REMOVE_FILES: $f is protected or belongs to a package - not removed"; continue; fi
  for k in "${MEDIA_KEEP_PATHS[@]}"; do [[ $f == "$k"/* ]] && { err "REMOVE_FILES: $f is under $k (kept path) - not removed"; continue 2; }; done
  if [[ ! -e $f ]]; then ok "$f is already gone"; continue; fi
  [[ -f $f ]] || { err "REMOVE_FILES: $f is not a regular file - remove it by hand"; continue; }
  if ! is_apply; then would "delete $f (listed in REMOVE_FILES)"; continue; fi
  forensics_gate "delete $f" || continue
  printf 'deleting %s (%s bytes, sha256 %s)\n' "$f" "$(stat -c %s "$f")" "$(sha256sum "$f" | cut -d' ' -f1)" >>"$CP_LOG"
  fix "delete $f (listed in REMOVE_FILES)" rm -f -- "$f"
done

section "Leftovers (report only)"
auto=$(apt_would_remove autoremove | tr '\n' ' ')
if [[ -n $auto ]]; then
  bad=""
  for p in $auto; do is_protected_pkg "$p" && bad+="$p "; done
  if [[ -n $bad ]]; then report "DO NOT run 'apt autoremove': it would remove required package(s): $bad"
  else info "'apt autoremove' would remove: $auto(not run automatically; none of them are in the config)"; fi
fi
if command -v snap >/dev/null; then
  info "snap packages (remove a prohibited one with: snap remove NAME):"
  snap list 2>/dev/null | sed 's/^/      /' | tee -a "$CP_LOG"
fi

section "Hunting: files no package owns, and archives in odd places (report only)"
while IFS= read -r -d '' f; do
  is_protected_path "$f" && continue
  is_pkg_file "$f" || report "not owned by any package: $f"
done < <(find /usr/games /usr/local/bin /usr/local/sbin /usr/local/games -xdev -type f -print0 2>/dev/null)
while IFS= read -r -d '' f; do
  is_protected_path "$f" && continue
  report "archive or installer: $f  ($(du -h "$f" 2>/dev/null | cut -f1))"
done < <(find /home /root /opt /usr/games /usr/local /tmp /var/tmp /srv -xdev \
           \( -path '*/.cache' -o -path '*/snap' -o -path '*/.mozilla' -o -path '*/.thunderbird' \) -prune -o \
           -type f \( -iname '*.zip' -o -iname '*.tar' -o -iname '*.tar.*' -o -iname '*.tgz' -o -iname '*.7z' \
           -o -iname '*.rar' -o -iname '*.deb' -o -iname '*.rpm' -o -iname '*.AppImage' -o -iname '*.run' \) -print0 2>/dev/null)
for d in /opt/*; do
  [[ -e $d ]] || continue
  is_protected_path "$d" && continue
  report "in /opt: $d (third-party software lives here; is it in the README?)"
done
cp_done
