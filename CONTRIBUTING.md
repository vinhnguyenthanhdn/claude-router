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

The POSIX side — the config layer, the terminal launcher and the VSCode switch — has its own suite, which needs only a shell and Node:

```sh
sh tests/run-tests.sh
```

`scripts/common.sh` is the counterpart of `scripts/Common.ps1`: it finds `config.local.json` in the same precedence order, applies the same validation, and fails with the same wording. Node parses the JSON because Claude Code already requires Node, so it is not a new dependency; `jq` and `python3` would be. `scripts/claude-9router` and `scripts/vscode-switch` are built on it: both source `common.sh` and spend none of their own code on reading or validating a config. Linux packaging (#6) should do the same rather than re-reading the config itself, so the two platforms cannot drift into disagreeing about what a valid config is.

Both suites assert **what the user would observe**, not the text of the script. The launcher's cases read the environment the child process receives, using a stub `claude` on `PATH` that reports each managed variable as its value or `<unset>`; a blank `ANTHROPIC_SMALL_FAST_MODEL` still reads as configured to the CLI, so "removed" and "set to empty" are different outcomes and only one of them is correct. The VSCode switch's cases read the settings file back after the run, because the promise being tested is about a file the user also edits by hand: what survived, what was replaced, and what was never written.

Shell scripts are parsed in CI by extension or shebang rather than from a list of filenames, so a new script is covered the moment it is committed. If you add one that is neither `*.sh` nor `#!/bin/sh`, widen the discovery in [`.github/workflows/test.yml`](.github/workflows/test.yml) instead of appending a name — a forgotten name leaves the step green while the script is never parsed at all.

The same rule decides which files must be committed executable: every tracked file whose first line is a shebang is asserted at git mode `100755`, and the scan fails if it matches nothing. `scripts/common.sh` is sourced rather than run and carries no shebang, so it is correctly left out. You do not have to remember `chmod +x` — but if your clone has `core.fileMode=false`, git ignores the local mode and the file lands at `100644`; fix it with `git update-index --chmod=+x <path>`.

PowerShell files must be **pure ASCII**. Windows PowerShell 5.1 reads a file with no BOM as ANSI, so a UTF-8 em dash decodes through cp1252 into a smart double quote, PowerShell accepts it as a real quote, and the string ends mid-sentence — the parse step then reports `Unexpected token '<some word>'` several words away from the cause and points at no line. `tests/ascii-ps1.sh` refuses any byte outside printable ASCII and tab in a tracked `.ps1`, and proves on every run that it still can: it scans scratch trees carrying an em dash and a non-breaking space and requires a rejection for each, plus a clean tree that must still pass. Write `-` and `"` rather than pasting typographic characters.

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

## Ways to contribute that aren't code

The scripts here drive a Claude Code installation on someone else's machine, and no test suite can see that machine. Reports from one are contributions:

- **Say what happened on your platform and version.** Which VSCode build, which `anthropic.claude-code` version, and what the panel actually did after the switch. The macOS and Linux issues are open because nobody has posted that yet, not because the code is hard.
- **Add or correct a row in [docs/PROVIDERS.md](docs/PROVIDERS.md).** A tested `No` is as useful as a tested `Yes`; both replace a guess.
- **Reproduce an open issue, or report that you could not.** State the version you tried — "not reproducible on <version>" narrows an issue that has been sitting still.
- **Review an open pull request.** The suite runs on `windows-latest` for every pull request, including from forks, so anything CI cannot reach — the real Claude Code install, the real VSCode panel — is carried by whoever reviews.

Credit follows the contribution, not the file: release notes and the compatibility tables name the person who tested or reported, the same as the person who patched.

## Documentation style

- Use concise, objective English.
- Write reusable instructions rather than machine-specific history.
- Use placeholders for keys, usernames, endpoints, and account IDs.
- Link to official upstream documentation where possible.

## Recognition

Contributors are credited through Git history, pull requests, compatibility tables, and release notes. Consistent contributors may be invited to help triage or maintain areas they know well.
