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
