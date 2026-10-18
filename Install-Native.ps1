[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ReleaseDirectory, [string]$ShortcutDirectory, [switch]$SkipStartMenu, [switch]$SkipAutostart)
$ErrorActionPreference = 'Stop'
$nativeRelease = [IO.Path]::GetFullPath($ReleaseDirectory)
if (-not (Test-Path -LiteralPath (Join-Path $nativeRelease 'indicators_work.exe'))) { throw 'Release folder must contain indicators_work.exe and its runtime files.' }
$nativeTarget = Join-Path $PSScriptRoot 'outputs\native-windows'
if (Test-Path -LiteralPath $nativeTarget) {
    $nativeOldProcesses = Get-Process -Name indicators_work -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $nativeTarget 'indicators_work.exe') }
    if ($nativeOldProcesses) { throw 'Exit Indicators & Work from the tray before updating the installed files.' }
    $nativeBackup = Join-Path $PSScriptRoot ('outputs\native-windows-before-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip')
    Compress-Archive -LiteralPath $nativeTarget -DestinationPath $nativeBackup
}
New-Item -ItemType Directory -Path $nativeTarget -Force | Out-Null
foreach ($nativeFile in Get-ChildItem -LiteralPath $nativeRelease -Recurse -File) {
    $nativeRelative = $nativeFile.FullName.Substring($nativeRelease.TrimEnd('\').Length + 1)
    $nativeDestination = Join-Path $nativeTarget $nativeRelative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $nativeDestination) | Out-Null
    Copy-Item -LiteralPath $nativeFile.FullName -Destination $nativeDestination -Force
}
$nativeLauncher = Join-Path $PSScriptRoot 'Start-Native.ps1'
$nativeSupport = Join-Path $PSScriptRoot 'outputs\native-launcher'
New-Item -ItemType Directory -Force -Path $nativeSupport | Out-Null
$nativeCommand = "& '" + $nativeLauncher.Replace("'", "''") + "'"
$nativeEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($nativeCommand))
$nativeVbs = Join-Path $nativeSupport 'launch.vbs'
[IO.File]::WriteAllText($nativeVbs, "Set appShell = CreateObject(""WScript.Shell"")`r`nappShell.Run ""powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $nativeEncoded"", 0, False`r`n", [Text.Encoding]::ASCII)
$nativeDestinations = @($(if ($ShortcutDirectory) { [IO.Path]::GetFullPath($ShortcutDirectory) } else { [Environment]::GetFolderPath('Desktop') }))
if (-not $SkipStartMenu) { $nativeDestinations += Join-Path ([Environment]::GetFolderPath('Programs')) 'Indicators & Work Dashboard' }
$nativeShell = New-Object -ComObject WScript.Shell
foreach ($nativeFolder in $nativeDestinations) {
    New-Item -ItemType Directory -Force -Path $nativeFolder | Out-Null
    $nativeLink = Join-Path $nativeFolder 'Indicators & Work Dashboard.lnk'
    if (Test-Path -LiteralPath $nativeLink) { Copy-Item -LiteralPath $nativeLink -Destination (Join-Path $nativeSupport ('previous-' + [guid]::NewGuid().ToString() + '.lnk')) }
    $nativeShortcut = $nativeShell.CreateShortcut($nativeLink)
    $nativeShortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
    $nativeShortcut.Arguments = '"' + $nativeVbs + '"'
    $nativeShortcut.WorkingDirectory = $PSScriptRoot
    $nativeShortcut.IconLocation = (Join-Path $nativeTarget 'indicators_work.exe') + ',0'
    $nativeShortcut.Description = 'Indicators & Work Dashboard — native Windows app'
    $nativeShortcut.Save()
    Write-Output $nativeLink
}
if (-not $SkipAutostart) { & (Join-Path $PSScriptRoot 'Install-Autostart.ps1') }
