param(
  [string]$Alias = "mytodo",
  [string]$OutputDir = "android/signing"
)

$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$keystorePath = Join-Path $OutputDir "mytodo-release.jks"

if (Test-Path $keystorePath) {
  throw "Keystore already exists: $keystorePath"
}

function New-Password {
  param([int]$Length = 32)
  $alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%+=_-"
  $bytes = [byte[]]::new($Length)
  [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  $chars = for ($i = 0; $i -lt $Length; $i++) {
    $alphabet[$bytes[$i] % $alphabet.Length]
  }
  -join $chars
}

$storePassword = New-Password
$keyPassword = New-Password

keytool `
  -genkeypair `
  -v `
  -keystore $keystorePath `
  -storetype JKS `
  -alias $Alias `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -storepass $storePassword `
  -keypass $keyPassword `
  -dname "CN=MyTodo, OU=Release, O=MyTodo, L=Local, ST=Local, C=CN"

$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $keystorePath)))

Write-Host ""
Write-Host "Android release keystore created: $keystorePath"
Write-Host ""
Write-Host "Add these GitHub repository secrets:"
Write-Host "MYTODO_ANDROID_KEYSTORE_BASE64=$base64"
Write-Host "MYTODO_ANDROID_KEYSTORE_PASSWORD=$storePassword"
Write-Host "MYTODO_ANDROID_KEY_ALIAS=$Alias"
Write-Host "MYTODO_ANDROID_KEY_PASSWORD=$keyPassword"
Write-Host ""
Write-Host "Keep $keystorePath and these passwords. Losing them means future APKs cannot update installed apps."
