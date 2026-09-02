# Claude Router Switcher — run Claude Code through any 9Router provider, on Windows, macOS and Linux

Use GPT, Gemini, DeepSeek, Grok, Anthropic, local models, or any other model exposed by 9Router inside Claude Code—without permanently changing your Claude configuration.

A small, config-driven toolkit for switching Claude Code between its default Anthropic connection and a local [9Router](https://github.com/decolua/9router)-compatible endpoint.

[![Test](https://github.com/vinhnguyenthanhdn/claude-router/actions/workflows/test.yml/badge.svg)](https://github.com/vinhnguyenthanhdn/claude-router/actions/workflows/test.yml)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-0078D4)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![License](https://img.shields.io/badge/license-MIT-green)

## What it does

| Capability | Windows | macOS and Linux | Effect |
|---|---|---|---|
| Route the Claude Code CLI through 9Router | `claude-9router` | `./scripts/claude-9router` | Only that child process is routed; `claude` in the same window still uses the default Anthropic connection |
| Check which endpoint and model would be used, without starting Claude | `claude-9router -DryRun` | `./scripts/claude-9router --dry-run` | Prints the base URL and model, then exits |
| Route the native Claude Code panel/sidebar in VSCode | `vscode-switch.ps1 on` | `./scripts/vscode-switch on` | Writes `claudeCode.environmentVariables` in user settings (machine scope), keeps unrelated entries, and backs the file up first |
| Show the current VSCode mode | `vscode-switch.ps1 status` | `./scripts/vscode-switch status` | Prints the base URL and model; the token is reported as configured and never printed |
| Return VSCode to the default Anthropic connection | `vscode-switch.ps1 off` | `./scripts/vscode-switch off` | Removes only the variables this toolkit manages |
| Remove the toolkit | `uninstall.ps1` | — | Disables VSCode routing first, then removes the PATH entry, the managed scripts, and the local config unless `-KeepConfig` is supplied |

The installer is the one part that is still Windows-only: on macOS and Linux you run the scripts out of the clone and put them on your own PATH if you want bare commands.

Any provider and model that 9Router exposes through its Anthropic-compatible `/v1/messages` endpoint works; secrets stay in a gitignored local config file.

> Routing the Claude Code client does not guarantee that the underlying model is Claude. The selected 9Router model may be GPT, Gemini, DeepSeek, Grok, a local model, or another provider. The Claude Code UI remains the client shell.

## Demo

<p align="center">
  <img src="docs/claude-code-9router-demo.png" alt="Claude Code running through a 9Router provider" width="424">
</p>

<p align="center"><em>Claude Code keeps its familiar interface while requests are routed to the provider and model selected in 9Router.</em></p>

### OpenCode Free with DeepSeek

<p align="center">
  <img src="docs/deepseek-demo.png" alt="Claude Code using the OpenCode Free DeepSeek model through 9Router" width="850">
</p>

<p align="center"><em>A Claude Code terminal session routed to <code>oc/deepseek-v4-flash-free</code> through the OpenCode Free provider.</em></p>

On macOS and Linux both switches work — the terminal launcher and the VSCode panel — out of the clone; see [macOS and Linux](#macos-and-linux). The installer, and with it the PATH entry and the managed copy under your profile, is Windows-only.

## Prerequisites

- Windows 10/11 and Windows PowerShell 5.1 or later, **or** macOS/Linux with any POSIX shell (the installer is the only Windows-only part)
- Claude Code CLI and/or the Claude Code VSCode extension
- a running 9Router installation
- at least one configured 9Router provider and a 9Router API key

See [Complete setup](docs/SETUP.md) for 9Router installation, provider setup, API key creation, model selection, toolkit configuration, recovery, and troubleshooting.

## Quick start

Installation is a single command after cloning:

```powershell
git clone https://github.com/vinhnguyenthanhdn/claude-router.git
cd claude-router
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

The installer copies the managed scripts to `%USERPROFILE%\.claude\9router`, adds that directory to the user PATH, and creates `config.local.json` from the example. You run the copies, not the repository, so **re-run the installer after every `git pull`** — it overwrites the managed scripts and preserves your local config ([Upgrade](docs/SETUP.md#8-upgrade)). Edit the config before first use:

```powershell
notepad "$env:USERPROFILE\.claude\9router\config.local.json"
```

```json
{
  "baseUrl": "http://127.0.0.1:20128",
  "authToken": "your-9router-api-key",
  "mainModel": "provider/model-id",
  "smallFastModel": "provider/smaller-model-id"
}
```

Open a new terminal after installation.

### Terminal

```powershell
claude                         # Direct/default Anthropic connection
claude-9router                 # Routed through 9Router
claude-9router -p "Hello"      # Normal Claude CLI arguments work
claude-9router --resume
claude-9router -DryRun         # Print the endpoint and model, do not start Claude
```

Only the routed child process receives the proxy variables. Global Claude Code settings remain untouched.

All remaining arguments (such as `--resume`, `doctor`, or `-p "prompt"`) forward directly to `claude`. See [Argument forwarding & shell quoting](docs/SETUP.md#argument-forwarding-and-shell-quoting) for quoting and tab-completion details.

### macOS and Linux

`scripts/claude-9router` and `scripts/vscode-switch` are the POSIX counterparts of the two PowerShell entries: same config file, same lookup order, same validation and the same wording when they refuse one. There is no installer on these platforms, so you run them out of the clone and put them on your own PATH if you want bare commands:

```sh
git clone https://github.com/vinhnguyenthanhdn/claude-router.git
cd claude-router
cp config.example.json config.local.json   # then fill in baseUrl, authToken, mainModel
./scripts/claude-9router --dry-run          # print the endpoint and model, do not start Claude
./scripts/claude-9router                    # routed session
./scripts/claude-9router -p "Hello"         # remaining arguments go to Claude Code untouched
./scripts/vscode-switch status              # is the VSCode panel routed right now?
./scripts/vscode-switch on                  # route the panel, then reload the VSCode window
./scripts/vscode-switch off                 # send the panel back to its default environment
```

Two differences from the Windows entries, both because POSIX shells and PowerShell disagree about flags: options are `--dry-run`, `--config <path>` and `--settings <path>` rather than `-DryRun`, `-ConfigPath` and `-SettingsPath`, and `--` ends the launcher's own options so a Claude argument of the same name reaches Claude.

`vscode-switch` resolves the default settings path per platform: `~/Library/Application Support/Code/User/settings.json` on macOS, `$XDG_CONFIG_HOME/Code/User/settings.json` (defaulting to `~/.config`) on Linux. Pass `--insiders` for VSCode Insiders; without it the switch always targets the stable edition, and it never picks an editor for you. `--settings` overrides all of that.

What is **not** ported: `install.ps1` (so no PATH entry and no managed copy under your profile) and `uninstall.ps1`. Node is required, as it is the JSON parser for the shell path; Claude Code already requires it.

### VSCode extension

The panel needs its own switch because it does not inherit your terminal. Exporting `ANTHROPIC_BASE_URL` in a shell — or letting `claude-9router` export it for a session — only reaches processes that shell starts, and the extension starts its own Claude process from VSCode. So a terminal session can be routed while the panel next to it is still talking to Anthropic directly, with nothing in either place saying so.

What the extension does read is its own setting, `claudeCode.environmentVariables`: an array of `{ name, value }` pairs applied when it launches Claude. That setting is where the switch writes, and it is why the two modes are separate commands rather than one.

```powershell
# Windows
& "$env:USERPROFILE\.claude\9router\vscode-switch.ps1" on            # enable routing for the panel
& "$env:USERPROFILE\.claude\9router\vscode-switch.ps1" status        # current mode (token is never printed)
& "$env:USERPROFILE\.claude\9router\vscode-switch.ps1" off           # back to the default/direct environment

# VSCode Insiders edition
& "$env:USERPROFILE\.claude\9router\vscode-switch.ps1" on -Insiders  # route VSCode Insiders panel
```

Without `-Insiders` the switch always targets the stable edition, even when only Insiders is installed; it never picks an editor for you.

```sh
# macOS and Linux
./scripts/vscode-switch on
./scripts/vscode-switch status
./scripts/vscode-switch off
```

Both sides own exactly the six names the toolkit manages. Every other entry in that array, and every other setting in the file, is written back as it was, and the file is backed up to `settings.json.bak-claude-router` before the first change. A settings file the switch cannot parse is refused before it is copied or written — which also means the presence of that backup always tells you a write was attempted.

Run **Developer: Reload Window** or restart VSCode after `on` or `off`. The setting has machine scope, so it affects every VSCode workspace on that machine.

## Provider support

The toolkit does not hard-code a provider. Set `mainModel` and `smallFastModel` to model IDs shown by your 9Router instance.

9Router v0.5.50 exposes these provider categories and integrations; availability depends on your version, region, account, and credentials:

- **Custom compatible endpoints:** Anthropic-compatible and OpenAI-compatible providers
- **OAuth providers:** Claude Code, Antigravity, OpenAI Codex, Qoder, GitHub Copilot, Cursor IDE, Kilo Code, Cline, ClinePass, CodeBuddy, CodeBuddy CN, Kimi, Grok CLI/Grok Build, and xAI/Grok
- **Free/cloud providers:** OpenCode Free, Gemini CLI, Kiro AI, OpenRouter, NVIDIA NIM, Ollama Cloud, Vertex AI, Gemini, Cloudflare, Poolside, BytePlus ModelArk, Kimchi, API.airforce, Bazaarlink, and Kilo Gateway
- **API-key providers shown in the dashboard:** Alibaba, Alibaba Coding, Alibaba Studio, Anthropic, Azure OpenAI, Baidu Qianfan, Blackbox AI, Cerebras, Chutes AI, Cohere, Command Code, DeepSeek, Featherless, Fireworks AI, GLM, GLM Coding, Groq, Hyperbolic, LLM7, Minimax, and additional providers under the dashboard's expanded list

This is a snapshot of the dashboard, not a compatibility guarantee. Test the exact model in 9Router before using it with Claude Code. Tool use, streaming, vision, prompt caching, and extended thinking can vary by provider.

See the community-maintained [provider compatibility matrix](docs/PROVIDERS.md), or submit a sanitized result through the provider compatibility issue form.

## Configuration

| Property | Required | Description |
|---|---:|---|
| `baseUrl` | Yes | Router origin without `/v1/messages`, normally `http://127.0.0.1:20128` |
| `authToken` | Yes | API key created under 9Router **Endpoint & Key** |
| `mainModel` | Yes | Any model ID exposed by an active provider through 9Router |
| `smallFastModel` | No | Model used by Claude Code for smaller background requests |

Set `CLAUDE_ROUTER_CONFIG` to use a config file outside the install directory.

## What routing costs you, and what else can do it

Pointing Claude Code at a non-Anthropic host is a supported thing to do, and it is not free. Two documented consequences, checked against the Claude Code docs on 2026-08-18:

- **MCP tool search is disabled by default** when `ANTHROPIC_BASE_URL` points at a non-first-party host. Set `ENABLE_TOOL_SEARCH=true` only if your proxy forwards `tool_reference` blocks.
- **Remote Control is disabled** as of Claude Code v2.1.196 when the base URL is not `api.anthropic.com`, the same as on Bedrock, Google Cloud's Agent Platform and Microsoft Foundry.

Both apply however you set the base URL, including with this toolkit. See [Environment variables](https://code.claude.com/docs/en/env-vars).

Three ways to do the switching, and this repo is the narrowest of them:

| | What it is | Reach for it when |
|---|---|---|
| [`ANTHROPIC_BASE_URL`](https://code.claude.com/docs/en/env-vars) by hand, or the `env` block of `settings.json` | No tool at all: two variables, exported in a shell or written into settings | One endpoint, one model, and you rarely change either |
| [`musistudio/claude-code-router`](https://github.com/musistudio/claude-code-router) | A cross-platform Node control plane that routes requests across models and providers, with rules for which request goes where | You want per-request routing, many providers, and support beyond Windows |
| `claude-router` (this repo) | Windows PowerShell scripts around one 9Router endpoint: a launcher that routes a single process, and a VSCode switch that is reversible | You are on Windows, you already run 9Router, and you want the VSCode panel switched without hand-editing settings |

The narrow part is the point: the launcher routes only the process it starts, so `claude` in the same window is untouched; the VSCode switch backs up your settings first and removes only the variables it wrote; and `uninstall.ps1` puts the machine back. What it does not do is choose a model per request — that is what a control plane is for.

## Security and provider terms

- Never commit `config.local.json`; it contains an API key.
- Treat OAuth sessions, subscription credentials, and API keys as secrets.
- Some providers do not license subscription or OAuth sessions for proxy/router use. Accounts may be restricted or banned. Use only accounts and endpoints you are authorized to route, and follow each provider's terms.
- The toolkit sends Claude Code conversation context and tool requests to the selected provider through 9Router. Do not route sensitive data to a provider that is not approved for it.

## Testing

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
```

Tests use temporary files and do not modify the real VSCode or Claude settings.

## Uninstall

```powershell
& "$env:USERPROFILE\.claude\9router\uninstall.ps1"
```

The uninstaller disables VSCode routing first, removes the PATH entry and managed scripts, then removes the local config unless `-KeepConfig` is supplied.

## Related tools

Two separate concerns around the same CLI; either works on its own.

| Tool | What it does |
|---|---|
| `claude-router` (this repo) | Points Claude Code at a 9Router provider instead of Anthropic, per process in the terminal or per machine in VSCode |
| [`claude-jobs`](https://github.com/vinhnguyenthanhdn/claude-jobs) | Runs Claude Code on a schedule, unattended, and reports the outcome (launchd, systemd or cron) |

## Contributing and support

- Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.
- Use the issue forms for bugs, features, and provider compatibility results.
- Read [SUPPORT.md](SUPPORT.md) to choose the correct support channel.
- Report vulnerabilities privately according to [SECURITY.md](SECURITY.md).
- Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).
- User-visible changes are recorded in [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE)
