[CmdletBinding()]
param(
  [string]$FlutterExecutable = 'flutter',
  [string]$MsixVersion = '',
  [string]$CertificatePath = '',
  [string]$CertificatePassword = '',
  [string]$Publisher = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$packagePath = Join-Path $repositoryRoot 'build\windows\x64\installer\PEeK-x64.msix'
$releaseDirectory = Join-Path $repositoryRoot 'build\windows\x64\runner\Release'
$flutterNoticesPath = Join-Path $releaseDirectory 'data\flutter_assets\NOTICES.Z'
$generatedNoticesPath = Join-Path $repositoryRoot 'THIRD_PARTY_NOTICES.txt'

if ($MsixVersion -and $MsixVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') {
  throw "Invalid MSIX version '$MsixVersion'. Expected four numeric parts, for example 1.2.3.0."
}
if ($MsixVersion) {
  $versionParts = $MsixVersion.Split('.') | ForEach-Object { [int]$_ }
  if ($versionParts.Where({ $_ -gt 65535 }).Count -gt 0) {
    throw 'Every MSIX version part must be between 0 and 65535.'
  }
}

if ($CertificatePath) {
  if (-not (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) {
    throw "Signing certificate not found: $CertificatePath"
  }
  if (-not $CertificatePassword) {
    throw 'CertificatePassword is required when CertificatePath is provided.'
  }
  if (-not $Publisher) {
    throw 'Publisher is required when CertificatePath is provided.'
  }
} elseif ($CertificatePassword -or $Publisher) {
  throw 'CertificatePath is required when CertificatePassword or Publisher is provided.'
}

if ([IO.Path]::IsPathRooted($FlutterExecutable)) {
  if (-not (Test-Path -LiteralPath $FlutterExecutable -PathType Leaf)) {
    throw "Flutter executable not found: $FlutterExecutable"
  }
  $flutterCommand = (Resolve-Path -LiteralPath $FlutterExecutable).Path
} else {
  $resolvedFlutter = Get-Command $FlutterExecutable -ErrorAction SilentlyContinue
  if ($null -eq $resolvedFlutter) {
    throw 'Flutter was not found. Pass -FlutterExecutable with the path to flutter.bat.'
  }
  $flutterCommand = $resolvedFlutter.Source
}

$flutterDirectory = Split-Path -Parent $flutterCommand
$dartCandidate = Join-Path $flutterDirectory 'dart.bat'
if (Test-Path -LiteralPath $dartCandidate -PathType Leaf) {
  $dartCommand = $dartCandidate
} else {
  $resolvedDart = Get-Command 'dart' -ErrorAction SilentlyContinue
  if ($null -eq $resolvedDart) {
    throw 'Dart was not found next to Flutter or on PATH.'
  }
  $dartCommand = $resolvedDart.Source
}

Push-Location $repositoryRoot
try {
  & $flutterCommand pub get
  if ($LASTEXITCODE -ne 0) {
    throw "flutter pub get failed with exit code $LASTEXITCODE."
  }

  $flutterBuildArguments = @('build', 'windows', '--release')
  if ($MsixVersion) {
    $flutterBuildArguments += @(
      '--build-name'
      ($versionParts[0..2] -join '.')
      '--build-number'
      $versionParts[3]
    )
  }

  & $flutterCommand @flutterBuildArguments
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter release build failed with exit code $LASTEXITCODE."
  }

  & $dartCommand run tool\generate_third_party_notices.dart `
    --flutter-notices $flutterNoticesPath `
    --output $generatedNoticesPath
  if ($LASTEXITCODE -ne 0) {
    throw "Third-party notice generation failed with exit code $LASTEXITCODE."
  }
  Copy-Item -LiteralPath $generatedNoticesPath `
    -Destination (Join-Path $releaseDirectory 'THIRD_PARTY_NOTICES.txt') `
    -Force

  $msixArguments = @(
    'run'
    'msix:create'
    '--build-windows'
    'false'
    '--install-certificate'
    'false'
  )
  if ($MsixVersion) {
    $msixArguments += @('--version', $MsixVersion)
  }
  if ($CertificatePath) {
    $msixArguments += @(
      '--certificate-path'
      (Resolve-Path -LiteralPath $CertificatePath).Path
      '--certificate-password'
      $CertificatePassword
      '--publisher'
      $Publisher
    )
  }

  & $dartCommand @msixArguments
  if ($LASTEXITCODE -ne 0) {
    throw "MSIX packaging failed with exit code $LASTEXITCODE."
  }
} finally {
  Pop-Location
}

if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
  throw "MSIX package was not created at the expected path: $packagePath"
}

$hash = Get-FileHash -LiteralPath $packagePath -Algorithm SHA256
$hashPath = "$packagePath.sha256"
[IO.File]::WriteAllText(
  $hashPath,
  "$($hash.Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($packagePath))`n"
)

Write-Output "Package: $packagePath"
Write-Output "SHA256: $($hash.Hash.ToLowerInvariant())"
if ($CertificatePath) {
  Write-Output "Signing publisher: $Publisher"
} else {
  Write-Output 'This development package uses a self-signed test certificate. Do not distribute it as a production release.'
}
