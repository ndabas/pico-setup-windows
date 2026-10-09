param (
  [Parameter(Mandatory = $true)]
  [string[]]
  $Path
)

$ErrorActionPreference = 'Stop'

$cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Subject -like "CN=Raspberry Pi*" }
if (-not $cert) {
  Write-Error "No suitable code signing certificates found."
}

$Path | Set-AuthenticodeSignature -Certificate $cert -TimestampServer "http://timestamp.digicert.com" -HashAlgorithm SHA256 | ForEach-Object {
  $_
  if ($_.Status -ne 'Valid') {
    Write-Error "Error signing $($_.Path)"
  }
}
