#!/usr/bin/env bash
# 100-persistence.sh - backdoors and persistence. Catalog: "Cron & persistence / backdoors".
# Auto-fixes one thing only: cron lines that start a netcat listener (the Ubuntu Training 2 backdoor),
# and, after asking, the netcat process itself. Everything else is reported for a human to judge.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cp_init "PERSISTENCE" "$@"

SUS='(\bnc(\.traditional|\.openbsd)?[[:space:]]|\bncat\b|\bnetcat\b|\bsocat\b|/dev/tcp/|/dev/udp/|bash -i|sh -i|python[0-9.]* -c|perl -e|base64 (-d|--decode)|(curl|wget) [^|]*\|[[:space:]]*(ba)?sh|mkfifo|chmod \+s|chmod [0-7]*777|msfvenom|meterpreter|backdoor|keylog|LD_PRELOAD)'
NC_CRON='^[^#]*\b(nc|ncat|netcat|nc\.traditional|nc\.openbsd)\b[^#]*[[:space:]]-[a-zA-Z]*[le]'
owned() { is_pkg_file "$1"; }
# remove_backdoor pid script cronfile... : the fix the Mint keys give (delete the script, kill it), plus its cron launcher.
remove_backdoor() {
  local pid=$1 script=$2 f t; shift 2
  for f in "$@"; do
    t=$(mktemp) || return 1
    grep -vF -- "$script" "$f" >"$t"; cron_install "$f" "$t"; rm -f "$t"
  done
  backup_file "$script"; rm -f -- "$script"
  kill "$pid" 2>/dev/null; pkill -f -- "$script" 2>/dev/null
  return 0
}

# ---------- listeners ----------
section "Listening programs that are shells, interpreters or netcat"
found=0
while read -r line; do
  name=$(grep -oP 'users:\(\("\K[^"]+' <<<"$line" | head -1)
  pid=$(grep -oP 'pid=\K[0-9]+' <<<"$line" | head -1)
  addr=$(awk '{print $5}' <<<"$line")
  [[ -n $pid ]] || continue
  case $name in
    nc|ncat|netcat|nc.traditional|nc.openbsd|socat|python*|perl*|ruby*|php*|bash|sh|dash|node|java) ;;
    *) continue ;;
  esac
  exe=$(readlink -f "/proc/$pid/exe" 2>/dev/null)
  is_protected_path "$exe" && continue
  cmd=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)
  is_protected_path "$cmd" && continue
  found=1
  unit=$(grep -oE '[^/]+\.service' "/proc/$pid/cgroup" 2>/dev/null | head -1)
  report "$name (pid $pid) listens on $addr | command: $cmd| started by: ${unit:-pid $(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null)}"
  case $name in
    nc|ncat|netcat|nc.traditional|nc.openbsd)
      if is_apply && forensics_gate "kill netcat listener pid $pid"; then
        confirm "Kill netcat listener pid $pid ($cmd)?" && fix "kill netcat listener pid $pid on $addr" kill "$pid"
      fi
      owned "$exe" && info "$exe belongs to package $(pkg_owner "$exe") - 60-software.sh offers to purge netcat-traditional" \
                   || info "$exe belongs to no package - after killing it, remove the file by hand: rm $exe" ;;
    *)
       script=$(awk '{for(i=2;i<=NF;i++) if($i ~ /^\//){print $i; exit}}' <<<"$cmd")
       if [[ -n $script ]]; then
         mapfile -t refs < <(grep -rIl -- "$script" /etc/cron* /var/spool/cron /etc/systemd /etc/rc.local /etc/init.d /etc/profile.d /home/*/.config/autostart 2>/dev/null)
         cronrefs=(); otherrefs=()
         for r in "${refs[@]}"; do case $r in /etc/crontab|/etc/cron.d/*|/var/spool/cron/*) cronrefs+=("$r") ;; *) otherrefs+=("$r") ;; esac; done
         info "$script is launched from: ${refs[*]:-(nothing found)}"
         (( ${#otherrefs[@]} )) && report "also remove the launcher by hand in: ${otherrefs[*]}"
         if is_pkg_file "$script"; then
           info "$script belongs to a package, so it is not removed automatically"
         elif ! is_apply; then
           would "remove this backdoor (asks first): delete $script, kill it, and delete the lines naming it in: ${cronrefs[*]:-no cron file}"
         elif forensics_gate "remove backdoor $script" && confirm "Remove this backdoor? Deletes $script, kills it, and deletes the lines naming it in: ${cronrefs[*]:-no cron file}"; then
           fix "remove backdoor $script (script, process, cron lines)" remove_backdoor "$pid" "$script" "${cronrefs[@]}"
         fi
       fi ;;
  esac
done < <(ss -H -tulnp 2>/dev/null)
(( found )) || ok "no shell, interpreter or netcat is listening"

# ---------- cron ----------
section "Cron"
CRONFILES=(/etc/crontab /etc/anacrontab)
for f in /etc/cron.d/* /etc/cron.hourly/* /etc/cron.daily/* /etc/cron.weekly/* /etc/cron.monthly/* /var/spool/cron/crontabs/*; do [[ -f $f ]] && CRONFILES+=("$f"); done
strip_nc() { local t rc; t=$(mktemp) || return 1; grep -Ev "$NC_CRON" "$1" >"$t"; cron_install "$1" "$t"; rc=$?; rm -f "$t"; return $rc; }
for f in "${CRONFILES[@]}"; do
  [[ -f $f ]] || continue
  is_protected_path "$f" && continue
  if grep -Eq "$NC_CRON" "$f"; then
    grep -En "$NC_CRON" "$f" | sed 's/^/      /' | tee -a "$CP_LOG"
    if ! is_apply; then would "remove the netcat listener line(s) above from $f"
    elif forensics_gate "edit $f"; then fix "remove netcat listener line(s) from $f" strip_nc "$f"; fi
  fi
  while IFS= read -r l; do report "$f: suspicious: $l"; done < <(grep -Ev '^[[:space:]]*#' "$f" | grep -Ev "$NC_CRON" | grep -E "$SUS")
  case $f in
    /var/spool/cron/crontabs/*)
      while IFS= read -r l; do report "crontab of $(basename "$f"): $l"; done < <(grep -Ev '^[[:space:]]*(#|$)' "$f") ;;
    /etc/cron.*/*)
      [[ $(basename "$f") == .placeholder ]] || owned "$f" || report "$f belongs to no package - read it" ;;
  esac
done
while IFS= read -r l; do report "/etc/crontab entry (stock Ubuntu has only run-parts lines): $l"; done < <(
  grep -Ev '^[[:space:]]*(#|$|[A-Z_]+=)' /etc/crontab 2>/dev/null | grep -v 'run-parts' | grep -Ev "$NC_CRON")
[[ -n $(ls -A /var/spool/cron/atjobs 2>/dev/null | grep -v '^\.SEQ$') ]] && report "there are queued 'at' jobs: list with atq, read with at -c N"

# ---------- systemd ----------
section "systemd units that belong to no package (report only)"
while IFS= read -r -d '' f; do
  is_protected_path "$f" && continue
  owned "$f" && continue
  ex=$(grep -E '^(ExecStart|ExecStartPre|ExecStartPost|OnCalendar|OnBootSec)=' "$f" 2>/dev/null | tr '\n' ' ')
  is_protected_path "$ex" && continue
  case $(basename "$f") in snap*|*.mount) continue ;; esac
  report "$f : $ex"
done < <(find /etc/systemd/system /usr/local/lib/systemd /home/*/.config/systemd /root/.config/systemd -xdev -type f \( -name '*.service' -o -name '*.timer' -o -name '*.socket' -o -name '*.path' \) -print0 2>/dev/null)

# ---------- boot and login scripts ----------
section "rc.local, init scripts, autostart (report only)"
if [[ -f /etc/rc.local ]]; then
  while IFS= read -r l; do report "/etc/rc.local runs: $l"; done < <(grep -Ev '^[[:space:]]*(#|$|exit 0)' /etc/rc.local)
fi
for f in /etc/init.d/* /etc/xdg/autostart/* /etc/profile.d/* /etc/update-motd.d/*; do
  [[ -f $f ]] || continue
  is_protected_path "$f" && continue
  case $f in /etc/profile.d/debuginfod.*) continue ;; esac   # generated when libdebuginfod is installed
  owned "$f" || report "$f belongs to no package - read it"
done
for f in /home/*/.config/autostart/* /root/.config/autostart/*; do
  [[ -f $f ]] || continue
  is_protected_path "$f" && continue
  grep -qi 'cyberpatriot\|ccs' "$f" 2>/dev/null && continue
  report "user autostart entry $f : $(grep -m1 '^Exec=' "$f" 2>/dev/null)"
done

section "Shell start-up files (report only)"
RC=(/etc/profile /etc/bash.bashrc /etc/environment /etc/bash.bash_logout /root/.bashrc /root/.profile /root/.bash_profile /root/.bash_login /root/.bash_logout)
for f in /etc/profile.d/* /etc/skel/.[!.]* /home/*/.bashrc /home/*/.profile /home/*/.bash_profile /home/*/.bash_login /home/*/.bash_logout /home/*/.bash_aliases /home/*/.zshrc; do [[ -f $f ]] && RC+=("$f"); done
for f in "${RC[@]}"; do
  [[ -f $f ]] || continue
  while IFS= read -r l; do report "$f: $l"; done < <(grep -En "$SUS" "$f" | grep -Ev '^[0-9]+:[[:space:]]*#')
  while IFS= read -r l; do report "$f: alias replaces a core command: $l"; done < <(
    grep -En '^[[:space:]]*alias[[:space:]]+(sudo|su|ssh|passwd|cd|cat|ps|ss|netstat|who|w|id|apt|apt-get|systemctl|ufw|nano|vi|vim|rm|find)=' "$f")
  while IFS= read -r l; do report "$f: PATH starts somewhere unusual: $l"; done < <(grep -En '^[[:space:]]*(export[[:space:]]+)?PATH=["'\'']?(/tmp|/var/tmp|/dev/shm|\.[:/])' "$f")
done

section "Netcat listeners still running after the cron clean-up"
left=0
while read -r line; do
  name=$(grep -oP 'users:\(\("\K[^"]+' <<<"$line" | head -1); pid=$(grep -oP 'pid=\K[0-9]+' <<<"$line" | head -1)
  case $name in nc|ncat|netcat|nc.traditional|nc.openbsd) ;; *) continue ;; esac
  [[ -n $pid ]] || continue
  left=1
  cmd=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)
  if ! is_apply; then would "kill netcat listener pid $pid ($cmd) - asks first"
  elif forensics_gate "kill netcat listener pid $pid" && confirm "Kill netcat listener pid $pid ($cmd)?"; then fix "kill netcat listener pid $pid" kill "$pid"; fi
done < <(ss -H -tulnp 2>/dev/null)
(( left )) || ok "no netcat listener is running"

section "Other persistence spots (report only)"
if [[ -s /etc/ld.so.preload ]]; then report "/etc/ld.so.preload is not empty (libraries forced into every program): $(tr '\n' ' ' </etc/ld.so.preload)"; fi
for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys /home/*/.ssh/authorized_keys2; do
  [[ -s $f ]] && report "SSH keys allowed in $f: $(grep -cv '^[[:space:]]*\(#\|$\)' "$f") key(s) - does the README mention them?"
done
while IFS= read -r -d '' f; do report "executable file in a temp directory: $f"; done < <(
  find /tmp /var/tmp /dev/shm -xdev -type f -perm /111 -print0 2>/dev/null)
for d in /lib/x86_64-linux-gnu/security /usr/lib/x86_64-linux-gnu/security; do
  [[ -d $d && ! -L $d ]] || continue
  for f in "$d"/*.so; do [[ -f $f ]] && ! owned "$f" && report "PAM module that belongs to no package: $f"; done
done
while IFS= read -r l; do report "/etc/hosts redirects a well-known site: $l"; done < <(
  grep -Ev '^[[:space:]]*(#|$)' /etc/hosts | grep -Ei 'ubuntu\.com|linuxmint\.com|mozilla|google|microsoft|uscyberpatriot')
cp_done
