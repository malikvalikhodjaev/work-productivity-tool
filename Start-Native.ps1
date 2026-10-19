[CmdletBinding()]
param([string]$BinaryDirectory = (Join-Path $PSScriptRoot 'outputs\native-windows'), [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$nativeBinary = Join-Path ([IO.Path]::GetFullPath($BinaryDirectory)) 'indicators_work.exe'
$nativeDataDirectory = if ($env:DASHBOARD_DATA_DIR) { $env:DASHBOARD_DATA_DIR } else { Join-Path $PSScriptRoot 'data' }
$nativeMovedFile = Join-Path $nativeDataDirectory 'server-moved.json'
$nativeHealthUrl = 'http://127.0.0.1:8787/api/health'
if (Test-Path -LiteralPath $nativeMovedFile) {
    $nativeMoved = Get-Content -LiteralPath $nativeMovedFile -Raw | ConvertFrom-Json
    if ($nativeMoved.version -ne 1 -or $nativeMoved.url -cnotmatch '^https://[a-z0-9-]+\.[a-z0-9-]+\.ts\.net/?$') { throw 'Invalid moved-server address.' }
    $nativeHealthUrl = $nativeMoved.url.TrimEnd('/') + '/api/health'
}
if (-not (Test-Path -LiteralPath $nativeBinary -PathType Leaf)) { throw 'Native app is missing. Build it and run Install-Native.ps1 with the release folder.' }
$nativeHasher = [Security.Cryptography.SHA256]::Create()
try { $nativeRootHash = ([BitConverter]::ToString($nativeHasher.ComputeHash([Text.Encoding]::Unicode.GetBytes($PSScriptRoot.ToUpperInvariant())))).Replace('-', '').Substring(0, 16) }
finally { $nativeHasher.Dispose() }
$nativeMutex = New-Object System.Threading.Mutex($false, ('Local\IndicatorsWorkLauncher-' + $nativeRootHash))
$nativeLocked = $false
try {
    try { $nativeLocked = $nativeMutex.WaitOne(30000) }
    catch [Threading.AbandonedMutexException] { $nativeLocked = $true }
    if (-not $nativeLocked) { throw 'Another dashboard launcher is still starting. Try again shortly.' }
    $nativeHealth = $null
    try {
        & (Join-Path $PSScriptRoot 'Start-Dashboard.ps1') -NoBrowser | Out-Null
        $nativeHealth = Invoke-RestMethod $nativeHealthUrl -TimeoutSec 3
        if (-not $nativeHealth.ok -or $nativeHealth.service -ne 'rhythm-dashboard') { throw 'Dashboard server is unavailable.' }
    } catch {
        if ($CheckOnly) { throw }
        Write-Warning 'Local server is unavailable; opening the app with its saved local data.'
    }
    if ($CheckOnly) { [pscustomobject]@{binary=$nativeBinary;serverVersion=$nativeHealth.version;ready=$true} | ConvertTo-Json; return }
    # The runner owns the single-instance mutex. A second invocation restores
    # its existing window, including when it has been hidden in the tray.
    Start-Process -FilePath $nativeBinary -WorkingDirectory (Split-Path -Parent $nativeBinary) -WindowStyle Hidden
} finally {
    if ($nativeLocked) { $nativeMutex.ReleaseMutex() }
    $nativeMutex.Dispose()
}
