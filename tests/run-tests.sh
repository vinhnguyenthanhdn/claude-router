#!/bin/sh
# Behavior tests for the POSIX side: scripts/common.sh (the config layer) and
# scripts/claude-9router (the launcher built on it).
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

# --- the launcher ----------------------------------------------------------
#
# The launcher's whole job is the environment it hands to Claude Code, so the
# assertions read that environment rather than the script's text. `claude` is a
# stub on PATH that prints the variables the toolkit owns and exits with a code
# the case chooses; nothing here runs a real Claude Code, and PATH is rebuilt
# per case inside a subshell so the stub cannot outlive it.

launcher="$root/scripts/claude-9router"
stub_dir="$temp/stub"
mkdir -p "$stub_dir"
cat > "$stub_dir/claude" <<'STUB'
#!/bin/sh
# Reports whether each managed name is set, and with what. "unset" is a
# distinct answer from empty: the launcher must remove names, not blank them.
for name in ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL \
    ANTHROPIC_SMALL_FAST_MODEL ANTHROPIC_API_KEY \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
do
    eval "set_check=\${$name+set}"
    if [ "${set_check:-}" = set ]; then
        eval "printf '%s=%s\n' \"\$name\" \"\$$name\""
    else
        printf '%s=<unset>\n' "$name"
    fi
done
printf 'ARGS=%s\n' "$*"
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$stub_dir/claude"

# Runs the launcher with the stub ahead of the real PATH, and prints its output
# followed by a final line carrying the exit status.
launch() {
    (
        PATH="$stub_dir:$PATH"
        export PATH
        set +e
        out=$("$launcher" "$@" 2>&1)
        status=$?
        set -e
        printf '%s\nSTATUS=%s\n' "$out" "$status"
    )
}

small="$temp/with-small.json"
write_config "$small" <<'JSON'
{
  "baseUrl": "https://router.test/api/",
  "authToken": "launcher-token-not-a-secret",
  "mainModel": "vendor/main-model",
  "smallFastModel": "vendor/small-model"
}
JSON

out=$(CLAUDE_ROUTER_CONFIG="$small" launch --dry-run)
check_contains 'dry run prints the base URL and the model' "$out" '[9Router] base=https://router.test/api model=vendor/main-model'
check_contains 'dry run says Claude Code was not started' "$out" 'dry run; Claude Code was not started'
check_eq 'dry run exits 0' "$(field "$out" '$')" 'STATUS=0'
case "$out" in
    *ARGS=*) fail 'dry run does not start Claude Code' 'the stub ran anyway' ;;
    *) ok 'dry run does not start Claude Code' ;;
esac
case "$out" in
    *launcher-token-not-a-secret*) fail 'the auth token is never printed' 'the token appeared in the output' ;;
    *) ok 'the auth token is never printed' ;;
esac

out=$(CLAUDE_ROUTER_CONFIG="$small" launch)
check_contains 'the child gets the base URL with the trailing slash stripped' "$out" 'ANTHROPIC_BASE_URL=https://router.test/api'
check_contains 'the child gets the auth token' "$out" 'ANTHROPIC_AUTH_TOKEN=launcher-token-not-a-secret'
check_contains 'the child gets the main model' "$out" 'ANTHROPIC_MODEL=vendor/main-model'
check_contains 'a configured smallFastModel reaches the child' "$out" 'ANTHROPIC_SMALL_FAST_MODEL=vendor/small-model'
check_contains 'nonessential traffic is disabled for the child' "$out" 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1'

# Both of these are about a parent shell that is already carrying the names:
# the launcher has to remove them, and "unset" is the only answer that proves it
# rather than a blank value the CLI would still read as configured.
no_small="$temp/no-small.json"
write_config "$no_small" <<'JSON'
{
  "baseUrl": "https://router.test",
  "authToken": "launcher-token-not-a-secret",
  "mainModel": "vendor/main-model"
}
JSON
out=$(
    ANTHROPIC_API_KEY='parent-key-not-a-secret' \
    ANTHROPIC_SMALL_FAST_MODEL='vendor/leftover-small' \
    CLAUDE_ROUTER_CONFIG="$no_small" launch
)
check_contains 'an inherited ANTHROPIC_API_KEY is removed for the child' "$out" 'ANTHROPIC_API_KEY=<unset>'
check_contains 'no smallFastModel in the config means unset in the child' "$out" 'ANTHROPIC_SMALL_FAST_MODEL=<unset>'

# The parent shell is the thing a user notices: if the launcher leaked, the next
# plain `claude` in the same window would still be routed.
parent=$(
    PATH="$stub_dir:$PATH"; export PATH
    ANTHROPIC_API_KEY='parent-key-not-a-secret'; export ANTHROPIC_API_KEY
    CLAUDE_ROUTER_CONFIG="$good"; export CLAUDE_ROUTER_CONFIG
    "$launcher" --dry-run >/dev/null 2>&1
    printf '%s|%s\n' "${ANTHROPIC_BASE_URL:-<unset>}" "${ANTHROPIC_API_KEY:-<unset>}"
)
check_eq 'the parent shell is unchanged after the launcher exits' "$parent" '<unset>|parent-key-not-a-secret'

out=$(CLAUDE_ROUTER_CONFIG="$small" launch --dry-run=no-such-form)
check_eq 'an unknown option is forwarded, not swallowed' "$(field "$out" '$')" 'STATUS=0'

out=$(CLAUDE_ROUTER_CONFIG="$small" launch -p 'hello world' --model x)
check_contains 'remaining arguments reach Claude Code unchanged' "$out" 'ARGS=-p hello world --model x'

out=$(CLAUDE_ROUTER_CONFIG="$small" launch -- --dry-run)
check_contains 'after -- the launcher options belong to Claude Code' "$out" 'ARGS=--dry-run'

out=$(STUB_EXIT=42 CLAUDE_ROUTER_CONFIG="$small" launch)
check_eq "Claude Code's exit code is propagated" "$(field "$out" '$')" 'STATUS=42'

# --config outranks $CLAUDE_ROUTER_CONFIG, the same precedence common.sh applies.
out=$(CLAUDE_ROUTER_CONFIG="$good" launch --config "$small" --dry-run)
check_contains '--config wins over CLAUDE_ROUTER_CONFIG' "$out" 'model=vendor/main-model'

out=$(CLAUDE_ROUTER_CONFIG="$good" launch --config="$small" --dry-run)
check_contains '--config=value is accepted too' "$out" 'model=vendor/main-model'

out=$(launch --config)
check_contains '--config with no path is refused' "$out" '--config needs a path'
check_eq '--config with no path exits non-zero' "$(field "$out" '$')" 'STATUS=2'

# A rejected config must stop the launcher before Claude Code starts, not after.
bad="$temp/bad-launcher.json"
write_config "$bad" <<'JSON'
{"baseUrl": "", "authToken": "t", "mainModel": "vendor/model"}
JSON
out=$(launch --config "$bad")
check_contains 'a rejected config names the offending field' "$out" 'Missing required config value: baseUrl'
check_eq 'a rejected config exits non-zero' "$(field "$out" '$')" 'STATUS=1'
case "$out" in
    *ARGS=*) fail 'a rejected config does not start Claude Code' 'the stub ran anyway' ;;
    *) ok 'a rejected config does not start Claude Code' ;;
esac

out=$(launch --config "$temp/no-such-config.json")
check_contains 'a missing config names the remedy' "$out" 'Copy config.example.json to config.local.json'

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
