#!/bin/sh
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." >/dev/null 2>&1 && pwd -P)
temp=$(mktemp -d "${TMPDIR:-/tmp}/claude-router-jsonc-XXXXXX")
trap 'rm -rf "$temp"' EXIT INT TERM
settings="$temp/settings.json"
config="$temp/config.json"
cat > "$settings" <<'JSON'
{
  // keep this comment
  "editor.fontSize": 13,
  "claudeCode.environmentVariables": [
    { "name": "MY_OWN_VAR", "value": "keep-me" },
  ],
}
JSON
cat > "$config" <<'JSON'
{"baseUrl":"https://router.test","authToken":"test-token","mainModel":"vendor/main"}
JSON

out=$("$root/scripts/vscode-switch" status --settings "$settings")
case "$out" in *"direct Anthropic/default environment"*) ;; *) echo "status did not accept JSONC" >&2; exit 1;; esac

before=$(cat "$settings")
if "$root/scripts/vscode-switch" on --config "$config" --settings "$settings" >"$temp/out" 2>&1; then
  echo 'on unexpectedly modified JSONC' >&2; exit 1
fi
case "$(cat "$temp/out")" in *"comments or trailing commas would be lost"*) ;; *) echo 'JSONC refusal message is wrong' >&2; exit 1;; esac
[ "$(cat "$settings")" = "$before" ]
[ ! -e "$settings.bak-claude-router" ]

cat > "$settings" <<'JSON'
{
  "claudeCode.environmentVariables": [
    { "name": "ANTHROPIC_BASE_URL", "value": "https://router.test" },
    { "name": "ANTHROPIC_MODEL", "value": "vendor/main" },
  ]
}
JSON
out=$("$root/scripts/vscode-switch" status --settings "$settings")
case "$out" in
  *"router enabled"*)
    case "$out" in
      *"Authentication token: configured (hidden)"*) ;;
      *) echo 'status did not report hidden token state' >&2; exit 1;;
    esac
    ;;
  *) echo 'status did not report JSONC router state' >&2; exit 1;;
esac
case "$out" in *"test-token"*) echo 'status leaked token' >&2; exit 1;; esac

before=$(cat "$settings")
if "$root/scripts/vscode-switch" off --settings "$settings" >"$temp/out" 2>&1; then
  echo 'off unexpectedly modified JSONC' >&2; exit 1
fi
case "$(cat "$temp/out")" in *"comments or trailing commas would be lost"*) ;; *) echo 'off JSONC refusal message is wrong' >&2; exit 1;; esac
[ "$(cat "$settings")" = "$before" ]
[ ! -e "$settings.bak-claude-router" ]

printf '%s\n' '{"a": }' > "$settings"
before=$(cat "$settings")
if "$root/scripts/vscode-switch" off --settings "$settings" >"$temp/out" 2>&1; then exit 1; fi
case "$(cat "$temp/out")" in *"Invalid JSON in VSCode settings"*) ;; *) exit 1;; esac
[ "$(cat "$settings")" = "$before" ]
[ ! -e "$settings.bak-claude-router" ]

for value in null '[]'; do
  printf '%s\n' "$value" > "$settings"
  before=$(cat "$settings")
  if "$root/scripts/vscode-switch" on --config "$config" --settings "$settings" >"$temp/out" 2>&1; then
    echo "on unexpectedly accepted non-object settings: $value" >&2
    exit 1
  fi
  case "$(cat "$temp/out")" in *"expected an object"*) ;; *) echo "non-object settings error is wrong: $value" >&2; exit 1;; esac
  [ "$(cat "$settings")" = "$before" ]
  [ ! -e "$settings.bak-claude-router" ]
done

echo 'All vscode-switch JSONC tests passed.'
