#!/usr/bin/env sh
# Removes the launchers this clone installed from a bin directory.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd -P)
target_dir="${1:-$HOME/.local/bin}"

# The bin directory is shared and claude-9router is a name someone could have
# installed another way, so a path is removed only when it is this clone's
# wrapper or a symlink resolving to this clone's launcher.
installed_by_clone() {
    _ibc_path="$target_dir/$1"
    if [ -L "$_ibc_path" ]; then
        _ibc_link=$(readlink "$_ibc_path")
        case "$_ibc_link" in
            /*) ;;
            *) _ibc_link="$target_dir/$_ibc_link" ;;
        esac
        [ "$_ibc_link" = "$script_dir/$1" ]
    elif [ -f "$_ibc_path" ]; then
        grep -qxF "# claude-router wrapper for $script_dir/$1" "$_ibc_path"
    else
        return 1
    fi
}

for name in claude-9router vscode-switch; do
    path="$target_dir/$name"
    if installed_by_clone "$name"; then
        rm -f "$path"
        echo "Removed $path"
    elif [ -e "$path" ] || [ -L "$path" ]; then
        echo "Left $path in place: not installed from $script_dir"
    else
        echo "Not installed: $path"
    fi
done
