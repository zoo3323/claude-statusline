#!/bin/bash
# Regression tests. Runs the scripts in src/ against a throwaway $HOME with curl
# stubbed out, and checks what the status line draws, how it fits a narrow
# terminal, when it replays the previous line instead of rendering, what it
# saves for the other sessions, and when the refresh scripts go to the network.
# The last part runs the generated installer, with its options, in homes of its own.
#
#   ./test.sh
cd "$(dirname "$0")" || exit 1

T=$(mktemp -d)
# A process to stand in for a live Claude Code: session status files are only believed when their
# pid is alive and, where /proc can tell, is called claude.
(exec -a claude sleep 900) & CLAUDE_PID=$!
disown
trap 'kill "$CLAUDE_PID" 2>/dev/null; rm -rf "$T"' EXIT
export HOME="$T/home"
unset COLUMNS         # no width: gauges at their default, nothing cut
unset CLAUDE_EFFORT   # the fallback for a payload without an effort level
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

# jq, counted: a replayed line must not have needed it.
mkdir -p "$T/bin"
printf '#!/bin/bash\necho run >> "%s/jq.log"\nexec "%s" "$@"\n' "$T" "$(command -v jq)" > "$T/bin/jq"
chmod +x "$T/bin/jq"
PATH="$T/bin:$PATH"
jq_runs() { local n; n=$(wc -l < "$T/jq.log" 2>/dev/null); echo $((n + 0)); }
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
reset_state() {
  rm -f "$STATE"/* "$LOGS"/* "$HOME"/*.jsonl "$HOME/curl.log"
  rm -rf "$HOME/.claude/sessions" "$HOME/.claude/tasks"
}
raw() { # stdin: payload -> the line as it is written, colour codes and all
  touch "$STATE/usage.last"
  "$SCRIPTS/statusline-codex.sh"
}
status() { # $1=session $2=busy|idle [$3=pid] -> the only status file there is: the one Claude Code
           # keeps for that session, named after its pid (default: the stand-in above)
  rm -rf "$HOME/.claude/sessions"; mkdir -p "$HOME/.claude/sessions"
  printf '{"pid":%s,"sessionId":"%s","status":"%s"}' "${3:-$CLAUDE_PID}" "$1" "$2" > "$HOME/.claude/sessions/${3:-$CLAUDE_PID}.json"
}

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
check "draws the gauge from its own payload"                 has "$out" "claude ▕▆▆▆▆▆▆▆▆▆░▏94%"
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

: > "$STATE/render.gone"; at 2020 "$STATE/render.gone"
: > "$STATE/render.live"
"$SCRIPTS/usage-refresh.sh" 300
check "the refresh sweeps the replay files of dead sessions" not test -e "$STATE/render.gone"
check "… and leaves those of live ones"                      test -e "$STATE/render.live"

out=$(payload a 6 "$soon" 34 "$week" | render)
check "the codex gauge is drawn from the poll"               has "$out" "codex ▕████████░░▏82%"

# --- the labels: words, or icons with the marker file ------------------------
ctx() { # $1=context used% -> the line
  payload a 6 "$soon" 34 "$week" | jq -c --argjson used "$1" '.context_window.used_percentage = $used' | render
}
check "the context gauge fills up as it is used"             has "$(ctx 12)" "ctx ▕█░░░░░░░░░▏12%"
check "… empty when nothing is used"                         has "$(ctx 0)" "ctx ▕░░░░░░░░░░▏0%"
check "… half way at 50%"                                    has "$(ctx 50)" "ctx ▕█████░░░░░▏50%"
check "… not drawn full until it is"                         has "$(ctx 97)" "ctx ▕█████████░▏97%"
check "… full at 100%"                                       has "$(ctx 100)" "ctx ▕██████████▏100%"
check "… and no wider past it"                               has "$(ctx 140)" "ctx ▕██████████▏140%"

: > "$STATE/icons"
out=$(ctx 12)
check "with the marker file the codex label is the logo"     has "$out" $'\xee\xb2\x81 ▕████████░░▏82%'
check "… and so is the claude one"                           has "$out" $'\xee\xb2\x82 ▕▆'
check "… with the word codex gone"                           lacks "$out" "codex"
check "… and the word claude"                                lacks "$out" "claude"
check "… and ctx is the speech bubble"                       has "$out" $'\xf3\xb0\x8d\xaa ▕█░░░░░░░░░▏12%'
check "… with the word ctx gone"                             lacks "$out" "ctx"
rm -f "$STATE/icons"
check "without it the words are back"                        has "$(ctx 12)" "codex ▕"

# --- fitting the terminal ----------------------------------------------------
# (codex has 82% left and claude 94%, as above)
wide() { COLUMNS=$1 ctx 12; }
check "a wide terminal gets wider gauges"                    has "$(wide 200)" "codex ▕███████████░░░▏82%"
check "a narrower one narrower gauges"                       has "$(wide 100)" "codex ▕███████░▏82%"
out=$(wide 80)
check "too narrow for gauges: only the numbers"              has "$out" "claude 92% ↻"
check "… the context one too"                                has "$out" "ctx 12%"
check "… and no gauge at all"                                lacks "$out" "▕"
check "narrower still: the countdowns go"                    has "$(wide 60)" "codex 82% · claude 92% · ctx 12%"

mkdir -p "$HOME/.claude/tasks/a"
echo '{"status":"completed","subject":"done before"}' > "$HOME/.claude/tasks/a/1.json"
echo '{"status":"in_progress","subject":"s","activeForm":"Reticulating the splines"}' > "$HOME/.claude/tasks/a/2.json"
check "the task in progress closes the line"                 has "$(ctx 12)" "▏12% · ▸ Reticulating the splines"
out=$(wide 140)
check "with room to spare it leaves the gauges alone"        has "$out" "codex ▕██████████░░▏82%"
check "…"                                                    has "$out" "▸ Reticulating the splines"
out=$(wide 120)
check "short of room the gauges give way to it"              has "$out" "codex ▕█████░▏82%"
check "…"                                                    has "$out" "▸ Reticulating the splines"
out=$(wide 110)
check "… but not below their minimum"                        has "$out" "codex ▕████░▏82%"
check "… then the task is cut instead"                       has "$out" "▸ Reticulating the"
check "…"                                                    lacks "$out" "splines"
check "and left out when hardly any of it would fit"         lacks "$(wide 70)" "▸"

# --- a gauge in use ----------------------------------------------------------
reset_state
printf '%s\n' '{"type":"event_msg","payload":{"type":"task_started"}}' \
  '{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":25,"resets_at":'"$week"'}}}}' \
  > "$LOGS/rollout-1.jsonl"
lit() { # $1=part of a raw line -> success when a light is on it: a shade that is not one of the two themes
  local s=${1//"[38;2;16;163;127m"/}; s=${s//"[38;2;217;119;87m"/}
  has "$s" "[38;2;"
}
# Where a running light is follows the session's clock: 7 seconds in, it is on cell 6, having come in
# on the right. Every draw differs in its context figure, so that none of them is a replay of the one
# before.
draws=0
draw() { # [$1=the session's clock in ms]
  draws=$((draws + 1))
  out=$(payload a 6 "$soon" 34 "$week" | jq -c --argjson ms "${1:-7000}" --argjson n "$draws" \
    '.cost.total_duration_ms = $ms | .context_window.used_percentage = $n' | raw)
  codex_part=${out%%claude*}; claude_part=${out##*claude}; claude_part=${claude_part%%ctx*}
}
part() { case "$1" in codex) printf '%s' "$codex_part" ;; *) printf '%s' "$claude_part" ;; esac; }
still() { # $1=codex|claude -> success when that gauge looks the same from one second to the next
  local before
  draw 7000; before=$(part "$1")
  draw 8000; [ "$(part "$1")" = "$before" ]
}
draw
check "the codex gauge is drawn from the session log"        has "$(sed -E $'s/\x1b\\[[0-9;]*m//g' <<< "$out")" "codex ▕████████░░▏75%"
check "a running codex task makes the codex gauge glow"      lit "$codex_part"
check "… a glow that does not move"                          still codex
check "… and leaves the claude gauge dark"                   not lit "$claude_part"
status a idle; draw
check "an idle session does not light the claude gauge"      not lit "$claude_part"
status b busy; draw
check "another session at work makes it glow"                lit "$claude_part"
check "… and nothing moves in this one"                      still claude
status b busy 99999999; draw
check "… unless it is gone and only left its file behind"    not lit "$claude_part"
if [ -r "/proc/$$/cmdline" ]; then   # only Linux can tell whose pid it is
  status b busy $$; draw
  check "… or its pid belongs to something else by now"      not lit "$claude_part"
fi
status a busy; draw
check "this session at work: a light on the claude gauge"    lit "$claude_part"
seen=$claude_part
check "… that runs along it"                                 not still claude
check "… as does the one on the codex gauge"                 not still codex
draw 17000
check "… and comes round every ten seconds"                  is "$claude_part" "$seen"
echo '{"type":"event_msg","payload":{"type":"task_complete"}}' >> "$LOGS/rollout-1.jsonl"
draw
check "the codex light goes out when the task is done"       not lit "$codex_part"
check "… while claude's stays on"                            lit "$claude_part"

# --- replaying the previous line ---------------------------------------------
reset_state
status a idle
tick() { # $1=the session's clock in ms  $2=context used% -> payload (no 5-hour window: nothing counts down)
  payload a - - 34 "$week" | jq -c --argjson ms "$1" --argjson used "${2:-12}" \
    '.cost.total_duration_ms = $ms | .context_window.used_percentage = $used'
}
settle() { # $1=clock: render, with the usage files older than the render
  at 2020 "$STATE"/*.json 2>/dev/null
  tick "$1" "$2" | raw
}
replayed() { # $1=payload -> success when drawing it took no jq; the line is left in $line
  local before; before=$(jq_runs)
  line=$(raw <<< "$1")
  [ "$(jq_runs)" = "$before" ]
}
tick 1000 | raw >/dev/null
first=$(settle 1000)
p=$(tick 3000)
check "an idle session's next render is a replay"            replayed "$p"
check "… of the very same line"                              is "$line" "$first"
p=$(tick 70000)
check "… for a minute at most"                               not replayed "$p"
p=$(tick 71000 13)
check "not when the payload says something new"              not replayed "$p"
check "… which is then drawn"                                has "$line" "13%"
p=$(tick 72000 13)
check "(and that one is replayed in turn)"                   replayed "$p"
resized() { COLUMNS=90 replayed "$1"; }
check "not when the terminal changed width"                  not resized "$p"
settle 72000 13 >/dev/null
: > "$STATE/claude-usage.json"
check "not when a usage file was written since"              not replayed "$p"
settle 72000 13 >/dev/null
: > "$STATE/icons"
check "not when the icons were switched on"                  not replayed "$p"
rm -f "$STATE/icons"; settle 72000 13 >/dev/null
status b busy
check "a session at work somewhere does not end the replay"  replayed "$p"

p=$(payload a 6 "$soon" 34 "$week" | jq -c '.cost.total_duration_ms = 5000')   # with a claude gauge
raw <<< "$p" >/dev/null; at 2020 "$STATE"/*.json; raw <<< "$p" >/dev/null
check "… the glow is put on the replayed line"               replayed "$p"
check "…"                                                    lit "$line"
status a busy
check "… or the running light, when it is this session"      replayed "$p"
check "…"                                                    lit "$line"
status a idle
check "… and taken off it again"                             replayed "$p"
check "…"                                                    not lit "$line"

# --- several sessions at once ------------------------------------------------
# (they share the saved payload and the codex log cache; a temporary file under one name for all of
# them used to be renamed away from under whoever came second)
reset_state
echo '{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":25,"resets_at":'"$week"'}}}}' > "$LOGS/rollout-1.jsonl"
touch "$STATE/usage.last"
renders=()
for n in 1 2 3 4 5 6 7 8; do
  payload "s$n" "$n" "$soon" 34 "$week" | "$SCRIPTS/statusline-codex.sh" > "$T/par.$n.out" 2> "$T/par.$n.err" &
  renders[${#renders[@]}]=$!
done
wait "${renders[@]}"   # not a bare wait: the stand-in for Claude Code is still running
check "renders running side by side do not trip each other" is "$(cat "$T"/par.*.err)" ""
check "… each draws its line"                                is "$(grep -l 'codex' "$T"/par.*.out | wc -l | tr -d ' ')" "8"
check "… the saved payload is one of theirs, whole"          has "$(jq -r '.session_id' "$STATE/claude-last-input.json" 2>/dev/null)" "s"
check "… and no temporary file is left behind"               is "$(find "$STATE" -name '*tmp*' | wc -l | tr -d ' ')" "0"

# --- choosing what is shown --------------------------------------------------
reset_state
printf '{"rate_limit":{"primary_window":{"used_percent":18,"reset_at":%s}}}' "$week" > "$STATE/codex-usage.json"
conf() { printf '%s\n' "$@" > "$STATE/config"; }
shows() { payload a 6 "$soon" 34 "$week" | jq -c '.context_window.used_percentage = 12 | .effort.level = "max"' | render; }
out=$(shows)
check "without a config everything is shown"                 has "$out" "proj · Opus 5.5 (max) · codex ▕████████░░▏82% ↻"
check "…"                                                    has "$out" "· ctx ▕█░░░░░░░░░▏12%"
conf "show=folder ctx"
check "the config names the segments to show"                is "$(shows)" "proj · ctx ▕█░░░░░░░░░▏12%"
conf "show=claude"
out=$(shows)
check "a single segment stands without a separator"          is "${out%%▕*}" "claude "
check "…"                                                    lacks "$out" " · "
conf "show=folder model codex claude ctx task" "countdown=off"
out=$(shows)
check "countdown=off drops the times until a reset"          lacks "$out" "↻"
check "… and nothing else"                                   has "$out" "codex ▕████████░░▏82% · claude ▕"
conf "icons=on"
check "icons=on does what the marker file of 1.2 did"        has "$(shows)" $'\xee\xb2\x82 ▕'
status a busy
conf "light=off"
check "light=off: no light, whoever is at work"              not lit "$(payload a 6 "$soon" 34 "$week" | raw)"
rm -f "$STATE/config"; rm -rf "$HOME/.claude/sessions"
tick 1000 >/dev/null; settle 1000 >/dev/null; p=$(tick 2000)
check "(a line that is being replayed …)"                    replayed "$p"
conf "show=folder"
check "… is drawn anew once the config changes"              not replayed "$p"
check "…"                                                    is "$(sed -E $'s/\x1b\\[[0-9;]*m//g' <<< "$line")" "proj"
rm -f "$STATE/config"

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
for _ in 1 2 3 4 5 6 7 8 9 10; do   # let the poll finish writing before the directory goes
  [ -f "$STATE/claude-usage.json" ] && break
  sleep 0.2
done

# --- the installer and its options -------------------------------------------
I="$PWD/install-claude-statusline.sh"
quiet() { "$@" > /dev/null 2>&1; }
check "the generated installer is up to date"                quiet ./build.sh --check
install_in() { local h=$1; shift; ( export HOME="$T/$h"; mkdir -p "$HOME/.claude"; bash "$I" "$@" ) > "$T/$h.out" 2>&1; }
conf_of() { tr '\n' '|' < "$T/$1/.claude/codex-status/config" 2>/dev/null; }

install_in h1
check "a plain install sets the status line"                 has "$(jq -r '.statusLine.command' "$T/h1/.claude/settings.json")" "/.claude/scripts/statusline-codex.sh"
check "… brings the stand-alone /refresh skill"              test -f "$T/h1/.claude/skills/refresh/SKILL.md"
check "… and writes no config: there is nothing to record"   not test -e "$T/h1/.claude/codex-status/config"

install_in h2 --plugin --show "folder claude ctx" --countdown off --icons on --light off
check "options record what to show"                          is "$(conf_of h2)" "show=folder claude ctx|countdown=off|icons=on|light=off|"
check "the plugin leaves the stand-alone skill out"          not test -e "$T/h2/.claude/skills/refresh"
install_in h2 --plugin --icons off
check "an option left out keeps its value"                   is "$(conf_of h2)" "show=folder claude ctx|countdown=off|icons=off|light=off|"

install_in h3 --show "folder weather"; rc=$?
check "an unknown segment is refused"                        is "$rc" "2"
check "… before anything is installed"                       not test -e "$T/h3/.claude/scripts"

mkdir -p "$T/h4/.claude/codex-status"; : > "$T/h4/.claude/codex-status/icons"
install_in h4
check "the icons marker of 1.2 becomes a config line"        is "$(conf_of h4)" "show=folder model codex claude ctx task|countdown=on|icons=on|light=on|"
check "… and is gone"                                        not test -e "$T/h4/.claude/codex-status/icons"

install_in h5 --plugin --sync
check "--sync sets nothing up where nothing was"             not test -e "$T/h5/.claude/scripts"

echo 0.0.1 > "$T/h2/.claude/codex-status/installed-version"
echo "# an older version" > "$T/h2/.claude/scripts/statusline-codex.sh"
jq 'del(.statusLine)' "$T/h2/.claude/settings.json" > "$T/h2.settings" && mv "$T/h2.settings" "$T/h2/.claude/settings.json"
install_in h2 --plugin --sync
check "--sync brings an older installation up to date"       cmp -s src/statusline-codex.sh "$T/h2/.claude/scripts/statusline-codex.sh"
check "… says so in installed-version"                       is "$(cat "$T/h2/.claude/codex-status/installed-version")" "$(cat VERSION)"
check "… keeps the choices"                                  is "$(conf_of h2)" "show=folder claude ctx|countdown=off|icons=off|light=off|"
check "… and leaves settings.json alone"                     is "$(jq -r '.statusLine // "none"' "$T/h2/.claude/settings.json")" "none"
echo "# edited by hand" > "$T/h2/.claude/scripts/statusline-codex.sh"
install_in h2 --plugin --sync
check "--sync does nothing when the version is the same"     is "$(cat "$T/h2/.claude/scripts/statusline-codex.sh")" "# edited by hand"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
