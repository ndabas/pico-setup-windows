Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. "$PSScriptRoot\pico-env.ps1"

# On first run, open the pico-examples repo. Open a blank VS Code instance otherwise.
$openArgs = "--disable-workspace-trust `"$PSScriptRoot\pico-examples`""
$regPath = 'HKCU:\Software\Raspberry Pi\pico-setup-windows'
$regName = 'FirstRun'
$entries = Get-ItemProperty -Path $regPath
if ($entries | Get-Member $regName) {
  $openArgs = ''
} else {
  Set-ItemProperty -Path $regPath -Name $regName -Value '0'
}

$codeBinDir = Split-Path -Parent (Get-Command 'code.cmd').Path
$codeExeDir = Split-Path -Parent $codeBinDir
$codeExe = Join-Path $codeExeDir 'code.exe'

cmd /s /c "start `"`" `"$codeExe`" --new-window $openArgs"
