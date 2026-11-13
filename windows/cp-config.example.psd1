# cp-config.psd1 - fill this in from the README on the image's desktop, BEFORE running CP-Run.ps1.
# Copy this file to cp-config.psd1 (same folder as CP-Run.ps1).
# Format: PowerShell data. Lists are @('a', 'b'). Text is 'in single quotes'. True/false are $true / $false.
# Every value must come from the README. Leave a list empty - @() - when the README says nothing.
@{
    # ---- README: "Authorized Administrators" - account names only (no "(you)", no passwords) ----
    Admins = @('pparker', 'tstark')

    # ---- README: "Authorized Users" ----
    Users = @('bbanner', 'swilson')

    # ---- README: "Critical Services" ----
    # Keywords: 'RDP', 'IIS', 'SMB', 'FTP', 'DNS', 'SSH', 'Print', 'WinRM', 'SNMP', 'Telnet', 'SMTP'
    # or an exact Windows service name. These are never stopped and are started if found stopped.
    CriticalServices = @('RDP')

    # ---- Remote Desktop: 'required', 'off', or 'leave' (set to 'required' automatically when RDP is critical) ----
    RemoteDesktop = 'leave'

    # ---- README: software that must stay. Part of the name as it appears in Settings > Apps is enough. ----
    # Anything listed here is never uninstalled or quarantined, even if it looks like a hacking tool (Wireshark, Nmap).
    RequiredApps = @('Google Chrome', 'Notepad++', 'LibreOffice', 'Thunderbird', '7-Zip')

    # ---- README apps to update, as winget ids. Built-in direct downloads (no winget needed) exist for: ----
    # Google.Chrome, Mozilla.Firefox, Mozilla.Thunderbird, TheDocumentFoundation.LibreOffice, Notepad++.Notepad++,
    # 7zip.7zip, OpenRocket.OpenRocket. Other ids need winget on the image.
    UpdateApps = @('Google.Chrome', 'Notepad++.Notepad++', '7zip.7zip')

    # ---- README: default browser for all users: 'Chrome', 'Firefox', 'Edge', or '' to leave alone ----
    DefaultBrowser = ''

    # ---- README: groups to create and who to add.  'Group name' = @('member', 'member') ----
    Groups = @{}

    # ---- README: folders that must stay shared. Everyone gets read; only Administrators can change the contents. ----
    # Example: @( @{ Name = 'Handbook'; Path = 'C:\Shares\Handbook' } )
    Shares = @()

    # Other share names that must not be removed (shares above are kept automatically).
    KeepShares = @()

    # Folders whose contents are business files: reported, never deleted or quarantined (share paths are kept automatically).
    KeepPaths = @()

    # ---- Forensics ----
    # Leave $false until every Forensics Question is answered and saved. While $false, the automatic run does not
    # delete users, files or programs, and does not kill or quarantine backdoors.
    ForensicsDone = $false

    # ---- Decisions after reading the -Audit output or the error report ----
    RemoveSoftware = @()     # part of a program's name: uninstall it even though the built-in lists do not know it
    RemoveFiles = @()        # full paths to move to C:\cp-quarantine

    # ---- Passwords ----
    ResetPasswords = $true   # give every README account except yours one new strong password (printed at the end)
    NewPassword = ''         # '' = generate one

    # ---- Windows Update ----
    WindowsUpdateMode = 4          # 4 = download and install automatically, 3 = download and ask, 2 = notify only
    InstallWindowsUpdates = $false # $true = also install security/quality updates now (never feature updates). Slow.

    # ---- Other ----
    DisableOneDrive = $true              # $false if the README needs OneDrive
    QuarantineSensitiveInShares = $true  # move files containing passwords out of README shares (to C:\cp-quarantine)
    ScanRoots = @()                      # @() = whole system drive except Windows and Program Files
}
