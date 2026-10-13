[CmdletBinding()]
param([string]$ShortcutDirectory, [switch]$SkipStartMenu)
$ErrorActionPreference = 'Stop'
$desktopLauncher = Join-Path $PSScriptRoot 'Start-Desktop.ps1'
if (-not (Test-Path -LiteralPath $desktopLauncher)) { throw 'Start-Desktop.ps1 is missing.' }
$desktopSupport = Join-Path $PSScriptRoot 'outputs\windows'
New-Item -ItemType Directory -Path $desktopSupport -Force | Out-Null
$desktopIcon = Join-Path $desktopSupport 'indicators-work.ico'
$desktopPng = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'public\icon-192.png'))
$desktopIconStream = [IO.File]::Create($desktopIcon)
$desktopIconWriter = [IO.BinaryWriter]::new($desktopIconStream)
try {
    $desktopIconWriter.Write([uint16]0); $desktopIconWriter.Write([uint16]1); $desktopIconWriter.Write([uint16]1)
    $desktopIconWriter.Write([byte]192); $desktopIconWriter.Write([byte]192); $desktopIconWriter.Write([byte]0); $desktopIconWriter.Write([byte]0)
    $desktopIconWriter.Write([uint16]1); $desktopIconWriter.Write([uint16]32); $desktopIconWriter.Write([uint32]$desktopPng.Length); $desktopIconWriter.Write([uint32]22)
    $desktopIconWriter.Write($desktopPng)
} finally { $desktopIconWriter.Dispose() }
$desktopDestinations = @($(if ($ShortcutDirectory) { [IO.Path]::GetFullPath($ShortcutDirectory) } else { [Environment]::GetFolderPath('Desktop') }))
if (-not $SkipStartMenu) { $desktopDestinations += Join-Path ([Environment]::GetFolderPath('Programs')) 'Indicators & Work Dashboard' }
$desktopShell = New-Object -ComObject WScript.Shell
foreach ($desktopVariant in @(@{name='Indicators & Work Dashboard';focus=$false;file='dashboard'},@{name='I&W Focus';focus=$true;file='focus'})) {
    $desktopCommand = "& '" + $desktopLauncher.Replace("'", "''") + "'" + $(if ($desktopVariant.focus) { ' -Focus' } else { '' })
    $desktopEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($desktopCommand))
    $desktopVbs = Join-Path $desktopSupport ($desktopVariant.file + '.vbs')
    [IO.File]::WriteAllText($desktopVbs, "Set appShell = CreateObject(""WScript.Shell"")`r`nappShell.Run ""powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $desktopEncoded"", 0, False`r`n", [Text.Encoding]::ASCII)
    foreach ($desktopDestination in $desktopDestinations) {
        New-Item -ItemType Directory -Path $desktopDestination -Force | Out-Null
        $desktopShortcutPath = Join-Path $desktopDestination ($desktopVariant.name + '.lnk')
        $desktopShortcut = $desktopShell.CreateShortcut($desktopShortcutPath)
        $desktopShortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
        $desktopShortcut.Arguments = '"' + $desktopVbs + '"'
        $desktopShortcut.WorkingDirectory = $PSScriptRoot
        $desktopShortcut.IconLocation = $desktopIcon + ',0'
        $desktopShortcut.Description = 'Indicators & Work Dashboard - local application window'
        $desktopShortcut.Save()
        Write-Output $desktopShortcutPath
    }
}
