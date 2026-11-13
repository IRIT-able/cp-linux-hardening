<#
  CyberPatriot Hardening Toolkit
  Windows 10/11 and Windows Server 2016+. Native PowerShell 5.1, no modules to install.

  Run:  powershell -ExecutionPolicy Bypass -File .\CyberPatriot-Toolkit.ps1     (interactive menu)
        powershell -ExecutionPolicy Bypass -File .\CP-Run.ps1                  (automatic, driven by cp-config.psd1)
  READ THE README FIRST. Do the forensics questions BEFORE deleting files or users.
  Anything destructive asks first. Every change is written to the log file next to this script.
#>

# --- self-elevate -------------------------------------------------------------
$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ErrorActionPreference = 'Continue'
$ToolkitPath = $PSCommandPath   # this file, even when dot-sourced - used to load functions into extra windows
$Here = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$Log  = Join-Path $Here ("cp-log-{0:yyyyMMdd-HHmmss}-$PID.txt" -f (Get-Date))   # PID: parallel windows start in the same second
$OS   = Get-CimInstance Win32_OperatingSystem
$IsDC = $OS.ProductType -eq 2

# --- output helpers -----------------------------------------------------------
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Ok($m)   { Say "  [+] $m" Green;  Add-Content $Log "[+] $m" }
function Warn($m) { Say "  [!] $m" Yellow; Add-Content $Log "[!] $m" }
function Info($m) { Say "  [*] $m" Cyan }
function Head($m) { Say "`n  --- $m ---" Magenta }
# Auto mode (set by the round scripts): every prompt takes the default given at its call site, no human input.
$Auto = $false
function Ask($q, $AutoAnswer = $false) {
    if ($Auto) { Say "  [auto] $q -> $(if ($AutoAnswer) { 'yes' } else { 'no' })" DarkGray; return $AutoAnswer }
    (Read-Host "  $q [y/N]") -match '^\s*y'
}
function ConvertTo-PSList($a) { ($a | ForEach-Object { "'$($_ -replace "'", "''")'" }) -join ',' }
function Get-NewPassword {
    if ($Auto) { ConvertTo-SecureString $AutoPassword -AsPlainText -Force } else { Read-Host '  Password for new/reset accounts' -AsSecureString }
}

# Runs toolkit code in its own elevated PowerShell window so the menu stays usable (e.g. long app updates).
# Runs one step; any error it throws or prints is turned into a logged [!] warning so it lands in the error report.
function Step($Name, [scriptblock]$Do) {
    Head $Name
    try {
        & $Do 2>&1 | ForEach-Object {
            if ($_ -is [Management.Automation.ErrorRecord]) { Warn "$Name : $($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))" } else { $_ }
        }
    } catch { Warn "$Name FAILED: $($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))" }
}

# Appends this window's [!] lines to the error report on the Desktop (set by the automatic scripts).
$ErrorReport = $null
function Save-ErrorReport($Title) {
    if (-not $ErrorReport) { return }
    $lines = @(Get-Content $Log -ErrorAction SilentlyContinue | Where-Object { $_ -like '`[!`]*' })
    $body = @("===== $Title   finished $(Get-Date -Format 'HH:mm:ss')   full log: $Log =====") +
            $(if ($lines) { $lines } else { '(no errors or warnings)' }) + ''
    for ($i = 0; $i -lt 10; $i++) {   # several windows may append at once
        try { Add-Content $ErrorReport $body -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds 300 }
    }
}

function Start-InNewWindow($Title, $Code) {
    $cmd = "`$Host.UI.RawUI.WindowTitle = '$Title'; . '$ToolkitPath'; `$Auto = `$$Auto; `$ErrorReport = '$ErrorReport'; " +
           "if ('$CfgPath') { Use-CpConfig '$CfgPath' }; " +
           "Step '$Title' { $Code }; Save-ErrorReport '$Title'; Read-Host '`n  Finished - press Enter to close'"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc"
    Ok "$Title running in a new window - keep using the menu"
}
function Read-List($prompt) {
    @((Read-Host "  $prompt (comma/space separated)") -split '[,;\s]+' | Where-Object { $_ })
}

# Numbered picker: returns the items the user selected ("1,3,5-8", "all", or Enter for none).
# In auto mode it returns the items $AutoPick says yes to (default: none).
function Select-Items($Items, [scriptblock]$Label, [scriptblock]$AutoPick = { $false }) {
    $Items = @($Items | Where-Object { $_ })
    if (-not $Items.Count) { Say '  (none found)' DarkGray; return }
    if ($Auto) {
        $pick = @($Items | Where-Object $AutoPick)
        $pick | ForEach-Object { Say "  [auto] $($_ | ForEach-Object $Label)" DarkGray }
        Say "  [auto] picked $($pick.Count) of $($Items.Count)" DarkGray
        return $pick
    }
    for ($i = 0; $i -lt $Items.Count; $i++) { Say ("  {0,3}) {1}" -f ($i + 1), ($Items[$i] | ForEach-Object $Label)) }
    $s = Read-Host '  Select (e.g. 1,3,5-8 / all / Enter = none)'
    $idx = if ($s -eq 'all') { 0..($Items.Count - 1) } else {
        foreach ($p in $s -split ',') {
            if ($p -match '^\s*(\d+)\s*(?:-\s*(\d+))?\s*$') {
                $a = [int]$matches[1]; $b = if ($matches[2]) { [int]$matches[2] } else { $a }
                ($a - 1)..($b - 1)
            }
        }
    }
    $idx | Where-Object { $_ -ge 0 -and $_ -lt $Items.Count } | Sort-Object -Unique | ForEach-Object { $Items[$_] }
}

function Set-Reg($Path, $Name, $Value, $Label, $Type = 'DWord') {
    try {
        if (-not (Test-Path $Path)) { New-Item $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        Ok $(if ($Label) { $Label } else { "$Name = $Value" })
    } catch { Warn "$Name : $($_.Exception.Message)" }
}

# Edits one section of the local security policy: [System Access] (password/lockout/guest/anon) or [Privilege Rights].
function Set-SecPolicy([hashtable]$Settings, $Section = 'System Access') {
    $inf = Join-Path $env:TEMP 'cp-secpol.inf'; $sdb = Join-Path $env:TEMP 'cp-secpol.sdb'
    secedit /export /cfg $inf /areas SECURITYPOLICY USER_RIGHTS /quiet | Out-Null
    $lines = [Collections.Generic.List[string]](Get-Content $inf)
    $at = $lines.IndexOf("[$Section]")
    if ($at -lt 0) { $lines.Add("[$Section]"); $at = $lines.Count - 1 }
    foreach ($k in $Settings.Keys) {
        $line = "$k = $($Settings[$k])"; $found = $false
        for ($j = 0; $j -lt $lines.Count; $j++) { if ($lines[$j] -match "^$k\s*=") { $lines[$j] = $line; $found = $true; break } }
        if (-not $found) { $lines.Insert($at + 1, $line) }
    }
    $lines | Set-Content $inf -Encoding Unicode
    secedit /configure /db $sdb /cfg $inf /areas SECURITYPOLICY USER_RIGHTS /quiet | Out-Null
    if ($LASTEXITCODE -eq 0) { $Settings.Keys | ForEach-Object { Ok "$_ = $($Settings[$_])" } } else { Warn "secedit failed ($LASTEXITCODE)" }
    Remove-Item $inf, $sdb -ErrorAction SilentlyContinue
}

# Group names resolved by SID so non-English images work too.
$AdminGrp = (Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction SilentlyContinue).Name
$UsersGrp = (Get-LocalGroup -SID 'S-1-5-32-545' -ErrorAction SilentlyContinue).Name

# ADSI instead of Get-LocalGroupMember: the latter breaks on orphaned SIDs (common on CP images).
function Get-GroupMembers($g) {
    try {
        @(([ADSI]"WinNT://$env:COMPUTERNAME/$g,group").psbase.Invoke('Members') |
            ForEach-Object { $_.GetType().InvokeMember('Name', 'GetProperty', $null, $_, $null) })
    } catch { @() }
}

function Sync-Group($g, $want, $keep = @()) {
    $have = Get-GroupMembers $g
    foreach ($m in $have) {
        if ($m -notin $want -and $m -notin $keep -and (Ask "'$m' should NOT be in '$g' - remove?" $true)) {
            net localgroup "$g" "$m" /delete | Out-Null
            if ($LASTEXITCODE -eq 0) { Ok "Removed $m from $g" } else { Warn "Could not remove $m from $g" }
        }
    }
    foreach ($m in $want) {
        if ($m -notin $have -and (Ask "'$m' is missing from '$g' - add?" $true)) {
            net localgroup "$g" "$m" /add | Out-Null
            if ($LASTEXITCODE -eq 0) { Ok "Added $m to $g" } else { Warn "Could not add $m to $g" }
        }
    }
}

# ==============================================================================
# 1. Users
# ==============================================================================
function Invoke-UserAudit($admins, $users) {
    if ($IsDC) { Warn 'Domain controller: manage users with Active Directory Users and Computers (dsa.msc).'; return }
    Head 'Current local users'
    Get-LocalUser | Format-Table Name, Enabled, PasswordRequired, PasswordExpires, LastLogon, Description -AutoSize | Out-String -Width 220 | Write-Host
    Info "Administrators: $((Get-GroupMembers $AdminGrp) -join ', ')"

    Info "You are '$env:USERNAME' - you are always kept."
    if ($admins) { Info "README admins: $($admins -join ', ')" } else { $admins = Read-List 'Authorized ADMINISTRATORS from README' }
    if ($users)  { Info "README users:  $($users -join ', ')" }  else { $users  = Read-List 'Authorized standard USERS from README' }
    $all    = @($admins + $users + $env:USERNAME) | Sort-Object -Unique
    $builtin = Get-LocalUser | Where-Object { $_.SID.Value -match '-(500|501|503|504)$' }  # Administrator, Guest, DefaultAccount, WDAG

    Head 'Unauthorized users'
    foreach ($u in Get-LocalUser) {
        if ($u.Name -in $all -or $u.Name -in $builtin.Name) { continue }
        $act = if ($Auto) { if (CanDestroy "delete unauthorized user $($u.Name)") { 'd' } else { '' } } else { Read-Host "  Unauthorized user '$($u.Name)' - [d]elete / dis[a]ble / Enter = skip" }
        switch -Regex ($act) {
            '^d' { Remove-LocalUser -Name $u.Name; Ok "Removed unauthorized user $($u.Name)" }
            '^a' { Disable-LocalUser -Name $u.Name; Ok "Disabled unauthorized user $($u.Name)" }
        }
    }

    Head 'Missing users'
    $pw = $null
    foreach ($n in $all) {
        if (Get-LocalUser -Name $n -ErrorAction SilentlyContinue) { continue }
        if (Ask "User '$n' is in the README but missing - create?" $true) {
            if (-not $pw) { $pw = Get-NewPassword }
            New-LocalUser -Name $n -Password $pw | Out-Null
            net localgroup "$UsersGrp" "$n" /add | Out-Null
            Ok "Created user account $n"
        }
    }

    Head 'Administrators group'
    Sync-Group $AdminGrp @($admins + $env:USERNAME) @(($builtin | Where-Object { $_.SID.Value -match '-500$' }).Name, 'Domain Admins')

    Head 'Guests group (should only contain Guest)'
    $guest = ($builtin | Where-Object { $_.SID.Value -match '-501$' }).Name
    Sync-Group (Get-LocalGroup -SID 'S-1-5-32-546').Name @($guest)

    Head 'Account settings'
    if (Ask 'Set a secure password + fix flags (expires, required, can change) on all authorized users except you?' ($Cfg.ResetPasswords -ne $false)) {
        if (-not $pw) { $pw = Get-NewPassword }
        foreach ($n in $all | Where-Object { $_ -ne $env:USERNAME }) {
            if (-not (Get-LocalUser -Name $n -ErrorAction SilentlyContinue)) { continue }
            Set-LocalUser -Name $n -Password $pw -PasswordNeverExpires $false -UserMayChangePassword $true
            net user "$n" /passwordreq:yes | Out-Null
            Ok "Secured account $n"
        }
    }
    if (Ask "Tick 'User must change password at next logon' for all authorized users except you?") {
        foreach ($n in $all | Where-Object { $_ -ne $env:USERNAME }) {
            if (-not (Get-LocalUser -Name $n -ErrorAction SilentlyContinue)) { continue }
            net user "$n" /logonpasswordchg:yes | Out-Null
            if ($LASTEXITCODE -eq 0) { Ok "$n must change password at next logon" } else { Warn "$n : could not set (password never expires?)" }
        }
    }
    foreach ($n in $all) {
        $u = Get-LocalUser -Name $n -ErrorAction SilentlyContinue
        if ($u -and -not $u.Enabled -and (Ask "Authorized user '$n' is disabled - enable?" $true)) { Enable-LocalUser $n; Ok "Enabled $n" }
    }
    foreach ($b in $builtin) {
        if ($b.Enabled -and $b.Name -ne $env:USERNAME) { Disable-LocalUser $b.Name; Ok "Disabled built-in account $($b.Name)" }
    }
    # Your own account is never changed automatically (an expired password at the next logon would lock the team out).
    $meUser = Get-LocalUser -Name $env:USERNAME -ErrorAction SilentlyContinue
    if ($meUser -and -not $meUser.PasswordExpires) { Warn "Your own account '$env:USERNAME' has 'Password never expires' ticked. Untick it by hand in lusrmgr.msc once you know its password." }
}

# ==============================================================================
# 2. Groups
# ==============================================================================
function Edit-Groups {
    if ($IsDC) { Warn 'Domain controller: edit groups in dsa.msc.'; return }
    Get-LocalGroup | ForEach-Object {
        $m = Get-GroupMembers $_.Name
        if ($m) { Say ("  {0,-34} {1}" -f $_.Name, ($m -join ', ')) }
    }
    while ($g = Read-Host "`n  Group to edit (e.g. Remote Desktop Users, Enter = back)") {
        if (-not (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)) {
            if (Ask "Group '$g' does not exist - create?") { New-LocalGroup -Name $g | Out-Null; Ok "Created group $g" } else { continue }
        }
        Info "Now: $((Get-GroupMembers $g) -join ', ')"
        Sync-Group $g (Read-List "Exact members the README wants in '$g'")
    }
}

# ==============================================================================
# 3. Password + lockout policy
# ==============================================================================
function Set-PasswordPolicy {
    if ($IsDC) { Warn 'DC: domain policy (gpmc.msc > Default Domain Policy) overrides this. Applying locally anyway.' }
    $p = @{
        MinimumPasswordAge    = 1;  MaximumPasswordAge = 60; MinimumPasswordLength = 12
        PasswordComplexity    = 1;  PasswordHistorySize = 24; ClearTextPassword = 0
        LockoutBadCount       = 5;  LockoutDuration = 30; ResetLockoutCount = 30
        EnableGuestAccount    = 0;  LSAAnonymousNameLookup = 0; ForceLogoffWhenHourExpire = 1
    }
    # Don't lock yourself out if you ARE the built-in Administrator.
    if ($me.Identity.User.Value -notmatch '-500$') { $p.EnableAdminAccount = 0 }
    Set-SecPolicy $p
    net accounts | Write-Host
}

# ==============================================================================
# 16. User rights assignment
# ==============================================================================
function Set-UserRights {
    if ($IsDC) { Warn 'Domain controller: set these in gpmc.msc (Default Domain Controllers Policy) instead.'; return }
    $A = '*S-1-5-32-544'; $U = '*S-1-5-32-545'; $G = '*S-1-5-32-546'; $RDU = '*S-1-5-32-555'
    $LS = '*S-1-5-19'; $NS = '*S-1-5-20'; $SVC = '*S-1-5-6'; $DWM = '*S-1-5-90-0'
    $WDI = '*S-1-5-80-3139157870-2983391045-3678747466-658725712-1809340420'
    Set-SecPolicy -Section 'Privilege Rights' @{
        SeTrustedCredManAccessPrivilege = '';           SeNetworkLogonRight = "$A,$U"
        SeTcbPrivilege = '';                            SeIncreaseQuotaPrivilege = "$A,$LS,$NS"
        SeInteractiveLogonRight = "$A,$U";              SeRemoteInteractiveLogonRight = "$A,$RDU"
        SeBackupPrivilege = $A;                         SeSystemtimePrivilege = "$A,$LS"
        SeTimeZonePrivilege = "$A,$LS,$U";              SeCreatePagefilePrivilege = $A
        SeCreateTokenPrivilege = '';                    SeCreateGlobalPrivilege = "$A,$LS,$NS,$SVC"
        SeCreatePermanentPrivilege = '';                SeCreateSymbolicLinkPrivilege = $A
        SeDebugPrivilege = $A;                          SeDenyNetworkLogonRight = $G
        SeDenyBatchLogonRight = $G;                     SeDenyServiceLogonRight = $G
        SeDenyInteractiveLogonRight = $G;               SeDenyRemoteInteractiveLogonRight = $G
        SeEnableDelegationPrivilege = '';               SeRemoteShutdownPrivilege = $A
        SeAuditPrivilege = "$LS,$NS";                   SeImpersonatePrivilege = "$A,$LS,$NS,$SVC"
        SeIncreaseBasePriorityPrivilege = "$A,$DWM";    SeLoadDriverPrivilege = $A
        SeLockMemoryPrivilege = '';                     SeBatchLogonRight = $A
        SeSecurityPrivilege = $A;                       SeRelabelPrivilege = ''
        SeSystemEnvironmentPrivilege = $A;              SeManageVolumePrivilege = $A
        SeProfileSingleProcessPrivilege = $A;           SeSystemProfilePrivilege = "$A,$WDI"
        SeAssignPrimaryTokenPrivilege = "$LS,$NS";      SeRestorePrivilege = $A
        SeShutdownPrivilege = "$A,$U";                  SeTakeOwnershipPrivilege = $A
    }
    Info 'Check secpol.msc > User Rights Assignment. Remote Desktop Users can still RDP; Everyone was removed from network access.'
}

# ==============================================================================
# 4. Security options (registry)
# ==============================================================================
function Set-SecurityOptions {
    $lsa = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
    $sys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $srv = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
    $wks = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
    $exp = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    $wl  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    @(
        @($lsa, 'LimitBlankPasswordUse', 1, 'Limit local use of blank passwords to console only'),
        @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\CredUI', 'EnumerateAdministrators', 0, 'Enumerate administrator accounts on elevation: disabled'),
        @($lsa, 'RestrictAnonymousSAM', 1, 'Do not allow anonymous enumeration of SAM accounts'),
        @($lsa, 'RestrictAnonymous', 1, 'Do not allow anonymous enumeration of SAM accounts and shares'),
        @($lsa, 'EveryoneIncludesAnonymous', 0, 'Everyone permissions do not apply to anonymous'),
        @($lsa, 'NoLMHash', 1, 'Do not store LAN Manager hash'),
        @($lsa, 'LmCompatibilityLevel', 5, 'NTLMv2 only, refuse LM & NTLM'),
        @($lsa, 'SCENoApplyLegacyAuditPolicy', 1, 'Audit subcategory settings override categories'),
        @($lsa, 'RunAsPPL', 1, 'LSA protection'),
        @('HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest', 'UseLogonCredential', 0, 'WDigest plaintext creds off'),
        @($srv, 'RestrictNullSessAccess', 1, 'Restrict anonymous access to pipes/shares'),
        @($srv, 'RequireSecuritySignature', 1, 'SMB server: always sign'),
        @($srv, 'EnableSecuritySignature', 1, 'SMB server: sign if client agrees'),
        @($srv, 'SMB1', 0, 'SMBv1 server off'),
        @($wks, 'RequireSecuritySignature', 1, 'SMB client: always sign'),
        @($wks, 'EnablePlainTextPassword', 0, 'No unencrypted passwords to SMB servers'),
        @($sys, 'EnableLUA', 1, 'UAC on'),
        @($sys, 'ConsentPromptBehaviorAdmin', 2, 'UAC: prompt admins on secure desktop'),
        @($sys, 'ConsentPromptBehaviorUser', 0, 'UAC: auto-deny elevation for standard users'),
        @($sys, 'PromptOnSecureDesktop', 1, 'UAC: secure desktop'),
        @($sys, 'EnableInstallerDetection', 1, 'UAC: detect installers'),
        @($sys, 'FilterAdministratorToken', 1, 'UAC: admin approval mode for built-in Administrator'),
        @($sys, 'LocalAccountTokenFilterPolicy', 0, 'Remote UAC filtering on'),
        @($sys, 'DontDisplayLastUserName', 1, 'Do not display last signed-in user'),
        @($sys, 'DisableCAD', 0, 'Require CTRL+ALT+DEL'),
        @($sys, 'InactivityTimeoutSecs', 900, 'Machine inactivity limit 15 min'),
        @($exp, 'NoDriveTypeAutoRun', 255, 'AutoPlay off on all drives'),
        @($exp, 'NoAutorun', 1, 'AutoRun off'),
        @($wl, 'AutoAdminLogon', '0', 'Automatic logon off', 'String'),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer', 'AlwaysInstallElevated', 0, 'AlwaysInstallElevated off (HKLM)'),
        @('HKCU:\SOFTWARE\Policies\Microsoft\Windows\Installer', 'AlwaysInstallElevated', 0, 'AlwaysInstallElevated off (HKCU)'),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'EnableSmartScreen', 1, 'SmartScreen on'),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'ShellSmartScreenLevel', 'Warn', 'SmartScreen level: Warn', 'String'),
        # --- Accounts / Devices / Interactive logon
        @($sys, 'NoConnectedUser', 3, "Block Microsoft accounts (can't add or log on)"),
        @($wl, 'AllocateCDRoms', '1', 'CD-ROM access restricted to locally logged-on user', 'String'),
        @($wl, 'AllocateFloppies', '1', 'Floppy access restricted to locally logged-on user', 'String'),
        @($wl, 'AllocateDASD', '2', 'Format/eject removable media: Administrators and Interactive Users', 'String'),
        @($sys, 'UndockWithoutLogon', 0, 'Allow undock without logon: disabled'),
        @('HKLM:\SYSTEM\CurrentControlSet\Control\Print\Providers\LanMan Print Services\Servers', 'AddPrinterDrivers', 1, 'Prevent users from installing printer drivers'),
        @($sys, 'DontDisplayLockedUserId', 3, 'Locked session: do not display user information'),
        @($wl, 'CachedLogonsCount', '4', 'Cached logons: 4', 'String'),
        @($wl, 'PasswordExpiryWarning', 14, 'Prompt to change password 14 days before expiry'),
        @($wl, 'ForceUnlockLogon', 0, 'Require DC authentication to unlock: disabled'),
        @($sys, 'ScForceOption', 0, 'Require smart card: disabled'),
        @($wl, 'ScRemoveOption', '1', 'Smart card removal: lock workstation', 'String'),
        @($sys, 'ShutdownWithoutLogon', 0, 'Shut down without logon: disabled'),
        @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device', 'DevicePasswordLessBuildVersion', 0, 'netplwiz: users must enter a user name and password'),
        # --- Audit
        @($lsa, 'AuditBaseObjects', 0, 'Audit access of global system objects: disabled'),
        # --- Domain member (secure channel)
        @('HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters', 'RequireSignOrSeal', 1, 'Secure channel: encrypt or sign (always)'),
        @('HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters', 'SealSecureChannel', 1, 'Secure channel: encrypt when possible'),
        @('HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters', 'SignSecureChannel', 1, 'Secure channel: sign when possible'),
        @('HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters', 'DisablePasswordChange', 0, 'Machine account password changes: allowed'),
        @('HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters', 'MaximumPasswordAge', 30, 'Machine account password age: 30 days'),
        @('HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters', 'RequireStrongKey', 1, 'Require strong session key'),
        # --- Microsoft network client / server
        @($wks, 'EnableSecuritySignature', 1, 'SMB client: sign if server agrees'),
        @($srv, 'AutoDisconnect', 15, 'SMB server idle disconnect: 15 min'),
        @($srv, 'EnableForcedLogOff', 1, 'SMB server: disconnect when logon hours expire'),
        @($srv, 'SmbServerNameHardeningLevel', 1, 'SMB server SPN validation: accept if provided by client'),
        # --- Network access
        @($lsa, 'DisableDomainCreds', 1, 'Do not store passwords/credentials for network authentication'),
        @($srv, 'NullSessionPipes', [string[]]@(), 'Anonymous named pipes: none', 'MultiString'),
        @($srv, 'NullSessionShares', [string[]]@(), 'Anonymous shares: none', 'MultiString'),
        @('HKLM:\SYSTEM\CurrentControlSet\Control\SecurePipeServers\Winreg\AllowedExactPaths', 'Machine', [string[]]@(), 'Remotely accessible registry paths: none', 'MultiString'),
        @('HKLM:\SYSTEM\CurrentControlSet\Control\SecurePipeServers\Winreg\AllowedPaths', 'Machine', [string[]]@(), 'Remotely accessible registry paths and sub-paths: none', 'MultiString'),
        @($lsa, 'ForceGuest', 0, 'Sharing model: Classic'),
        # --- Network security
        @($lsa, 'UseMachineId', 1, 'LocalSystem uses computer identity for NTLM'),
        @("$lsa\MSV1_0", 'allownullsessionfallback', 0, 'LocalSystem NULL session fallback: disabled'),
        @("$lsa\pku2u", 'AllowOnlineID', 0, 'PKU2U online identities: disabled'),
        @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters', 'SupportedEncryptionTypes', 2147483644, 'Kerberos: RC4, AES128, AES256, future types'),
        @('HKLM:\SYSTEM\CurrentControlSet\Services\LDAP', 'LDAPClientIntegrity', 1, 'LDAP client signing: negotiate'),
        @("$lsa\MSV1_0", 'NTLMMinClientSec', 537395200, 'NTLM SSP clients: require NTLMv2 + 128-bit'),
        @("$lsa\MSV1_0", 'NTLMMinServerSec', 537395200, 'NTLM SSP servers: require NTLMv2 + 128-bit'),
        # --- Recovery console / shutdown / system
        @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole', 'SecurityLevel', 0, 'Recovery console auto admin logon: disabled'),
        @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole', 'SetCommand', 0, 'Recovery console floppy/all drives: disabled'),
        @('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management', 'ClearPageFileAtShutdown', 0, 'Clear pagefile at shutdown: disabled'),
        @("$lsa\FIPSAlgorithmPolicy", 'Enabled', 0, 'FIPS algorithms: disabled'),
        @('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Kernel', 'ObCaseInsensitive', 1, 'Case insensitivity for non-Windows subsystems'),
        @('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager', 'ProtectionMode', 1, 'Strengthen default permissions of system objects'),
        @('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\SubSystems', 'Optional', [string[]]@(), 'Optional subsystems: none', 'MultiString'),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers', 'AuthenticodeEnabled', 0, 'Certificate rules for SRP: disabled'),
        # --- UAC (rest)
        @($sys, 'EnableUIADesktopToggle', 0, 'UAC: UIAccess apps cannot skip secure desktop'),
        @($sys, 'ValidateAdminCodeSignatures', 0, 'UAC: only elevate signed executables: disabled'),
        @($sys, 'EnableSecureUIAPaths', 1, 'UAC: UIAccess only from secure locations'),
        @($sys, 'EnableVirtualization', 1, 'UAC: virtualize file/registry write failures'),
        # --- Misc checklist items
        @('HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config', 'AutoConnectAllowedOEM', 0, 'Wi-Fi Sense: no auto-connect to suggested hotspots'),
        @('HKLM:\SOFTWARE\Microsoft\DirectplayNATHelp\DPNHUPnP', 'UPnPMode', 2, 'UPnP port 1900 disabled (UPnPMode=2)'),
        @('HKLM:\SOFTWARE\Policies\Google\Chrome', 'DefaultPopupsSetting', 2, 'Chrome pop-up blocker on'),
        @('HKLM:\SOFTWARE\Policies\Google\Chrome', 'SafeBrowsingProtectionLevel', 1, 'Chrome Safe Browsing on'),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'DefaultPopupsSetting', 2, 'Edge pop-up blocker on'),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'SmartScreenEnabled', 1, 'Edge SmartScreen on'),
        @('HKLM:\SOFTWARE\Policies\Mozilla\Firefox\PopupBlocking', 'Default', 1, 'Firefox pop-up blocker on')
    ) | ForEach-Object { Set-Reg @_ }

    if ((Get-ItemProperty $wl -ErrorAction SilentlyContinue).DefaultPassword) {
        Remove-ItemProperty $wl -Name DefaultPassword; Ok 'Removed plaintext autologon password (Winlogon\DefaultPassword)'
    }
    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue

    # Screen saver: 10 min + password on resume, for every loaded user profile.
    Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' } | ForEach-Object {
        $k = "Registry::$($_.Name)\Software\Policies\Microsoft\Windows\Control Panel\Desktop"
        if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
        @{ ScreenSaveActive = '1'; ScreenSaverIsSecure = '1'; ScreenSaveTimeOut = '600' }.GetEnumerator() |
            ForEach-Object { New-ItemProperty $k -Name $_.Key -Value $_.Value -PropertyType String -Force | Out-Null }
    }
    Ok 'Screen saver: 10 min, show logon screen on resume (logged-in users)'

    if (Ask 'Disable OneDrive (only if the README does not need it)?' ($Cfg.DisableOneDrive -ne $false)) {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' DisableFileSyncNGSC 1 'OneDrive disabled'
        Get-ChildItem Registry::HKEY_USERS | ForEach-Object {
            Remove-ItemProperty "Registry::$($_.Name)\Software\Microsoft\Windows\CurrentVersion\Run" -Name OneDrive -ErrorAction SilentlyContinue }
        Ok 'OneDrive removed from startup'
    }
    if (Ask 'Disable SMB compression (ONLY if the README mentions it)?') {
        Set-Reg $srv DisableCompression 1 'SMB compression disabled'
    }
    Info 'Some options apply after reboot / re-login.'
}

# ==============================================================================
# 5. Firewall, Defender, auditing
# ==============================================================================
function Set-Protection {
    sc.exe config MpsSvc start= auto | Out-Null; Start-Service MpsSvc -ErrorAction SilentlyContinue
    Set-NetFirewallProfile -All -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Allow -NotifyOnListen True -LogBlocked True
    Ok 'Firewall protection has been enabled (all profiles)'

    Head 'Inbound firewall rules for consumer apps (Edge, Search, MSN, Photos, Xbox)'
    Select-Items (Get-NetFirewallRule -Direction Inbound -Enabled True | Where-Object { $_.DisplayName -match 'Microsoft Edge|Search|MSN|Money|Sports|News|Weather|Photos|Xbox' }) { $_.DisplayName } { $true } |
        ForEach-Object { Disable-NetFirewallRule -Name $_.Name; Ok "Disabled inbound rule $($_.DisplayName)" }

    Head 'Inbound rules left by removed or prohibited programs'
    Remove-StaleFirewallRules

    Head 'Microsoft Defender'
    if ($OS.ProductType -ne 1 -and (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue)) {
        $f = Get-WindowsFeature Windows-Defender -ErrorAction SilentlyContinue
        if ($f -and -not $f.Installed -and (Ask 'Microsoft Defender Antivirus is not installed - install it (needs a restart)?' $true)) {
            Install-WindowsFeature Windows-Defender | Out-Null
            Ok 'Installed Microsoft Defender Antivirus - reboot, then run option 5 again'
        }
    }
    Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Name DisableAntiSpyware, DisableAntiVirus -ErrorAction SilentlyContinue
    Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' -Name DisableRealtimeMonitoring, DisableBehaviorMonitoring, DisableOnAccessProtection, DisableIOAVProtection -ErrorAction SilentlyContinue
    Remove-DefenderPolicyExclusions
    if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
        Set-MpPreference -DisableRealtimeMonitoring $false -DisableBehaviorMonitoring $false -DisableIOAVProtection $false `
            -DisableScriptScanning $false -PUAProtection Enabled -MAPSReporting Advanced -ErrorAction SilentlyContinue
        Ok 'Defender real-time / behavior / PUA protection on'
        $p = Get-MpPreference
        $ex = foreach ($t in 'Path', 'Process', 'Extension') { foreach ($v in $p."Exclusion$t") { if ($v) { [pscustomobject]@{ Type = $t; Value = $v } } } }
        # The scoring engine lives in C:\CyberPatriot - removing its exclusion can break the image.
        $ex | Where-Object { $_.Value -match 'CyberPatriot' } | ForEach-Object { Say "  [=] Keeping exclusion $($_.Value) (scoring engine)" DarkGreen }
        Head 'Defender exclusions to remove'
        Select-Items ($ex | Where-Object { $_.Value -notmatch 'CyberPatriot' }) { "$($_.Type): $($_.Value)" } { $true } | ForEach-Object {
            $h = @{ "Exclusion$($_.Type)" = $_.Value }; Remove-MpPreference @h; Ok "Removed Defender exclusion $($_.Value)"
        }
        if ($Auto) {
            Start-InNewWindow 'Defender update + scan' 'Update-MpSignature; Start-MpScan -ScanType QuickScan; Get-MpThreat | ForEach-Object { Warn "Threat: $($_.ThreatName)" }; Remove-MpThreat -ErrorAction SilentlyContinue; Ok "Defender scan done"'
        } else { Info 'Updating Defender signatures...'; Update-MpSignature -ErrorAction SilentlyContinue }
        if (-not $Auto -and (Ask 'Run a Defender quick scan now?')) {
            Start-MpScan -ScanType QuickScan; Ok 'Quick scan done'
            $threats = Get-MpThreat -ErrorAction SilentlyContinue
            if ($threats) {
                $threats | ForEach-Object { Warn "Threat: $($_.ThreatName)" }
                if (Ask 'Quarantine/remove these threats?') { Remove-MpThreat; Ok 'Detected threats removed' }
            } else { Say '  [=] No threats found' DarkGreen }
        }
    } else { Warn 'Defender cmdlets not present (Defender removed?).' }

    auditpol /set /category:* /success:enable /failure:enable | Out-Null
    Ok 'Auditing: success + failure for all categories'
}

# ==============================================================================
# 6. Remote access
# ==============================================================================
function Set-RemoteAccess($Rdp) {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' fAllowToGetHelp 0 'Remote Assistance connections disabled'
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' fAllowFullControl 0 'Remote Assistance control disabled'

    $ts = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $rdpRules = '@FirewallAPI.dll,-28752'   # "Remote Desktop" rule group, language independent
    $tsp = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    if (-not $Rdp) { $Rdp = Read-Host '  Is Remote Desktop REQUIRED by the README? (y/n/Enter = leave as is)' }
    switch -Regex ($Rdp) {
        '^(y|req)' {
            Set-Reg $ts fDenyTSConnections 0 'Remote Desktop enabled'
            Set-Reg $tsp fDenyTSConnections 0 'Policy no longer blocks Remote Desktop'
            Enable-NetFirewallRule -Group $rdpRules -ErrorAction SilentlyContinue
            sc.exe config TermService start= auto | Out-Null; Start-Service TermService -ErrorAction SilentlyContinue
            Info "Use menu 2 to set 'Remote Desktop Users' to exactly who the README lists."
        }
        '^(n|off)' {
            Set-Reg $ts fDenyTSConnections 1 'Remote Desktop disabled'
            Disable-NetFirewallRule -Group $rdpRules -ErrorAction SilentlyContinue
            if (Ask 'Also stop & disable the Remote Desktop service (TermService)?') {
                Stop-Service TermService -Force -ErrorAction SilentlyContinue; sc.exe config TermService start= disabled | Out-Null; Ok 'TermService disabled'
            }
        }
    }
    Set-Reg $tsp fEncryptRPCTraffic 1 'RDP policy: require secure RPC communication'
    Set-Reg $tsp SecurityLayer 2 'RDP policy: security layer SSL'
    Set-Reg $tsp UserAuthentication 1 'RDP policy: require NLA'
    Set-Reg $tsp MinEncryptionLevel 3 'RDP policy: high encryption'
    Set-Reg $tsp fAllowToGetHelp 0 'Policy: Remote Assistance off'
    $rdp = "$ts\WinStations\RDP-Tcp"
    Set-Reg $rdp UserAuthentication 1 'RDP network level authentication enabled'
    Set-Reg $rdp SecurityLayer 2 'RDP security layer: TLS'
    Set-Reg $rdp MinEncryptionLevel 3 'RDP encryption: high'
}

# ==============================================================================
# 7. Services
# ==============================================================================
$BadServices = [ordered]@{
    ftpsvc = 'FTP'; TlntSvr = 'Telnet'; sshd = 'OpenSSH Server'; SNMP = 'SNMP'; SNMPTRAP = 'SNMP Trap'
    RemoteRegistry = 'Remote Registry'; SSDPSRV = 'SSDP Discovery'; upnphost = 'UPnP Device Host'
    SharedAccess = 'Internet Connection Sharing'; RemoteAccess = 'Routing and Remote Access'; RasAuto = 'RAS Auto Connection'
    simptcp = 'Simple TCP/IP'; W3SVC = 'IIS Web Server'; WMSvc = 'IIS Web Management'; SMTPSVC = 'SMTP'
    WinRM = 'Windows Remote Management'; WebClient = 'WebDAV Client'; Spooler = 'Print Spooler'; Fax = 'Fax'
    icssvc = 'Mobile Hotspot'; lfsvc = 'Geolocation'; MapsBroker = 'Maps Manager'; NetTcpPortSharing = 'Net.Tcp Port Sharing'
    XblAuthManager = 'Xbox Auth'; XblGameSave = 'Xbox Game Save'; XboxNetApiSvc = 'Xbox Networking'; XboxGipSvc = 'Xbox Accessories'
    DNS = 'DNS Server (keep on a domain controller!)'; mnmsrvc = 'NetMeeting Remote Desktop Sharing'; RDSessMgr = 'Remote Desktop Help Session Manager'
}
$GoodServices = 'WinDefend', 'MpsSvc', 'BFE', 'EventLog', 'Wecsvc', 'wscsvc', 'Dnscache'

function Set-Services {
    Info 'Keep anything the README says is a critical service!'
    foreach ($name in $BadServices.Keys) {
        $s = Get-Service $name -ErrorAction SilentlyContinue
        if (-not $s) { continue }
        $label = $BadServices[$name]
        if ($s.Status -eq 'Stopped' -and $s.StartType -eq 'Disabled') { Say "  [=] $label already disabled" DarkGray; continue }
        if (Ask "$label ($name) is $($s.Status)/$($s.StartType) - stop & disable?" $true) {
            Stop-Service $name -Force -ErrorAction SilentlyContinue
            sc.exe config $name start= disabled | Out-Null
            if ($LASTEXITCODE -eq 0) { Ok "$label service has been stopped and disabled" } else { Warn "Could not disable $name" }
        }
    }
    Head 'Remote management / polling agents (README: company uses none)'
    Select-Items (Get-CimInstance Win32_Service | Where-Object { "$($_.Name) $($_.DisplayName) $($_.PathName)" -match $RmmPattern }) { "$($_.Name)  ($($_.DisplayName))  $($_.State)" } { $true } |
        ForEach-Object {
            Stop-Service $_.Name -Force -ErrorAction SilentlyContinue; sc.exe config $_.Name start= disabled | Out-Null
            Ok "$($_.DisplayName) service has been stopped and disabled - uninstall it in menu 8"
        }
    Head 'Required services'
    foreach ($name in $GoodServices) {
        $s = Get-Service $name -ErrorAction SilentlyContinue
        if (-not $s) { continue }
        if ($s.StartType -ne 'Automatic') { sc.exe config $name start= auto | Out-Null }   # protected ones (WinDefend) just refuse
        if ($s.Status -ne 'Running') { Start-Service $name -ErrorAction SilentlyContinue }
        $s.Refresh()
        if ($s.Status -eq 'Running') { Say "  [=] $name running" DarkGreen } else { Warn "$name is $($s.Status) - check manually" }
    }
    Head 'Non-Windows services (look for backdoors / unknown names)'
    Get-CimInstance Win32_Service |
        Where-Object { $_.PathName -and $_.PathName -notmatch '\\Windows\\(system32|SysWOW64|Microsoft\.NET|servicing)\\|Windows Defender' } |
        Format-Table Name, State, StartMode, PathName -AutoSize | Out-String -Width 220 | Write-Host
}

# ==============================================================================
# 8. Software
# ==============================================================================
$BadSoftware = 'wireshark|npcap|winpcap|ccleaner|nmap|zenmap|\bcain\b|john the ripper|hashcat|ophcrack|l0phtcrack|metasploit|' +
    'angry ip|advanced ip scanner|netstumbler|nessus|burp|hydra|netcat|ncat|aircrack|cheat engine|mimikatz|' +
    'utorrent|bittorrent|qbittorrent|vuze|frostwire|limewire|shareaza|deluge|tor browser|' +
    'teamviewer|anydesk|tightvnc|realvnc|ultravnc|ammyy|radmin|remote utilities|' +
    'advanced systemcare|driver booster|pc cleaner|steam|epic games|minecraft|roblox|wildtangent|windirstat'
# Centralized maintenance / polling (RMM, monitoring) tools - every README says the company uses none.
$RmmPattern = 'kaseya|connectwise|screenconnect|labtech|\bltsvc\b|n-able|n-central|solarwinds|ninjarmm|ninjaone|\batera|datto|logmein|' +
    'splashtop|\bpdq|zabbix|nagios|nsclient|\bncpa\b|\bprtg|lansweeper|manageengine|desktop central|puppet|chef-client|chef client|' +
    'salt-minion|salt minion|tactical ?rmm|meshagent|mesh agent|rustdesk|dameware|bomgar|beyondtrust|pulseway|syncro|action1|' +
    'gotoassist|goto resolve|chrome remote desktop|nomachine|remotepc|supremo|zoho assist|ocs ?inventory|glpi'
$BadSoftware += "|$RmmPattern"
# Seen on the Round 2 images but never "installed": HFS (portable web file server), SharpHound, a planted Minesweeper.
$BadSoftware += '|\bhfs\b|http file server|sharphound|bloodhound|powersploit|minesweeper|pinball'
function Test-RemoveListed($Name) {
    foreach ($r in @($Cfg.RemoveSoftware)) { if ($r -and "$Name" -like "*$r*") { return $true } }
    $false
}

function Get-Installed {
    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'Registry::HKEY_USERS\*\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.UninstallString -and -not $_.SystemComponent } |
        Sort-Object DisplayName -Unique
}

function Remove-BadSoftware {
    $all = Get-Installed
    Head "All installed programs ($(@($all).Count)) - compare with README"
    $all | ForEach-Object { Say ("  {0,-55} {1,-18} {2}" -f $_.DisplayName, $_.DisplayVersion, $_.Publisher) DarkGray }

    Head 'Flagged programs (hacking / P2P / remote / cleaners / games)'
    # Anything the README requires (RequiredApps in the config) is never offered, whatever it is called.
    $all | Where-Object { $_.DisplayName -match $BadSoftware -and (Test-Required $_.DisplayName) } | ForEach-Object { Say "  [=] Keeping $($_.DisplayName) (required by the README)" DarkGreen }
    Select-Items ($all | Where-Object { ($_.DisplayName -match $BadSoftware -or (Test-RemoveListed $_.DisplayName)) -and -not (Test-Required $_.DisplayName) }) { "$($_.DisplayName) $($_.DisplayVersion)" } { CanDestroy } | ForEach-Object { Uninstall-App $_ }

    if (Ask 'Uninstall something else from the full list?') {
        Select-Items $all { "$($_.DisplayName) $($_.DisplayVersion)" } | ForEach-Object { Uninstall-App $_ }
    }
    Head 'Program folders that are not installed programs (portable tools, planted games)'
    Find-UnknownPrograms
    Head 'Older copies of updated programs'
    Remove-OldVersions
    Head 'Firewall rules left behind'
    Remove-StaleFirewallRules
    Info 'Also check Settings > Apps for Store apps.'
}

function Uninstall-App($p) {
    $cmd = if ($p.QuietUninstallString) { $p.QuietUninstallString } else { $p.UninstallString }
    $msi = $cmd -match 'msiexec'
    if ($msi) { $cmd = ($cmd -replace '/I', '/X') + ' /qb /norestart' }
    elseif ($Auto -and -not $p.QuietUninstallString) {   # silent switches: Inno Setup, then NSIS (Wireshark, Npcap, ...)
        if ($cmd -match 'unins\d+\.exe') { $cmd += ' /VERYSILENT /SUPPRESSMSGBOXES /NORESTART' } elseif ($cmd -match 'uninst[^\\]*\.exe') { $cmd += ' /S' }
    }
    Info "Running: $cmd  (finish any uninstaller window that opens)"
    if ($Auto -and -not $msi) {   # GUI uninstallers would block the run - leave their windows open and move on
        Start-Process cmd.exe "/c `"$cmd`""; Ok "Started uninstaller for $($p.DisplayName) - click through its window"
    } else { Start-Process cmd.exe "/c `"$cmd`"" -Wait; Ok "Ran uninstaller for $($p.DisplayName)" }
}

# ==============================================================================
# 9. Prohibited files
# ==============================================================================
$MediaExt   = 'mp3', 'mp4', 'm4a', 'm4v', 'wav', 'wma', 'wmv', 'flac', 'aac', 'ogg', 'avi', 'mkv', 'mov', 'flv', 'webm', 'mpg', 'mpeg', '3gp', 'aiff'
$ImageExt   = 'jpg', 'jpeg', 'png', 'gif', 'bmp', 'heic', 'tif', 'tiff'
$SuspectExt = 'exe', 'msi', 'bat', 'cmd', 'ps1', 'vbs', 'zip', '7z', 'rar', 'iso', 'torrent', 'pcap', 'pcapng', 'kdbx'
$SuspectName = 'pass(word|wd)?s?|cred|secret|hack|crack|keygen|backdoor|payload|mimikatz|netcat|nc64|exploit|shell|sharphound|bloodhound|rubeus|lazagne|powersploit|pwdump|fgdump|psexec|winpeas|kerbrute'

# Auto mode deletes media + files named like hacking tools (never inside AppData); everything else is only listed.
$ToolFilePattern = 'nmap|wireshark|netcat|\bnc(64)?\b|ncat|mimikatz|hashcat|john|ophcrack|\bcain\b|hydra|aircrack|metasploit|burp|nessus|keygen|crack|backdoor|payload|exploit|\.torrent$' +
    '|sharphound|bloodhound|rubeus|lazagne|powersploit|pwdump|fgdump|psexec|\bhfs\b|winpeas|seatbelt|kerbrute|chisel|ngrok'

# Whole system drive except Windows and the program folders (those are covered by the unknown-program check).
# The first version only looked in C:\Users, which is why C:\HFS and files in C:\inetpub went unseen.
function Get-ScanRoots {
    if (@($Cfg.ScanRoots).Count) { return @($Cfg.ScanRoots) }
    @(Get-ChildItem -LiteralPath "$env:SystemDrive\" -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '^(Windows|Windows\.old|Program Files|Program Files \(x86\)|ProgramData|\$.*|System Volume Information|Recovery|PerfLogs|Config\.Msi|Documents and Settings|cp-quarantine|CyberPatriot.*)$' } |
        ForEach-Object { $_.FullName })
}
# README shares, KeepPaths and the scoring engine: listed, never auto-deleted.
function Test-KeptPath($Path) {
    if ("$Path" -match 'CyberPatriot|\\cp-quarantine\\') { return $true }
    foreach ($k in @($Cfg.KeepPaths) + @($Cfg.Shares | ForEach-Object { $_.Path })) {
        if ($k -and "$Path".StartsWith("$k".TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    $false
}
function Find-BadFiles([string[]]$Roots) {
    if (-not $Roots) { $r = if (-not $Auto) { Read-Host '  Folder to scan [Enter = whole drive except Windows and Program Files]' }; $Roots = if ($r) { $r } else { Get-ScanRoots } }
    Info "Scanning: $($Roots -join ', ')"
    $root = $Roots
    $images = Ask 'Include images (jpg/png/...)?'
    Info 'Scanning...'
    $hits = Get-ChildItem $root -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\AppData\\Local\\(Microsoft|Packages|Temp\\.+\.tmp)|\\WinSxS\\|\\cp-quarantine\\|CyberPatriot|\\cp-log-|CyberPatriot-Toolkit|CP-Run\.ps1' } |
        ForEach-Object {
            $e = $_.Extension.TrimStart('.').ToLower()
            $why = if ($e -in $MediaExt) { 'media' } elseif ($images -and $e -in $ImageExt) { 'image' }
                   elseif ($_.BaseName -match $SuspectName) { 'name' } elseif ($e -in $SuspectExt) { 'type' }
            if ($why) { [pscustomobject]@{ Why = $why; File = $_ } }
        } | Sort-Object Why
    Info 'Answer forensics questions BEFORE deleting anything they might ask about.'
    Select-Items $hits { "[{0,-5}] {1}  ({2:N0} KB)" -f $_.Why, $_.File.FullName, ($_.File.Length / 1KB) } {
        (CanDestroy) -and $_.File.FullName -notmatch '\\AppData\\' -and -not (Test-KeptPath $_.File.FullName) -and ($_.Why -eq 'media' -or $_.File.Name -match $ToolFilePattern) } | ForEach-Object {
        Remove-Item -LiteralPath $_.File.FullName -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $_.File.FullName) { Warn "Could not delete $($_.File.FullName)" } else { Ok "Deleted $($_.File.FullName)" }
    }
    # In auto mode the files that were only listed go into the error report, so a person reads them.
    if ($Auto) { $hits | Where-Object { $_.Why -ne 'image' -and (Test-Path -LiteralPath $_.File.FullName) -and $_.File.FullName -notmatch '\\AppData\\' } | Select-Object -First 60 | ForEach-Object { Warn "Left in place, check it: [$($_.Why)] $($_.File.FullName)" } }
    foreach ($f in @($Cfg.RemoveFiles)) {
        if (-not $f -or -not (Test-Path -LiteralPath $f)) { continue }
        if (Test-KeptPath $f) { Warn "RemoveFiles: $f is under a kept path - not removed"; continue }
        if (CanDestroy "remove $f") { Move-ToQuarantine $f }
    }
}

# ==============================================================================
# 10. Review: shares, startup, tasks, backdoors, hosts, ports
# ==============================================================================
$KeepShares = '^([A-Z]\$|ADMIN\$|IPC\$|print\$|NETLOGON|SYSVOL)$'
# Auto mode removes autoruns / tasks that look like backdoors or run from outside Windows / Program Files.
$SuspectCmd = 'nc(64)?\.exe|ncat|netcat|socat|\s-e\s+\S*(cmd|powershell)(\.exe)?\b|\s-l\S*\s+(-p\s*)?\d{2,5}\b|' +   # netcat-style args, even when renamed
    'powershell.*(\s-e(nc|ncodedcommand)?\s|-w(indowstyle)?\s+h|downloadstring|invoke-expression|\biex\b)|' +
    'mshta|wscript|cscript|bitsadmin|certutil|regsvr32|rundll32.*(http|javascript)|\\Users\\Public\\|\\Temp\\|\.(bat|vbs|ps1|cmd)\b'
$TrustedExe = '^"?(%(windir|SystemRoot|ProgramFiles(\(x86\))?)%|C:\\Windows\\|C:\\Program Files)'
# Moves a file to C:\cp-quarantine (removed from where it was, but recoverable).
function Move-ToQuarantine($Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    New-Item 'C:\cp-quarantine' -ItemType Directory -Force | Out-Null
    $dest = Join-Path 'C:\cp-quarantine' ($Path -replace '[:\\]', '_')
    try { Move-Item -LiteralPath $Path $dest -Force -ErrorAction Stop; Ok "Removed $Path (moved to $dest)" } catch { Warn "Could not remove $Path : $($_.Exception.Message)" }
}
function Test-Suspect($exe, $cmdline) { ("$exe $cmdline" -match $SuspectCmd) -or ($exe -and $exe -notmatch $TrustedExe) }
function Invoke-Review {
    Head 'Non-default SMB shares'
    Select-Items (Get-SmbShare | Where-Object { $_.Name -notmatch $KeepShares }) { "$($_.Name) -> $($_.Path)" } { $true } |
        ForEach-Object { Remove-SmbShare -Name $_.Name -Force; Ok "Removed share $($_.Name)" }

    # !! = netcat by name, or an UNSIGNED program running from C:\Windows (renamed netcat, e.g. System32\mfc.exe).
    Head 'Processes: backdoors (!!) and everything outside C:\Windows'
    $nc = '^(nc|nc64|ncat|netcat|socat)$'; $sig = @{}
    $procs = Get-Process | Where-Object { ($_.Path -and $_.Path -notmatch '\\Windows Defender\\|CyberPatriot') -or $_.ProcessName -match $nc } | ForEach-Object {
        $bad = $_.ProcessName -match $nc
        if (-not $bad -and $_.Path -match '^C:\\Windows\\') {
            if (-not $sig.ContainsKey($_.Path)) { $sig[$_.Path] = "$((Get-AuthenticodeSignature -LiteralPath $_.Path -ErrorAction SilentlyContinue).Status)" }
            if ($sig[$_.Path] -eq 'Valid') { return }   # signed Windows binary
            $bad = $true
        }
        $_ | Add-Member NoteProperty Bad $bad -PassThru
    } | Sort-Object ProcessName
    Select-Items $procs { "{0}{1,-28} pid {2,-6} {3}" -f $(if ($_.Bad) { '!! ' } else { '' }), $_.ProcessName, $_.Id, $_.Path } { $_.Bad -and (CanDestroy) } |
        ForEach-Object {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue; Ok "Killed process $($_.ProcessName) ($($_.Id))"
            if ($_.Bad -and $_.Path) { Start-Sleep -Milliseconds 300; Move-ToQuarantine $_.Path }
        }

    Head 'Run / RunOnce registry entries'
    $runKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
               'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
               'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    $run = foreach ($k in $runKeys) {
        $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
        if ($p) { $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { [pscustomobject]@{ Key = $k; Name = $_.Name; Cmd = $_.Value } } }
    }
    Select-Items $run { "$($_.Name) = $($_.Cmd)" } { (CanDestroy) -and (Test-Suspect "$($_.Cmd)" '') } | ForEach-Object { Remove-ItemProperty $_.Key -Name $_.Name; Ok "Removed autorun $($_.Name)" }

    Head 'Startup folders'
    Select-Items (Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\*", 'C:\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\*' -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'desktop.ini' }) { $_.FullName } { CanDestroy } | ForEach-Object { Move-ToQuarantine $_.FullName }

    Head 'Scheduled tasks outside \Microsoft\'
    Select-Items (Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' }) {
        "{0}{1}  ->  {2} {3}" -f $_.TaskPath, $_.TaskName, ($_.Actions.Execute -join ';'), ($_.Actions.Arguments -join ';')
    } { (CanDestroy) -and "$($_.TaskPath)$($_.TaskName) $($_.Actions.Execute)" -notmatch 'CyberPatriot' -and (Test-Suspect ($_.Actions.Execute -join ';') ($_.Actions.Arguments -join ';')) } | ForEach-Object {
        $_ | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue   # piping the object works for root-folder tasks too
        if (Get-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue) { Warn "Could not delete scheduled task $($_.TaskPath)$($_.TaskName)" } else { Ok "Deleted scheduled task $($_.TaskPath)$($_.TaskName)" }
    }

    Head 'Image File Execution Options debuggers (sticky-keys style backdoors)'
    $ifeo = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options' -ErrorAction SilentlyContinue |
        ForEach-Object { $d = (Get-ItemProperty $_.PSPath).Debugger; if ($d) { [pscustomobject]@{ Path = $_.PSPath; Exe = $_.PSChildName; Debugger = $d } } }
    Select-Items $ifeo { "$($_.Exe) -> $($_.Debugger)" } { $true } | ForEach-Object { Remove-ItemProperty $_.Path -Name Debugger; Ok "Removed IFEO debugger on $($_.Exe)" }
    foreach ($exe in 'sethc', 'utilman', 'osk', 'Magnify', 'Narrator', 'DisplaySwitch') {
        $f = Get-Item "$env:windir\System32\$exe.exe" -ErrorAction SilentlyContinue
        # Real attack = a shell copied over the accessibility tool. (Magnify/Narrator are ScreenMagnifier/SR internally - fine.)
        if ($f -and $f.VersionInfo.OriginalFilename -match '^(cmd|powershell|pwsh|explorer|taskmgr|conhost|mmc)\.exe') { Warn "$exe.exe is really $($f.VersionInfo.OriginalFilename) (accessibility backdoor) - restore with: sfc /scannow" }
    }

    Head 'hosts file'
    $hosts = "$env:windir\System32\drivers\etc\hosts"
    $active = Get-Content $hosts | Where-Object { $_ -match '^\s*[^#\s]' }
    if (-not $active) { Say '  [=] hosts file clean' DarkGreen }
    else {
        $active | ForEach-Object { Warn "hosts: $_" }
        if (Ask 'Reset hosts file to default?' $true) {
            (Get-Item $hosts).Attributes = 'Normal'
            Set-Content $hosts '# localhost name resolution is handled within DNS itself.' -Encoding ASCII
            ipconfig /flushdns | Out-Null; Ok 'hosts file reset'
        }
    }

    Head 'Renamed tools in the Windows folders (netcat under another name)'
    Find-RenamedTools

    Head 'Listening TCP ports -> program, file, signature (3 snapshots)'
    Show-Listeners
}

# ==============================================================================
# 11. Windows features
# ==============================================================================
$BadFeatures = 'SMB1Protocol', 'SMB1Protocol-Client', 'SMB1Protocol-Server', 'TelnetClient', 'TFTP', 'SimpleTCP',
               'MicrosoftWindowsPowerShellV2Root', 'MicrosoftWindowsPowerShellV2', 'Internet-Explorer-Optional-amd64',
               'IIS-WebServerRole', 'IIS-WebServer', 'IIS-FTPServer', 'IIS-FTPSvc', 'WorkFolders-Client', 'Printing-Foundation-LPDPrintService',
               'TelnetServer', 'SNMP', 'WMISnmpProvider', 'RasRip', 'ServicesForNFS-ClientOnly', 'ClientForNFS-Infrastructure', 'NFS-Administration'

# Runs Disable-BadFeatures in its own window, with this session's (possibly README-edited) feature list.
function Start-FeatureRemoval { Start-InNewWindow 'Windows features' "`$BadFeatures = $(ConvertTo-PSList $BadFeatures); Disable-BadFeatures" }

function Disable-BadFeatures {
    Info 'Reading optional features (takes a moment)...'
    $on = Get-WindowsOptionalFeature -Online | Where-Object { $_.State -eq 'Enabled' -and $_.FeatureName -in $BadFeatures }
    Select-Items $on { $_.FeatureName } { $true } | ForEach-Object {
        Disable-WindowsOptionalFeature -Online -FeatureName $_.FeatureName -NoRestart -WarningAction SilentlyContinue | Out-Null
        Ok "Disabled feature $($_.FeatureName)"
    }
    Info 'Reboot to finish feature removal.'
}

# ==============================================================================
# 17. Network adapters
# ==============================================================================
function Set-NetworkAdapters([string[]]$Keep) {   # $Keep: component IDs auto mode must leave ticked
    if ($IsDC) { Warn 'Domain controller: keep Client for MS Networks, File and Printer Sharing and IPv6 - AD needs them.' }
    Info 'Unchecking Client for MS Networks / File and Printer Sharing breaks file shares - skip them if the README needs sharing.'
    $comp = [ordered]@{
        ms_msclient = 'Client for Microsoft Networks'; ms_server = 'File and Printer Sharing'; ms_pacer = 'QoS Packet Scheduler'
        ms_implat = 'Network Adapter Multiplexor Protocol'; ms_lldp = 'LLDP Protocol Driver'; ms_lltdio = 'Link-Layer Topology Discovery Mapper I/O'
        ms_rspndr = 'Link-Layer Topology Discovery Responder'; ms_tcpip6 = 'Internet Protocol Version 6'
    }
    Select-Items (Get-NetAdapterBinding | Where-Object { $_.Enabled -and $comp.Contains($_.ComponentID) }) { "{0,-22} {1}" -f $_.Name, $comp[$_.ComponentID] } { $_.ComponentID -notin $Keep } |
        ForEach-Object { Disable-NetAdapterBinding -Name $_.Name -ComponentID $_.ComponentID; Ok "Unchecked $($comp[$_.ComponentID]) on $($_.Name)" }

    if (Ask "IPv4: untick 'Register this connection's addresses in DNS' and disable NetBIOS over TCP/IP?" $true) {
        Get-NetAdapter | ForEach-Object { Set-DnsClient -InterfaceIndex $_.ifIndex -RegisterThisConnectionsAddress $false -ErrorAction SilentlyContinue }
        Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE' |
            ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = [uint32]2 } | Out-Null }
        Ok 'DNS registration off, NetBIOS over TCP/IP disabled'
    }
}


# ==============================================================================
# 13. App updates (winget)
# ==============================================================================
function Update-Apps {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Warn 'winget not found - use the "Install winget" option first, or update apps from Help > About.'
        return
    }
    Info 'Checking for app updates...'
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    $out = @(winget upgrade --include-unknown --accept-source-agreements | ForEach-Object { ($_ -split "`r")[-1] })
    # winget prints a fixed-width table; find column starts from the header line.
    $h = [Array]::FindIndex($out, [Predicate[string]] { param($l) $l -match '\bId\b' -and $l -match '\bVersion\b' })
    $apps = if ($h -ge 0) {
        $idCol = $out[$h].IndexOf('Id'); $verCol = $out[$h].IndexOf('Version')
        $out[($h + 2)..($out.Count - 1)] | Where-Object { $_.Length -gt $verCol -and $_ -notmatch 'upgrades? available|explicit targeting' } |
            ForEach-Object { [pscustomobject]@{ Name = $_.Substring(0, $idCol).Trim(); Id = $_.Substring($idCol, $verCol - $idCol).Trim(); Ver = $_.Substring($verCol).Trim() } }
    }
    if (-not $apps) { $out | Write-Host; Info 'Nothing to update (or could not read the list above).'; return }

    Info 'Do NOT update programs you are about to uninstall. Pick what the README needs.'
    $ids = @(Select-Items $apps { "{0,-40} {1,-40} {2}" -f $_.Name, $_.Id, $_.Ver } | ForEach-Object { $_.Id })
    if ($ids) { Start-NamedAppUpdates $ids }
    Info 'Browsers: chrome://settings/help, about:preferences (Firefox), edge://settings/help'
}

# ==============================================================================
# 14. Install winget
# ==============================================================================
function Install-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { Ok "winget already installed ($(winget --version))"; return }
    # Win10/11: App Installer is usually present but not registered for this user.
    Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue
    if (Get-Command winget -ErrorAction SilentlyContinue) { Ok 'winget registered'; return }

    # Otherwise install App Installer + the exact frameworks it needs (LTSC / Server have no Store, so none are present).
    # The release's own dependency zip always matches the bundle (VCLibs.140.00, UWPDesktop, WindowsAppRuntime, ...).
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    $rel  = 'https://github.com/microsoft/winget-cli/releases/latest/download'
    $dir  = Join-Path $env:TEMP 'cp-winget'; New-Item $dir -ItemType Directory -Force | Out-Null
    $zipPath = Join-Path $dir 'deps.zip'; $bundle = Join-Path $dir 'winget.msixbundle'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is very slow with the progress bar on PS 5.1
    try {
        Info 'Downloading winget + dependencies (~300 MB)...'
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {   # built into Win10 1803+/Server 2019+, far faster than IWR
            curl.exe -sSLZ --fail --retry 1 --connect-timeout 15 --speed-limit 51200 --speed-time 30 --max-time 900 -o $zipPath "$rel/DesktopAppInstaller_Dependencies.zip" -o $bundle "$rel/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
            if ($LASTEXITCODE -ne 0) { throw "download failed (curl exit $LASTEXITCODE)" }
        } else {
            Invoke-WebRequest "$rel/DesktopAppInstaller_Dependencies.zip" -OutFile $zipPath -UseBasicParsing -TimeoutSec 900 -ErrorAction Stop
            Invoke-WebRequest "$rel/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -OutFile $bundle -UseBasicParsing -TimeoutSec 900 -ErrorAction Stop
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $deps = @(foreach ($en in $zip.Entries | Where-Object { $_.FullName -like "$arch/*.appx" }) {
                $p = Join-Path $dir $en.Name; [IO.Compression.ZipFileExtensions]::ExtractToFile($en, $p, $true); $p })
        } finally { $zip.Dispose() }
        if (-not $deps) { throw "no $arch packages in the dependency zip" }
        foreach ($d in $deps) {
            try { Add-AppxPackage $d -ErrorAction Stop; Ok "Installed framework $(Split-Path $d -Leaf)" }
            catch { if ($_.Exception.Message -notmatch '0x80073D06') { Warn "$(Split-Path $d -Leaf): $($_.Exception.Message)" } }   # 0x80073D06 = newer already installed
        }
        Add-AppxPackage $bundle -ErrorAction Stop
    } catch { Warn "winget install failed: $($_.Exception.Message)"; return }
    finally { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }

    $env:Path += ";$env:LOCALAPPDATA\Microsoft\WindowsApps"
    if (Get-Command winget -ErrorAction SilentlyContinue) { Ok "winget installed ($(winget --version))" }
    else { Warn 'Installed, but winget is not on PATH yet - restart this script. (Server 2019 and older are not supported.)' }
}

# ==============================================================================
# 15. Forensics toolkit
# ==============================================================================
function Invoke-Forensics {
    while ($true) {
        Say "`n  1 Find file by name     2 Search text in files   3 Hash file / find file by hash"
        Say   "  4 Decode string         5 Alternate data streams 6 Recently modified files"
        Say   "  7 File owner + ACL      8 SID <-> name           9 User details (net user)"
        $c = Read-Host '  Forensics (Enter = back)'
        switch ($c) {
            '' { return }
            '1' {
                $p = Read-Host '  Name pattern (e.g. *secret*)'; $r = Read-Host '  Root [C:\]'; if (-not $r) { $r = 'C:\' }
                Get-ChildItem $r -Recurse -Force -Filter $p -ErrorAction SilentlyContinue | ForEach-Object { Say "  $($_.FullName)   $($_.LastWriteTime)" }
            }
            '2' {
                $t = Read-Host '  Text to find'; $r = Read-Host '  Root [C:\Users]'; if (-not $r) { $r = 'C:\Users' }
                Get-ChildItem $r -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 20MB } |
                    Select-String -Pattern $t -SimpleMatch -ErrorAction SilentlyContinue |
                    ForEach-Object { Say "  $($_.Path):$($_.LineNumber)  $($_.Line.Trim())" }
            }
            '3' {
                $f = Read-Host '  File or folder'
                if (Test-Path $f -PathType Leaf) {
                    'MD5', 'SHA1', 'SHA256', 'SHA512' | ForEach-Object { Say ("  {0,-7} {1}" -f $_, (Get-FileHash $f -Algorithm $_).Hash) }
                } else {
                    $h = (Read-Host '  Hash to look for').Trim()
                    $alg = switch ($h.Length) { 32 { 'MD5' } 40 { 'SHA1' } 128 { 'SHA512' } default { 'SHA256' } }
                    Get-ChildItem $f -Recurse -File -Force -ErrorAction SilentlyContinue |
                        Where-Object { (Get-FileHash $_.FullName -Algorithm $alg -ErrorAction SilentlyContinue).Hash -eq $h } |
                        ForEach-Object { Ok "Hash match: $($_.FullName)" }
                }
            }
            '4' {
                $s = Read-Host '  Encoded string'
                try { Say "  base64 : $([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s.Trim())))" } catch {}
                $hex = $s -replace '0x|[\s:]', ''
                if ($hex -match '^([0-9a-fA-F]{2})+$') { Say "  hex    : $(-join ($hex -split '(..)' | Where-Object { $_ } | ForEach-Object { [char][Convert]::ToByte($_, 16) }))" }
                if ($s -match '^[01\s]+$') { Say "  binary : $(-join ($s.Trim() -split '\s+' | ForEach-Object { [char][Convert]::ToByte($_, 2) }))" }
                Say "  rot13  : $(-join ($s.ToCharArray() | ForEach-Object {
                    $n = [int]$_
                    if ($n -ge 65 -and $n -le 90) { [char](($n - 52) % 26 + 65) } elseif ($n -ge 97 -and $n -le 122) { [char](($n - 84) % 26 + 97) } else { $_ } }))"
                try { Say "  url    : $([Uri]::UnescapeDataString($s))" } catch {}
            }
            '5' {
                $r = Read-Host '  Folder [C:\Users]'; if (-not $r) { $r = 'C:\Users' }
                Get-ChildItem $r -Recurse -File -Force -ErrorAction SilentlyContinue | Get-Item -Stream * -ErrorAction SilentlyContinue |
                    Where-Object { $_.Stream -notin ':$DATA', 'Zone.Identifier', 'SmartScreen' } | ForEach-Object {
                        Warn "$($_.FileName) : stream '$($_.Stream)' ($($_.Length) bytes)"
                        Say "      $((Get-Content -LiteralPath $_.FileName -Stream $_.Stream -Raw -ErrorAction SilentlyContinue) -replace '\s+', ' ' | ForEach-Object { $_.Substring(0, [Math]::Min(200, $_.Length)) })" DarkGray
                    }
            }
            '6' {
                $d = Read-Host '  Days back [3]'; if (-not $d) { $d = 3 }
                $r = Read-Host '  Root [C:\Users]'; if (-not $r) { $r = 'C:\Users' }
                Get-ChildItem $r -Recurse -File -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-[int]$d) -and $_.FullName -notmatch '\\AppData\\' } |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 100 | ForEach-Object { Say ("  {0:yyyy-MM-dd HH:mm}  {1}" -f $_.LastWriteTime, $_.FullName) }
            }
            '7' { $f = Read-Host '  Path'; Get-Acl $f | Format-List Owner, AccessToString | Out-String | Write-Host }
            '8' {
                $x = Read-Host '  Name or SID'
                try {
                    if ($x -match '^S-1-') { Say "  $(([Security.Principal.SecurityIdentifier]$x).Translate([Security.Principal.NTAccount]).Value)" }
                    else { Say "  $((New-Object Security.Principal.NTAccount $x).Translate([Security.Principal.SecurityIdentifier]).Value)" }
                } catch { Warn 'Could not translate' }
            }
            '9' { net user (Read-Host '  Username') | Write-Host }
        }
    }
}

# ==============================================================================
# 12. Windows automatically CHECKS for updates - never downloads or installs on its own
#     Only writes the "Configure Automatic Updates" policy. No scan, no service changes, no installs.
# ==============================================================================
function Set-UpdateCheckOnly {
    $au = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    Set-Reg $au NoAutoUpdate 0 'Configure Automatic Updates: enabled (Windows checks automatically)'
    Set-Reg $au AUOptions 2 'Updates: notify before download - nothing installs on its own'
}

# ==============================================================================
# 18. Action Center / Security Center ("must be enabled and monitoring" in every README)
# ==============================================================================
function Set-ActionCenter {
    $userHives = @(Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' } | ForEach-Object { "Registry::$($_.Name)" })
    foreach ($h in @('HKLM:') + $userHives) {
        Remove-ItemProperty "$h\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name DisableNotificationCenter -ErrorAction SilentlyContinue
        Remove-ItemProperty "$h\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name HideSCAHealth, NoTrayItemsDisplay -ErrorAction SilentlyContinue
        Remove-ItemProperty "$h\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications" -Name NoToastApplicationNotification -ErrorAction SilentlyContinue
    }
    foreach ($h in $userHives) { New-ItemProperty "$h\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications" -Name ToastEnabled -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null }
    Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications' -Name DisableNotifications, DisableEnhancedNotifications -ErrorAction SilentlyContinue
    Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray' -Name HideSystray -ErrorAction SilentlyContinue
    Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Defender Security Center\Notifications' -Name DisableNotifications -ErrorAction SilentlyContinue
    Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Security Center' -Name AntiVirusDisableNotify, FirewallDisableNotify, UpdatesDisableNotify, AntiVirusOverride, FirewallOverride -ErrorAction SilentlyContinue
    Ok 'Action Center / notification center / Security Center notifications enabled'
    sc.exe config wscsvc start= delayed-auto | Out-Null; Start-Service wscsvc -ErrorAction SilentlyContinue
    if ((Get-Service wscsvc -ErrorAction SilentlyContinue).Status -eq 'Running') { Ok 'Security Center service (wscsvc) running' } else { Warn 'Security Center service (wscsvc) not running - check services.msc' }
}


# ==============================================================================
# 20. Default browser -> Google Chrome for all users
# ==============================================================================
function Set-DefaultBrowserChrome {
    if (-not (Test-Path 'Registry::HKEY_CLASSES_ROOT\ChromeHTML')) { Warn 'ChromeHTML not registered - install/repair Google Chrome (system-wide) first.'; return }
    $xml = Join-Path $env:ProgramData 'cp-default-browser.xml'
    @('<?xml version="1.0" encoding="UTF-8"?>', '<DefaultAssociations>') +
        ('.htm', '.html', '.shtml', '.xht', '.xhtml', 'http', 'https' | ForEach-Object { "  <Association Identifier=`"$_`" ProgId=`"ChromeHTML`" ApplicationName=`"Google Chrome`" />" }) +
        '</DefaultAssociations>' | Set-Content $xml -Encoding ASCII
    dism.exe /Online /Import-DefaultAppAssociations:"$xml" | Out-Null
    if ($LASTEXITCODE -eq 0) { Ok 'Default app associations imported (new users)' } else { Warn "dism import failed ($LASTEXITCODE)" }
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' DefaultAssociationsConfiguration $xml 'Default browser policy -> Chrome (applied at every sign-in, all users)' 'String'
    Set-Reg 'HKLM:\SOFTWARE\Policies\Google\Chrome' DefaultBrowserSettingEnabled 1 'Chrome policy: Chrome is the default browser'
    Info 'Your session picks it up after sign-out. To set it right now: Settings > Apps > Default apps > Google Chrome > Set default.'
    if (-not $Auto) { Start-Process 'ms-settings:defaultapps' -ErrorAction SilentlyContinue }
}

# Same as Update-NamedApps, but in a separate window.
function Start-NamedAppUpdates([string[]]$Ids) {
    Start-InNewWindow 'CP app updates' "Update-NamedApps $(ConvertTo-PSList $Ids)"
}

# Updates the README's business apps by winget id (and undoes policies that block their updaters).
function Update-NamedApps([string[]]$Ids) {
    Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Google\Update' -Name UpdateDefault, AutoUpdateCheckPeriodMinutes, 'Update{8A69D345-D564-463C-AFF1-A69D9E530F96}' -ErrorAction SilentlyContinue
    Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox', 'HKLM:\SOFTWARE\Policies\Mozilla\Thunderbird' -Name DisableAppUpdate -ErrorAction SilentlyContinue
    foreach ($s in Get-Service gupdate, gupdatem, 'GoogleUpdater*', MozillaMaintenance -ErrorAction SilentlyContinue) {
        if ($s.StartType -eq 'Disabled') { sc.exe config $s.Name start= demand | Out-Null; Ok "Re-enabled updater service $($s.Name)" }
    }
    # Fast path first: the app's own updater or a small official installer. winget only if the image already has it -
    # installing winget is ~300 MB and big installers (Chrome MSI, LibreOffice) stall for minutes on CP VMs.
    $haveWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
    foreach ($id in $Ids) {
        Info "Updating $id..."
        if (Install-Direct $id) { continue }
        if ($haveWinget) {
            $p = Start-Process winget "upgrade --id $id --exact --silent --include-unknown --accept-package-agreements --accept-source-agreements" -NoNewWindow -PassThru
            if (-not $p.WaitForExit(240000)) { $p | Stop-Process -Force -ErrorAction SilentlyContinue; Warn "${id}: winget took over 4 minutes - stopped. Update it by hand."; continue }
            if ($p.ExitCode -eq 0) { Ok "$id has been updated (winget)"; continue }
            if ($p.ExitCode -eq -1978335189) { Say "  [=] $id already up to date" DarkGreen; continue }   # UPDATE_NOT_APPLICABLE
        }
        Warn "${id}: update it by hand - Help > About, or the vendor site (x64 build, no ads)"
    }
}

# Download that gives up instead of hanging: aborts below 50 KB/s for 30 s, or after $MaxSeconds.
function Get-Download($Url, $Out, $MaxSeconds = 180) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        curl.exe -sSL --fail --retry 1 --connect-timeout 15 --speed-limit 51200 --speed-time 30 --max-time $MaxSeconds -o $Out $Url
        if ($LASTEXITCODE) { throw "download failed or too slow (curl exit $LASTEXITCODE): $Url" }
    } else { $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest $Url -OutFile $Out -UseBasicParsing -TimeoutSec $MaxSeconds -ErrorAction Stop }
}

# Small official installers (GitHub releases): winget id -> repo, x64 asset, silent switch, process to close first,
# and the installed-programs name used to read the current version.
$DirectApps = @{
    'Notepad++.Notepad++'   = 'notepad-plus-plus/notepad-plus-plus', 'Installer\.x64\.exe$', '/S', 'notepad++', '^Notepad\+\+'
    '7zip.7zip'             = 'ip7z/7zip', '^7z\d+-x64\.exe$', '/S', '7zFM', '^7-Zip'
    'OpenRocket.OpenRocket' = 'openrocket/openrocket', '(?i)(windows|installer).*\.exe$', '-q', 'OpenRocket', '^OpenRocket'   # install4j: -q = unattended. UNTESTED.
}

function Get-InstalledVersion($NamePattern) {
    @(Get-Installed | Where-Object { $_.DisplayName -match $NamePattern } |
        Sort-Object { try { [version](("$($_.DisplayVersion)" -replace '[^\d\.]', '').Trim('.')) } catch { [version]'0.0' } } -Descending)[0].DisplayVersion
}
# $true when $Latest is a higher version than $Have (or when either cannot be read, so the update is attempted).
function Test-Newer($Have, $Latest) {
    try {
        $h = [version]((("$Have" -replace '[^\d\.]', '').Trim('.') -split '\.' | Select-Object -First 3) -join '.')
        $l = [version]((("$Latest" -replace '[^\d\.]', '').Trim('.') -split '\.' | Select-Object -First 3) -join '.')
        $l -gt $h
    } catch { $true }
}
# Downloads from the first URL that works (mirrors fail: LibreOffice gave a 502 on the VM), runs the installer silently.
function Install-FromUrl($Label, [string[]]$Urls, $File, $Arguments, $Proc, [switch]$Msi) {
    $got = $false
    foreach ($u in $Urls) {
        try { Info "Downloading $u"; Get-Download $u $File 600; $got = $true; break } catch { Warn "${Label}: $($_.Exception.Message) - trying the next source" }
    }
    if (-not $got) { return $false }
    if ($Proc) { Get-Process $Proc -ErrorAction SilentlyContinue | Stop-Process -Force }
    $p = if ($Msi) { Start-Process msiexec.exe "/i `"$File`" /qn /norestart" -PassThru } else { Start-Process $File $Arguments -PassThru }
    if (-not $p.WaitForExit(600000)) { $p | Stop-Process -Force; Warn "${Label}: installer ran for over 10 minutes - stopped"; return $false }
    if ($p.ExitCode -notin 0, 3010) { Warn "${Label}: installer exit code $($p.ExitCode)"; return $false }
    $true
}

# Returns $true when the app was updated, is already current, or its own updater was started; $false = try winget / do it by hand.
function Install-Direct($Id) {
    if ($Id -eq 'Google.Chrome') {
        # Chrome's own updater downloads only a small diff - not the 171 MB installer - and runs in the background.
        $upd = @(Get-ChildItem "${env:ProgramFiles(x86)}\Google\GoogleUpdater\*\updater.exe", "$env:ProgramFiles\Google\GoogleUpdater\*\updater.exe" -ErrorAction SilentlyContinue |
            Sort-Object { try { [version]$_.Directory.Name } catch { [version]'0.0' } } -Descending)[0]
        $legacy = "${env:ProgramFiles(x86)}\Google\Update\GoogleUpdate.exe"
        Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force   # lets the update swap in now, not on next launch
        if ($upd) { Start-Process $upd.FullName '--wake --system' -WindowStyle Hidden }
        elseif (Test-Path $legacy) { Start-Process $legacy '/ua /installsource scheduler' -WindowStyle Hidden }
        else { return $false }
        Ok "Chrome's own updater started - it finishes in the background (check chrome://settings/help in a few minutes)"
        return $true
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $file = Join-Path $env:TEMP "cp-direct-$($Id -replace '\W', '')"
    try {
        if ($Id -in 'Mozilla.Thunderbird', 'Mozilla.Firefox') {
            $prod = if ($Id -match 'Thunderbird') { 'thunderbird' } else { 'firefox' }
            $latest = (Invoke-RestMethod "https://product-details.mozilla.org/1.0/${prod}_versions.json" -UseBasicParsing -TimeoutSec 20)."LATEST_$($prod.ToUpper())_VERSION"
            $have = Get-InstalledVersion "^Mozilla $prod"
            if ($have -and $latest -and -not (Test-Newer $have $latest)) { Say "  [=] $prod $have is already the latest ($latest)" DarkGreen; return $true }
            if (Install-FromUrl $prod @("https://download.mozilla.org/?product=$prod-latest-ssl&os=win64&lang=en-US") "$file.exe" '/S' $prod) {
                Ok "$prod has been updated to $latest (was $have)"; return $true
            }
            return $false
        }
        if ($Id -eq 'TheDocumentFoundation.LibreOffice') {
            $bases = 'https://download.documentfoundation.org/libreoffice/stable/', 'https://mirror.clarkson.edu/tdf/libreoffice/stable/', 'https://mirrors.ocf.berkeley.edu/tdf/libreoffice/stable/'
            $ver = $null
            foreach ($b in $bases) {
                try {
                    $html = (Invoke-WebRequest $b -UseBasicParsing -TimeoutSec 20).Content
                    $ver = [regex]::Matches($html, 'href="(\d+\.\d+\.\d+)/"') | ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending | Select-Object -First 1
                    if ($ver) { break }
                } catch { }
            }
            if (-not $ver) { Warn 'LibreOffice: could not read the latest version from any mirror'; return $false }
            $have = Get-InstalledVersion '^LibreOffice \d'
            if ($have -and -not (Test-Newer $have "$ver")) { Say "  [=] LibreOffice $have is already the latest ($ver)" DarkGreen; return $true }
            $urls = $bases | ForEach-Object { "$_$ver/win/x86_64/LibreOffice_${ver}_Win_x86-64.msi" }
            if (Install-FromUrl 'LibreOffice' $urls "$file.msi" $null 'soffice.bin' -Msi) { Ok "LibreOffice has been updated to $ver (was $have)"; return $true }
            return $false
        }
        if (-not $DirectApps.ContainsKey($Id)) { return $false }
        $repo, $pattern, $switch, $proc, $namePat = $DirectApps[$Id]
        $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing -TimeoutSec 20
        $have = Get-InstalledVersion $namePat
        if ($have -and -not (Test-Newer $have $rel.tag_name)) { Say "  [=] $Id $have is already the latest ($($rel.tag_name))" DarkGreen; return $true }
        $url = ($rel.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1).browser_download_url
        if (-not $url) { throw "no x64 installer in $repo $($rel.tag_name)" }
        if (Install-FromUrl $Id @($url) "$file.exe" $switch $proc) { Ok "$Id has been updated to $($rel.tag_name) (was $have)"; return $true }
        $false
    } catch { Warn "${Id} direct update failed: $($_.Exception.Message)"; $false }
    finally { Remove-Item "$file.exe", "$file.msi" -Force -ErrorAction SilentlyContinue }
}

# ==============================================================================
# README config (cp-config.psd1): one file per image, filled in from the README.
# Loaded by CP-Run.ps1 (automatic run) or menu option C. Background windows reload it too.
# ==============================================================================
$Cfg = @{}; $CfgPath = ''
$KeepBindings = @('ms_msclient')   # network components auto mode leaves ticked
$IisCritical = $false

# True when deleting is allowed: always in the interactive menu; in auto mode only once the config says the
# forensics questions are answered (deleting users, files or backdoors first can make them unanswerable).
function CanDestroy($What) {
    if (-not $Auto -or $Cfg.ForensicsDone) { return $true }
    if ($What) { Warn "SKIPPED until ForensicsDone = `$true in the config: $What" }
    $false
}

# Is this program / file / rule something the README says must stay?
function Test-Required($Name) {
    foreach ($r in @($Cfg.RequiredApps)) { if ($r -and "$Name" -like "*$r*") { return $true } }
    $false
}

# README "critical service" -> never stop it, keep it running. Accepts a keyword (RDP, IIS, SMB, FTP, DNS, SSH,
# Print, WinRM, SNMP, Telnet, SMTP) or an exact Windows service name.
function Protect-Service($s) {
    $map = @{
        'rdp' = 'TermService', 'SessionEnv', 'UmRdpService'; 'remote desktop' = 'TermService', 'SessionEnv', 'UmRdpService'
        'iis' = 'W3SVC', 'WAS'; 'web' = 'W3SVC', 'WAS'; 'http' = 'W3SVC', 'WAS'
        'smb' = @('LanmanServer'); 'file sharing' = @('LanmanServer'); 'file server' = @('LanmanServer')
        'ftp' = @('ftpsvc'); 'dns' = @('DNS'); 'ssh' = @('sshd'); 'openssh' = @('sshd'); 'print' = @('Spooler'); 'printing' = @('Spooler')
        'winrm' = @('WinRM'); 'snmp' = @('SNMP'); 'telnet' = @('TlntSvr'); 'smtp' = @('SMTPSVC')
    }
    $key = "$s".ToLower().Trim()
    $names = if ($map.ContainsKey($key)) { @($map[$key]) } else { @("$s".Trim()) }
    foreach ($n in $names) {
        if ($script:BadServices.Contains($n)) { $script:BadServices.Remove($n) }
        if ($n -notin $script:GoodServices) { $script:GoodServices = @($script:GoodServices) + $n }
    }
    switch -Regex ($key) {
        '^(rdp|remote desktop)$' { $script:Cfg.RemoteDesktop = 'required' }
        '^(iis|web|http)$' {
            $script:BadFeatures = @($script:BadFeatures | Where-Object { $_ -notmatch '^IIS-WebServer' }) + 'IIS-WebDAV', 'IIS-ManagementService'
            $script:IisCritical = $true
        }
        '^ftp$' { $script:BadFeatures = @($script:BadFeatures | Where-Object { $_ -notmatch '^IIS-FTP' }) }
        '^telnet$' { $script:BadFeatures = @($script:BadFeatures | Where-Object { $_ -ne 'TelnetServer' }) }
        '^snmp$' { $script:BadFeatures = @($script:BadFeatures | Where-Object { $_ -notmatch 'SNMP' }) }
        '^(smb|file sharing|file server)$' { if ('ms_server' -notin $script:KeepBindings) { $script:KeepBindings = @($script:KeepBindings) + 'ms_server' } }
    }
}

function Use-CpConfig($Path) {
    $c = Import-PowerShellDataFile -LiteralPath $Path -ErrorAction Stop
    $d = @{
        Admins = @(); Users = @(); CriticalServices = @(); RequiredApps = @(); UpdateApps = @()
        DefaultBrowser = ''; RemoteDesktop = 'leave'; Groups = @{}; Shares = @(); KeepShares = @()
        ForensicsDone = $false; ResetPasswords = $true; NewPassword = ''
        RemoveSoftware = @(); RemoveFiles = @(); ScanRoots = @(); KeepPaths = @()
        WindowsUpdateMode = 4; InstallWindowsUpdates = $false; DisableOneDrive = $true
        QuarantineSensitiveInShares = $true
    }
    foreach ($k in @($c.Keys)) {
        if (-not $d.ContainsKey($k)) { Warn "config: unknown setting '$k' - check the spelling against cp-config.example.psd1" }
        $d[$k] = $c[$k]
    }
    foreach ($k in 'Admins', 'Users', 'CriticalServices', 'RequiredApps', 'UpdateApps', 'KeepShares', 'RemoveSoftware', 'RemoveFiles', 'ScanRoots', 'KeepPaths', 'Shares') {
        $d[$k] = @($d[$k] | Where-Object { $_ })
    }
    if (-not $d.Groups) { $d.Groups = @{} }
    $script:Cfg = $d; $script:CfgPath = "$Path"
    foreach ($s in $d.CriticalServices) { Protect-Service $s }
    if ($d.Shares.Count) { Protect-Service 'smb' }
    $shareNames = @($d.Shares | ForEach-Object { $_.Name }) + $d.KeepShares | Where-Object { $_ }
    if ($shareNames) {
        $script:KeepShares = '^([A-Z]\$|ADMIN\$|IPC\$|print\$|NETLOGON|SYSVOL|' + (($shareNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')$'
    }
}

# Checks that would otherwise delete the wrong accounts. Returns $false when the config must not be used.
function Test-CpConfig {
    $bad = $false
    if (-not $Cfg.Admins.Count) { Warn 'config: Admins is empty - fill in the README''s Authorized Administrators'; $bad = $true }
    if ($env:USERNAME -notin $Cfg.Admins) { Warn "config: you are '$env:USERNAME' but that name is not in Admins - wrong config for this image?"; $bad = $true }
    foreach ($n in @($Cfg.Admins) + @($Cfg.Users)) { if ($n -match '[\s\(\)]') { Warn "config: '$n' is not a plain account name (remove '(you)', passwords and spaces)"; $bad = $true } }
    $dup = @($Cfg.Admins | Where-Object { $_ -in $Cfg.Users })
    if ($dup) { Warn "config: listed as both admin and user: $($dup -join ', ')"; $bad = $true }
    if (-not $IsDC -and (Get-Command Get-LocalUser -ErrorAction SilentlyContinue)) {
        $all = @($Cfg.Admins) + @($Cfg.Users)
        $local = @(Get-LocalUser | Where-Object { $_.SID.Value -notmatch '-(500|501|503|504)$' })
        $gone = @($local | Where-Object { $_.Name -notin $all })
        if ($local.Count -ge 4 -and $gone.Count -ge ($local.Count - $gone.Count)) {
            Warn "config: it would remove $($gone.Count) of $($local.Count) accounts - that looks like the wrong README"; $bad = $true
        }
    }
    -not $bad
}

# ==============================================================================
# 21. Groups the README asks for
# ==============================================================================
function Set-ReadmeGroups {
    if ($IsDC) { Warn 'Domain controller: create README groups in dsa.msc.'; return }
    foreach ($g in @($Cfg.Groups.Keys)) {
        if (-not (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)) { New-LocalGroup -Name $g | Out-Null; Ok "Created group $g" }
        $have = Get-GroupMembers $g
        foreach ($m in @($Cfg.Groups[$g])) {
            if ($m -in $have) { Say "  [=] $m already in $g" DarkGreen; continue }
            net localgroup "$g" "$m" /add | Out-Null
            if ($LASTEXITCODE -eq 0) { Ok "Added $m to group $g" } else { Warn "Could not add $m to $g (does the account exist?)" }
        }
    }
}

# ==============================================================================
# 22. Programs that are on disk but not "installed" (portable tools, planted games)
#     The installed-programs list misses these: Minesweeper sat in C:\Program Files\Minesweeper, HFS in C:\HFS.
# ==============================================================================
$GamePattern = 'minesweeper|solitaire|pinball|mahjong|\bchess|tetris|pac-?man|\bdoom\b|\bquake\b|freeciv|\bgames?\b'
$RemoteToolPattern = 'teamviewer|anydesk|tightvnc|realvnc|ultravnc|\bvnc|ammyy|radmin|remote utilities|rustdesk|splashtop|logmein|screenconnect|' +
    '\bhfs\b|http file server|netcat|ncat|\bnc(64)?\.exe'
$DefaultProgramDirs = '^(Common Files|Internet Explorer|Microsoft.*|ModifiableWindowsApps|MSBuild|Reference Assemblies|Windows.*|Uninstall Information|' +
    'VMware|dotnet|PackageManagement|IIS.*|PowerShell|Hyper-V|CyberPatriot.*|desktop\.ini)$'
$DefaultRootDirs = '^(\$.*|Config\.Msi|Documents and Settings|inetpub|PerfLogs|Program Files|Program Files \(x86\)|ProgramData|Recovery|' +
    'System Volume Information|Users|Windows|Windows\.old|OneDriveTemp|CyberPatriot.*|cp-quarantine|AFA.*)$'

function Find-UnknownPrograms {
    $installed = @(Get-Installed)
    $locs  = @($installed | ForEach-Object { "$($_.InstallLocation)".Trim('"').TrimEnd('\') } | Where-Object { $_ })
    $names = @($installed | ForEach-Object { "$($_.DisplayName) $($_.Publisher)" })
    $keep  = @($Cfg.KeepPaths) + @($Cfg.Shares | ForEach-Object { $_.Path }) | Where-Object { $_ }
    $cands = @()
    foreach ($pf in $env:ProgramFiles, ${env:ProgramFiles(x86)}) {
        if ($pf) { $cands += @(Get-ChildItem -LiteralPath $pf -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $DefaultProgramDirs }) }
    }
    $cands += @(Get-ChildItem -LiteralPath "$env:SystemDrive\" -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $DefaultRootDirs })
    $unknown = foreach ($d in $cands) {
        $full = $d.FullName
        if ($keep | Where-Object { $full -eq $_.TrimEnd('\') -or $_ -like "$full\*" }) { continue }          # README share / kept path
        if ($locs | Where-Object { $_ -eq $full -or $_.StartsWith("$full\", [StringComparison]::OrdinalIgnoreCase) }) { continue }   # a real installed program lives here
        $n = [regex]::Escape($d.Name)
        if ($names | Where-Object { $_ -match $n }) { continue }                                              # folder named after an installed program / its publisher
        if (Test-Required $d.Name) { continue }
        $exes = @(Get-ChildItem -LiteralPath $full -Recurse -File -Force -Filter *.exe -ErrorAction SilentlyContinue | Select-Object -First 30)
        $d | Add-Member NoteProperty Exes $exes -PassThru
    }
    foreach ($u in $unknown) { Warn "Not an installed program and not in the README: $($u.FullName)   exe files: $(($u.Exes.Name | Select-Object -First 6) -join ', ')" }
    Select-Items $unknown { "$($_.FullName)  ($($_.Exes.Count) exe)" } {
        (CanDestroy) -and ("$($_.Name) $($_.Exes.Name -join ' ')" -match "$BadSoftware|$GamePattern|$RemoteToolPattern|$ToolFilePattern")
    } | ForEach-Object {
        $full = $_.FullName
        Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith("$full\", [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue; Ok "Killed $($_.ProcessName) running from $full"
        }
        Start-Sleep -Milliseconds 400
        Move-ToQuarantine $full
    }
    if (-not $Auto) { Info 'Anything left on the list above: decide by hand. Unknown is not the same as bad.' }
}

# ==============================================================================
# 23. Inbound firewall rules left behind by removed or prohibited programs
#     (AnyDesk left 6 allow rules after its uninstall; TeamViewer did the same on the server.)
# ==============================================================================
function Remove-StaleFirewallRules {
    $p = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules' -ErrorAction SilentlyContinue
    if (-not $p) { return }
    $rules = foreach ($v in @($p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' -and $_.Value -is [string] })) {
        $f = @{}
        foreach ($part in $v.Value -split '\|') { $i = $part.IndexOf('='); if ($i -gt 0) { $f[$part.Substring(0, $i)] = $part.Substring($i + 1) } }
        if ($f['Dir'] -ne 'In' -or $f['Action'] -ne 'Allow') { continue }
        $app = [Environment]::ExpandEnvironmentVariables("$($f['App'])")
        $why = $null
        if ("$($f['Name']) $app" -match $RemoteToolPattern -and -not (Test-Required "$($f['Name']) $app")) { $why = 'remote-access or prohibited program' }
        elseif ($app -match '^[A-Za-z]:\\' -and $app -notmatch '^[A-Za-z]:\\Windows\\' -and -not (Test-Path -LiteralPath $app)) { $why = 'its program is no longer on disk' }
        if ($why) { [pscustomobject]@{ Id = $v.Name; Name = $f['Name']; App = $app; Why = $why } }
    }
    Select-Items $rules { "$($_.Name)   [$($_.Why)]   $($_.App)" } { $true } | ForEach-Object {
        Remove-NetFirewallRule -Name $_.Id -ErrorAction SilentlyContinue
        if (Get-NetFirewallRule -Name $_.Id -ErrorAction SilentlyContinue) { Warn "Could not remove firewall rule $($_.Name)" } else { Ok "Removed inbound firewall rule '$($_.Name)' ($($_.Why))" }
    }
}

# Defender exclusions set by POLICY live in the registry and survive Remove-MpPreference (the server's "exe" exclusion did).
function Remove-DefenderPolicyExclusions {
    $base = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions'
    foreach ($sub in 'Extensions', 'Paths', 'Processes', 'IpAddresses') {
        $k = "$base\$sub"
        $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        foreach ($v in @($p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })) {
            if ($v.Name -match 'CyberPatriot') { Say "  [=] Keeping policy exclusion $($v.Name) (scoring engine)" DarkGreen; continue }
            Remove-ItemProperty -LiteralPath $k -Name $v.Name -ErrorAction SilentlyContinue
            Ok "Removed Defender POLICY exclusion ($sub): $($v.Name)"
        }
    }
    Remove-ItemProperty $base -Name Exclusions_Extensions, Exclusions_Paths, Exclusions_Processes -ErrorAction SilentlyContinue
}

# ==============================================================================
# 24. Files that hold passwords or personal data (file CONTENTS, not names: staff.csv in a share)
# ==============================================================================
$TextExt = 'txt', 'csv', 'tsv', 'log', 'ini', 'cfg', 'conf', 'xml', 'json', 'yml', 'yaml', 'md', 'rtf', 'bak', 'old', 'sql'
$SensitivePattern = '(?i)\b(pass(word|wd)?s?|pwd|ssn|social security|credit ?card|card ?number|cvv)\b'
function Find-SensitiveFiles([string[]]$Roots, [string[]]$AutoRoots) {
    $Roots = @($Roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    if (-not $Roots) { return }
    Info "Reading text files under: $($Roots -join ', ')"
    $hits = Get-ChildItem -LiteralPath $Roots -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -lt 5MB -and $_.Extension.TrimStart('.').ToLower() -in $TextExt -and $_.FullName -notmatch '\\AppData\\|CyberPatriot|cp-quarantine|Forensic|README|cp-log-|CP-Errors' } |
        ForEach-Object {
            $m = Select-String -LiteralPath $_.FullName -Pattern $SensitivePattern -List -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($m) { [pscustomobject]@{ File = $_; Line = "$($m.Line)".Trim() } }
        }
    foreach ($h in $hits) { Warn "Possible passwords / personal data: $($h.File.FullName)   line: $($h.Line.Substring(0, [Math]::Min(80, $h.Line.Length)))" }
    Select-Items $hits { "$($_.File.FullName)   -> $($_.Line.Substring(0, [Math]::Min(60, $_.Line.Length)))" } {
        $path = $_.File.FullName
        (CanDestroy) -and $Cfg.QuarantineSensitiveInShares -and [bool]($AutoRoots | Where-Object { $_ -and $path.StartsWith($_.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) })
    } | ForEach-Object { Move-ToQuarantine $_.File.FullName }
}

# ==============================================================================
# 25. Backdoors: renamed tools in the Windows folders, and what is listening
#     The Windows 11 backdoor was netcat renamed to nvhostsvc.exe in System32, and it was not listening when we looked.
# ==============================================================================
$NcOrig = '^(nc|nc64|ncat|netcat|socat|cryptcat|powercat|psexec|psexesvc|plink|mimikatz|pwdump\d*|fgdump|lazagne|rubeus|sharphound|chisel|ngrok|hfs)(64)?(\.exe)?$'
$RunKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
           'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
           'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'

# What starts this file? Services, scheduled tasks and Run entries that mention it.
function Get-Launchers($Path) {
    $leaf = [regex]::Escape((Split-Path $Path -Leaf))
    $out = @()
    $out += @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.PathName -match "\\$leaf" } | ForEach-Object { [pscustomobject]@{ Kind = 'service'; Name = $_.Name; Detail = $_.PathName } })
    $out += @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { "$($_.Actions.Execute) $($_.Actions.Arguments)" -match $leaf } | ForEach-Object { [pscustomobject]@{ Kind = 'task'; Name = "$($_.TaskPath)$($_.TaskName)"; Detail = "$($_.Actions.Execute) $($_.Actions.Arguments)"; Task = $_ } })
    foreach ($k in $RunKeys) {
        $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
        if ($p) { $out += @($p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' -and "$($_.Value)" -match $leaf } | ForEach-Object { [pscustomobject]@{ Kind = 'run'; Name = $_.Name; Detail = "$($_.Value)"; Key = $k } }) }
    }
    $out
}

# Kills it, switches off whatever launches it, and moves the file to C:\cp-quarantine.
function Remove-Backdoor($Path) {
    Get-Process | Where-Object { $_.Path -eq $Path } | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue; Ok "Killed backdoor process $($_.ProcessName) (pid $($_.Id))" }
    foreach ($l in Get-Launchers $Path) {
        switch ($l.Kind) {
            'service' { Stop-Service $l.Name -Force -ErrorAction SilentlyContinue; sc.exe config $l.Name start= disabled | Out-Null; Ok "Stopped and disabled service $($l.Name) -> $($l.Detail)" }
            'task'    { $l.Task | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue; Ok "Deleted scheduled task $($l.Name) -> $($l.Detail)" }
            'run'     { Remove-ItemProperty $l.Key -Name $l.Name -ErrorAction SilentlyContinue; Ok "Removed autorun $($l.Name) -> $($l.Detail)" }
        }
    }
    Start-Sleep -Milliseconds 400
    Move-ToQuarantine $Path
}

function Find-RenamedTools {
    Info 'Checking every .exe in Windows, System32 and SysWOW64 (takes a minute)...'
    $listening = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Path } | Where-Object { $_ })
    $sus = foreach ($f in Get-ChildItem "$env:windir\System32\*.exe", "$env:windir\SysWOW64\*.exe", "$env:windir\*.exe" -Force -ErrorAction SilentlyContinue) {
        $vi = $f.VersionInfo
        $orig = "$($vi.OriginalFilename)" -replace '\.mui$', ''
        $why = $null; $bad = $false
        if ($orig -match $NcOrig -or "$($vi.InternalName)" -match $NcOrig) {
            $why = "is really '$orig' ($($vi.FileDescription))"; $bad = $true
        } elseif ("$($vi.CompanyName)" -notmatch 'Microsoft') {
            $sig = Get-AuthenticodeSignature -LiteralPath $f.FullName -ErrorAction SilentlyContinue
            if ("$($sig.Status)" -ne 'Valid') {
                $launch = @(Get-Launchers $f.FullName)
                $why = "not a Microsoft file and not signed (company '$($vi.CompanyName)', original name '$orig')"
                if ($launch) { $why += "; started by $(($launch | ForEach-Object { "$($_.Kind) $($_.Name)" }) -join ', ')"; $bad = $true }
                if ($f.FullName -in $listening) { $why += '; LISTENING on the network'; $bad = $true }
            }
        }
        if ($why) { [pscustomobject]@{ File = $f; Why = $why; Bad = $bad } }
    }
    foreach ($s in $sus) { Warn "$(if ($s.Bad) { 'BACKDOOR? ' })$($s.File.FullName) $($s.Why)" }
    Select-Items $sus { "{0}{1}  - {2}" -f $(if ($_.Bad) { '!! ' } else { '' }), $_.File.FullName, $_.Why } { $_.Bad -and (CanDestroy) -and $_.File.FullName -notmatch 'CyberPatriot' } |
        ForEach-Object { Remove-Backdoor $_.File.FullName }
}

# Ports -> program name, file, original file name and signature. Several snapshots, because a backdoor that
# restarts on a timer is easy to miss in one. Known remote-tool ports are named so they are not mistaken for it.
$KnownPorts = @{
    21 = 'FTP'; 22 = 'SSH'; 23 = 'Telnet'; 25 = 'SMTP'; 53 = 'DNS'; 80 = 'HTTP'; 135 = 'Windows RPC'; 139 = 'NetBIOS'; 443 = 'HTTPS'; 445 = 'SMB file sharing'
    3389 = 'Remote Desktop'; 5040 = 'Windows CDP'; 5357 = 'Windows network discovery'; 5985 = 'WinRM'; 5986 = 'WinRM (TLS)'; 7680 = 'Windows Update delivery'
    5900 = 'VNC'; 5800 = 'VNC (web)'; 5938 = 'TeamViewer'; 7070 = 'AnyDesk'; 6568 = 'AnyDesk'; 8080 = 'HTTP (alternate; HFS uses 80 or 8080)'
    4444 = 'Metasploit default'; 1337 = 'common backdoor port'; 31337 = 'common backdoor port'; 6667 = 'IRC'
}
function Show-Listeners($Snapshots = 3, $GapSeconds = 8) {
    $seen = @{}
    for ($i = 0; $i -lt $Snapshots; $i++) {
        if ($i) { Info "next snapshot in $GapSeconds s..."; Start-Sleep -Seconds $GapSeconds }
        Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
            $k = "$($_.LocalPort)|$($_.OwningProcess)"
            if (-not $seen.ContainsKey($k)) {
                $pr = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
                $seen[$k] = [pscustomobject]@{ Port = [int]$_.LocalPort; Addr = $_.LocalAddress; ProcId = $_.OwningProcess; Name = "$($pr.ProcessName)"; Path = "$($pr.Path)"; Shots = 0 }
            }
            $seen[$k].Shots++
        }
    }
    $rows = foreach ($r in @($seen.Values) | Sort-Object Port) {
        $orig = ''; $sig = ''
        if ($r.Path -and (Test-Path -LiteralPath $r.Path)) {
            $orig = "$((Get-Item -LiteralPath $r.Path).VersionInfo.OriginalFilename)" -replace '\.mui$', ''
            $sig = "$((Get-AuthenticodeSignature -LiteralPath $r.Path -ErrorAction SilentlyContinue).Status)"
        }
        $flag = ''
        if ($r.Name -match $NcOrig -or $orig -match $NcOrig) { $flag = '!!' }
        elseif ($r.Path -and $sig -ne 'Valid' -and $r.Path -match '^[A-Za-z]:\\Windows\\') { $flag = '!!' }
        elseif ($r.Path -and $sig -ne 'Valid') { $flag = '? ' }
        $r | Add-Member NoteProperty Orig $orig -PassThru | Add-Member NoteProperty Sig $sig -PassThru | Add-Member NoteProperty Flag $flag -PassThru
    }
    foreach ($r in $rows) {
        $known = if ($KnownPorts.ContainsKey($r.Port)) { "[$($KnownPorts[$r.Port])]" } else { '' }
        $line = "{0,-2} {1,-6} {2,-22} pid {3,-6} {4}  {5} {6}{7}" -f $r.Flag, $r.Port, $r.Name, $r.ProcId, $r.Path, $known,
            $(if ($r.Orig -and $r.Path -and $r.Orig -ne (Split-Path $r.Path -Leaf)) { "(original name: $($r.Orig)) " } else { '' }),
            $(if ($r.Shots -lt $Snapshots) { "(seen in $($r.Shots) of $Snapshots snapshots - comes and goes)" } else { '' })
        if ($r.Flag -eq '!!') { Warn "LISTENING BACKDOOR? $line" } elseif ($r.Flag -or $r.Shots -lt $Snapshots) { Warn "Listener to check: $line" } else { Say "  $line" }
    }
    Info 'A known remote-tool port (AnyDesk 7070, TeamViewer 5938, VNC 5900) is that tool, not a backdoor: uninstall the tool.'
    $rows | Where-Object { $_.Flag -eq '!!' -and $_.Path -and $_.Path -notmatch 'CyberPatriot' } | ForEach-Object {
        if ((CanDestroy "remove listening backdoor $($_.Path)") -and (Ask "Remove $($_.Path) (listening on $($_.Port))?" $true)) { Remove-Backdoor $_.Path }
    }
}

# ==============================================================================
# 26. Older copies of a program left next to the updated one (7-Zip 24.05 beside 26.06)
# ==============================================================================
function Remove-OldVersions {
    $groups = Get-Installed | Where-Object { $_.DisplayName -notmatch 'microsoft|redistributable|runtime|\.net|driver|update|vmware' } |
        Group-Object { (($_.DisplayName -replace '\(?\bx(64|86)\b[^)]*\)?', '') -replace '[\d\.]+', '' -replace '\s+', ' ').Trim().ToLower() } |
        Where-Object { $_.Count -gt 1 -and $_.Name }
    $old = foreach ($g in $groups) {
        $sorted = @($g.Group | Sort-Object { try { [version](("$($_.DisplayVersion)" -replace '[^\d\.]', '').Trim('.')) } catch { [version]'0.0' } } -Descending)
        $sorted | Select-Object -Skip 1 | Where-Object { $_.DisplayVersion -ne $sorted[0].DisplayVersion }
    }
    Select-Items $old { "$($_.DisplayName) $($_.DisplayVersion)  (a newer version is also installed)" } { CanDestroy } | ForEach-Object { Uninstall-App $_ }
}

# ==============================================================================
# 27. Windows Update: automatic, and security / quality updates only
# ==============================================================================
# Local Group Policy keeps its own copy of machine policy in Registry.pol and re-applies it at every gpupdate,
# undoing a plain registry edit (this is what happened on the Windows 11 image). If that file already sets
# the value, change the number in place there as well. Only touches an existing DWORD entry; a backup is kept.
function Set-PolDword($Key, $Name, [int]$Value) {
    $pol = "$env:windir\System32\GroupPolicy\Machine\Registry.pol"
    if (-not (Test-Path $pol)) { return }
    try {
        $b = [IO.File]::ReadAllBytes($pol)
        if ($b.Length -lt 8 -or [Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'PReg') { return }
        $needle = [Text.Encoding]::Unicode.GetBytes("[$Key`0;$Name`0;")
        $low = [Text.Encoding]::Unicode.GetBytes("[$Key`0;$Name`0;".ToLower()); $up = [Text.Encoding]::Unicode.GetBytes("[$Key`0;$Name`0;".ToUpper())
        $at = -1
        for ($i = 8; $i -le $b.Length - $needle.Length; $i += 2) {
            $hit = $true
            for ($j = 0; $j -lt $needle.Length; $j++) { $x = $b[$i + $j]; if ($x -ne $needle[$j] -and $x -ne $low[$j] -and $x -ne $up[$j]) { $hit = $false; break } }
            if ($hit) { $at = $i; break }
        }
        if ($at -lt 0) { return }                       # local Group Policy does not manage this value
        $p = $at + $needle.Length                        # type(4) ';'(2) size(4) ';'(2) data
        if ($p + 16 -gt $b.Length) { return }
        if ([BitConverter]::ToInt32($b, $p) -ne 4 -or [BitConverter]::ToInt32($b, $p + 6) -ne 4) { Warn "Registry.pol: $Name is not a DWORD - set it in gpedit.msc"; return }
        if ([BitConverter]::ToInt32($b, $p + 12) -eq $Value) { return }
        Copy-Item $pol "$pol.cp-backup" -Force
        [BitConverter]::GetBytes($Value).CopyTo($b, $p + 12)
        [IO.File]::WriteAllBytes($pol, $b)
        $script:PolChanged = $true
        Ok "Local Group Policy file: $Name = $Value (so gpupdate does not put the old value back)"
    } catch { Warn "Registry.pol ($Name): $($_.Exception.Message)" }
}

# Mode 4 = download and install automatically. Mode 3 = download, ask to install. Mode 2 = notify only.
function Set-WindowsUpdatePolicy($Mode = 4) {
    $script:PolChanged = $false
    $auKey = 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; $au = "HKLM:\$auKey"
    $want = [ordered]@{ NoAutoUpdate = 0; AUOptions = [int]$Mode }
    if ($Mode -eq 4) { $want.ScheduledInstallDay = 0; $want.ScheduledInstallTime = 3 }
    foreach ($n in $want.Keys) { Set-Reg $au $n $want[$n] "Windows Update policy: $n = $($want[$n])"; Set-PolDword $auKey $n $want[$n] }
    Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name DisableWindowsUpdateAccess, DoNotConnectToWindowsUpdateInternetLocations, SetDisableUXWUAccess -ErrorAction SilentlyContinue
    foreach ($s in 'wuauserv', 'UsoSvc', 'BITS') {
        $svc = Get-Service $s -ErrorAction SilentlyContinue
        if ($svc -and $svc.StartType -eq 'Disabled') { sc.exe config $s start= demand | Out-Null; Ok "Windows Update service $s was disabled - set back to manual" }
    }
    if ($script:PolChanged) { gpupdate /target:computer /force | Out-Null }
    $now = Get-ItemProperty $au -ErrorAction SilentlyContinue
    if ($now.NoAutoUpdate -eq 0 -and $now.AUOptions -eq $Mode) { Ok "Checked: automatic updates on, option $Mode" }
    else { Warn "Windows Update policy did not stick (NoAutoUpdate=$($now.NoAutoUpdate), AUOptions=$($now.AUOptions)). Set it in gpedit.msc: Configure Automatic Updates = ENABLED, option $Mode. ('Disabled' there turns updates OFF.)" }
}

# Installs security / cumulative / quality updates. Never feature updates, upgrades or previews (READMEs forbid them).
function Install-SecurityUpdates {
    Info 'Searching Windows Update (this can take several minutes)...'
    $session = New-Object -ComObject Microsoft.Update.Session
    $found = $session.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
    $todo = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $found.Updates) {
        if ($u.Title -match 'Feature update|Upgrade to Windows|Preview|Insider') { Say "  [skip] $($u.Title)" DarkGray; continue }
        if (-not $u.EulaAccepted) { $u.AcceptEula() }
        [void]$todo.Add($u); Say "  [get]  $($u.Title)"
    }
    if (-not $todo.Count) { Ok 'No security or quality updates are waiting'; return }
    $dl = $session.CreateUpdateDownloader(); $dl.Updates = $todo; [void]$dl.Download()
    $ins = $session.CreateUpdateInstaller(); $ins.Updates = $todo; $res = $ins.Install()
    if ($res.ResultCode -eq 2) { Ok "Installed $($todo.Count) Windows update(s)" } else { Warn "Windows Update finished with result code $($res.ResultCode) (2 = success, 3 = some failed)" }
    if ($res.RebootRequired) { Warn 'A reboot is needed to finish Windows updates. Reboot, then check the scoring report did not lose anything.' }
}

# ==============================================================================
# 28. Default browser for all users (Chrome, Firefox or Edge)
# ==============================================================================
function Set-DefaultBrowser($Browser) {
    $b = switch -Regex ("$Browser") {
        'chrome'  { @{ ProgId = 'ChromeHTML'; Name = 'Google Chrome' } }
        'firefox' { @{ ProgId = (Get-ChildItem 'Registry::HKEY_CLASSES_ROOT' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'FirefoxHTML*' } | Select-Object -First 1).PSChildName; Name = 'Firefox' } }
        'edge'    { @{ ProgId = 'MSEdgeHTM'; Name = 'Microsoft Edge' } }
        default   { $null }
    }
    if (-not $b) { Warn "DefaultBrowser '$Browser' is not one of Chrome, Firefox, Edge - set it by hand in Settings > Apps > Default apps"; return }
    if (-not $b.ProgId -or -not (Test-Path "Registry::HKEY_CLASSES_ROOT\$($b.ProgId)")) { Warn "$($b.Name) is not registered - install or repair it (system-wide) first."; return }
    $xml = Join-Path $env:ProgramData 'cp-default-browser.xml'
    @('<?xml version="1.0" encoding="UTF-8"?>', '<DefaultAssociations>') +
        ('.htm', '.html', '.shtml', '.xht', '.xhtml', 'http', 'https' | ForEach-Object { "  <Association Identifier=`"$_`" ProgId=`"$($b.ProgId)`" ApplicationName=`"$($b.Name)`" />" }) +
        '</DefaultAssociations>' | Set-Content $xml -Encoding ASCII
    dism.exe /Online /Import-DefaultAppAssociations:"$xml" | Out-Null
    if ($LASTEXITCODE -eq 0) { Ok 'Default app associations imported (new users)' } else { Warn "dism import failed ($LASTEXITCODE)" }
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' DefaultAssociationsConfiguration $xml "Default browser policy -> $($b.Name) (applied at every sign-in, all users)" 'String'
    if ($b.ProgId -eq 'ChromeHTML') { Set-Reg 'HKLM:\SOFTWARE\Policies\Google\Chrome' DefaultBrowserSettingEnabled 1 'Chrome policy: Chrome is the default browser' }
    Info "Your session picks it up after sign-out. To set it right now: Settings > Apps > Default apps > $($b.Name) > Set default."
    if (-not $Auto) { Start-Process 'ms-settings:defaultapps' -ErrorAction SilentlyContinue }
}

# ==============================================================================
# 29. IIS (when the README makes the web server critical)
# ==============================================================================
$AppCmd = "$env:windir\System32\inetsrv\appcmd.exe"
function Invoke-AppCmd($Label) {
    $out = & $AppCmd @args 2>&1
    if ($LASTEXITCODE -eq 0) { Ok $Label } else { Warn "$Label : $out" }
}

# Lists Allow ACEs that give a non-admin principal write/delete/permission rights on a folder.
function Show-NonAdminWrite($Path) {
    $okSids = 'S-1-5-18', 'S-1-5-32-544', 'S-1-3-0', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'   # SYSTEM, Admins, CREATOR OWNER, TrustedInstaller
    $bad = (Get-Acl $Path).Access | Where-Object {
        $ace = $_
        $sid = try { $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { $ace.IdentityReference.Value }
        $ace.AccessControlType -eq 'Allow' -and $sid -notin $okSids -and ([int64]$ace.FileSystemRights -band 0x500D0156)
    }
    if ($bad) { $bad | ForEach-Object { Warn "$Path : $($_.IdentityReference) has $($_.FileSystemRights)" } } else { Say "  [=] $Path : only admins can write" DarkGreen }
}

function Get-IisRoots {
    if (-not (Test-Path $AppCmd)) { return @() }
    $roots = @(& $AppCmd list vdir /text:physicalPath | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) } | Where-Object { Test-Path $_ } | Sort-Object -Unique)
    if (-not $roots) { $roots = @('C:\inetpub\wwwroot') }   # never let Get-ChildItem fall back to the current folder
    $roots
}

function Set-IIS {
    if (-not (Test-Path $AppCmd)) { Warn 'IIS is not installed (appcmd.exe missing). If the README says IIS is critical: Server Manager > Add Roles > Web Server (IIS).'; return }
    foreach ($s in 'WAS', 'W3SVC') { sc.exe config $s start= auto | Out-Null; Start-Service $s -ErrorAction SilentlyContinue }
    if ((Get-Service W3SVC).Status -eq 'Running') { Ok 'IIS (W3SVC + WAS) automatic and running' } else { Warn 'W3SVC is not running - check services.msc / Event Viewer' }
    if (-not (Get-NetFirewallRule -DisplayName 'CP - IIS HTTP/HTTPS' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName 'CP - IIS HTTP/HTTPS' -Direction Inbound -Protocol TCP -LocalPort 80, 443 -Action Allow | Out-Null
        Ok 'Firewall allows inbound HTTP/HTTPS (80, 443)'
    }

    Head 'Sites'
    & $AppCmd list site | ForEach-Object { Say "  $_" }
    $vdirs = @(& $AppCmd list vdir /text:name | ForEach-Object { $_.TrimEnd('/') })
    $roots = Get-IisRoots
    $webConfigs = @(Get-ChildItem $roots -Recurse -Filter web.config -Force -ErrorAction SilentlyContinue)

    Head 'Directory browsing OFF'
    Invoke-AppCmd 'Directory browsing disabled (server level)' set config /section:system.webServer/directoryBrowse /enabled:false
    foreach ($v in $vdirs) { Invoke-AppCmd "Directory browsing disabled on $v" set config "$v" /section:system.webServer/directoryBrowse /enabled:false }

    Head 'IIS hardening'
    Invoke-AppCmd 'Server header removed' set config /section:system.webServer/security/requestFiltering /removeServerHeader:true
    Invoke-AppCmd 'Request filtering: double escaping blocked' set config /section:system.webServer/security/requestFiltering /allowDoubleEscaping:false
    Invoke-AppCmd 'Detailed errors only for local requests' set config /section:system.webServer/httpErrors /errorMode:DetailedLocalOnly
    Invoke-AppCmd 'IIS logging on' set config /section:system.webServer/httpLogging /dontLog:false
    Invoke-AppCmd 'Handlers: Read + Script only (no Write/Execute)' set config /section:system.webServer/handlers /accessPolicy:Read,Script
    Invoke-AppCmd 'ASP.NET debug compilation off' set config /commit:WEBROOT /section:system.web/compilation /debug:false
    Invoke-AppCmd 'ASP.NET trace off' set config /commit:WEBROOT /section:system.web/trace /enabled:false
    # ASP.NET's own error pages are a separate setting from IIS httpErrors: mode="Off" shows stack traces to everyone.
    Invoke-AppCmd 'ASP.NET customErrors: RemoteOnly (no stack traces to visitors)' set config /commit:WEBROOT /section:system.web/customErrors /mode:RemoteOnly
    if ((& $AppCmd list config /section:system.webServer/httpProtocol) -match 'X-Powered-By') {
        Invoke-AppCmd 'X-Powered-By header removed' set config /section:system.webServer/httpProtocol '/-customHeaders.[name=''X-Powered-By'']'
    }
    # Site and sub-folder web.config files override the server level, so fix them too (a copy of each goes to C:\cp-quarantine).
    foreach ($wc in $webConfigs) {
        $t = Get-Content $wc.FullName -Raw
        $n = $t -replace '(<directoryBrowse[^>]*enabled\s*=\s*")true"', '$1false"' `
                -replace '(<compilation[^>]*debug\s*=\s*")true"', '$1false"' `
                -replace '(<customErrors[^>]*mode\s*=\s*")Off"', '$1RemoteOnly"' `
                -replace '(<trace[^>]*enabled\s*=\s*")true"', '$1false"'
        if ($n -ne $t) {
            New-Item 'C:\cp-quarantine' -ItemType Directory -Force | Out-Null
            Copy-Item -LiteralPath $wc.FullName (Join-Path 'C:\cp-quarantine' (($wc.FullName -replace '[:\\]', '_') + '.before')) -Force
            $n | Set-Content $wc.FullName -Encoding UTF8
            Ok "Fixed directoryBrowse / debug / customErrors / trace in $($wc.FullName)"
        }
    }
    foreach ($v in $vdirs) { Say "  [=] $v : $((& $AppCmd list config "$v" /section:system.webServer/directoryBrowse) -join ' ')" DarkGreen }
    Info "Anonymous auth: $((& $AppCmd list config /section:system.webServer/security/authentication/anonymousAuthentication) -join ' ')"
    Info 'Anonymous user should be IUSR (or blank = app pool identity), never an admin account.'

    Head 'Application pools (must not run as LocalSystem / an admin)'
    foreach ($p in & $AppCmd list apppool /text:name) {
        $type = & $AppCmd list apppool "$p" /text:processModel.identityType
        $user = & $AppCmd list apppool "$p" /text:processModel.userName
        Say "  $p : $type $user"
        if ($type -in 'LocalSystem', 'SpecificUser' -and (Ask "App pool '$p' runs as $type $user - switch to ApplicationPoolIdentity?" $true)) {
            Invoke-AppCmd "App pool $p -> ApplicationPoolIdentity" set apppool "$p" /processModel.identityType:ApplicationPoolIdentity
        }
    }
    & $AppCmd recycle apppool /apppool.name:* 2>&1 | Out-Null

    Head 'Web root permissions'
    $roots | ForEach-Object { Show-NonAdminWrite $_ }
    Info 'Fix any non-admin write with: icacls <path> /remove:g <user>  (keep IIS_IUSRS/IUSR read)'

    Head 'Possible web shells in site folders'
    $shells = Get-ChildItem $roots -Recurse -File -Force -Include *.asp, *.aspx, *.ashx, *.asmx, *.php, *.jsp, *.cfm, *.cgi, *.pl, *.py, *.ps1, *.bat -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -lt 5MB -and (Select-String -LiteralPath $_.FullName -Quiet -Pattern 'cmd\.exe|Process\.Start|ProcessStartInfo|WScript\.Shell|eval\s*\(|shell_exec|passthru|system\s*\(|base64_decode|Runtime\.getRuntime|powershell') }
    # Moved, not deleted: if a real page got caught, copy it back from C:\cp-quarantine.
    Select-Items $shells { $_.FullName } { CanDestroy } | ForEach-Object { Move-ToQuarantine $_.FullName }
}

# IIS needs IIS_IUSRS in "Log on as a batch job" and "Impersonate a client" (CIS allows it).
function Set-UserRightsIIS {
    Set-UserRights
    if ($IsDC) { return }
    $A = '*S-1-5-32-544'; $IIS = '*S-1-5-32-568'
    Set-SecPolicy -Section 'Privilege Rights' @{ SeBatchLogonRight = "$A,$IIS"; SeImpersonatePrivilege = "$A,*S-1-5-19,*S-1-5-20,*S-1-5-6,$IIS" }
}

# ==============================================================================
# 30. Shares the README requires: Everyone = read, only Administrators can change the contents
#     Config:  Shares = @( @{ Name = 'Handbook'; Path = 'C:\Shares\Handbook' } )
# ==============================================================================
function Set-ReadmeShare($Share) {
    $name = $Share.Name; $path = "$($Share.Path)".TrimEnd('\')
    if (-not $name -or -not $path) { Warn 'config: each entry in Shares needs Name and Path'; return }
    $everyone = ([Security.Principal.SecurityIdentifier]'S-1-1-0').Translate([Security.Principal.NTAccount]).Value
    $admins   = ([Security.Principal.SecurityIdentifier]'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value
    if (-not (Test-Path $path)) {
        Warn "$path is missing! The README says it must be shared (check the Recycle Bin / forensics)."
        if (-not (Ask 'Create the empty folder so the share works?' $true)) { return }
        New-Item $path -ItemType Directory -Force | Out-Null
    }
    sc.exe config LanmanServer start= auto | Out-Null; Start-Service LanmanServer -ErrorAction SilentlyContinue
    Set-SmbServerConfiguration -EnableSMB2Protocol $true -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
    Enable-NetAdapterBinding -Name * -ComponentID ms_server -ErrorAction SilentlyContinue
    Get-NetFirewallRule -Group '@FirewallAPI.dll,-28502' -Direction Inbound -ErrorAction SilentlyContinue |
        Where-Object { ($_ | Get-NetFirewallPortFilter).LocalPort -contains '445' } | Enable-NetFirewallRule
    Ok 'Server service on, SMB2 on, File and Printer Sharing bound + firewall SMB-In open'

    $sh = Get-SmbShare -Name $name -ErrorAction SilentlyContinue
    if ($sh -and $sh.Path.TrimEnd('\') -ne $path) { Warn "$name share pointed at $($sh.Path) - recreating"; Remove-SmbShare $name -Force; $sh = $null }
    if (-not $sh) { New-SmbShare -Name $name -Path $path -ReadAccess $everyone -FullAccess $admins | Out-Null; Ok "Created share $name -> $path" }

    Head "Share $name permissions: Everyone = Read, Administrators = Full"
    foreach ($a in Get-SmbShareAccess -Name $name) {
        if ($a.AccessControlType -eq 'Deny') {
            Unblock-SmbShareAccess -Name $name -AccountName $a.AccountName -Force | Out-Null; Ok "Removed share DENY for $($a.AccountName)"
        } elseif ($a.AccountName -ne $admins -and -not ($a.AccountName -eq $everyone -and $a.AccessRight -eq 'Read')) {
            Revoke-SmbShareAccess -Name $name -AccountName $a.AccountName -Force | Out-Null; Ok "Revoked share $($a.AccessRight) for $($a.AccountName)"
        }
    }
    Grant-SmbShareAccess -Name $name -AccountName $everyone -AccessRight Read -Force | Out-Null
    Grant-SmbShareAccess -Name $name -AccountName $admins -AccessRight Full -Force | Out-Null
    Get-SmbShareAccess -Name $name | ForEach-Object { Say "  [=] $($_.AccountName) $($_.AccessControlType) $($_.AccessRight)" DarkGreen }

    Head "NTFS permissions on ${path}: Administrators + SYSTEM = Full, Everyone = Read"
    icacls $path /setowner '*S-1-5-32-544' /T /C /Q | Out-Null
    icacls $path /reset /Q | Out-Null
    icacls $path /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-1-0:(OI)(CI)RX' /Q | Out-Null
    if ($LASTEXITCODE -eq 0) { Ok "$name folder ACL: only Administrators can change contents" } else { Warn "icacls failed ($LASTEXITCODE)" }
    if (Get-ChildItem $path -Force -ErrorAction SilentlyContinue) { icacls "$path\*" /reset /T /C /Q | Out-Null; Ok "$name files now inherit the folder ACL" }
    Show-NonAdminWrite $path
}

# ==============================================================================
# 31. VMware copy and paste, and a final check
# ==============================================================================
# Copy/paste into the VM needs the per-user VMware Tools process; it was missing on the Windows 11 image.
function Start-VmwareUserAgent {
    $exe = "$env:ProgramFiles\VMware\VMware Tools\vmtoolsd.exe"
    if (-not (Test-Path $exe)) { return }
    $running = Get-CimInstance Win32_Process -Filter "Name='vmtoolsd.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match '-n\s+vmusr' }
    if ($running) { Say '  [=] VMware Tools user agent running (copy and paste works)' DarkGreen; return }
    Start-Process -FilePath $exe -ArgumentList '-n', 'vmusr' -ErrorAction SilentlyContinue
    Ok 'Started the VMware Tools user agent (copy and paste into the VM)'
}

# Re-reads the settings that matter most after everything else has run. Scores can lag a minute or two behind.
function Invoke-FinalCheck {
    $off = @(Get-NetFirewallProfile | Where-Object { -not $_.Enabled })
    if ($off) { Warn "Firewall is OFF for: $($off.Name -join ', ')" } else { Ok 'Checked: firewall on for all profiles' }
    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
        if ($mp -and $mp.RealTimeProtectionEnabled) { Ok 'Checked: Defender real-time protection on' } else { Warn 'Defender real-time protection is NOT on' }
        $left = @((Get-MpPreference).ExclusionExtension) + @((Get-MpPreference).ExclusionPath) + @((Get-MpPreference).ExclusionProcess) | Where-Object { $_ -and $_ -notmatch 'CyberPatriot' }
        if ($left) { Warn "Defender exclusions still present: $($left -join ', ') (set by policy? check gpedit.msc > Microsoft Defender Antivirus > Exclusions)" }
    }
    foreach ($s in $GoodServices) {
        $svc = Get-Service $s -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Running') { Warn "Required service $s is $($svc.Status)" }
    }
    $au = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue
    if ($au.NoAutoUpdate -eq 1) { Warn 'Automatic updates are turned OFF by policy (NoAutoUpdate = 1)' }
    if ("$($Cfg.RemoteDesktop)" -match '^(required|y)') {
        if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server').fDenyTSConnections -eq 0) { Ok 'Checked: Remote Desktop is on (README requires it)' } else { Warn 'Remote Desktop is OFF but the README requires it' }
    }
    foreach ($sh in @($Cfg.Shares)) { if ($sh.Name -and -not (Get-SmbShare -Name $sh.Name -ErrorAction SilentlyContinue)) { Warn "README share $($sh.Name) does not exist" } }
    foreach ($n in @($Cfg.Admins) + @($Cfg.Users)) { if ($n -and -not $IsDC -and -not (Get-LocalUser -Name $n -ErrorAction SilentlyContinue)) { Warn "README account $n does not exist" } }
    Info 'Give the scoring report a minute or two, then read it. A check that dropped during an install often comes back on its own.'
}

# ==============================================================================
# Menu
# ==============================================================================
$Menu = [ordered]@{
    '1'  = 'Users: remove/create/demote per README, passwords', { Invoke-UserAudit }
    '2'  = 'Groups: edit members (Remote Desktop Users, etc.)', { Edit-Groups }
    '3'  = 'Password + lockout policy', { Set-PasswordPolicy }
    '4'  = 'Security options (anon SAM, blank pw, UAC, SMB...)', { Set-SecurityOptions }
    '5'  = 'Firewall, Defender, audit policy', { Set-Protection }
    '6'  = 'Remote Desktop / Remote Assistance', { Set-RemoteAccess }
    '7'  = 'Services (FTP, Telnet, RemoteRegistry...)', { Set-Services }
    '8'  = 'Prohibited software', { Remove-BadSoftware }
    '9'  = 'Prohibited / media files', { Find-BadFiles }
    '10' = 'Review: shares, autoruns, tasks, backdoors, hosts, ports', { Invoke-Review }
    '11' = 'Windows features (SMBv1, Telnet, TFTP, PSv2...)', { Disable-BadFeatures }
    '12' = 'Windows Update: automatic (policy option 4, survives gpupdate)', { Set-WindowsUpdatePolicy 4 }
    '13' = 'App updates (pick which apps, runs in a new window)', { Update-Apps }
    '14' = 'Install winget', { Install-Winget }
    '15' = 'Forensics toolkit', { Invoke-Forensics }
    '16' = 'User rights assignment (secpol)', { Set-UserRights }
    '17' = 'Network adapters (IPv6, bindings, NetBIOS, DNS registration)', { Set-NetworkAdapters }
    '18' = 'Action Center / Security Center notifications on', { Set-ActionCenter }
    '20' = 'Default browser for all users (Chrome / Firefox / Edge)', { Set-DefaultBrowser $(if ($Cfg.DefaultBrowser) { $Cfg.DefaultBrowser } else { Read-Host '  Browser (chrome / firefox / edge)' }) }
    '21' = 'Groups the README asks for (from the config)', { Set-ReadmeGroups }
    '22' = 'Program folders that are not installed programs', { Find-UnknownPrograms }
    '23' = 'Firewall rules left by removed / prohibited programs', { Remove-StaleFirewallRules }
    '24' = 'Files containing passwords or personal data', { Find-SensitiveFiles (@('C:\Users') + @($Cfg.Shares | ForEach-Object { $_.Path }) + @(Get-IisRoots)) @($Cfg.Shares | ForEach-Object { $_.Path }) }
    '25' = 'Backdoors: renamed tools in System32 + listening ports', { Find-RenamedTools; Show-Listeners }
    '26' = 'Older copies of updated programs', { Remove-OldVersions }
    '27' = 'Install Windows security updates (no feature updates; new window)', { Start-InNewWindow 'Windows security updates' 'Install-SecurityUpdates' }
    '29' = 'IIS hardening (only when the web server is critical)', { Set-IIS }
    '30' = 'README shares (from the config)', { foreach ($sh in @($Cfg.Shares)) { Set-ReadmeShare $sh } }
    '31' = 'Final check + VMware copy/paste agent', { Start-VmwareUserAgent; Invoke-FinalCheck }
    'C'  = 'Load a README config (cp-config.psd1)', { $p = Read-Host '  Path [.\cp-config.psd1]'; if (-not $p) { $p = Join-Path $Here 'cp-config.psd1' }; Use-CpConfig $p; Ok "Loaded $p"; [void](Test-CpConfig) }
    'A'  = 'Quick run: 3, 4, 5, 6', { Set-PasswordPolicy; Set-SecurityOptions; Set-Protection; Set-RemoteAccess }
}

function Show-Menu($Title = 'CYBERPATRIOT HARDENING TOOLKIT', $Note) {
    while ($true) {
        Clear-Host
        Say ('  ' + '=' * 62) DarkCyan
        Say "   $Title" White
        Say "   $($OS.Caption)  |  $env:COMPUTERNAME  |  $env:USERNAME$(if ($IsDC) { '  |  DOMAIN CONTROLLER' })" DarkGray
        Say "   Log: $Log" DarkGray
        if ($Note) { $Note | ForEach-Object { Say "   $_" Yellow } }
        Say ('  ' + '=' * 62) DarkCyan
        foreach ($k in $Menu.Keys) { Say ("   {0,3}  {1}" -f $k, $Menu[$k][0]) }
        Say '     Q  Quit'
        $c = (Read-Host "`n  Select").Trim().ToUpper()
        if ($c -eq 'Q') { break }
        if ($Menu.Contains($c)) {
            Say "`n  ==== $($Menu[$c][0]) ====" Magenta
            try { & $Menu[$c][1] } catch { Warn $_.Exception.Message }
            Read-Host "`n  Done. Press Enter for menu" | Out-Null
        }
    }
}

# Dot-sourced by the round-specific scripts: they load these functions and show their own menu.
if ($MyInvocation.InvocationName -ne '.') { Show-Menu }
