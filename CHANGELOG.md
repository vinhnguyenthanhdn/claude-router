# Changelog

All notable changes to this project will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project intends to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `scripts/claude-9router`, a terminal launcher for macOS and Linux at parity with `claude-9router.ps1`: same config file and lookup order, same validation, same refusal wording, same per-process variables, and the same removal of a conflicting `ANTHROPIC_API_KEY`. Options are `--dry-run` and `--config <path>` because PowerShell parameter syntax does not carry over, `--` ends them, and remaining arguments and the exit code pass through to Claude Code untouched. The installer, the PATH entry and the VSCode switch are still Windows-only, so the launcher runs out of the clone.
- `scripts/common.sh`, the POSIX counterpart of `Common.ps1`: same config lookup order, same validation, same error wording, with Node parsing the JSON so no new dependency is introduced.
- `tests/run-tests.sh`, a shell suite that runs on macOS and Linux without a Windows host, and a `posix-shell` CI job covering both platforms on Node 18 and 22.
- An `Upgrade` section in `docs/SETUP.md`. You run the copies of the scripts under `%USERPROFILE%\.claude\9router`, not the ones in the repository, so pulling a new revision changes nothing until the installer is re-run — which nothing said. It also names what an upgrade does not do: `config.local.json` is created once and never merged again, so a setting added later is absent from yours, loudly if it is required and silently if it is not.

### Changed

- README opens with a capability table (command and effect per capability) and documents `claude-9router -DryRun`, which the scripts have always supported.
- README says what routing costs — MCP tool search off by default and Remote Control disabled once the base URL is not `api.anthropic.com` — and places this toolkit against setting `ANTHROPIC_BASE_URL` by hand and against a full routing control plane, so a reader can tell which of the three they actually want.

## [0.1.0] - 2026-08-11

### Added

- Config-driven Claude Code launcher for any model exposed by a compatible router.
- Reversible VSCode extension switching with settings backup and token redaction.
- Idempotent Windows installer and uninstaller.
- Isolated PowerShell test suite.
- Full 9Router/provider setup documentation.
- Community health files, issue forms, CI, and provider compatibility reporting.

[Unreleased]: https://github.com/vinhnguyenthanhdn/claude-router/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/vinhnguyenthanhdn/claude-router/releases/tag/v0.1.0
