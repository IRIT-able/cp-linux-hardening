<#
  CyberPatriot - automatic run for Windows 10/11 and Windows Server, driven by a README config.

  1. Copy cp-config.example.psd1 to cp-config.psd1 and fill it in from the README on the desktop.
  2. Check only (changes nothing):   powershell -ExecutionPolicy Bypass -File .\CP-Run.ps1 -Audit
  3. Answer the forensics questions, then set ForensicsDone = $true in the config.
  4. Run:                             powershell -ExecutionPolicy Bypass -File .\CP-Run.ps1

  Another config file:               .\CP-Run.ps1 -Config .\configs\win11-cp19-r2.psd1
  Missed something? CyberPatriot-Toolkit.ps1 is the same code as an interactive menu.

  This replaces the per-round scripts (CP-Round2-Win11.ps1, CP-Round2-Server2022.ps1): everything that was
  typed into those now comes from the config, so a new image needs a new config, not a new script.
#>
param(
    [string]$Config,
    [switch]$Audit
)

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $extra = ''
    if ($Config) { $extra += " -Config `"$Config`"" }
    if ($Audit)  { $extra += ' -Audit' }
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"$extra" -Verb RunAs
    exit
}
$Toolkit = Join-Path $PSScriptRoot 'CyberPatriot-Toolkit.ps1'
if (-not (Test-Path $Toolkit)) { Write-Host "CyberPatriot-Toolkit.ps1 must be in the same folder as this script ($PSScriptRoot)." -ForegroundColor Red; Read-Host; exit 1 }
. $Toolkit

if (-not $Config) { $Config = Join-Path $PSScriptRoot 'cp-config.psd1' }
if (-not (Test-Path $Config)) {
    Warn "No config at $Config. Copy cp-config.example.psd1 to cp-config.psd1 and fill it in from the README."
    Read-Host "`n  Press Enter to close" | Out-Null; exit 1
}
try { Use-CpConfig (Resolve-Path $Config).Path } catch { Warn "The config could not be read: $($_.Exception.Message)"; Read-Host "`n  Press Enter to close" | Out-Null; exit 1 }
if (-not (Test-CpConfig)) {
    Warn 'The config failed its checks (see above). Nothing was changed.'
    Read-Host "`n  Press Enter to close" | Out-Null; exit 1
}

# ------------------------------------------------------------------------------
# -Audit: read-only. Shows what the README config will be compared against and what is on the machine.
# ------------------------------------------------------------------------------
if ($Audit) {
    Say "`n  AUDIT ONLY - nothing is changed   (config: $Config)" White
    Head 'Config'
    Info "Admins: $($Cfg.Admins -join ', ')"
    Info "Users:  $($Cfg.Users -join ', ')"
    Info "Critical services: $($Cfg.CriticalServices -join ', ')   Remote Desktop: $($Cfg.RemoteDesktop)"
    Info "Required apps: $($Cfg.RequiredApps -join ', ')"
    Info "ForensicsDone: $($Cfg.ForensicsDone)"
    if (-not $IsDC) {
        $all = @($Cfg.Admins) + @($Cfg.Users)
        Head 'Accounts'
        Get-LocalUser | Where-Object { $_.SID.Value -notmatch '-(500|501|503|504)$' -and $_.Name -notin $all } | ForEach-Object { Warn "Not in the README (would be removed): $($_.Name)" }
        $all | Where-Object { -not (Get-LocalUser -Name $_ -ErrorAction SilentlyContinue) } | ForEach-Object { Warn "In the README but missing (would be created): $_" }
        Get-GroupMembers $AdminGrp | Where-Object { $_ -notin $Cfg.Admins -and $_ -notmatch '^(Administrator|Domain Admins)$' } | ForEach-Object { Warn "Administrator but not a README admin (would be demoted): $_" }
        Get-LocalUser | Where-Object { $_.Enabled -and -not $_.PasswordExpires } | ForEach-Object { Warn "Password never expires: $($_.Name)" }
    }
    Head 'Installed programs flagged as prohibited'
    Get-Installed | Where-Object { ($_.DisplayName -match $BadSoftware -or (Test-RemoveListed $_.DisplayName)) -and -not (Test-Required $_.DisplayName) } | ForEach-Object { Warn "Would be uninstalled: $($_.DisplayName) $($_.DisplayVersion)" }
    Get-Installed | Where-Object { $_.DisplayName -match $BadSoftware -and (Test-Required $_.DisplayName) } | ForEach-Object { Info "Kept (README requires it): $($_.DisplayName)" }
    Head 'Services that would be stopped'
    foreach ($n in $BadServices.Keys) { $s = Get-Service $n -ErrorAction SilentlyContinue; if ($s -and -not ($s.Status -eq 'Stopped' -and $s.StartType -eq 'Disabled')) { Warn "Would be disabled: $n ($($BadServices[$n])) - now $($s.Status)/$($s.StartType)" } }
    Head 'Shares'
    Get-SmbShare | Where-Object { $_.Name -notmatch $KeepShares } | ForEach-Object { Warn "Would be removed: share $($_.Name) -> $($_.Path)" }
    Head 'Listening ports (one snapshot)'
    $Auto = $true; $saved = $Cfg.ForensicsDone; $Cfg.ForensicsDone = $false   # CanDestroy is false: nothing below can remove anything
    Show-Listeners 1 0
    $Cfg.ForensicsDone = $saved
    Head 'Done'
    Info "Read every [!] line above against the README. Log: $Log"
    Read-Host "`n  Press Enter to close" | Out-Null
    exit
}

# ------------------------------------------------------------------------------
# Automatic run
# ------------------------------------------------------------------------------
$Auto = $true
$AutoPassword = if ($Cfg.NewPassword) { $Cfg.NewPassword } else { 'Afa!' + [guid]::NewGuid().ToString('N').Substring(0, 12) + 'Zq7#' }
# Errors/warnings from this run and every background window are collected here.
$ErrorReport = Join-Path ([Environment]::GetFolderPath('Desktop')) ("CP-Errors-{0:HHmmss}.txt" -f (Get-Date))

function Set-ReadmeRdp {
    Set-RemoteAccess $Cfg.RemoteDesktop
    if ("$($Cfg.RemoteDesktop)" -notmatch '^(y|req)') { return }
    if (-not $IsDC) { Set-SecPolicy -Section 'Privilege Rights' @{ SeRemoteInteractiveLogonRight = '*S-1-5-32-544,*S-1-5-32-555'; SeDenyRemoteInteractiveLogonRight = '*S-1-5-32-546' } }
    $port = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp').PortNumber
    if ($port -ne 3389) { Warn "RDP listens on port $port, not 3389 - firewall rule 'Remote Desktop' only covers 3389." }
    if (-not $IsDC) {
        Head 'Remote Desktop Users (only README accounts may stay)'
        Sync-Group (Get-LocalGroup -SID 'S-1-5-32-555').Name @() @($Cfg.Admins + $Cfg.Users)
    }
}

$t0 = Get-Date
$sharePaths = @($Cfg.Shares | ForEach-Object { $_.Path } | Where-Object { $_ })
Say "`n  CYBERPATRIOT AUTOMATIC RUN - $($OS.Caption)   (config: $Config   log: $Log)" White
if (-not $Cfg.ForensicsDone) {
    Say '  ForensicsDone is $false: users, files, programs and backdoors will NOT be removed this run.' Yellow
    Say '  Answer the forensics questions, set ForensicsDone = $true in the config, and run again.' Yellow
}

Step 'VMware copy and paste' { Start-VmwareUserAgent }
if ($Cfg.UpdateApps.Count) { Step 'README app updates (new window)' { Start-NamedAppUpdates $Cfg.UpdateApps } }
Step 'Windows features (new window)' { Start-FeatureRemoval }
Step 'Users and groups' { Invoke-UserAudit $Cfg.Admins $Cfg.Users }
if ($Cfg.Groups.Count) { Step 'Groups the README asks for' { Set-ReadmeGroups } }
Step 'Password + lockout policy' { Set-PasswordPolicy }
Step 'User rights' { if ($IisCritical) { Set-UserRightsIIS } else { Set-UserRights } }
Step 'Security options' { Set-SecurityOptions }
Step 'Firewall, Defender, auditing' { Set-Protection }
Step 'Remote Desktop' { Set-ReadmeRdp }
Step 'Services' { Set-Services }
Step 'Prohibited software, unknown program folders, old versions' { Remove-BadSoftware }
Step 'Prohibited files (whole drive)' { Find-BadFiles }
Step 'Files containing passwords or personal data' { Find-SensitiveFiles (@('C:\Users') + $sharePaths + @(Get-IisRoots)) $sharePaths }
Step 'Backdoors, autoruns, tasks, shares, hosts, listeners' { Invoke-Review }
Step 'Network adapters' { Set-NetworkAdapters $KeepBindings }
if ($IisCritical) { Step 'IIS (critical): directory browsing off + hardening' { Set-IIS } }
foreach ($sh in $Cfg.Shares) { Step "README share $($sh.Name)" { Set-ReadmeShare $sh } }
Step 'Windows Update policy' { Set-WindowsUpdatePolicy $Cfg.WindowsUpdateMode }
if ($Cfg.InstallWindowsUpdates) { Step 'Windows security updates (new window, no feature updates)' { Start-InNewWindow 'Windows security updates' 'Install-SecurityUpdates' } }
Step 'Action Center' { Set-ActionCenter }
if ($Cfg.DefaultBrowser) { Step "Default browser -> $($Cfg.DefaultBrowser)" { Set-DefaultBrowser $Cfg.DefaultBrowser } }
Step 'Firewall rules left behind by uninstalls' { Remove-StaleFirewallRules }
Step 'Final check' { Invoke-FinalCheck }

Head 'Done'
Ok "Automatic run finished in $([int]((Get-Date) - $t0).TotalSeconds)s"
if ($Cfg.ResetPasswords -ne $false) { Say "  [*] New password for every README account except you: $AutoPassword" Yellow; Add-Content $Log "[*] New password: $AutoPassword" }
Save-ErrorReport 'Main run'
Info "Error report: $ErrorReport  <- READ THIS. Every [!] line is something a person has to decide."
Info 'Still running in other windows: app updates, Windows features, Defender scan.'
Info 'Click through any uninstaller windows. Removed files are in C:\cp-quarantine. Reboot, wait two minutes, read the scoring report.'
Read-Host "`n  Press Enter to close" | Out-Null
