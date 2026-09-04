Set-StrictMode -Version 2.0

$script:ManagedEnvironmentNames = @(
    'ANTHROPIC_BASE_URL',
    'ANTHROPIC_AUTH_TOKEN',
    'ANTHROPIC_API_KEY',
    'ANTHROPIC_MODEL',
    'ANTHROPIC_SMALL_FAST_MODEL',
    'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'
)

# Where a failure goes, and the two destinations are not interchangeable:
# anything the router, a provider or a model rejected happens inside 9Router and
# belongs upstream, while anything this toolkit did before handing over belongs
# here. A user who cannot tell the two apart reports neither.
#
# Written to the error stream directly rather than through Write-Error: these are
# the words the user has to read and copy, and Write-Error wraps them in a record
# whose formatting depends on the host. tests/report-destination-parity.sh holds
# them to the wording common.sh prints.
$script:RouterIssuesUrl = 'https://github.com/vinhnguyenthanhdn/claude-router/issues/new/choose'
$script:RouterUpstreamUrl = 'https://github.com/decolua/9router/issues'

function Write-RouterUnexpected {
    param([string]$Detail)
    [Console]::Error.WriteLine("claude-router stopped with an error it has no message for: $Detail")
    [Console]::Error.WriteLine("Report it here, with this output and the command you ran: $script:RouterIssuesUrl")
    [Console]::Error.WriteLine("If the router or a provider rejected the request, that belongs upstream: $script:RouterUpstreamUrl")
}

# Claude Code itself is the one dependency the launcher cannot work around, and
# invoking a missing command prints a CommandNotFoundException that names neither
# this toolkit nor what to install.
function Assert-ClaudeOnPath {
    if (Get-Command claude -ErrorAction SilentlyContinue) { return }
    [Console]::Error.WriteLine('Claude Code was not found on PATH. Install it first, then run this launcher again; docs/SETUP.md has the steps.')
    exit 127
}

function Resolve-RouterConfigPath {
    param([string]$ConfigPath)

    $candidates = @()
    if ($ConfigPath) { $candidates += $ConfigPath }
    if ($env:CLAUDE_ROUTER_CONFIG) { $candidates += $env:CLAUDE_ROUTER_CONFIG }
    $candidates += (Join-Path $PSScriptRoot 'config.local.json')
    $candidates += (Join-Path (Split-Path $PSScriptRoot -Parent) 'config.local.json')

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Router config not found. Copy config.example.json to config.local.json and add your 9Router API key."
}

function Get-RouterConfig {
    param([string]$ConfigPath)

    $resolved = Resolve-RouterConfigPath $ConfigPath
    try {
        $config = Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json
    } catch {
        throw "Invalid JSON in router config '$resolved': $($_.Exception.Message)"
    }

    # Valid JSON that is not an object. Without this the array [1,2] falls
    # through to the loop below and is reported as a missing baseUrl, which
    # sends the reader looking for a key in a file that has no keys at all.
    # tests/config-refusal-parity.sh keeps the wording identical to common.sh.
    if ($null -eq $config -or $config.GetType().Name -ne 'PSCustomObject') {
        throw "Invalid JSON in router config '$resolved': expected an object."
    }

    foreach ($name in @('baseUrl', 'authToken', 'mainModel')) {
        $property = $config.PSObject.Properties[$name]
        if ($null -eq $property) {
            throw "Missing required property '$name' in router config '$resolved'."
        }
        if ([string]::IsNullOrWhiteSpace([string]$property.Value)) {
            throw "Required property '$name' in router config '$resolved' cannot be empty."
        }
    }

    $uri = $null
    if (-not [Uri]::TryCreate([string]$config.baseUrl, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('http', 'https')) {
        throw "baseUrl must be an absolute HTTP or HTTPS URL in router config '$resolved'."
    }
    if ([string]$config.authToken -match 'replace-with|your-api-key|^<.+>$') {
        throw "Replace the placeholder authToken in router config '$resolved'."
    }
    if ([string]$config.mainModel -match 'provider/model-id|^<.+>$') {
        throw "Replace the placeholder mainModel in router config '$resolved'."
    }

    $result = [pscustomobject]@{
        Path = $resolved
        BaseUrl = ([string]$config.baseUrl).TrimEnd('/')
        AuthToken = [string]$config.authToken
        MainModel = [string]$config.mainModel
        SmallFastModel = if ($config.PSObject.Properties['smallFastModel']) { [string]$config.smallFastModel } else { '' }
    }

    # Every one of these leaves here as an environment variable, and a line
    # break cannot survive that intact. Refusing beats truncating a config
    # silently and routing to half a model id. Mirrors the same check in
    # common.sh, on the same four values, after the same trimming.
    foreach ($value in @($result.BaseUrl, $result.AuthToken, $result.MainModel, $result.SmallFastModel)) {
        if ($value -match "`n") {
            throw "Config values must be single-line: an environment variable cannot carry a line break."
        }
    }

    $result
}

function Get-RouterEnvironmentEntries {
    param($Config)

    $entries = @(
        [pscustomobject]@{ name = 'ANTHROPIC_BASE_URL'; value = $Config.BaseUrl },
        [pscustomobject]@{ name = 'ANTHROPIC_AUTH_TOKEN'; value = $Config.AuthToken },
        [pscustomobject]@{ name = 'ANTHROPIC_MODEL'; value = $Config.MainModel },
        [pscustomobject]@{ name = 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'; value = '1' }
    )
    if (-not [string]::IsNullOrWhiteSpace($Config.SmallFastModel)) {
        $entries += [pscustomobject]@{ name = 'ANTHROPIC_SMALL_FAST_MODEL'; value = $Config.SmallFastModel }
    }
    return $entries
}

function Test-IsManagedEnvironmentName {
    param([string]$Name)
    return $script:ManagedEnvironmentNames -contains $Name
}

function Write-JsonFile {
    param($Value, [string]$Path)
    $json = $Value | ConvertTo-Json -Depth 30
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}

function Resolve-VSCodeSettingsPath {
    param(
        [string]$SettingsPath,
        [switch]$Insiders
    )

    if ($SettingsPath) {
        return $SettingsPath
    }

    # No fallback to the other edition: with both editors installed, silently
    # picking Insiders would stop routing the editor the user actually runs.
    # The not-found error downstream prints the resolved path, which already
    # says which edition was looked for and where.
    $appData = if ($env:APPDATA) { $env:APPDATA } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) 'AppData\Roaming' }
    $folder = if ($Insiders) { 'Code - Insiders' } else { 'Code' }
    return Join-Path $appData (Join-Path $folder 'User\settings.json')
}

