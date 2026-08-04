#!/bin/bash
# Uninstaller for claude-statusline. Reverts exactly what the installer touched.
#   curl -fsSL https://raw.githubusercontent.com/zoo3323/claude-statusline/main/uninstall-claude-statusline.sh | bash
set -e

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  cp "$SETTINGS" "$SETTINGS.bak.uninstall.$(date +%Y%m%d%H%M%S)"
  jq '
    if ((.statusLine.command // "") | test("statusline-codex\\.sh")) then del(.statusLine) else . end
    | .hooks.PreToolUse = ((.hooks.PreToolUse // []) | map(select(.matcher != "mcp__codex__codex|mcp__codex__codex-reply")))
    | .hooks.PostToolUse = ((.hooks.PostToolUse // []) | map(select(.matcher != "mcp__codex__codex|mcp__codex__codex-reply")))
    | .hooks.PostToolUseFailure = ((.hooks.PostToolUseFailure // []) | map(select(.matcher != "mcp__codex__codex|mcp__codex__codex-reply")))
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "✅ Removed only the status line and the Codex hooks from settings.json (other settings untouched, backup: $SETTINGS.bak.uninstall.*)"
fi

rm -rf "$CLAUDE_DIR/scripts/statusline-codex.sh" \
       "$CLAUDE_DIR/scripts/codex-status-set.sh" \
       "$CLAUDE_DIR/scripts/codex-usage-refresh.sh" \
       "$CLAUDE_DIR/scripts/claude-usage-refresh.sh" \
       "$CLAUDE_DIR/scripts/usage-refresh.sh" \
       "$CLAUDE_DIR/skills/refresh" \
       "$CLAUDE_DIR/codex-status"

for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  if [ -f "$rc" ]; then
    # The last pattern is the localized comment line shipped by earlier versions.
    sed -i.bak '/alias cu-refresh=/d; /# Refresh both usage gauges now/d; /# Codex 사용량 즉시 새로고침/d' "$rc"
    rm -f "$rc.bak"
  fi
done

echo "✅ claude-statusline removed. Restart Claude Code and the status line is gone."
