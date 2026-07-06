#!/bin/bash
# claude-statusline 제거 스크립트. 설치가 건드린 것만 정확히 되돌린다.
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
  echo "✅ settings.json에서 상태줄/Codex 훅만 제거했습니다 (다른 설정은 그대로, 백업: $SETTINGS.bak.uninstall.*)"
fi

rm -rf "$CLAUDE_DIR/scripts/statusline-codex.sh" \
       "$CLAUDE_DIR/scripts/codex-status-set.sh" \
       "$CLAUDE_DIR/scripts/codex-usage-refresh.sh" \
       "$CLAUDE_DIR/skills/refresh" \
       "$CLAUDE_DIR/codex-status"

for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  if [ -f "$rc" ]; then
    sed -i.bak '/alias cu-refresh=/d; /# Codex 사용량 즉시 새로고침/d' "$rc"
    rm -f "$rc.bak"
  fi
done

echo "✅ claude-statusline 제거 완료. Claude Code를 재시작하면 상태줄이 사라집니다."
