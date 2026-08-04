#!/bin/bash
# Tracks how many Codex MCP calls are in-flight for the current session (supports parallel calls).
# Usage: codex-status-set.sh <inc|dec>   (hook JSON piped on stdin)
op="$1"
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

mkdir -p "$HOME/.claude/codex-status"
count_file="$HOME/.claude/codex-status/${session_id}.count"
lock_dir="$HOME/.claude/codex-status/${session_id}.lock"

acquired=0
for _ in $(seq 1 50); do
  if mkdir "$lock_dir" 2>/dev/null; then
    acquired=1
    break
  fi
  sleep 0.05
done

current=$(cat "$count_file" 2>/dev/null || echo 0)
case "$op" in
  inc) new=$((current + 1)) ;;
  dec) new=$((current - 1)); [ "$new" -lt 0 ] && new=0 ;;
  *) new=$current ;;
esac
echo "$new" > "$count_file"

[ "$acquired" = "1" ] && rmdir "$lock_dir" 2>/dev/null
exit 0
