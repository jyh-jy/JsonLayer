[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern("^https://")]
  [string]$UpdateBaseUrl,

  [string]$IsccPath = "",

  [switch]$SkipFlutterBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$originalLocation = Get-Location

try {
  Set-Location $projectRoot

  $pubspec = Get-Content -Raw -Encoding UTF8 "pubspec.yaml"
  $versionMatch = [regex]::Match(
    $pubspec,
    "(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?\s*$"
  )
  if (-not $versionMatch.Success) {
    throw "pubspec.yaml version must use the form 1.2.3 or 1.2.3+4."
  }

  $shortVersion = $versionMatch.Groups[1].Value
  $packageVersion = $shortVersion
  if ($versionMatch.Groups[2].Success) {
    $packageVersion = "$shortVersion+$($versionMatch.Groups[2].Value)"
  }
  $baseUrl = $UpdateBaseUrl.TrimEnd("/")
  $feedUrl = "$baseUrl/appcast.xml"

  $privateKey = Join-Path $projectRoot "dsa_priv.pem"
  $publicKey = Join-Path $projectRoot "dsa_pub.pem"
  if (-not (Test-Path $privateKey) -or -not (Test-Path $publicKey)) {
    throw "Missing dsa_priv.pem or dsa_pub.pem. Run: dart run auto_updater:generate_keys"
  }

  if (-not $SkipFlutterBuild) {
    & flutter build windows --release "--dart-define=JSON_LAYER_UPDATE_FEED_URL=$feedUrl"
    if ($LASTEXITCODE -ne 0) {
      throw "Flutter Windows release build failed."
    }
  }

  if ([string]::IsNullOrWhiteSpace($IsccPath)) {
    $isccCandidates = @(
      "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
      "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    )
    $IsccPath = $isccCandidates |
      Where-Object { Test-Path $_ } |
      Select-Object -First 1
  }
  if ([string]::IsNullOrWhiteSpace($IsccPath) -or -not (Test-Path $IsccPath)) {
    throw "Inno Setup 6 was not found. Pass its ISCC.exe path with -IsccPath."
  }

  & $IsccPath `
    "/DMyAppVersion=$shortVersion" `
    "/DMyAppUpdatesUrl=$feedUrl" `
    "installer\json_layer.iss"
  if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed."
  }

  $installerName = "JsonLayer-$shortVersion-windows-x64-setup.exe"
  $installerPath = Join-Path $projectRoot "dist\inno_setup\$installerName"
  if (-not (Test-Path $installerPath)) {
    throw "Installer was not generated at $installerPath."
  }

  if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
    $gitOpenSslDirectory = "C:\Program Files\Git\mingw64\bin"
    if (Test-Path (Join-Path $gitOpenSslDirectory "openssl.exe")) {
      $env:PATH = "$gitOpenSslDirectory;$env:PATH"
    }
  }
  if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
    throw "OpenSSL was not found. Install OpenSSL or Git for Windows."
  }

  $signatureOutput = (
    & dart run auto_updater:sign_update $installerPath $privateKey 2>&1 |
      Out-String
  )
  if ($LASTEXITCODE -ne 0) {
    throw "Update package signing failed: $signatureOutput"
  }

  $signatureMatch = [regex]::Match(
    $signatureOutput,
    'sparkle:dsaSignature="([^"]+)"'
  )
  if (-not $signatureMatch.Success) {
    throw "Could not read the DSA signature from auto_updater output."
  }

  $signature = $signatureMatch.Groups[1].Value
  $length = (Get-Item $installerPath).Length
  $releaseDate = [DateTimeOffset]::UtcNow.ToString(
    "ddd, dd MMM yyyy HH:mm:ss '+0000'",
    [Globalization.CultureInfo]::InvariantCulture
  )

  $outputDirectory = Join-Path $projectRoot "dist\update"
  New-Item -ItemType Directory -Force $outputDirectory | Out-Null
  Copy-Item $installerPath (Join-Path $outputDirectory $installerName) -Force

  $releaseNotesSource = Join-Path $projectRoot "updates\release-notes.html"
  $releaseNotesTarget = Join-Path $outputDirectory "release-notes.html"
  $releaseNotes = Get-Content -Raw -Encoding UTF8 $releaseNotesSource
  $releaseNotes = $releaseNotes.Replace("{{VERSION}}", $shortVersion)
  [IO.File]::WriteAllText(
    $releaseNotesTarget,
    $releaseNotes,
    [Text.UTF8Encoding]::new($false)
  )

  $xmlBaseUrl = [Security.SecurityElement]::Escape($baseUrl)
  $xmlInstallerName = [Security.SecurityElement]::Escape($installerName)
  $xmlSignature = [Security.SecurityElement]::Escape($signature)
  $xmlVersion = [Security.SecurityElement]::Escape($packageVersion)

  $appcast = @"
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>JsonLayer Windows Updates</title>
    <description>JsonLayer Windows release channel</description>
    <language>zh-cn</language>
    <item>
      <title>JsonLayer $shortVersion</title>
      <sparkle:releaseNotesLink>$xmlBaseUrl/release-notes.html</sparkle:releaseNotesLink>
      <pubDate>$releaseDate</pubDate>
      <enclosure
        url="$xmlBaseUrl/$xmlInstallerName"
        sparkle:dsaSignature="$xmlSignature"
        sparkle:version="$xmlVersion"
        sparkle:os="windows"
        length="$length"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
"@

  $appcastPath = Join-Path $outputDirectory "appcast.xml"
  [IO.File]::WriteAllText(
    $appcastPath,
    $appcast,
    [Text.UTF8Encoding]::new($false)
  )

  Write-Host ""
  Write-Host "Release prepared: $outputDirectory"
  Write-Host "Feed URL: $feedUrl"
  Write-Host "Upload every file in dist\update to: $baseUrl/"
} finally {
  Set-Location $originalLocation
}
