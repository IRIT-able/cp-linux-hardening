#!/usr/bin/env bash
# 20-passwords-pam.sh - account lockout, null passwords, password length/history, ageing, password changes.
# Catalog: "Passwords & PAM", "Login / lockout policy".
# Order matters: pam-auth-update runs before any hand edit of /etc/pam.d/common-*.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cp_init "PAM" "$@"

CA=/etc/pam.d/common-auth
CPW=/etc/pam.d/common-password

# ---------- account lockout (pam_faillock via pam-auth-update) ----------
CP_CAT="LOCKOUT"
section "Account lockout"
write_profile() { # name, content
  local f=/usr/share/pam-configs/$1
  if [[ -e $f ]]; then echo "$f already exists, left as it is"; return 0; fi
  printf '%b' "$2" >"$f"
}
install_faillock() {
  local profiles=(faillock faillock_notify) f
  for f in /etc/pam.d/common-auth /etc/pam.d/common-account /etc/pam.d/common-password /etc/pam.d/common-session; do backup_file "$f"; done
  if (( IS_MINT )); then
    # Recipe from the Mint 21 training keys (three profiles).
    write_profile faillock 'Name: Lockout on failed logins\nDefault: no\nPriority: 0\nAuth-Type: Primary\nAuth:\n\t[default=die]\tpam_faillock.so authfail\n' || return 1
    write_profile faillock_reset 'Name: Reset lockout on success\nDefault: no\nPriority: 0\nAuth-Type: Additional\nAuth:\n\trequired\tpam_faillock.so authsucc\n' || return 1
    write_profile faillock_notify 'Name: Notify on account lockout\nDefault: no\nPriority: 1024\nAuth-Type: Primary\nAuth:\n\trequisite\tpam_faillock.so preauth\n' || return 1
    profiles+=(faillock_reset)
  else
    # Recipe from the Ubuntu 22 Training Round 2 key (two profiles).
    write_profile faillock 'Name: Enforce failed login attempt counter\nDefault: no\nPriority: 0\nAuth-Type: Primary\nAuth:\n\t[default=die]\tpam_faillock.so authfail\n\tsufficient\tpam_faillock.so authsucc\n' || return 1
    write_profile faillock_notify 'Name: Notify on failed login attempts\nDefault: no\nPriority: 1024\nAuth-Type: Primary\nAuth:\n\trequisite\tpam_faillock.so preauth\n' || return 1
  fi
  DEBIAN_FRONTEND=noninteractive pam-auth-update --enable "${profiles[@]}" || return 1
  if ! grep -q 'pam_faillock\.so' "$CA" || ! pam_sane "$CA"; then
    echo "pam-auth-update did not produce a usable common-auth; restoring the backup"
    cp -a "$CP_BACKUP$CA" "$CA"
    return 1
  fi
}
if grep -Eq '^[^#]*pam_faillock\.so' "$CA"; then
  ok "pam_faillock is in $CA"
elif [[ -z $(find /lib /usr/lib -name pam_faillock.so 2>/dev/null | head -1) ]]; then
  report "pam_faillock.so is not on this system - no lockout policy can be set this way"
elif [[ ${ENABLE_LOCKOUT,,} == no ]]; then
  skip "lockout policy not configured (ENABLE_LOCKOUT=no)"
elif ! is_apply; then
  would "add pam_faillock profiles in /usr/share/pam-configs and enable them with pam-auth-update (asks first; test on a snapshot)"
elif [[ ${ENABLE_LOCKOUT,,} == yes ]] || confirm_strict "Enable account lockout (pam_faillock)? A mistake here can block every login. Is a second root shell open?"; then
  fix "enable pam_faillock lockout via pam-auth-update" install_faillock
  info "locked out by accident?  faillock --user NAME --reset"
fi

# ---------- null passwords ----------
CP_CAT="PAM"
section "Null passwords, minimum length, history"
if grep -Eq '^[^#]*pam_unix\.so.*\bnullok' "$CA"; then
  fix "remove nullok from pam_unix.so in $CA" safe_sed "$CA" pam_sane '/^[^#]*pam_unix\.so/ s/[[:space:]]+nullok(_secure)?\b//g'
else
  ok "no nullok on pam_unix.so in $CA"
fi

# ---------- minimum length (pam_pwquality if present, and pam_unix) and history ----------
set_pam_opt() { # module-regex label key value
  local cur
  cur=$(pam_opt_min "$CPW" "$1" "$3")
  if [[ -z $cur ]]; then return 1; fi
  if (( cur >= $4 )); then ok "$2 has $3=$cur in $CPW"
  else fix "set $3=$4 on $2 in $CPW (was ${cur/#0/unset})" safe_sed "$CPW" pam_sane "$(pam_opt_script "$1" "$3" "$4")"; fi
}
set_pam_opt 'pam_pwquality\.so' pam_pwquality.so minlen "$PASS_MINLEN" \
  || info "pam_pwquality is not in use (libpam-pwquality not installed); length is set on pam_unix.so only"
set_pam_opt 'pam_unix\.so' pam_unix.so minlen "$PASS_MINLEN" || err "no pam_unix.so line in $CPW"
set_pam_opt 'pam_unix\.so' pam_unix.so remember "$PASS_REMEMBER"

# ---------- login.defs ----------
CP_CAT="PASSWORDS"
section "Password ageing defaults (/etc/login.defs)"
LD=/etc/login.defs
cur=$(kv_space_get $LD PASS_MAX_DAYS)
if [[ $cur =~ ^[0-9]+$ ]] && (( cur >= 1 && cur <= PASS_MAX_DAYS )); then ok "PASS_MAX_DAYS $cur"
else fix "PASS_MAX_DAYS $PASS_MAX_DAYS (was ${cur:-unset})" kv_space_set $LD PASS_MAX_DAYS "$PASS_MAX_DAYS"; fi
cur=$(kv_space_get $LD PASS_MIN_DAYS)
if [[ $cur =~ ^[0-9]+$ ]] && (( cur >= 1 && cur <= 7 )); then ok "PASS_MIN_DAYS $cur"
else fix "PASS_MIN_DAYS $PASS_MIN_DAYS (was ${cur:-unset})" kv_space_set $LD PASS_MIN_DAYS "$PASS_MIN_DAYS"; fi
cur=$(kv_space_get $LD PASS_WARN_AGE)
if [[ $cur =~ ^[0-9]+$ ]] && (( cur >= 7 )); then ok "PASS_WARN_AGE $cur"
else fix "PASS_WARN_AGE 7 (was ${cur:-unset})" kv_space_set $LD PASS_WARN_AGE 7; fi

# ---------- passwords from the config ----------
section "Passwords listed in SET_PASSWORDS"
set_pw() { printf '%s:%s\n' "$1" "$2" | chpasswd; }
if ! have_userlists; then
  (( ${#SET_PASSWORDS[@]} )) && report "user lists are empty in the config - no passwords will be changed"
else
  for e in "${SET_PASSWORDS[@]}"; do
    u=${e%%:*}; p=${e#*:}
    if ! id "$u" >/dev/null 2>&1; then report "SET_PASSWORDS: no such user $u"; continue; fi
    if ! is_authorized "$u"; then report "SET_PASSWORDS: $u is not an authorized user - skipped"; continue; fi
    if is_self "$u"; then skip "$u is your own account - the README says its password need not change; not touched"; continue; fi
    (( ${#p} < PASS_MINLEN )) && report "SET_PASSWORDS: the password for $u is shorter than PASS_MINLEN=$PASS_MINLEN"
    pw_matches "$u" "$p"; rc=$?
    if (( rc == 0 )); then ok "$u already has the configured password"; continue; fi
    backup_file /etc/shadow
    fix "set the configured password for $u" set_pw "$u" "$p"
  done
fi
for u in "${FORCE_PW_CHANGE[@]}"; do
  id "$u" >/dev/null 2>&1 || { report "FORCE_PW_CHANGE: no such user $u"; continue; }
  is_self "$u" && { skip "FORCE_PW_CHANGE: $u is you"; continue; }
  if [[ $(getent shadow "$u" | cut -d: -f3) == 0 ]]; then ok "$u must change password at next login"
  else backup_file /etc/shadow; fix "expire the password of $u so it must be changed at next login" passwd -e "$u"; fi
done

# ---------- root and empty passwords ----------
section "Root account and empty passwords"
rh=$(getent shadow root | cut -d: -f2)
if ! getent shadow root >/dev/null; then
  err "cannot read the shadow entry for root"
elif [[ -z $rh ]]; then
  backup_file /etc/shadow
  fix "lock root: its password is blank (passwd -l root)" passwd -l root
elif [[ $rh == \$* ]]; then
  report "root has a usable password. If the README says nobody logs in as root, lock it: passwd -l root"
else
  ok "root password is locked"
fi
while IFS=: read -r u h _; do
  [[ $u == root ]] && continue
  [[ -z $h ]] && report "$u has an EMPTY password - add it to SET_PASSWORDS, or delete the account if unauthorized"
done </etc/shadow

# ---------- per-user maximum age ----------
section "Maximum password age per user"
today=$(( $(date +%s) / 86400 ))
while read -r u; do
  IFS=: read -r _ h last _ max _ < <(getent shadow "$u")
  [[ $max =~ ^[0-9]+$ ]] && (( max >= 1 && max <= PASS_MAX_DAYS )) && { ok "$u: maximum age $max days"; continue; }
  if [[ $h == \$* && $last =~ ^[0-9]+$ ]] && (( last > 0 && last + PASS_MAX_DAYS <= today )); then
    # The password is already older than the limit, so setting the limit alone would expire it at once
    # (and lock you out of sudo). Marking it as changed today avoids that. UNTESTED for score.
    backup_file /etc/shadow
    fix "chage -M $PASS_MAX_DAYS $u, and mark the password as changed today so it does not expire at once (it is $((today-last)) days old)" chage -d "$(date +%F)" -M "$PASS_MAX_DAYS" "$u"
    continue
  fi
  backup_file /etc/shadow
  fix "chage -M $PASS_MAX_DAYS $u (was ${max:-unset})" chage -M "$PASS_MAX_DAYS" "$u"
done < <(human_users)

# ---------- weak password check (report only) ----------
section "Obviously weak passwords (tries 4 guesses per user; can take a minute)"
while read -r u; do
  for guess in "$u" password 123456 changeme; do
    if pw_matches "$u" "$guess"; then
      if is_self "$u"; then info "$u (you) has the password '$guess' - the README says you need not change it"
      else report "$u has the password '$guess' - add a strong one to SET_PASSWORDS"; fi
      break
    fi
  done
done < <(human_users)

if (( N_CHANGED )); then
  printf '%s\n' "${C_RED}${C_BLD}PAM or passwords changed. In ANOTHER terminal test now:  sudo -k; sudo true   and   su - $SELF_USER${C_RST}"
  info "to undo a PAM edit: cp -a $CP_BACKUP/etc/pam.d/. /etc/pam.d/"
fi
cp_done
