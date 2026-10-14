param(
    [string]$SigningDirectory = "$env:USERPROFILE/.android/rshop-release",
    [switch]$Create,
    [switch]$LoadEnvironment
)
$ErrorActionPreference = 'Stop'
$credentialPath = Join-Path $SigningDirectory 'signing.credential.xml'
$keyPath = Join-Path $SigningDirectory 'rshop-release.p12'
if ($Create) {
    if ((Test-Path -LiteralPath $credentialPath) -or (Test-Path -LiteralPath $keyPath)) {
        throw 'Signing identity already exists; reuse it, never regenerate.'
    }
    New-Item -ItemType Directory -Path $SigningDirectory -Force | Out-Null
    $password = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
    $secure = ConvertTo-SecureString $password -AsPlainText -Force
    [pscredential]::new('rshop-release', $secure) | Export-Clixml -LiteralPath $credentialPath
    $env:RSHOP_NEW_SIGNING_PASSWORD = $password
    try {
        & "$env:JAVA_HOME/bin/keytool.exe" -genkeypair -noprompt -storetype PKCS12 `
            -keystore $keyPath -alias rshop-release -keyalg RSA -keysize 4096 `
            -validity 10000 -dname 'CN=R-Shop Fork, OU=Android, O=Darkaxt' `
            -storepass:env RSHOP_NEW_SIGNING_PASSWORD -keypass:env RSHOP_NEW_SIGNING_PASSWORD
        if ($LASTEXITCODE -ne 0) { throw 'Release identity creation failed; inspect exact outputs before retrying.' }
    } finally {
        Remove-Item Env:/RSHOP_NEW_SIGNING_PASSWORD
        $password = $null
    }
}
if ($LoadEnvironment) {
    $credential = Import-Clixml -LiteralPath $credentialPath
    $env:RSHOP_RELEASE_STORE_FILE = $keyPath
    $env:RSHOP_RELEASE_KEY_ALIAS = 'rshop-release'
    $env:RSHOP_RELEASE_STORE_PASSWORD = $credential.GetNetworkCredential().Password
    $env:RSHOP_RELEASE_KEY_PASSWORD = $env:RSHOP_RELEASE_STORE_PASSWORD
}
Write-Output "Private signing identity: $keyPath (password not displayed)"
