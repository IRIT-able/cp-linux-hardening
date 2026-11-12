#!/usr/bin/env bash
# 10-users.sh - user accounts, groups, administrator rights, sudoers (report only).
# Catalog: "User accounts & groups", "Sudoers".
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cp_init "USERS" "$@"

ADMIN_GROUPS=(sudo)
getent group admin >/dev/null && ADMIN_GROUPS+=(admin)
getent group wheel >/dev/null && ADMIN_GROUPS+=(wheel)

group_members() { # supplementary members plus users whose primary group it is
  local g=$1 gid
  gid=$(getent group "$g" | cut -d: -f3) || return 0
  { getent group "$g" | cut -d: -f4 | tr ',' '\n'; awk -F: -v g="$gid" '$4==g {print $1}' /etc/passwd; } | sed '/^$/d' | sort -u
}
in_group() { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"; }
backup_accounts() { local f; for f in /etc/passwd /etc/shadow /etc/group /etc/gshadow; do backup_file "$f"; done; }

del_user() { pkill -KILL -u "$1" 2>/dev/null; sleep 1; deluser --remove-home "$1"; }
make_user() { adduser --disabled-password --gecos "" "$1"; }

USER_CHANGES_OK=1
if ! have_userlists; then
  USER_CHANGES_OK=0
  report "AUTHORIZED_ADMINS and AUTHORIZED_USERS are empty - no user will be added, removed or changed"
elif [[ -z $SELF_USER || $SELF_USER == root ]]; then
  USER_CHANGES_OK=0
  report "cannot tell which account is yours - set CURRENT_USER in config.conf; no user changes will be made"
elif ! in_list "$SELF_USER" "${AUTHORIZED_ADMINS[@]}"; then
  USER_CHANGES_OK=0
  report "your account '$SELF_USER' is not in AUTHORIZED_ADMINS - the config looks wrong, so no user changes will be made"
fi

# ---------- requested groups and new accounts (from the README) ----------
section "README requests: groups and new accounts"
if (( USER_CHANGES_OK )); then
  for g in "${GROUPS_CREATE[@]}"; do
    if getent group "$g" >/dev/null; then ok "group $g exists"
    else backup_accounts; fix "create group $g" addgroup "$g"; fi
  done
  for e in "${NEW_USERS[@]}"; do
    u=${e%%:*}; role=${e#*:}
    if ! is_authorized "$u"; then err "NEW_USERS: $u is not in the authorized lists - add it there first"; continue; fi
    if id "$u" >/dev/null 2>&1; then ok "user $u exists"
    else
      backup_accounts
      fix "create user $u (no password yet - put one in SET_PASSWORDS and run 20-passwords-pam.sh)" make_user "$u"
    fi
    [[ $role == admin ]] && ! in_list "$u" "${AUTHORIZED_ADMINS[@]}" && err "NEW_USERS: $u is marked admin but is not in AUTHORIZED_ADMINS"
  done
  for e in "${GROUP_ADD[@]}"; do
    u=${e%%:*}; g=${e#*:}
    if ! getent group "$g" >/dev/null; then
      in_list "$g" "${GROUPS_CREATE[@]}" && ! is_apply && { would "add $u to group $g (after the group is created)"; continue; }
      report "GROUP_ADD: group $g does not exist (add it to GROUPS_CREATE if the README asks for it)"; continue
    fi
    if ! id "$u" >/dev/null 2>&1; then report "GROUP_ADD: user $u does not exist"; continue; fi
    if in_group "$u" "$g"; then ok "$u is in group $g"
    else backup_accounts; fix "add $u to group $g" gpasswd -a "$u" "$g"; fi
  done
fi

# ---------- unauthorized and missing accounts ----------
section "Accounts compared with the README lists"
mapfile -t HUMANS < <(human_users)
if (( USER_CHANGES_OK )); then
  to_delete=()
  for u in "${HUMANS[@]}"; do
    if is_authorized "$u"; then continue; fi
    if is_self "$u"; then err "$u is the account you are using but is not authorized - never deleted"; continue; fi
    to_delete+=("$u")
  done
  for u in "${AUTHORIZED_ADMINS[@]}" "${AUTHORIZED_USERS[@]}"; do
    id "$u" >/dev/null 2>&1 || report "authorized user $u has no account (check spelling in config.conf; create it only if the README says to)"
  done
  n_auth_present=0
  for u in "${HUMANS[@]}"; do is_authorized "$u" && n_auth_present=$((n_auth_present+1)); done
  if (( ${#to_delete[@]} == 0 )); then
    ok "no unauthorized accounts with UID >= $UID_MIN"
  elif (( ${#to_delete[@]} >= n_auth_present )); then
    err "config would delete ${#to_delete[@]} accounts and keep $n_auth_present - that looks like a wrong config; nothing deleted: ${to_delete[*]}"
  else
    for u in "${to_delete[@]}"; do
      if ! is_apply; then would "delete unauthorized user $u and its home directory"; continue; fi
      forensics_gate "delete user $u" || continue
      backup_accounts
      fix "delete unauthorized user $u and its home directory" del_user "$u"
    done
  fi
else
  info "human accounts (UID >= $UID_MIN): ${HUMANS[*]}"
fi

# ---------- hidden accounts: UID below UID_MIN that look like a person's login ----------
section "Hidden login accounts (UID 1-$((UID_MIN-1)))"
found_hidden=0
while IFS=: read -r u _ uid _ _ home shell; do
  (( uid >= 1 && uid < UID_MIN )) || continue
  reasons=()
  hash=$(getent shadow "$u" | cut -d: -f2)
  [[ $hash == \$* ]] && reasons+=("has a usable password")
  [[ $home == /home/* && -d $home ]] && reasons+=("home directory $home exists")
  grep -qxF "$shell" /etc/shells 2>/dev/null && reasons+=("login shell $shell")
  (( ${#reasons[@]} )) || continue
  found_hidden=1
  if is_authorized "$u"; then info "$u (UID $uid) is authorized but has a system UID: ${reasons[*]}"; continue; fi
  # A usable password on a system UID is the sign of a hidden person's account (the Mint training images did this).
  # Stock service accounts (syslog, cups-pk-helper, ...) have no password, so they are never offered for deletion.
  if [[ $hash == \$* ]] && (( USER_CHANGES_OK )) && ! is_self "$u"; then
    if ! is_apply; then would "delete hidden user $u (UID $uid: ${reasons[*]}) - you will be asked first"; continue; fi
    forensics_gate "delete hidden user $u" || continue
    confirm "Delete hidden user $u (UID $uid: ${reasons[*]})?" || continue
    backup_accounts
    fix "delete hidden user $u" del_user "$u"
  else
    report "$u (UID $uid): ${reasons[*]} - service accounts such as postgres can be legitimate; check the README"
  fi
done </etc/passwd
(( found_hidden )) || ok "no system-UID account has a password, a /home directory or a login shell"

# ---------- administrator rights ----------
section "Administrator rights (groups: ${ADMIN_GROUPS[*]})"
if (( USER_CHANGES_OK )); then
  for g in "${ADMIN_GROUPS[@]}"; do
    while read -r u; do
      [[ -z $u ]] && continue
      if in_list "$u" "${AUTHORIZED_ADMINS[@]}"; then continue; fi
      if is_self "$u"; then err "$u is you; not removing from $g"; continue; fi
      id "$u" >/dev/null 2>&1 || continue
      backup_accounts
      fix "remove $u from group $g (not an authorized administrator)" gpasswd -d "$u" "$g"
    done < <(group_members "$g")
  done
  for u in "${AUTHORIZED_ADMINS[@]}"; do
    id "$u" >/dev/null 2>&1 || continue
    if in_group "$u" sudo; then ok "administrator $u is in sudo"
    else backup_accounts; fix "add authorized administrator $u to group sudo" gpasswd -a "$u" sudo; fi
  done
else
  for g in "${ADMIN_GROUPS[@]}"; do info "members of $g: $(group_members "$g" | tr '\n' ' ')"; done
fi
for g in root adm shadow disk lxd docker; do
  getent group "$g" >/dev/null || continue
  extra=()
  while read -r u; do
    [[ -z $u || $u == root || $u == syslog ]] && continue
    in_list "$u" "${AUTHORIZED_ADMINS[@]}" && continue
    extra+=("$u")
  done < <(group_members "$g")
  (( ${#extra[@]} )) && report "non-administrators in privileged group $g: ${extra[*]} (remove each with: gpasswd -d NAME $g, unless the README explains it)"
done

# ---------- hunting ----------
section "Hunting: UID 0, duplicate IDs, shells"
uid0=$(awk -F: '$3==0 && $1!="root" {print $1}' /etc/passwd | tr '\n' ' ')
if [[ -n $uid0 ]]; then report "UID 0 accounts other than root: $uid0- remove the account or give it a normal UID by hand"
else ok "root is the only UID 0 account"; fi
gid0=$(awk -F: '$4==0 && $1!="root" {print $1}' /etc/passwd | tr '\n' ' ')
[[ -n $gid0 ]] && report "accounts whose primary group is root (GID 0): $gid0"
dups=$(cut -d: -f3 /etc/passwd | sort | uniq -d | tr '\n' ' ')
[[ -n $dups ]] && report "duplicate UIDs in /etc/passwd: $dups"
dupn=$(cut -d: -f1 /etc/passwd | sort | uniq -d | tr '\n' ' ')
[[ -n $dupn ]] && report "duplicate user names in /etc/passwd: $dupn"
while IFS=: read -r u _ uid _ _ _ shell; do
  (( uid >= UID_MIN && uid < 60000 )) || [[ $u == root ]] || continue
  case $shell in
    /bin/bash|/usr/bin/bash|/bin/sh|/usr/bin/sh|/bin/dash|/usr/bin/dash|/bin/zsh|/usr/bin/zsh) ;;
    /usr/sbin/nologin|/sbin/nologin|/bin/false|/usr/bin/false) info "$u cannot log in (shell $shell)" ;;
    *) report "$u has an unusual shell: '$shell'" ;;
  esac
done </etc/passwd

# ---------- sudoers (report only: no key scored a sudoers item) ----------
CP_CAT="SUDOERS"
section "Sudoers (report only)"
if visudo -c >>"$CP_LOG" 2>&1; then ok "visudo -c: syntax is valid"; else err "visudo -c reports a syntax error - fix with visudo before anything else"; fi
for f in /etc/sudoers /etc/sudoers.d/*; do
  [[ -f $f ]] || continue
  [[ $(basename "$f") == README ]] && continue
  while IFS= read -r line; do
    case $line in
      *NOPASSWD*|*'!authenticate'*)
        if [[ $f == /etc/sudoers.d/* && ! $line =~ NOPASSWD:[[:space:]]*ALL ]] && is_pkg_file "$f"; then
          info "$f (shipped by a package): no-password rule for one command: $line"
        else report "$f: no-password rule: $line"; fi ;;
      *'!env_reset'*|*visiblepw*|*timestamp_timeout=-1*|*'!requiretty'*) report "$f: weakened default: $line" ;;
      Defaults*|root*|%sudo*|%admin*|@include*|'#include'*) ;;
      *) report "$f: extra rule (who is this for?): $line" ;;
    esac
  done < <(grep -Ev '^[[:space:]]*(#($|[^i])|$)' "$f")
done
info "edit sudoers only with: visudo   or   visudo -f /etc/sudoers.d/<file>"

cp_done
