# CyberPatriot Linux hardening scripts

> **Windows:** the Windows 10/11 and Server scripts are in [`windows/`](windows/README.md), with their own README and config format.

Bash scripts for Ubuntu 22.04 / 24.04, Linux Mint 21 and Debian 12 practice and competition prep.

**Debian 12 has had one real run** (CP19 Training Round 2: 75 on the first pass, 100 after three script fixes; see `coverage.md`). It uses the same tools as Ubuntu (apt, PAM with `pam-auth-update`, systemd, `sudo` group), so the modules run unchanged. Known differences the scripts account for: GDM settings live in `/etc/gdm3/daemon.conf`; login events are in the journal rather than `/var/log/auth.log`; `ufw` is not installed by default (module 40 installs it); the browser package is `firefox-esr`; package sources may be in `/etc/apt/sources.list.d/debian.sources`. Things to watch on a Debian image: `sudo` may not be installed or the `(you)` account may not be in the `sudo` group; root often has a real password, which is only reported; and the lockout recipe used is the Ubuntu one.

**Test status: read this first.** The scripts have had one real run: the CP19 Training Round 2 Mint 21 image, where `--apply` plus hand-answered forensics reached 92 of 100 unassisted and 100 of 100 after two fixes learned from that image's answer key, with no penalties (details in `coverage.md`). They have not been run on Ubuntu 22.04 or 24.04 images. Other checks:

- every script passes `bash -n`;
- the text-editing helpers (PAM lines, `sshd_config`, `sysctl.conf`, `login.defs`) and the package-protection checks were tested on sample files;
- every module's `--audit` mode was run on an Ubuntu 24.04 desktop inside an unprivileged sandbox (so without real root, and without being able to read `/etc/shadow`).

`--apply` has been run once, on that Mint image. Run it on a snapshotted practice VM before trusting it on anything else.

## Quick start: get the scripts into a VM

The VM downloads the scripts itself, so it does not matter whether the host PC runs Windows or Linux, and nothing has to be copied in from the host. Use whichever source the team hosts them on.

**From GitHub** (public repository):

```bash
cd ~ && wget -qO- https://github.com/IRIT-able/cp-linux-hardening/archive/refs/heads/main.tar.gz | tar -xz && mv cp-linux-hardening-main cp-linux && cd cp-linux
```

**From a Nextcloud public share link** (share the `cp-linux.tar.gz` file, then add `/download` to the link):

```bash
cd ~ && wget -qO cp-linux.tar.gz "https://YOUR-NEXTCLOUD/s/SHARE-TOKEN/download" && tar -xzf cp-linux.tar.gz && cd cp-linux
```

If `wget` is missing, `curl -L URL -o cp-linux.tar.gz` does the same. To build the tarball for Nextcloud, run this in the scripts folder on any Linux machine or WSL:

```bash
tar --exclude=config.conf --exclude='*.pdf' --exclude=.git --transform 's,^\./,cp-linux/,' -czf cp-linux.tar.gz .
```

Then, inside the VM:

```bash
cp config.conf.example config.conf && nano config.conf     # fill in from the README on the desktop
sudo ./run-all.sh --audit                                  # changes nothing; read the output
sudo ./forensics-helpers.sh help                           # answer the forensics questions first
nano config.conf                                           # set FORENSICS_DONE="yes", add DISABLE_SERVICES / REMOVE_PACKAGES
sudo ./run-all.sh --apply                                  # type APPLY; keep a second terminal open with: sudo -i
```

Two filled-in examples are in `configs/` (the CP19 Training Round 2 Mint 21 and Debian 12 images). For those images: `cp configs/debian12-cp19-tr2.conf config.conf`.

Before a real competition round, check the current CyberPatriot rules with your coach about which scripts and outside help a team may use. These were built for practice.

## Files

| File | Purpose |
|---|---|
| `config.conf.example` | Template. Copy to `config.conf` and fill in from the round's README. |
| `configs/` | Filled-in examples for two practice images (no passwords). |
| `.claude/skills/cp-config/SKILL.md` | Instructions for an AI model to write `config.conf` from a pasted README. In Claude Code, open this folder and type `/cp-config`; with any other model, paste the file followed by the README. Check its output against the README before applying. |
| `collect.sh` | Practice only: uploads the run log to a receiver on the host PC for debugging. Not needed normally. |
| `run-all.sh` | Menu, or `--audit` / `--apply` for all or selected modules. |
| `10-users.sh` … `120-updates.sh` | One module per category. Each takes `--audit` (default) or `--apply`. |
| `forensics-helpers.sh` | Read-only search and decode tools. Answers nothing. |
| `lib/common.sh` | Shared code: logging, backups, config, protection rules. |
| `catalog.md` | Every scored item and penalty from the answer keys. |
| `coverage.md` | Per key: what is fixed automatically, reported, or manual. |

## Run order

1. **Practice only:** take a VM snapshot.
2. Read the README on the image's desktop. Read every Forensics Question. Change nothing yet.
3. `cp config.conf.example config.conf` and fill it in (next section).
4. `sudo ./run-all.sh --audit` — changes nothing. Read the output. `WOULD CHANGE` is what apply will do; `REPORT` needs a person.
5. Answer the forensics questions (`sudo ./forensics-helpers.sh help`). Save each question file.
6. Set `FORENSICS_DONE="yes"` in `config.conf`. Add anything the audit suggested to `DISABLE_SERVICES` / `REMOVE_PACKAGES`.
7. Open a second terminal, run `sudo -i`, and leave it open.
8. `sudo ./run-all.sh --apply` (type `APPLY`). Or go one module at a time — `sudo ./run-all.sh --apply 10` — and check the scoring report after each. This is the better way in practice, because it shows which module earned or lost points.
9. In the second terminal test `sudo -k; sudo true` and `su - <your user>`. Only then close the root shell.
10. Work through the `REPORT` lines: `grep REPORT /root/cp-log-*.txt`. Then do the "always by hand" list below.
11. `sudo ./run-all.sh --audit` again. It should show no `WOULD CHANGE` except things you declined.

Logs go to `/root/cp-log-<timestamp>.txt`. Backups of every edited file go to `/root/cp-backup/<timestamp>/` with the original path underneath, so `/etc/pam.d/common-auth` is restored with `cp -a /root/cp-backup/<timestamp>/etc/pam.d/common-auth /etc/pam.d/`.

## Filling in config.conf from a README

| README text | Config line | Notes |
|---|---|---|
| `Authorized Administrators:` list | `AUTHORIZED_ADMINS=(…)` | Names only. Drop `(you)` and the `password:` lines. |
| `Authorized Users:` list | `AUTHORIZED_USERS=(…)` | |
| The account marked `(you)` | `CURRENT_USER="…"` | Never deleted, never loses sudo, password never changed. |
| `Critical Services:` list, and sentences like "sshd is a critical service" | `REQUIRED_SERVICES=(…)` | `sshd` and `ssh` are the same. |
| "must have access to the latest version of Firefox, Thunderbird and Perl" | `REQUIRED_PACKAGES=(firefox thunderbird perl)` | apt package names. Audit tells you if a name is not installed (Chrome is `google-chrome-stable`). |
| "Management now requires … X2GO server installed" | `INSTALL_PACKAGES=(x2goserver)` | |
| "add the user mariya to the pioneers group" | `GROUP_ADD=("mariya:pioneers")` | One entry per user. |
| "create a group called spider" | `GROUPS_CREATE=(spider)` | |
| "create a new administrator account for edarby" | `NEW_USERS=("edarby:admin")` | Also add the name to `AUTHORIZED_ADMINS`, and a password to `SET_PASSWORDS`. |
| An admin whose listed password is weak (`alice` / `alice`) | `SET_PASSWORDS=('alice:…')` | Single quotes. At least 12 characters. |
| "must change password at next login" | `FORCE_PW_CHANGE=(edarby)` | |
| A service the README does not need (after reading the audit) | `DISABLE_SERVICES=(nginx)` | Otherwise apply asks about each one. |
| Software the README does not allow (after reading the audit) | `REMOVE_PACKAGES=(aisleriot)` | Otherwise apply asks about each one. |

The scripts refuse to add, remove or change any user when both user lists are empty, when your own account is not in `AUTHORIZED_ADMINS`, or when the config would delete as many accounts as it keeps.

## What each module does

`[key]` = a fix taken from the answer keys. `[std]` = standard Ubuntu configuration that no key has scored; untested for points.

| Module | Changes in `--apply` | Reports only |
|---|---|---|
| `10-users.sh` | Creates requested groups and users, adds users to groups `[key]`. Deletes unauthorized accounts with UID ≥ 1000 `[key]`. Offers to delete system-UID accounts that have a password `[key]`. Removes non-admins from `sudo`, adds authorized admins `[key]`. | UID 0 accounts, duplicate IDs, odd shells, privileged groups, sudoers rules (`NOPASSWD` etc.). |
| `20-passwords-pam.sh` | `pam_faillock` lockout via `pam-auth-update`, after you type `YES` `[key]`. Removes `nullok` `[key]`. `minlen` and `remember` `[key]`. `PASS_MAX_DAYS`/`PASS_MIN_DAYS` in `login.defs` `[key]`. Sets `SET_PASSWORDS`. Locks root if its password is blank `[key]`. `chage -M 90` per user `[key]`. | Empty passwords, root with a usable password, passwords equal to the user name or a few common words. |
| `30-ssh.sh` | `PermitRootLogin no` `[key]`, `PermitEmptyPasswords no` `[std]`. Validated with `sshd -t` before the file is replaced; sshd is reloaded, never stopped. | Other settings in effect, `Match` blocks. |
| `40-firewall.sh` | Allows ports for required services, then `ufw enable` `[key]`. Default incoming policy to deny `[std]`. | The rule list. |
| `50-services.sh` | Starts and enables required services. Installs `INSTALL_PACKAGES` `[key]`. Disables services in `DISABLE_SERVICES`; asks about other known network services `[key]`. | Everything listening on the network. |
| `60-software.sh` | Purges packages in `REMOVE_PACKAGES`; asks about known hacking tools, games, file sharing and insecure remote-access packages `[key]`. Simulates each purge first and refuses if a required package would go too. Never runs `apt autoremove`. | What `autoremove` would take, snaps, files no package owns in `/usr/games` and `/usr/local`, archives and installers. |
| `70-media.sh` | Deletes audio/video under `/home`, one directory at a time, after you say yes `[key]`. | Media outside `/home` or under `MEDIA_KEEP_PATHS`, images, media content hiding under another extension, odd hidden files in home directories. |
| `80-permissions.sh` | `/etc/shadow` to 640 `[key]`; `passwd`, `group`, `gshadow`, `sudoers` to Ubuntu defaults `[std]`; removes world-write from files under `/etc`, `/usr`, `/boot`. | World-writable files elsewhere, SUID/SGID outside the usual set, ownerless files. |
| `90-sysctl.sh` | SYN cookies on, IP forwarding off, ASLR on `[key]`. Redirect, source-route and reverse-path settings `[std]` (turn off with `SYSCTL_EXTRA="no"`). | Conflicting values in `/etc/ufw/sysctl.conf`. |
| `100-persistence.sh` | Removes cron lines that start a netcat listener `[key]`; offers to kill the netcat process `[key]`. | Listening interpreters and shells with who launches them, all user crontabs, suspicious cron lines, systemd units no package owns, `rc.local`, autostart entries, shell start-up files, `ld.so.preload`, `authorized_keys`, executables in temp directories. |
| `110-apps-desktop.sh` | Switches off the LightDM guest session `[std]`. | GDM/LightDM auto-login, Firefox policy files, settings for vsftpd, Apache, nginx, Samba, MySQL, PHP, PostgreSQL. No key scored any of this. |
| `120-updates.sh` | `APT::Periodic` daily check and unattended upgrades `[std]`. After you say yes, `apt-get full-upgrade` keeping existing config files `[key]`. On Mint, tries `mintupdate-automation upgrade enable` (untested). | Missing security/updates sources, third-party sources, snap updates, reboot needed. |

### Safety rules built in

- **Audit is the default.** Audit takes no backups and edits nothing.
- **Forensics gate.** Until `FORENSICS_DONE="yes"`, apply will not delete users, media or packages, kill listeners, or edit cron.
- **Protected.** Anything in `REQUIRED_SERVICES`, `REQUIRED_PACKAGES` or `INSTALL_PACKAGES`; `sudo`; your own account; and anything whose path or name contains `CyberPatriot`, `CCS`, or `scoring report`.
- **Validated before use.** `sshd_config` with `sshd -t`; PAM files with a structural check (there is no official PAM validator) and restored from backup if `pam-auth-update` produces something unusable; sudoers is never edited, only checked with `visudo -c`.
- **Idempotent.** Each change is preceded by a check of the current state, so a second run reports `OK`.

## What must always be done by hand

1. **Forensics questions.** Before anything destructive. The helper finds and decodes; a person answers.
2. **Reading the README** for anything unusual: required software versions, a browser that must come from a PPA rather than a snap, a display manager that must not change, machines that route traffic.
3. **GUI update settings**, until a practice run confirms the file-level equivalents score: Ubuntu *Software & Updates → Updates → check Daily*, and the "Important security updates" boxes; Mint *Update Manager → Preferences → Automation* (both switches), and repairing sources if it says the APT configuration is corrupt.
4. **Backdoors that are not netcat-in-cron.** The script shows the listener, its command line and what references its file. You kill it and delete the file and its launcher (the Mint key: `rm -f /usr/share/zod/kneelB4zod.py; pkill -f kneelB4zod.py`).
5. **Hacking-tool archives and unpackaged files** (`/usr/games/pyrdp-master.zip` in the Mint keys). Reported; you delete.
6. **Every `REPORT` line**: UID 0 accounts, sudoers rules, unusual SUID files, empty passwords with no entry in `SET_PASSWORDS`, extra firewall rules, authorized SSH keys.
7. **Application hardening** for any service the README requires (vsftpd, Apache, Samba, MySQL, PHP). The script prints current values next to the usual hardening; you edit and restart.
8. **Firefox settings**, per user, in the browser.
9. **`apt autoremove`**. Run it yourself only after reading what the script says it would remove.
10. **Checking the scoring report** after each module, and noting any penalty immediately.

## Most likely to break on a different image

| Risk | Why | What happens / what to check |
|---|---|---|
| Account lockout (`pam-auth-update`) | Images often have hand-edited `/etc/pam.d/common-*`; `pam-auth-update` may then decline to rewrite them. The Ubuntu and Mint recipes differ. | The script checks that `pam_faillock.so` appeared and the file is still well-formed, otherwise restores the backup and reports. Test on a snapshot. Unlock with `faillock --user NAME --reset`. |
| `minlen` / `remember` on `pam_unix.so` | Different images have different module lines (`pam_pwquality` present or not). | Both lines are set when present. Whether the scorer reads one or the other is unknown. |
| Scoring-engine protection | The protected names are a pattern guess (`CyberPatriot`, `CCS`), not read from an image. | On the practice VM run `systemctl list-units \| grep -i ccs` and `ls /opt` and confirm they match. |
| SSH on Ubuntu 24.04 | `ssh.service` is started on demand by `ssh.socket`, so it can look inactive; settings may also live in `/etc/ssh/sshd_config.d/`. | Handled in code but never run on 24.04 with sshd installed. |
| Package names | `REQUIRED_PACKAGES` must be apt names. On stock 22.04 the `firefox` apt package is a stub that installs the snap. | Audit reports names it cannot find. |
| Service unit names | `REQUIRED_SERVICES` entries are matched to units through a small alias table. | Audit reports a required service with no unit. |
| Hidden users | Only system-UID accounts **with a password** are offered for deletion. The Mint keys do not say whether their hidden user had one. | If not, it is reported instead and you delete it by hand. |
| `chage -M 90` | On a password older than 90 days this would force a change at next login. | Such accounts are skipped and reported. |
| SUID list | The "usual set" was written from memory, not taken from a clean image. | Expect a few false alarms; report only. |
| Password idempotence | The "already set?" check uses Python's `crypt` module, which is gone in Python 3.13. | Without it the password is simply set again each run. |
| `deluser --remove-home` | Needs the full `perl` package; fails if perl was removed. | Reported as an error; use `userdel -r`. |
| `ufw` default deny | Blocks any service whose port is not allowed. | Ports for required services are allowed first; add others to `UFW_ALLOW`. |
| Broken apt sources | Installs and upgrades fail. | Reported; repair by hand, then rerun module 120. |
| `sysctl` extras | `ufw` applies its own `/etc/ufw/sysctl.conf` when it starts. | Conflicts are reported. |
| Media deletion | Not backed up (a copy would still be a prohibited file). | Each directory is listed and confirmed; path, size and hash go in the log. |
