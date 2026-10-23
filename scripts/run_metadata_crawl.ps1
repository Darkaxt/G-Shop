[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Manifest,
  [Parameter(Mandatory)][string]$OutputDirectory,
  [Parameter(Mandatory)][string]$RuntimeDirectory,
  [Parameter(Mandatory)][string]$DartCommand,
  [Parameter(Mandatory)][string]$JavaHome,
  [Parameter(Mandatory)][string]$XzJar,
  [string]$CredentialsFile = '.env.local',
  [long]$MaxArchiveBytes = 0
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$javac = Join-Path $JavaHome 'bin/javac.exe'
$java = Join-Path $JavaHome 'bin/java.exe'
if ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($OutputDirectory)) -ine 'E:\') {
  throw 'Persistent crawl/cache output belongs on E:, not the Drive virtual unit.'
}
foreach ($file in @($Manifest, $DartCommand, $javac, $java, $XzJar)) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'A required input/runtime is missing.' }
}
New-Item -ItemType Directory -Path $RuntimeDirectory -Force | Out-Null
$classes = [IO.Path]::GetFullPath($RuntimeDirectory)
& $javac -cp $XzJar -d $classes `
  (Join-Path $repo 'android/app/src/main/java/com/retro/rshop/OwnedArchiveIdentity.java') `
  (Join-Path $repo 'android/app/src/main/java/com/retro/rshop/OwnedN64SevenZip.java') `
  (Join-Path $PSScriptRoot 'DesktopArchiveIdentifier.java')
if ($LASTEXITCODE -ne 0) { throw 'Archive reader compilation failed.' }
Push-Location $repo
try {
  & $DartCommand (Join-Path $PSScriptRoot 'crawl_metadata.dart') `
    --manifest ([IO.Path]::GetFullPath($Manifest)) `
    --output ([IO.Path]::GetFullPath($OutputDirectory)) `
    --java $java --archive-classpath "$classes$([IO.Path]::PathSeparator)$XzJar" `
    --credentials ([IO.Path]::GetFullPath($CredentialsFile)) --max-archive-bytes $MaxArchiveBytes
  if ($LASTEXITCODE -ne 0) { throw 'Metadata crawl requires attention; retain its checkpoint.' }
} finally { Pop-Location }
