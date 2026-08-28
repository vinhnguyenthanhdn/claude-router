$ErrorActionPreference = 'Stop'

# The Quick start in the README is one command: install.ps1. Until this script
# existed nothing ever ran it - the Windows job parsed it and stopped there - so
# every claim the Quick start makes about the result was unmeasured, and a broken
# installer would have kept CI green while failing every new user at step one.
#
# The expectation below is derived from `git ls-files`, not from the copy list
# inside install.ps1. A filter bug in the installer (a missed extension, a name
# spelled wrong) has to show up here rather than be replayed by it.

$root = Split-Path $PSScriptRoot -Parent
$scriptsDir = Join-Path $root 'scripts'

function Get-ExpectedManagedName {
    $tracked = & git -C $root ls-files 'scripts/*'
    if ($LASTEXITCODE -ne 0) { throw 'Could not list tracked files under scripts/.' }
    $names = @($tracked |
        ForEach-Object { Split-Path $_ -Leaf } |
        Where-Object { $_ -match '\.(ps1|cmd)$' -and $_ -ne 'install.ps1' } |
        Sort-Object)
    if ($names.Count -eq 0) {
        throw 'No tracked Windows script was found under scripts/ - the expectation must never be empty.'
    }
    return $names
}

function Get-InstallProblem {
    param([string]$Dir)

    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($name in Get-ExpectedManagedName) {
        $target = Join-Path $Dir $name
        if (-not (Test-Path -LiteralPath $target)) {
            $problems.Add("Managed script was not installed: $name")
            continue
        }
        $source = Get-Content -LiteralPath (Join-Path $scriptsDir $name) -Raw
        if ((Get-Content -LiteralPath $target -Raw) -ne $source) {
            $problems.Add("Installed copy does not match the repository: $name")
        }
    }
    return $problems
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ("claude-router-install-" + [guid]::NewGuid())
$installDir = Join-Path $temp 'managed'
New-Item -ItemType Directory -Path $temp | Out-Null

try {
    # Negative evidence for the readback: nothing may be there before install runs,
    # otherwise every assertion below could be satisfied by a leftover tree.
    if (Test-Path -LiteralPath $installDir) { throw 'The install directory existed before install.ps1 ran.' }

    $pathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')

    & (Join-Path $scriptsDir 'install.ps1') -InstallDir $installDir -SkipPath

    $problems = @(Get-InstallProblem -Dir $installDir)
    if ($problems.Count -gt 0) { throw ($problems -join '; ') }

    $configPath = Join-Path $installDir 'config.local.json'
    if (-not (Test-Path -LiteralPath $configPath)) { throw 'install.ps1 did not create config.local.json.' }
    $example = Get-Content -LiteralPath (Join-Path $root 'config.example.json') -Raw
    if ((Get-Content -LiteralPath $configPath -Raw) -ne $example) {
        throw 'config.local.json was not created from config.example.json.'
    }

    # -SkipPath is what lets this gate run on a shared runner. If it ever stops
    # meaning that, the gate would start editing the machine it is measuring.
    if ([Environment]::GetEnvironmentVariable('Path', 'User') -ne $pathBefore) {
        throw 'install.ps1 -SkipPath changed the user PATH.'
    }

    # The README makes two claims about re-running the installer after a git pull:
    # it overwrites the managed scripts, and it preserves the local config.
    $victim = (Get-ExpectedManagedName)[0]
    Set-Content -LiteralPath (Join-Path $installDir $victim) -Value 'stale copy' -Encoding UTF8
    $marker = '{ "baseUrl": "http://127.0.0.1:20128", "authToken": "edited-by-the-user" }'
    Set-Content -LiteralPath $configPath -Value $marker -Encoding UTF8

    & (Join-Path $scriptsDir 'install.ps1') -InstallDir $installDir -SkipPath

    $problems = @(Get-InstallProblem -Dir $installDir)
    if ($problems.Count -gt 0) { throw ("Re-running the installer left: " + ($problems -join '; ')) }
    if ((Get-Content -LiteralPath $configPath -Raw).Trim() -ne $marker) {
        throw 'Re-running the installer overwrote the local config.'
    }

    # The check above only means something while it can still fail. Gut the tree
    # on purpose and require the same function to name the file that went missing.
    $removed = (Get-ExpectedManagedName)[-1]
    Remove-Item -LiteralPath (Join-Path $installDir $removed) -Force
    $detected = @(Get-InstallProblem -Dir $installDir)
    if ($detected.Count -eq 0) { throw 'The readback stayed clean after a managed script was deleted.' }
    if (-not ($detected -join '; ').Contains($removed)) {
        throw "The readback failed without naming the deleted script: $removed"
    }

    Write-Host "install.ps1 round trip: OK ($((Get-ExpectedManagedName).Count) managed scripts, config created, config preserved, deletion detected)"
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
