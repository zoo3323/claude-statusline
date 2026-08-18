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
