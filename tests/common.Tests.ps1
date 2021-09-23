BeforeAll {
  Set-StrictMode -Version Latest
  $ErrorActionPreference = 'Stop'

  . "$PSScriptRoot\..\common.ps1"
}

Describe 'exec' {
  It 'Should run native command' {
    exec { cmd /c echo Hello world! } | Should -Be 'Hello world!'
  }

  It 'Should capture stderr' {
    exec { cmd /c "echo Oops 1>&2" } | Should -Be 'Oops '
  }

  It 'Should throw on non-zero exit code' {
    { exec { cmd /c exit 42 } } | Should -Throw
  }

  It 'Should not clobber a variable named cmd' {
    $cmd = 'Yes'
    exec { cmd /c "echo $cmd" } | Should -Be 'Yes'
  }

  It 'Should throw on script errors' {
    { exec { xyzzy } } | Should -Throw
  }
}

Describe 'mkdirp' {
  It 'Should create directory tree' {
    $targetRoot = Join-Path ([IO.Path]::GetTempPath()) (New-Guid)
    $target = Join-Path $targetRoot "a\b\c"

    mkdirp $target

    Test-Path $target -PathType Container | Should -BeTrue
    Remove-Item $targetRoot -Recurse
  }
}
