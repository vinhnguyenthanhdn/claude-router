# POSIX shell counterpart of Common.ps1: locating the router config, reading it,
# and refusing it when it is not usable. Sourced by the shell entries; it defines
# functions and sets variables, and deliberately runs nothing on its own.
#
# JSON is parsed by node rather than jq or python3. Claude Code already requires
# node, so this adds no dependency the user does not have; jq and python3 are
# both absent from plenty of machines that run Claude Code fine.
#
# Every rule below mirrors Common.ps1, including the wording of the errors, so
# the two platforms fail the same way on the same file.

# The scripts directory, which is what PowerShell gets for free as $PSScriptRoot
# and POSIX shells do not expose for a sourced file. Every shell entry lives in
# scripts/, so the sourcing script's own path answers it; anything sourcing this
# file from elsewhere — the test harness, for one — sets ROUTER_SCRIPT_DIR.
router_script_dir() {
    if [ -n "${ROUTER_SCRIPT_DIR:-}" ]; then
        CDPATH='' cd -- "$ROUTER_SCRIPT_DIR" >/dev/null 2>&1 && pwd -P
        return
    fi
    CDPATH='' cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd -P
}

router_abs_path() {
    _rap_dir=$(CDPATH='' cd -- "$(dirname -- "$1")" >/dev/null 2>&1 && pwd -P) || return 1
    printf '%s/%s\n' "$_rap_dir" "$(basename -- "$1")"
}

# Precedence, highest first: explicit argument, $CLAUDE_ROUTER_CONFIG,
# scripts/config.local.json, then config.local.json at the repository root.
router_resolve_config_path() {
    _rrcp_dir=$(router_script_dir)
    for _rrcp_candidate in \
        "$1" \
        "${CLAUDE_ROUTER_CONFIG:-}" \
        "$_rrcp_dir/config.local.json" \
        "$(dirname -- "$_rrcp_dir")/config.local.json"
    do
        [ -n "$_rrcp_candidate" ] || continue
        [ -f "$_rrcp_candidate" ] || continue
        router_abs_path "$_rrcp_candidate"
        return 0
    done

    echo "Router config not found. Copy config.example.json to config.local.json and add your 9Router API key." >&2
    return 1
}

# Reads and validates the config, then exports the four values the launchers
# need. On failure it prints the reason and returns non-zero, having exported
# nothing.
router_load_config() {
    ROUTER_CONFIG_PATH=$(router_resolve_config_path "$1") || return 1

    # node prints the validated values, one per line, in a fixed order. Values
    # are single-line by construction — a newline inside one of these fields
    # cannot survive an environment variable intact, so the reader rejects it
    # rather than silently truncating the config.
    _rlc_out=$(ROUTER_CONFIG_PATH="$ROUTER_CONFIG_PATH" node -e '
const fs = require("fs");
const path = process.env.ROUTER_CONFIG_PATH;
const die = (m) => { console.error(m); process.exit(1); };

let config;
try {
    config = JSON.parse(fs.readFileSync(path, "utf8"));
} catch (err) {
    die(`Invalid JSON in router config ${JSON.stringify(path)}: ${err.message}`);
}
if (config === null || typeof config !== "object" || Array.isArray(config)) {
    die(`Invalid JSON in router config ${JSON.stringify(path)}: expected an object.`);
}

const read = (name) => (typeof config[name] === "string" ? config[name] : config[name] == null ? "" : String(config[name]));
for (const name of ["baseUrl", "authToken", "mainModel"]) {
    if (read(name).trim() === "") die(`Missing required config value: ${name}`);
}

let url;
try {
    url = new URL(read("baseUrl"));
} catch {
    die("baseUrl must be an absolute HTTP or HTTPS URL.");
}
if (url.protocol !== "http:" && url.protocol !== "https:") {
    die("baseUrl must be an absolute HTTP or HTTPS URL.");
}
if (/replace-with|your-api-key|^<.+>$/i.test(read("authToken"))) {
    die("Replace the placeholder authToken in config.local.json.");
}
if (/provider\/model-id|^<.+>$/i.test(read("mainModel"))) {
    die("Replace the placeholder mainModel in config.local.json.");
}

const values = [
    read("baseUrl").replace(/\/+$/, ""),
    read("authToken"),
    read("mainModel"),
    read("smallFastModel"),
];
if (values.some((v) => v.includes("\n"))) {
    die("Config values must be single-line: an environment variable cannot carry a line break.");
}
process.stdout.write(values.join("\n") + "\n");
') || return 1

    ROUTER_BASE_URL=$(printf '%s\n' "$_rlc_out" | sed -n '1p')
    ROUTER_AUTH_TOKEN=$(printf '%s\n' "$_rlc_out" | sed -n '2p')
    ROUTER_MAIN_MODEL=$(printf '%s\n' "$_rlc_out" | sed -n '3p')
    ROUTER_SMALL_FAST_MODEL=$(printf '%s\n' "$_rlc_out" | sed -n '4p')
    export ROUTER_CONFIG_PATH ROUTER_BASE_URL ROUTER_AUTH_TOKEN ROUTER_MAIN_MODEL ROUTER_SMALL_FAST_MODEL
}

# The environment names the toolkit owns. Anything else in a user's environment
# or settings file is none of its business — the Windows switch keeps unrelated
# entries untouched and the shell side has to keep the same promise.
ROUTER_MANAGED_ENV_NAMES='ANTHROPIC_BASE_URL
ANTHROPIC_AUTH_TOKEN
ANTHROPIC_API_KEY
ANTHROPIC_MODEL
ANTHROPIC_SMALL_FAST_MODEL
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'

router_is_managed_env_name() {
    printf '%s\n' "$ROUTER_MANAGED_ENV_NAMES" | grep -qx -- "$1"
}
