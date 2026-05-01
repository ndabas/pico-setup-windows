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

#Requires -Version 7.2

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$remoteCommit = ((Get-Content .\config\repositories.json | ConvertFrom-Json).repositories |
  Where-Object { $_.href -like "*${Repo}.git" } |
  ForEach-Object { git ls-remote $_.href $_.tree }).Split("`t")[0]

$msystem = (Get-Content $ConfigFile | ConvertFrom-Json).msysEnv

"$($Repo.ToUpperInvariant())_BUILD_ID=$Repo-$remoteCommit-$msystem"
