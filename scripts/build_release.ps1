param(
    [string]$FlutterCommand = 'flutter',
    [string]$SigningDirectory = "$env:USERPROFILE/.android/rshop-release",
    [string]$GateScript = "$env:USERPROFILE/.agents/skills/gradle-build-gate/scripts/invoke_gradle_build_gate.py",
    [string]$ThreadName = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $projectRoot
try {
    # S12 local oracle builds may include owner-extracted assets. Public release
    # packaging must wait for S13's original-APK importer and asset-free manifest.
    if ((Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Raw) -match 'assets/socket_media/') {
        throw 'Public release blocked: remove bundled Socket resources and complete the S13 local APK importer first.'
    }
    & (Join-Path $PSScriptRoot 'build_media_shaders.ps1')
    # Official Flutter release preparation filters dev-only native plugins.
    # --config-only returns before Gradle execution; the actual build uses the gate.
    # Do not pass --no-pub: Flutter intentionally skips plugin regeneration then.
    & $FlutterCommand build apk --release --config-only --target-platform android-arm64
    if ($LASTEXITCODE -ne 0) { throw 'Flutter release preparation failed.' }
    $registrant = Join-Path $projectRoot 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
    if ((Get-Content -LiteralPath $registrant -Raw) -match 'IntegrationTestPlugin|FlutterNativeSplashPlugin') {
        throw 'Release registrant still contains dev-only plugins; no Gradle request submitted.'
    }
    . (Join-Path $PSScriptRoot 'release_signing.ps1') -SigningDirectory $SigningDirectory -LoadEnvironment
    $gateArguments = @($GateScript, 'run', '--project', (Join-Path $projectRoot 'android'),
        '--owner-task', 'Verify and package signed R-Shop release', '--kotlin-strategy', 'in-process')
    if ($ThreadName) { $gateArguments += @('--thread-name', $ThreadName) }
    $gateArguments += @('--', ':app:testReleaseUnitTest', ':app:assembleRelease', '-Ptarget-platform=android-arm64')
    & python @gateArguments
    $buildExit = $LASTEXITCODE
} finally {
    Remove-Item Env:/RSHOP_RELEASE_STORE_PASSWORD, Env:/RSHOP_RELEASE_KEY_PASSWORD -ErrorAction SilentlyContinue
    Pop-Location
}
exit $buildExit
