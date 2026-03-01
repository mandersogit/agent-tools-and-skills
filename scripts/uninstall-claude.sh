#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="$HOME/.claude"

unlink_item() {
    local src_abs="$1" dst="$2"
    local dst_dir
    dst_dir="$(dirname "$dst")"
    local rel
    rel="$(realpath --relative-to="$dst_dir" "$src_abs")"

    if [ -L "$dst" ]; then
        existing="$(readlink "$dst")"
        if [ "$existing" = "$rel" ]; then
            rm "$dst"
            echo "  removed  $dst"
        else
            echo "  skipped  $dst -> $existing (not ours)"
        fi
    elif [ -e "$dst" ]; then
        echo "  skipped  $dst (not a symlink)"
    else
        echo "  absent   $dst"
    fi
}

# Skills: shared (skills/) and Claude-specific (claude/skills/)
for skills_dir in "$REPO_DIR/skills" "$REPO_DIR/claude/skills"; do
    [ -d "$skills_dir" ] || continue
    for skill in "$skills_dir"/*/; do
        [ -d "$skill" ] || continue
        name="$(basename "$skill")"
        unlink_item "$skill" "$CLAUDE_DIR/skills/$name"
    done
done

# Hooks
if [ -d "$REPO_DIR/claude/hooks" ]; then
    unlink_item "$REPO_DIR/claude/hooks" "$CLAUDE_DIR/hooks"
fi

# Claude-specific config files
for cfg in "$REPO_DIR"/claude/*.json; do
    [ -f "$cfg" ] || continue
    name="$(basename "$cfg")"
    unlink_item "$cfg" "$CLAUDE_DIR/$name"
done

echo ""
echo "Done. settings.json was not modified."
