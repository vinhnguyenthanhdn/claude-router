#!/bin/sh
# Every tracked .ps1 must be pure ASCII, and this check must still be able to
# fail.
#
# Windows PowerShell 5.1 reads a file without a BOM as ANSI, so a UTF-8 em dash
# (E2 80 94) decodes through cp1252 into a smart double quote. PowerShell treats
# that as a real quote, the string ends mid-sentence, and the parse step reports
# `Unexpected token '<some word>'` several words away from the cause, with no
# line number. Every .ps1 here happens to be ASCII, which is a convention nobody
# wrote down and nothing enforced.
#
# The scan takes the tree to inspect as an argument, so the self-test below can
# point the same code at a scratch repository holding a file it must refuse.
# Pointing it at this repository proves nothing on its own: the answer is always
# "clean", and a pattern that stopped matching would look identical.
#
# It runs from the POSIX side even though the failure it prevents is
# Windows-only. The question is about bytes in committed files, so any platform
# can answer it, and this side is discovered automatically by the workflow.
set -eu

# Printable ASCII plus tab. Anything else - an em dash, a non-breaking space, a
# stray CR - is refused, because all of them change how 5.1 reads the file.
allowed='[^ -~	]'

scan() {
  root="$1"
  CDPATH='' cd -- "$root" >/dev/null 2>&1 || { echo "no such tree: $root" >&2; return 1; }

  found=0
  bad=0
  for file in $(git ls-files '*.ps1'); do
    found=$((found + 1))
    if hits=$(LC_ALL=C grep -n "$allowed" "$file"); then
      bad=$((bad + 1))
      echo "$file has bytes outside printable ASCII; PowerShell 5.1 will read them as cp1252:"
      echo "$hits" | LC_ALL=C sed 's/^/  /'
    fi
  done

  if [ "$found" -eq 0 ]; then
    echo "No tracked .ps1 file was found - this scan must never be empty." >&2
    return 1
  fi
  if [ "$bad" -gt 0 ]; then
    return 1
  fi
  echo "Scanned $found tracked .ps1 file(s), all pure ASCII."
}

# One scratch repository per case. The bad bytes are built with printf escapes
# rather than typed, so this file stays ASCII itself and the scan cannot trip
# over its own fixture.
self_test() {
  for case_name in em-dash nbsp clean; do
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/claude-router-ascii-XXXXXX")
    (
      cd "$tmp"
      # No identity is configured and nothing is committed: `git add` is enough
      # to make `git ls-files` report the file, and an address-shaped literal
      # here would be found by tests/scan-secrets.ps1 scanning this very file.
      git init -q .
      mkdir -p scripts
      case "$case_name" in
        em-dash) printf 'Write-Host "a dash \342\200\224 here"\n' > scripts/probe.ps1 ;;
        nbsp)    printf 'Write-Host "a space \302\240 here"\n' > scripts/probe.ps1 ;;
        clean)   printf 'Write-Host "plain ascii only"\n' > scripts/probe.ps1 ;;
      esac
      git add --force -- scripts/probe.ps1
    )

    status=0
    ( scan "$tmp" ) >/dev/null 2>&1 || status=$?
    rm -rf "$tmp"

    if [ "$case_name" = clean ]; then
      if [ "$status" -ne 0 ]; then
        echo "the scan rejected a pure ASCII tree - it refuses everything, so the other cases prove nothing" >&2
        return 1
      fi
      echo "accepted as expected: $case_name"
    else
      if [ "$status" -eq 0 ]; then
        echo "the scan accepted a .ps1 carrying $case_name - it can no longer go red" >&2
        return 1
      fi
      echo "rejected as expected: $case_name"
    fi
  done
  echo "self-test: the scan still fires on non-ASCII bytes and still passes a clean tree"
}

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." >/dev/null 2>&1 && pwd -P)
self_test
scan "$root"
