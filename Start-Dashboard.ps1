$ErrorActionPreference = 'Stop'
$rhythmDirectory = $PSScriptRoot
$rhythmUrl = 'http://127.0.0.1:8787'
$rhythmReady = $false
try {
    $rhythmHealth = Invoke-RestMethod -Uri "$rhythmUrl/api/health" -TimeoutSec 2
    $rhythmReady = ($rhythmHealth.ok -eq $true -and $rhythmHealth.service -eq 'rhythm-dashboard')
} catch { }
if (-not $rhythmReady) {
    $rhythmNode = (Get-Command node.exe -ErrorAction Stop).Source
    $rhythmLogDirectory = Join-Path $rhythmDirectory 'logs'
    New-Item -ItemType Directory -Path $rhythmLogDirectory -Force | Out-Null
    $rhythmServerPath = Join-Path $rhythmDirectory 'server.mjs'
    $rhythmProcess = Start-Process -FilePath $rhythmNode -ArgumentList @('"' + $rhythmServerPath + '"') -WorkingDirectory $rhythmDirectory -WindowStyle Hidden -RedirectStandardOutput (Join-Path $rhythmLogDirectory 'server.log') -RedirectStandardError (Join-Path $rhythmLogDirectory 'server-error.log') -PassThru
    for ($rhythmAttempt = 0; $rhythmAttempt -lt 20; $rhythmAttempt++) {
        try {
            $rhythmHealth = Invoke-RestMethod -Uri "$rhythmUrl/api/health" -TimeoutSec 1
            if ($rhythmHealth.ok -eq $true -and $rhythmHealth.service -eq 'rhythm-dashboard') { $rhythmReady = $true; break }
        } catch { }
        if ($rhythmProcess.HasExited) { break }
        Start-Sleep -Milliseconds 250
    }
    if (-not $rhythmReady) {
        Write-Host 'Could not start dashboard. See personal-dashboard\logs\server-error.log.' -ForegroundColor Red
        exit 1
    }
}
if (-not ($args -contains '-NoBrowser')) { Start-Process $rhythmUrl }
Write-Host "Dashboard is running: $rhythmUrl"
