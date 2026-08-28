#!/bin/sh
# A pull request may remove a public function from scripts/, but the
# description has to say which one and why.
#
# The shared config layer is a surface other files depend on by name:
# scripts/Common.ps1 and scripts/common.sh are dot-sourced by the launchers, by
# the installers, and now by the suites as well - tests/run-tests.ps1 loads
# Common.ps1 and calls Get-RouterConfig directly. A name that quietly leaves one
# of those files breaks callers that are not in the diff, and the reviewer sees
# only the file that changed. CONTRIBUTING.md asks for the same thing in prose;
# prose is skippable and a CI job is not.
#
# Which files count is decided by a property, not by a list: every tracked file
# under scripts/ that PowerShell or a POSIX shell would run, classified the same
# way the workflow classifies files it parses. A library added later is covered
# on the day it lands, with nobody remembering to add it here.
#
# The scan takes the two commits to compare as arguments, so the self-test below
# can point the same code at scratch repositories it must refuse. Pointing it at
# a real pull request proves nothing on its own: almost every pull request
# removes nothing, so a scan that had stopped being able to fire would look
# exactly like today's green.
#
# Usage:
#
#     PR_BODY="<pull request description>" sh tests/scope-guard.sh <base> <head>
#
# With no arguments it runs the self-test only, which is what the workflow step
# that discovers every tests/*.sh does on a push.
set -eu

# Tracked files under scripts/ that either shell runs, at one commit. The .cmd
# shim and any data file are skipped: they declare no functions.
scripts_at() {
  ref="$1"
  for path in $(git ls-tree -r --name-only "$ref" -- scripts/); do
    case "$path" in
      *.ps1 | *.sh)
        echo "$path"
        continue
        ;;
    esac
    case "$(git show "$ref:$path" 2>/dev/null | head -c 32)" in
      '#!/bin/sh'* | '#!/usr/bin/env sh'*) echo "$path" ;;
    esac
  done
}

# Top-level function names defined in one file at one commit. A function nested
# inside a block or written on a continued line is not seen; both styles are
# absent here and the parse step keeps the files in the shape this reads.
names_at() {
  ref="$1"
  path="$2"
  case "$path" in
    *.ps1)
      git show "$ref:$path" 2>/dev/null |
        sed -n 's/^function[ 	][ 	]*\([A-Za-z][A-Za-z0-9_-]*\).*/\1/p'
      ;;
    *)
      git show "$ref:$path" 2>/dev/null |
        sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)()[ 	]*{.*/\1/p'
      ;;
  esac
}

guard() {
  root="$1"
  base="$2"
  head="$3"
  CDPATH='' cd -- "$root" >/dev/null 2>&1 || { echo "no such tree: $root" >&2; return 1; }

  found=0
  removed=''
  for path in $(scripts_at "$base"); do
    before=$(names_at "$base" "$path")
    after=$(names_at "$head" "$path")
    for name in $before; do
      found=$((found + 1))
      if ! printf '%s\n' $after | grep -qx -- "$name"; then
        removed="$removed $path:$name"
      fi
    done
  done

  # A rename of scripts/, a change to how functions are written, or a sed that
  # stopped matching all look like "nothing was removed" without this.
  if [ "$found" -eq 0 ]; then
    echo "scope-guard: no function was found under scripts/ at $base - the scan must never be empty." >&2
    return 1
  fi

  if [ -z "$removed" ]; then
    echo "scope-guard: $found public function(s) checked, none removed."
    return 0
  fi

  unexplained=0
  for entry in $removed; do
    path=${entry%%:*}
    name=${entry#*:}
    if printf '%s' "${PR_BODY:-}" | grep -qF -- "$name"; then
      echo "scope-guard: $path removes $name -- mentioned in the pull request description."
    else
      echo "scope-guard: $path removes $name -- NOT MENTIONED in the pull request description."
      unexplained=$((unexplained + 1))
    fi
  done

  if [ "$unexplained" -eq 0 ]; then
    echo "scope-guard: every removal is named in the pull request description."
    return 0
  fi

  echo "Either restore the functions listed as NOT MENTIONED, or name each of them"
  echo "in the pull request description together with the reason it is going away."
  return 1
}

# One scratch repository per case, each with a base commit and a head commit.
# The identity is assembled from fragments because tests/scan-secrets.ps1 scans
# every tracked file, including this one, and refuses anything shaped like an
# address.
scratch_commit() {
  message="$1"
  git add --force -- scripts
  git \
    -c user.name=scope-guard-self-test \
    -c user.email="scope-guard@""example.invalid" \
    -c commit.gpgsign=false \
    commit -qm "$message"
}

write_base_tree() {
  mkdir -p scripts
  printf 'function Get-Thing {\n}\nfunction Set-Thing {\n}\n' > scripts/Common.ps1
  printf '#!/bin/sh\nrouter_read() {\n  :\n}\n' > scripts/common.sh
}

self_test() {
  for case_name in ps1-removed sh-removed removed-and-mentioned clean; do
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/claude-router-scope-XXXXXX")
    (
      cd "$tmp"
      git init -q .
      write_base_tree
      scratch_commit base

      case "$case_name" in
        ps1-removed | removed-and-mentioned)
          printf 'function Get-Thing {\n}\n' > scripts/Common.ps1
          ;;
        sh-removed)
          printf '#!/bin/sh\n' > scripts/common.sh
          ;;
        clean)
          printf 'function Get-Thing {\n}\nfunction Set-Thing {\n}\nfunction New-Thing {\n}\n' \
            > scripts/Common.ps1
          ;;
      esac
      scratch_commit head
    )

    body=''
    [ "$case_name" = removed-and-mentioned ] && body='Drops Set-Thing, which no caller used.'

    base=$(git -C "$tmp" rev-parse 'HEAD^')
    head=$(git -C "$tmp" rev-parse HEAD)
    status=0
    output=$(PR_BODY="$body" guard "$tmp" "$base" "$head" 2>&1) || status=$?
    rm -rf "$tmp"

    case "$case_name" in
      ps1-removed | sh-removed)
        expected=Set-Thing
        [ "$case_name" = sh-removed ] && expected=router_read
        if [ "$status" -eq 0 ]; then
          echo "the guard accepted an unexplained removal ($case_name) - it can no longer go red" >&2
          return 1
        fi
        if ! printf '%s' "$output" | grep -qF -- "$expected"; then
          echo "the guard went red for $case_name without naming $expected" >&2
          printf '%s\n' "$output" >&2
          return 1
        fi
        echo "rejected as expected, naming $expected: $case_name"
        ;;
      *)
        if [ "$status" -ne 0 ]; then
          echo "the guard rejected $case_name - it refuses everything, so the other cases prove nothing" >&2
          printf '%s\n' "$output" >&2
          return 1
        fi
        echo "accepted as expected: $case_name"
        ;;
    esac
  done
  echo "self-test: the guard still fires on an unexplained removal in either language"
}

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." >/dev/null 2>&1 && pwd -P)
self_test

if [ "$#" -eq 2 ]; then
  ( guard "$root" "$1" "$2" )
else
  echo "scope-guard: no base and head given, so only the self-test ran."
fi
