Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. "$PSScriptRoot\pico-env.ps1"

# On first run, open the pico-examples repo. Open a blank VS Code instance otherwise.
$openArgs = "--disable-workspace-trust --new-window `"$env:PICO_EXAMPLES_PATH`""
$regPath = "HKCU:\$env:PICO_REG_KEY"

if (-not (Test-Path $regPath)) {
  New-Item -Path $regPath -Force
}

$regName = 'FirstRun'
$entries = Get-ItemProperty -Path $regPath
if ($entries -and ($entries | Get-Member $regName)) {
  $openArgs = ''
} else {
  Set-ItemProperty -Path $regPath -Name $regName -Value '0'
}

$codeBinDir = Split-Path -Parent (Get-Command 'code.cmd').Path
$codeExeDir = Split-Path -Parent $codeBinDir
$codeExe = Join-Path $codeExeDir 'code.exe'

cmd /s /c "start `"`" `"$codeExe`" $openArgs"
