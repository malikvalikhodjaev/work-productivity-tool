[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BundlePath,
    [Parameter(Mandatory=$true)][string]$BundletoolPath,
    [string]$JavaHome = 'C:\IWD-Tools\jdk17',
    [string]$ExpectedPackage = 'uz.iw.indicators_work',
    [string]$ExpectedCertificateSha256,
    [int]$MinimumVersionCode = 1
)
$ErrorActionPreference = 'Stop'
$bundleFile = (Resolve-Path -LiteralPath $BundlePath).Path
$bundleTool = (Resolve-Path -LiteralPath $BundletoolPath).Path
$java = Join-Path $JavaHome 'bin\java.exe'
$jarsigner = Join-Path $JavaHome 'bin\jarsigner.exe'
$keytool = Join-Path $JavaHome 'bin\keytool.exe'
$validation = & $java -jar $bundleTool validate ('--bundle=' + $bundleFile) 2>&1
if ($LASTEXITCODE -ne 0) { throw ('bundletool rejected the bundle: ' + ($validation -join "`n")) }
$signature = & $jarsigner '-J-Duser.language=en' -verify $bundleFile 2>&1
if ($LASTEXITCODE -ne 0 -or ($signature -join "`n") -notmatch 'jar verified') { throw 'Bundle JAR signature is not valid.' }
$certificate = & $keytool '-J-Duser.language=en' -printcert -jarfile $bundleFile 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the bundle certificate.' }
$certificateMatch = [regex]::Match(($certificate -join "`n"), 'SHA256:\s*([0-9A-Fa-f:]+)')
if (-not $certificateMatch.Success) { throw 'Certificate SHA256 is missing.' }
$certificateSha = $certificateMatch.Groups[1].Value.Replace(':','').ToLowerInvariant()
if ($ExpectedCertificateSha256 -and $certificateSha -cne $ExpectedCertificateSha256.Replace(':','').ToLowerInvariant()) { throw 'Bundle signed by a different key.' }
$package = ((& $java -jar $bundleTool dump manifest ('--bundle=' + $bundleFile) '--xpath=/manifest/@package') -join '').Trim()
if ($LASTEXITCODE -ne 0 -or $package -cne $ExpectedPackage) { throw 'Unexpected Android package.' }
$versionCode = ((& $java -jar $bundleTool dump manifest ('--bundle=' + $bundleFile) '--xpath=/manifest/@android:versionCode') -join '').Trim()
if ($LASTEXITCODE -ne 0 -or $versionCode -notmatch '^\d+$' -or [int]$versionCode -lt $MinimumVersionCode) { throw 'Bundle version code is too low or missing.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($bundleFile)
try {
    $privateEntries = @($archive.Entries | Where-Object { $_.FullName -match '(?i)(\.sqlite($|-)|telegram-bot\.json|remote-access\.json|native-signing|\.jks$|\.keystore$)' })
    if ($privateEntries.Count) { throw 'Private installation files must not be included in an App Bundle.' }
    $libraries = @($archive.Entries | Where-Object { $_.FullName -match '(^|/)lib/[^/]+/[^/]+\.so$' })
    if (-not $libraries.Count) { throw 'Native libraries are missing.' }
    $elfChecks = foreach ($entry in $libraries) {
        $stream = $entry.Open()
        $memory = New-Object IO.MemoryStream
        try {
            $stream.CopyTo($memory)
            $bytes = $memory.ToArray()
            if ($bytes.Length -lt 64 -or $bytes[0] -ne 127 -or [Text.Encoding]::ASCII.GetString($bytes,1,3) -cne 'ELF' -or $bytes[4] -ne 2 -or $bytes[5] -ne 1) { throw ('Expected a little-endian 64-bit ELF: ' + $entry.FullName) }
            $headerOffset = [BitConverter]::ToUInt64($bytes,32)
            $headerSize = [BitConverter]::ToUInt16($bytes,54)
            $headerCount = [BitConverter]::ToUInt16($bytes,56)
            $loadAlignments = @()
            for ($index=0; $index -lt $headerCount; $index++) {
                $offset = $headerOffset + $index * $headerSize
                if ($headerSize -lt 56 -or $offset + 56 -gt $bytes.Length) { throw 'Invalid ELF program headers.' }
                if ([BitConverter]::ToUInt32($bytes,[int]$offset) -eq 1) { $loadAlignments += [BitConverter]::ToUInt64($bytes,[int]($offset+48)) }
            }
            if (-not $loadAlignments.Count -or @($loadAlignments | Where-Object { $_ -lt 16384 }).Count) { throw ('Native library lacks 16 KiB LOAD alignment: ' + $entry.FullName) }
            [pscustomobject]@{file=$entry.FullName;minimumLoadAlignment=($loadAlignments | Measure-Object -Minimum).Minimum}
        } finally { $stream.Dispose(); $memory.Dispose() }
    }
} finally { $archive.Dispose() }
[pscustomobject]@{
    bundle=$bundleFile
    package=$package
    versionCode=[int]$versionCode
    bundletoolValidated=$true
    signatureVerified=$true
    certificateSha256=$certificateSha
    privateDataFiles=0
    nativeLibraries=$elfChecks
    sha256=(Get-FileHash -LiteralPath $bundleFile -Algorithm SHA256).Hash.ToLowerInvariant()
} | ConvertTo-Json -Depth 5
