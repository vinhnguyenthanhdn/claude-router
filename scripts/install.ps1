param(
    [string]$InstallDir = (Join-Path $HOME '.claude\9router'),
    [switch]$SkipPath
)

$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'config.example.json'))) {
    Write-Error 'Run install.ps1 from the cloned repository.'
    exit 1
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

# Ask for the property instead of listing names: every Windows entry point in
# scripts/ is managed, and install.ps1 is the one that stays behind. A name list
# here would have to be edited by hand every time a script is added, and nothing
# would report the day it was not.
$managed = @(Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object {
    @('.ps1', '.cmd') -contains $_.Extension.ToLowerInvariant() -and $_.Name -ne 'install.ps1'
})
if ($managed.Count -eq 0) {
    Write-Error 'No managed script was found next to install.ps1.'
    exit 1
}
foreach ($file in $managed) {
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $InstallDir $file.Name) -Force
}

$configPath = Join-Path $InstallDir 'config.local.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    Copy-Item -LiteralPath (Join-Path $repoRoot 'config.example.json') -Destination $configPath
    Write-Host "Created $configPath" -ForegroundColor Yellow
    Write-Host 'Edit it and add your endpoint, API key, and model IDs before use.' -ForegroundColor Yellow
} else {
    Write-Host "Preserved existing $configPath" -ForegroundColor Green
}

if (-not $SkipPath) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($current -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts -notcontains $InstallDir) {
        [Environment]::SetEnvironmentVariable('Path', (($parts + $InstallDir) -join ';'), 'User')
        Write-Host "Added $InstallDir to user PATH." -ForegroundColor Green
    } else {
        Write-Host 'User PATH already contains the install directory.' -ForegroundColor Green
    }
}

Write-Host 'Installation complete. Open a new terminal after editing config.local.json.' -ForegroundColor Cyan
