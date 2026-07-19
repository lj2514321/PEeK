[CmdletBinding()]
param(
  [string]$FlutterExecutable = 'flutter'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$packagePath = Join-Path $repositoryRoot 'build\windows\x64\installer\PEeK-x64.msix'

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

  & $flutterCommand build windows --release
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter release build failed with exit code $LASTEXITCODE."
  }

  & $dartCommand run msix:create --build-windows false --install-certificate false
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
Write-Output 'This development package uses a self-signed test certificate. Do not distribute it as a production release.'
