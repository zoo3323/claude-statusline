#!/bin/bash
# Installer for the Claude Code status line.
#   curl -fsSL https://raw.githubusercontent.com/zoo3323/usage-statusline/main/install.sh | bash
# Options go after `bash -s --`; see usage() below. The plugin's setup skill runs
# this same file.
#
# GENERATED FILE — do not edit. The scripts it writes live in src/; change them
# there and run ./build.sh.
#
# Everything is defined as functions and only run by the `main "$@"` on the last
# line. A download cut short therefore installs nothing at all instead of
# leaving a truncated script behind.
set -e

VERSION="1.6.2"

CLAUDE_DIR="$HOME/.claude"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
STATE_DIR="$CLAUDE_DIR/codex-status"
SKILLS_DIR="$CLAUDE_DIR/skills/refresh"
SETTINGS="$CLAUDE_DIR/settings.json"
LOCAL_BIN="$HOME/.local/bin"

usage() {
  cat <<'EOF'
Usage: install.sh [options]

What the status line shows (kept from the last time when left out):
  --show "<segments>"   any of: folder model codex claude ctx
  --countdown on|off    the time until a usage window resets
  --light on|off        the light and the glow on a quota that is in use

  --plugin              run from the Claude Code plugin: leave the stand-alone
                        /refresh skill out, the plugin brings its own
  --sync                only bring an existing installation up to this version;
                        installs nothing new and leaves settings.json alone
EOF
}

PLUGIN=""; SYNC=""; OPT_SHOW=""; OPT_COUNTDOWN=""; OPT_ICONS=""; OPT_LIGHT=""
parse_args() {
  local s
  while [ $# -gt 0 ]; do
    case "$1" in
      --show)
        OPT_SHOW=$2
        [ -n "$OPT_SHOW" ] || { echo "❌ --show needs at least one segment"; return 2; }
        for s in $OPT_SHOW; do
          case "$s" in folder|model|codex|claude|ctx) ;;
            *) echo "❌ --show: unknown segment '$s'"; return 2 ;;
          esac
        done
        shift ;;
      --countdown|--icons|--light)
        case "$2" in on|off) ;; *) echo "❌ $1 takes on or off"; return 2 ;; esac
        case "$1" in --countdown) OPT_COUNTDOWN=$2 ;; --icons) OPT_ICONS=$2 ;; --light) OPT_LIGHT=$2 ;; esac
        shift ;;
      --plugin) PLUGIN=1 ;;
      --sync)   SYNC=1 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "❌ Unknown option: $1"; usage; return 2 ;;
    esac
    shift
  done
}

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
#   folder | model (effort) | codex usage | claude usage | context
#
# Claude Code runs this every second in every open session, visible or not, and
# nothing stays in memory between runs — what a session costs is what one run
# does. Two things keep that small:
#   - while nothing it shows has changed, a session replays the line it drew
#     last (below) and spawns nothing; only the lights are drawn afresh
#   - a full render spawns the clock, one stat and one jq, plus ls/grep/awk
#     when the codex logs moved; the rest is shell builtins, no subshells
IFS= read -r -d '' input   # all of stdin
STATE_DIR="$HOME/.claude/codex-status"
CONFIG="$STATE_DIR/config"   # what the user chose to show, see "What to draw"
icons=0; [ -e "$STATE_DIR/icons" ] && icons=1

# Shared palette — explicit 256-colour greys instead of dim (\033[2m), which
# some terminals render almost invisibly.
ESC=$'\033'
RESET="${ESC}[0m"
GRAY="${ESC}[38;5;245m"    # separators, secondary info (reset time)
RAIL="${ESC}[38;5;245m"    # gauge end rails
EMPTY="${ESC}[38;5;240m"   # empty gauge cells (a touch darker than the fill)
TRACK="${ESC}[48;5;238m"   # the dark background of a gauge
WARN="${ESC}[38;5;214m"    # 70% used and up
CRIT="${ESC}[38;5;196m"    # 90% used and up

# --- Gauges in use -------------------------------------------------------------
# A gauge whose quota is being spent right now shows it — the quota is the
# account's, whichever session spends it:
#   run   this session is at work: a light runs along the gauge
#   glow  only something else is spending it: the end of the bar glows, still
# Nothing moves in a session that is not at work. A moving light is terminal
# output every second, and connections that keep the output for replay (Eternal
# Terminal keeps the last 64 MiB per connection in the server's memory) fill up
# on it; a session at work writes to the terminal all the time anyway, a spinner
# alone is tens of kilobytes a second, an idle one would otherwise write nothing.
#
# Claude's is in use while any session on this machine is at work. Claude Code
# keeps a status file per live session, named after its pid. That is not a
# documented interface, so anything unexpected simply means "not in use"; a file
# left behind by a session that died is told by its pid being gone, or belonging
# to something else by now.
claude_use() { # -> claude_mode
  local f st pid arg ours
  claude_mode=""
  for f in "$HOME"/.claude/sessions/*.json; do
    [ -f "$f" ] || continue
    IFS= read -r st < "$f"
    case "$st" in *'"status":"busy"'*) ;; *) continue ;; esac
    pid=${f##*/}; pid=${pid%.json}
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$pid" 2>/dev/null || continue
    # A pid gets handed out again; where /proc tells, it has to be Claude Code's.
    if [ -r "/proc/$pid/cmdline" ]; then
      ours=""
      while IFS= read -r -d '' arg || [ -n "$arg" ]; do
        case "$arg" in *claude*) ours=1; break ;; esac
      done < "/proc/$pid/cmdline"
      [ -n "$ours" ] || continue
    fi
    case "$st" in *"\"sessionId\":\"$sid\""*) claude_mode=run; return ;; esac
    claude_mode=glow
  done
}
# Codex's is in use while a task runs in its newest session log; the full render
# works that out and leaves the verdict in this file, shared by all sessions.
LOG_CACHE="$STATE_DIR/codex-logs.cache"
codex_use() { # $1=the verdict -> codex_mode
  codex_mode=""
  [ "$1" = run ] || return
  codex_mode=glow; [ "$claude_mode" = run ] && codex_mode=run
}

# The track of a gauge: $1 cells of block $2 in colour $3, the rest empty, on a
# dark background with thin rails (▕ ▏) at both ends. $4 puts a light on it
# (empty: none) and $5 $6 $7 is the colour as r g b: the cells around the light's
# centre are lightened towards white, the centre the most, and never by much —
# it is a sheen, not a lamp. $4 is the cell it is centred on, or "tip" for the
# glow: the bar grows lighter towards its end, a little with every cell, so that
# it reads as a bar that is lit and not as a few cells of another colour.
#
# The light is as wide as the bar has room for: two cells to either side of the
# centre on a short bar, four on the longest. A cell is one flat colour, so the
# fall-off towards the edges is a staircase, and a light of the same five cells
# on a bar of fourteen was three hard steps in a small patch. More cells make
# more and lower steps; at two cells a side they are the 40, 24 and 10 percent
# the light was tuned to.
#
# The running light moves LIGHT_STEP cells to the left with every second; there
# is no moving it more often, Claude Code re-runs the status line once a second
# at the most. It comes in on the right and leaves on the left, and one passes
# any given cell every LIGHT_EVERY seconds: the next follows that many steps
# behind.
LIGHT_STEP=2
LIGHT_EVERY=10
LIGHT=40  # how much lighter, in percent towards white, the centre of the running light is
GLOW=35   # … and the end of a glowing bar
draw_track() { # -> track
  local cells=$1 block=$2 colour=$3 light=$4 round=$((LIGHT_EVERY * LIGHT_STEP)) i ch c d k r g b last="" s=""
  local n=$((bar_w / 4 + 2)) m   # the light reaches n-1 cells to either side of its centre
  for ((i=0; i<bar_w; i++)); do
    if [ "$i" -lt "$cells" ]; then ch=$block; c=$colour; r=$5; g=$6; b=$7
    else ch="░"; c=$EMPTY; r=88; g=88; b=88; fi
    if [ -n "$light" ]; then
      k=0
      if [ "$light" = tip ]; then
        [ "$i" -lt "$cells" ] && k=$((GLOW * (i + 1) / cells))
      else
        d=$(( (i - light + round) % round )); [ $((d * 2)) -gt "$round" ] && d=$((round - d))
        m=$((n - d)); [ "$m" -gt 0 ] && k=$((LIGHT * m * (7 * n + 3 * m) / (10 * n * n)))
      fi
      [ "$k" -gt 0 ] && c="${ESC}[38;2;$((r + (255 - r) * k / 100));$((g + (255 - g) * k / 100));$((b + (255 - b) * k / 100))m"
    fi
    [ "$c" = "$last" ] || { s="$s$c"; last=$c; }
    s="$s$ch"
  done
  track="${RAIL}▕${RESET}${TRACK}${s}${RESET}${RAIL}▏${RESET}"
}

# The line is kept in pieces so that the light can be put on it without working
# anything else out again: text, the codex track, text, the claude track, text.
# A track is its cell count, block, colour and that colour's r g b (k1_…, k2_…;
# no cell count: no track).
compose() { # $1=codex_mode $2=claude_mode -> line
  local round=$((LIGHT_EVERY * LIGHT_STEP)) at on
  at=$(( (round - clock_s % LIGHT_EVERY * LIGHT_STEP) % round ))
  line=$t0
  if [ -n "$k1_cells" ]; then
    on=""; case "$1" in run) on=$at ;; glow) on=tip ;; esac
    draw_track "$k1_cells" "$k1_block" "$k1_colour" "$on" "$k1_r" "$k1_g" "$k1_b"; line="$line$track"
  fi
  line="$line$t1"
  if [ -n "$k2_cells" ]; then
    on=""; case "$2" in run) on=$at ;; glow) on=tip ;; esac
    draw_track "$k2_cells" "$k2_block" "$k2_colour" "$on" "$k2_r" "$k2_g" "$k2_b"; line="$line$track"
  fi
  line="$line$t2"
}

# --- Replay --------------------------------------------------------------------
# The payload of a session in which nothing happens differs from the one before
# only in cost.total_duration_ms, the session's wall clock. So when the payload
# is the same apart from that clock, the terminal is as wide as it was, no usage
# file and no codex log was written since, and the clock has not reached the
# moment a drawn countdown changes, the line drawn last time still stands — and
# all there is left to do is to put the light on it. (That clock also spares
# asking for the time.)
#
# The payload is taken apart with regexes only: on a string this size the
# pattern operators of bash 3.2 (${var/…/}, ${var#*…}) take many milliseconds in
# a UTF-8 locale, a regex match a few hundredths of one.
re_sid='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_-]+)"'
re_dur='^(.*)"total_duration_ms"[[:space:]]*:[[:space:]]*([0-9]+)(.*)$'
sid=""; dur=""; key=""
[[ $input =~ $re_sid ]] && sid=${BASH_REMATCH[1]}
if [ -n "$sid" ] && [[ $input =~ $re_dur ]]; then
  dur=${BASH_REMATCH[2]}
  key="${BASH_REMATCH[1]}${BASH_REMATCH[3]}"; key=${key%$'\n'}
  case "$key" in *$'\n'*) key="" ;; esac   # the file below is line-based
fi
R_CACHE="$STATE_DIR/render.$sid"
if [ -n "$key" ] && [ -f "$R_CACHE" ]; then
  { IFS=' ' read -r c_cols c_dur c_ttl c_icons bar_w c_light
    IFS= read -r c_key; IFS= read -r c_out; IFS= read -r t0
    IFS= read -r k1_cells; IFS= read -r k1_block; IFS= read -r k1_colour
    IFS= read -r k1_r; IFS= read -r k1_g; IFS= read -r k1_b; IFS= read -r t1
    IFS= read -r k2_cells; IFS= read -r k2_block; IFS= read -r k2_colour
    IFS= read -r k2_r; IFS= read -r k2_g; IFS= read -r k2_b; IFS= read -r t2
    IFS= read -r c_end; } < "$R_CACHE" 2>/dev/null
  replay=""
  [ "$c_end" = end ] && [ "$c_key" = "$key" ] && [ "$c_cols" = "${COLUMNS:--}" ] \
    && [ "$c_icons" = "$icons" ] && replay=1
  case "$c_dur$c_ttl$bar_w" in ''|*[!0-9]*) replay="" ;; esac
  if [ -n "$replay" ]; then
    age=$((dur - c_dur))
    { [ "$age" -lt 0 ] || [ "$age" -ge "$c_ttl" ]; } && replay=""
  fi
  if [ -n "$replay" ]; then
    # "Not older" would miss a file written within the same second.
    for f in "$STATE_DIR/claude-usage.json" "$STATE_DIR/claude-last-input.json" "$STATE_DIR/codex-usage.json" "$CONFIG"; do
      [ -e "$f" ] && ! [ "$R_CACHE" -nt "$f" ] && { replay=""; break; }
    done
  fi
  codex_state=""
  if [ -n "$replay" ] && [ -f "$LOG_CACHE" ]; then
    { IFS= read -r _; IFS= read -r newest; IFS= read -r _; IFS= read -r _; IFS= read -r codex_state; } < "$LOG_CACHE"
    # While Codex works its log is written many times a second; a strict test
    # here would have every session render in full on every tick.
    [ -n "$newest" ] && [ "$newest" -nt "$LOG_CACHE" ] && replay=""
  fi
  if [ -n "$replay" ]; then
    if [ "$c_light" = on ]; then
      claude_use; codex_use "$codex_state"
      if [ -n "$codex_mode$claude_mode" ]; then
        clock_s=$((dur / 1000)); compose "$codex_mode" "$claude_mode"; c_out=$line
      fi
    fi
    printf '%s' "$c_out"
    exit 0
  fi
fi

# --- Full render ---------------------------------------------------------------
if [ "${BASH_VERSINFO[0]}" -ge 5 ]; then now_s=$EPOCHSECONDS; else now_s=$(date +%s); fi

# "mtime size name" for each file, in one stat. On macOS /usr/bin/stat is the
# BSD one whatever else is on PATH; anywhere else try GNU first, because there
# `stat -f` means something else entirely. Only pass files that exist: GNU stat
# fails on a missing one, and the fallback would then run on the others too.
case "$OSTYPE" in
  darwin*) stat_files() { /usr/bin/stat -f '%m %z %N' "$@" 2>/dev/null; } ;;
  *)       stat_files() { stat -c '%Y %s %n' "$@" 2>/dev/null || stat -f '%m %z %N' "$@" 2>/dev/null; } ;;
esac

# Codex session logs. They carry the rate limits Codex last reported (fresher
# than the poll right after a codex call) and whether a task is running. Finding
# the newest of a few hundred logs and grepping megabytes on every render adds
# up, so one small file shared by all sessions remembers the answer: the logs are
# listed again at most every 10 seconds, and one is read again only when its
# mtime or size changed.
CODEX_EVENTS='"rate_limits"|"type":"event_msg","payload":\{"type":"(task_started|task_complete|turn_aborted)"'
scan_events() { awk '
  /"rate_limits"/ { limits = $0; next }
  /"task_started"/ { state = "run"; next }
  { state = "done" }
  END { print state; print limits }'; }
list_logs() { log_files=$(ls -t "$HOME/.codex/sessions"/*/*/*/rollout-*.jsonl 2>/dev/null); }
c_scan=0; c_newest=""; c_sig=""; sess_m=0; c_state=""; cu_line=""; c_end=""
[ -f "$LOG_CACHE" ] && { IFS= read -r c_scan; IFS= read -r c_newest; IFS= read -r c_sig; IFS= read -r sess_m
                        IFS= read -r c_state; IFS= read -r cu_line; IFS= read -r c_end; } < "$LOG_CACHE"
case "$c_scan$sess_m" in ''|*[!0-9]*) c_end="" ;; esac
[ "$c_end" = end ] || { c_scan=0; c_newest=""; c_sig=""; sess_m=0; c_state=""; cu_line=""; }
newest=$c_newest; log_files=""; scan_at=$c_scan; codex_state=$c_state
if [ $((now_s - c_scan)) -ge 10 ] || { [ -n "$newest" ] && [ ! -f "$newest" ]; }; then
  list_logs; IFS= read -r newest <<< "$log_files"; scan_at=$now_s
fi

CL_CACHE="$STATE_DIR/claude-usage.json"
LAST_INPUT="$STATE_DIR/claude-last-input.json"
CU_CACHE="$STATE_DIR/codex-usage.json"
U_MARK="$STATE_DIR/usage.last"
u_mark_m=0; cache_m=0; newest_m=0; newest_sig=""
to_stat=()
for f in "$U_MARK" "$CU_CACHE" "$newest"; do [ -e "$f" ] && to_stat[${#to_stat[@]}]=$f; done
if [ ${#to_stat[@]} -gt 0 ]; then
  while read -r m z name; do
    case "$name" in
      "$U_MARK")   u_mark_m=$m ;;
      "$CU_CACHE") cache_m=$m ;;
      "$newest")   newest_m=$m; newest_sig="$m $z" ;;
    esac
  done <<< "$(stat_files "${to_stat[@]}")"
fi

# One trigger for both usage polls: at most every 5 minutes, kick the shared
# wrapper in the background. The mark file is touched on every attempt and
# shared by all sessions, so failures back off at the same pace instead of
# hammering — the Claude endpoint answers a burst with 429 for a few minutes.
# The wrapper gets the same 300s as a freshness bound: each refresh script
# skips its network call when Claude Code or Codex itself reported new numbers
# more recently than that (the saved payload below, the codex session log), so
# while you are actively working nothing is fetched.
if [ $((now_s - u_mark_m)) -gt 300 ]; then
  touch "$U_MARK"
  ( "$HOME/.claude/scripts/usage-refresh.sh" 300 >/dev/null 2>&1 & )
fi

case "$newest_m" in ''|*[!0-9]*) newest_m=0 ;; esac
if [ -n "$newest" ] && [ "$newest $newest_sig" != "$c_newest $c_sig" ]; then
  # Something was written — and with it another log may have become the newest.
  if [ "$scan_at" != "$now_s" ]; then
    list_logs; scan_at=$now_s
    IFS= read -r lf <<< "$log_files"
    if [ -n "$lf" ] && [ "$lf" != "$newest" ]; then
      newest=$lf; read -r newest_m z _ <<< "$(stat_files "$newest")"
      case "$newest_m" in ''|*[!0-9]*) newest_m=0 ;; esac
      newest_sig="$newest_m $z"
    fi
  fi
  tried=0; codex_state=""; cu_line=""; sess_m=0
  while IFS= read -r lf && [ "$tried" -lt 3 ]; do   # the three newest logs
    tried=$((tried + 1))
    # The run state and the last rate_limits line, in that order. Only the
    # last lines matter and a log runs past 100MB, so read its tail first and
    # the whole file only when the tail holds no rate_limits line.
    found=$(tail -c 2000000 "$lf" 2>/dev/null | grep -E "$CODEX_EVENTS" | scan_events)
    case "$found" in *$'\n'?*) ;; *)
      found=$(grep -E "$CODEX_EVENTS" "$lf" 2>/dev/null | scan_events) ;;
    esac
    [ "$tried" -eq 1 ] && codex_state=${found%%$'\n'*}
    case "$found" in *$'\n'*)
      cu_line=${found#*$'\n'}
      if [ "$lf" = "$newest" ]; then sess_m=$newest_m; else read -r sess_m _ <<< "$(stat_files "$lf")"; fi
      break ;;
    esac
  done <<< "$log_files"
fi
case "$sess_m" in ''|*[!0-9]*) sess_m=0 ;; esac
# A task that started and has not finished is running — unless its log has been
# silent for a quarter of an hour, which is what a killed Codex leaves behind.
[ "$codex_state" = run ] && [ $((now_s - newest_m)) -gt 900 ] && codex_state=stale
if [ "$scan_at" != "$c_scan" ] || [ "$newest $newest_sig" != "$c_newest $c_sig" ] || [ "$codex_state" != "$c_state" ]; then
  printf '%s\n%s\n%s\n%s\n%s\n%s\nend\n' \
    "$scan_at" "$newest" "$newest_sig" "$sess_m" "$codex_state" "$cu_line" > "$LOG_CACHE"
fi

# Codex account usage: whichever of the poll and the session log is newer.
codex_json=""; codex_shape=""
if [ -f "$CU_CACHE" ] && [ "$cache_m" -ge "$sess_m" ]; then
  IFS= read -r -d '' codex_json < "$CU_CACHE"; codex_shape=poll
elif [ -n "$cu_line" ]; then
  codex_json=$cu_line; codex_shape=log
fi

# The other two sources of Claude usage (see below).
saved_json=""; poll_json=""
[ -f "$LAST_INPUT" ] && IFS= read -r -d '' saved_json < "$LAST_INPUT"
[ -f "$CL_CACHE" ] && IFS= read -r -d '' poll_json < "$CL_CACHE"

# One jq pass pulls every number the render needs out of all of them,
# tab-separated. A missing value is emitted as "-" rather than an empty field:
# tab counts as IFS whitespace, so empty fields would collapse and shift every
# later column. A source that is not valid JSON counts as absent.
IFS=$'\t' read -r session_id transcript cur_dir model effort ctx_pct \
                  l5 l5r l7 l7r p5 p5r p7 p7r a5 a5r a7 a7r cu_pct cu7_pct cu_reset <<< "$(
  jq -r --arg saved "$saved_json" --arg poll "$poll_json" --arg codex "$codex_json" \
        --arg shape "$codex_shape" '
  def at(f): try f catch null;
  def v(d): if type == "number" or (type == "string" and . != "") then . else d end;
  def n: if type == "number" then floor else v("-") end;
  def obj: (fromjson? // {}) | if type == "object" then . else {} end;
  def windows: [ (at(.five_hour.used_percentage) | n), (at(.five_hour.resets_at) | v(0)),
                 (at(.seven_day.used_percentage) | n), (at(.seven_day.resets_at) | v(0)) ];
  ($codex | obj | if $shape == "poll"
                  then {primary: at(.rate_limit.primary_window), secondary: at(.rate_limit.secondary_window)}
                  else at(.payload.rate_limits) end) as $cx
  | [ (at(.session_id) | v("-")),
      (at(.transcript_path) | v("-")),
      (at(.workspace.current_dir) // at(.cwd) | v("-")),
      (at(.model.display_name) | v("Claude")),
      (at(.effort.level) | v("-")),
      (at(.context_window.used_percentage) | n) ]
    + (at(.rate_limits) | if type == "object" then . else {} end | windows)
    + ($saved | obj | at(.rate_limits) | if type == "object" then . else {} end | windows)
    + ($poll | obj | windows)
    + [ (at($cx.primary.used_percent) | n), (at($cx.secondary.used_percent) | n),
        (at($cx.primary.resets_at) // at($cx.primary.reset_at) | v("-")) ]
  | @tsv' <<< "$input" 2>/dev/null)"
[ "$session_id" = "-" ] && session_id=""
[ "$transcript" = "-" ] && transcript=""
[ "$cur_dir" = "-" ] && cur_dir="."
[ "$effort" = "-" ] && effort=""
[ "$ctx_pct" = "-" ] && ctx_pct=""
[ "$cu_pct" = "-" ] && cu_pct=""
[ "$cu7_pct" = "-" ] && cu7_pct=""
[ "$cu_reset" = "-" ] && cu_reset=""

dir_name=${cur_dir%/}; dir_name=${dir_name##*/}
[ -n "$dir_name" ] || dir_name=$cur_dir
# Drop the trailing " (… context)" suffix: "Opus 4.8 (1M context)" -> "Opus 4.8"
ctx_suffix='^(.*[^ ])? *\([^)]*context\)$'
[[ $model =~ $ctx_suffix ]] && model=${BASH_REMATCH[1]}

# effort: from JSON .effort.level, else the $CLAUDE_EFFORT environment variable
[ -z "$effort" ] && effort="$CLAUDE_EFFORT"

# model (effort) — segment colour is the model: Fable magenta, Opus blue,
# Sonnet cyan, Haiku green
shopt -s nocasematch
case "$model" in
  *fable*)  mcolor="${ESC}[38;5;213m" ;;
  *opus*)   mcolor="${ESC}[38;5;75m"  ;;
  *sonnet*) mcolor="${ESC}[38;5;80m"  ;;
  *haiku*)  mcolor="${ESC}[38;5;114m" ;;
  *)        mcolor=$RESET ;;
esac
shopt -u nocasematch
model_txt=$model; [ -n "$effort" ] && model_txt="$model ($effort)"

# A reading of a quota window is a used% and the epoch that window resets at.
# Anything that is not a whole number counts as missing (jq hands over "-").
is_num() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }

# Two readings of one window carry the same reset time — give or take: the usage
# endpoint reports it to the microsecond, a hair before the round second Claude
# Code works with. Reset times this close together are the same window.
SAME_WINDOW=60

# Is reading B newer than reading A? Usage only climbs until the window resets,
# so a later resets_at means a newer window, and inside one window the larger
# number is the more recent one.
newer() { # $1=usedA $2=resetA $3=usedB $4=resetB
  local ua=$1 ra=$2 ub=$3 rb=$4
  is_num "$ub" || return 1
  is_num "$ua" || return 0
  is_num "$ra" || ra=0
  is_num "$rb" || rb=0
  [ $((rb - ra)) -gt "$SAME_WINDOW" ] && return 0
  [ $((ra - rb)) -gt "$SAME_WINDOW" ] && return 1
  [ "$ub" -gt "$ua" ]
}

# Claude account usage.
#
# Claude Code only refills the rate_limits block after an API response, so an
# idle session would keep painting the numbers it last saw — and once a window
# rolls over it would keep painting them for hours. So we read three sources and
# draw the freshest: this payload (l…), the furthest-along payload any session
# has been handed (p…, saved below), and a background poll of the account usage
# endpoint (a…; account info, not a model request: it costs no usage).
#
# Save this payload for the other sessions (and agents) — but only when it is
# news, i.e. further along than the saved one. An idle session is re-rendered
# with the payload it last received; saving that would overwrite what a busier
# session just learned, and would keep the file's mtime at "now", which
# claude-usage-refresh.sh reads as "Claude Code reported usage a moment ago, no
# need to poll". The weekly reading decides and the 5-hour one only breaks a
# tie, so two sessions that are each ahead in one window cannot keep overwriting
# each other.
payload_is_news() {
  newer "$p7" "$p7r" "$l7" "$l7r" && return 0
  newer "$l7" "$l7r" "$p7" "$p7r" && return 1
  newer "$p5" "$p5r" "$l5" "$l5r"
}
# "Larger is newer" only holds while usage climbs. It can also drop inside a
# window — limits get reset early, or you log in to another account — and then
# an old high reading would win until its window ran out. The poll is the one
# source with a known time, so a reading that predates it steps aside for it:
# the saved payload when the poll is newer than that file, this session's own
# when the poll is newer than its transcript (nothing has happened here since).
outdated_p=""; outdated_l=""
if payload_is_news; then
  # (a temporary file of our own: several sessions can get here at once)
  printf '%s' "$input" > "$LAST_INPUT.tmp.$$" && mv "$LAST_INPUT.tmp.$$" "$LAST_INPUT"
  p5=$l5; p5r=$l5r; p7=$l7; p7r=$l7r
else
  [ "$CL_CACHE" -nt "$LAST_INPUT" ] && outdated_p=1
  [ -n "$transcript" ] && [ "$CL_CACHE" -nt "$transcript" ] && outdated_l=1
fi

# The freshest reading of one window. Outdated ones only count when the poll
# has nothing for that window.
pick() { # $1 $2=payload  $3 $4=saved payload  $5 $6=poll  -> best_used best_reset
  best_used=$5; best_reset=$6
  if [ -z "$outdated_p" ] || ! is_num "$5"; then
    newer "$best_used" "$best_reset" "$3" "$4" && { best_used=$3; best_reset=$4; }
  fi
  if [ -z "$outdated_l" ] || ! is_num "$5"; then
    newer "$best_used" "$best_reset" "$1" "$2" && { best_used=$1; best_reset=$2; }
  fi
  is_num "$best_used" || best_used=""
  is_num "$best_reset" || best_reset=0
}
pick "$l5" "$l5r" "$p5" "$p5r" "$a5" "$a5r"; c5=$best_used; c5r=$best_reset
pick "$l7" "$l7r" "$p7" "$p7r" "$a7" "$a7r"; c7=$best_used; c7r=$best_reset

# A window whose reset time has passed has already rolled over: the numbers we
# hold describe the window before it, so the current one starts empty.
if [ -n "$c5" ] && [ "$c5r" -gt 0 ] && [ "$c5r" -le "$now_s" ]; then c5=0; c5r=0; fi
if [ -n "$c7" ] && [ "$c7r" -gt 0 ] && [ "$c7r" -le "$now_s" ]; then c7=0; c7r=0; fi

# --- What to draw --------------------------------------------------------------
# Seconds until something on the line reads differently; the replay above is
# good for that long, a minute at most.
next_change=60
sooner() { [ "$1" -gt 0 ] && [ "$1" -lt "$next_change" ] && next_change=$1; }

countdown() { # $1=reset epoch -> cd_txt "↻6d3h" / "↻1h23m" / "↻45m", empty if past or unset
  # Switches unit with the distance: days for a weekly window, hours/minutes for
  # a 5-hour one. Codex dropped its 5-hour window on 2026-07-12 and sent only
  # the weekly (~7 day) one, which is why days are shown at all; when a short
  # window comes back the display returns to hours/minutes on its own.
  local at=$1 remain d h m
  cd_txt=""
  is_num "$at" || return
  remain=$((at - now_s)); [ "$remain" -le 0 ] && return
  d=$((remain / 86400)); h=$(( (remain % 86400) / 3600 )); m=$(( (remain % 3600) / 60 ))
  if [ "$d" -gt 0 ]; then cd_txt="↻${d}d${h}h"; sooner $((remain % 3600 + 1))
  elif [ "$h" -gt 0 ]; then cd_txt="↻${h}h${m}m"; sooner $((remain % 60 + 1))
  else cd_txt="↻${m}m"; sooner $((remain % 60 + 1)); fi
}

# What to show is the user's to choose: ~/.claude/codex-status/config, one
# key=value a line, written by the plugin's setup skill or the installer's
# options. Without it everything is shown, labelled in words.
#   show=folder model codex claude ctx        the segments, any of them
#   countdown=on|off                          the time until a window resets
#   icons=on|off                              icons for the three gauge labels
#   light=on|off                              the light and the glow of a quota in use
show=" folder model codex claude ctx "; opt_countdown=on; opt_icons=""; opt_light=on
if [ -f "$CONFIG" ]; then
  while IFS='=' read -r k v || [ -n "$k" ]; do
    case "$k" in
      show)      show=" $v " ;;
      countdown) opt_countdown=$v ;;
      icons)     opt_icons=$v ;;
      light)     opt_light=$v ;;
    esac
  done < "$CONFIG"
fi
# (1.2 switched the icons on with a marker file; it still counts where the config does not say)
[ -n "$opt_icons" ] || { opt_icons=off; [ "$icons" = 1 ] && opt_icons=on; }
shown() { case "$show" in *" $1 "*) return 0 ;; esac; return 1; }

# The icons are Nerd Fonts glyphs, and a script cannot tell whether the
# terminal's font has them, which is why they are a choice and not the default:
#   codex, claude  the vendors' logos (cod-openai U+EC81, cod-claude U+EC82,
#                  both only since Nerd Fonts 3.5.0)
#   ctx            a speech bubble, the conversation so far
#                  (md-message_text_outline U+F036A)
# Spelled as UTF-8 bytes because bash 3.2 has no \u escape.
codex_label=codex; claude_label=claude; ctx_label=ctx
if [ "$opt_icons" = on ]; then
  codex_label=$'\xee\xb2\x81'; claude_label=$'\xee\xb2\x82'; ctx_label=$'\xf3\xb0\x8d\xaa'
fi

codex_num=""; codex_cd=""; claude_num=""; claude_cd=""; ctx_num=""
if is_num "$cu_pct"; then
  codex_left=$((100 - cu_pct)); [ "$codex_left" -lt 0 ] && codex_left=0
  codex_num="$codex_left%"; countdown "$cu_reset"; codex_cd=$cd_txt
fi
if [ -n "$c5" ]; then
  claude_left=$((100 - c5)); [ "$claude_left" -lt 0 ] && claude_left=0
  claude_num="$claude_left%"; countdown "$c5r"; claude_cd=$cd_txt
  [ "$c7r" -gt "$now_s" ] && sooner $((c7r - now_s + 1))
fi
[ -n "$ctx_pct" ] && ctx_num="$ctx_pct%"
shown codex || codex_num=""
shown claude || claude_num=""
shown ctx || ctx_num=""
[ "$opt_countdown" = on ] || { codex_cd=""; claude_cd=""; }

# --- Fitting it to the terminal ------------------------------------------------
# Cells a text takes: one per character, two for CJK and emoji. Counted on the
# bytes, so it does not depend on the locale: continuation bytes do not count,
# lead bytes E3–ED (CJK, kana, hangul) and F0 (emoji) count double.
disp_width() { # $1=text -> width
  local s=$1 had=${LC_ALL+x} old=$LC_ALL cont wide
  LC_ALL=C
  cont=${s//[!$'\x80'-$'\xbf']/}
  wide=${s//[!$'\xe3'-$'\xed'$'\xf0']/}
  width=$(( ${#s} - ${#cont} + ${#wide} ))
  if [ -n "$had" ]; then LC_ALL=$old; else unset LC_ALL; fi
}

# Claude Code hands over the terminal's width in $COLUMNS and indents the line
# by two cells; one more is left free. The gauges are as wide as the terminal
# allows: a twelfth of it each, MAX_W at most, less when the line would not fit,
# and below MIN_W they are dropped and only the numbers remain. Without a width
# they are DEFAULT_W wide and nothing is cut.
MIN_W=5; MAX_W=14; DEFAULT_W=10
cols=$COLUMNS; is_num "$cols" || cols=0
if [ "$cols" -gt 0 ]; then
  budget=$((cols - 3))
  bar_w=$(( (cols + 6) / 12 )); [ "$bar_w" -gt "$MAX_W" ] && bar_w=$MAX_W
else
  budget=100000; bar_w=$DEFAULT_W
fi

plain=0   # the line without bars and countdowns
segs=0; rails=0; cds=0; gauges=0
count_seg() { # $1=its width; a separator goes before every segment but the first
  [ "$segs" -gt 0 ] && plain=$((plain + 3))
  segs=$((segs + 1)); plain=$((plain + $1))
}
# A terminal draws an icon wider than its cell, into the blank that follows.
# Before a bar that blank is spare; before a bare number one more is needed.
icon_gap=0; [ "$opt_icons" = on ] && icon_gap=1
count_gauge() { # $1=label $2=number
  [ -n "$2" ] || return
  gauges=$((gauges + 1)); rails=$((rails + 2))
  disp_width "$1"; count_seg $((width + 1 + icon_gap + ${#2}))
}
shown folder && { disp_width "$dir_name"; count_seg "$width"; }
shown model && { disp_width "$model_txt"; count_seg "$width"; }
count_gauge "$codex_label" "$codex_num"
count_gauge "$claude_label" "$claude_num"
count_gauge "$ctx_label" "$ctx_num"
[ -n "$codex_cd" ] && { disp_width "$codex_cd"; cds=$((cds + 1 + width)); }
[ -n "$claude_cd" ] && { disp_width "$claude_cd"; cds=$((cds + 1 + width)); }
with_bars=$((plain - gauges * icon_gap + rails + cds))   # all but the cells of the bars

show_cd=1
if [ "$gauges" -gt 0 ]; then
  fit=$(( (budget - with_bars) / gauges ))
  [ "$fit" -lt "$bar_w" ] && bar_w=$fit
  if [ "$bar_w" -lt "$MIN_W" ]; then
    bar_w=0
    [ $((plain + cds)) -gt "$budget" ] && show_cd=""
  fi
else
  bar_w=0
fi

# --- Drawing -------------------------------------------------------------------
# Usage gauge — drains from 100% as the quota is spent.
#  bar length = share of the 5-hour window left, block height (▁▂▃▄▅▆▇█) = weekly
usage_gauge() { # $1=label $2=5h used% $3=weekly used% $4=left% text $5=countdown
                # $6 $7 $8=theme colour as r g b -> head, k_… (the track), tail
  local label=$1 used=$2 weekly=$3 num=$4 cd=$5 left left7 idx
  local blocks=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
  k_cells=""; k_block="█"; k_colour="${ESC}[38;2;$6;$7;${8}m"; k_r=$6; k_g=$7; k_b=$8
  head="$k_colour$label$RESET "
  [ "$bar_w" -gt 0 ] || [ "$icon_gap" -eq 0 ] || head="$head "
  if [ "$used" -ge 90 ]; then k_colour=$CRIT; k_r=255; k_g=0; k_b=0
  elif [ "$used" -ge 70 ]; then k_colour=$WARN; k_r=255; k_g=175; k_b=0; fi
  if [ "$bar_w" -gt 0 ]; then
    left=$((100 - used)); [ "$left" -lt 0 ] && left=0
    k_cells=$(( (left * bar_w + 50) / 100 )); [ "$k_cells" -gt "$bar_w" ] && k_cells=$bar_w
    [ "$k_cells" -eq 0 ] && [ "$left" -gt 0 ] && k_cells=1
    # Block height = weekly quota *left*, so it flattens as the week is spent.
    if is_num "$weekly"; then
      left7=$((100 - weekly)); [ "$left7" -lt 0 ] && left7=0
      idx=$((left7 * 8 / 100)); [ "$idx" -gt 7 ] && idx=7; k_block=${blocks[$idx]}
    fi
    tail=$num
  elif [ "$used" -ge 70 ]; then
    tail="$k_colour$num$RESET"   # no bar to carry the warning colour
  else
    tail=$num
  fi
  [ -n "$cd" ] && [ -n "$show_cd" ] && tail="$tail $GRAY$cd$RESET"
}

sep=" ${GRAY}·${RESET} "
t0=""; t1=""; t2=""
k1_cells=""; k1_block=""; k1_colour=""; k1_r=""; k1_g=""; k1_b=""
k2_cells=""; k2_block=""; k2_colour=""; k2_r=""; k2_g=""; k2_b=""
at=0   # the piece of text being written: t0, then t1 after the codex track, t2 after claude's
put() { case "$at" in 0) t0="$t0$1" ;; 1) t1="$t1$1" ;; *) t2="$t2$1" ;; esac; }
drawn=""
seg() { [ -n "$drawn" ] && put "$sep"; drawn=1; put "$1"; }   # a segment, set off from the one before
shown folder && seg "${ESC}[1m$dir_name$RESET"
shown model && seg "$mcolor$model_txt$RESET"

# (theme: OpenAI green #10A37F)
if [ -n "$codex_num" ]; then
  usage_gauge "$codex_label" "$cu_pct" "$cu7_pct" "$codex_num" "$codex_cd" 16 163 127
  seg "$head"
  if [ -n "$k_cells" ]; then
    k1_cells=$k_cells; k1_block=$k_block; k1_colour=$k_colour; k1_r=$k_r; k1_g=$k_g; k1_b=$k_b; at=1
  fi
  put "$tail"
fi
# (theme: Claude coral #D97757)
if [ -n "$claude_num" ]; then
  usage_gauge "$claude_label" "$c5" "$c7" "$claude_num" "$claude_cd" 217 119 87
  seg "$head"
  if [ -n "$k_cells" ]; then
    k2_cells=$k_cells; k2_block=$k_block; k2_colour=$k_colour; k2_r=$k_r; k2_g=$k_g; k2_b=$k_b; at=2
  fi
  put "$tail"
fi

# Context — a gauge that fills up as the context does (the usage gauges drain
# instead); colour tracks the level (green → yellow → red).
if [ -n "$ctx_num" ]; then
  level="${ESC}[38;5;41m"
  if [ "$ctx_pct" -ge 90 ] 2>/dev/null; then level=$CRIT
  elif [ "$ctx_pct" -ge 70 ] 2>/dev/null; then level=$WARN; fi
  if [ "$bar_w" -gt 0 ] && is_num "$ctx_pct"; then
    cells=$(( (ctx_pct * bar_w + 50) / 100 ))
    # Only a context that really is full draws a full bar.
    if [ "$cells" -ge "$bar_w" ]; then
      cells=$bar_w; [ "$ctx_pct" -lt 100 ] && cells=$((bar_w - 1))
    fi
    draw_track "$cells" "█" "$level" ""
    seg "$level$ctx_label$RESET $track$ctx_num"
  elif [ "$icon_gap" -eq 1 ]; then
    seg "$level$ctx_label  $ctx_num$RESET"
  else
    seg "$level$ctx_label $ctx_num$RESET"
  fi
fi

clock_s=$now_s; [ -n "$dur" ] && clock_s=$((dur / 1000))
compose "" ""; still=$line
if [ "$opt_light" = on ]; then
  claude_use; codex_use "$codex_state"
  [ -n "$codex_mode$claude_mode" ] && compose "$codex_mode" "$claude_mode"
fi
printf '%s' "$line"

# Keep it for the replay: the line without a light, and its pieces.
if [ -n "$key" ]; then
  printf '%s\n' "${COLUMNS:--} $dur $((next_change * 1000)) $icons $bar_w $opt_light" "$key" "$still" "$t0" \
    "$k1_cells" "$k1_block" "$k1_colour" "$k1_r" "$k1_g" "$k1_b" "$t1" \
    "$k2_cells" "$k2_block" "$k2_colour" "$k2_r" "$k2_g" "$k2_b" "$t2" end > "$R_CACHE"
fi
EMBEDDED_statusline-codex.sh
chmod +x "$SCRIPTS_DIR/statusline-codex.sh"

cat > "$SCRIPTS_DIR/codex-usage-refresh.sh" <<'EMBEDDED_codex-usage-refresh.sh'
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
# every 5 minutes (via usage-refresh.sh).
#
# $1 (optional): how long, in seconds, numbers that came from Claude Code itself
# count as current. The status line passes 300. It saves a payload only when the
# usage figures in it moved, so while that file is younger than this you are
# prompting, and the next API response will beat whatever is fetched here.
# Manual runs (cu-refresh, /refresh) pass nothing and fetch regardless.
#
# Either way a cache written within the last minute is left alone: this endpoint
# answers a burst with 429 for a few minutes, so a manual run landing right
# after a background poll would spend that budget for nothing.
export PATH="$HOME/.local/bin:$PATH"

STATE_DIR="$HOME/.claude/codex-status"
CACHE="$STATE_DIR/claude-usage.json"
CREDS="$HOME/.claude/.credentials.json"

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
[ -n "$MAX_AGE" ] && fresh "$STATE_DIR/claude-last-input.json" "$MAX_AGE" && exit 0

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
  # ISO-8601 (optional fraction/offset) -> epoch seconds, to the nearest one.
  # The endpoint says 02:49:59.78 for the reset Claude Code calls 02:50:00, and
  # the status line tells windows apart by that time, so it has to round the
  # same way instead of dropping the fraction.
  def epoch:
    if . == null then 0
    else ((capture("\\.(?<f>[0-9]+)").f | "0.\(.)" | tonumber | round) // 0) as $carry
      | (sub("\\.[0-9]+"; "")) as $s
      | ($s | capture("(?<off>Z|[+-][0-9]{2}:[0-9]{2})$") // {off: "Z"}) as $c
      | (($s | sub("(Z|[+-][0-9]{2}:[0-9]{2})$"; "")) + "Z" | fromdateiso8601) as $base
      | $carry + if $c.off == "Z" then $base
        else $base - ((($c.off[1:3] | tonumber) * 3600 + ($c.off[4:6] | tonumber) * 60)
                      * (if ($c.off[0:1]) == "+" then 1 else -1 end))
        end
    end;
  def window: if .utilization == null then null
              else {used_percentage: (.utilization | floor), resets_at: (.resets_at | epoch)} end;
  {fetched_at: (now | floor), five_hour: (.five_hour | window), seven_day: (.seven_day | window)}
' > "$CACHE.tmp.$$" 2>/dev/null && mv "$CACHE.tmp.$$" "$CACHE" || rm -f "$CACHE.tmp.$$"
EMBEDDED_claude-usage-refresh.sh
chmod +x "$SCRIPTS_DIR/claude-usage-refresh.sh"

cat > "$SCRIPTS_DIR/usage-refresh.sh" <<'EMBEDDED_usage-refresh.sh'
#!/bin/bash
# Refreshes both usage caches. Bound to the `cu-refresh` command, used by the
# /refresh skill, and called by the status line's shared 5-minute trigger.
#
# $1 (optional): passed through to both scripts — how long, in seconds, numbers
# that Claude Code or Codex reported on its own count as current. The status
# line passes 300 so nothing is fetched while you are actively working. Manual
# runs omit it and fetch regardless, bar a one-minute burst guard on each cache.
#
# Each half is independent: one failing (not logged in, endpoint rate limited)
# leaves the other's cache updated and the previous values in place.
DIR="$HOME/.claude/scripts"

# The status line keeps the last line it drew per session (render.<session id>)
# to replay while nothing changes. A live session rewrites its file at least
# once a minute; sweep the ones left behind by sessions that are gone, and with
# them any temporary file a cancelled run did not get to rename.
find "$HOME/.claude/codex-status" -maxdepth 1 \( -name 'render.*' -o -name '*.tmp.*' \) -mmin +1440 -delete 2>/dev/null

[ -x "$DIR/codex-usage-refresh.sh" ] && "$DIR/codex-usage-refresh.sh" "$@"
[ -x "$DIR/claude-usage-refresh.sh" ] && "$DIR/claude-usage-refresh.sh" "$@"
exit 0
EMBEDDED_usage-refresh.sh
chmod +x "$SCRIPTS_DIR/usage-refresh.sh"

# refresh skill, so /refresh works from any session (the plugin has its own)
if [ -z "$PLUGIN" ]; then
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
   - If that script does not exist, the status line is not set up here. Say so, point to
     `/usage-statusline:setup` when this skill came with the plugin, and stop.
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
4. Report the numbers in a line or two. The status line picks them up within a second
   or two.
EMBEDDED_SKILL.md
fi
}

# What the status line shows — ~/.claude/codex-status/config, see "What to draw"
# in statusline-codex.sh. An installation that has no config yet gets one: the
# gauges are labelled with icons, and the script by itself would spell the
# labels out. --sync only writes when there is something to carry over.
write_config() {
  local cfg="$STATE_DIR/config" show="" countdown="" icons="" light="" k v write=""
  if [ -f "$cfg" ]; then
    while IFS='=' read -r k v || [ -n "$k" ]; do
      case "$k" in show) show=$v ;; countdown) countdown=$v ;; icons) icons=$v ;; light) light=$v ;; esac
    done < "$cfg"
  fi
  [ -f "$cfg" ] || [ -n "$SYNC" ] || write=1
  if [ -e "$STATE_DIR/icons" ]; then
    [ -n "$icons" ] || icons=on
    rm -f "$STATE_DIR/icons"; write=1
  fi
  [ -n "$OPT_SHOW" ] && { show=$OPT_SHOW; write=1; }
  [ -n "$OPT_COUNTDOWN" ] && { countdown=$OPT_COUNTDOWN; write=1; }
  [ -n "$OPT_ICONS" ] && { icons=$OPT_ICONS; write=1; }
  [ -n "$OPT_LIGHT" ] && { light=$OPT_LIGHT; write=1; }
  # (up to 1.4 there was a sixth segment, the task in progress)
  case " $show " in *" task "*)
    show=" $show "; show=${show/ task / }; show=${show# }; show=${show% }; write=1 ;;
  esac
  [ -n "$write" ] || return 0
  printf 'show=%s\ncountdown=%s\nicons=%s\nlight=%s\n' \
    "${show:-folder model codex claude ctx}" "${countdown:-on}" "${icons:-on}" "${light:-on}" > "$cfg.tmp.$$" \
    && mv "$cfg.tmp.$$" "$cfg"
}

newer_version() { # is $1 a later version than $2?
  local a b i
  IFS=. read -r -a a <<< "$1"
  IFS=. read -r -a b <<< "$2"
  for i in 0 1 2; do
    [ "${a[i]:-0}" -gt "${b[i]:-0}" ] 2>/dev/null && return 0
    [ "${a[i]:-0}" -lt "${b[i]:-0}" ] 2>/dev/null && return 1
  done
  return 1
}

# --sync, which the plugin runs when a session starts: an installation the setup
# skill made follows the plugin's version. Where nothing was set up, nothing is.
sync_installed() {
  local have
  [ -f "$STATE_DIR/installed-version" ] || return 0
  have=$(cat "$STATE_DIR/installed-version")
  newer_version "$VERSION" "$have" || return 0
  write_files
  link_cu_refresh
  write_config
  remove_legacy_files
  printf '%s\n' "$VERSION" > "$STATE_DIR/installed-version"
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

# Merge the statusLine into settings.json (existing settings are preserved; a
# timestamped backup is written first). It is re-run every second: that is the
# pace of the lights on a gauge in use, and a session in which nothing changed
# answers such a tick by replaying its last line, without spawning anything. Versions before 1.1.0 also registered
# Codex in-flight hooks for a run-state segment the status line no longer
# draws — strip those on upgrade, the hook script is gone.
merge_settings() {
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  prune_settings_backups
  jq '
    .statusLine = {type: "command", command: "~/.claude/scripts/statusline-codex.sh", refreshInterval: 1}
    | (if .hooks then
         .hooks |= with_entries(.value |= map(select(.matcher != "mcp__codex__codex|mcp__codex__codex-reply")))
       else . end)
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
}

# Leftovers from earlier versions: the hook script and its per-session
# counter/lock files (before 1.1.0), the per-session payload dumps the very
# first status line wrote on every render (*.state.json), and the session-log
# cache in the format used before 1.2.0.
remove_legacy_files() {
  rm -f "$SCRIPTS_DIR/codex-status-set.sh" "$STATE_DIR"/*.count \
        "$STATE_DIR"/claude-usage.last "$STATE_DIR"/codex-usage.last \
        "$STATE_DIR"/*.state.json "$STATE_DIR"/codex-sess.cache
  rm -rf "$STATE_DIR"/*.lock
}

main() {
  parse_args "$@" || exit 2
  if [ -n "$SYNC" ]; then
    sync_installed
    return 0
  fi
  mkdir -p "$SCRIPTS_DIR" "$STATE_DIR"
  ensure_jq
  ensure_local_bin_on_path
  write_files
  link_cu_refresh
  merge_settings
  write_config
  remove_legacy_files
  printf '%s\n' "$VERSION" > "$STATE_DIR/installed-version"

  echo "✅ Installed usage-statusline $VERSION"
  echo "   - Status line: it appears at the bottom, in a new session at the latest"
  if [ -n "$PLUGIN" ]; then
    echo "   - Refresh usage now: cu-refresh in a terminal, /usage-statusline:refresh inside Claude Code"
    echo "   - Change what it shows: /usage-statusline:setup"
  else
    echo "   - Refresh usage now: cu-refresh in a terminal, /refresh inside Claude Code"
    echo "   - Change what it shows: run this again with options, see --help"
  fi
  echo "   - Backup: $SETTINGS.bak.*"
}

main "$@"
