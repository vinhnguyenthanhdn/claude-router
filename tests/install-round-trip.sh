#!/bin/sh
# The macOS/Linux Quick start, run end to end: install into a scratch bin
# directory, use the installed entry points, uninstall, and check what is left.
#
# This is the POSIX counterpart of tests/install-round-trip.ps1. Without it
# nothing exercises scripts/install.sh: tests/run-tests.sh sources common.sh
# directly and runs the launcher out of the clone, so an installed entry point
# that cannot find common.sh is green in every job while being broken for
# everyone who follows docs/SETUP.md.
#
# Nothing is written outside $TMPDIR. The bin directory is a scratch directory,
# and the config is passed with --config instead of being placed in the clone.
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." >/dev/null 2>&1 && pwd -P)
temp=$(mktemp -d "${TMPDIR:-/tmp}/claude-router-install-XXXXXX")
trap 'rm -rf "$temp"' EXIT INT TERM

bin="$temp/bin"
mkdir -p "$bin"

passed=0
failed=0

ok() {
    passed=$((passed + 1))
    printf 'ok   %s\n' "$1"
}

fail() {
    failed=$((failed + 1))
    printf 'FAIL %s\n' "$1"
    [ $# -lt 2 ] || printf '     %s\n' "$2"
}

check_contains() {
    case "$2" in
        *"$3"*) ok "$1" ;;
        *) fail "$1" "expected to contain [$3], got [$2]" ;;
    esac
}

check_missing() {
    case "$2" in
        *"$3"*) fail "$1" "did not expect [$3], got [$2]" ;;
        *) ok "$1" ;;
    esac
}

cat > "$temp/config.json" <<'JSON'
{
  "baseUrl": "https://router.invalid",
  "authToken": "install-round-trip",
  "mainModel": "vendor/round-trip"
}
JSON

printf '{}\n' > "$temp/settings.json"

# A file the installer did not put there, and a name that collides with one it
# did: the bin directory is shared, so uninstall has to leave both alone.
printf 'not ours\n' > "$bin/keep-me"

status=0
out=$(sh "$root/scripts/install.sh" "$bin" 2>&1) || status=$?
if [ "$status" -eq 0 ]; then
    ok 'install.sh exits 0'
else
    fail 'install.sh exits 0' "exit $status: $out"
fi

for name in claude-9router vscode-switch; do
    if [ -x "$bin/$name" ]; then
        ok "installed $name is executable"
    else
        fail "installed $name is executable"
    fi
done

# The defect this gate exists for. The installed entry point has to reach
# common.sh, which sits next to the launcher in the clone and not in the bin
# directory the user put on PATH.
status=0
out=$("$bin/claude-9router" --config "$temp/config.json" --dry-run 2>&1) || status=$?
if [ "$status" -eq 0 ]; then
    ok 'installed claude-9router --dry-run exits 0'
else
    fail 'installed claude-9router --dry-run exits 0' "exit $status: $out"
fi
check_contains 'installed claude-9router reaches the dry-run path' "$out" 'dry run'
check_missing 'installed claude-9router finds common.sh' "$out" 'common.sh'

# vscode-switch fails the same way but exits 0 while doing it, so the exit code
# proves nothing here and the message is what has to be checked.
status=0
out=$("$bin/vscode-switch" status --config "$temp/config.json" --settings "$temp/settings.json" 2>&1) || status=$?
check_missing 'installed vscode-switch finds common.sh' "$out" 'common.sh'

# The config lookup order docs/SETUP.md promises: with no --config the last two
# candidates resolve inside the clone, not inside the bin directory.
status=0
out=$(CLAUDE_ROUTER_CONFIG='' "$bin/claude-9router" --dry-run 2>&1) || status=$?
check_missing 'config lookup does not point at the bin directory' "$out" "$bin"

status=0
out=$(sh "$root/scripts/uninstall.sh" "$bin" 2>&1) || status=$?
if [ "$status" -eq 0 ]; then
    ok 'uninstall.sh exits 0'
else
    fail 'uninstall.sh exits 0' "exit $status: $out"
fi

for name in claude-9router vscode-switch; do
    if [ -e "$bin/$name" ] || [ -L "$bin/$name" ]; then
        fail "uninstall removed $name"
    else
        ok "uninstall removed $name"
    fi
done

if [ "$(cat "$bin/keep-me")" = 'not ours' ]; then
    ok 'uninstall left an unrelated file alone'
else
    fail 'uninstall left an unrelated file alone'
fi

# A path this clone never installed, under a name it does install.
printf 'not ours either\n' > "$bin/claude-9router"
status=0
out=$(sh "$root/scripts/uninstall.sh" "$bin" 2>&1) || status=$?
if [ "$status" -eq 0 ]; then
    ok 'uninstall.sh exits 0 with a foreign file in the way'
else
    fail 'uninstall.sh exits 0 with a foreign file in the way' "exit $status: $out"
fi
if [ -f "$bin/claude-9router" ] && [ "$(cat "$bin/claude-9router")" = 'not ours either' ]; then
    ok 'uninstall left a foreign claude-9router alone'
else
    fail 'uninstall left a foreign claude-9router alone' "$out"
fi
check_missing 'uninstall does not report a name it did not remove' "$out" 'Removed'

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
