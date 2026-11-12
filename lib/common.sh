#!/usr/bin/env bash
# lib/common.sh - shared helpers. Sourced by every module; never run directly.
# Sourcing has no side effects. cp_init does the root check, logging and config load.

[[ -n "${CP_LIB_LOADED:-}" ]] && return 0
CP_LIB_LOADED=1
set -u

CP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CP_TS="${CP_TS:-$(date +%Y%m%d-%H%M%S)}"
CP_STATE_DIR="${CP_STATE_DIR:-/root}"   # override only for testing the scripts themselves
CP_LOG="$CP_STATE_DIR/cp-log-$CP_TS.txt"
CP_BACKUP="$CP_STATE_DIR/cp-backup/$CP_TS"
CP_CONFIG="${CP_CONFIG:-$CP_ROOT/config.conf}"
CP_CAT="GENERAL"
MODE="audit"
CONFIG_LOADED=0
CONFIRM_ALL=0
N_WOULD=0; N_CHANGED=0; N_REPORT=0; N_ERR=0

if [[ -t 1 ]]; then
  C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_BLU=$'\e[34m'
  C_MAG=$'\e[35m'; C_CYN=$'\e[36m'; C_BLD=$'\e[1m'; C_RST=$'\e[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_MAG=""; C_CYN=""; C_BLD=""; C_RST=""
fi

# ---------- config defaults (config.conf overrides these) ----------
AUTHORIZED_ADMINS=(); AUTHORIZED_USERS=(); CURRENT_USER=""
REQUIRED_SERVICES=(); REQUIRED_PACKAGES=(); INSTALL_PACKAGES=()
DISABLE_SERVICES=(); REMOVE_PACKAGES=()
GROUPS_CREATE=(); GROUP_ADD=(); NEW_USERS=(); SET_PASSWORDS=(); FORCE_PW_CHANGE=()
MEDIA_KEEP_PATHS=(/srv /var/www)
UFW_ALLOW=()
FORENSICS_DONE="no"
PASS_MINLEN=12; PASS_MAX_DAYS=90; PASS_MIN_DAYS=2; PASS_REMEMBER=5
ENABLE_LOCKOUT="ask"
SYSCTL_EXTRA="yes"; ALLOW_IP_FORWARD="no"
FTP_MODE=""; FTP_ROOT="/srv/ftp"; FTP_ANON_ROOT="/var/ftp"
REMOVE_FILES=()

# ---------- logging ----------
_log() { # status color message...
  local status=$1 color=$2; shift 2
  local line="[$CP_CAT] [$status] $*"
  printf '%s%s%s\n' "$color" "$line" "$C_RST"
  [[ -w "$CP_LOG" ]] && printf '%s %s\n' "$(date +%T)" "$line" >>"$CP_LOG"
  return 0
}
ok()      { _log "OK" "$C_GRN" "$@"; }
info()    { _log "INFO" "$C_BLU" "$@"; }
would()   { N_WOULD=$((N_WOULD+1)); _log "WOULD CHANGE" "$C_YEL" "$@"; }
changed() { N_CHANGED=$((N_CHANGED+1)); _log "CHANGED" "$C_CYN" "$@"; }
report()  { N_REPORT=$((N_REPORT+1)); _log "REPORT - human decision" "$C_MAG" "$@"; }
skip()    { _log "SKIPPED" "$C_YEL" "$@"; }
err()     { N_ERR=$((N_ERR+1)); _log "ERROR" "$C_RED" "$@"; }
section() { printf '\n%s== %s ==%s\n' "$C_BLD" "$*" "$C_RST"; [[ -w "$CP_LOG" ]] && printf '\n== %s ==\n' "$*" >>"$CP_LOG"; return 0; }

is_apply() { [[ $MODE == apply ]]; }

# fix "description" command args...
# Audit: logs what would change. Apply: runs the command and logs the result.
fix() {
  local desc=$1; shift
  if ! is_apply; then would "$desc"; return 0; fi
  if "$@" >>"$CP_LOG" 2>&1; then changed "$desc"; return 0; fi
  err "FAILED: $desc (details in $CP_LOG)"; return 1
}

# Prompts talk to /dev/tty, not stdin: many checks run inside "while read ...; done < <(command)" loops,
# where stdin is the command's output. (Found on the Debian run: every prompt in such a loop was skipped.)
have_tty() { { : </dev/tty; } 2>/dev/null; }

confirm() { # yes / no / all-in-this-module
  (( CONFIRM_ALL )) && return 0
  # CP_ASSUME_YES=1 answers yes to these prompts for unattended runs. It does not cover confirm_strict.
  if [[ ${CP_ASSUME_YES:-0} == 1 ]]; then info "assumed yes (CP_ASSUME_YES): $1"; return 0; fi
  have_tty || { skip "needs a yes/no answer but there is no terminal: $1"; return 1; }
  local a
  printf '%s?? %s [y/N/a = yes to all in this module] %s' "$C_YEL" "$1" "$C_RST" >/dev/tty
  read -r a </dev/tty
  case $a in
    a|A) CONFIRM_ALL=1; return 0 ;;
    y|Y|yes|YES) return 0 ;;
    *) skip "declined: $1"; return 1 ;;
  esac
}

confirm_strict() { # must type the word; never covered by "all"
  have_tty || { skip "needs confirmation but there is no terminal: $1"; return 1; }
  local a
  printf '%s?? %s  Type YES to continue: %s' "$C_RED" "$1" "$C_RST" >/dev/tty
  read -r a </dev/tty
  [[ $a == YES ]] || { skip "declined: $1"; return 1; }
}

# ---------- startup ----------
cp_usage() {
  cat <<EOF
Usage: sudo $0 [--audit | --apply] [--config FILE]
  --audit   report what would change, change nothing (default)
  --apply   make the changes
  --config  path to config.conf (default: $CP_ROOT/config.conf)
EOF
}

detect_os() {
  OS_ID="unknown"; OS_VER="unknown"; OS_NAME="unknown"
  if [[ -r /etc/os-release ]]; then
    OS_ID=$(. /etc/os-release; echo "${ID:-unknown}")
    OS_VER=$(. /etc/os-release; echo "${VERSION_ID:-unknown}")
    OS_NAME=$(. /etc/os-release; echo "${PRETTY_NAME:-unknown}")
  fi
  IS_MINT=0; [[ $OS_ID == linuxmint ]] && IS_MINT=1
  case "$OS_ID:$OS_VER" in
    ubuntu:22.04|ubuntu:24.04|linuxmint:21*|linuxmint:22*|debian:12*) OS_SUPPORTED=1 ;;
    *) OS_SUPPORTED=0 ;;
  esac
}

valid_name() { [[ $1 =~ ^[a-z_][a-z0-9_.-]*\$?$ ]]; }

load_config() {
  if [[ ! -f "$CP_CONFIG" ]]; then
    if is_apply; then err "no config file at $CP_CONFIG - copy config.conf.example to config.conf and fill it in from the README"; exit 1; fi
    report "no config file at $CP_CONFIG - audit continues, but nothing README-dependent can be judged"
    return 0
  fi
  # The config is sourced as root, so refuse one that another user could have written.
  local owner mode
  owner=$(stat -c %U "$CP_CONFIG"); mode=$(stat -c %a "$CP_CONFIG")
  if [[ $owner != root && $owner != "${SUDO_USER:-root}" ]] || (( 8#$mode & 8#002 )); then
    err "$CP_CONFIG is owned by '$owner' with mode $mode - it must belong to you or root and not be world-writable"; exit 1
  fi
  if ! bash -n "$CP_CONFIG" 2>>"$CP_LOG"; then err "$CP_CONFIG has a bash syntax error"; exit 1; fi
  # shellcheck disable=SC1090
  . "$CP_CONFIG"
  CONFIG_LOADED=1
  local n
  for n in "${AUTHORIZED_ADMINS[@]}" "${AUTHORIZED_USERS[@]}"; do
    valid_name "$n" || { err "config: '$n' is not a valid user name (lower case, no spaces, no '(you)')"; exit 1; }
  done
}

cp_init() { # category "$@"
  CP_CAT=$1; shift
  while (( $# )); do
    case $1 in
      --audit) MODE=audit ;;
      --apply) MODE=apply ;;
      --config) CP_CONFIG=${2:?--config needs a file}; shift ;;
      -h|--help) cp_usage; exit 0 ;;
      *) echo "Unknown option: $1"; cp_usage; exit 2 ;;
    esac
    shift
  done
  if (( EUID != 0 )); then echo "Run as root:  sudo $0 --$MODE"; exit 1; fi
  mkdir -p "$CP_STATE_DIR/cp-backup"; touch "$CP_LOG"; chmod 600 "$CP_LOG"
  detect_os
  INVOKER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
  UID_MIN=$(awk '$1=="UID_MIN"{print $2}' /etc/login.defs 2>/dev/null); UID_MIN=${UID_MIN:-1000}
  section "$(basename "$0")  mode=$MODE  os=$OS_NAME  log=$CP_LOG"
  load_config
  SELF_USER="${CURRENT_USER:-$INVOKER}"
  (( OS_SUPPORTED )) || report "this OS ($OS_NAME) is not one the scripts were written for (Ubuntu 22.04/24.04, Mint 21/22, Debian 12)"
  if is_apply; then
    printf '%s%s%s\n' "$C_RED$C_BLD" "APPLY MODE. Keep a second root shell open (sudo -i in another terminal) until you have tested login and sudo." "$C_RST"
  fi
}

cp_done() {
  section "summary for $(basename "$0"): would-change=$N_WOULD changed=$N_CHANGED reports=$N_REPORT errors=$N_ERR"
  is_apply && [[ -d $CP_BACKUP ]] && info "backups of edited files: $CP_BACKUP"
  return 0
}

forensics_gate() { # destructive steps wait until the forensics questions are answered
  is_apply || return 0
  [[ ${FORENSICS_DONE,,} == yes ]] && return 0
  skip "$1 - set FORENSICS_DONE=\"yes\" in config.conf once every forensics question is answered"
  return 1
}

# ---------- lists and protection ----------
in_list() { local x=$1 e; shift; for e in "$@"; do [[ $e == "$x" ]] && return 0; done; return 1; }

have_userlists() { (( ${#AUTHORIZED_ADMINS[@]} + ${#AUTHORIZED_USERS[@]} > 0 )); }
is_authorized()  { in_list "$1" "${AUTHORIZED_ADMINS[@]}" "${AUTHORIZED_USERS[@]}"; }
is_self()        { [[ $1 == "$INVOKER" || $1 == "$SELF_USER" ]]; }

human_users() { awk -F: -v min="$UID_MIN" '$3>=min && $3<60000 {print $1}' /etc/passwd; }

# Anything belonging to the CyberPatriot scoring engine is never touched.
is_protected_path() {
  case "${1,,}" in */cyberpatriot*|*/ccs*|*ccsclient*|*scoring*report*|*uniqueid*) return 0 ;; esac
  return 1
}

svc_key() { # normalise a service name for comparison only
  local s=${1,,}; s=${s%.service}
  case $s in
    sshd|ssh|openssh|openssh-server) echo ssh ;;
    ftp|vsftp|vsftpd) echo vsftpd ;;
    apache|apache2|httpd) echo apache2 ;;
    mysql|mysqld|mariadb|mariadbd) echo mysql ;;
    samba|smb|smbd) echo smbd ;;
    bind|bind9|named) echo named ;;
    x2go|x2goserver) echo x2goserver ;;
    cups|cupsd) echo cups ;;
    *) echo "$s" ;;
  esac
}

is_protected_service() {
  local k e; k=$(svc_key "$1")
  case $k in *ccs*|*cyberpatriot*|*scoring*) return 0 ;; esac
  for e in "${REQUIRED_SERVICES[@]}"; do [[ $(svc_key "$e") == "$k" ]] && return 0; done
  return 1
}

svc_packages() { # packages that provide a required service
  case $(svc_key "$1") in
    ssh) echo "openssh-server openssh-sftp-server openssh-client" ;;
    vsftpd) echo "vsftpd" ;;
    apache2) echo "apache2 apache2-bin apache2-data apache2-utils" ;;
    nginx) echo "nginx nginx-*" ;;
    mysql) echo "mysql-server* mariadb-server* mysql-common mariadb-common" ;;
    smbd) echo "samba samba-*" ;;
    named) echo "bind9 bind9-*" ;;
    x2goserver) echo "x2goserver x2goserver-*" ;;
    *) svc_key "$1" ;;
  esac
}

is_protected_pkg() {
  local p=$1 e pat
  case ${p,,} in sudo|*ccs*|*cyberpatriot*) return 0 ;; esac
  for e in "${REQUIRED_PACKAGES[@]}" "${INSTALL_PACKAGES[@]}"; do
    # shellcheck disable=SC2053
    [[ $p == $e || $p == "$e":* ]] && return 0
  done
  for e in "${REQUIRED_SERVICES[@]}"; do
    for pat in $(svc_packages "$e"); do
      # shellcheck disable=SC2053
      [[ $p == $pat ]] && return 0
    done
  done
  return 1
}

# Package ownership. "dpkg -S" per file is slow, so the list of every packaged file is loaded once.
# On merged-/usr systems dpkg may record /lib/x or /usr/lib/x for the same file, so each spelling is tried.
declare -A _DPKG_FILES=()
_DPKG_LOADED=0
_path_spellings() { # path -> SPELLINGS array
  local p=$1 r
  r=$(readlink -f "$p" 2>/dev/null)
  SPELLINGS=("$p")
  [[ -n $r && $r != "$p" ]] && SPELLINGS+=("$r")
  case $p in /usr/*) SPELLINGS+=("${p#/usr}") ;; *) SPELLINGS+=("/usr$p") ;; esac
}
is_pkg_file() { # call directly, not inside $(...), so the cache is kept
  local l c
  if (( ! _DPKG_LOADED )); then
    # Read from a real file: bash reads a pipe one byte at a time, which is several times slower.
    local t; t=$(mktemp)
    cat /var/lib/dpkg/info/*.list >"$t" 2>/dev/null
    while IFS= read -r l; do _DPKG_FILES[$l]=1; done <"$t"
    rm -f "$t"
    _DPKG_LOADED=1
  fi
  _path_spellings "$1"
  for c in "${SPELLINGS[@]}"; do [[ -n ${_DPKG_FILES[$c]:-} ]] && return 0; done
  return 1
}
pkg_owner() { # prints the owning package name (slow; use is_pkg_file for yes/no)
  local c out
  _path_spellings "$1"
  for c in "${SPELLINGS[@]}"; do
    out=$(dpkg -S "$c" 2>/dev/null | head -1 | cut -d: -f1)
    [[ -n $out ]] && { echo "$out"; return 0; }
  done
  return 1
}

pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'ok installed'; }

# Names of installed packages matching dpkg glob patterns.
pkgs_matching() {
  dpkg-query -W -f='${Package}\t${Status}\n' "$@" 2>/dev/null | awk -F'\t' '$2 ~ /ok installed/ {print $1}' | sort -u
}

# apt_would_remove <apt-get args...> : packages a command would remove (simulation only)
apt_would_remove() { apt-get -s "$@" 2>/dev/null | awk '/^(Remv|Purg) /{print $2}' | sort -u; }

# Returns 1 and reports if the simulated command would remove a protected package.
apt_safe() {
  local p bad=0
  while read -r p; do
    [[ -z $p ]] && continue
    if is_protected_pkg "$p"; then err "refusing: 'apt-get $*' would also remove protected package $p"; bad=1; fi
  done < <(apt_would_remove "$@")
  return $bad
}

# ---------- Linux Mint package sources ----------
# The Mint training image ships with its official sources commented out ("Your APT configuration is corrupt").
# Only lines for the three official hosts in Mint's own sources file are re-enabled; nothing else is touched.
MINT_SRC=/etc/apt/sources.list.d/official-package-repositories.list
MINT_SRC_RE='^#[[:space:]]*deb[[:space:]]+https?://(packages\.linuxmint\.com|archive\.ubuntu\.com|security\.ubuntu\.com)[/[:space:]]'
mint_sources_repair() { backup_file "$MINT_SRC"; sed -E -i "\\,$MINT_SRC_RE, s,^#[[:space:]]*,," "$MINT_SRC"; }
fix_mint_sources() {
  (( IS_MINT )) && [[ -f $MINT_SRC ]] || return 0
  local n; n=$(grep -Ec "$MINT_SRC_RE" "$MINT_SRC")
  (( n > 0 )) || return 0
  grep -E "$MINT_SRC_RE" "$MINT_SRC" | sed 's/^/      /'
  fix "re-enable $n official package source line(s) that are commented out in $MINT_SRC [the keys repair this through Update Manager]" mint_sources_repair
}

# ---------- Debian package sources ----------
# The Debian 12 training image points apt at a frozen 2023 snapshot (snapshot.debian.org), so nothing can be
# updated. The standard bookworm sources from the Debian documentation are put in its place.
# Only acts when there is no official current source at all. UNTESTED for score.
DEB_SRC=/etc/apt/sources.list
debian_sources_repair() {
  local code; code=$(. /etc/os-release; echo "${VERSION_CODENAME:-bookworm}")
  backup_file "$DEB_SRC"
  sed -E -i 's,^([[:space:]]*deb(-src)?[[:space:]].*snapshot\.debian\.org.*)$,# disabled by cp scripts: \1,; s,^([[:space:]]*deb[[:space:]]+cdrom:.*)$,# disabled by cp scripts: \1,' "$DEB_SRC"
  cat >>"$DEB_SRC" <<EOF
deb http://deb.debian.org/debian $code main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $code-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security $code-security main contrib non-free non-free-firmware
EOF
}
fix_debian_sources() {
  [[ $OS_ID == debian && -f $DEB_SRC ]] || return 0
  grep -rqsE '^[[:space:]]*deb[[:space:]].*(deb\.debian\.org|security\.debian\.org)|^URIs:.*(deb\.debian\.org|security\.debian\.org)' "$DEB_SRC" /etc/apt/sources.list.d/ && return 0
  grep -E '^[[:space:]]*deb' "$DEB_SRC" | sed 's/^/      current: /'
  fix "replace the frozen/missing package sources in $DEB_SRC with the standard Debian main, updates and security sources [Debian documentation; untested for score]" debian_sources_repair
}
fix_os_sources() { fix_mint_sources; fix_debian_sources; }

# ---------- file editing ----------
backup_file() {
  local f=$1
  is_apply || return 0
  [[ $f == /* && -e $f ]] || return 0
  [[ -e "$CP_BACKUP$f" ]] && return 0
  mkdir -p "$CP_BACKUP$(dirname "$f")" && cp -a "$f" "$CP_BACKUP$f"
}

# safe_sed <file> <checker> <sed -E script>
# Edits a copy, runs "<checker> <copy>", and only then replaces the real file (after a backup).
safe_sed() {
  local f=$1 checker=$2 script=$3 tmp
  tmp=$(mktemp) || return 1
  if ! sed -E "$script" "$f" >"$tmp"; then rm -f "$tmp"; return 1; fi
  if ! $checker "$tmp"; then rm -f "$tmp"; echo "validation failed, $f left unchanged"; return 1; fi
  backup_file "$f" && cat "$tmp" >"$f"
  local rc=$?
  rm -f "$tmp"; return $rc
}

# "key value" files (login.defs)
kv_space_get() { awk -v k="$2" '$1==k {v=$2} END{print v}' "$1"; }
kv_space_set() { # file key value
  local f=$1 k=$2 v=$3
  backup_file "$f"
  if grep -Eq "^[[:space:]]*$k[[:space:]]" "$f"; then
    sed -E -i "s|^[[:space:]]*$k[[:space:]].*|$k\t$v|" "$f"
  elif grep -Eq "^#[[:space:]]*$k[[:space:]]" "$f"; then
    sed -E -i "0,/^#[[:space:]]*$k[[:space:]].*/s||$k\t$v|" "$f"
  else
    printf '%s\t%s\n' "$k" "$v" >>"$f"
  fi
}

# "key = value" files (sysctl.conf)
kv_eq_get() { # file key -> last active value
  awk -F= -v k="$2" '{key=$1; gsub(/[ \t]/,"",key)} key==k {v=$2; gsub(/[ \t]/,"",v)} END{print v}' "$1" 2>/dev/null
}
kv_eq_set() { # file key value
  local f=$1 k=$2 v=$3 re=${2//./\\.}
  backup_file "$f"
  if grep -Eq "^[[:space:]]*$re[[:space:]]*=" "$f"; then
    sed -E -i "s|^[[:space:]]*$re[[:space:]]*=.*|$k=$v|" "$f"
  elif grep -Eq "^#[[:space:]]*$re[[:space:]]*=" "$f"; then
    sed -E -i "0,/^#[[:space:]]*$re[[:space:]]*=.*/s||$k=$v|" "$f"
  else
    printf '%s=%s\n' "$k" "$v" >>"$f"
  fi
}

# sshd_config: print the file with "Key value" set once, outside any Match block.
ssh_set_in() { # file key value -> stdout
  awk -v k="$2" -v v="$3" '
    BEGIN { kl = tolower(k) }
    {
      line = $0; t = $0; sub(/^[ \t]+/, "", t)
      n = split(t, a, /[ \t=]+/); first = tolower(a[1])
    }
    first == "match" && !inmatch { if (!done) { print k " " v; done = 1 } inmatch = 1 }
    !inmatch && first == kl { if (!done) { print k " " v; done = 1 } next }
    !inmatch && !done && tolower(t) ~ ("^#[ \t]*" kl "[ \t]") { print k " " v; done = 1; next }
    { print line }
    END { if (!done) print k " " v }' "$1"
}

# cron_install <cron file> <new content file>
# User crontabs go through crontab(1): cron only rereads the spool when it is told to, so writing the file
# directly leaves the old job running (the Debian netcat backdoor kept respawning for this reason).
cron_install() {
  local f=$1 new=$2
  backup_file "$f"
  case $f in
    /var/spool/cron/crontabs/*) grep -vE '^# (DO NOT EDIT THIS FILE|\(.* installed on|\(Cron version)' "$new" | crontab -u "$(basename "$f")" - ;;
    *) cat "$new" >"$f" ;;
  esac
}

# ---------- PAM ----------
pam_sane() { # structural check of a pam.d file; there is no official PAM validator
  awk '
    /^[[:space:]]*(#|$)/ { next }
    $1 == "@include" { if (NF < 2) bad = 1; next }
    { t = $1; sub(/^-/, "", t); if (t !~ /^(auth|account|password|session)$/ || NF < 3) bad = 1 }
    END { exit bad }' "$1" && grep -q 'pam_unix\.so' "$1"
}

# Smallest value of key=N across active lines naming the module ("" if no such line, 0 if a line lacks the key).
pam_opt_min() { # file module-regex key
  awk -v m="$2" -v k="$3" '
    /^[[:space:]]*#/ { next }
    $0 ~ m {
      v = 0
      for (i = 1; i <= NF; i++) if (index($i, k "=") == 1) v = substr($i, length(k) + 2) + 0
      if (!seen || v < min) min = v
      seen = 1
    }
    END { if (seen) print min }' "$1"
}

pam_opt_script() { # module-regex key value -> sed script that sets key=value on the module's lines
  printf '/^[^#]*%s/ { s/[[:space:]]+%s=[^[:space:]]+//g; s/[[:space:]]*$/ %s=%s/ }' "$1" "$2" "$2" "$3"
}

# ---------- passwords ----------
# pw_matches user password : 0 = matches the stored hash, 1 = does not, 2 = cannot tell
pw_matches() {
  local h
  h=$(getent shadow "$1" | cut -d: -f2)
  [[ -z $h || $h == [!\$]* ]] && return 1
  CP_PW="$2" CP_H="$h" python3 - 2>/dev/null <<'EOF'
import os, sys
try:
    import crypt
    r = crypt.crypt(os.environ["CP_PW"], os.environ["CP_H"])
except Exception:
    sys.exit(2)
if r is None:
    sys.exit(2)
sys.exit(0 if r == os.environ["CP_H"] else 1)
EOF
}
