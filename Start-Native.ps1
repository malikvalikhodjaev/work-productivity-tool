[CmdletBinding()]
param([string]$BinaryDirectory = (Join-Path $PSScriptRoot 'outputs\native-windows'), [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$nativeBinary = Join-Path ([IO.Path]::GetFullPath($BinaryDirectory)) 'indicators_work.exe'
if (-not (Test-Path -LiteralPath $nativeBinary -PathType Leaf)) { throw 'Native app is missing. Build it and run Install-Native.ps1 with the release folder.' }
& (Join-Path $PSScriptRoot 'Start-Dashboard.ps1') -NoBrowser | Out-Null
$nativeHealth = Invoke-RestMethod 'http://127.0.0.1:8787/api/health' -TimeoutSec 3
if (-not $nativeHealth.ok -or $nativeHealth.service -ne 'rhythm-dashboard') { throw 'Dashboard server is unavailable.' }
if ($CheckOnly) { [pscustomobject]@{binary=$nativeBinary;serverVersion=$nativeHealth.version;ready=$true} | ConvertTo-Json; return }
Start-Process -FilePath $nativeBinary -WorkingDirectory (Split-Path -Parent $nativeBinary)
