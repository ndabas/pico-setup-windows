param (
  [ValidateNotNullOrEmpty()]
  [string]
  $VSInstallerPath = '.\installers\vs_BuildTools.exe',

  [ValidateNotNullOrEmpty()]
  [string]
  $VSWherePath = '.\installers\vswhere.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$installerVersion = [version](Get-Item $VSInstallerPath).VersionInfo.FileVersion
$interval = "[{0},{1})" -f $installerVersion.Major, ($installerVersion.Major + 1)

$VSInstallerPath -match 'vs_([a-zA-Z]+).exe' | Out-Null
$product = $Matches[1]

Write-Host "Looking for existing Visual Studio $product installs: " -NoNewline
$modify = ""
$existingInstallPath = & $VSWherePath -products "Microsoft.VisualStudio.Product.$product" -version $interval -latest -property installationPath
if ($existingInstallPath) {
  $modify = "modify --installPath `"$existingInstallPath`""
  Write-Host $existingInstallPath
}
else {
  Write-Host "not found"
}

$installArgs = "$modify --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --quiet --wait --norestart"
Write-Host "Starting $VSInstallerPath $installArgs"
$process = Start-Process -FilePath $VSInstallerPath -ArgumentList $installArgs -Wait -PassThru
exit $process.ExitCode
