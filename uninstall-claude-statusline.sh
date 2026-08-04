#!/bin/bash
# Uninstaller for claude-statusline. Reverts exactly what the installer touched.
#   curl -fsSL https://raw.githubusercontent.com/zoo3323/claude-statusline/main/uninstall-claude-statusline.sh | bash
#
# As in the installer, everything runs from the `main "$@"` on the last line, so a
# truncated download removes nothing rather than removing half of it.
set -e

CLAUDE_DIR="$HOME/.claude"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
SETTINGS="$CLAUDE_DIR/settings.json"
LOCAL_BIN="$HOME/.local/bin"

# Keep the three most recent settings backups (see the installer).
prune_settings_backups() {
  local old
  old=$(ls -t "$SETTINGS".bak.* 2>/dev/null | tail -n +4) || true
  [ -n "$old" ] && printf '%s\n' "$old" | xargs rm -f
  return 0
}

clean_settings() {
  [ -f "$SETTINGS" ] || return 0
  if ! command -v jq >/dev/null 2>&1; then
    echo "⚠️  jq not found — left settings.json alone. Remove the statusLine and the Codex hook entries by hand."
    return 0
  fi
  cp "$SETTINGS" "$SETTINGS.bak.uninstall.$(date +%Y%m%d%H%M%S)"
  prune_settings_backups
  jq '
    if ((.statusLine.command // "") | test("statusline-codex\\.sh")) then del(.statusLine) else . end
    | .hooks.PreToolUse = ((.hooks.PreToolUse // []) | map(select(.matcher != "mcp__codex__codex|mcp__codex__codex-reply")))
    | .hooks.PostToolUse = ((.hooks.PostToolUse // []) | map(select(.matcher != "mcp__codex__codex|mcp__codex__codex-reply")))
    | .hooks.PostToolUseFailure = ((.hooks.PostToolUseFailure // []) | map(select(.matcher != "mcp__codex__codex|mcp__codex__codex-reply")))
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "✅ Removed only the status line and the Codex hooks from settings.json (other settings untouched, backup: $SETTINGS.bak.uninstall.*)"
}

remove_files() {
  rm -rf "$SCRIPTS_DIR/statusline-codex.sh" \
         "$SCRIPTS_DIR/codex-status-set.sh" \
         "$SCRIPTS_DIR/codex-usage-refresh.sh" \
         "$SCRIPTS_DIR/claude-usage-refresh.sh" \
         "$SCRIPTS_DIR/usage-refresh.sh" \
         "$CLAUDE_DIR/skills/refresh" \
         "$CLAUDE_DIR/codex-status"
}

# The cu-refresh symlink, but only while it still points at our script, so a
# cu-refresh someone else put there is left alone. Older versions installed an
# alias instead — drop that too.
remove_cu_refresh() {
  local link="$LOCAL_BIN/cu-refresh" rc
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$SCRIPTS_DIR/usage-refresh.sh" ]; then
    rm -f "$link"
  fi
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$rc" ] || continue
    if grep -q 'alias cu-refresh=' "$rc"; then
      # The last pattern is the localized comment line shipped by earlier versions.
      sed -i.bak '/alias cu-refresh=/d; /# Refresh both usage gauges now/d; /# Codex 사용량 즉시 새로고침/d' "$rc"
      rm -f "$rc.bak"
    fi
  done
}

main() {
  clean_settings
  remove_files
  remove_cu_refresh
  echo "✅ claude-statusline removed. Restart Claude Code and the status line is gone."
}

main "$@"
