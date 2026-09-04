#!/bin/sh
# The two entries must send a user to the same place when they fail.
#
# An error message that names no destination is why this repo has never received
# an issue from a user: the launcher printed one bare line, and the reader had
# nothing to copy and nowhere to send it. The fix is only worth as much as its
# weakest platform, so the wording and the destinations live in scripts/Common.ps1
# and scripts/common.sh, and this script holds them to each other — the PowerShell
# suite cannot see the POSIX file and the POSIX suite cannot see the PowerShell one.
#
# Two properties, not one copied list:
#   1. every message either side prints, with the interpolated values blanked out,
#      must exist on the other side;
#   2. every URL either side can print must exist on the other side, unblanked —
#      the destinations are the payload, and blanking them would let a gate pass
#      while one platform pointed somewhere else entirely.
#
# Takes the tree to inspect as an argument so --self-test can point it at a
# deliberately broken copy; without that the pattern would have to be written
# down a second time to be tested, and the second copy is what drifts.
#
# Usage: report-destination-parity.sh [tree]
#        report-destination-parity.sh --self-test

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd -P)
repo_root=$(dirname -- "$here")

compare() {
    ROUTER_PARITY_TREE="$1" node -e '
const fs = require("fs");
const path = require("path");

const tree = process.env.ROUTER_PARITY_TREE;
const psPath = path.join(tree, "scripts", "Common.ps1");
const shPath = path.join(tree, "scripts", "common.sh");

// A message with its interpolated values blanked out. One side calling the
// detail $Detail and the other $1 is not a disagreement; different words are.
const shape = (s) => s
    .replace(/\$\((?:[^()]|\([^()]*\))*\)/g, "<>")        // PowerShell $( ... )
    .replace(/\$\{[^}]*\}/g, "<>")                        // ${ ... }
    .replace(/\$(?:script:)?[A-Za-z_][A-Za-z0-9_]*/g, "<>")   // $name, $script:Name
    .replace(/\$[0-9@*]/g, "<>")                          // shell positional
    .trim();

const readOr = (p) => {
    try {
        return fs.readFileSync(p, "utf8");
    } catch {
        console.error(`Cannot read ${p}.`);
        process.exit(1);
    }
};

// Messages, and the lines that were supposed to produce them. Counting the
// candidate lines is the half that survives a reformat: a pattern that stops
// matching one call site drops a message out of both sets, and two sets missing
// the same element still compare equal.
const psSrc = readOr(psPath);
const shSrc = readOr(shPath);

const collect = (src, callRe, stringRe) => {
    const calls = src.split("\n").filter((line) => callRe.test(line)).length;
    const found = [...src.matchAll(stringRe)].map((m) => shape(m[1] !== undefined ? m[1] : m[2]));
    return { calls, found };
};

const ps = collect(
    psSrc,
    /\[Console\]::Error\.WriteLine\(/,
    /\[Console\]::Error\.WriteLine\(\s*(?:"((?:[^"\\]|\\.)*)"|'"'"'((?:[^'"'"'\\]|\\.)*)'"'"')\s*\)/g
);
const sh = collect(
    shSrc,
    /^\s*printf\s+\S+\s+["'"'"'].*>&2\s*$/,
    /printf\s+[^ ]+\s+(?:"((?:[^"\\]|\\.)*)"|'"'"'((?:[^'"'"'\\]|\\.)*)'"'"')\s*>&2/g
);

const urls = (src) => new Set(src.match(/https?:\/\/[^\s"'"'"'`]+/g) || []);

let ok = true;
const fail = (m) => { ok = false; console.error(m); };

for (const [name, side, file] of [["Common.ps1", ps, psPath], ["common.sh", sh, shPath]]) {
    if (side.found.length === 0) {
        fail(`No report message found in ${file}; the ${name} pattern no longer matches anything.`);
    } else if (side.found.length !== side.calls) {
        fail(`${file} has ${side.calls} report call(s) but ${side.found.length} readable message(s); the ${name} pattern missed one.`);
    }
}
if (!ok) process.exit(1);

const psMsgs = new Set(ps.found);
const shMsgs = new Set(sh.found);
for (const m of [...psMsgs].filter((m) => !shMsgs.has(m)).sort()) {
    fail(`  only in scripts/Common.ps1: ${m}`);
}
for (const m of [...shMsgs].filter((m) => !psMsgs.has(m)).sort()) {
    fail(`  only in scripts/common.sh:  ${m}`);
}

const psUrls = urls(psSrc);
const shUrls = urls(shSrc);
for (const u of [...psUrls].filter((u) => !shUrls.has(u)).sort()) {
    fail(`  destination only in scripts/Common.ps1: ${u}`);
}
for (const u of [...shUrls].filter((u) => !psUrls.has(u)).sort()) {
    fail(`  destination only in scripts/common.sh:  ${u}`);
}
if (psUrls.size === 0 || shUrls.size === 0) {
    fail("One side names no destination at all; an error with nowhere to go is the state this gate exists to prevent.");
}

if (ok) {
    console.log(`report destination parity: OK (${psMsgs.size} messages, ${psUrls.size} destinations on both sides)`);
    process.exit(0);
}

console.error("");
console.error("Both entries promise the same failure output on either platform. Change");
console.error("both sides, or change the promise.");
process.exit(1);
'
}

# Runs the comparison and reports what it did, rather than what it should have
# done: a self-test that trusts its own setup proves nothing.
expect() {
    _want=$1      # pass | fail
    _label=$2
    _tree=$3
    _needle=${4:-}
    set +e
    _out=$(compare "$_tree" 2>&1)
    _code=$?
    set -e

    if [ "$_want" = pass ] && [ "$_code" -ne 0 ]; then
        echo "SELF-TEST FAIL: $_label should have passed, exit $_code"
        printf '%s\n' "$_out"
        exit 1
    fi
    if [ "$_want" = fail ] && [ "$_code" -eq 0 ]; then
        echo "SELF-TEST FAIL: $_label should have failed, exit 0"
        printf '%s\n' "$_out"
        exit 1
    fi
    if [ -n "$_needle" ] && ! printf '%s' "$_out" | grep -q -- "$_needle"; then
        echo "SELF-TEST FAIL: $_label did not name [$_needle]"
        printf '%s\n' "$_out"
        exit 1
    fi
    echo "  ok: $_label"
}

if [ "${1:-}" = '--self-test' ]; then
    scratch=$(mktemp -d)
    trap 'rm -rf "$scratch"' EXIT INT TERM

    mkdir -p "$scratch/clean/scripts"
    cp "$repo_root/scripts/Common.ps1" "$repo_root/scripts/common.sh" "$scratch/clean/scripts/"

    echo 'report destination parity self-test:'

    # A gate that refuses every tree satisfies every negative case, so the clean
    # tree has to pass before any of the others mean anything.
    expect pass 'an unmodified tree agrees' "$scratch/clean"

    # Reword one side.
    cp -R "$scratch/clean" "$scratch/reworded"
    sed 's/Report it here, with this output/Report it here, along with this output/' \
        "$scratch/clean/scripts/Common.ps1" > "$scratch/reworded/scripts/Common.ps1"
    expect fail 'a reworded PowerShell message is caught' "$scratch/reworded" 'along with this output'

    # Point one side somewhere else. This is the failure the blanked-out message
    # comparison cannot see, and the one that matters most to a reader.
    cp -R "$scratch/clean" "$scratch/redirected"
    sed 's|github.com/decolua/9router/issues|example.invalid/somewhere-else|' \
        "$scratch/clean/scripts/common.sh" > "$scratch/redirected/scripts/common.sh"
    expect fail 'a destination changed on one side only is caught' "$scratch/redirected" 'example.invalid'

    # Add a message to one side only. New output drifts the same way rewordings do.
    cp -R "$scratch/clean" "$scratch/extra"
    sed 's|^\(function Write-RouterUnexpected {\)$|\1\n    [Console]::Error.WriteLine("A line only the PowerShell entry prints.")|' \
        "$scratch/clean/scripts/Common.ps1" > "$scratch/extra/scripts/Common.ps1"
    expect fail 'a PowerShell-only message is caught' "$scratch/extra" 'only the PowerShell entry prints'

    # Interpolated values differ by platform and must not count as disagreement.
    cp -R "$scratch/clean" "$scratch/renamed"
    sed 's/\$Detail/$FailureText/g' \
        "$scratch/clean/scripts/Common.ps1" > "$scratch/renamed/scripts/Common.ps1"
    expect pass 'renaming an interpolated variable is not a disagreement' "$scratch/renamed"

    # The extraction failing open is the failure mode that hides every other one,
    # and it hides them by making both sides shorter at once.
    cp -R "$scratch/clean" "$scratch/silent"
    sed 's/\[Console\]::Error\.WriteLine(/[Console]::Error.WriteLine( @(/' \
        "$scratch/clean/scripts/Common.ps1" > "$scratch/silent/scripts/Common.ps1"
    expect fail 'an extraction that stops reading a call is an error, not a pass' \
        "$scratch/silent" 'pattern'

    echo 'report destination parity self-test: OK'
    exit 0
fi

compare "${1:-$repo_root}"
