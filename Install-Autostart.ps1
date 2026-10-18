[CmdletBinding()]
param([switch]$Remove, [switch]$ServerOnly)
$ErrorActionPreference = 'Stop'
$startupDirectory = [Environment]::GetFolderPath('Startup')
$startupFile = Join-Path $startupDirectory 'Indicators-Work-Dashboard.vbs'
if (Test-Path -LiteralPath $startupFile) {
    $startupBackupDirectory = Join-Path $PSScriptRoot 'outputs\autostart-backups'
    New-Item -ItemType Directory -Path $startupBackupDirectory -Force | Out-Null
    Copy-Item -LiteralPath $startupFile -Destination (Join-Path $startupBackupDirectory ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString() + '.vbs'))
}
if ($Remove) {
    if (Test-Path -LiteralPath $startupFile) { Remove-Item -LiteralPath $startupFile }
    Write-Host 'Dashboard autostart removed.'
    exit 0
}
$startupNative = -not $ServerOnly -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'outputs\native-windows\indicators_work.exe'))
$startupLauncherName = if ($startupNative) { 'Start-Native.ps1' } else { 'Start-Dashboard.ps1' }
$dashboardLauncher = (Join-Path $PSScriptRoot $startupLauncherName).Replace("'", "''")
$startupCommand = "& '$dashboardLauncher'" + $(if ($startupNative) { '' } else { ' -NoBrowser' })
$startupEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($startupCommand))
$startupScript = "Set dashboardShell = CreateObject(""WScript.Shell"")`r`ndashboardShell.Run ""powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $startupEncoded"", 0, False`r`n"
New-Item -ItemType Directory -Path $startupDirectory -Force | Out-Null
[System.IO.File]::WriteAllText($startupFile, $startupScript, [System.Text.Encoding]::ASCII)
if ($startupNative) { Write-Host 'Indicators & Work app and local server will start when this Windows user signs in.' }
else { Write-Host 'Dashboard server will start hidden when this Windows user signs in.' }
