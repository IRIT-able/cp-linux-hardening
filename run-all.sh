#!/usr/bin/env bash
# run-all.sh - menu and batch runner for the hardening modules.
#   sudo ./run-all.sh                 interactive menu
#   sudo ./run-all.sh --audit         audit with every module
#   sudo ./run-all.sh --apply         apply with every module (asks for confirmation)
#   sudo ./run-all.sh --audit 10 30   only modules 10 and 30
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CP_TS="${CP_TS:-$(date +%Y%m%d-%H%M%S)}"   # one log file and one backup folder for the whole run
B=$'\e[1m'; RED=$'\e[31m'; YEL=$'\e[33m'; R=$'\e[0m'; [[ -t 1 ]] || { B=""; RED=""; YEL=""; R=""; }

if (( EUID != 0 )); then echo "Run as root:  sudo $0 $*"; exit 1; fi

mapfile -t MODULES < <(find "$HERE" -maxdepth 1 -name '[0-9]*-*.sh' -printf '%f\n' | sort -n)
describe() {
  case $1 in
    10-*) echo "users, groups, administrators, sudoers report" ;;
    20-*) echo "lockout, null passwords, length/history, ageing, password changes" ;;
    30-*) echo "SSH server settings" ;;
    40-*) echo "UFW firewall" ;;
    50-*) echo "required services, installs, unneeded services" ;;
    60-*) echo "prohibited software" ;;
    70-*) echo "prohibited media files" ;;
    80-*) echo "permissions, world-writable files, SUID report" ;;
    90-*) echo "sysctl kernel settings" ;;
    100-*) echo "backdoors and persistence (mostly report)" ;;
    110-*) echo "display manager, browser, app configs (report)" ;;
    120-*) echo "update settings and installing updates (slow; last)" ;;
  esac
}

run_modules() { # mode, module numbers... (none = all)
  local mode=$1 m num; shift
  if [[ $mode == apply ]]; then
    cat <<EOF
${RED}${B}
  APPLY MODE - this changes the system.
   1. Is there a VM snapshot (practice) or have you read the audit output (competition)?
   2. Is config.conf filled in from THIS round's README?
   3. Open a second terminal now and run:  sudo -i     Leave it open until login and sudo are tested.
${R}
EOF
    grep -q '^FORENSICS_DONE="yes"' "${CP_CONFIG:-$HERE/config.conf}" 2>/dev/null ||
      echo "${YEL}  FORENSICS_DONE is not \"yes\": users, media, packages and listeners will NOT be removed this run.${R}"
    local a; read -r -p "  Type APPLY to continue: " a
    [[ $a == APPLY ]] || { echo "  cancelled"; return 1; }
  fi
  for m in "${MODULES[@]}"; do
    num=${m%%-*}
    if (( $# )) && ! printf '%s\n' "$@" | grep -qx "$num"; then continue; fi
    bash "$HERE/$m" "--$mode" || echo "${RED}module $m exited with an error${R}"
  done
  echo
  echo "${B}Log: /root/cp-log-$CP_TS.txt${R}"
  [[ -d /root/cp-backup/$CP_TS ]] && echo "${B}Backups: /root/cp-backup/$CP_TS${R}"
  echo "Findings marked REPORT need a person:  grep REPORT /root/cp-log-$CP_TS.txt"
}

# ---------- non-interactive ----------
if (( $# )); then
  case $1 in
    --audit) shift; run_modules audit "$@"; exit ;;
    --apply) shift; run_modules apply "$@"; exit ;;
    *) sed -n '2,6p' "$0"; exit 2 ;;
  esac
fi

# ---------- menu ----------
while true; do
  echo
  echo "${B}CyberPatriot Linux hardening${R}   config: ${CP_CONFIG:-$HERE/config.conf}$([[ -f ${CP_CONFIG:-$HERE/config.conf} ]] || echo "  ${RED}(MISSING - copy config.conf.example)${R}")"
  for m in "${MODULES[@]}"; do printf '   %-4s %-24s %s\n' "${m%%-*}" "$m" "$(describe "$m")"; done
  cat <<EOF

   1) Audit everything            (changes nothing - start here)
   2) Audit selected modules
   3) Apply everything
   4) Apply selected modules
   5) Forensics helper list
   6) Show findings that need a person (from this session's log)
   q) Quit
EOF
  read -r -p "Choice: " c
  case $c in
    1) run_modules audit ;;
    2) read -r -p "Module numbers, space separated (e.g. 10 30 40): " -a sel; (( ${#sel[@]} )) && run_modules audit "${sel[@]}" ;;
    3) run_modules apply ;;
    4) read -r -p "Module numbers, space separated (e.g. 10 30 40): " -a sel; (( ${#sel[@]} )) && run_modules apply "${sel[@]}" ;;
    5) bash "$HERE/forensics-helpers.sh" help ;;
    6) grep -E 'REPORT|ERROR' "/root/cp-log-$CP_TS.txt" 2>/dev/null || echo "nothing logged yet" ;;
    q|Q) exit 0 ;;
  esac
done
