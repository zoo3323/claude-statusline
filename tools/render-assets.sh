#!/bin/bash
# Regenerates the images in assets/ from what the status line really draws: the
# scripts in src/ are run against a throwaway home with made-up numbers, and
# their output is drawn by ansi2png.py.
#
#   tools/render-assets.sh
#
# Needs uv (for Pillow) and two fonts, a monospace one and one with the Nerd
# Fonts 3.5 glyphs; point TEXT_FONT and ICON_FONT at yours.
set -e
cd "$(dirname "$0")/.."
TEXT_FONT=${TEXT_FONT:-$HOME/Library/Fonts/D2Coding-Ver1.3.2-20180524.ttc}
ICON_FONT=${ICON_FONT:-$HOME/Library/Fonts/SymbolsNerdFont-Regular.ttf}

T=$(mktemp -d)
(exec -a claude sleep 600) & CLAUDE_PID=$!   # a live "Claude Code" for the session status files to name
disown
trap 'kill "$CLAUDE_PID" 2>/dev/null; rm -rf "$T"' EXIT
export HOME="$T/home"
unset CLAUDE_EFFORT COLUMNS
STATE="$HOME/.claude/codex-status"
LOGS="$HOME/.codex/sessions/2026/01/01"
mkdir -p "$STATE" "$LOGS" "$HOME/.claude/scripts" "$HOME/.claude/sessions" "$HOME/.claude/tasks/demo"
printf '#!/bin/bash\nexit 0\n' > "$HOME/.claude/scripts/usage-refresh.sh"; chmod +x "$HOME/.claude/scripts/usage-refresh.sh"
now=$(date +%s)

conf() { printf '%s\n' "$@" > "$STATE/config"; }                      # what to show
codex() { # $1=5-hour used% $2=weekly used% [$3=task running]
  rm -f "$STATE/codex-logs.cache" "$LOGS"/*
  printf '%s\n' ${3:+'{"type":"event_msg","payload":{"type":"task_started"}}'} \
    '{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":'"$1"',"resets_at":'$((now + 525000))'},"secondary":{"used_percent":'"$2"'}}}}' \
    > "$LOGS/rollout-1.jsonl"
}
session() { # $1=whose (demo: this one, other: another)  $2=busy|idle
  printf '{"pid":%s,"sessionId":"%s","status":"%s"}' "$CLAUDE_PID" "$1" "$2" > "$HOME/.claude/sessions/$CLAUDE_PID.json"
}
task() { rm -f "$HOME/.claude/tasks/demo"/*; [ -n "$1" ] && printf '{"status":"in_progress","activeForm":"%s"}' "$1" > "$HOME/.claude/tasks/demo/1.json"; return 0; }
draw() { # $1=label $2=columns $3=5-hour used% $4=weekly used% $5=context% [$6=session clock, s]
  touch "$STATE/usage.last"
  printf '%s\t' "$1"
  jq -cn --argjson u5 "$3" --argjson u7 "$4" --argjson ctx "$5" --argjson ms "$(( ${6:-0} * 1000 ))" \
        --argjson r5 $((now + 8010)) --argjson r7 $((now + 400000)) '
    {session_id: "demo", cwd: "/work/my-app", model: {display_name: "Opus 5.5"}, effort: {level: "high"},
     cost: {total_duration_ms: $ms}, context_window: {used_percentage: $ctx},
     rate_limits: {five_hour: {used_percentage: $u5, resets_at: $r5}, seven_day: {used_percentage: $u7, resets_at: $r7}}}' \
    | COLUMNS=$2 /bin/bash src/statusline-codex.sh
  echo
  rm -f "$STATE"/render.* "$STATE/claude-last-input.json"   # every draw starts from its own numbers
}
png() { uv run --quiet --with pillow python tools/ansi2png.py --out "assets/$1" --text-font "$TEXT_FONT" --icon-font "$ICON_FONT"; }

# hero: a session at work, a codex task running — ten seconds of it
conf "icons=on"; codex 7 20 running; session demo busy; task "Running tests"
for t in 0 1 2 3 4 5 6 7 8 9; do draw "" 112 41 30 42 "$t"; echo "---"; done | png hero.png

# how much is left: plenty, under 30%, under 10%
task ""; session demo idle
{ codex 7 20;  draw "" 92 18 25 18
  codex 72 55; draw "" 92 75 80 74
  codex 31 60; draw "" 92 94 91 93; } | png levels.png

# in use: nobody, another session, this one
{ codex 7 20;         session demo idle;  draw "1" 92 41 30 42
  codex 7 20 running; session other busy; draw "2" 92 41 30 42
  codex 7 20 running; session demo busy;  draw "3" 92 41 30 42 8; } | png in-use.png

# the same line in terminals of different widths
codex 7 20; session demo idle
for c in 150 104 88 72 52; do draw "$c" "$c" 41 30 42; done | png widths.png

# what to show
{ conf "icons=off";                           draw "icons=off" 96 41 30 42
  conf "icons=on";                            draw "icons=on" 96 41 30 42
  conf "icons=on" "countdown=off";            draw "countdown=off" 96 41 30 42
  conf "icons=on" "show=folder claude ctx";   draw "show=folder claude ctx" 96 41 30 42; } | png choose.png
