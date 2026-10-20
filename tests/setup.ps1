param(
  [switch]$Quick
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

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

$installer = Get-ChildItem bin\pico-setup-windows-* | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
# Keep this short: CMake embeds the source path in object paths under the build tree, so the install path
# appears twice in some pico-examples paths, and not all bundled tools are long-path aware.
$installPath = Join-Path $env:SystemDrive "Pico"

if ($installer.EndsWith('.exe')) {
  Write-Host "Installing $installer to $installPath"
  # NSIS requires /D= to be the last argument, unquoted
  $elapsed = Measure-Command { Start-Process -FilePath $installer -ArgumentList "/S", "/D=$installPath" -PassThru | Wait-Process }
  Write-Host ("Finished in {0:hh':'mm':'ss}" -f $elapsed)

  # Write-Host "Copying logs"
  # New-Item -Path logs -Type Directory -Force | Out-Null
  # Copy-Item "$installPath\install.log" .\logs

  Update-EnvironmentVariables
} elseif ($installer.EndsWith('.zip')) {
  Write-Host "Extracting $installer to $installPath"
  $elapsed = Measure-Command { Expand-Archive -Path $installer -DestinationPath $installPath -Force }
  Write-Host ("Finished in {0:hh':'mm':'ss}" -f $elapsed)
} else {
  throw "Unknown installer format: $installer"
}

Write-Output "::group::Running pico-setup.cmd"
cmd /c call "$installPath\pico-setup.cmd" -noninteractive -werror
Write-Output "::endgroup::"
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

if ($Quick) {
  Write-Host "Quick mode: skipping pico-build.cmd"
  exit 0
}

$env:PICO_INSTALL_PATH = $installPath
cmd /c call "$PSScriptRoot\pico-build.cmd"
exit $LASTEXITCODE
