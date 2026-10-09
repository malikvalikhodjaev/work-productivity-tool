[CmdletBinding()]
param([switch]$Remove)
$ErrorActionPreference = 'Stop'
$startupDirectory = [Environment]::GetFolderPath('Startup')
$startupFile = Join-Path $startupDirectory 'Indicators-Work-Dashboard.vbs'
if ($Remove) {
    if (Test-Path -LiteralPath $startupFile) { Remove-Item -LiteralPath $startupFile }
    Write-Host 'Dashboard autostart removed.'
    exit 0
}
$dashboardLauncher = (Join-Path $PSScriptRoot 'Start-Dashboard.ps1').Replace("'", "''")
$startupCommand = "& '$dashboardLauncher' -NoBrowser"
$startupEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($startupCommand))
$startupScript = "Set dashboardShell = CreateObject(""WScript.Shell"")`r`ndashboardShell.Run ""powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $startupEncoded"", 0, False`r`n"
New-Item -ItemType Directory -Path $startupDirectory -Force | Out-Null
[System.IO.File]::WriteAllText($startupFile, $startupScript, [System.Text.Encoding]::ASCII)
Write-Host 'Dashboard will start hidden when this Windows user signs in.'
