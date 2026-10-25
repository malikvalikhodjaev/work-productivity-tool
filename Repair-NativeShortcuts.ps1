[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ApplicationDirectory,
    [string]$LauncherScript,
    [string]$ShortcutDirectory,
    [string]$BackupDirectory
)
$ErrorActionPreference = 'Stop'
$iwAppDirectory = [IO.Path]::GetFullPath($ApplicationDirectory)
$iwExecutable = Join-Path $iwAppDirectory 'indicators_work.exe'
$iwSourceIcon = Join-Path $iwAppDirectory 'data\flutter_assets\assets\iw.ico'
if (-not (Test-Path -LiteralPath $iwExecutable -PathType Leaf)) { throw 'Native application executable not found.' }
if (-not (Test-Path -LiteralPath $iwSourceIcon -PathType Leaf)) { throw 'Bundled application icon not found.' }
$iwIconHash = (Get-FileHash -LiteralPath $iwSourceIcon -Algorithm SHA256).Hash.ToLowerInvariant()
# A new path when the artwork changes avoids reusing an older cached EXE icon.
$iwIcon = Join-Path $iwAppDirectory ('pomodoro-club-' + $iwIconHash.Substring(0,16) + '.ico')
if (-not (Test-Path -LiteralPath $iwIcon)) { Copy-Item -LiteralPath $iwSourceIcon -Destination $iwIcon }
if ((Get-FileHash -LiteralPath $iwIcon -Algorithm SHA256).Hash.ToLowerInvariant() -ne $iwIconHash) { throw 'Shortcut icon checksum mismatch.' }
if ($LauncherScript) { $iwLauncher = [IO.Path]::GetFullPath($LauncherScript) } else { $iwLauncher = $null }
if (-not $BackupDirectory) { $BackupDirectory = Join-Path (Split-Path -Parent $iwAppDirectory) ('shortcut-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')) }
$iwBackup = [IO.Path]::GetFullPath($BackupDirectory)
$iwFolders = @(
    (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'Indicators & Work Dashboard'),
    $(if ($ShortcutDirectory) { [IO.Path]::GetFullPath($ShortcutDirectory) } else { [Environment]::GetFolderPath('Desktop') })
)
if (-not ('IndicatorsWork.ShortcutShell' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace IndicatorsWork {
    public static class ShortcutShell {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern void SHChangeNotify(int eventId, uint flags, string item1, IntPtr item2);
        public static void Updated(string path) {
            // SHCNE_UPDATEITEM; SHCNF_PATHW | SHCNF_FLUSH.
            SHChangeNotify(0x00002000, 0x1005, path, IntPtr.Zero);
        }
    }
}
'@
}
$iwShell = New-Object -ComObject WScript.Shell
$iwChanges = @()
foreach ($iwFolder in ($iwFolders | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $iwFolder -PathType Container)) { continue }
    foreach ($iwFile in (Get-ChildItem -LiteralPath $iwFolder -Filter '*.lnk' -File)) {
        $iwLink = $iwShell.CreateShortcut($iwFile.FullName)
        $iwDirect = $iwLink.TargetPath -and [IO.Path]::GetFullPath($iwLink.TargetPath) -eq $iwExecutable
        $iwViaLauncher = $iwLauncher -and ([IO.Path]::GetFileName($iwLink.TargetPath) -ieq 'wscript.exe') -and $iwLink.Arguments -ceq ('"' + $iwLauncher + '"')
        if (-not ($iwDirect -or $iwViaLauncher)) { continue }
        $iwLocation = $iwIcon + ',0'
        if ($iwLink.IconLocation -ne $iwLocation) {
            New-Item -ItemType Directory -Force -Path $iwBackup | Out-Null
            $iwSavedLink = Join-Path $iwBackup ([guid]::NewGuid().ToString() + '.lnk')
            Copy-Item -LiteralPath $iwFile.FullName -Destination $iwSavedLink
            $iwOldTarget = $iwLink.TargetPath
            $iwOldArguments = $iwLink.Arguments
            $iwOldIcon = $iwLink.IconLocation
            try {
                $iwLink.IconLocation = $iwLocation
                $iwLink.Save()
                $iwReadBack = $iwShell.CreateShortcut($iwFile.FullName)
                if ($iwReadBack.TargetPath -cne $iwOldTarget -or $iwReadBack.Arguments -cne $iwOldArguments -or $iwReadBack.IconLocation -ne $iwLocation) { throw 'Shortcut verification failed.' }
            } catch {
                Copy-Item -LiteralPath $iwSavedLink -Destination $iwFile.FullName -Force
                throw
            }
            $iwChanges += [pscustomobject]@{shortcut=$iwFile.FullName;previousIcon=$iwOldIcon;icon=$iwLocation;backup=$iwSavedLink;targetPreserved=$true}
        }
        [IndicatorsWork.ShortcutShell]::Updated($iwFile.FullName)
    }
}
[IndicatorsWork.ShortcutShell]::Updated($iwExecutable)
[pscustomobject]@{icon=$iwIcon;iconSha256=$iwIconHash;changedShortcuts=$iwChanges;applicationRestarted=$false} | ConvertTo-Json -Depth 5
