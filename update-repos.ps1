#Requires -Version 7.4

<#
.SYNOPSIS
Updates the repository trees in config\repositories.json for a Pico SDK release.

.PARAMETER SdkVersion
The Pico SDK version to update to, e.g. 2.3.1. Defaults to the latest released version.

.PARAMETER Develop
Update to the development versions instead of a release. Repositories with a develop branch (in href, or in
upstream if href does not have one) are set to it, and other repositories are updated for the latest SDK release.
#>

[CmdletBinding(DefaultParameterSetName = 'Release')]
param (
  [Parameter(ParameterSetName = 'Release')]
  [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')]
  [string] $SdkVersion,

  [Parameter(ParameterSetName = 'Develop', Mandatory)]
  [switch] $Develop
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoriesPath = "$PSScriptRoot\config\repositories.json"

# Matches e.g. 2.2.0, sdk-2.2.0, 2.2.0-a4, 2.1.0-correct-picotool
$versionRefPattern = '^(?<prefix>.*?)(?<version>[0-9]+\.[0-9]+\.[0-9]+)(?<suffix>-.+)?$'

# Suffixes that indicate a pre-release rather than a post-release fix
$preReleaseSuffixPattern = '^-(rc|alpha|beta|pre|dev)'

function getRemoteRefs {
  param ([string] $Href)

  $refs = git ls-remote --tags --heads --refs $Href
  if ($LASTEXITCODE -ne 0) {
    throw "git ls-remote failed for $Href"
  }

  $refs |
    ForEach-Object { ($_ -split "`t")[1] -replace '^refs/(tags|heads)/', '' } |
    Select-Object -Unique
}

function getVersionRefs {
  param (
    [string[]] $Refs,
    [string] $Prefix
  )

  foreach ($ref in $Refs) {
    if ($ref -match $versionRefPattern -and $Matches.prefix -ceq $Prefix) {
      $suffix = $Matches.ContainsKey('suffix') ? $Matches.suffix : ''

      if ($suffix -notmatch $preReleaseSuffixPattern) {
        [pscustomobject]@{
          Name    = $ref
          Version = [version]$Matches.version
          Suffix  = $suffix
        }
      }
    }
  }
}

function naturalSortKey {
  param ([string] $Value)

  [regex]::Replace($Value, '[0-9]+', { $args[0].Value.PadLeft(10, '0') })
}

# For a given base version, a bare tag (2.2.0) is older than any fix tags (2.2.0-a4)
function sortVersionRefs {
  param ([Parameter(ValueFromPipeline)] $InputObject)

  end {
    $input | Sort-Object Version, { $_.Suffix -ne '' }, { naturalSortKey $_.Suffix }
  }
}

function updateRepoTree {
  param (
    $Repo,
    [string[]] $Refs,
    [version] $TargetVersion
  )

  if ($Repo.tree -notmatch $versionRefPattern) {
    Write-Warning "$($Repo.href): tree '$($Repo.tree)' is not a version, skipping"
    return
  }

  $prefix = $Matches.prefix

  # Repositories are not always tagged for every SDK release, so take the newest version not after the target
  $best = getVersionRefs $Refs $prefix |
    Where-Object Version -le $TargetVersion |
    sortVersionRefs |
    Select-Object -Last 1

  if (-not $best) {
    Write-Warning "$($Repo.href): no tree found for $TargetVersion, leaving at $($Repo.tree)"
    return
  }

  if ($best.Version.Major -ne $TargetVersion.Major -or $best.Version.Minor -ne $TargetVersion.Minor) {
    Write-Warning "$($Repo.href): newest tree for $TargetVersion is $($best.Name)"
  }

  $note = $best.Version -eq $TargetVersion ? '' : " (no $TargetVersion tree)"
  Write-Host "$($Repo.href): $($Repo.tree) -> $($best.Name)$note"

  $Repo.tree = $best.Name
}

function hasBranch {
  param (
    [string] $Href,
    [string] $Branch
  )

  git ls-remote --exit-code --heads $Href "refs/heads/$Branch" | Out-Null
  switch ($LASTEXITCODE) {
    0 { $true }
    2 { $false }
    default { throw "git ls-remote failed for $Href" }
  }
}

function updateRepoToDevelop {
  param ($Repo)

  $upstream = $Repo.PSObject.Properties['upstream']

  if (hasBranch $Repo.href $developBranch) {
    $href = $Repo.href
  } elseif ($upstream -and (hasBranch $upstream.Value $developBranch)) {
    # Forks only carry release fixes, so take develop from upstream directly
    $href = $upstream.Value
    $Repo.PSObject.Properties.Remove('upstream')
  } else {
    return $false
  }

  Write-Host "$($Repo.href): $($Repo.tree) -> $href $developBranch"
  $Repo.href = $href
  $Repo.tree = $developBranch
  return $true
}

$developBranch = 'develop'

$config = Get-Content $repositoriesPath | ConvertFrom-Json

$sdkRepo = $config.repositories | Where-Object href -match '/pico-sdk(\.git)?$'
$sdkRefs = getRemoteRefs $sdkRepo.href
$sdkPrefix = $sdkRepo.tree -match $versionRefPattern ? $Matches.prefix : ''

# SDK releases always have a bare version tag, even if later fixes get suffixed tags
$sdkReleases = getVersionRefs $sdkRefs $sdkPrefix | Where-Object Suffix -eq ''

if ($SdkVersion) {
  if (-not ($sdkReleases | Where-Object Version -eq ([version]$SdkVersion))) {
    throw "Pico SDK version $SdkVersion not found"
  }
} else {
  $SdkVersion = ($sdkReleases | sortVersionRefs | Select-Object -Last 1).Version.ToString()
}

Write-Host "Pico SDK $($Develop ? 'development' : 'release') version: $SdkVersion"

foreach ($repo in $config.repositories) {
  if ($repo.href -match '/riscv-gnu-toolchain(\.git)?$') {
    $latest = getRemoteRefs $repo.href |
      Where-Object { $_ -match '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$' } |
      Sort-Object |
      Select-Object -Last 1

    if ($latest) {
      Write-Host "$($repo.href): $($repo.tree) -> $latest"
      $repo.tree = $latest
    } else {
      Write-Warning "$($repo.href): no release tags found, leaving at $($repo.tree)"
    }

    continue
  }

  if ($Develop) {
    if (updateRepoToDevelop $repo) {
      continue
    }

    if ($repo -eq $sdkRepo) {
      throw "$($repo.href): no $developBranch branch found"
    }

    Write-Host "$($repo.href): no $developBranch branch, using SDK $SdkVersion tree"
  }

  $refs = $repo -eq $sdkRepo ? $sdkRefs : (getRemoteRefs $repo.href)
  updateRepoTree $repo $refs ([version]$SdkVersion)
}

$config | ConvertTo-Json -Depth 4 | Set-Content $repositoriesPath
