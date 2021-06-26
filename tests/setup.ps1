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

exec { cmd /c call "$env:TEMP\RefreshEnv.cmd" "&&" call "$installPath\pico-setup.cmd" }
