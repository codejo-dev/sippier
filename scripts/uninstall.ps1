# Uninstalls Sippier from Windows: the app in %LOCALAPPDATA%\Programs\Sippier,
# its Start menu entry, and its accounts, settings, call history and log,
# passwords included:
#
#   irm https://raw.githubusercontent.com/codejo-dev/sippier/main/scripts/uninstall.ps1 | iex

& {
  $ErrorActionPreference = 'Stop'

  $paths = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Sippier'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'Sippier.lnk'),
    # The app's data, where Flutter's path_provider puts it:
    # <CompanyName>\<ProductName> from Runner.rc. The passwords are in there
    # too, encrypted with DPAPI.
    (Join-Path $env:APPDATA 'dev.codejo\Sippier'),
    (Join-Path $env:LOCALAPPDATA 'dev.codejo\Sippier')
  ) | Where-Object { Test-Path $_ }

  # Older versions of the storage plugin kept the passwords in Credential
  # Manager, and the current one still leaves a key there when it looks for
  # them. Named after the executable.
  Add-Type -Namespace Sippier -Name Credentials -MemberDefinition @'
[DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool CredEnumerateW(string filter, int flags, out int count, out IntPtr credentials);
[DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool CredDeleteW(string target, int type, int flags);
[DllImport("advapi32.dll")]
public static extern void CredFree(IntPtr buffer);
'@
  $prefix = 'sippier_VGhpcyBpcyB0aGUgcHJlZml4IGZv_'
  $credentials = foreach ($filter in "$prefix*", "key_$prefix*") {
    $count = 0
    $list = [IntPtr]::Zero
    if ([Sippier.Credentials]::CredEnumerateW($filter, 0, [ref]$count, [ref]$list)) {
      try {
        for ($i = 0; $i -lt $count; $i++) {
          # CREDENTIALW starts with Flags, Type and TargetName
          $credential = [Runtime.InteropServices.Marshal]::ReadIntPtr($list, $i * [IntPtr]::Size)
          [pscustomobject]@{
            Type = [Runtime.InteropServices.Marshal]::ReadInt32($credential, 4)
            Name = [Runtime.InteropServices.Marshal]::PtrToStringUni(
              [Runtime.InteropServices.Marshal]::ReadIntPtr($credential, 8))
          }
        }
      } finally {
        [Sippier.Credentials]::CredFree($list)
      }
    }
  }

  if (-not $paths -and -not $credentials) {
    Write-Host "Sippier isn't installed"
    return
  }

  $running = Get-Process sippier -ErrorAction SilentlyContinue
  if ($running) {
    Write-Host 'Closing Sippier'
    $running | Stop-Process -Force
    $running | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
  }

  foreach ($credential in $credentials) {
    [void][Sippier.Credentials]::CredDeleteW($credential.Name, $credential.Type, 0)
  }
  foreach ($path in $paths) {
    Remove-Item $path -Recurse -Force
    Write-Host "Removed $path"
  }
  # The company folder, if Sippier was all there was in it
  foreach ($parent in $env:APPDATA, $env:LOCALAPPDATA) {
    $company = Join-Path $parent 'dev.codejo'
    if ((Test-Path $company) -and -not (Get-ChildItem $company -Force)) {
      Remove-Item $company
    }
  }

  Write-Host 'Sippier is uninstalled'
}
