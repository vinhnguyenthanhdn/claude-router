#!/usr/bin/env sh
# Installs claude-9router and vscode-switch into a bin directory in PATH.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd -P)
target_dir="${1:-$HOME/.local/bin}"

mkdir -p "$target_dir"

# A wrapper rather than a symlink: each launcher derives its own directory from
# "$0" so it can source common.sh, and for a symlink "$0" is the link, so the
# launcher would look for common.sh in the bin directory. Exec-ing the real path
# keeps that directory inside the clone, which is where the config lookup order
# in docs/SETUP.md says the last two candidates live.
install_launcher() {
    chmod +x "$script_dir/$1"
    rm -f "$target_dir/$1"
    cat > "$target_dir/$1" <<EOF
#!/usr/bin/env sh
# claude-router wrapper for $script_dir/$1
exec "$script_dir/$1" "\$@"
EOF
    chmod +x "$target_dir/$1"
}

install_launcher claude-9router
install_launcher vscode-switch

echo "Installed launchers into $target_dir:"
echo "  $target_dir/claude-9router -> $script_dir/claude-9router"
echo "  $target_dir/vscode-switch  -> $script_dir/vscode-switch"

case ":$PATH:" in
    *":$target_dir:"*) ;;
    *)
        echo ""
        echo "Note: $target_dir is not in your PATH."
        echo "Add it to your shell profile (~/.bashrc or ~/.zshrc):"
        echo "  export PATH=\"$target_dir:\$PATH\""
        ;;
esac
