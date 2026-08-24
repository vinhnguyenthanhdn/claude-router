param([string]$Root = (Split-Path $PSScriptRoot -Parent))

$ErrorActionPreference = 'Stop'
$excludedDirectories = @('.git', '.tests-temp', 'TestResults')
$binaryExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.ico', '.zip', '.exe', '.dll')
$findings = New-Object System.Collections.Generic.List[string]

# Contact addresses that are intentionally published in the community health files.
$allowedContactEmails = @(
    ('vinh.nguyenthanhdn' + '@' + 'gmail.com'),
    ('noreply' + '@' + 'anthropic.com')
)

$patterns = @(
    @{ Name = 'Likely API key'; Regex = '(?i)\bsk-[a-z0-9_-]{99,}\b' },
    @{ Name = 'Private key'; Regex = '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' },
    @{ Name = 'Machine user path'; Regex = '(?i)\bC:\\Users\\(?!USERNAME\b|<)[^\\\s"'']+' },
    @{ Name = 'Email address'; Regex = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b' },
    @{ Name = 'Committed local config'; Regex = '^$a' }
)

$files = Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object {
    $relative = $_.FullName.Substring($Root.Length).TrimStart('\')
    $segments = $relative -split '[\\/]'
    -not ($segments | Where-Object { $excludedDirectories -contains $_ }) -and
    $binaryExtensions -notcontains $_.Extension.ToLowerInvariant()
}

foreach ($file in $files) {
    $relative = $file.FullName.Substring($Root.Length).TrimStart('\')
    if ($file.Name -eq 'config.local.json') {
        $findings.Add("Committed local config: $relative")
        continue
    }
    $content = [IO.File]::ReadAllText($file.FullName)
    foreach ($allowed in $allowedContactEmails) {
        $content = $content -replace [regex]::Escape($allowed), 'allowed-contact'
    }
    foreach ($pattern in $patterns | Where-Object { $_.Name -ne 'Committed local config' }) {
        if ([regex]::IsMatch($content, $pattern.Regex)) {
            $findings.Add("$($pattern.Name): $relative")
        }
    }
}

# Build private-setup identifiers from fragments so this scanner does not match itself.
$privateSetupIdentifiers = @(
    ('private' + 'relay.appleid.com'),
    ('vinh' + 'nt36')
)
foreach ($needle in $privateSetupIdentifiers) {
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($Root.Length).TrimStart('\')
        if ([IO.File]::ReadAllText($file.FullName).IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $findings.Add("Private setup identifier: $relative")
        }
    }
}

if ($findings.Count -gt 0) {
    $findings | Sort-Object -Unique | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'Repository secret and identity scan passed.' -ForegroundColor Green
