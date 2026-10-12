#!/bin/bash
# Reads Codex account usage from the backend API and caches it for the status
# line. This is an account-info request, not a model request: it consumes no
# usage. statusline-codex.sh calls it in the background at most once every
# 5 minutes (via usage-refresh.sh).
#
# $1 (optional): how long, in seconds, numbers that came from Codex itself count
# as current. The status line passes 300: every codex call drops fresh
# rate_limits into its session log, so while that log is younger than this,
# polling would fetch numbers the log already beats. Manual runs (cu-refresh,
# /refresh) pass nothing and fetch regardless.
#
# Either way a cache written within the last minute is left alone, so a manual
# run landing right after a background poll does not ask twice.
export PATH="$HOME/.local/bin:$PATH"

AUTH="$HOME/.codex/auth.json"
CACHE="$HOME/.claude/codex-status/codex-usage.json"
[ -f "$AUTH" ] || exit 0

MAX_AGE=$1
case "$MAX_AGE" in *[!0-9]*) MAX_AGE="" ;; esac
now_s=$(date +%s)
fresh() { # $1=file $2=seconds -> success when the file is younger than that
  local m
  [ -f "$1" ] || return 1
  m=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0)
  [ $(( now_s - m )) -lt "$2" ]
}
fresh "$CACHE" 60 && exit 0
if [ -n "$MAX_AGE" ]; then
  for cf in $(ls -t "$HOME/.codex/sessions"/*/*/*/rollout-*.jsonl 2>/dev/null | head -3); do
    if grep -q '"rate_limits"' "$cf" 2>/dev/null; then
      fresh "$cf" "$MAX_AGE" && exit 0
      break
    fi
  done
fi

TOKEN=$(jq -r '.tokens.access_token // empty' "$AUTH" 2>/dev/null)
ACC=$(jq -r '.tokens.account_id // empty' "$AUTH" 2>/dev/null)
[ -z "$TOKEN" ] && exit 0

mkdir -p "$HOME/.claude/codex-status"
out=$(curl -s --max-time 8 \
  -H "Authorization: Bearer $TOKEN" \
  -H "chatgpt-account-id: $ACC" \
  "https://chatgpt.com/backend-api/wham/usage")

# Replace the cache only on a valid response (atomic write)
if printf '%s' "$out" | jq -e '.rate_limit.primary_window.used_percent' >/dev/null 2>&1; then
  printf '%s' "$out" > "$CACHE.tmp.$$" && mv "$CACHE.tmp.$$" "$CACHE"
fi
