param (
  [Parameter(Mandatory = $true,
    Position = 0,
    HelpMessage = "Base name of the repository to check.")]
  [ValidateNotNullOrEmpty()]
  [string]
  $Repo,

  [Parameter(Mandatory = $true,
    Position = 1,
    HelpMessage = "Path to a compile configuration file.")]
  [Alias("PSPath")]
  [ValidateNotNullOrEmpty()]
  [string]
  $ConfigFile
)

#Requires -Version 7.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$remoteCommit = ((Get-Content .\config\repositories.json | ConvertFrom-Json).repositories |
  Where-Object { $_.href -like "*${Repo}.git" } |
  ForEach-Object { git ls-remote $_.href $_.tree }).Split("`t")[0]

if ($remoteCommit -notmatch '^[0-9a-f]{40}$') {
  Write-Error "Could not resolve remote commit for $Repo (got '$remoteCommit')"
}

$msystem = (Get-Content $ConfigFile | ConvertFrom-Json).msysEnv

"$($Repo.ToUpperInvariant() -replace '[^A-Z0-9]', '_')_BUILD_ID=$Repo-$remoteCommit-$msystem"
