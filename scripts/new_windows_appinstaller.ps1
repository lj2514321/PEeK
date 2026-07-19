[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^https://')]
  [string]$BaseUri,

  [string]$PackagePath,

  [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PackagePath)) {
  $PackagePath = Join-Path $repositoryRoot 'build\windows\x64\installer\PEeK-x64.msix'
}
$resolvedPackage = (Resolve-Path -LiteralPath $PackagePath -ErrorAction Stop).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path (Split-Path -Parent $resolvedPackage) 'PEeK.appinstaller'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($resolvedPackage)
try {
  $manifestEntry = $archive.GetEntry('AppxManifest.xml')
  if ($null -eq $manifestEntry) {
    throw 'AppxManifest.xml is missing from the MSIX package.'
  }
  $reader = [IO.StreamReader]::new($manifestEntry.Open())
  try {
    [xml]$manifest = $reader.ReadToEnd()
  } finally {
    $reader.Dispose()
  }
} finally {
  $archive.Dispose()
}

$identity = $manifest.Package.Identity
$name = [Security.SecurityElement]::Escape([string]$identity.Name)
$publisher = [Security.SecurityElement]::Escape([string]$identity.Publisher)
$version = [Security.SecurityElement]::Escape([string]$identity.Version)
$architecture = [Security.SecurityElement]::Escape([string]$identity.ProcessorArchitecture)
$normalizedBaseUri = $BaseUri.TrimEnd('/')
$packageFileName = [IO.Path]::GetFileName($resolvedPackage)
$packageUri = [Security.SecurityElement]::Escape("$normalizedBaseUri/$packageFileName")
$appInstallerUri = [Security.SecurityElement]::Escape("$normalizedBaseUri/PEeK.appinstaller")

$content = @"
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller xmlns="http://schemas.microsoft.com/appx/appinstaller/2021"
              Uri="$appInstallerUri"
              Version="$version">
  <MainPackage Name="$name"
               Publisher="$publisher"
               Version="$version"
               ProcessorArchitecture="$architecture"
               Uri="$packageUri" />
  <UpdateSettings>
    <OnLaunch HoursBetweenUpdateChecks="24"
              ShowPrompt="true"
              UpdateBlocksActivation="false" />
    <AutomaticBackgroundTask />
  </UpdateSettings>
</AppInstaller>
"@

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
  [IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}
[IO.File]::WriteAllText(
  $OutputPath,
  $content,
  [Text.UTF8Encoding]::new($false)
)

[xml]$validated = [IO.File]::ReadAllText($OutputPath)
if ($validated.AppInstaller.MainPackage.Name -ne $identity.Name) {
  throw 'Generated App Installer identity does not match the MSIX package.'
}

Write-Output "App Installer: $OutputPath"
Write-Output "Package URI: $normalizedBaseUri/$packageFileName"
