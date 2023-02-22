Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. "$PSScriptRoot\..\common.ps1"

$installer = Get-ChildItem bin\*.exe | Select-Object -First 1 -ExpandProperty FullName
Write-Host "Starting $installer"
$elapsed = Measure-Command { Start-Process -FilePath $installer -ArgumentList "/S" -Wait }
Write-Host ("Finished in {0:hh':'mm':'ss}" -f $elapsed)

$installPath = "$([Environment]::GetFolderPath("MyDocuments"))\Pico"

Write-Host "Copying logs"
mkdirp logs
Copy-Item $env:TEMP\dd_*.log .\logs
Copy-Item "$installPath\install.log" .\logs

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

exec { cmd /c call "$installPath\pico-setup.cmd" }
