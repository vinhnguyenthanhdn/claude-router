#!/bin/sh
# Behavior tests for scripts/common.sh, the POSIX side of the config layer.
#
# Everything runs against a throwaway tree under $TMPDIR: the suite never reads
# or writes a real config, a real settings file, or anything under the user's
# profile. It is the same promise tests/run-tests.ps1 makes on Windows.
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." >/dev/null 2>&1 && pwd -P)
temp=$(mktemp -d "${TMPDIR:-/tmp}/claude-router-tests-XXXXXX")
trap 'rm -rf "$temp"' EXIT INT TERM

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

check_eq() {
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        fail "$1" "expected [$3], got [$2]"
    fi
}

check_contains() {
    case "$2" in
        *"$3"*) ok "$1" ;;
        *) fail "$1" "expected to contain [$3], got [$2]" ;;
    esac
}

write_config() {
    cat > "$1"
}

# Loads the config in a subshell so one case cannot leak values into the next,
# and prints either the resolved values or the error, plus the exit status.
load() {
    (
        ROUTER_SCRIPT_DIR="${FAKE_SCRIPTS:-$root/scripts}"
        export ROUTER_SCRIPT_DIR
        # shellcheck source=../scripts/common.sh
        . "$root/scripts/common.sh"
        if router_load_config "${1:-}" 2>"$temp/err"; then
            printf '%s\n%s\n%s\n%s\n%s\n' "$ROUTER_CONFIG_PATH" "$ROUTER_BASE_URL" \
                "$ROUTER_AUTH_TOKEN" "$ROUTER_MAIN_MODEL" "$ROUTER_SMALL_FAST_MODEL"
        else
            exit 1
        fi
    )
}

field() { printf '%s\n' "$1" | sed -n "$2p"; }

# --- a config that is fine ------------------------------------------------

good="$temp/good.json"
write_config "$good" <<'JSON'
{
  "baseUrl": "http://127.0.0.1:20128/",
  "authToken": "test-token-not-a-secret",
  "mainModel": "test/main-model",
  "smallFastModel": "test/small-model"
}
JSON

if out=$(load "$good"); then
    check_eq 'explicit path is used as given' "$(field "$out" 2)" 'http://127.0.0.1:20128'
    check_eq 'trailing slashes are trimmed from baseUrl' "$(field "$out" 2)" 'http://127.0.0.1:20128'
    check_eq 'authToken is read verbatim' "$(field "$out" 3)" 'test-token-not-a-secret'
    check_eq 'mainModel is read verbatim' "$(field "$out" 4)" 'test/main-model'
    check_eq 'smallFastModel is read when present' "$(field "$out" 5)" 'test/small-model'
else
    fail 'a valid config loads' "$(cat "$temp/err")"
fi

minimal="$temp/minimal.json"
write_config "$minimal" <<'JSON'
{"baseUrl": "https://example.test", "authToken": "t", "mainModel": "vendor/model"}
JSON
if out=$(load "$minimal"); then
    check_eq 'smallFastModel is optional and reads empty' "$(field "$out" 5)" ''
else
    fail 'a config without smallFastModel loads' "$(cat "$temp/err")"
fi

# --- where the config is looked up ----------------------------------------
# A fake scripts/ tree, so precedence is exercised without a config.local.json
# ever existing inside the repository.

FAKE_SCRIPTS="$temp/fake/scripts"
mkdir -p "$FAKE_SCRIPTS"
export FAKE_SCRIPTS

write_config "$temp/fake/config.local.json" <<'JSON'
{"baseUrl": "https://root.test", "authToken": "t", "mainModel": "vendor/root"}
JSON
if out=$(load ''); then
    check_eq 'the repository root config is the last resort' "$(field "$out" 2)" 'https://root.test'
else
    fail 'the repository root config is found' "$(cat "$temp/err")"
fi

write_config "$FAKE_SCRIPTS/config.local.json" <<'JSON'
{"baseUrl": "https://scripts.test", "authToken": "t", "mainModel": "vendor/scripts"}
JSON
if out=$(load ''); then
    check_eq 'the scripts config outranks the repository root' "$(field "$out" 2)" 'https://scripts.test'
else
    fail 'the scripts config is found' "$(cat "$temp/err")"
fi

envcfg="$temp/from-env.json"
write_config "$envcfg" <<'JSON'
{"baseUrl": "https://env.test", "authToken": "t", "mainModel": "vendor/env"}
JSON
if out=$(CLAUDE_ROUTER_CONFIG="$envcfg" load ''); then
    check_eq 'CLAUDE_ROUTER_CONFIG outranks both file locations' "$(field "$out" 2)" 'https://env.test'
else
    fail 'CLAUDE_ROUTER_CONFIG is honoured' "$(cat "$temp/err")"
fi

if out=$(CLAUDE_ROUTER_CONFIG="$envcfg" load "$good"); then
    check_eq 'an explicit path outranks CLAUDE_ROUTER_CONFIG' "$(field "$out" 2)" 'http://127.0.0.1:20128'
else
    fail 'an explicit path wins' "$(cat "$temp/err")"
fi

if out=$(CLAUDE_ROUTER_CONFIG="$temp/does-not-exist.json" load ''); then
    check_eq 'a missing CLAUDE_ROUTER_CONFIG falls through to the files' "$(field "$out" 2)" 'https://scripts.test'
else
    fail 'a missing CLAUDE_ROUTER_CONFIG falls through' "$(cat "$temp/err")"
fi

FAKE_SCRIPTS="$temp/empty/scripts"
mkdir -p "$FAKE_SCRIPTS"
if load '' >/dev/null 2>&1; then
    fail 'no config anywhere is an error'
else
    ok 'no config anywhere is an error'
    check_contains 'the not-found message names the file to create' "$(cat "$temp/err")" 'config.local.json'
fi
FAKE_SCRIPTS="$temp/fake/scripts"

# --- configs that must be refused -----------------------------------------

refuse() {
    name=$1
    expected=$2
    path="$temp/refuse.json"
    cat > "$path"
    if load "$path" >/dev/null 2>&1; then
        fail "$name" 'loaded a config that should have been refused'
    else
        check_contains "$name" "$(cat "$temp/err")" "$expected"
    fi
}

refuse 'broken JSON is refused by name' 'Invalid JSON in router config' <<'JSON'
{"baseUrl": "https://example.test",,}
JSON

refuse 'a JSON array is not a config' 'Invalid JSON in router config' <<'JSON'
["baseUrl", "https://example.test"]
JSON

refuse 'a missing mainModel is named' 'Missing required config value: mainModel' <<'JSON'
{"baseUrl": "https://example.test", "authToken": "t"}
JSON

refuse 'a blank authToken is missing, not present' 'Missing required config value: authToken' <<'JSON'
{"baseUrl": "https://example.test", "authToken": "   ", "mainModel": "vendor/model"}
JSON

refuse 'a relative baseUrl is refused' 'baseUrl must be an absolute HTTP or HTTPS URL.' <<'JSON'
{"baseUrl": "127.0.0.1:20128", "authToken": "t", "mainModel": "vendor/model"}
JSON

refuse 'a non-HTTP scheme is refused' 'baseUrl must be an absolute HTTP or HTTPS URL.' <<'JSON'
{"baseUrl": "ftp://example.test", "authToken": "t", "mainModel": "vendor/model"}
JSON

refuse 'the example authToken placeholder is refused' 'Replace the placeholder authToken' <<'JSON'
{"baseUrl": "https://example.test", "authToken": "replace-with-your-key", "mainModel": "vendor/model"}
JSON

refuse 'an angle-bracket authToken placeholder is refused' 'Replace the placeholder authToken' <<'JSON'
{"baseUrl": "https://example.test", "authToken": "<your token here>", "mainModel": "vendor/model"}
JSON

refuse 'the example mainModel placeholder is refused' 'Replace the placeholder mainModel' <<'JSON'
{"baseUrl": "https://example.test", "authToken": "t", "mainModel": "provider/model-id"}
JSON

refuse 'a value carrying a line break is refused' 'single-line' <<'JSON'
{"baseUrl": "https://example.test", "authToken": "line1\nline2", "mainModel": "vendor/model"}
JSON

# --- the shipped example must fail the same way a user's copy of it would ---

if out=$(load "$root/config.example.json" 2>/dev/null); then
    fail 'config.example.json is refused until it is filled in' 'the shipped example loaded as a real config'
else
    check_contains 'config.example.json is refused until it is filled in' "$(cat "$temp/err")" 'Replace the placeholder'
fi

# --- the managed name list ------------------------------------------------

managed=$(
    ROUTER_SCRIPT_DIR="$root/scripts"; export ROUTER_SCRIPT_DIR
    # shellcheck source=../scripts/common.sh
    . "$root/scripts/common.sh"
    router_is_managed_env_name ANTHROPIC_BASE_URL && printf 'yes '
    router_is_managed_env_name ANTHROPIC_API_KEY && printf 'yes '
    router_is_managed_env_name PATH || printf 'no'
)
check_eq 'only the toolkit-owned names are managed' "$managed" 'yes yes no'

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
