[CmdletBinding()]
param(
    [string]$ToolsDirectory = 'C:\IWD-Tools',
    [string]$BuildDirectory = 'C:\IWD-Tools\iw-native-build',
    [string]$KeyPropertiesPath = $env:IW_ANDROID_KEY_PROPERTIES,
    [ValidateSet('Apk','AppBundle')][string]$Format = 'Apk',
    [switch]$Online
)
$ErrorActionPreference = 'Stop'
$taskTools = [IO.Path]::GetFullPath($ToolsDirectory)
$taskBuild = [IO.Path]::GetFullPath($BuildDirectory)
if (-not $taskBuild.StartsWith($taskTools + '\')) { throw 'BuildDirectory must be inside ToolsDirectory.' }
$taskManifest = Get-Content -LiteralPath (Join-Path $taskTools 'tools-manifest.json') -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($KeyPropertiesPath) -or -not (Test-Path -LiteralPath $KeyPropertiesPath -PathType Leaf)) {
    throw 'Set IW_ANDROID_KEY_PROPERTIES or pass KeyPropertiesPath to your private release key.properties.'
}
$env:JAVA_HOME = Join-Path $taskTools 'jdk17'
$env:ANDROID_HOME = Join-Path $taskTools 'Android'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:GRADLE_USER_HOME = Join-Path $taskTools 'gradle-cache'
$env:PUB_CACHE = $taskManifest.pubCache
$env:IW_ANDROID_KEY_PROPERTIES = [IO.Path]::GetFullPath($KeyPropertiesPath)
$env:Path = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$($taskManifest.flutter)\bin;" + $env:Path
Remove-Item Env:\GRADLE_RO_DEP_CACHE -ErrorAction SilentlyContinue
$taskFlutter = Join-Path $taskManifest.flutter 'bin\flutter.bat'
$taskGradle = Join-Path $env:GRADLE_USER_HOME 'wrapper\dists\gradle-9.3.1-all\9ot9r568e8zfvvd4mn8rbu1j0\gradle-9.3.1\bin\gradle.bat'
foreach ($taskExecutable in @($taskFlutter,$taskGradle,(Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
    if (-not (Test-Path -LiteralPath $taskExecutable -PathType Leaf)) { throw 'Missing local build tool: ' + $taskExecutable }
}
New-Item -ItemType Directory -Path $taskBuild -Force | Out-Null
$taskSource = Join-Path $PSScriptRoot 'native-app'
& robocopy.exe $taskSource $taskBuild /E /XJ /R:2 /W:1 /NFL /NDL /NP /NJH /NJS /XD .git .dart_tool build .gradle /XF local.properties key.properties '*.jks' '*.keystore' | Out-Null
if ($LASTEXITCODE -gt 7) { throw 'Source copy failed.' }
$taskVersion = Select-String -LiteralPath (Join-Path $taskSource 'pubspec.yaml') -Pattern '^version:\s+([^+\s]+)\+(\d+)\s*$'
if (-not $taskVersion) { throw 'pubspec.yaml must contain a version name and build number.' }
$taskProperties = "sdk.dir=$($env:ANDROID_HOME.Replace('\','\\'))`nflutter.sdk=$($taskManifest.flutter.Replace('\','\\'))`nflutter.buildMode=release`nflutter.versionName=$($taskVersion.Matches[0].Groups[1].Value)`nflutter.versionCode=$($taskVersion.Matches[0].Groups[2].Value)`n"
[IO.File]::WriteAllText((Join-Path $taskBuild 'android\local.properties'),$taskProperties,[Text.UTF8Encoding]::new($false))
Push-Location $taskBuild
try {
    & $taskFlutter config --android-sdk $env:ANDROID_HOME --jdk-dir $env:JAVA_HOME | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Flutter tool configuration failed.' }
    & $taskFlutter pub get --offline
    if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed.' }
    [IO.File]::WriteAllText((Join-Path $taskBuild 'android\local.properties'),$taskProperties,[Text.UTF8Encoding]::new($false))
    Push-Location (Join-Path $taskBuild 'android')
    try {
        $taskLog = Join-Path $taskBuild $(if ($Format -eq 'AppBundle') { 'android-appbundle-build.log' } else { 'android-build.log' })
        $taskCacheFlags = @()
        if (-not $Online) { $taskCacheFlags += '--offline' }
        # AGP otherwise marks an APK with an injected ABI as test-only.
        $taskReleaseTask = if ($Format -eq 'AppBundle') { 'bundleRelease' } else { 'assembleRelease' }
        & $taskGradle --no-daemon @taskCacheFlags '-Dorg.gradle.vfs.watch=false' '-Pandroid.injected.build.abi=arm64-v8a' '-Pandroid.injected.testOnly=false' '-Ptarget-platform=android-arm64' '-Ptarget=lib/main.dart' '-Ptree-shake-icons=true' $taskReleaseTask *> $taskLog
        $taskExit = $LASTEXITCODE
        Get-Content -LiteralPath $taskLog -Tail 24
        if ($taskExit -ne 0) { throw "Android build failed; see $taskLog" }
    } finally { Pop-Location }
} finally { Pop-Location }
if ($Format -eq 'AppBundle') {
    $taskBundle = Join-Path $taskBuild 'build\app\outputs\bundle\release\app-release.aab'
    if (-not (Test-Path -LiteralPath $taskBundle -PathType Leaf)) { throw 'Release App Bundle was not generated.' }
    $taskSignature = & (Join-Path $env:JAVA_HOME 'bin\jarsigner.exe') -verify $taskBundle 2>&1
    if ($LASTEXITCODE -ne 0 -or ($taskSignature -join "`n") -notmatch '(?i)(jar verified|jar проверен)') { throw 'App Bundle signature could not be verified.' }
    [pscustomobject]@{aab=$taskBundle;versionName=$taskVersion.Matches[0].Groups[1].Value;versionCode=[int]$taskVersion.Matches[0].Groups[2].Value;signatureVerified=$true;sha256=(Get-FileHash -LiteralPath $taskBundle -Algorithm SHA256).Hash} | ConvertTo-Json
    return
}
$taskApk = Join-Path $taskBuild 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path -LiteralPath $taskApk -PathType Leaf)) { throw 'Release APK was not generated.' }
$taskAapt = Join-Path $env:ANDROID_HOME 'build-tools\36.0.0\aapt.exe'
$taskApkManifest = & $taskAapt dump xmltree $taskApk AndroidManifest.xml 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Release APK manifest could not be verified.' }
if ($taskApkManifest -match 'android:(testOnly|debuggable).*0xffffffff') {
    throw 'Release APK must not be test-only or debuggable.'
}
[pscustomobject]@{apk=$taskApk;sha256=(Get-FileHash -LiteralPath $taskApk -Algorithm SHA256).Hash} | ConvertTo-Json
