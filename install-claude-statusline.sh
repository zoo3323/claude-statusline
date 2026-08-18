#!/bin/bash
# Installer for the Claude Code status line + Codex hooks.
#   curl -fsSL https://raw.githubusercontent.com/zoo3323/claude-statusline/main/install-claude-statusline.sh | bash
#
# GENERATED FILE — do not edit. The scripts it writes live in src/; change them
# there and run ./build.sh.
#
# Everything is defined as functions and only run by the `main "$@"` on the last
# line. A download cut short therefore installs nothing at all instead of
# leaving a truncated script behind.
set -e

VERSION="1.0.0"

CLAUDE_DIR="$HOME/.claude"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
STATE_DIR="$CLAUDE_DIR/codex-status"
SKILLS_DIR="$CLAUDE_DIR/skills/refresh"
SETTINGS="$CLAUDE_DIR/settings.json"
LOCAL_BIN="$HOME/.local/bin"

verify_sha256() { # $1=file $2=expected hex digest
  local got
  if command -v shasum >/dev/null 2>&1; then
    got=$(shasum -a 256 "$1" | awk '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$1" | awk '{print $1}')
  else
    echo "⚠️  Neither shasum nor sha256sum found — skipping checksum verification."
    return 0
  fi
  [ "$got" = "$2" ]
}

# jq is required. Fetch it into ~/.local/bin when it is missing, so no admin
# rights and no package manager are needed. Digests are the ones published in
# the jq 1.7.1 release's own sha256sum.txt.
ensure_jq() {
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi
  echo "ℹ️  jq not found — installing it locally (no admin rights required)..."
  local ver="jq-1.7.1" asset sum tmp
  case "$(uname -s)/$(uname -m)" in
    Darwin/arm64)
      asset="jq-macos-arm64"; sum="0bbe619e663e0de2c550be2fe0d240d076799d6f8a652b70fa04aea8a8362e8a" ;;
    Darwin/*)
      asset="jq-macos-amd64"; sum="4155822bbf5ea90f5c79cf254665975eb4274d426d0709770c21774de5407443" ;;
    Linux/aarch64|Linux/arm64)
      asset="jq-linux-arm64"; sum="4dd2d8a0661df0b22f1bb9a1f9830f06b6f3b8f7d91211a1ef5d7c4f06a8b4a5" ;;
    Linux/*)
      asset="jq-linux-amd64"; sum="5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5" ;;
    *)
      echo "❌ No automatic install for this OS. Install jq yourself and run this again."
      return 1 ;;
  esac
  mkdir -p "$LOCAL_BIN"
  tmp="$LOCAL_BIN/.jq.download.$$"
  if ! curl -fsSL -o "$tmp" "https://github.com/jqlang/jq/releases/download/${ver}/${asset}"; then
    rm -f "$tmp"
    echo "❌ Could not download jq. Install it manually and run this again: (mac) brew install jq / (ubuntu) sudo apt install -y jq"
    return 1
  fi
  if ! verify_sha256 "$tmp" "$sum"; then
    rm -f "$tmp"
    echo "❌ The downloaded jq does not match its published checksum — refusing to install it."
    return 1
  fi
  chmod +x "$tmp"
  mv "$tmp" "$LOCAL_BIN/jq"
  export PATH="$LOCAL_BIN:$PATH"
  command -v jq >/dev/null 2>&1 || { echo "❌ jq is installed but still not on PATH."; return 1; }
  echo "✅ Installed jq to $LOCAL_BIN/jq"
}

# Put ~/.local/bin on PATH in shell rc files that lack it, so the next shell finds
# jq and cu-refresh. The pattern looks for a line that actually sets PATH, not a
# comment that happens to mention the directory.
ensure_local_bin_on_path() {
  local rc
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$rc" ] || continue
    if ! grep -qE '^[[:space:]]*[^#[:space:]].*PATH.*\.local/bin' "$rc"; then
      printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
    fi
  done
}

write_files() {
cat > "$SCRIPTS_DIR/statusline-codex.sh" <<'EMBEDDED_statusline-codex.sh'
#!/bin/bash
# Claude Code statusLine:
#   folder | model (effort) | codex usage | claude usage | context% | task
input=$(cat)
STATE_DIR="$HOME/.claude/codex-status"

# Keep the most recent payload that carried rate_limits, so other sessions (and
# agents) can read the numbers Claude Code handed us last.
case "$input" in
  *'"rate_limits"'*) printf '%s' "$input" > "$STATE_DIR/claude-last-input.json" ;;
esac

session_id=$(echo "$input" | jq -r '.session_id // empty')

# Shared palette — explicit 256-colour greys instead of dim (\033[2m), which
# some terminals render almost invisibly.
RESET='\033[0m'
GRAY='\033[38;5;245m'   # separators, secondary info (reset time), idle state
RAIL='\033[38;5;245m'   # gauge end rails
EMPTY='\033[38;5;240m'  # empty gauge cells (a touch darker than the fill)

mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
now_s=$(date +%s)

dir_name=$(basename "$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."')")
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
# Drop the trailing " (… context)" suffix: "Opus 4.8 (1M context)" -> "Opus 4.8"
model=$(printf '%s' "$model" | sed -E 's/ *\([^)]*context\)$//')

# effort: from JSON .effort.level, else the $CLAUDE_EFFORT environment variable
effort=$(echo "$input" | jq -r '.effort.level // empty')
[ -z "$effort" ] && effort="$CLAUDE_EFFORT"

# model (effort) — segment colour is the model: Fable magenta, Opus blue,
# Sonnet cyan, Haiku green
case "$(echo "$model" | tr '[:upper:]' '[:lower:]')" in
  *fable*)  mcolor='\033[38;5;213m' ;;
  *opus*)   mcolor='\033[38;5;75m'  ;;
  *sonnet*) mcolor='\033[38;5;80m'  ;;
  *haiku*)  mcolor='\033[38;5;114m' ;;
  *)        mcolor='\033[0m' ;;
esac
if [ -n "$effort" ]; then
  model_part=$(printf '%b%s (%s)%b' "$mcolor" "$model" "$effort" "$RESET")
else
  model_part=$(printf '%b%s%b' "$mcolor" "$model" "$RESET")
fi

# Context — percentage only, colour tracks the level (green → yellow → red).
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

ctx_part=""
if [ -n "$ctx_pct" ]; then
  if [ "$ctx_pct" -ge 90 ] 2>/dev/null; then color='\033[38;5;196m'
  elif [ "$ctx_pct" -ge 70 ] 2>/dev/null; then color='\033[38;5;214m'
  else color='\033[38;5;41m'; fi
  ctx_part=$(printf '%bctx %s%%%b' "$color" "$ctx_pct" "$RESET")
fi

# Usage gauge — drains from 100% as the quota is spent.
#  bar length = share of the 5-hour window left, block height (▁▂▃▄▅▆▇█) = weekly
usage_gauge() { # $1=5h used% $2=weekly used% $3=theme colour -> "gauge remaining%"
  local used=$1 weekly=$2 theme=$3 w=10 rem rem7 cells hc idx fill="" empty="" i c
  rem=$((100 - used)); [ "$rem" -lt 0 ] && rem=0
  cells=$(( (rem * w + 50) / 100 )); [ "$cells" -gt "$w" ] && cells=$w
  [ "$cells" -eq 0 ] && [ "$rem" -gt 0 ] && cells=1
  # Block height = weekly quota *left*, so it flattens as the week is spent.
  local chars=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
  hc="█"
  case "$weekly" in
    ''|*[!0-9]*) ;;
    *) rem7=$((100 - weekly)); [ "$rem7" -lt 0 ] && rem7=0
       idx=$(( rem7 * 8 / 100 )); [ "$idx" -gt 7 ] && idx=7; hc="${chars[$idx]}" ;;
  esac
  for ((i=0; i<cells; i++)); do fill="${fill}${hc}"; done
  for ((i=cells; i<w; i++)); do empty="${empty}░"; done
  if [ "$used" -ge 90 ] 2>/dev/null; then c='\033[38;5;196m'
  elif [ "$used" -ge 70 ] 2>/dev/null; then c='\033[38;5;214m'
  else c=$theme; fi
  # Dark background across the whole track, thin rails (▕ ▏) at both ends.
  printf '%b▕%b\033[48;5;238m%b%s%b%s%b%b▏%b%s%%' \
    "$RAIL" "$RESET" "$c" "$fill" "$EMPTY" "$empty" "$RESET" "$RAIL" "$RESET" "$rem"
}

reset_txt() { # $1=reset epoch -> "↻6d3h" / "↻1h23m" / "↻45m" (empty if past/unset)
  # Switches unit with the distance: days for a weekly window, hours/minutes for
  # a 5-hour one. Codex dropped its 5-hour window on 2026-07-12 and sent only
  # the weekly (~7 day) one, which is why days are shown at all; when a short
  # window comes back the display returns to hours/minutes on its own.
  local at=$1 remain rm_d rm_h rm_m
  [ -z "$at" ] && return
  remain=$(( at - $(date +%s) )) 2>/dev/null || return
  [ "$remain" -le 0 ] && return
  rm_d=$((remain / 86400)); rm_h=$(( (remain % 86400) / 3600 )); rm_m=$(( (remain % 3600) / 60 ))
  if [ "$rm_d" -gt 0 ]; then printf '%b↻%sd%sh%b' "$GRAY" "$rm_d" "$rm_h" "$RESET"
  elif [ "$rm_h" -gt 0 ]; then printf '%b↻%sh%sm%b' "$GRAY" "$rm_h" "$rm_m" "$RESET"
  else printf '%b↻%sm%b' "$GRAY" "$rm_m" "$RESET"; fi
}

# Pick the fresher of two readings of the same window. Usage only climbs until
# the window resets, so a later resets_at means a newer window, and inside one
# window the larger number is the more recent one.
fresher() { # $1=usedA $2=resetA $3=usedB $4=resetB -> "used reset" (blank if neither)
  local ua=$1 ra=$2 ub=$3 rb=$4
  case "$ua" in ''|*[!0-9]*) ua="" ;; esac
  case "$ub" in ''|*[!0-9]*) ub="" ;; esac
  case "$ra" in ''|*[!0-9]*) ra=0 ;; esac
  case "$rb" in ''|*[!0-9]*) rb=0 ;; esac
  if [ -z "$ua" ]; then
    [ -n "$ub" ] && printf '%s %s' "$ub" "$rb"
    return
  fi
  if [ -z "$ub" ]; then printf '%s %s' "$ua" "$ra"; return; fi
  if [ "$rb" -gt "$ra" ] || { [ "$rb" -eq "$ra" ] && [ "$ub" -gt "$ua" ]; }; then
    printf '%s %s' "$ub" "$rb"
  else
    printf '%s %s' "$ua" "$ra"
  fi
}

# Claude account usage (theme: Claude coral #D97757, height = weekly usage).
#
# Claude Code only refills the rate_limits block after an API response, so an
# idle session would keep painting the numbers it last saw — and once a window
# rolls over it would keep painting them for hours. So we read three sources and
# draw the freshest: this payload, the last payload any session received, and a
# background poll of the account usage endpoint (account info, not a model
# request: it costs no usage).
CL_CACHE="$STATE_DIR/claude-usage.json"
CL_MARK="$STATE_DIR/claude-usage.last"
cl_cache_m=0; [ -f "$CL_CACHE" ] && cl_cache_m=$(mtime_of "$CL_CACHE")
cl_mark_m=0;  [ -f "$CL_MARK" ]  && cl_mark_m=$(mtime_of "$CL_MARK")
# Refresh when the cache is over 5 minutes old. The mark file is touched on every
# attempt and shared by all sessions, so failures back off at the same 5-minute
# pace instead of hammering — that endpoint is itself rate limited and answers a
# burst with 429 for a few minutes.
if [ $((now_s - cl_cache_m)) -gt 300 ] && [ $((now_s - cl_mark_m)) -gt 300 ]; then
  touch "$CL_MARK"
  ( "$HOME/.claude/scripts/claude-usage-refresh.sh" >/dev/null 2>&1 & )
fi

# used% / resets_at for both windows, one tab-separated row per source. A missing
# percentage is emitted as "-" rather than an empty field: tab counts as IFS
# whitespace, so empty fields would collapse and shift every later column.
PAYLOAD_TSV='def n: (. // "-") | (floor? // .);
  [ (.rate_limits.five_hour.used_percentage | n), (.rate_limits.five_hour.resets_at // 0),
    (.rate_limits.seven_day.used_percentage | n), (.rate_limits.seven_day.resets_at // 0) ] | @tsv'
IFS=$'\t' read -r l5 l5r l7 l7r <<< "$(echo "$input" | jq -r "$PAYLOAD_TSV" 2>/dev/null)"
IFS=$'\t' read -r p5 p5r p7 p7r <<< "$(jq -r "$PAYLOAD_TSV" "$STATE_DIR/claude-last-input.json" 2>/dev/null)"
IFS=$'\t' read -r a5 a5r a7 a7r <<< "$(jq -r 'def n: (. // "-") | (floor? // .);
  [ (.five_hour.used_percentage | n), (.five_hour.resets_at // 0),
    (.seven_day.used_percentage | n), (.seven_day.resets_at // 0) ] | @tsv' "$CL_CACHE" 2>/dev/null)"

read -r c5 c5r <<< "$(fresher "$l5" "$l5r" "$p5" "$p5r")"
read -r c5 c5r <<< "$(fresher "$c5" "$c5r" "$a5" "$a5r")"
read -r c7 c7r <<< "$(fresher "$l7" "$l7r" "$p7" "$p7r")"
read -r c7 c7r <<< "$(fresher "$c7" "$c7r" "$a7" "$a7r")"

# A window whose reset time has passed has already rolled over: the numbers we
# hold describe the window before it, so the current one starts empty.
if [ -n "$c5" ] && [ "${c5r:-0}" -gt 0 ] && [ "$c5r" -le "$now_s" ]; then c5=0; c5r=0; fi
if [ -n "$c7" ] && [ "${c7r:-0}" -gt 0 ] && [ "$c7r" -le "$now_s" ]; then c7=0; c7r=0; fi

claude_part=""
if [ -n "$c5" ]; then
  claude_part="$(printf '\033[38;2;217;119;87mclaude\033[0m ')$(usage_gauge "$c5" "$c7" '\033[38;2;217;119;87m')"
  rt=$(reset_txt "$c5r")
  [ -n "$rt" ] && claude_part="$claude_part $rt"
fi

# Codex account usage — polled in the background every 5 minutes (account info,
# not a model request: it costs no usage). Whichever of the cache and the codex
# session log is newer wins.
# (theme: OpenAI green #10A37F, bar = 5h left, height = weekly, ↻ = time to reset)
CU_CACHE="$STATE_DIR/codex-usage.json"
CU_MARK="$STATE_DIR/codex-usage.last"
cache_m=0; [ -f "$CU_CACHE" ] && cache_m=$(mtime_of "$CU_CACHE")
mark_m=0;  [ -f "$CU_MARK" ]  && mark_m=$(mtime_of "$CU_MARK")
if [ $((now_s - cache_m)) -gt 300 ] && [ $((now_s - mark_m)) -gt 60 ] && [ -f "$HOME/.codex/auth.json" ]; then
  touch "$CU_MARK"
  ( "$HOME/.claude/scripts/codex-usage-refresh.sh" >/dev/null 2>&1 & )
fi

# Latest rate_limits in the session log (fresher than the cache right after a
# codex call)
cu_line=""; sess_m=0
for cf in $(ls -t "$HOME/.codex/sessions"/*/*/*/rollout-*.jsonl 2>/dev/null | head -3); do
  cu_line=$(grep '"rate_limits"' "$cf" 2>/dev/null | tail -1)
  [ -n "$cu_line" ] && { sess_m=$(mtime_of "$cf"); break; }
done

cu_pct=""; cu7_pct=""; cu_reset=""
if [ -f "$CU_CACHE" ] && [ "$cache_m" -ge "$sess_m" ]; then
  cu_pct=$(jq -r '.rate_limit.primary_window.used_percent // empty | floor' "$CU_CACHE" 2>/dev/null)
  cu7_pct=$(jq -r '.rate_limit.secondary_window.used_percent // empty | floor' "$CU_CACHE" 2>/dev/null)
  cu_reset=$(jq -r '.rate_limit.primary_window.reset_at // empty' "$CU_CACHE" 2>/dev/null)
elif [ -n "$cu_line" ]; then
  cu_pct=$(echo "$cu_line" | jq -r '.payload.rate_limits.primary.used_percent // empty | floor' 2>/dev/null)
  cu7_pct=$(echo "$cu_line" | jq -r '.payload.rate_limits.secondary.used_percent // empty | floor' 2>/dev/null)
  cu_reset=$(echo "$cu_line" | jq -r '.payload.rate_limits.primary.resets_at // empty' 2>/dev/null)
fi

# Codex usage segment (same shape as the claude gauge, label in OpenAI green)
cu_part=""
if [ -n "$cu_pct" ]; then
  cu_part="$(printf '\033[38;2;16;163;127mcodex\033[0m ')$(usage_gauge "$cu_pct" "$cu7_pct" '\033[38;2;16;163;127m')"
  crt=$(reset_txt "$cu_reset")
  [ -n "$crt" ] && cu_part="$cu_part $crt"
fi

# Task in progress (first in_progress one, ellipsised past 30 chars)
task_part=""
tasks_dir="$HOME/.claude/tasks/$session_id"
if [ -d "$tasks_dir" ]; then
  task=$(cat "$tasks_dir"/*.json 2>/dev/null | jq -r 'select(.status == "in_progress") | (.activeForm // .subject)' 2>/dev/null | head -1)
  if [ -n "$task" ]; then
    [ ${#task} -gt 30 ] && task="${task:0:29}…"
    task_part=$(printf '\033[1;38;5;214m▸ %s\033[0m' "$task")
  fi
fi

# Assemble one line:
#   [folder · model · codex gauge · claude gauge · context% · task]
sep=$(printf ' %b·%b ' "$GRAY" "$RESET")
left="$(printf '\033[1m%s\033[0m' "$dir_name")${sep}${model_part}"
[ -n "$cu_part" ] && left="${left}${sep}${cu_part}"
[ -n "$claude_part" ] && left="${left}${sep}${claude_part}"
[ -n "$ctx_part" ] && left="${left}${sep}${ctx_part}"
[ -n "$task_part" ] && left="${left}${sep}${task_part}"

printf '%s' "$left"
EMBEDDED_statusline-codex.sh
chmod +x "$SCRIPTS_DIR/statusline-codex.sh"

cat > "$SCRIPTS_DIR/codex-status-set.sh" <<'EMBEDDED_codex-status-set.sh'
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
EMBEDDED_codex-status-set.sh
chmod +x "$SCRIPTS_DIR/codex-status-set.sh"

cat > "$SCRIPTS_DIR/codex-usage-refresh.sh" <<'EMBEDDED_codex-usage-refresh.sh'
#!/bin/bash
# Reads Codex account usage from the backend API and caches it for the status
# line. This is an account-info request, not a model request: it consumes no
# usage. statusline-codex.sh calls it in the background at most once every
# 5 minutes.
export PATH="$HOME/.local/bin:$PATH"

AUTH="$HOME/.codex/auth.json"
CACHE="$HOME/.claude/codex-status/codex-usage.json"
[ -f "$AUTH" ] || exit 0

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
  printf '%s' "$out" > "$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
fi
EMBEDDED_codex-usage-refresh.sh
chmod +x "$SCRIPTS_DIR/codex-usage-refresh.sh"

cat > "$SCRIPTS_DIR/claude-usage-refresh.sh" <<'EMBEDDED_claude-usage-refresh.sh'
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
EMBEDDED_claude-usage-refresh.sh
chmod +x "$SCRIPTS_DIR/claude-usage-refresh.sh"

cat > "$SCRIPTS_DIR/usage-refresh.sh" <<'EMBEDDED_usage-refresh.sh'
#!/bin/bash
# Refreshes both usage caches right now, bypassing the status line's 5-minute
# schedule. Bound to the `cu-refresh` shell alias and used by the /refresh skill.
# Each half is independent: one failing (not logged in, endpoint rate limited)
# leaves the other's cache updated and the previous values in place.
DIR="$HOME/.claude/scripts"
[ -x "$DIR/codex-usage-refresh.sh" ] && "$DIR/codex-usage-refresh.sh"
[ -x "$DIR/claude-usage-refresh.sh" ] && "$DIR/claude-usage-refresh.sh"
exit 0
EMBEDDED_usage-refresh.sh
chmod +x "$SCRIPTS_DIR/usage-refresh.sh"

# refresh skill, so /refresh works from any session
mkdir -p "$SKILLS_DIR"
cat > "$SKILLS_DIR/SKILL.md" <<'EMBEDDED_SKILL.md'
---
name: refresh
description: Refresh the Codex and Claude usage gauges right now and report the numbers. Use when the user asks for "/refresh", "refresh usage", or "show me my usage now".
---

# refresh

Both usage gauges refresh in the background at most once every 5 minutes, so the
status line can be up to 5 minutes behind. Use this skill when the user wants the
current numbers immediately.

## Steps

1. Note the mtime of the two cache files, then run `~/.claude/scripts/usage-refresh.sh`
   with Bash. It refreshes both caches and prints nothing.
   - If that script does not exist, claude-statusline is not installed here. Say so and stop.
2. Read the caches:
   - Codex — `~/.claude/codex-status/codex-usage.json`: `rate_limit.primary_window.used_percent`
     (5-hour), `rate_limit.secondary_window.used_percent` (weekly),
     `rate_limit.primary_window.reset_at` (Unix epoch).
   - Claude — `~/.claude/codex-status/claude-usage.json`: `five_hour.used_percentage`,
     `seven_day.used_percentage`, `five_hour.resets_at` (Unix epoch), `fetched_at`.
3. A cache whose mtime did not change means one of two things — tell them apart by
   how old the file is:
   - Under a minute old: the poll was skipped on purpose, because the numbers were
     already current. Nothing is wrong.
   - Older than that: this half failed and its numbers are older than they look.
     Usual causes are Codex not being logged in (`~/.codex/auth.json` missing), the
     Claude usage endpoint rate-limiting the call (it answers bursts with 429 for a
     few minutes), or an OAuth token that expired before Claude Code rotated it.
     Report a stale half as stale rather than presenting old numbers as current.
4. Report the numbers in a line or two. The status line picks them up within its
   refresh interval (2s).
EMBEDDED_SKILL.md
}

# cu-refresh as a symlink on PATH instead of a shell alias, so no rc file has to
# be rewritten. Versions before 1.0.0 appended an alias; remove it when it is
# there, otherwise the alias would shadow the symlink forever.
link_cu_refresh() {
  local rc
  mkdir -p "$LOCAL_BIN"
  ln -sf "$SCRIPTS_DIR/usage-refresh.sh" "$LOCAL_BIN/cu-refresh"
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$rc" ] || continue
    if grep -q 'alias cu-refresh=' "$rc"; then
      # The last pattern is the localized comment line shipped by earlier versions.
      sed -i.bak '/alias cu-refresh=/d; /# Refresh both usage gauges now/d; /# Codex 사용량 즉시 새로고침/d' "$rc"
      rm -f "$rc.bak"
    fi
  done
}

# Keep the three most recent settings backups; installs and uninstalls each add
# one and nothing else ever cleans them up.
prune_settings_backups() {
  local old
  old=$(ls -t "$SETTINGS".bak.* 2>/dev/null | tail -n +4) || true
  [ -n "$old" ] && printf '%s\n' "$old" | xargs rm -f
  return 0
}

# Merge statusLine + the Codex hooks into settings.json (existing settings are
# preserved; a timestamped backup is written first).
merge_settings() {
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  prune_settings_backups
  jq '
    .statusLine = {type: "command", command: "~/.claude/scripts/statusline-codex.sh", refreshInterval: 2}
    | .hooks = (.hooks // {})
    | .hooks.PreToolUse = ((.hooks.PreToolUse // []) | map(select(.matcher != "mcp__codex__codex|mcp__codex__codex-reply")) + [{matcher: "mcp__codex__codex|mcp__codex__codex-reply", hooks: [{type: "command", command: "~/.claude/scripts/codex-status-set.sh inc 2>/dev/null || true"}]}])
    | .hooks.PostToolUse = ((.hooks.PostToolUse // []) | map(select(.matcher != "mcp__codex__codex|mcp__codex__codex-reply")) + [{matcher: "mcp__codex__codex|mcp__codex__codex-reply", hooks: [{type: "command", command: "~/.claude/scripts/codex-status-set.sh dec 2>/dev/null || true"}]}])
    | .hooks.PostToolUseFailure = ((.hooks.PostToolUseFailure // []) | map(select(.matcher != "mcp__codex__codex|mcp__codex__codex-reply")) + [{matcher: "mcp__codex__codex|mcp__codex__codex-reply", hooks: [{type: "command", command: "~/.claude/scripts/codex-status-set.sh dec 2>/dev/null || true"}]}])
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
}

main() {
  mkdir -p "$SCRIPTS_DIR" "$STATE_DIR"
  ensure_jq
  ensure_local_bin_on_path
  write_files
  link_cu_refresh
  merge_settings
  printf '%s\n' "$VERSION" > "$STATE_DIR/installed-version"

  echo "✅ Installed claude-statusline $VERSION"
  echo "   - Status line: restart Claude Code and it appears at the bottom"
  echo "   - Refresh usage now: cu-refresh in a terminal, /refresh inside Claude Code"
  echo "   - Backup: $SETTINGS.bak.*"
}

main "$@"
