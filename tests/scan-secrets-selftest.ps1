# The secret scan reports "passed" on every run and always will: none of the
# things it looks for can appear in a repository that has never committed one.
# A pass therefore says nothing about whether the scan can still fail, and a
# pattern that stopped matching would look exactly like today's green.
#
# This runs the real scanner against a scratch directory carrying one planted
# violation per pattern and requires a rejection for each. Same scanner, same
# patterns, pointed at a tree that is deliberately dirty.
#
# Every planted string is assembled from fragments. Spelled out, they would be
# found by the scan of this repository and the scanner would fail on its own
# test file.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$scanner = Join-Path $root 'tests\scan-secrets.ps1'

function Invoke-Scanner {
    param([string]$Root)
    # A finding goes to stderr, and under 'Stop' a native command writing to
    # stderr is a terminating error: the self-test would die on the very
    # rejection it exists to observe. Drop to 'Continue' for the call and read
    # the exit code, which is the scanner's actual verdict.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & powershell -NoProfile -File $scanner -Root $Root 2>&1 | Out-Null
        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

$cases = @(
    @{ Name = 'Likely API key'; File = 'notes.txt'; Body = ('sk-' + 'abcdefghijklmnop1234') }
    @{ Name = 'Private key'; File = 'id_rsa'; Body = ('-----' + 'BEGIN' + ' RSA PRIVATE KEY-----') }
    @{ Name = 'Machine user path'; File = 'setup.md'; Body = ('C:' + '\Users\' + 'alice\projects') }
    @{ Name = 'Email address'; File = 'contact.md'; Body = ('someone' + '@' + 'example.com') }
    @{ Name = 'Committed local config'; File = 'config.local.json'; Body = '{}' }
    @{ Name = 'Private setup identifier'; File = 'account.md'; Body = ('vinh' + 'nt36') }
)

$temp = Join-Path ([IO.Path]::GetTempPath()) ("claude-router-scanselftest-" + [guid]::NewGuid())

try {
    foreach ($case in $cases) {
        $dir = Join-Path $temp ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dir $case.File) -Value $case.Body -Encoding UTF8

        # A child process, not a dot-source: the scanner sets its own error
        # preference and calls Write-Error, so running it in this session would
        # abort the self-test instead of letting it read the exit code.
        if ((Invoke-Scanner -Root $dir) -eq 0) {
            Write-Error ("The scanner accepted a tree carrying '" + $case.Name + "'. That pattern can no longer go red.")
            exit 1
        }
        Write-Host ("Rejected as expected: " + $case.Name)
    }

    # And the other direction, or a scanner that failed on everything would pass
    # every case above while refusing the real repository too.
    $clean = Join-Path $temp 'clean'
    New-Item -ItemType Directory -Path $clean -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $clean 'README.md') -Value 'Nothing to find here.' -Encoding UTF8
    if ((Invoke-Scanner -Root $clean) -ne 0) {
        Write-Error 'The scanner rejected a clean tree. It is failing for a reason other than a finding.'
        exit 1
    }
    Write-Host 'Accepted as expected: a tree with nothing to find'

    Write-Host ("Secret scan self-test passed: " + $cases.Count + " patterns still fire, and a clean tree still passes.") -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
