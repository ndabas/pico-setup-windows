#Requires -Version 7.2

function crawl {
  param ([string]$url)

  (Invoke-WebRequest $url -UseBasicParsing).Links |
    Where-Object {
      ($_ | Get-Member href) -and
      [uri]::IsWellFormedUriString($_.href, [System.UriKind]::RelativeOrAbsolute)
    } |
    ForEach-Object {
      $href = [System.Net.WebUtility]::HtmlDecode($_.href)

      try {
        (New-Object System.Uri([uri]$url, $href)).AbsoluteUri
      }
      catch {
        $href
      }
    }
}

function mkdirp {
  param ([string] $dir, [switch] $clean)

  New-Item -Path $dir -Type Directory -Force | Out-Null

  if ($clean) {
    Remove-Item -Path "$dir\*" -Recurse -Force
  }
}

function exec {
  param ([scriptblock]$private:cmd)

  $global:LASTEXITCODE = 0

  & $cmd

  if ($LASTEXITCODE -ne 0) {
    throw "Command '$cmd' exited with code $LASTEXITCODE"
  }
}
