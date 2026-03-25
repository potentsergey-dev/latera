try {
    $c = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
        'c:\Users\voron\Documents\Projects\latera\certs\latera-test.pfx',
        'WQgln2YUrdk1EHBc'
    )
    Write-Output "=== Certificate Info ==="
    Write-Output "Subject: $($c.Subject)"
    Write-Output "Issuer: $($c.Issuer)"
    Write-Output "NotBefore: $($c.NotBefore)"
    Write-Output "NotAfter: $($c.NotAfter)"
    Write-Output "Thumbprint: $($c.Thumbprint)"
    Write-Output "SerialNumber: $($c.SerialNumber)"
    $expired = $c.NotAfter -lt (Get-Date)
    Write-Output "Expired: $expired"
} catch {
    Write-Output "ERROR: $($_.Exception.Message)"
}
