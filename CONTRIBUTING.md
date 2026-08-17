# Contributing

Thank you for helping improve Claude Router Switcher. Contributions may include code, tests, documentation, provider compatibility reports, and reproducible bug reports.

## Before opening an issue

- Search existing issues and discussions.
- Confirm whether the problem belongs to this toolkit, 9Router, Claude Code, or the upstream model provider.
- Remove API keys, OAuth data, email addresses, account IDs, usernames, private source code, and internal URLs from logs and screenshots.
- Use the appropriate issue form. Provider results belong in the provider compatibility form.

Security vulnerabilities and leaked credentials must not be reported in a public issue. Follow [SECURITY.md](SECURITY.md).

## Development setup

To run the suite on your own machine you need:

- Windows 10/11 and Windows PowerShell 5.1 or later, for the PowerShell suite
- A POSIX shell and Node 18+, for the shell suite — no Windows needed
- Git

Clone your fork, then run the isolated test suite:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
```

The tests use temporary directories and must never mutate real Claude Code or VSCode settings.

The POSIX side of the config layer has its own suite, which needs only a shell and Node:

```sh
sh tests/run-tests.sh
```

`scripts/common.sh` is the counterpart of `scripts/Common.ps1`: it finds `config.local.json` in the same precedence order, applies the same validation, and fails with the same wording. Node parses the JSON because Claude Code already requires Node, so it is not a new dependency; `jq` and `python3` would be. A shell launcher (#9), the macOS VSCode switch (#10) and the Linux entries (#6) build on this rather than re-reading the config themselves, so the two platforms cannot drift into disagreeing about what a valid config is.

### Contributing without a Windows machine

You do not need Windows to send a pull request here. Every pull request, including one from a fork, runs [`.github/workflows/test.yml`](.github/workflows/test.yml) on `windows-latest`: JSON validation, a PowerShell parse of every `.ps1`, the secret scan, and the full `tests/run-tests.ps1` suite. That is the same suite you would run locally, on a real Windows PowerShell host.

So the loop for a macOS or Linux contributor is: push the branch, open the pull request, and read the run under the Checks tab — `Test / windows-powershell` — where a failure names the failing assertion and the line. A first pull request waits for a maintainer to approve the workflow run before it starts; that is GitHub's rule for first-time contributors, not a problem with your branch.

What this does not cover, and what a reviewer will exercise on Windows for you: anything that has to touch a real Claude Code or VSCode install — the settings writes, the backup and restore path, and the behaviour of the VSCode panel itself. Say in the pull request that you could not run it on Windows, and the review will cover that part rather than assume it.

## Design rules

- Keep the toolkit provider-independent. Provider and model IDs belong in `config.local.json`, not in runtime scripts.
- Support Windows PowerShell 5.1 unless a change explicitly raises the documented minimum version.
- Preserve unrelated properties in VSCode `settings.json`.
- Preserve unrelated entries in `claudeCode.environmentVariables`.
- Back up a settings file before changing it and restore it after a failed write.
- Never print authentication tokens in status output, errors, tests, screenshots, or logs.
- Keep secrets in `config.local.json`; this file must remain ignored by Git.
- Prefer small, focused pull requests with tests.

## Pull request workflow

1. Create a branch from the default branch.
2. Add or update tests for behavioral changes.
3. Run `tests/run-tests.ps1` locally, or let the pull request's `windows-latest` run do it and say in the description that you have no Windows machine.
4. Check that no local config, backup, token, account data, or absolute user path is included.
5. Update README/setup/provider documentation when behavior changes.
6. Open a pull request using the provided template.

A maintainer may ask you to split unrelated changes. A passing CI run is required, but does not replace review.

## Provider compatibility contributions

Provider support is model-specific and version-specific. To add a result to [docs/PROVIDERS.md](docs/PROVIDERS.md):

- test the exact provider and model ID through Claude Code;
- record the 9Router version;
- test basic streaming and, where applicable, tool use, vision, thinking, and prompt caching;
- use `Yes`, `No`, `Partial`, or `Not tested` rather than guessing;
- include only sanitized evidence;
- do not imply that presence in the 9Router dashboard guarantees compatibility.

## Documentation style

- Use concise, objective English.
- Write reusable instructions rather than machine-specific history.
- Use placeholders for keys, usernames, endpoints, and account IDs.
- Link to official upstream documentation where possible.

## Recognition

Contributors are credited through Git history, pull requests, compatibility tables, and release notes. Consistent contributors may be invited to help triage or maintain areas they know well.
