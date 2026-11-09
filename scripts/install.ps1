# Installs or updates Sippier on Windows from the newest GitHub release,
# pre-releases included, into %LOCALAPPDATA%\Programs\Sippier with a Start
# menu entry:
#
#   irm https://raw.githubusercontent.com/codejo-dev/sippier/main/scripts/install.ps1 | iex
#
# The app isn't code-signed yet. Windows warns about unsigned apps that a
# browser downloaded; files PowerShell downloads aren't marked that way.
#
# Environment:
#   SIPPIER_VERSION  the release to install, e.g. v0.2.0 (default: newest)
#   GITHUB_TOKEN     for GitHub's API, against its rate limit (default: `gh auth token`)

& {
  $ErrorActionPreference = 'Stop'
  [Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

  $repo = 'codejo-dev/sippier'
  $api = "https://api.github.com/repos/$repo"

  # The system's own architecture, as Windows records it: the same from any
  # PowerShell, 32-bit or emulated ones included, which .NET's
  # RuntimeInformation.OSArchitecture isn't
  $native = (Get-ItemProperty `
      'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' `
      -Name PROCESSOR_ARCHITECTURE).PROCESSOR_ARCHITECTURE
  $arch = switch ($native) {
    'ARM64' { 'arm64' }
    'AMD64' { 'x64' }
    default { throw "Sippier needs 64-bit Windows (x64 or Arm64), not '$native'" }
  }
  $asset = "Sippier-windows-$arch.zip"

  $token = $env:GITHUB_TOKEN
  if (-not $token -and (Get-Command gh -ErrorAction SilentlyContinue)) {
    try { $token = gh auth token 2>$null } catch { }
  }
  $headers = @{}
  if ($token) { $headers.Authorization = "Bearer $token" }

  $url = "$api/releases?per_page=1"
  if ($env:SIPPIER_VERSION) { $url = "$api/releases/tags/$env:SIPPIER_VERSION" }
  try {
    $releases = Invoke-RestMethod $url -Headers $headers -UseBasicParsing
  } catch {
    throw 'No release found'
  }
  # A list of releases, newest first, or one release
  $release = $releases[0]
  if (-not $release) { throw 'No release found' }
  $tag = $release.tag_name
  $zipAsset = $release.assets | Where-Object name -EQ $asset
  $sumsAsset = $release.assets | Where-Object name -EQ 'SHA256SUMS.txt'
  if (-not $zipAsset -or -not $sumsAsset) { throw "Release $tag has no $asset" }

  # With curl, which Windows has since 10 1803: it doesn't pass the token on
  # when GitHub redirects the download to its storage, where it's refused
  function Save-Asset($url, $file) {
    $options = @('-fsSL', '-H', 'Accept: application/octet-stream', '-o', $file)
    if ($token) { $options += @('-H', "Authorization: Bearer $token") }
    curl.exe @options $url
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $url" }
  }

  $tmp = Join-Path ([IO.Path]::GetTempPath()) "sippier-$([Guid]::NewGuid())"
  New-Item -ItemType Directory $tmp | Out-Null
  try {
    Write-Host "Downloading Sippier $tag ($arch)"
    $zip = Join-Path $tmp $asset
    $sums = Join-Path $tmp 'SHA256SUMS.txt'
    Save-Asset $sumsAsset.url $sums
    Save-Asset $zipAsset.url $zip

    $expected = Get-Content $sums | ForEach-Object {
      $hash, $name = $_ -split '\s+', 2
      if ($name -eq $asset) { $hash }
    }
    if (-not $expected -or (Get-FileHash $zip -Algorithm SHA256).Hash -ne $expected) {
      throw "$asset doesn't match its checksum"
    }

    $dir = Join-Path $env:LOCALAPPDATA 'Programs\Sippier'
    $running = Get-Process sippier -ErrorAction SilentlyContinue |
      Where-Object { $_.Path -like "$dir\*" }
    if ($running) {
      Write-Host 'Closing Sippier'
      $running | Stop-Process -Force
      $running | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
    }
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    Expand-Archive $zip $dir
    $exe = Join-Path $dir 'sippier.exe'
    if (-not (Test-Path $exe)) { throw "$asset has no sippier.exe" }
    Get-ChildItem $dir -Recurse -File | Unblock-File

    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut(
      (Join-Path ([Environment]::GetFolderPath('Programs')) 'Sippier.lnk'))
    $shortcut.TargetPath = $exe
    $shortcut.WorkingDirectory = $dir
    $shortcut.Save()

    Write-Host "Installed Sippier $tag in $dir"
    Start-Process $exe
  } finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
}
