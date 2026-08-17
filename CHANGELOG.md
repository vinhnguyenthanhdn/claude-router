# Changelog

All notable changes to this project will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project intends to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `scripts/common.sh`, the POSIX counterpart of `Common.ps1`: same config lookup order, same validation, same error wording, with Node parsing the JSON so no new dependency is introduced.
- `tests/run-tests.sh`, a shell suite that runs on macOS and Linux without a Windows host, and a `posix-shell` CI job covering both platforms on Node 18 and 22.

### Changed

- README opens with a capability table (command and effect per capability) and documents `claude-9router -DryRun`, which the scripts have always supported.

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
