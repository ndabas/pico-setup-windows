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
  param ([string] $dir)

  New-Item -Path $dir -Type Directory -Force | Out-Null
}

function exec {
  param ([scriptblock]$private:cmd)

  $private:eap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $global:LASTEXITCODE = 0

  try {
    # Convert stderr in ErrorRecord objects back to strings
    & $cmd 2>&1 | ForEach-Object { "$_" }

    if ($LASTEXITCODE -ne 0) {
      throw "Command '$cmd' exited with code $LASTEXITCODE"
    }
  }
  finally {
    $ErrorActionPreference = $eap
  }
}
