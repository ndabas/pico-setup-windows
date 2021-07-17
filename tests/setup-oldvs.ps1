# Install an older version of Visual Studio 2019 Build Tools, for testing if the installer can
# properly modify an existing install to add the Visual C++ tools needed.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. "$PSScriptRoot\..\common.ps1"

# BuildTools 16.4.24 from https://docs.microsoft.com/en-us/visualstudio/releases/2019/history
$href = "https://download.visualstudio.microsoft.com/download/pr/755cef87-e337-468d-bc48-7c0426929076/90deefbf24f4a074ea9df5ee42c56152f7a57229655fe4d44477a32bb0a23d55/vs_BuildTools.exe"
$file = "vs_BuildTools.exe"

Write-Host "Downloading $file"
exec { curl.exe --fail --silent --show-error --url $href --location --output "installers/$file" --create-dirs }

Write-Host "Starting $file"
$process = $null
$elapsed = Measure-Command { $process = Start-Process -FilePath ".\installers\$file" -ArgumentList '--add Microsoft.VisualStudio.Workload.DataBuildTools --quiet --wait --norestart' -Wait -PassThru }
Write-Host ("Finished in {0:hh':'mm':'ss}" -f $elapsed)

if ($process.ExitCode -ne 0) {
  throw "Install failed with exit code $($process.ExitCode)"
  exit $process.ExitCode
}
