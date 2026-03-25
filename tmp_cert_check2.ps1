try {
    $c = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
        'c:\Users\voron\Documents\Projects\latera\certs\latera-test.pfx',
        'WQgln2YUrdk1EHBc'
    )
    $out = @()
    $out += "=== Certificate Info ==="
    $out += "Subject: $($c.Subject)"
    $out += "Issuer: $($c.Issuer)"
    $out += "NotBefore: $($c.NotBefore)"
    $out += "NotAfter: $($c.NotAfter)"
    $out += "Thumbprint: $($c.Thumbprint)"
    $expired = $c.NotAfter -lt (Get-Date)
    $out += "Expired: $expired"
    $out | Set-Content "c:\Users\voron\Documents\Projects\latera\cert_result.txt"
} catch {
    "ERROR: $($_.Exception.Message)" | Set-Content "c:\Users\voron\Documents\Projects\latera\cert_result.txt"
}
