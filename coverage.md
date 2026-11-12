# Coverage by answer key

## Measured result: CP19 Training Round 2, Mint 21 (the only real run so far)

Run on the actual image: **100 of 100 points, 27 of 27 items, 0 penalties.**

How the points were earned:

| Scored item(s) | Pts | How |
|---|---|---|
| Forensics 1-3 | 18 | By hand (answers typed into the files) |
| Removed user jonas; wells not admin; group marketing; users added to it | 12 | Module 10 |
| Max password age (briar); root password not blank; minimum length; history; lockout; null passwords | 18 | Module 20 |
| UFW enabled | 4 | Module 40 |
| nginx, Squid, POP3 (dovecot) disabled | 12 | Module 50 |
| doona, xprobe removed | 6 | Module 60 |
| `pyrdp-master.zip` removed | 3 | By hand in this run after module 60 reported it; now `REMOVE_FILES` does it |
| OGG files removed | 3 | Module 70 |
| ASLR, SYN cookies | 8 | Module 90 |
| TIME-WAIT assassination protection (`tcp_rfc1337`) | 4 | Added to module 90 after reading this image's key, then applied |
| zod backdoor removed | 4 | Module 100 (script, process and its `/etc/crontab` line) |
| vsftpd updated | 4 | Module 120, after it re-enabled Mint's package sources |
| FTP users must log on as anonymous | 4 | Module 110 set anonymous-only, but it scored only after `anon_root` was changed by hand from `/srv/ftp` to `/var/ftp` (linked to `/srv/ftp`). Module 110 now does this |

So the first unassisted pass reached 92; the last 8 points needed two changes learned from the answer key, both now in the scripts. Those two script changes have not been re-run from a clean snapshot.

Findings from this run:

- "Update manager installs updates automatically" was **not** a scored item on this image, so `mintupdate-automation upgrade enable` is still unverified.
- Nothing "not in the keys" caused a penalty here (extra sysctl values, `PermitEmptyPasswords`, file modes, password ageing defaults, installing Firefox).
- After the 664-package upgrade the VM stalled for long stretches, and after reboot DNS was dead until `systemctl restart systemd-resolved` and `nmcli dev reapply`. Cause not established; the scoring engine needs DNS, so check the report's connection status after a big upgrade.

## Measured result: CP19 Training Round 2, Debian 12

**100 of 100 points, 26 of 26 items, 0 penalties**, as reported by the team after two passes. Forensics (12 pts) were answered by hand.

- First pass (`--apply`, all modules): 75 points, 20 of 26.
- The first pass exposed three script bugs, since fixed: prompts inside loops were skipped ("no terminal"), so Wireshark, AisleRiot and netcat-traditional were never removed; root's crontab was edited directly, which cron does not notice, so the netcat backdoor on port 1337 kept respawning; and there was no repair for the image's frozen `snapshot.debian.org` package source.
- Second pass (`--apply 60 100 120` with the fixed scripts and the removals listed in the config): all remaining items scored. The individual item names from the second pass were not captured.

Not re-run from a clean snapshot in a single pass. After the second pass, copy and paste between host and VM stopped working; cause not confirmed (the package upgrade replacing VMware's guest tools is the likely one).

The sections below are still design estimates for the other keys.

**Nothing below has been confirmed against a scoring engine**, apart from the run above. "Auto" means the script performs the fix the key describes (or an equivalent command) when `config.conf` is filled in correctly and you answer yes to its prompts. It does not mean points were observed. Percentages are design coverage, not measured scores.

| Class | Meaning |
|---|---|
| **Auto** | `--apply` does what the key says. Config-driven items need the right config line; items marked *ask* need a yes at a prompt. |
| **Unverified** | `--apply` attempts it, but by a route the key does not give (the key shows only GUI steps). May or may not score. |
| **Partial** | Part automatic, part by hand. |
| **Report** | Audit shows the problem; a person fixes it. |
| **Manual** | Not handled. Forensics always. |

## Summary

| Key | Items | Auto | Unverified | Partial | Report | Manual | Auto % (items) | Auto % (points) |
|---|---|---|---|---|---|---|---|---|
| U-P17 Ubuntu 22 Practice | 16 | 13 | 1 | 0 | 0 | 2 | 81% | 78 of 100 = 78% |
| U-T1 Ubuntu 22 Training 1 | 17 | 14 | 1 | 0 | 0 | 2 | 82% | 79 of 101 = 78% |
| U-T2 Ubuntu 22 Training 2 (both files) | 24 | 20 | 1 | 1 | 0 | 2 | 83% | 76 of 100 = 76% |
| M-P18 Mint 21 Practice | 19 | 16 | 1 | 0 | 0 | 2 | 84% | 79 of 100 = 79% |
| M-T18 Mint 21 Training 2 | 26 | 19 | 1 | 0 | 2 | 4 | 73% | 61 of 95 printed = 64% |
| M-P19 Mint 21 Practice | 18 | 16 | 1 | 0 | 0 | 1 | 89% | 87 of 100 = 87% |
| M-T19 Mint 21 Training | 21 | 16 | 0 | 0 | 2 | 3 | 76% | 69 of 99 = 70% |

The Mint numbers assume the shared modules behave on Mint as on Ubuntu; that is phase 2 and untested. In M-T18 the two unauthorized-user items have no printed point value and are left out of the points column.

**Penalties.** Every penalty in the keys (required service stopped or removed, required package removed, files deleted from FTP directories) is guarded by the config: required services and packages are never stopped or removed, every purge is simulated first, `apt autoremove` is never run, and media under `/srv` and `/var/www` is never deleted. This holds only if `REQUIRED_SERVICES` and `REQUIRED_PACKAGES` are filled in correctly.

## U-P17 — CP17 Ubuntu 22 Practice

| # | Item | Pts | Class | Module | Note |
|---|---|---|---|---|---|
| 1 | Forensics 1 (base64) | 8 | Manual | helper `decode` | |
| 2 | Forensics 2 (MP3 directory) | 8 | Manual | helper `ext mp3` | Answer before module 70 |
| 3 | Remove user balloony | 6 | Auto | 10 | |
| 4–5 | doofenshmirtz, lawrence not admins | 12 | Auto | 10 | |
| 6 | Password for pinky | 6 | Auto | 20 | Needs `SET_PASSWORDS` |
| 7 | candace → firesidegirls | 8 | Auto | 10 | Needs `GROUP_ADD` |
| 8 | UFW enabled | 6 | Auto | 40 | |
| 9 | nginx disabled | 6 | Auto (ask) | 50 | |
| 10 | Check for updates daily | 6 | Unverified | 120 | Key gives GUI only; script sets `APT::Periodic::Update-Package-Lists "1"` |
| 11 | Chrome updated | 5 | Auto (ask) | 120 | `full-upgrade`; needs Google's apt source working |
| 12 | Thunderbird updated | 5 | Auto (ask) | 120 | A snap Thunderbird would need `snap refresh` (reported) |
| 13 | MP3s removed | 6 | Auto (ask) | 70 | |
| 14–15 | ophcrack, Wireshark removed | 12 | Auto (ask) | 60 | |
| 16 | SSH root login disabled | 6 | Auto | 30 | |

## U-T1 — CP17 Ubuntu 22 Training Round 1

| # | Item | Pts | Class | Module | Note |
|---|---|---|---|---|---|
| 1 | Forensics 1 (base64, then Trash) | 8 | Manual | helper `decode`, `trash` | |
| 2 | Forensics 2 (MP3 directory) | 8 | Manual | helper `ext mp3` | |
| 3 | Remove user eli | 6 | Auto | 10 | |
| 4 | cornelius not admin | 6 | Auto | 10 | |
| 5 | Password for alice | 6 | Auto | 20 | Needs `SET_PASSWORDS` |
| 6 | mariya → pioneers | 7 | Auto | 10 | |
| 7 | Minimum password length | 4 | Auto | 20 | `minlen` on `pam_unix.so` as in the key (and on `pam_pwquality.so` if present) |
| 8 | Null passwords | 6 | Auto | 20 | |
| 9 | UFW enabled | 6 | Auto | 40 | |
| 10 | X2Go installed | 5 | Auto | 50 | Needs `INSTALL_PACKAGES` and working apt sources |
| 11 | nginx disabled | 6 | Auto (ask) | 50 | |
| 12 | Check for updates daily | 6 | Unverified | 120 | |
| 13–14 | Firefox, Thunderbird updated | 10 | Auto (ask) | 120 | |
| 15 | MP3s removed | 6 | Auto (ask) | 70 | |
| 16 | AisleRiot removed | 5 | Auto (ask) | 60 | |
| 17 | SSH root login disabled | 6 | Auto | 30 | |

## U-T2 — CP17 Ubuntu 22 Training Round 2 (same key as CP18 Ubuntu22 Training2)

| # | Item | Pts | Class | Module | Note |
|---|---|---|---|---|---|
| 1–2 | Forensics 1, 2 | 14 | Manual | helpers | |
| 3–6 | eli, cornelius, alice, mariya | 11 | Auto | 10, 20 | |
| 7 | Default minimum password age | 3 | Auto | 20 | `PASS_MIN_DAYS 2` |
| 8 | Minimum password length | 4 | Auto | 20 | On `pam_pwquality.so` as in this key |
| 9 | Account lockout | 3 | Auto (type YES) | 20 | Key's two-profile recipe. Highest lockout risk; never run |
| 10 | Null passwords | 3 | Auto | 20 | |
| 11–12 | SYN cookies, IP forwarding | 8 | Auto | 90 | |
| 13 | UFW enabled | 5 | Auto | 40 | |
| 14 | `/etc/shadow` permissions | 5 | Auto | 80 | |
| 15 | X2Go installed | 5 | Auto | 50 | |
| 16–17 | nginx, vsftpd disabled | 8 | Auto (ask) | 50 | |
| 18 | Check for updates daily | 5 | Unverified | 120 | |
| 19–20 | Firefox, Thunderbird updated | 8 | Auto (ask) | 120 | |
| 21 | MP3s removed | 4 | Auto (ask) | 70 | |
| 22 | AisleRiot removed | 4 | Auto (ask) | 60 | |
| 23 | netcat backdoor | 5 | Partial | 100, 60 | Cron line removed automatically; process killed after a prompt; the binary goes only if you agree to purge `netcat-traditional` in module 60, otherwise `rm` by hand. Which of the three the scorer checks is unknown |
| 24 | SSH root login disabled | 5 | Auto | 30 | |

## M-P18 — CP18 Mint 21 Practice

| # | Item | Pts | Class | Module | Note |
|---|---|---|---|---|---|
| 1 | Forensics 1 (codename) | 8 | Manual | helper `os` | |
| 2 | Forensics 2 (MP3 directory) | 8 | Manual | helper `ext mp3` | |
| 3–5 | Remove leon, oirving, romero | 12 | Auto | 10 | |
| 6–7 | tcolby, mralbern not admins | 8 | Auto | 10 | |
| 8 | Password for pmccleery | 4 | Auto | 20 | |
| 9 | UFW enabled | 6 | Auto | 40 | |
| 10 | Apache2 installed and started | 6 | Auto | 50 | `INSTALL_PACKAGES=(apache2)` and `REQUIRED_SERVICES=(apache2)` |
| 11 | Update Manager installs automatically | 5 | Unverified | 120 | `mintupdate-automation upgrade enable`; command not confirmed |
| 12–15 | systemd, OpenSSH, Chromium, Gimp updated | 20 | Auto (ask) | 120 | |
| 16 | MP3s removed | 5 | Auto (ask) | 70 | |
| 17–18 | Wireshark, ophcrack removed | 12 | Auto (ask) | 60 | |
| 19 | SSH root login disabled | 6 | Auto | 30 | |

## M-T18 — CP18 Mint 21 Training 2

| # | Item | Pts | Class | Module | Note |
|---|---|---|---|---|---|
| 1 | Forensics 1 (backdoor directory) | 6 | Manual | helper `ports` | Answer before killing anything |
| 2 | Forensics 2 (pcap passwords) | 6 | Manual | helper `pcap` | Uses `tcpdump` if installed; the key installs `tshark` |
| 3 | Forensics 3 (steghide, MD5) | 6 | Manual | helper `decode`, `steg`, `hash` | Needs `steghide`; installing it is a human decision |
| 4 | Remove penguru | ? | Auto | 10 | |
| 5 | Remove hidden user (liv) | ? | Auto (ask) | 10 | Only if the account has a password; otherwise Report |
| 6 | ham not admin | 3 | Auto | 10 | |
| 7 | noir maximum password age | 4 | Auto | 20 | Skipped and reported if noir's password is already older than 90 days |
| 8–9 | Group spider, members | 7 | Auto | 10 | Uses `gpasswd -a` per user rather than the key's `gpasswd -M` |
| 10 | Root password blank | 4 | Auto | 20 | |
| 11 | Minimum length | 3 | Auto | 20 | |
| 12 | Password history | 3 | Auto | 20 | |
| 13 | Account lockout | 4 | Auto (type YES) | 20 | Key's three-profile recipe; never run |
| 14 | Null passwords | 4 | Auto | 20 | Only if `nullok` is actually on the line (the key's quoted line has none) |
| 15–16 | ASLR, SYN cookies | 8 | Auto | 90 | |
| 17 | UFW enabled | 3 | Auto | 40 | Allows 21/tcp for required vsftpd; passive FTP ports are not opened |
| 18–19 | nginx, Squid disabled | 8 | Auto (ask) | 50 | |
| 20 | Update Manager installs automatically | 3 | Unverified | 120 | |
| 21 | vsftpd updated | 3 | Manual | 120 | Sources must be repaired in Software Sources first; then module 120 upgrades |
| 22 | OGG files removed | 4 | Auto (ask) | 70 | |
| 23 | `pyrdp-master.zip` removed | 4 | Report | 60 | Listed as an archive in `/usr/games` |
| 24–25 | doona, xprobe removed | 6 | Auto (ask) | 60 | |
| 26 | zod backdoor | 6 | Report | 100 | Listener, command line and launcher are shown; removal by hand |

## M-P19 — CP19 Mint 21 Practice

| # | Item | Pts | Class | Module | Note |
|---|---|---|---|---|---|
| 1 | Forensics 1 (MP3 directory) | 8 | Manual | helper `ext mp3` | |
| 2–3 | Remove tgianopolous, jquelling | 10 | Auto | 10 | |
| 4 | dscott not admin | 5 | Auto | 10 | |
| 5 | Password for llitt | 5 | Auto | 20 | |
| 6 | New administrator edarby | 6 | Auto | 10 | `NEW_USERS=("edarby:admin")` plus the admin list |
| 7 | edarby must change password | 6 | Auto | 20 | `FORCE_PW_CHANGE=(edarby)` |
| 8 | UFW enabled | 6 | Auto | 40 | |
| 9 | vsftpd disabled or removed | 6 | Auto (ask) | 50 | Disabled, not purged |
| 10 | Refreshes update list automatically | 5 | Unverified | 120 | Script sets `APT::Periodic` and tries the Mint automation command; the Mint switch itself is by hand |
| 11 | Install important security updates | 5 | Auto (ask) | 120 | `full-upgrade` |
| 12–14 | systemd, Chromium, OpenSSH updated | 15 | Auto (ask) | 120 | |
| 15 | MP3s removed | 5 | Auto (ask) | 70 | |
| 16–17 | Wireshark, Zangband removed | 12 | Auto (ask) | 60 | |
| 18 | SSH root login disabled | 6 | Auto | 30 | |

## M-T19 — CP19 Mint 21 Training

| # | Item | Pts | Class | Module | Note |
|---|---|---|---|---|---|
| 1 | Forensics 1 (backdoor directory) | 8 | Manual | helper `ports` | |
| 2 | Forensics 2 (steghide, MD5) | 8 | Manual | helper `decode`, `steg`, `hash` | |
| 3 | Remove hidden user felix | 4 | Auto (ask) | 10 | Only if the account has a password; otherwise Report |
| 4 | nova not admin | 4 | Auto | 10 | |
| 5 | kaia maximum password age | 5 | Auto | 20 | |
| 6–7 | Group spider, members | 9 | Auto | 10 | |
| 8 | Root password blank | 5 | Auto | 20 | |
| 9 | Minimum length | 4 | Auto | 20 | |
| 10 | Account lockout | 4 | Auto (type YES) | 20 | |
| 11 | Null passwords | 4 | Auto | 20 | |
| 12 | SYN cookies | 5 | Auto | 90 | |
| 13 | UFW enabled | 5 | Auto | 40 | |
| 14–15 | nginx, Squid disabled | 10 | Auto (ask) | 50 | |
| 16 | vsftpd updated | 5 | Manual | 120 | Repair sources first |
| 17 | OGG files removed | 4 | Auto (ask) | 70 | |
| 18 | `pyrdp-master.zip` removed | 4 | Report | 60 | |
| 19–20 | doona, xprobe removed | 6 | Auto (ask) | 60 | |
| 21 | zod backdoor | 5 | Report | 100 | |

## Things the scripts do that no key scored

Listed so a practice run can tell whether they help, do nothing, or hurt: `PermitEmptyPasswords no`; `ufw default deny incoming`; `PASS_MAX_DAYS 90` and `PASS_WARN_AGE 7` in `login.defs`; Ubuntu-default modes on `passwd`, `group`, `gshadow`, `sudoers`; removing world-write under `/etc`, `/usr`, `/boot`; the extra sysctl values; `APT::Periodic::Unattended-Upgrade "1"`; `allow-guest=false` for LightDM; adding an authorized administrator to `sudo` when missing.
