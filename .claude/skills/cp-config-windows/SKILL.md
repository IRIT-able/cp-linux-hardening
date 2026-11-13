---
name: cp-config-windows
description: Turn a CyberPatriot Windows image README (Windows 10/11 or Windows Server) into a filled-in cp-config.psd1 for the Windows scripts in windows/. Use when the user pastes a Windows README and asks for the config.
---

# CyberPatriot Windows README → cp-config.psd1

Produce one file, `windows/cp-config.psd1`, from the README. Start from `windows/cp-config.example.psd1`: keep every setting name and the order. `windows/configs/` has two finished examples.

The file is PowerShell data, read with `Import-PowerShellDataFile`. Only literals are allowed: `@('a', 'b')` lists, `@{ }` tables, `'single-quoted text'`, numbers, `$true`, `$false`. No variables, no commands, no double-quoted strings with `$` in them.

## The one rule that matters

Every value comes from the README text. Never add an account, service or program because it is usually there, and never copy from another image's config. If the README does not say, leave the list empty and tell the user.

## Mapping

| README text | Setting | Notes |
|---|---|---|
| Authorized Administrators | `Admins` | Names only. Drop "(you)" and all `password:` lines. |
| Authorized Users | `Users` | All of them. A name must not be in both lists. |
| "Critical Services", or a sentence saying a service must stay available | `CriticalServices` | Keywords: `RDP`, `IIS`, `SMB`, `FTP`, `DNS`, `SSH`, `Print`, `WinRM`, `SNMP`, `Telnet`, `SMTP`. Otherwise the exact Windows service name. |
| Remote Desktop must work / must be disabled | `RemoteDesktop = 'required'` / `'off'` | `'leave'` when the README is silent. |
| Software employees use, or that is "authorized" | `RequiredApps` | Part of the display name: `'Google Chrome'`, `'Notepad++'`, `'LibreOffice'`, `'7-Zip'`, `'Wireshark'`. Include authorized tools that look like hacking tools, so they are kept. |
| Software to be kept up to date | `UpdateApps` | winget ids: `Google.Chrome`, `Mozilla.Firefox`, `Mozilla.Thunderbird`, `TheDocumentFoundation.LibreOffice`, `Notepad++.Notepad++`, `7zip.7zip`, `OpenRocket.OpenRocket`, `WinSCP.WinSCP`. If unsure of an id, leave it out and say so. |
| Default browser | `DefaultBrowser` | `'Chrome'`, `'Firefox'` or `'Edge'`. |
| "Create group X and add a, b" | `Groups = @{ 'X' = @('a', 'b') }` | |
| A folder that must stay shared | `Shares = @( @{ Name = 'ShareName'; Path = 'C:\Path' } )` | Also add `'SMB'` to `CriticalServices`. |
| Business files that must not be removed | `KeepPaths` | Full folder paths. |
| "Do not install feature updates" | `InstallWindowsUpdates = $false` | Say in your reply that `$true` installs security updates only. |
| README needs OneDrive | `DisableOneDrive = $false` | |

Leave alone on a first config: `ForensicsDone = $false` (unless the user says forensics are answered), `RemoveSoftware = @()`, `RemoveFiles = @()`, `ResetPasswords = $true`, `NewPassword = ''`, `WindowsUpdateMode = 4`, `ScanRoots = @()`.

Never put README passwords in the file.

## Output

1. Write the file with a one-line comment above each block quoting the README sentence it came from.
2. Count the names in `Admins` and `Users` against the README. A dropped or misspelled name gets that account deleted.
3. Check the syntax: balanced `@( )` and `@{ }`, single quotes only, backslashes in paths not doubled.
4. Reply with: the counts, critical services, required apps, anything the README asks that the config cannot express (to be done by hand), and the next command: `powershell -ExecutionPolicy Bypass -File .\CP-Run.ps1 -Audit`.
