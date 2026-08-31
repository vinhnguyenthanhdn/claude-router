#!/bin/sh
# The two config readers must refuse the same file with the same words.
#
# README.md, CONTRIBUTING.md and the header of scripts/common.sh all say so in
# prose, and until this script existed nothing checked it: the PowerShell suite
# exercises Common.ps1, the POSIX suite exercises common.sh, and neither one can
# see the other. A change to the wording on one side is green on both.
#
# What this asks is a property, not a copied list: pull every refusal each
# reader can print, blank out the interpolated values, and require the two sets
# to be equal. A message added to one side is a failure until the other side has
# it too, which is the only form of the promise that survives a new rule.
#
# Takes the tree to inspect as an argument so --self-test can point it at a
# deliberately broken copy; without that the pattern would have to be written
# down a second time to be tested, and the second copy is what drifts.
#
# Usage: config-refusal-parity.sh [tree]
#        config-refusal-parity.sh --self-test

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

// A refusal text with its interpolated values blanked out. Two readers naming
// different paths still agree; two readers using different words do not.
const shape = (s) => s
    .replace(/\$\((?:[^()]|\([^()]*\))*\)/g, "<>")   // PowerShell $( ... )
    .replace(/\$\{[^}]*\}/g, "<>")                   // JavaScript ${ ... }
    .replace(/\$[A-Za-z_][A-Za-z0-9_]*/g, "<>")      // PowerShell $name
    .trim();

const powershell = (src) =>
    [...src.matchAll(/throw\s+"((?:[^"\\]|\\.)*)"/g)].map((m) => shape(m[1]));

// The node half of common.sh lives inside a single-quoted shell string, so one
// apostrophe is written as a four-character close-escape-reopen run in the
// source and arrives as a single character at runtime. Undo that before
// comparing, or the embedding reads as a difference in wording and the gate is
// red on a repo that agrees. Built from char codes because this file embeds
// node the same way, and a literal apostrophe here would end the string.
const APOS = String.fromCharCode(39);
const unshell = (s) => s.split(APOS + "\\" + APOS + APOS).join(APOS);

// die() carries most of them; the config-not-found case is printed by the shell
// half of the file, before node is ever started, so it has to be read too.
const posix = (src) => [
    ...[...src.matchAll(/die\(`((?:[^`\\]|\\.)*)`\)/g)].map((m) => m[1]),
    ...[...src.matchAll(/die\("((?:[^"\\]|\\.)*)"\)/g)].map((m) => m[1]),
    ...[...src.matchAll(/echo\s+"((?:[^"\\]|\\.)*)"\s+>&2/g)].map((m) => m[1]),
].map(unshell).map(shape);

const readOr = (p) => {
    try {
        return fs.readFileSync(p, "utf8");
    } catch {
        console.error(`Cannot read ${p}.`);
        process.exit(1);
    }
};

const ps = new Set(powershell(readOr(psPath)));
const sh = new Set(posix(readOr(shPath)));

// An empty side means the extraction stopped matching, not that the two agree.
// Without this the day someone reformats a throw is the day the gate turns into
// a no-op and keeps reporting success.
for (const [name, set, file] of [["Common.ps1", ps, psPath], ["common.sh", sh, shPath]]) {
    if (set.size === 0) {
        console.error(`No refusal messages found in ${file}; the ${name} pattern no longer matches anything.`);
        process.exit(1);
    }
}

const onlyPs = [...ps].filter((m) => !sh.has(m)).sort();
const onlySh = [...sh].filter((m) => !ps.has(m)).sort();

if (onlyPs.length === 0 && onlySh.length === 0) {
    console.log(`config refusal parity: OK (${ps.size} messages on both sides)`);
    process.exit(0);
}

console.error("The two config readers do not refuse with the same wording.");
for (const m of onlyPs) console.error(`  only in scripts/Common.ps1: ${m}`);
for (const m of onlySh) console.error(`  only in scripts/common.sh:  ${m}`);
console.error("");
console.error("README.md, CONTRIBUTING.md and the header of scripts/common.sh all promise");
console.error("these two fail the same way on the same file. Change both sides, or change");
console.error("the promise.");
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

    echo 'config refusal parity self-test:'

    # A gate that refuses every tree satisfies every negative case, so the clean
    # tree has to pass before any of the others mean anything.
    expect pass 'an unmodified tree agrees' "$scratch/clean"

    # Reword one side. This is the exact shape of the change that reached CI
    # green in #27.
    cp -R "$scratch/clean" "$scratch/reworded"
    sed 's/Missing required config value: /Missing required property /' \
        "$scratch/clean/scripts/Common.ps1" > "$scratch/reworded/scripts/Common.ps1"
    expect fail 'a reworded PowerShell message is caught' "$scratch/reworded" 'Missing required property'

    # Add a rule to one side only. New refusals drift the same way rewordings do.
    cp -R "$scratch/clean" "$scratch/extra"
    sed 's|^\(const die = .*\)$|\1\nif (false) die("A rule only the POSIX reader has.");|' \
        "$scratch/clean/scripts/common.sh" > "$scratch/extra/scripts/common.sh"
    expect fail 'a POSIX-only rule is caught' "$scratch/extra" 'only the POSIX reader has'

    # Interpolated values differ by platform and must not count as disagreement.
    cp -R "$scratch/clean" "$scratch/renamed"
    sed 's/\$resolved/$configFilePath/g' \
        "$scratch/clean/scripts/Common.ps1" > "$scratch/renamed/scripts/Common.ps1"
    expect pass 'renaming an interpolated variable is not a disagreement' "$scratch/renamed"

    # The extraction failing open is the failure mode that hides every other one.
    cp -R "$scratch/clean" "$scratch/silent"
    sed "s/throw \"/throw @\"\n/" \
        "$scratch/clean/scripts/Common.ps1" > "$scratch/silent/scripts/Common.ps1"
    expect fail 'an extraction that matches nothing is an error, not a pass' \
        "$scratch/silent" 'no longer matches anything'

    echo 'config refusal parity self-test: OK'
    exit 0
fi

compare "${1:-$repo_root}"
