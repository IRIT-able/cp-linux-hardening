# Example config: CP19 Round 2, Windows 11 (front-desk workstation).
# The account lists come from the original CP-Round2-Win11.ps1. Check them against the README before use.
@{
    Admins = @('pparker', 'tstark', 'ppotts', 'hhogan', 'nfury', 'mhill', 'pcoulson')
    Users  = @('bbanner', 'swilson', 'sstrange', 'slang', 'cdanvers', 'okoye', 'kbishop', 'ybelova', 'jfoster', 'nleeds', 'mjwatson', 'jtorres', 'pcarter')

    # README: Remote Desktop is a critical service.
    CriticalServices = @('RDP')
    RemoteDesktop = 'required'

    RequiredApps = @('Google Chrome', 'Notepad++', 'LibreOffice', 'Thunderbird', 'OpenRocket', '7-Zip')
    UpdateApps   = @('Google.Chrome', 'Notepad++.Notepad++', 'TheDocumentFoundation.LibreOffice', 'Mozilla.Thunderbird', 'OpenRocket.OpenRocket', '7zip.7zip')
    DefaultBrowser = 'Chrome'

    Groups = @{}
    Shares = @()
    KeepShares = @()
    KeepPaths = @()

    ForensicsDone = $false

    RemoveSoftware = @()
    RemoveFiles = @()
    ResetPasswords = $true
    NewPassword = ''
    WindowsUpdateMode = 4
    InstallWindowsUpdates = $false   # README: no feature updates. $true installs security/quality updates only.
    DisableOneDrive = $true
    QuarantineSensitiveInShares = $true
    ScanRoots = @()
}
