# Example config: CP19 Round 2, Windows Server 2022 (lab intranet server).
# The account lists come from the original CP-Round2-Server2022.ps1. Check them against the README before use.
@{
    Admins = @('pparker', 'tstark', 'ppotts', 'hhogan', 'nfury', 'mhill', 'pcoulson')
    Users  = @('bbanner', 'swilson', 'sstrange', 'slang', 'cdanvers', 'okoye', 'kbishop', 'ybelova', 'jfoster', 'nleeds', 'mjwatson', 'jtorres', 'pcarter')

    # README: IIS is critical, and the Handbook share must stay available.
    CriticalServices = @('IIS', 'SMB')
    RemoteDesktop = 'leave'

    RequiredApps = @('Google Chrome', 'Notepad++', 'WinSCP', '7-Zip')
    UpdateApps   = @('Google.Chrome', 'Notepad++.Notepad++', 'WinSCP.WinSCP', '7zip.7zip')   # WinSCP has no direct download: needs winget or a manual update
    DefaultBrowser = 'Chrome'

    Groups = @{}
    Shares = @( @{ Name = 'Handbook'; Path = 'C:\Shares\Handbook' } )
    KeepShares = @()
    KeepPaths = @()

    ForensicsDone = $false

    RemoveSoftware = @()
    RemoveFiles = @()
    ResetPasswords = $true
    NewPassword = ''
    WindowsUpdateMode = 4
    InstallWindowsUpdates = $false
    DisableOneDrive = $true
    QuarantineSensitiveInShares = $true   # staff.csv (passwords) in the Handbook share was a scored item
    ScanRoots = @()
}
