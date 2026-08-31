$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$temp = Join-Path ([IO.Path]::GetTempPath()) ("claude-router-tests-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null

try {
    $config = Join-Path $temp 'config.local.json'
    @{
        baseUrl = 'http://127.0.0.1:20128'
        authToken = 'test-token-not-a-secret'
        mainModel = 'test/main-model'
        smallFastModel = 'test/small-model'
    } | ConvertTo-Json | Set-Content -LiteralPath $config -Encoding UTF8

    $settings = Join-Path $temp 'settings.json'
    @{
        'editor.fontSize' = 14
        'claudeCode.environmentVariables' = @(
            @{ name = 'KEEP_ME'; value = 'unchanged' },
            @{ name = 'ANTHROPIC_BASE_URL'; value = 'http://old.example' }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $settings -Encoding UTF8

    & (Join-Path $root 'scripts\claude-9router.ps1') -ConfigPath $config -DryRun
    if ($LASTEXITCODE -ne 0) { throw 'Launcher dry run failed.' }

    & (Join-Path $root 'scripts\vscode-switch.ps1') on -ConfigPath $config -SettingsPath $settings
    if ($LASTEXITCODE -ne 0) { throw 'VSCode switch on failed.' }
    $on = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
    if ($on.'editor.fontSize' -ne 14) { throw 'Unrelated VSCode setting changed.' }
    $keep = @($on.'claudeCode.environmentVariables' | Where-Object { $_.name -eq 'KEEP_ME' })
    if ($keep.Count -ne 1 -or $keep[0].value -ne 'unchanged') { throw 'Unrelated environment entry changed.' }
    $base = @($on.'claudeCode.environmentVariables' | Where-Object { $_.name -eq 'ANTHROPIC_BASE_URL' })
    if ($base.Count -ne 1 -or $base[0].value -ne 'http://127.0.0.1:20128') { throw 'Managed entry was not replaced.' }
    if (-not (Test-Path -LiteralPath "$settings.bak-claude-router")) { throw 'Backup was not created.' }

    $statusOnOutput = & (Join-Path $root 'scripts\vscode-switch.ps1') status -SettingsPath $settings 6>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'VSCode switch status (on) failed.' }
    if ($statusOnOutput -notmatch 'router enabled') { throw 'Status (on) did not report router enabled.' }
    if ($statusOnOutput -notmatch [regex]::Escape('http://127.0.0.1:20128')) { throw 'Status (on) did not report base URL.' }
    if ($statusOnOutput -match [regex]::Escape('test-token-not-a-secret')) { throw 'Status (on) leaked plaintext authentication token.' }
    if ($statusOnOutput -notmatch 'Authentication token: configured \(hidden\)') { throw 'Status (on) did not report hidden token state.' }

    & (Join-Path $root 'scripts\vscode-switch.ps1') off -SettingsPath $settings
    if ($LASTEXITCODE -ne 0) { throw 'VSCode switch off failed.' }
    $off = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
    $names = @($off.'claudeCode.environmentVariables' | ForEach-Object { $_.name })
    if ($names -contains 'ANTHROPIC_BASE_URL' -or $names -notcontains 'KEEP_ME') { throw 'Switch off removed or retained wrong entries.' }

    $statusOffOutput = & (Join-Path $root 'scripts\vscode-switch.ps1') status -SettingsPath $settings 6>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'VSCode switch status (off) failed.' }
    if ($statusOffOutput -notmatch 'direct Anthropic/default environment') { throw 'Status (off) did not report default/direct environment.' }
    if ($statusOffOutput -match [regex]::Escape('http://127.0.0.1:20128')) { throw 'Status (off) still referenced router base URL.' }

    . (Join-Path $root 'scripts\Common.ps1')
    $customConfig = Join-Path $temp 'custom.router.config.json'
    @{
        baseUrl = 'http://127.0.0.1:20129'
        authToken = 'test-token-custom'
        mainModel = 'test/custom-main'
        smallFastModel = 'test/custom-small'
    } | ConvertTo-Json | Set-Content -LiteralPath $customConfig -Encoding UTF8

    $savedRouterConfigEnv = $env:CLAUDE_ROUTER_CONFIG
    try {
        $env:CLAUDE_ROUTER_CONFIG = $customConfig
        $loaded = Get-RouterConfig
        if ($loaded.BaseUrl -ne 'http://127.0.0.1:20129') { throw 'Custom CLAUDE_ROUTER_CONFIG BaseUrl mismatch.' }
        if ($loaded.AuthToken -ne 'test-token-custom') { throw 'Custom CLAUDE_ROUTER_CONFIG AuthToken mismatch.' }
        if ($loaded.MainModel -ne 'test/custom-main') { throw 'Custom CLAUDE_ROUTER_CONFIG MainModel mismatch.' }
        if ($loaded.SmallFastModel -ne 'test/custom-small') { throw 'Custom CLAUDE_ROUTER_CONFIG SmallFastModel mismatch.' }

        $env:CLAUDE_ROUTER_CONFIG = Join-Path $temp 'non-existent-config.json'
        $errorMessage = $null
        try {
            Get-RouterConfig | Out-Null
        } catch {
            $errorMessage = $_.Exception.Message
        }
        if (-not $errorMessage) { throw 'Non-existent CLAUDE_ROUTER_CONFIG did not throw.' }
        if ($errorMessage -notmatch 'Router config not found') {
            throw "Unexpected error message for missing config: $errorMessage"
        }

        # Valid JSON that is not an object. Before this refusal existed the
        # array fell through to the required-key loop and was reported as a
        # missing baseUrl. tests/config-refusal-parity.sh keeps the wording the
        # same as common.sh; these two assert the PowerShell side reaches it.
        $arrayConfig = Join-Path $temp 'array.config.json'
        '[1, 2]' | Set-Content -LiteralPath $arrayConfig -Encoding UTF8
        $env:CLAUDE_ROUTER_CONFIG = $arrayConfig
        $arrayError = $null
        try { Get-RouterConfig | Out-Null } catch { $arrayError = $_.Exception.Message }
        if (-not $arrayError) { throw 'A JSON array was accepted as a config.' }
        if ($arrayError -notmatch 'expected an object') {
            throw "Unexpected error message for a JSON array: $arrayError"
        }

        # A line break cannot survive the trip through an environment variable,
        # so the reader refuses it rather than truncating the value.
        $multilineConfig = Join-Path $temp 'multiline.config.json'
        @{
            baseUrl = 'http://127.0.0.1:20128'
            authToken = "line-one`nline-two"
            mainModel = 'test/model'
        } | ConvertTo-Json | Set-Content -LiteralPath $multilineConfig -Encoding UTF8
        $env:CLAUDE_ROUTER_CONFIG = $multilineConfig
        $multilineError = $null
        try { Get-RouterConfig | Out-Null } catch { $multilineError = $_.Exception.Message }
        if (-not $multilineError) { throw 'A value carrying a line break was accepted.' }
        if ($multilineError -notmatch 'single-line') {
            throw "Unexpected error message for a multi-line value: $multilineError"
        }
    } finally {
        $env:CLAUDE_ROUTER_CONFIG = $savedRouterConfigEnv
    }

    Write-Host 'All tests passed.' -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
