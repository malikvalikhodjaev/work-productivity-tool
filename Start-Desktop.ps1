[CmdletBinding()]
param([switch]$Focus, [ValidateSet('Auto','Edge','Chrome')][string]$Browser = 'Auto', [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
try {
    $desktopBrowsers = @{
        Edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe", "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe")
        Chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")
    }
    $desktopBrowserPath = $null
    foreach ($desktopBrowserName in $(if ($Browser -eq 'Auto') { @('Edge','Chrome') } else { @($Browser) })) {
        foreach ($desktopCandidate in $desktopBrowsers[$desktopBrowserName]) {
            if (Test-Path -LiteralPath $desktopCandidate -PathType Leaf) { $desktopBrowserPath = $desktopCandidate; break }
        }
        if ($desktopBrowserPath) { break }
    }
    if (-not $desktopBrowserPath) { throw 'Microsoft Edge or Google Chrome is required. Install one from its official website.' }
    & (Join-Path $PSScriptRoot 'Start-Dashboard.ps1') -NoBrowser | Out-Null
    $desktopHealth = Invoke-RestMethod -Uri 'http://127.0.0.1:8787/api/health' -TimeoutSec 3
    if (-not $desktopHealth.ok -or $desktopHealth.service -ne 'rhythm-dashboard') { throw 'The dashboard server is unavailable.' }
    $desktopUrl = if ($Focus) { 'http://localhost:8787/focus' } else { 'http://localhost:8787/#work' }
    if ($CheckOnly) { [pscustomobject]@{browser=$desktopBrowserPath;url=$desktopUrl;version=$desktopHealth.version;serverReady=$true} | ConvertTo-Json; return }
    $desktopSize = if ($Focus) { '560,900' } else { '1360,920' }
    Start-Process -FilePath $desktopBrowserPath -ArgumentList @("--app=$desktopUrl", "--window-size=$desktopSize")
} catch {
    $desktopError = $_.Exception.Message
    $desktopLogDirectory = Join-Path $PSScriptRoot 'logs'
    New-Item -ItemType Directory -Path $desktopLogDirectory -Force | Out-Null
    Add-Content -LiteralPath (Join-Path $desktopLogDirectory 'desktop-error.log') -Value ("$(Get-Date -Format o) $desktopError")
    if (-not $CheckOnly) { Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show($desktopError, 'Indicators & Work Dashboard') | Out-Null }
    throw
}
