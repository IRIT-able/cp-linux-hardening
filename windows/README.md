# CyberPatriot Windows scripts

For Windows 10/11 and Windows Server 2016+. Native PowerShell 5.1, nothing to install.

These are a teammate's scripts (`CyberPatriot-Toolkit.ps1` and two per-round scripts), reworked so they are driven by a README config the same way the Linux scripts are, with fixes for everything the Round 2 Windows 11 and Server 2022 runs missed.

**Test status: none of this version has been run on Windows.** It was written on a Linux machine with no PowerShell available, so it has not even been through PowerShell's own parser. The only checks done are bracket balance and a read-through. Expect a typo-level error or two on the first run: start with `-Audit` on a snapshotted practice image, and send back the red error text.

## Files

| File | Purpose |
|---|---|
| `CP-Run.ps1` | Automatic run driven by the config. Replaces the per-round scripts. |
| `CyberPatriot-Toolkit.ps1` | All the functions, plus an interactive menu when run on its own. |
| `cp-config.example.psd1` | Template. Copy to `cp-config.psd1` and fill in from the README. |
| `configs/` | Filled-in examples for the two CP19 Round 2 images. |

## Run order

1. Take a VM snapshot (practice). Read the README and every Forensics Question.
2. Copy `cp-config.example.psd1` to `cp-config.psd1` and fill it in (table below).
3. Check, changing nothing:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\CP-Run.ps1 -Audit
   ```
4. Answer the forensics questions. Set `ForensicsDone = $true` in the config.
5. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\CP-Run.ps1
   ```
6. Read `CP-Errors-<time>.txt` on the Desktop. Every `[!]` line is something a person has to decide.
7. Click through any uninstaller windows, reboot, wait two minutes, read the scoring report.
8. Use `CyberPatriot-Toolkit.ps1` (menu) for anything left. Menu option `C` loads the same config.

Getting the files onto the VM: open PowerShell in the VM and paste this. It downloads the `windows` branch to the Desktop and opens the folder (while the scripts live on the `windows` branch; change `windows` to `main` in both places once they are merged):

```powershell
cd $HOME\Desktop; [Net.ServicePointManager]::SecurityProtocol = 'Tls12'; iwr https://github.com/IRIT-able/cp-linux-hardening/archive/refs/heads/windows.zip -OutFile cp.zip -UseBasicParsing; Expand-Archive cp.zip . -Force; cd cp-linux-hardening-windows\windows
```

## Filling in the config from a README

| README text | Config setting |
|---|---|
| Authorized Administrators | `Admins = @('name', 'name')` - names only |
| Authorized Users | `Users = @(...)` |
| Critical Services | `CriticalServices = @('RDP')` - keywords `RDP`, `IIS`, `SMB`, `FTP`, `DNS`, `SSH`, `Print`, `WinRM`, `SNMP`, `Telnet`, `SMTP`, or an exact service name |
| Software that must stay ("authorized", "required", "employees use") | `RequiredApps = @('Google Chrome', 'Wireshark')` - part of the name shown in Settings > Apps |
| Software to keep up to date | `UpdateApps = @('Google.Chrome', ...)` - winget ids |
| Default browser | `DefaultBrowser = 'Chrome'` (or `'Firefox'`, `'Edge'`) |
| "Create a group X and add a, b" | `Groups = @{ 'X' = @('a', 'b') }` |
| A folder that must stay shared | `Shares = @( @{ Name = 'Handbook'; Path = 'C:\Shares\Handbook' } )` |
| Business files that must not be removed | `KeepPaths = @('D:\Projects')` |
| "Do not install feature updates" | leave `InstallWindowsUpdates = $false`, or `$true` for security updates only |

The run refuses to start if `Admins` is empty, if your own account is not in `Admins`, or if the config would remove half or more of the accounts on the machine.

## What changed from the original scripts

| Problem on the Round 2 images | Fix |
|---|---|
| README data was typed into a script per image | One `CP-Run.ps1`; the README goes in `cp-config.psd1` |
| Nothing stopped a run before forensics were answered | `ForensicsDone` gate: no users, files, programs or backdoors are removed until it is `$true` |
| Minesweeper in `C:\Program Files\Minesweeper` and HFS in `C:\HFS` were missed (not "installed") | Every folder in both Program Files folders and the root of `C:` is compared with the installed-programs list and the README; games and tools are quarantined, the rest reported |
| Defender `.exe` exclusion survived (set by policy) | Policy exclusions under `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions` are removed too |
| `SharpHound.zip` was listed but not removed | Tool names extended (SharpHound, BloodHound, Rubeus, LaZagne, PsExec, HFS and more); the file scan now covers the whole drive, not three folders |
| `staff.csv` with passwords in the share | New content scan of text files; matches inside README shares are quarantined, the rest reported |
| Backdoor (netcat renamed `nvhostsvc.exe` in System32) was not listening when checked | Every `.exe` in Windows, System32 and SysWOW64 is checked for original file name and signature; unsigned files that a service, task or Run key starts are removed with their launcher. Ports are sampled three times and mapped to program, file and signature |
| AnyDesk's port 7070 was mistaken for the backdoor | Known remote-tool ports are labelled (7070 AnyDesk, 5938 TeamViewer, 5900 VNC) |
| AnyDesk / TeamViewer firewall rules left after uninstall | Inbound allow rules for prohibited tools, or whose program no longer exists, are removed |
| App updates needed winget, which was not on the image | Direct downloads for LibreOffice (with mirror fallback), Thunderbird, Firefox and OpenRocket, added to Chrome, Notepad++ and 7-Zip |
| "Update by hand" warning for an already-current Thunderbird | Installed version is compared with the latest before warning |
| Old 7-Zip left beside the new one | Older duplicate versions are uninstalled |
| Windows Update ended at "notify", and gpupdate undid registry edits | Policy set to option 4; if Local Group Policy's `Registry.pol` holds the value, it is changed there too, then verified |
| Feature updates must not be installed | Optional step installs security and quality updates only |
| ASP.NET `customErrors mode="Off"` | Set to `RemoteOnly` at server level and in every site `web.config` |
| Copy and paste into the VM did not work | The VMware Tools user agent is started if it is missing |
| A check dropped during an install and came back | A final check re-reads firewall, Defender, required services, update policy, shares and accounts |
| Required software could be removed (Wireshark on an image that authorizes it) | Anything matching `RequiredApps` is never uninstalled, quarantined or firewalled off |
| Files deleted permanently | Programs, startup items, web shells and sensitive files go to `C:\cp-quarantine`; media and tool files are still deleted |

Kept as they were: password policy, lockout, audit policy, UAC, SMB1 and signing, RDP NLA, Remote Assistance, Ctrl+Alt+Del, AutoPlay, Defender, SmartScreen and the security options. All of those scored cleanly.

## Least certain parts

Check these first on a practice image:

- **Syntax of the whole file**, as said above.
- **`Registry.pol` edit** (`Set-PolDword`): changes a 4-byte number in place and keeps `Registry.pol.cp-backup`. Only runs when the file already contains that Windows Update value.
- **Unsigned-file removal in System32**: the rule is "not Microsoft, not signed, and started by a service, task or Run key, or listening". A legitimate unsigned third-party helper would match. Files are quarantined and services disabled, not deleted.
- **OpenRocket silent install** (`-q`) and the **LibreOffice mirror URLs and file name pattern**: written from memory.
- **Whole-drive file scan**: slower than the old three-folder scan.
- **Stale firewall rule removal**: removes any inbound allow rule whose program path no longer exists outside `C:\Windows`.

## Always by hand

Forensics questions; reading the error report; anything the README asks that the config cannot express; your own account's "password never expires" flag (reported, never changed); Store apps; browser settings; Windows feature updates (never install them).
