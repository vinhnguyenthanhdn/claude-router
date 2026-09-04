param(
    [string]$ConfigPath,
    [switch]$DryRun,
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$ClaudeArgs
)

. (Join-Path $PSScriptRoot 'Common.ps1')

# Anything that stops this script without a message of its own gets one, plus
# the two places a report belongs. The catch below still owns the config
# refusals: those are already the whole answer, and inviting a bug report on top
# of one teaches the user to ignore the invitation.
trap {
    Write-RouterUnexpected $_.Exception.Message
    exit 70
}

try {
    $config = Get-RouterConfig $ConfigPath
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

$env:ANTHROPIC_BASE_URL = $config.BaseUrl
$env:ANTHROPIC_AUTH_TOKEN = $config.AuthToken
Remove-Item Env:\ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
$env:ANTHROPIC_MODEL = $config.MainModel
if ([string]::IsNullOrWhiteSpace($config.SmallFastModel)) {
    Remove-Item Env:\ANTHROPIC_SMALL_FAST_MODEL -ErrorAction SilentlyContinue
} else {
    $env:ANTHROPIC_SMALL_FAST_MODEL = $config.SmallFastModel
}
$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'

Write-Host "[9Router] base=$($config.BaseUrl) model=$($config.MainModel)" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host '[9Router] dry run; Claude Code was not started.' -ForegroundColor DarkGray
    exit 0
}

# Asked before the invocation so the refusal comes from the launcher, with a
# name and a next step, instead of from PowerShell after the environment is
# already set.
Assert-ClaudeOnPath

& claude @ClaudeArgs
exit $LASTEXITCODE
