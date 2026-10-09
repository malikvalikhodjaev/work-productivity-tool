[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$bundleRoot = $PSScriptRoot
$bundleStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bundleOutputs = Join-Path $bundleRoot 'outputs'
$bundleStage = Join-Path $bundleOutputs ("server-transfer-$bundleStamp")
if (Test-Path -LiteralPath $bundleStage) { throw 'Transfer directory already exists. Run again in a few seconds.' }
New-Item -ItemType Directory -Path $bundleStage -Force | Out-Null
$bundleData = if ($env:DASHBOARD_DATA_DIR) { $env:DASHBOARD_DATA_DIR } else { Join-Path $bundleRoot 'data' }
$bundleNode = (Get-Command node.exe -ErrorAction Stop).Source
& $bundleNode (Join-Path $bundleRoot 'scripts/backup.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Backup failed; export stopped.' }
foreach ($bundleItem in @('lib','public','docs','scripts','server.mjs','package.json','package-lock.json','tests','AGENTS.md','.dockerignore','Dockerfile','compose.yaml','README.md','Start-Dashboard.ps1','Install-Autostart.ps1','Connect-Android.ps1','Export-Server.ps1','Open-Alphas.cmd','Открыть дашборд.cmd','Подключить Android.cmd')) {
    Copy-Item -LiteralPath (Join-Path $bundleRoot $bundleItem) -Destination (Join-Path $bundleStage $bundleItem) -Recurse
}
$bundleDestination = Join-Path $bundleStage 'data'
New-Item -ItemType Directory -Path $bundleDestination -Force | Out-Null
foreach ($bundleItem in Get-ChildItem -LiteralPath $bundleData -Force) {
    if ($bundleItem.Name -eq 'backups' -or $bundleItem.Name.EndsWith('.tmp')) { continue }
    Copy-Item -LiteralPath $bundleItem.FullName -Destination (Join-Path $bundleDestination $bundleItem.Name) -Recurse
}
$bundleManifest = @(Get-ChildItem -LiteralPath $bundleStage -File -Recurse -Force | ForEach-Object {
    @{path=$_.FullName.Substring($bundleStage.Length + 1).Replace('\','/'); sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(); size=$_.Length}
})
[IO.File]::WriteAllText((Join-Path $bundleStage 'transfer-manifest.json'), ($bundleManifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
$bundleZip = Join-Path $bundleOutputs ("indicators-work-server-$bundleStamp.zip")
Compress-Archive -Path (Join-Path $bundleStage '*') -DestinationPath $bundleZip -CompressionLevel Optimal
Write-Host "Private transfer archive: $bundleZip"
Write-Host 'Keep it private: it contains your data. The expanded directory includes SHA256 hashes. Stop the old server before the final transfer; only one server may write this data directory.'
