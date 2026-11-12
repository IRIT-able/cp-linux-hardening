# CyberPatriot Linux vulnerability catalog

Built from every Linux answer key and ReadMe in `~/Downloads/CyberPatriot`. Step 1 only: no scripts exist yet.

## Keys read

| Code | File | OS | Scored items | Points listed |
|---|---|---|---|---|
| U-P17 | `CP17/Practice Round/Ubuntu 22 Practice Answer Key.pdf` | Ubuntu 22 | 16 | 100 |
| U-T1 | `CP17/Training Round 1/Ubuntu 22 Training Round 1 Answer Key.pdf` | Ubuntu 22 | 17 | 101 (as printed) |
| U-T2 | `CP17/Training Round 2/Ubuntu 22 Training Round 2 Answer Key.pdf.pdf` **and** `Practice Round 2 2025/CP18_Ubuntu22_Training2_Answer_Key.pdf` | Ubuntu 22 | 24 | 100 |
| M-P18 | `Practice Round 1 2025/CP18_Mint21_Practice_Answer_Key.pdf` | Mint 21 | 19 | 100 |
| M-T18 | `Practice Round 2 2025/CP18_Mint21_Training2_Answer_Key.pdf` | Mint 21 | 26 | 95 printed + items 4–5 unprinted |
| M-P19 | `CP19_Mint21_Practice_Answer_Key.pdf` | Mint 21 | 18 | 100 |
| M-T19 | `Training Round/CP19_Mint21_Training_Answer_Key.pdf` | Mint 21 | 21 | 99 (as printed) |

**The two "Training 2" Ubuntu keys are the same document.** The PDFs differ in bytes but the extracted text is identical, so there are 7 distinct keys, not 8. "Keys" counts below are out of 7.

ReadMes read: Ubuntu 22 Training Round 1 and Training Round 2. They describe the same scenario (same users, same passwords, same requirements). There is no ReadMe for U-P17 or for any Mint image, so README-dependence for those is taken from what each key says the README contained.

## How a README states the things the config must capture

From the two ReadMes (same layout in both):

| What | Where and how it is written | Example |
|---|---|---|
| Authorized administrators | Heading `Authorized Administrators:`, one name per line, each followed by an indented `password:` line. The team's own account is marked `(you)`. | `perry (you)` / `password: M4mm@lOfAct!0n` |
| Authorized standard users | Heading `Authorized Users:`, one name per line, no passwords. | `jaimie`, `adalbern`, … |
| Weak passwords to change | Not called out. An admin's listed password is simply weak. | `alice` / `password: alice` |
| Critical services | Sentence in the scenario plus a `Critical Services:` list. | `sshd` |
| Required software | Prose in the OS paragraph, not a list. | Firefox (Mozilla PPA, **not** snap), Thunderbird, Perl |
| Software to install | Prose, one sentence. | "Management now requires this computer to have X2GO server installed." |
| Group tasks | Prose, one sentence. | "Please add the user "mariya" to the "pioneers" group." |
| Policy | Prose. | No media files, no "hacking tools", UFW is the only firewall, no root login, display manager stays GDM3 |
| Guidelines | Bullets at the end. | Do not change the auto-login user's password; do not stop the CCS Client; do not remove authorized users or their home directories; do not change time zone |

## Catalog

Points are per key in the order listed. "README?" = the decision depends on the round's README and must come from `config.conf`.

### Forensics questions (human only)

| Category | Vulnerability | How it was detected | Fix | Points | Keys | README? |
|---|---|---|---|---|---|---|
| Forensics | Absolute path of the directory holding prohibited MP3s | `locate '*.mp3'` (M-P19 runs `sudo updatedb` first) | Type the directory path into the question file | 8, 8, 7, 8, 8 | U-P17, U-T1, U-T2, M-P18, M-P19 (5) | no |
| Forensics | Decode a base64 message on the Desktop | Desktop file; key uses an online decoder (`base64 -d` does the same) | Type decoded answer | 8, 8, 7 | U-P17, U-T1, U-T2 (3) | no |
| Forensics | Open a deleted file in the Trash (second half of the base64 question) | Decoded message points to `l.jpg` in Trash | View the image, type what it shows | part of the above | U-T1, U-T2 (2) | no |
| Forensics | Directory containing the python backdoor | `ss -tlnp`, `ps -ef \| grep python` → `/usr/share/zod/kneelB4zod.py` on port 1337 | Type the directory | 6, 8 | M-T18, M-T19 (2) | no |
| Forensics | MD5 of a message hidden in `stanlee.jpg` | `locate override.txt`, `base64 -d` for the passphrase, `steghide extract -p … -sf stanlee.jpg`, `md5sum message.txt` | Type the hash | 6, 8 | M-T18, M-T19 (2) | no |
| Forensics | Two plaintext passwords in `ftp_capture.pcap` | `tshark -q -z follow,tcp,ascii,N -r ftp_capture.pcap \| grep PASS` | Type both passwords | 6 | M-T18 (1) | no |
| Forensics | Codename of the distribution | `lsb_release -a` | Type the codename | 8 | M-P18 (1) | no |

Order hazards seen in these keys: the MP3 path is needed before MP3s are deleted, the backdoor path before the backdoor is killed, the Trash file before the Trash is emptied, and the steghide files live under `/srv/ftp` where deleting is a penalty.

### User accounts & groups

| Category | Vulnerability | How it was detected | Fix | Points | Keys | README? |
|---|---|---|---|---|---|---|
| Users | Unauthorized user exists | Compare accounts with README lists. Mint training images hide one with UID < 1000 | GUI, or `deluser --remove-home <user>` | 6, 6, 2, 4×3, ?, 5×2, 4 | all 7 | **yes** |
| Users | Non-admin user has administrator rights | Compare `sudo` group with README admin list | GUI toggle, or `gpasswd -d <user> sudo` | 6×2, 6, 2, 4×2, 3, 5, 4 | all 7 | **yes** |
| Users | Authorized admin has a weak password | README prints the password (`alice`/`alice`; a 10-character one in M-P19) | Set a strong password (M-P19 says at least 12 characters) | 6, 6, 2, 4, 5 | U-P17, U-T1, U-T2, M-P18, M-P19 (5) | **yes** |
| Users | User(s) missing from a group | README request | `gpasswd -a <user> <group>`; Mint keys use `gpasswd -M a,b,c <group>` (replaces the whole member list) | 8, 7, 5, 4, 5 | U-P17, U-T1, U-T2, M-T18, M-T19 (5) | **yes** |
| Users | Requested group does not exist | README request | `addgroup spider` | 3, 4 | M-T18, M-T19 (2) | **yes** |
| Users | Requested new administrator account missing | README request (inferred, no ReadMe on hand) | `adduser edarby`; `usermod -aG sudo edarby` | 6 | M-P19 (1) | **yes** |
| Users | New user must change password at next login | README request (inferred) | `passwd -e edarby` | 6 | M-P19 (1) | **yes** |

### Passwords & PAM

| Category | Vulnerability | How it was detected | Fix | Points | Keys | README? |
|---|---|---|---|---|---|---|
| PAM | Null passwords authenticate | `nullok` on the `pam_unix.so` line in `/etc/pam.d/common-auth` | Remove `nullok` | 6, 3, 4, 4 | U-T1, U-T2, M-T18, M-T19 (4) | no |
| PAM | No minimum password length | `/etc/pam.d/common-password` | Add `minlen=`. U-T1: `minlen=8` on `pam_unix.so`. U-T2: `minlen=10` on `pam_pwquality.so`. M-T18: `minlen=10` on `pam_unix.so`. M-T19: 12 on `pam_unix.so` | 4, 4, 3, 4 | U-T1, U-T2, M-T18, M-T19 (4) | no |
| Passwords | Root password is blank | `getent shadow root` | `passwd -l root` | 4, 5 | M-T18, M-T19 (2) | no |
| Passwords | A named user has no maximum password age | `getent shadow <user>` | `chage -M 90 <user>` | 4, 5 | M-T18 (noir), M-T19 (kaia) (2) | no (applies to any user) |
| Passwords | No default minimum password age | `PASS_MIN_DAYS 0` in `/etc/login.defs` | `PASS_MIN_DAYS 2` (key says 1–3 is accepted) | 3 | U-T2 (1) | no |
| PAM | Password history not kept | `/etc/pam.d/common-password` | Append `remember=3` to the `pam_unix.so` line | 3 | M-T18 (1) | no |

### Login / lockout policy

| Category | Vulnerability | How it was detected | Fix | Points | Keys | README? |
|---|---|---|---|---|---|---|
| Lockout | No account lockout policy | No `pam_faillock` in the PAM stack | Create profiles in `/usr/share/pam-configs/` and enable with `pam-auth-update`. U-T2 uses two profiles (`faillock`: `[default=die] pam_faillock.so authfail` + `sufficient pam_faillock.so authsucc`; `faillock_notify`: `requisite pam_faillock.so preauth`). Mint keys use three (`faillock`, `faillock_reset` with `required … authsucc` as Auth-Type Additional, `faillock_notify`) | 3, 4, 4 | U-T2, M-T18, M-T19 (3) | no |

### Sudoers

No scored item in any key touches `/etc/sudoers` or `/etc/sudoers.d`. Admin rights were always `sudo` group membership. Hunting checks only.

### SSH

| Category | Vulnerability | How it was detected | Fix | Points | Keys | README? |
|---|---|---|---|---|---|---|
| SSH | Root login over SSH allowed | `PermitRootLogin yes` in `/etc/ssh/sshd_config` | `PermitRootLogin no` | 6, 6, 5, 6, 6 | U-P17, U-T1, U-T2, M-P18, M-P19 (5) | no (but sshd itself is README-critical) |

### Firewall

| Category | Vulnerability | How it was detected | Fix | Points | Keys | README? |
|---|---|---|---|---|---|---|
| Firewall | UFW disabled | `ufw status` | `ufw enable` | 6, 6, 5, 6, 3, 6, 5 | all 7 | no |

### Services & daemons

| Category | Vulnerability | How it was detected | Fix | Points | Keys | README? |
|---|---|---|---|---|---|---|
| Services | nginx running and not required | `systemctl list-units --type=service --state=active` | `systemctl disable --now nginx` | 6, 6, 4, 4, 5 | U-P17, U-T1, U-T2, M-T18, M-T19 (5) | **yes** |
| Services | FTP (vsftpd) running and not required | same | `systemctl disable --now vsftpd`; M-P19 purges it | 4, 6 | U-T2, M-P19 (2) | **yes** — vsftpd is a *critical service* in M-T18 and M-T19 |
| Services | Squid proxy running and not required | same | `systemctl disable --now squid` (takes up to a minute) | 4, 5 | M-T18, M-T19 (2) | **yes** |
| Services | Required X2Go server not installed | README sentence | `apt update`; `apt install x2goserver` | 5, 5 | U-T1, U-T2 (2) | **yes** |
| Services | Required Apache2 not installed/running | README request | `apt update`; `apt install -y apache2` | 6 | M-P18 (1) | **yes** |

### Unauthorized software & hacking tools

| Category | Vulnerability | How it was detected | Fix | Points | Keys | README? |
|---|---|---|---|---|---|---|
| Software | Wireshark installed | Applications menu / desktop link | `apt remove wireshark` + `apt autoremove`; Mint: `apt purge -y wireshark*` | 6, 6, 6 | U-P17, M-P18, M-P19 (3) | **yes** |
| Software | ophcrack installed | Applications menu / desktop link | `apt remove ophcrack`; Mint: `apt purge -y ophcrack*` | 6, 6 | U-P17, M-P18 (2) | **yes** |
| Software | AisleRiot (game) installed | Applications menu | `apt purge aisleriot`; `apt autoremove -y` | 5, 4 | U-T1, U-T2 (2) | **yes** |
| Software | doona and xprobe installed | Not stated (key text is copied from another item) | `apt purge -y doona xprobe` | 3×2, 3×2 | M-T18, M-T19 (2) | **yes** |
| Software | Hacking-tool archive `pyrdp-master.zip` | `locate *.zip` → `/usr/games/pyrdp-master.zip` | `rm /usr/games/pyrdp-master.zip` | 4, 4 | M-T18, M-T19 (2) | **yes** |
| Software | Zangband (game) installed | Desktop link | `apt purge -y zangband*` | 6 | M-P19 (1) | **yes** |

### Prohibited media files

| Category | Vulnerability | How it was detected | Fix | Points | Keys | README? |
|---|---|---|---|---|---|---|
| Media | MP3 files in a user's Music directory | `locate '*.mp3'` | `rm /home/<user>/Music/*.mp3` | 6, 6, 4, 5, 5 | U-P17, U-T1, U-T2, M-P18, M-P19 (5) | **yes** (policy is in the README; authorized files elsewhere are a penalty) |
| Media | OGG files nested two levels under Music | `locate '*.ogg'` | `rm /home/<user>/Music/*/*/*.ogg` | 4, 4 | M-T18, M-T19 (2) | **yes** |

### File permissions & ownership

| Category | Vulnerability | How it was detected | Fix | Points | Keys | README? |
|---|---|---|---|---|---|---|
| Permissions | `/etc/shadow` world readable | `ls -alF /etc/shadow` | `chmod 640 /etc/shadow` | 5 | U-T2 (1) | no |

### Kernel / sysctl

| Category | Vulnerability | How it was detected | Fix | Points | Keys | README? |
|---|---|---|---|---|---|---|
| sysctl | TCP SYN cookies off | `net.ipv4.tcp_syncookies=0` in `/etc/sysctl.conf` | Set to `1`; `sysctl --system` | 4, 4, 5 | U-T2, M-T18, M-T19 (3) | no |
| sysctl | IPv4 forwarding on | `net.ipv4.ip_forward=1` in `/etc/sysctl.conf` | Set to `0`; `sysctl --system` | 4 | U-T2 (1) | no |
| sysctl | ASLR off | `kernel.randomize_va_space=0` in `/etc/sysctl.conf` | Set to `2`; `sysctl --system` | 4 | M-T18 (1) | no |

### Updates & auto-updates

| Category | Vulnerability | How it was detected | Fix | Points | Keys | README? |
|---|---|---|---|---|---|---|
| Updates | Ubuntu does not check for updates daily | Software & Updates → Updates tab | GUI: "Automatically check for updates" → Daily. File equivalent not given in the key | 6, 6, 5 | U-P17, U-T1, U-T2 (3) | no |
| Updates | Thunderbird out of date | Software Updater | Install updates | 5, 5, 4 | U-P17, U-T1, U-T2 (3) | no |
| Updates | Mint Update Manager does not install updates automatically | Update Manager → Edit → Preferences → Automation | Tick "Apply updates automatically" | 5, 3 | M-P18, M-T18 (2) | no |
| Updates | systemd, OpenSSH, Chromium out of date | — | `apt update`; `apt full-upgrade -y` | 5×3, 5×3 | M-P18, M-P19 (2) | no |
| Updates | Firefox out of date | Software Updater | Install updates | 5, 4 | U-T1, U-T2 (2) | no |
| Updates | vsftpd out of date, and APT sources are broken | Update Manager reports "Your APT configuration is corrupt" | Restore default Mint mirrors in Software Sources, then `apt update`; `apt full-upgrade -y` | 3, 5 | M-T18, M-T19 (2) | no |
| Updates | Google Chrome out of date | Software Updater | Install updates | 5 | U-P17 (1) | no |
| Updates | Gimp out of date | — | `apt full-upgrade -y` | 5 | M-P18 (1) | no |
| Updates | "The system refreshes the list of updates automatically" | Update Manager → Automation | Key's fix text says tick "Apply updates automatically" | 5 | M-P19 (1) | no |
| Updates | "Install updates from important security updates" | Update Manager | Refresh, Install Updates (or `apt full-upgrade -y`) | 5 | M-P19 (1) | no |

### Cron & persistence / backdoors

| Category | Vulnerability | How it was detected | Fix | Points | Keys | README? |
|---|---|---|---|---|---|---|
| Backdoor | Python backdoor `kneelB4zod.py` listening on 1337 | `ss -tlnp`, `ps -ef \| grep python` | `rm -f /usr/share/zod/kneelB4zod.py`; `pkill -f kneelB4zod.py`. The key does not say what starts it | 6, 5 | M-T18, M-T19 (2) | no |
| Backdoor | netcat listener on 1337 started from `/etc/crontab` | `ss -tlnp` shows `nc.traditional` | Delete the `/usr/bin/nc.traditional` line from `/etc/crontab`; `pkill -f nc.traditional`; `rm /usr/bin/nc.traditional` | 5 | U-T2 (1) | no |

### Categories with no scored item in any key

Sudoers, application-specific configs (Apache, nginx, vsftpd, Samba, MySQL/MariaDB, PHP), Firefox settings, display manager (guest login, autologin). The only application rule in these keys is a penalty: do not delete files from the public FTP directories. Anything the scripts do in these categories is hunting based on standard Ubuntu documentation, not on these keys, and needs testing.

### Penalties

| Category | Penalty | Why | How to avoid | Points | Keys | README? |
|---|---|---|---|---|---|---|
| Penalty | OpenSSH stopped or removed (U-T2 adds "disabled") | Critical service | Never stop, disable or remove a service in the config | −5 each | U-P17, U-T1, U-T2, M-P18, M-P19 (5) | **yes** |
| Penalty | Thunderbird removed | Required software | Never remove a config-listed package; watch `apt autoremove` | −5 each | U-P17, U-T1, U-T2 (3) | **yes** |
| Penalty | Perl removed | Required software | Same; `apt autoremove` and wildcard purges are the likely cause | −5 each | U-P17, U-T1, U-T2 (3) | **yes** |
| Penalty | Firefox removed | Required software (Mozilla PPA, not snap) | Same | −5 each | U-T1, U-T2 (2) | **yes** |
| Penalty | VSFTP stopped or removed | Critical service | Same | −5 each | M-T18, M-T19 (2) | **yes** |
| Penalty | Important files removed from public FTP directories | Work files | Never auto-delete under `/srv/ftp` or any required service's data directory | −5 each | M-T18, M-T19 (2) | **yes** |
| Penalty | Google Chrome removed | Required software | Same | −5 | U-P17 (1) | **yes** |
| Penalty | Chromium removed | Default browser | Same | −5 | M-P19 (1) | **yes** |
| Warning | VirtualBox is unsupported | Platform notice | Use VMware | −0 | M-P18, M-P19 (2) | no |

## Added after the first catalog: two more keys

Read later, after running the scripts on the real images. "Keys" counts in the tables above do not include these.

**CP19 Training Round 2, Linux Mint 21** (27 items, 100 pts). Same image family as M-T18, with these differences:

| Category | Vulnerability | How it was detected | Fix | Points | README? |
|---|---|---|---|---|---|
| Services | POP3 (dovecot) running and not required | `systemctl list-units` | `systemctl disable --now dovecot.service` | 4 | **yes** |
| sysctl | TIME-WAIT assassination protection off | not stated | `sysctl -w net.ipv4.tcp_rfc1337=1`, persist in sysctl config | 4 | no |
| App config | FTP must be anonymous-only | README sentence | In `/etc/vsftpd.conf`: `anonymous_enable=YES`, `local_enable=NO`, `anon_root=/var/ftp`; restart vsftpd. On the image only `/var/ftp` scored, and that directory did not exist | 4 | **yes** |
| Users | Requested group / members | README | group `marketing`, four users | 3 + 3 | **yes** |
| Backdoor | zod python backdoor | Forensics Q1 says it restarts from cron | Launcher was a line in `/etc/crontab` (the key does not say so) | 4 | no |

**CP19 Training Round 2, Debian 12** (26 items, 100 pts). The first Debian key:

| Category | Vulnerability | How it was detected | Fix in the key | Points | README? |
|---|---|---|---|---|---|
| Forensics | Message from a user, base64 then ROT13 | Desktop question | decode twice | 6 | no |
| Forensics | Directory of MP3 files | `locate *.mp3` | `/home/<user>/Music` | 6 | no |
| Users | Two unauthorized users; one non-admin in `sudo`; weak admin password (9 characters); add user to group | README | `deluser`, `gpasswd -d`, `passwd`, `adduser user group` | 2+2, 2, 2, 4 | **yes** |
| Passwords | No default minimum age | `/etc/login.defs` | `PASS_MIN_DAYS 7` | 3 | no |
| PAM | No minimum length | `/etc/pam.d/common-password` | install `libpam-pwquality`, add `minlen=12` to the `pam_pwquality.so` line (`minlen` on `pam_unix.so` also scored) | 3 | no |
| Lockout | No lockout policy | PAM | the three-profile `pam_faillock` recipe (the two-profile Ubuntu recipe also scored) | 3 | no |
| PAM | Null passwords authenticate | `common-auth` | remove `nullok` | 3 | no |
| sysctl | SYN cookies off; IP forwarding on | `/etc/sysctl.conf` | set `1` / `0` | 4 + 4 | no |
| Firewall | UFW not installed | - | `apt install ufw`; `ufw enable` | 5 | no |
| Permissions | `/etc/shadow` is 664 | `ls -l` | `chmod 640` | 5 | no |
| Services | Apache2 and FTP (vsftpd) running | services list | disable | 4 + 4 | **yes** |
| Updates | No daily update check | - | `APT::Periodic::Update-Package-Lists "1";` in `/etc/apt/apt.conf.d/20auto-upgrades` | 4 | no |
| Updates | Sources point at a frozen snapshot; security updates, Chromium and OpenSSH out of date | `/etc/apt/sources.list` | replace with `deb.debian.org` bookworm, bookworm-updates and `security.debian.org` bookworm-security; `apt upgrade` | 4 x 3 | no |
| Media | MP3 files in the admin's own Music directory | `locate` | `rm` | 4 | **yes** |
| Software | AisleRiot and Wireshark | desktop links | `apt purge -y wireshark* aisleriot*` | 4 + 4 | **yes** |
| Backdoor | netcat listener from **root's crontab** | `sudo crontab -l` | kill it, `rm /usr/bin/nc.traditional` | 5 | no |
| SSH | Root login allowed | `sshd_config` | `PermitRootLogin no` | 5 | no |
| Penalty | Chromium removed | required browser | - | not printed | **yes** |

Note the contrast with the Mint image, where Wireshark was authorized by the README and vsftpd was a critical service: the same two things were scored removals here.

## Unreadable or ambiguous places in the keys

1. **M-T18 item 4/5.** The heading reads "Removed unauthorized users penguru" with no point value and item 5 is missing. The body mentions a hidden user "liv" (UID < 1000) but only shows the command for penguru. Probably two users; the printed points leave 5 unaccounted for.
2. **Minimum length: two different lines.** U-T2 puts `minlen` on `pam_pwquality.so`; U-T1 and both Mint training keys put it on `pam_unix.so`. Which line the scorer reads on a given image is not stated.
3. **Lockout: two different recipes** (two profiles on Ubuntu, three on Mint), and the Mint text is partly run together in the PDF. This is the item most likely to lock an account out if wrong.
4. **Null passwords on Mint.** The key quotes the line as `pam_unix.so try_first_pass` and then says remove `nullok`; the quoted line has no `nullok` in it.
5. **M-P19 item 10.** Title says the system *refreshes the list* automatically; the fix says tick *Apply updates automatically*. Those are two different switches in Update Manager.
6. **Daily update check (Ubuntu) and Mint automation** are given as GUI steps only. The file or command behind them is not in any key.
7. **Typos that do not change the fix:** M-P19 item 4 heading says dscott, body says jquelling; M-T18 item 9 calls the group "multiverse" once; M-T19 item 5 body says noir, command says kaia; "xproble" is the package `xprobe`; doona/xprobe and zod "how to find" text is copied from unrelated items.
8. **Totals:** U-T1 adds to 101 and M-T19 to 99 as printed.
9. **Training Round 2 ReadMe PDF** lost every "ti" and "tt" ligature in text extraction ("mothy" for timothy, "mar n" for martin). It matches the Training Round 1 ReadMe, which extracts cleanly, so nothing was lost.
