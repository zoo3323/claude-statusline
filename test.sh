#!/bin/bash
# Regression tests. Runs the scripts in src/ against a throwaway $HOME with curl
# stubbed out, and checks what the status line draws, what it saves for the
# other sessions, and when the refresh scripts go to the network.
#
#   ./test.sh
cd "$(dirname "$0")" || exit 1

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
SCRIPTS="$HOME/.claude/scripts"
STATE="$HOME/.claude/codex-status"
LOGS="$HOME/.codex/sessions/2026/01/01"
mkdir -p "$SCRIPTS" "$STATE" "$LOGS" "$HOME/.local/bin"
cp src/*.sh "$SCRIPTS/"
chmod +x "$SCRIPTS"/*.sh

# Stand-ins for the network and the Keychain. curl logs the URL it was asked
# for and answers with $HOME/response, which carries both endpoints' shapes.
cat > "$HOME/.local/bin/curl" <<'EOF'
#!/bin/bash
for url; do :; done
echo "$url" >> "$HOME/curl.log"
cat "$HOME/response"
EOF
printf '#!/bin/bash\nexit 1\n' > "$HOME/.local/bin/security"
chmod +x "$HOME/.local/bin/curl" "$HOME/.local/bin/security"
echo '{"claudeAiOauth":{"accessToken":"test","expiresAt":0}}' > "$HOME/.claude/.credentials.json"
echo '{"tokens":{"access_token":"test","account_id":"test"}}' > "$HOME/.codex/auth.json"

now=$(date +%s)
soon=$((now + 7200))    # a 5-hour window that is still open
week=$((now + 400000))  # a weekly window that is still open
gone=$((now - 3600))    # a window that has already reset

payload() { # $1=session  $2 $3=5-hour used/reset  $4 $5=weekly used/reset  ("-" = no such window)
  jq -cn --arg s "$1" --arg t "$HOME/$1.jsonl" --arg u5 "$2" --arg r5 "$3" --arg u7 "$4" --arg r7 "$5" '
    def window($u; $r): if $u == "-" then null else {used_percentage: ($u | tonumber), resets_at: ($r | tonumber)} end;
    {session_id: $s, transcript_path: $t, cwd: "/tmp/proj", model: {display_name: "Opus 5.5"},
     rate_limits: ({five_hour: window($u5; $r5), seven_day: window($u7; $r7)} | with_entries(select(.value != null)))}'
}
render() { # stdin: payload -> the line, colour codes stripped
  touch "$STATE/usage.last"   # keeps the background poll out of it
  "$SCRIPTS/statusline-codex.sh" | sed -E $'s/\x1b\\[[0-9;]*m//g'
}
poll() { # $1 $2=5-hour used/reset  $3 $4=weekly used/reset -> the cache a poll leaves behind
  printf '{"fetched_at":%s,"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}\n' \
    "$now" "$1" "$2" "$3" "$4" > "$STATE/claude-usage.json"
}
saved() { # "session 5-hour% weekly%" of the payload kept for the other sessions
  jq -r '[.session_id, .rate_limits.five_hour.used_percentage, .rate_limits.seven_day.used_percentage]
         | map(tostring) | join(" ")' "$STATE/claude-last-input.json" 2>/dev/null
}
iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%S; }
at() { local year=$1; shift; touch -t "${year}01010000" "$@"; }       # give files an old date
untouched() { [ -n "$(find "$1" -mmin +1440 2>/dev/null)" ]; }         # …and see whether they kept it
fetched() { grep -q "$1" "$HOME/curl.log" 2>/dev/null; }
reset_state() { rm -f "$STATE"/* "$LOGS"/* "$HOME"/*.jsonl "$HOME/curl.log"; }

pass=0; fail=0
check() { # $1=what is expected, the rest=a command that must succeed
  local what=$1; shift
  if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $what"; fi
}
is() { [ "$1" = "$2" ]; }
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
lacks() { ! has "$@"; }
not() { ! "$@"; }

# --- what the status line saves for the other sessions -----------------------
reset_state
out=$(payload a 6 "$soon" 34 "$week" | render)
check "draws the gauge from its own payload"                 has "$out" "claude ▕▆▆▆▆▆▆▆▆▆▆▆▆▆░▏94%"
check "saves a payload that carries news"                    is "$(saved)" "a 6 34"

at 2020 "$STATE/claude-last-input.json"
payload a 6 "$soon" 34 "$week" | render >/dev/null
check "an idle re-render leaves the saved payload alone"     untouched "$STATE/claude-last-input.json"

out=$(payload b 2 "$soon" 30 "$week" | render)
check "a session that is behind does not overwrite it"       is "$(saved)" "a 6 34"
check "… nor touch the file"                                 untouched "$STATE/claude-last-input.json"
check "… and draws the saved reading instead of its own"     has "$out" "94%"

payload b 9 "$soon" 34 "$week" | render >/dev/null
check "the 5-hour reading breaks a weekly tie"               is "$(saved)" "b 9 34"

payload c - - 40 "$week" | render >/dev/null                 # ahead in weekly, no 5-hour window
check "the weekly reading decides"                           is "$(saved)" "c null 40"
at 2020 "$STATE/claude-last-input.json"
payload b 9 "$soon" 34 "$week" | render >/dev/null           # ahead in 5-hour only
check "… so two sessions cannot keep overwriting each other" untouched "$STATE/claude-last-input.json"

payload d 90 "$gone" 40 "$week" | render >/dev/null
payload e 1 "$soon" 40 "$week" | render >/dev/null
check "a new window replaces a spent one"                    is "$(saved)" "e 1 40"

# --- which reading it draws ---------------------------------------------------
reset_state
out=$(payload a 80 "$gone" 20 "$week" | render)
check "a window past its reset starts over"                  has "$out" "▏100%"

# The usage endpoint and Claude Code can disagree on the reset time by a second.
reset_state
poll 7 "$((soon - 1))" 35 "$((week - 1))"
out=$(payload a - - 17 "$week" | render)
check "a poll one second off is still the same window"       has "$out" "▆░▏93%"
check "… so its weekly reading beats the stale payload's"    lacks "$out" "▇"

# Usage can also drop (limits reset early, another account). The poll is the
# only source with a known time, so readings older than it step aside.
reset_state
payload a 60 "$soon" 80 "$week" | render >/dev/null
: > "$HOME/a.jsonl"; : > "$HOME/b.jsonl"
at 2020 "$STATE/claude-last-input.json" "$HOME/a.jsonl"      # nothing from Claude Code since…
poll 5 "$soon" 10 "$week"; at 2021 "$STATE/claude-usage.json"   # …and then a poll that says less
out=$(payload a 60 "$soon" 80 "$week" | render)
check "an idle session follows a poll that says less"        has "$out" "▏95%"
out=$(payload b 6 "$soon" 10 "$week" | render)               # b has been busy since that poll
check "a session busy since the poll keeps its own reading"  has "$out" "▏94%"

# --- when the refresh scripts go to the network ------------------------------
reset_state
cat > "$HOME/response" <<EOF
{"five_hour": {"utilization": 8.0, "resets_at": "$(iso $((soon - 1))).781902+00:00"},
 "seven_day": {"utilization": 35.9, "resets_at": "$(iso "$week")Z"},
 "rate_limit": {"primary_window": {"used_percent": 18, "reset_at": $week}, "secondary_window": null}}
EOF

payload a 6 "$soon" 34 "$week" | render >/dev/null           # Claude Code reported usage just now
"$SCRIPTS/claude-usage-refresh.sh" 300
check "background: no poll while Claude Code is reporting"   not fetched anthropic
"$SCRIPTS/claude-usage-refresh.sh"
check "manual: polls regardless"                             fetched anthropic
check "… and rounds the reset to the second Claude Code uses" \
  is "$(jq -c '[.five_hour.used_percentage, .five_hour.resets_at, .seven_day.used_percentage, .seven_day.resets_at]' "$STATE/claude-usage.json")" "[8,$soon,35,$week]"
rm -f "$HOME/curl.log"
"$SCRIPTS/claude-usage-refresh.sh"
check "… but not twice within a minute"                      not fetched anthropic
at 2020 "$STATE/claude-last-input.json" "$STATE/claude-usage.json"
"$SCRIPTS/claude-usage-refresh.sh" 300
check "background: polls once the numbers stop moving"       fetched anthropic

rm -f "$HOME/curl.log"
echo '{"payload":{"rate_limits":{"primary":{"used_percent":25,"resets_at":'"$week"'}}}}' > "$LOGS/rollout-1.jsonl"
"$SCRIPTS/codex-usage-refresh.sh" 300
check "codex background: no poll right after a codex call"   not fetched chatgpt
"$SCRIPTS/codex-usage-refresh.sh"
check "codex manual: polls regardless"                       fetched chatgpt
out=$(payload a 6 "$soon" 34 "$week" | render)
check "the codex gauge is drawn from the poll"               has "$out" "codex ▕███████████░░░▏82%"

# --- the status line's own trigger -------------------------------------------
reset_state
: > "$STATE/usage.last"; at 2020 "$STATE/usage.last"
payload a - - - - | "$SCRIPTS/statusline-codex.sh" >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  fetched anthropic && break
  sleep 0.2
done
check "a mark older than 5 minutes kicks off the codex poll" fetched chatgpt
check "… and the claude poll"                                fetched anthropic
check "… and is reset so the next render does not"           not untouched "$STATE/usage.last"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
