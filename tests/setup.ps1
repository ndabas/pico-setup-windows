Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$installer = Get-ChildItem bin\*.exe | Select-Object -First 1 -ExpandProperty FullName
Write-Host "Starting $installer"
$elapsed = Measure-Command { Start-Process -FilePath $installer -ArgumentList "/S" -Wait }
Write-Host ("Finished in {0:hh':'mm':'ss}" -f $elapsed)

$uninstRegKey = "Microsoft\Windows\CurrentVersion\Uninstall\Raspberry Pi Pico SDK*"
$installPath = (Get-ItemProperty -Path "HKCU:\Software\$uninstRegKey", "HKLM:\Software\$uninstRegKey", "HKLM:\Software\WOW6432Node\$uninstRegKey" -Name InstallPath -ErrorAction SilentlyContinue).InstallPath

# Write-Host "Copying logs"
# New-Item -Path logs -Type Directory -Force | Out-Null
# Copy-Item "$installPath\install.log" .\logs

# See: https://stackoverflow.com/a/22670892/12156188
function Update-EnvironmentVariables {
  foreach ($level in "Machine", "User") {
    [Environment]::GetEnvironmentVariables($level).GetEnumerator() | ForEach-Object {
      # For Path variables, append the new values, if they're not already in there
      if ($_.Name -match 'Path$') {
        $_.Value = ($((Get-Content "Env:$($_.Name)") + ";$($_.Value)") -split ';' | Select-Object -Unique) -join ';'
      }
      $_
    } | Set-Content -Path { "Env:$($_.Name)" }
  }
}

Update-EnvironmentVariables

cmd /c call "$installPath\pico-setup.cmd" "$([Environment]::GetFolderPath("MyDocuments"))\Pico"
