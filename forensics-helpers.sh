#!/usr/bin/env bash
# forensics-helpers.sh - read-only search and decode tools for the Forensics Questions.
# It never answers a question and never changes, deletes or installs anything. A human reads the
# output and types the answer into the question file on the Desktop.
# Works without the config. Run with sudo to see every user's files.
set -u
B=$'\e[1m'; R=$'\e[0m'; [[ -t 1 ]] || { B=""; R=""; }
PRUNE=( \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -path /snap -o -path '/var/lib/snapd' \) -prune -o )

usage() {
  cat <<EOF
${B}forensics-helpers.sh - read-only tools${R}   (sudo recommended)

  questions                 show every "Forensics Question" file on the Desktops
  ext EXT [DIR]             find files by extension            e.g.  ext mp3     ext pcap /home
  name PATTERN [DIR]        find files by name (wildcards ok)  e.g.  name 'override*'
  owner USER [DIR]          find files owned by a user
  newer DAYS [DIR]          files changed in the last DAYS days (system noise filtered)
  between FROM TO [DIR]     files changed between two dates    e.g.  between 2024-09-01 2024-09-30
  grep TEXT [DIR]           find files containing text
  type PATH                 what a file really is (file, size, owner, times, first bytes)
  trash                     list every user's Trash, including deleted-from paths
  decode FILE|TEXT          try base64, base32, hex, rot13, URL and binary decodings
  hash FILE...              md5, sha1, sha256, sha512
  ports                     listening ports with the owning program, command line and package
  proc PID                  everything about one process (command, file, parent, start, unit)
  users                     accounts, UIDs, groups, last logins, sudo members
  user NAME                 one account in detail (groups, password status, home, crontab)
  pkg NAME|PATH             is it installed / which package owns this file / when installed
  history                   recent package installs and removals (dpkg log)
  os                        distribution name, version, codename, kernel
  pcap FILE [FILTER]        print a capture as text with tcpdump  e.g.  pcap ftp_capture.pcap 'port 21'
  steg FILE                 look inside an image (strings, appended data, steghide info if installed)
  logins                    recent and failed logins

Reminders: answer forensics questions BEFORE deleting users, media, software or backdoors.
Save the question file after typing the answer. A wrong answer costs nothing.
EOF
}

need() { [[ -n ${1:-} ]] || { echo "missing argument"; usage; exit 2; }; }
ffind() { find "$1" "${PRUNE[@]}" "${@:2}" 2>/dev/null; }

cmd=${1:-help}; shift || true
case $cmd in
  questions)
    for f in /home/*/Desktop/*[Ff]orensic* /root/Desktop/*[Ff]orensic*; do
      [[ -f $f ]] || continue
      printf '\n%s===== %s =====%s\n' "$B" "$f" "$R"; cat "$f"
    done ;;
  ext)   need "${1:-}"; ffind "${2:-/}" -type f -iname "*.${1#.}" -printf '%10s bytes  %u  %TY-%Tm-%Td  %p\n'
         echo; echo "Directories containing them:"; ffind "${2:-/}" -type f -iname "*.${1#.}" -printf '%h\n' | sort | uniq -c ;;
  name)  need "${1:-}"; ffind "${2:-/}" -iname "$1" -printf '%y %10s  %u  %TY-%Tm-%Td %TH:%TM  %p\n' ;;
  owner) need "${1:-}"; ffind "${2:-/}" -user "$1" -printf '%y %10s  %TY-%Tm-%Td  %p\n' | grep -v '/\.cache/' | head -500 ;;
  newer) need "${1:-}"; ffind "${2:-/}" -type f -mtime "-$1" -printf '%TY-%Tm-%Td %TH:%TM  %u  %p\n' |
           grep -Ev '/(\.cache|\.mozilla|\.config/(dconf|pulse)|var/(log|lib|cache)|\.local/share/(gvfs|recently))' | sort | tail -300 ;;
  between) need "${2:-}"; ffind "${3:-/}" -type f -newermt "$1" ! -newermt "$2" -printf '%TY-%Tm-%Td %TH:%TM  %u  %p\n' |
           grep -Ev '/(\.cache|var/(log|lib|cache))' | sort | tail -300 ;;
  grep)  need "${1:-}"; grep -rIl --exclude-dir={proc,sys,dev,run,snap,.cache} -- "$1" "${2:-/home}" 2>/dev/null | head -200 ;;
  type)  need "${1:-}"; file "$1"; stat "$1"; echo "--- first bytes ---"; head -c 256 "$1" | xxd | head -16 ;;
  trash)
    for t in /home/*/.local/share/Trash /root/.local/share/Trash; do
      [[ -d $t ]] || continue
      printf '\n%s%s%s\n' "$B" "$t" "$R"; ls -la "$t/files" 2>/dev/null
      for i in "$t"/info/*.trashinfo; do [[ -f $i ]] && { echo "--- $(basename "$i")"; grep -E '^(Path|DeletionDate)=' "$i"; }; done
    done
    echo; echo "View an image without restoring it:  xdg-open '<path under Trash/files>'" ;;
  decode)
    need "${1:-}"
    if [[ -f $1 ]]; then data=$(cat "$1"); else data=$1; fi
    clean=$(tr -d ' \n\r\t' <<<"$data")
    try() { local out; out=$(eval "$2" 2>/dev/null | tr -d '\0'); [[ -n $out ]] && printf '%s--- %s ---%s\n%s\n' "$B" "$1" "$R" "$out"; }
    try "base64"  'base64 -d <<<"$clean"'
    try "base64, decoded twice" 'base64 -d <<<"$clean" | base64 -d'
    try "base32"  'base32 -d <<<"$clean"'
    try "hex"     'xxd -r -p <<<"$clean"'
    try "rot13"   'tr "A-Za-z" "N-ZA-Mn-za-m" <<<"$data"'
    try "URL"     'python3 -c "import sys,urllib.parse;print(urllib.parse.unquote(sys.argv[1]))" "$data"'
    try "binary (8-bit groups)" 'python3 -c "import sys;b=sys.argv[1].split();print(bytes(int(x,2) for x in b).decode())" "$data"'
    try "decimal ASCII codes"   'python3 -c "import sys;b=sys.argv[1].replace(\",\",\" \").split();print(bytes(int(x) for x in b).decode())" "$data"'
    echo; echo "Only the readable result is the right decoding. Caesar shifts other than 13: use 'tr' or an online tool." ;;
  hash)  need "${1:-}"; for f in "$@"; do for h in md5sum sha1sum sha256sum sha512sum; do printf '%-10s %s\n' "$h" "$($h "$f")"; done; done
         echo "(a text file's hash changes if you add or remove a trailing newline - hash the file itself, not copied text)" ;;
  ports)
    ss -H -tulnp 2>/dev/null | while read -r line; do
      pid=$(grep -oP 'pid=\K[0-9]+' <<<"$line" | head -1)
      printf '%s%s%s\n' "$B" "$(awk '{print $1, $5}' <<<"$line")  $(grep -oP 'users:\(\("\K[^"]+' <<<"$line" | head -1) pid=${pid:-?}" "$R"
      [[ -n $pid ]] || { echo "    (run with sudo to see the program)"; continue; }
      exe=$(readlink -f "/proc/$pid/exe" 2>/dev/null)
      echo "    command: $(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)"
      echo "    program: $exe   package: $(dpkg -S "$exe" 2>/dev/null | cut -d: -f1 || true)"
      echo "    user: $(stat -c %U "/proc/$pid" 2>/dev/null)   working dir: $(readlink -f "/proc/$pid/cwd" 2>/dev/null)"
    done ;;
  proc)
    need "${1:-}"; p=$1
    ps -o pid,ppid,user,lstart,cmd -p "$p"
    echo "program:     $(readlink -f "/proc/$p/exe")"
    echo "working dir: $(readlink -f "/proc/$p/cwd")"
    echo "parent:      $(ps -o pid=,cmd= -p "$(ps -o ppid= -p "$p" | tr -d ' ')")"
    echo "unit:        $(grep -oE '[^/]+\.(service|scope)' "/proc/$p/cgroup" | head -1)"
    echo "open files:"; ls -l "/proc/$p/fd" 2>/dev/null | awk '{print "   ", $NF}' | sort -u | head -30 ;;
  users)
    printf '%-18s %-6s %-6s %-22s %s\n' USER UID GID HOME SHELL
    awk -F: '$3==0 || ($3>=1000 && $3<60000) {printf "%-18s %-6s %-6s %-22s %s\n",$1,$3,$4,$6,$7}' /etc/passwd
    echo; echo "sudo group:  $(getent group sudo | cut -d: -f4)"
    echo "UID 0:       $(awk -F: '$3==0{print $1}' /etc/passwd | tr '\n' ' ')"
    echo "system UIDs with a login shell: $(awk -F: '$3>0 && $3<1000 && $7 ~ /(bash|sh|zsh)$/ {print $1"("$3")"}' /etc/passwd | tr '\n' ' ')"
    echo; lastlog 2>/dev/null | grep -v 'Never logged in' ;;
  user)
    need "${1:-}"; id "$1"; getent passwd "$1"
    echo "password status: $(passwd -S "$1" 2>/dev/null || echo 'needs sudo')"; chage -l "$1" 2>/dev/null
    echo "--- crontab"; crontab -l -u "$1" 2>/dev/null || echo "(none or needs sudo)"
    h=$(getent passwd "$1" | cut -d: -f6); echo "--- $h"; ls -la "$h" 2>/dev/null | head -60 ;;
  pkg)
    need "${1:-}"
    if [[ -e $1 ]]; then dpkg -S "$(readlink -f "$1")" 2>/dev/null || echo "$1 belongs to no package"
    else dpkg -l "$1" 2>/dev/null | tail -n +6 || echo "$1 is not a known package"; apt-cache policy "$1" 2>/dev/null | head -4
         zgrep -h " install $1\| remove $1\| purge $1" /var/log/dpkg.log* 2>/dev/null | sort | tail -5; fi ;;
  history) zgrep -hE ' (install|remove|purge) ' /var/log/dpkg.log* 2>/dev/null | sort | tail -80
           echo "--- apt commands"; zgrep -h -A1 '^Start-Date' /var/log/apt/history.log* 2>/dev/null | grep -v '^--' | tail -40 ;;
  os)    cat /etc/os-release; echo; lsb_release -a 2>/dev/null; uname -a ;;
  pcap)  need "${1:-}"
         command -v tcpdump >/dev/null || { echo "tcpdump is not installed. The key used tshark; installing a sniffer is your call - remove it afterwards."; exit 1; }
         # shellcheck disable=SC2086
         tcpdump -nn -A -r "$1" ${2:-} 2>/dev/null | less -R
         echo "Quick look for cleartext logins:  $0 pcap FILE | grep -aE 'USER|PASS|login|password'" ;;
  steg)  need "${1:-}"; file "$1"; echo "--- readable strings (last 30)"; strings -n 6 "$1" | tail -30
         if command -v steghide >/dev/null; then steghide info "$1" </dev/null 2>&1 | head -10
         else echo "steghide is not installed. A key used: steghide extract -p PASSPHRASE -sf FILE (the passphrase was base64 in another file). Installing it is your call."; fi
         command -v exiftool >/dev/null && exiftool "$1" | head -30 ;;
  logins) last -n 30 2>/dev/null; echo "--- failed"; { lastb -n 20 2>/dev/null || echo "(needs sudo)"; }
          if [[ -f /var/log/auth.log ]]; then grep -ah 'Failed password\|Accepted' /var/log/auth.log | tail -20
          else journalctl -q --no-pager -n 400 _COMM=sshd _COMM=sudo _COMM=su 2>/dev/null | grep -a 'Failed password\|Accepted\|session opened' | tail -20; fi ;;   # Debian 12 logs to the journal only
  help|-h|--help|*) usage ;;
esac
