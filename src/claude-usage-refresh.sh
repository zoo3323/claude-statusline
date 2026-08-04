#!/bin/bash
# Reads Claude account usage (5-hour + weekly rate limits) and caches it for the
# status line. This is an account-info request, not a model request: it consumes
# no usage.
#
# Why it exists: Claude Code only refreshes the rate_limits block it hands to the
# status line after an API response. Without this poll the claude gauge freezes
# whenever you stop prompting, and keeps showing a spent window long after that
# window has reset. statusline-codex.sh calls this in the background at most once
# every 5 minutes.
export PATH="$HOME/.local/bin:$PATH"

CACHE="$HOME/.claude/codex-status/claude-usage.json"
CREDS="$HOME/.claude/.credentials.json"

# A cache written seconds ago is as good as a new call, and this endpoint answers
# bursts with 429 for a few minutes — so a manual cu-refresh landing right after a
# background poll would spend that budget for nothing.
if [ -f "$CACHE" ]; then
  cache_m=$(stat -c %Y "$CACHE" 2>/dev/null || stat -f %m "$CACHE" 2>/dev/null || echo 0)
  [ $(( $(date +%s) - cache_m )) -lt 60 ] && exit 0
fi

# OAuth token — the credentials file first, the macOS Keychain only if that file
# is missing or already stale. An expired token is skipped rather than traded for
# a 401: Claude Code rotates it on its own schedule and the next run picks the new
# one up.
read_token() { # stdin: credentials JSON -> "<token> <expiry_ms>"
  jq -r '.claudeAiOauth | select(.accessToken != null)
         | "\(.accessToken) \(.expiresAt // 0)"' 2>/dev/null
}

now_ms=$(( $(date +%s) * 1000 ))
usable() { # "<token> <expiry_ms>" -> success when present and good for 30s more
  [ -n "$1" ] || return 1
  local exp=${1##* }
  case "$exp" in ''|*[!0-9]*) exp=0 ;; esac
  [ "$exp" -eq 0 ] || [ "$exp" -gt $((now_ms + 30000)) ]
}

cand=""
[ -f "$CREDS" ] && cand=$(read_token < "$CREDS")
if ! usable "$cand"; then
  cand=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | read_token)
fi
usable "$cand" || exit 0
TOKEN=${cand%% *}

mkdir -p "$(dirname "$CACHE")"
out=$(curl -s --max-time 8 \
  -H "Authorization: Bearer $TOKEN" \
  -H "anthropic-beta: oauth-2025-04-20" \
  "https://api.anthropic.com/api/oauth/usage")

# Only touch the cache on a response that actually carries a window. Errors
# (including this endpoint's own rate limit) leave the previous cache in place.
printf '%s' "$out" | jq -e '(.five_hour.utilization // .seven_day.utilization) != null' >/dev/null 2>&1 || exit 0

# Normalise to the shape the status line reads: integer percentages and Unix
# epoch resets, matching what Claude Code puts in .rate_limits.
printf '%s' "$out" | jq '
  def epoch:                       # ISO-8601 (optional fraction/offset) -> epoch seconds
    if . == null then 0
    else (sub("\\.[0-9]+"; "")) as $s
      | ($s | capture("(?<off>Z|[+-][0-9]{2}:[0-9]{2})$") // {off: "Z"}) as $c
      | (($s | sub("(Z|[+-][0-9]{2}:[0-9]{2})$"; "")) + "Z" | fromdateiso8601) as $base
      | if $c.off == "Z" then $base
        else $base - ((($c.off[1:3] | tonumber) * 3600 + ($c.off[4:6] | tonumber) * 60)
                      * (if ($c.off[0:1]) == "+" then 1 else -1 end))
        end
    end;
  def window: if .utilization == null then null
              else {used_percentage: (.utilization | floor), resets_at: (.resets_at | epoch)} end;
  {fetched_at: (now | floor), five_hour: (.five_hour | window), seven_day: (.seven_day | window)}
' > "$CACHE.tmp" 2>/dev/null && mv "$CACHE.tmp" "$CACHE" || rm -f "$CACHE.tmp"
