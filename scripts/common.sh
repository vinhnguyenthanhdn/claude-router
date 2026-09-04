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
    die(`Invalid JSON in router config '\''${path}'\'': ${err.message}`);
}
if (config === null || typeof config !== "object" || Array.isArray(config)) {
    die(`Invalid JSON in router config '\''${path}'\'': expected an object.`);
}

const read = (name) => (typeof config[name] === "string" ? config[name] : config[name] == null ? "" : String(config[name]));
for (const name of ["baseUrl", "authToken", "mainModel"]) {
    if (!(name in config)) die(`Missing required property '\''${name}'\'' in router config '\''${path}'\''.`);
    if (read(name).trim() === "") die(`Required property '\''${name}'\'' in router config '\''${path}'\'' cannot be empty.`);
}

let url;
try {
    url = new URL(read("baseUrl"));
} catch {
    die(`baseUrl must be an absolute HTTP or HTTPS URL in router config '\''${path}'\''.`);
}
if (url.protocol !== "http:" && url.protocol !== "https:") {
    die(`baseUrl must be an absolute HTTP or HTTPS URL in router config '\''${path}'\''.`);
}
if (/replace-with|your-api-key|^<.+>$/i.test(read("authToken"))) {
    die(`Replace the placeholder authToken in router config '\''${path}'\''.`);
}
if (/provider\/model-id|^<.+>$/i.test(read("mainModel"))) {
    die(`Replace the placeholder mainModel in router config '\''${path}'\''.`);
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

# Where a failure goes, and the two destinations are not interchangeable:
# anything the router, a provider or a model rejected happens inside 9Router and
# belongs upstream, while anything this toolkit did before handing over belongs
# here. A user who cannot tell the two apart reports neither.
#
# Printed with printf rather than echo on purpose: tests/config-refusal-parity.sh
# claims every echoed stderr line in this file as a config refusal and requires
# Common.ps1 to throw the same words, and these lines are not refusals of a
# config. tests/report-destination-parity.sh is the gate that holds them to
# their PowerShell counterparts. Quoting the echo form in a comment here is
# enough to be counted, which is what a pattern reading source text costs.
ROUTER_ISSUES_URL='https://github.com/vinhnguyenthanhdn/claude-router/issues/new/choose'
ROUTER_UPSTREAM_URL='https://github.com/decolua/9router/issues'

router_report_unexpected() {
    printf '%s\n' "claude-router stopped with an error it has no message for: $1" >&2
    printf '%s\n' "Report it here, with this output and the command you ran: $ROUTER_ISSUES_URL" >&2
    printf '%s\n' "If the router or a provider rejected the request, that belongs upstream: $ROUTER_UPSTREAM_URL" >&2
}

# A failure the toolkit already has words for: a config it refused by name, an
# option used wrong, a dependency it can tell the user to install. The exit trap
# in the entries stays quiet for these — the message is already the whole answer,
# and inviting a bug report on top of it teaches the user to ignore the invitation.
router_exit_expected() {
    ROUTER_EXPECTED_EXIT=1
    export ROUTER_EXPECTED_EXIT
    exit "${1:-1}"
}

# Reports any exit the launcher did not describe itself. Installed as an EXIT
# trap by the entries; `exec claude` replaces the process, so a failure that
# comes out of Claude Code or the router is never attributed to the wrapper.
router_report_exit() {
    _rre_status=$?
    [ "$_rre_status" -eq 0 ] && return 0
    [ "${ROUTER_EXPECTED_EXIT:-0}" = 1 ] && return "$_rre_status"
    router_report_unexpected "it exited with status $_rre_status before Claude Code started"
    return "$_rre_status"
}

# Claude Code itself is the one dependency the launcher cannot work around, and
# `exec claude` on a machine without it prints a shell-level "not found" that
# names neither this toolkit nor what to install.
router_require_claude() {
    command -v claude >/dev/null 2>&1 && return 0
    printf '%s\n' 'Claude Code was not found on PATH. Install it first, then run this launcher again; docs/SETUP.md has the steps.' >&2
    router_exit_expected 127
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
