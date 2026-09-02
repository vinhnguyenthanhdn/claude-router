param(
    [Parameter(Position = 0)]
    [ValidateSet('on', 'off', 'status')]
    [string]$Mode = 'status',
    [string]$ConfigPath,
    [string]$SettingsPath,
    [switch]$Insiders
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$SettingsPath = Resolve-VSCodeSettingsPath $SettingsPath -Insiders:$Insiders
$settingsKey = 'claudeCode.environmentVariables'

if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
    Write-Error "VSCode settings.json not found: $SettingsPath"
    exit 1
}

try {
    $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
} catch {
    Write-Error "Invalid JSON in VSCode settings '$SettingsPath': $($_.Exception.Message)"
    exit 1
}

$property = $settings.PSObject.Properties[$settingsKey]
$currentEntries = @()
if ($null -ne $property -and $null -ne $property.Value) {
    $currentEntries = @($property.Value)
}
$managedEntries = @($currentEntries | Where-Object { Test-IsManagedEnvironmentName ([string]$_.name) })

if ($Mode -eq 'status') {
    $base = @($managedEntries | Where-Object { $_.name -eq 'ANTHROPIC_BASE_URL' })
    if ($base.Count -gt 0) {
        $model = @($managedEntries | Where-Object { $_.name -eq 'ANTHROPIC_MODEL' } | Select-Object -First 1)
        Write-Host 'VSCode Claude Code -> router enabled' -ForegroundColor Yellow
        Write-Host "  Base URL: $($base[0].value)"
        if ($model.Count -gt 0) { Write-Host "  Model: $($model[0].value)" }
        Write-Host '  Authentication token: configured (hidden)'
    } else {
        Write-Host 'VSCode Claude Code -> direct Anthropic/default environment' -ForegroundColor Green
    }
    exit 0
}

$backupPath = "$SettingsPath.bak-claude-router"
Copy-Item -LiteralPath $SettingsPath -Destination $backupPath -Force

$preservedEntries = @($currentEntries | Where-Object { -not (Test-IsManagedEnvironmentName ([string]$_.name)) })
if ($Mode -eq 'on') {
    try {
        $config = Get-RouterConfig $ConfigPath
    } catch {
        Write-Error $_.Exception.Message
        exit 1
    }
    $newEntries = @($preservedEntries) + @(Get-RouterEnvironmentEntries $config)
} else {
    $newEntries = @($preservedEntries)
}

if ($settings.PSObject.Properties[$settingsKey]) {
    $settings.PSObject.Properties.Remove($settingsKey)
}
if ($newEntries.Count -gt 0) {
    $settings | Add-Member -NotePropertyName $settingsKey -NotePropertyValue $newEntries
}

try {
    Write-JsonFile $settings $SettingsPath
} catch {
    Copy-Item -LiteralPath $backupPath -Destination $SettingsPath -Force
    Write-Error "Could not update VSCode settings; restored backup. $($_.Exception.Message)"
    exit 1
}

if ($Mode -eq 'on') {
    Write-Host 'ON  - VSCode Claude Code now routes through the configured endpoint.' -ForegroundColor Yellow
    Write-Host "      Model: $($config.MainModel)"
} else {
    Write-Host 'OFF - VSCode Claude Code returned to its default/direct environment.' -ForegroundColor Green
}
Write-Host "      Backup: $backupPath" -ForegroundColor DarkGray
Write-Host '      Restart VSCode or run Developer: Reload Window.' -ForegroundColor Cyan
