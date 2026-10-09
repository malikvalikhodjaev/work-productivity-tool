[CmdletBinding()]
param([switch]$NoBrowser, [switch]$NoAutostart)
$ErrorActionPreference = 'Stop'
$dashboardRoot = $PSScriptRoot
$tailscaleCandidates = @((Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'), (Join-Path ${env:ProgramFiles(x86)} 'Tailscale\tailscale.exe'))
$tailscaleCommand = Get-Command tailscale.exe -ErrorAction SilentlyContinue
$tailscalePath = if ($tailscaleCommand) { $tailscaleCommand.Source } else { $tailscaleCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1 }
if (-not $tailscalePath) {
    Write-Host 'Install Tailscale on this PC and Android, then sign in to the same account.'
    if (-not $NoBrowser) { Start-Process 'https://tailscale.com/download/windows' }
    exit 2
}
$tailscaleRawStatus = & $tailscalePath status --json
if ($LASTEXITCODE -ne 0) { throw 'Could not read Tailscale status.' }
$tailscaleStatus = $tailscaleRawStatus | ConvertFrom-Json
if ($tailscaleStatus.BackendState -ne 'Running') {
    Write-Host 'Sign in to Tailscale on this PC, then run this script again.'
    exit 2
}
$dashboardDns = ([string]$tailscaleStatus.Self.DNSName).TrimEnd('.')
$ownerProfile = $tailscaleStatus.User.PSObject.Properties | Where-Object { $_.Name -eq [string]$tailscaleStatus.Self.UserID } | Select-Object -ExpandProperty Value
$ownerLogin = ([string]$ownerProfile.LoginName).Trim().ToLowerInvariant()
if ($dashboardDns -notmatch '^[a-z0-9-]+\.[a-z0-9-]+\.ts\.net$' -or -not $ownerLogin) { throw 'The PC must be an authenticated user device with a Tailscale DNS name.' }
$existingServeRaw = & $tailscalePath serve status --json
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect existing Tailscale Serve configuration.' }
$existingServe = $existingServeRaw | ConvertFrom-Json
if ($existingServe.AllowFunnel -and @($existingServe.AllowFunnel.PSObject.Properties | Where-Object { $_.Value -eq $true }).Count -gt 0) { throw 'Tailscale Funnel is enabled. Disable public access before connecting this private dashboard.' }
$existingHandlers = @()
if ($existingServe.Web) { foreach ($webEntry in $existingServe.Web.PSObject.Properties) { foreach ($handler in $webEntry.Value.Handlers.PSObject.Properties) { $existingHandlers += [PSCustomObject]@{ Host=$webEntry.Name; Path=$handler.Name; Proxy=$handler.Value.Proxy } } } }
foreach ($handler in $existingHandlers) {
    if ($handler.Host -eq "${dashboardDns}:443" -and ($handler.Path -ne '/' -or $handler.Proxy -ne 'http://127.0.0.1:8789')) { throw 'Port 443 already serves another application. Existing settings were preserved.' }
}
$dashboardData = if ($env:DASHBOARD_DATA_DIR) { $env:DASHBOARD_DATA_DIR } else { Join-Path $dashboardRoot 'data' }
New-Item -ItemType Directory -Path $dashboardData -Force | Out-Null
$configPath = Join-Path $dashboardData 'remote-access.json'
if (Test-Path -LiteralPath $configPath) {
    $configBackup = Join-Path $dashboardRoot ('outputs\backups\remote-access-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    New-Item -ItemType Directory -Path (Split-Path $configBackup -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $configPath -Destination $configBackup
}
$dashboardConfig = @{version=1; url="https://$dashboardDns"; allowedLogin=$ownerLogin}
$configTemp = "$configPath.tmp"
[System.IO.File]::WriteAllText($configTemp, ($dashboardConfig | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $configTemp -Destination $configPath -Force
& (Join-Path $dashboardRoot 'Start-Dashboard.ps1') -NoBrowser
$gatewayStatus = Invoke-RestMethod -Uri 'http://127.0.0.1:8787/api/mobile-access' -TimeoutSec 5
if (-not $gatewayStatus.gatewayReady -or -not $gatewayStatus.configured) { throw 'Restart the updated dashboard server and run this script again.' }
& $tailscalePath serve --bg --https=443 http://127.0.0.1:8789
if ($LASTEXITCODE -ne 0) { throw 'HTTPS setup is incomplete. Follow the Tailscale link above to enable HTTPS, then run this script again.' }
if (-not $NoAutostart) { & (Join-Path $dashboardRoot 'Install-Autostart.ps1') }
Write-Host "Android URL: https://$dashboardDns"
Write-Host 'Connect Tailscale on Android. Open this URL in Chrome, then choose Install / Add to home screen.'
Write-Host 'The PC must stay powered on. Only viewing is available remotely.'
if (-not $NoBrowser) { Start-Process "https://$dashboardDns" }
