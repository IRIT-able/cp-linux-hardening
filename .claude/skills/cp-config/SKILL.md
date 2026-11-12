---
name: cp-config
description: Turn a CyberPatriot Linux image README into a filled-in config.conf for the cp-linux hardening scripts. Use when the user pastes or points to a CyberPatriot README (Ubuntu, Linux Mint or Debian) and asks for the config, the conf file, or "set this image up".
---

# CyberPatriot README → config.conf

You are given the README from a CyberPatriot Linux image. Produce one file, `config.conf`, that the scripts in this repository read. The config is a bash file that gets sourced as root, so it must be syntactically valid and contain nothing but assignments and comments.

Start from `config.conf.example` in the repository root: keep its variable names and order. `configs/` holds two finished examples made from real READMEs; read one if you are unsure of the style.

## The one rule that matters

Every value must come from the README text. Never add a user, service or package because it is "usually" there, and never carry anything over from another image. The same thing can be required on one image and a scored removal on another (Wireshark and vsftpd both have been). If the README does not say, leave the list empty and say so in your reply.

## How to read the README

| README text | Variable | Notes |
|---|---|---|
| "Authorized Administrators:" list | `AUTHORIZED_ADMINS` | Names only. Drop "(you)" and every `password:` line. |
| "Authorized Users:" list | `AUTHORIZED_USERS` | One name per line in the README; all of them. |
| The administrator marked "(you)" | `CURRENT_USER` | Exactly one. If none is marked, ask. |
| "Critical Services:" list, and sentences such as "sshd is a critical service", "the FTP server must remain operational" | `REQUIRED_SERVICES` | Use the systemd name: `sshd`, `vsftpd`, `apache2`, `nginx`, `smbd`, `mysql`. |
| Software that must be present: "default web browser should be Firefox", "must have access to Thunderbird and Perl", "X is an authorized program" | `REQUIRED_PACKAGES` | apt package names, see below. Authorized-but-suspicious tools go here too, so the scripts will not remove them. |
| "Management now requires X installed", or required software that the image may lack | `INSTALL_PACKAGES` | Only when the README asks for it to be installed or present. |
| "Create a group called G" | `GROUPS_CREATE=(G)` | |
| "Add user U to group G" / "add the new members: a, b, c" | `GROUP_ADD=("a:G" "b:G" "c:G")` | One `"user:group"` entry per user. |
| "Create a new (administrator) account for U" | `NEW_USERS=("U:admin")` or `("U:standard")` | Also add U to the matching authorized list. |
| "U must change password at next login" | `FORCE_PW_CHANGE=(U)` | |
| An administrator whose listed password is weak | `SET_PASSWORDS` | See "Passwords". |
| "FTP users may log in only as anonymous" | `FTP_MODE="anonymous-only"` | Set `FTP_ROOT` to the directory the README names for FTP files. Leave `FTP_ANON_ROOT="/var/ftp"`. |
| Directories whose files are "business-related and should not be removed" | `MEDIA_KEEP_PATHS` | Add them to the default `(/srv /var/www)`. |
| "This machine routes / forwards traffic" | `ALLOW_IP_FORWARD="yes"` | Otherwise `"no"`. |

### Package names

`REQUIRED_PACKAGES` and `INSTALL_PACKAGES` take apt names, not product names:

| README says | Ubuntu / Mint | Debian |
|---|---|---|
| Firefox | `firefox` | `firefox-esr` |
| Chromium | `chromium` (Mint), `chromium-browser` (Ubuntu) | `chromium` |
| Google Chrome | `google-chrome-stable` | `google-chrome-stable` |
| Thunderbird | `thunderbird` | `thunderbird` |
| Wireshark (when authorized) | `'wireshark*' 'libwireshark*'` | same |
| X2Go server | `x2goserver` | `x2goserver` |
| OpenSSH | covered by `REQUIRED_SERVICES=(sshd)`; do not list it | same |

Quote any entry containing `*`. If you are not sure of a package name, use your best guess and tell the user: audit mode reports names it cannot find.

### Passwords

- Never copy the README's passwords into the config, except as described here.
- A README password is weak if it is a plain word or name, equals the user name, or is shorter than 10 characters with no symbols (`alice`, `stormsend`). For each weak one add `'user:NewPassword'` to `SET_PASSWORDS`, with a new password of 14 or more characters mixing cases, digits and a symbol. Use single quotes. Tell the user which accounts you did this for, and that the new passwords are in the file.
- Never add `CURRENT_USER` to `SET_PASSWORDS`. The README says the auto-login account's password need not change, and changing it can lock the team out.
- If no password is weak, `SET_PASSWORDS=()`.

### Leave these alone on a first config

- `DISABLE_SERVICES=()`, `REMOVE_PACKAGES=()`, `REMOVE_FILES=()`: these are decisions made after reading the audit output, not the README. Only fill them if the user gives you audit output, and then only with items the README does not require.
- `FORENSICS_DONE="no"`, unless the user says the forensics questions are already answered.
- `UFW_ALLOW=()`: ports for required services are opened automatically.
- Policy values (`PASS_MINLEN=12`, `PASS_MAX_DAYS=90`, `PASS_MIN_DAYS=2`, `PASS_REMEMBER=5`, `ENABLE_LOCKOUT="ask"`, `SYSCTL_EXTRA="yes"`): keep the defaults unless the README states a number.

## Output

1. Write the file as `config.conf` (or the path the user names). Above each block put a short comment quoting the README sentence it came from, so a teammate can check it.
2. Check it: `bash -n config.conf` must pass, and every name in `AUTHORIZED_ADMINS` and `AUTHORIZED_USERS` must be lower case with no spaces.
3. Count the names against the README. A dropped or misspelled authorized user gets that account deleted.
4. Reply briefly with: the admins and users count, required services and packages, the README tasks you encoded, any weak passwords replaced, and anything the README asks for that the config cannot express (those must be done by hand). Typical hand items: display manager must stay as it is, browser must come from a PPA rather than a snap, time zone must not change.
5. Give the next command: `sudo ./run-all.sh --audit`.

## Things README text often hides

- A new employee in a group task ("Mariya is a new employee, add mariya to pioneers") is already in the authorized list; do not add them to `NEW_USERS` unless the README says to create the account.
- "Do not stop or disable the CCS Client" needs no config; the scripts never touch it.
- A service named in the scenario prose but not under "Critical Services" still counts if the sentence says it must stay working.
- If the README names a firewall other than UFW, say so; the scripts only manage UFW.

## Example

README excerpt:

```
Your boss has decided that the default web browser should be the latest stable version of Chromium.
Barrison is a new employee. Please add the user "bselmy" to the "queensguard" group.
sshd is a critical service and needs to remain enabled.
Authorized Administrators:
dtargaryen (you)
        password: M0th3r0fDr@g0ns
rbaratheon
        password: stormsend
Authorized Users:
tlannister
bselmy
```

Config lines that follow from it:

```bash
AUTHORIZED_ADMINS=(dtargaryen rbaratheon)
AUTHORIZED_USERS=(tlannister bselmy)
CURRENT_USER="dtargaryen"
REQUIRED_SERVICES=(sshd)
REQUIRED_PACKAGES=(chromium 'chromium-*')
INSTALL_PACKAGES=()
GROUP_ADD=("bselmy:queensguard")
SET_PASSWORDS=('rbaratheon:<new 14+ character password>')   # "stormsend" is a plain word
```
