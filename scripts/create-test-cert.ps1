# Create Test Certificate for MSIX Signing
# Usage: .\scripts\create-test-cert.ps1 [-Password "your-password"] [-OutputDir ".\certs"]
#
# This script creates a self-signed PFX certificate for testing MSIX packages.
# For production/Store distribution, use a proper code signing certificate.
#
# IMPORTANT: 
# - Test certificates are for development only
# - Self-signed certificates require manual installation on target machines
# - Store distribution requires a certificate from Microsoft Partner Center

param(
    [string]$Password = "",
    [string]$OutputDir = ".\certs",
    [string]$Subject = "CN=LateraTeam, O=Latera, C=BY",
    [string]$FriendlyName = "Latera Test Signing Certificate",
    [int]$ValidityYears = 5,
    [switch]$ShowPassword
)

$ErrorActionPreference = "Stop"

Write-Host "=== Latera Test Certificate Generator ===" -ForegroundColor Cyan
Write-Host "Subject: $Subject" -ForegroundColor Gray
Write-Host "Output: $OutputDir" -ForegroundColor Gray

# Create output directory if it doesn't exist
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$OutputPath = Join-Path $ProjectRoot $OutputDir

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-Host "Created output directory: $OutputPath" -ForegroundColor Gray
}

# Generate password if not provided
if ([string]::IsNullOrEmpty($Password)) {
    $Password = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
}

# Save password to file (more secure than console output)
$passwordPath = Join-Path $OutputPath "cert-password.txt"
$Password | Out-File -FilePath $passwordPath -Encoding ASCII -NoNewline

if ($ShowPassword) {
    Write-Host "Generated password: $Password" -ForegroundColor Yellow
    Write-Host "SAVE THIS PASSWORD - you'll need it for signing!" -ForegroundColor Yellow
} else {
    Write-Host "Password saved to: $passwordPath" -ForegroundColor Gray
    Write-Host "Use -ShowPassword to display password in console (not recommended in CI)" -ForegroundColor Gray
}

$SecurePassword = ConvertTo-SecureString -String $Password -Force -AsPlainText

# Check if certificate already exists in store
$ExistingCert = Get-ChildItem -Path Cert:\CurrentUser\My | Where-Object { $_.Subject -eq $Subject }

if ($ExistingCert) {
    Write-Host "`nWARNING: Certificate with subject '$Subject' already exists in store:" -ForegroundColor Yellow
    foreach ($cert in $ExistingCert) {
        Write-Host "  Thumbprint: $($cert.Thumbprint)" -ForegroundColor Gray
        Write-Host "  Expires: $($cert.NotAfter)" -ForegroundColor Gray
    }
    
    $response = Read-Host "Do you want to create a new certificate anyway? (y/N)"
    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-Host "Aborted. Using existing certificate." -ForegroundColor Yellow
        exit 0
    }
}

# Create the certificate
Write-Host "`nCreating self-signed certificate..." -ForegroundColor Yellow

$cert = New-SelfSignedCertificate `
    -Type Custom `
    -Subject $Subject `
    -KeyUsage DigitalSignature `
    -FriendlyName $FriendlyName `
    -CertStoreLocation Cert:\CurrentUser\My `
    -TextExtension @(
        "2.5.29.37={text}1.3.6.1.5.5.7.3.3",  # Code Signing
        "2.5.29.19={text}"  # Basic Constraints (not a CA)
    ) `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -NotAfter (Get-Date).AddYears($ValidityYears)

Write-Host "Certificate created successfully!" -ForegroundColor Green
Write-Host "  Thumbprint: $($cert.Thumbprint)" -ForegroundColor Gray
Write-Host "  Subject: $($cert.Subject)" -ForegroundColor Gray
Write-Host "  Expires: $($cert.NotAfter)" -ForegroundColor Gray

# Export to PFX
$pfxPath = Join-Path $OutputPath "latera-test.pfx"
$cerPath = Join-Path $OutputPath "latera-test.cer"

Write-Host "`nExporting certificate..." -ForegroundColor Yellow

Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $SecurePassword | Out-Null
Export-Certificate -Cert $cert -FilePath $cerPath -Type CERT | Out-Null

Write-Host "Exported files:" -ForegroundColor Green
Write-Host "  PFX (private key): $pfxPath" -ForegroundColor Gray
Write-Host "  CER (public key):  $cerPath" -ForegroundColor Gray

# Generate Base64 for GitHub Secrets
$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($pfxPath))

Write-Host "`n=== GitHub Secrets Configuration ===" -ForegroundColor Cyan
Write-Host "Add these secrets to your GitHub repository:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. BASE64_CERT:" -ForegroundColor White
Write-Host "   (See base64-cert.txt in output directory)" -ForegroundColor Gray
Write-Host ""
Write-Host "2. CERT_PASSWORD:" -ForegroundColor White
if ($ShowPassword) {
    Write-Host "   $Password" -ForegroundColor Gray
} else {
    Write-Host "   (See cert-password.txt in output directory)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "3. CERT_SHA1 (optional):" -ForegroundColor White
Write-Host "   $($cert.Thumbprint)" -ForegroundColor Gray

# Save Base64 to file
$base64Path = Join-Path $OutputPath "base64-cert.txt"
$base64 | Out-File -FilePath $base64Path -Encoding ASCII -NoNewline

Write-Host "`nBase64 certificate saved to: $base64Path" -ForegroundColor Gray

# Add to .gitignore
$gitignorePath = Join-Path $ProjectRoot ".gitignore"
$gitignoreEntry = "`n# Test certificates`ncerts/`n*.pfx`n*.cer`nbase64-cert.txt"

if (Test-Path $gitignorePath) {
    $gitignoreContent = Get-Content $gitignorePath -Raw
    if ($gitignoreContent -notmatch "certs/") {
        Add-Content -Path $gitignorePath -Value $gitignoreEntry
        Write-Host "`nAdded 'certs/' to .gitignore" -ForegroundColor Gray
    }
}

Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. Install the certificate on test machines:" -ForegroundColor White
Write-Host "   Double-click latera-test.cer -> Install Certificate -> Local Machine -> Trusted People" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Build signed MSIX:" -ForegroundColor White
Write-Host "   .\scripts\build.ps1 -Release -Msix" -ForegroundColor Gray
Write-Host ""
Write-Host "3. For CI/CD, add secrets to GitHub:" -ForegroundColor White
Write-Host "   Repository -> Settings -> Secrets and variables -> Actions -> New repository secret" -ForegroundColor Gray
Write-Host ""
Write-Host "=== IMPORTANT ===" -ForegroundColor Red
Write-Host "This is a TEST certificate for development only!" -ForegroundColor Yellow
Write-Host "For Store distribution, use a certificate from Partner Center." -ForegroundColor Yellow
Write-Host "For external distribution, use a proper code signing certificate." -ForegroundColor Yellow