#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="$HOME/.claude"

link_item() {
    local src_abs="$1" dst="$2"
    local dst_dir
    dst_dir="$(dirname "$dst")"
    local rel
    rel="$(realpath --relative-to="$dst_dir" "$src_abs")"

    if [ -L "$dst" ]; then
        existing="$(readlink "$dst")"
        if [ "$existing" = "$rel" ]; then
            echo "  ok        $dst"
            return
        fi
        echo "  CONFLICT  $dst -> $existing (expected $rel)"
        echo "            Remove it manually and re-run, or use: rm \"$dst\""
        return
    fi
    if [ -e "$dst" ]; then
        echo "  CONFLICT  $dst exists and is not a symlink"
        echo "            Back it up and remove it, then re-run."
        return
    fi
    ln -s "$rel" "$dst"
    echo "  linked    $dst -> $rel"
}

# Skills: shared (skills/) and Claude-specific (claude/skills/)
mkdir -p "$CLAUDE_DIR/skills"
for skills_dir in "$REPO_DIR/skills" "$REPO_DIR/claude/skills"; do
    [ -d "$skills_dir" ] || continue
    for skill in "$skills_dir"/*/; do
        [ -d "$skill" ] || continue
        name="$(basename "$skill")"
        link_item "$skill" "$CLAUDE_DIR/skills/$name"
    done
done

# Hooks: symlink the claude/hooks/ directory
if [ -d "$REPO_DIR/claude/hooks" ]; then
    link_item "$REPO_DIR/claude/hooks" "$CLAUDE_DIR/hooks"
fi

# Claude-specific config files: any .json file in claude/
for cfg in "$REPO_DIR"/claude/*.json; do
    [ -f "$cfg" ] || continue
    name="$(basename "$cfg")"
    link_item "$cfg" "$CLAUDE_DIR/$name"
done

echo ""
echo "Done."
echo ""
echo "NOTE: ~/.claude/settings.json is NOT managed by this repo."
echo "Ensure it contains the SessionStart hook. See README.md for the required config."
