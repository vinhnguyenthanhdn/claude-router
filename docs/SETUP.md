# Complete 9Router and Claude Code setup

This guide covers the complete path: install 9Router, add one or more providers, create a local API key, identify model IDs, install this toolkit, and switch Claude Code between direct and routed modes.

## 1. Install and start 9Router

1. Open the official 9Router repository or release page: <https://github.com/decolua/9router>.
2. Follow the installation instructions for the release you choose. Do not download builds from unofficial mirrors.
3. Start 9Router and open its dashboard. The default local dashboard used by this toolkit is:

   ```text
   http://localhost:20128
   ```

4. Verify the app responds:

   ```powershell
   Invoke-WebRequest http://127.0.0.1:20128 -UseBasicParsing
   ```

A redirect response is normal. If your installation uses another port or a remote/tunneled URL, use that origin in `baseUrl`.

## 2. Configure a provider

Open **Providers** in the 9Router dashboard. Provider setup differs by integration:

- **OAuth provider:** select the provider, choose **Add**, complete its login/authorization flow, and confirm the connection is active.
- **API-key provider:** select the provider, enter the provider API key and required endpoint/account fields, save, then test it.
- **Custom endpoint:** choose **Add Anthropic Compatible** or **Add OpenAI Compatible**, enter the upstream base URL, key, and model information, then test it.

The toolkit is provider-independent. Any model can be selected if 9Router exposes it correctly through its Anthropic-compatible API used by Claude Code.

### Provider catalog snapshot

9Router v0.5.50 shows:

- OAuth integrations including Claude Code, Antigravity, OpenAI Codex, Qoder, GitHub Copilot, Cursor, Kilo Code, Cline, CodeBuddy, Kimi, and Grok/xAI tools.
- Free/cloud integrations including OpenCode Free, Gemini CLI, Kiro AI, OpenRouter, NVIDIA NIM, Ollama Cloud, Vertex AI, Gemini, Cloudflare, Poolside, BytePlus ModelArk, and others.
- API-key integrations including Anthropic, Azure OpenAI, DeepSeek, Groq, Cerebras, Cohere, Fireworks AI, Alibaba, Baidu Qianfan, GLM, Minimax, and many others.
- Custom Anthropic-compatible and OpenAI-compatible endpoints.

The dashboard is authoritative for your installed version. Provider availability and features can change.

### Validate the provider

1. Ensure the connection status is active/connected.
2. Use **Test Connection** or the model's **Test** action.
3. If multiple credentials are configured, choose the desired balancing policy (for example, round robin) and test each connection.
4. Copy the exact model ID displayed in **Available Models**. Do not infer model IDs from marketing names.

Compatibility is model-specific. Confirm streaming and tool use when you plan to use the Claude Code agent loop.

## 3. Create a 9Router API key

1. Open **Endpoint & Key**.
2. Enable **Require API key** for local protection.
3. Choose **Create Key**, or use an existing dedicated key.
4. Copy the key once and store it in a password manager or the local config created below.
5. Do not paste the key into README files, shell history, screenshots, issue reports, or Git commits.

The router origin is normally `http://127.0.0.1:20128`. The Claude Code client sends messages to the Anthropic-compatible path below it; therefore `baseUrl` should normally omit `/v1/messages`.

## 4. Install the switcher

From the cloned repository:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

The installer:

- copies the runtime scripts to `~/.claude/9router`;
- creates `~/.claude/9router/config.local.json` if absent;
- preserves an existing local config;
- adds the installation directory to user PATH once.

Edit the generated local config:

```powershell
notepad "$env:USERPROFILE\.claude\9router\config.local.json"
```

Example:

```json
{
  "baseUrl": "http://127.0.0.1:20128",
  "authToken": "your-9router-api-key",
  "mainModel": "provider/model-id",
  "smallFastModel": "provider/smaller-model-id"
}
```

`smallFastModel` is optional. It can use the same model as `mainModel` if the provider does not offer a suitable smaller model.

Open a new terminal so the updated user PATH is loaded.

## 5. Use the terminal launcher

```powershell
claude               # Direct/default connection
claude-9router       # Routed connection
```

The launcher sets these variables only in its child process:

- `ANTHROPIC_BASE_URL`
- `ANTHROPIC_AUTH_TOKEN`
- `ANTHROPIC_MODEL`
- `ANTHROPIC_SMALL_FAST_MODEL` when configured
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`

It removes a conflicting process-level `ANTHROPIC_API_KEY` before launching. It does not modify `~/.claude/settings.json`.

Verify with:

```powershell
claude-9router -p "Reply with exactly: ROUTER_OK"
```

Then open 9Router **Console Log** and confirm the request was routed to the selected provider/model.

### On macOS and Linux

Step 4 does not apply — there is no installer for these platforms — so the launcher runs out of the clone and the config lives next to it:

```sh
cp config.example.json config.local.json   # then fill in baseUrl, authToken, mainModel
./scripts/claude-9router --dry-run
./scripts/claude-9router -p "Reply with exactly: ROUTER_OK"
```

The variables, the removal of a conflicting `ANTHROPIC_API_KEY`, and the promise not to touch `~/.claude/settings.json` are identical. Three practical differences:

- Options are `--dry-run` and `--config <path>`, not `-DryRun` and `-ConfigPath`. `--` ends the launcher's options.
- The config is looked up in the same order, but the last two candidates resolve to `scripts/config.local.json` and `config.local.json` in the clone rather than under `%USERPROFILE%\.claude\9router`. `CLAUDE_ROUTER_CONFIG` works the same way and is the cleanest way to keep the config outside the clone.
- Because you run the clone directly, `git pull` **is** the upgrade — the gap section 8 describes does not exist here. The other half of it still does: `config.local.json` is copied once, so a key added to the example later is absent from yours.

Section 6 is Windows-only: the VSCode panel switch is not ported ([#10](https://github.com/vinhnguyenthanhdn/claude-router/issues/10)).

## 6. Use the native VSCode extension

Enable:

```powershell
& "$env:USERPROFILE\.claude\9router\vscode-switch.ps1" on
```

Check status:

```powershell
& "$env:USERPROFILE\.claude\9router\vscode-switch.ps1" status
```

Return to the default/direct environment:

```powershell
& "$env:USERPROFILE\.claude\9router\vscode-switch.ps1" off
```

After `on` or `off`, restart VSCode or run **Developer: Reload Window**. The extension reads its environment when its Claude process starts.

The switcher updates only toolkit-managed entries under `claudeCode.environmentVariables`; unrelated VSCode settings and unrelated environment entries are preserved. Before each mutation it writes:

```text
%APPDATA%\Code\User\settings.json.bak-claude-router
```

The extension setting has machine scope, so it affects all workspaces in that VSCode installation.

## 7. Switch providers or models

Edit `config.local.json` and change `mainModel` or `smallFastModel` to any exact ID shown by 9Router. No script changes are required.

- Terminal: the next `claude-9router` process loads the updated config.
- VSCode: run `vscode-switch.ps1 on` again, then reload the window.

You can also point to another configuration file:

```powershell
$env:CLAUDE_ROUTER_CONFIG = 'D:\secure\work-router.json'
claude-9router
```

This supports separate work/personal routers without committing either key.

## 8. Upgrade

`install.ps1` copies the scripts into `%USERPROFILE%\.claude\9router` and you run them from there, so pulling a new revision of this repository changes nothing until you install again:

```powershell
git pull
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

Re-running it is the upgrade, and it is safe to repeat. It overwrites `Common.ps1`, `claude-9router.ps1`, `claude-9router.cmd`, `vscode-switch.ps1` and `uninstall.ps1` with the versions you just pulled, leaves `config.local.json` exactly as it is (it prints `Preserved existing …`), and adds the install directory to your user `PATH` only if it is not already there.

What it does **not** do is merge new keys into your `config.local.json`. That file is copied from `config.example.json` once, on first install, and never touched again — so if a later version adds a setting, yours will not have it. A missing *required* value (`baseUrl`, `authToken`, `mainModel`) fails loudly on the next launch with `Missing required config value: <name>`; an optional one falls back silently. After an upgrade that mentions a new setting, compare the two files:

```powershell
Compare-Object (Get-Content .\config.example.json) `
               (Get-Content "$env:USERPROFILE\.claude\9router\config.local.json")
```

VSCode is separate. `vscode-switch.ps1` writes `claudeCode.environmentVariables` into your user `settings.json`, and that entry is not rewritten by an install — re-run the switcher (section 6) if an upgrade changes what belongs there.

## 9. Recovery and uninstall

If VSCode settings must be restored manually:

```powershell
Copy-Item "$env:APPDATA\Code\User\settings.json.bak-claude-router" `
          "$env:APPDATA\Code\User\settings.json" -Force
```

Uninstall:

```powershell
& "$env:USERPROFILE\.claude\9router\uninstall.ps1"
```

Keep the local key/config during uninstall:

```powershell
& "$env:USERPROFILE\.claude\9router\uninstall.ps1" -KeepConfig
```

## 10. Troubleshooting

### `claude-9router` is not recognized

Open a new terminal after installation, or run the full path:

```powershell
& "$env:USERPROFILE\.claude\9router\claude-9router.ps1"
```

### Connection refused

Start 9Router, verify its port, and verify `baseUrl`. Direct `claude` remains unaffected.

### Model not found / no active credentials

Confirm the provider connection is active and copy the exact model ID from 9Router. A provider name alone is not necessarily a valid model ID.

### VSCode still uses the previous mode

Reload the VSCode window after switching. Existing Claude sessions may continue with their already-started process; start a new conversation if needed and verify the router console log.

### Provider returns weak or malformed tool behavior

Test another model/provider. Translation between Anthropic messages and another provider's protocol is performed by 9Router, and not every model supports every Claude Code feature equally.

## 11. Security and terms

Conversation context, code, tool definitions, and tool results may be sent to the provider selected in 9Router. Route only data that the provider is authorized to receive.

Subscription and OAuth sessions may not be licensed for proxy/router use. Follow provider terms and organizational policies. Account restrictions or bans are possible. This toolkit does not bypass provider access controls and does not grant authorization to use an account or endpoint.
