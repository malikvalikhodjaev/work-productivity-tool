[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Url,
    [Parameter(Mandatory=$true)][string]$ExpectedServerId,
    [Parameter(Mandatory=$true)][string]$ExpectedWritingInstanceId
)
$ErrorActionPreference='Stop'
if ($Url -cnotmatch '^https://[a-z0-9-]+\.[a-z0-9-]+\.ts\.net/?$') { throw 'Use the new private HTTPS Tailscale address.' }
$remotePort=if($env:DASHBOARD_PORT){[int]$env:DASHBOARD_PORT}else{8787}
if (@(Get-NetTCPConnection -State Listen -LocalPort $remotePort -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Stop the old local server before activating the remote host.' }
$remoteOrigin=$Url.TrimEnd('/')
$remoteHeaders=@{Origin=$remoteOrigin}
$remoteHealth=Invoke-RestMethod ($remoteOrigin+'/api/health') -TimeoutSec 10
if(-not $remoteHealth.ok -or $remoteHealth.service -ne 'rhythm-dashboard'){throw 'The new dashboard server did not pass its health check.'}
$remoteContext=Invoke-RestMethod ($remoteOrigin+'/api/offline/connect') -Method Post -ContentType 'application/json' -Headers $remoteHeaders -Body (@{deviceId=[guid]::NewGuid().ToString()}|ConvertTo-Json) -TimeoutSec 10
$remoteWriting=Invoke-RestMethod ($remoteOrigin+'/api/writing/context') -TimeoutSec 10
if($remoteContext.serverId -ne $ExpectedServerId -or $remoteWriting.instanceId -ne $ExpectedWritingInstanceId){throw 'Archive identity mismatch. The old host has not been marked as moved.'}
$remoteData=if($env:DASHBOARD_DATA_DIR){$env:DASHBOARD_DATA_DIR}else{Join-Path $PSScriptRoot 'data'}
$remoteMarker=Join-Path $remoteData 'server-moved.json'
if(Test-Path -LiteralPath $remoteMarker){Copy-Item -LiteralPath $remoteMarker -Destination ($remoteMarker+'.before-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))}
$remoteDocument=@{version=1;url=$remoteOrigin;serverId=$ExpectedServerId;writingInstanceId=$ExpectedWritingInstanceId;movedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json
[IO.File]::WriteAllText($remoteMarker+'.tmp',$remoteDocument,[Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath ($remoteMarker+'.tmp') -Destination $remoteMarker -Force
Write-Host "Remote host verified: $remoteOrigin. This PC will not start a second writing server. Set this address in both clients without clearing their local data."
