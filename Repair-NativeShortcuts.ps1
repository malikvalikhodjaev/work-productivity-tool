[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ApplicationDirectory,
    [string]$LauncherScript,
    [string]$ShortcutDirectory,
    [string]$BackupDirectory
)
$ErrorActionPreference = 'Stop'
$iwAppDirectory = [IO.Path]::GetFullPath($ApplicationDirectory)
$iwExecutable = Join-Path $iwAppDirectory 'indicators_work.exe'
$iwSourceIcon = Join-Path $iwAppDirectory 'data\flutter_assets\assets\iw.ico'
if (-not (Test-Path -LiteralPath $iwExecutable -PathType Leaf)) { throw 'Native application executable not found.' }
if (-not (Test-Path -LiteralPath $iwSourceIcon -PathType Leaf)) { throw 'Bundled application icon not found.' }
$iwIconHash = (Get-FileHash -LiteralPath $iwSourceIcon -Algorithm SHA256).Hash.ToLowerInvariant()
# A new path when the artwork changes avoids reusing an older cached EXE icon.
$iwIcon = Join-Path $iwAppDirectory ('pomodoro-club-desktop-' + $iwIconHash.Substring(0,16) + '.ico')
if (-not (Test-Path -LiteralPath $iwIcon)) { Copy-Item -LiteralPath $iwSourceIcon -Destination $iwIcon }
if ((Get-FileHash -LiteralPath $iwIcon -Algorithm SHA256).Hash.ToLowerInvariant() -ne $iwIconHash) { throw 'Shortcut icon checksum mismatch.' }
if ($LauncherScript) { $iwLauncher = [IO.Path]::GetFullPath($LauncherScript) } else { $iwLauncher = $null }
if (-not $BackupDirectory) { $BackupDirectory = Join-Path (Split-Path -Parent $iwAppDirectory) ('shortcut-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')) }
$iwBackup = [IO.Path]::GetFullPath($BackupDirectory)
$iwFolders = @(
    (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'Indicators & Work Dashboard'),
    $(if ($ShortcutDirectory) { [IO.Path]::GetFullPath($ShortcutDirectory) } else { [Environment]::GetFolderPath('Desktop') })
)
if (-not ('IndicatorsWork.ShortcutShell' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace IndicatorsWork {
    [StructLayout(LayoutKind.Sequential)] public struct PropertyKey {
        public Guid format; public uint id;
        public PropertyKey(Guid value, uint number) { format=value; id=number; }
    }
    [StructLayout(LayoutKind.Explicit, Size=24)] public struct PropertyValue {
        [FieldOffset(0)] public ushort type;
        [FieldOffset(8)] public IntPtr pointer;
    }
    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface PropertyStore {
        void GetCount(out uint count);
        void GetAt(uint index, out PropertyKey key);
        void GetValue(ref PropertyKey key, out PropertyValue value);
        void SetValue(ref PropertyKey key, ref PropertyValue value);
        void Commit();
    }
    public static class ShortcutShell {
        [DllImport("shell32.dll", CharSet=CharSet.Unicode, PreserveSig=false)]
        private static extern void SHGetPropertyStoreFromParsingName(string path, IntPtr context, uint flags, ref Guid id, [MarshalAs(UnmanagedType.Interface)] out PropertyStore store);
        private static void InitPropVariantFromString(string text, out PropertyValue value) {
            value = new PropertyValue { type=31, pointer=Marshal.StringToCoTaskMemUni(text) };
        }
        [DllImport("ole32.dll")] private static extern int PropVariantClear(ref PropertyValue value);
        private static PropertyKey AppIdKey = new PropertyKey(new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), 5);
        public static string AppId(string path) {
            Guid id=typeof(PropertyStore).GUID; PropertyStore store;
            SHGetPropertyStoreFromParsingName(path, IntPtr.Zero, 0, ref id, out store);
            PropertyValue value;
            try { store.GetValue(ref AppIdKey, out value);
                try { return value.type==31 ? Marshal.PtrToStringUni(value.pointer) : null; }
                finally { PropVariantClear(ref value); }
            } finally { Marshal.ReleaseComObject(store); }
        }
        public static void SetAppId(string path, string appId) {
            Guid id=typeof(PropertyStore).GUID; PropertyStore store;
            SHGetPropertyStoreFromParsingName(path, IntPtr.Zero, 2, ref id, out store);
            PropertyValue value;
            try { InitPropVariantFromString(appId, out value);
                try { store.SetValue(ref AppIdKey, ref value); store.Commit(); }
                finally { PropVariantClear(ref value); }
            } finally { Marshal.ReleaseComObject(store); }
        }
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern void SHChangeNotify(int eventId, uint flags, string item1, IntPtr item2);
        public static void Updated(string path) {
            // SHCNE_UPDATEITEM; SHCNF_PATHW | SHCNF_FLUSH.
            SHChangeNotify(0x00002000, 0x1005, path, IntPtr.Zero);
        }
    }
}
'@
}
$iwShell = New-Object -ComObject WScript.Shell
$iwChanges = @()
foreach ($iwFolder in ($iwFolders | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $iwFolder -PathType Container)) { continue }
    foreach ($iwFile in (Get-ChildItem -LiteralPath $iwFolder -Filter '*.lnk' -File)) {
        $iwLink = $iwShell.CreateShortcut($iwFile.FullName)
        $iwDirect = $iwLink.TargetPath -and [IO.Path]::GetFullPath($iwLink.TargetPath) -eq $iwExecutable
        $iwViaLauncher = $iwLauncher -and ([IO.Path]::GetFileName($iwLink.TargetPath) -ieq 'wscript.exe') -and $iwLink.Arguments -ceq ('"' + $iwLauncher + '"')
        if (-not ($iwDirect -or $iwViaLauncher)) { continue }
        $iwLocation = $iwIcon + ',0'
        $iwAppId = 'UzIW.IndicatorsWork.Desktop'
        if ($iwLink.IconLocation -ne $iwLocation -or [IndicatorsWork.ShortcutShell]::AppId($iwFile.FullName) -ne $iwAppId) {
            New-Item -ItemType Directory -Force -Path $iwBackup | Out-Null
            $iwSavedLink = Join-Path $iwBackup ([guid]::NewGuid().ToString() + '.lnk')
            Copy-Item -LiteralPath $iwFile.FullName -Destination $iwSavedLink
            $iwOldTarget = $iwLink.TargetPath
            $iwOldArguments = $iwLink.Arguments
            $iwOldIcon = $iwLink.IconLocation
            try {
                $iwLink.IconLocation = $iwLocation
                $iwLink.Save()
                [IndicatorsWork.ShortcutShell]::SetAppId($iwFile.FullName, $iwAppId)
                $iwReadBack = $iwShell.CreateShortcut($iwFile.FullName)
                if ($iwReadBack.TargetPath -cne $iwOldTarget -or $iwReadBack.Arguments -cne $iwOldArguments -or $iwReadBack.IconLocation -ne $iwLocation) { throw 'Shortcut verification failed.' }
                if ([IndicatorsWork.ShortcutShell]::AppId($iwFile.FullName) -ne $iwAppId) { throw 'Shortcut application identity verification failed.' }
            } catch {
                Copy-Item -LiteralPath $iwSavedLink -Destination $iwFile.FullName -Force
                throw
            }
            $iwChanges += [pscustomobject]@{shortcut=$iwFile.FullName;previousIcon=$iwOldIcon;icon=$iwLocation;backup=$iwSavedLink;targetPreserved=$true}
        }
        [IndicatorsWork.ShortcutShell]::Updated($iwFile.FullName)
    }
}
[IndicatorsWork.ShortcutShell]::Updated($iwExecutable)
[pscustomobject]@{icon=$iwIcon;iconSha256=$iwIconHash;changedShortcuts=$iwChanges;applicationRestarted=$false} | ConvertTo-Json -Depth 5
