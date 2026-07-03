#!/bin/bash
# Claude Code 상태줄 + Codex 훅 + 대시보드 설치 스크립트.
# 이 파일 하나만 다른 머신에 복사해서 실행하면 됨:
#   scp ~/.claude/scripts/install-claude-statusline.sh 서버:/tmp/ && ssh 서버 'bash /tmp/install-claude-statusline.sh'
set -e

command -v jq >/dev/null 2>&1 || {
  echo "❌ jq가 필요합니다. 먼저 설치하세요: (mac) brew install jq / (ubuntu) sudo apt install -y jq"
  exit 1
}

CLAUDE_DIR="$HOME/.claude"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
mkdir -p "$SCRIPTS_DIR" "$CLAUDE_DIR/codex-status"

cat > "$SCRIPTS_DIR/statusline-codex.sh" <<'EMBEDDED_statusline-codex.sh'
#!/bin/bash
# Claude Code statusLine: folder | model (effort) | ctx gauge | 5h limit gauge | Codex status
# Also persists the raw input JSON per session for the dashboard (claude-dashboard.sh).
input=$(cat)

session_id=$(echo "$input" | jq -r '.session_id // empty')

# 대시보드용 세션 상태 저장 (원본 입력 그대로)
if [ -n "$session_id" ]; then
  mkdir -p "$HOME/.claude/codex-status"
  echo "$input" > "$HOME/.claude/codex-status/${session_id}.state.json"
fi

dir_name=$(basename "$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."')")
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
effort=$(echo "$input" | jq -r '.effort.level // empty')
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
r5_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty | if . == "" then . else floor end')
r5_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

# 모델 (effort) — 모델 계열별 색상: Fable 마젠타, Opus 파랑, Sonnet 시안, Haiku 초록
case "$(echo "$model" | tr '[:upper:]' '[:lower:]')" in
  *fable*)  mcolor='\033[35m' ;;
  *opus*)   mcolor='\033[34m' ;;
  *sonnet*) mcolor='\033[36m' ;;
  *haiku*)  mcolor='\033[32m' ;;
  *)        mcolor='\033[0m' ;;
esac
model_txt="$model"
[ -n "$effort" ] && model_txt="$model ($effort)"
model_part=$(printf '%b%s%b' "$mcolor" "$model_txt" '\033[0m')

# 컨텍스트 게이지바 (20칸) — 채운 부분만 색상(초록→노랑→빨강), 빈 부분은 흐리게
ctx_part=""
if [ -n "$ctx_pct" ]; then
  width=20
  filled=$(( (ctx_pct * width + 50) / 100 )); [ "$filled" -gt "$width" ] && filled=$width
  fill_bar=""; empty_bar=""
  for ((i=0; i<filled; i++)); do fill_bar="${fill_bar}█"; done
  for ((i=filled; i<width; i++)); do empty_bar="${empty_bar}░"; done
  if [ "$ctx_pct" -ge 90 ] 2>/dev/null; then color='\033[31m'
  elif [ "$ctx_pct" -ge 70 ] 2>/dev/null; then color='\033[33m'
  else color='\033[32m'; fi
  ctx_part=$(printf '\033[2m컨텍스트\033[0m \033[38;5;246m▕\033[0m\033[48;5;238m%b%s\033[38;5;246m%s\033[0m\033[38;5;246m▏\033[0m%s%%' "$color" "$fill_bar" "$empty_bar" "$ctx_pct")
fi

# 사용량 게이지 빌더 — 남은 양이 100%에서 점점 줄어드는 방식.
#  가로 길이 = 5시간 창 남은 비율, 블록 높이(▁▂▃▄▅▆▇█) = 주간 사용량
usage_gauge() { # $1=사용%(5h) $2=주간사용% $3=테마색 → "게이지 남은%" 출력
  local used=$1 weekly=$2 theme=$3 w=20 rem rem7 cells hc idx fill="" empty="" i c
  rem=$((100 - used)); [ "$rem" -lt 0 ] && rem=0
  cells=$(( (rem * w + 50) / 100 )); [ "$cells" -gt "$w" ] && cells=$w
  [ "$cells" -eq 0 ] && [ "$rem" -gt 0 ] && cells=1
  # 블록 높이 = 주간 "남은" 양 (주간을 쓸수록 낮아짐)
  local chars=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
  hc="█"
  case "$weekly" in
    ''|*[!0-9]*) ;;
    *) rem7=$((100 - weekly)); [ "$rem7" -lt 0 ] && rem7=0
       idx=$(( rem7 * 8 / 100 )); [ "$idx" -gt 7 ] && idx=7; hc="${chars[$idx]}" ;;
  esac
  for ((i=0; i<cells; i++)); do fill="${fill}${hc}"; done
  for ((i=cells; i<w; i++)); do empty="${empty}░"; done
  if [ "$used" -ge 90 ] 2>/dev/null; then c='\033[31m'
  elif [ "$used" -ge 70 ] 2>/dev/null; then c='\033[33m'
  else c=$theme; fi
  # 트랙 전체에 어두운 배경을 깔고 양끝을 얇은 레일(▕ ▏)로 마감
  printf '\033[38;5;246m▕\033[0m\033[48;5;238m%b%s\033[38;5;246m%s\033[0m\033[38;5;246m▏\033[0m%s%%' "$c" "$fill" "$empty" "$rem"
}

reset_txt() { # $1=리셋 epoch → "↻1h23m" (지났거나 없으면 빈 문자열)
  local at=$1 remain rm_h rm_m
  [ -z "$at" ] && return
  remain=$(( at - $(date +%s) )) 2>/dev/null || return
  [ "$remain" -le 0 ] && return
  rm_h=$((remain / 3600)); rm_m=$(( (remain % 3600) / 60 ))
  if [ "$rm_h" -gt 0 ]; then printf '\033[2m↻%sh%sm\033[0m' "$rm_h" "$rm_m"
  else printf '\033[2m↻%sm\033[0m' "$rm_m"; fi
}

# Claude 5시간 한도 (테마: Claude 코랄 #D97757, 높이 = 주간 사용량)
r7_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty | if . == "" then . else floor end')
sess_part=""
if [ -n "$r5_pct" ]; then
  sess_part="$(printf '\033[38;2;217;119;87mclaude\033[0m ')$(usage_gauge "$r5_pct" "$r7_pct" '\033[38;2;217;119;87m')"
  rt=$(reset_txt "$r5_reset")
  [ -n "$rt" ] && sess_part="$sess_part $rt"
fi

# Codex 상태 (세션별 in-flight 카운터)
count=0
if [ -n "$session_id" ]; then
  count_file="$HOME/.claude/codex-status/${session_id}.count"
  [ -f "$count_file" ] && count=$(cat "$count_file" 2>/dev/null || echo 0)
fi
case "$count" in ''|*[!0-9]*) count=0 ;; esac

# Codex 계정 사용량 — 최근 codex 세션 로그의 rate_limits에서 추출
# (테마: OpenAI 그린 #10A37F, 가로 = 5h 남은 양, 높이 = 주간 사용량, ↻ = 리셋까지 남은 시간)
cu_line=""
for cf in $(ls -t "$HOME/.codex/sessions"/*/*/*/rollout-*.jsonl 2>/dev/null | head -3); do
  cu_line=$(grep '"rate_limits"' "$cf" 2>/dev/null | tail -1)
  [ -n "$cu_line" ] && break
done
# Codex 사용량 게이지 세그먼트 (claude 게이지와 같은 형식, 라벨은 OpenAI 그린)
cu_part=""
if [ -n "$cu_line" ]; then
  cu_pct=$(echo "$cu_line" | jq -r '.payload.rate_limits.primary.used_percent // empty | floor' 2>/dev/null)
  cu7_pct=$(echo "$cu_line" | jq -r '.payload.rate_limits.secondary.used_percent // empty | floor' 2>/dev/null)
  cu_reset=$(echo "$cu_line" | jq -r '.payload.rate_limits.primary.resets_at // empty' 2>/dev/null)
  if [ -n "$cu_pct" ]; then
    cu_part="$(printf '\033[38;2;16;163;127mcodex\033[0m ')$(usage_gauge "$cu_pct" "$cu7_pct" '\033[38;2;16;163;127m')"
    crt=$(reset_txt "$cu_reset")
    [ -n "$crt" ] && cu_part="$cu_part $crt"
  fi
fi

# Codex 실행 상태 표시 (맨 오른쪽에 배치)
if [ "$count" -ge 1 ]; then
  # 갱신 주기(2초)마다 프레임이 돌아가는 스피너
  frames=("◜" "◝" "◞" "◟")
  frame=${frames[$(( $(date +%s) / 2 % 4 ))]}
  label="codex"
  [ "$count" -gt 1 ] && label="codex ×${count}"
  codex_part=$(printf '\033[1;32m%s %s\033[0m \033[32m작업중\033[0m' "$frame" "$label")
else
  codex_part=$(printf '\033[2m◌ codex\033[0m')
fi

# 진행 중 태스크 (in_progress 첫 번째, 30자 초과 시 말줄임)
task_part=""
tasks_dir="$HOME/.claude/tasks/$session_id"
if [ -d "$tasks_dir" ]; then
  task=$(cat "$tasks_dir"/*.json 2>/dev/null | jq -r 'select(.status == "in_progress") | (.activeForm // .subject)' 2>/dev/null | head -1)
  if [ -n "$task" ]; then
    [ ${#task} -gt 30 ] && task="${task:0:29}…"
    task_part=$(printf '\033[33m▸ %s\033[0m' "$task")
  fi
fi

# 조립 — 한 줄: [폴더 · 모델 · codex게이지 · claude게이지 · codex상태 · 태스크] ...여백... [컨텍스트]
sep=$(printf ' \033[2m·\033[0m ')
left="$(printf '\033[1m%s\033[0m' "$dir_name")${sep}${model_part}"
[ -n "$cu_part" ] && left="${left}${sep}${cu_part}"
[ -n "$sess_part" ] && left="${left}${sep}${sess_part}"
left="${left}${sep}${codex_part}"
[ -n "$task_part" ] && left="${left}${sep}${task_part}"

if [ -n "$ctx_part" ]; then
  # 터미널 폭을 알 수 있으면 ctx를 오른쪽 끝에 정렬, 모르면 그냥 이어붙임
  cols=${COLUMNS:-$( (stty size </dev/tty) 2>/dev/null | awk '{print $2}')}
  [ -z "$cols" ] && cols=$(tput cols 2>/dev/null)
  strip_ansi() { printf '%s' "$1" | sed $'s/\x1b\\[[0-9;]*m//g'; }
  disp_width() { # 표시 폭: 글자 수 + 한글/CJK(2칸 문자) 개수 보정
    local plain chars wide
    plain=$(strip_ansi "$1")
    chars=$(printf '%s' "$plain" | wc -m)
    wide=$(printf '%s' "$plain" | perl -CS -ne '$n += () = /[\x{1100}-\x{11FF}\x{3130}-\x{318F}\x{AC00}-\x{D7A3}\x{4E00}-\x{9FFF}\x{3040}-\x{30FF}]/g; END { print $n + 0 }' 2>/dev/null)
    case "$wide" in ''|*[!0-9]*) wide=0 ;; esac
    echo $((chars + wide))
  }
  if [ -n "$cols" ] 2>/dev/null && [ "$cols" -gt 0 ] 2>/dev/null; then
    lw=$(disp_width "$left")
    rw=$(disp_width "$ctx_part")
    pad=$((cols - lw - rw - 1))
    if [ "$pad" -gt 0 ]; then
      printf '%s%*s%s' "$left" "$pad" "" "$ctx_part"
    else
      printf '%s%s%s' "$left" "$sep" "$ctx_part"
    fi
  else
    printf '%s%s%s' "$left" "$sep" "$ctx_part"
  fi
else
  printf '%s' "$left"
fi
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
for i in $(seq 1 50); do
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

cat > "$SCRIPTS_DIR/claude-dashboard.sh" <<'EMBEDDED_claude-dashboard.sh'
#!/bin/bash
# Claude 세션 대시보드 — cmux/tmux 오른쪽 pane에서 실행:
#   tmux split-window -h -l 58 ~/.claude/scripts/claude-dashboard.sh
# 상태줄 훅이 2초마다 남기는 ~/.claude/codex-status/<sid>.state.json 을 집계한다.
# 60초 이상 갱신 없는 세션은 종료된 것으로 보고 숨긴다.

STATUS_DIR="$HOME/.claude/codex-status"
TASKS_DIR="$HOME/.claude/tasks"
STALE_SECS=60

C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
C_RED=$'\033[31m'; C_CYN=$'\033[36m'; C_RST=$'\033[0m'

gauge() { # gauge <pct> <width>
  local pct=$1 width=$2 filled bar="" i
  filled=$(( (pct * width + 50) / 100 )); [ "$filled" -gt "$width" ] && filled=$width
  for ((i=0; i<width; i++)); do
    [ "$i" -lt "$filled" ] && bar="${bar}▰" || bar="${bar}▱"
  done
  printf '%s' "$bar"
}

pct_color() { # pct_color <pct>
  if [ "$1" -ge 90 ]; then printf '%s' "$C_RED"
  elif [ "$1" -ge 70 ]; then printf '%s' "$C_YEL"
  else printf '%s' "$C_GRN"; fi
}

render() {
  local now shown=0 rate_line=""
  now=$(date +%s)
  echo "${C_BOLD}${C_CYN} Claude Sessions${C_RST}  ${C_DIM}$(date '+%H:%M:%S')${C_RST}"
  echo "${C_DIM}──────────────────────────────────────────────${C_RST}"

  for f in "$STATUS_DIR"/*.state.json; do
    [ -e "$f" ] || continue
    local mtime age sid
    mtime=$(stat -f %m "$f" 2>/dev/null || echo 0)
    age=$((now - mtime))
    [ "$age" -gt "$STALE_SECS" ] && continue
    sid=$(basename "$f" .state.json)

    local name dir model effort ctx cost mins codex sname
    eval "$(jq -r '
      "dir=\(.workspace.current_dir // .cwd // "." | @sh)
       model=\(.model.display_name // "Claude" | @sh)
       effort=\(.effort.level // "" | @sh)
       ctx=\(.context_window.used_percentage // -1 | floor)
       cost=\(.cost.total_cost_usd // 0)
       mins=\((.cost.total_duration_ms // 0) / 60000 | floor)
       sname=\(.session_name // "" | @sh)
       r5=\(.rate_limits.five_hour.used_percentage // -1 | floor)
       r7=\(.rate_limits.seven_day.used_percentage // -1 | floor)"
    ' "$f")"
    dir=$(basename "$dir")

    # Codex in-flight count
    local cnt=0
    [ -f "$STATUS_DIR/${sid}.count" ] && cnt=$(cat "$STATUS_DIR/${sid}.count" 2>/dev/null || echo 0)
    case "$cnt" in ''|*[!0-9]*) cnt=0 ;; esac
    if [ "$cnt" -gt 0 ]; then
      codex="${C_GRN}🟢 codex×${cnt}${C_RST}"
    else
      codex="${C_DIM}⚪${C_RST}"
    fi

    # 헤더 줄: 폴더 · 모델(effort) · codex
    local eff_txt=""
    [ -n "$effort" ] && eff_txt=" (${effort})"
    printf ' %s%-12s%s %s%s  %b\n' "$C_BOLD" "$dir" "$C_RST" "$model" "$eff_txt" "$codex"
    [ -n "$sname" ] && printf '   %s%.44s%s\n' "$C_DIM" "$sname" "$C_RST"

    # ctx 게이지 + 비용/시간
    local line2=""
    if [ "$ctx" -ge 0 ]; then
      line2="$(pct_color "$ctx")$(gauge "$ctx" 10) ${ctx}%${C_RST}"
    fi
    local dur_txt="${mins}m"
    [ "$mins" -ge 60 ] && dur_txt="$((mins/60))h $((mins%60))m"
    printf '   %b  %s\n' "$line2" "$(printf '$%.2f · %s' "$cost" "$dur_txt")"

    # 진행 중 태스크 (in_progress만)
    if [ -d "$TASKS_DIR/$sid" ]; then
      jq -r 'select(.status == "in_progress") | "   ▸ " + (.activeForm // .subject)' \
        "$TASKS_DIR/$sid"/*.json 2>/dev/null | head -3 | while IFS= read -r t; do
        printf '%s%s%s\n' "$C_YEL" "$t" "$C_RST"
      done
    fi

    # rate limit 은 아무 세션에서나 하나 잡으면 됨 (계정 공통)
    if [ -z "$rate_line" ] && [ "${r5:-\-1}" -ge 0 ]; then
      rate_line=" rate  5h $(pct_color "$r5")$(gauge "$r5" 8) ${r5}%${C_RST}   7d $(pct_color "$r7")$(gauge "$r7" 8) ${r7}%${C_RST}"
    fi
    echo ""
    shown=$((shown + 1))
  done

  [ "$shown" -eq 0 ] && echo " ${C_DIM}활성 세션 없음${C_RST}" && echo ""
  echo "${C_DIM}──────────────────────────────────────────────${C_RST}"
  [ -n "$rate_line" ] && echo -e "$rate_line"
}

# --once: 한 번만 렌더하고 종료 (테스트용)
if [ "$1" = "--once" ]; then
  render
  exit 0
fi

# 메인 루프
trap 'tput cnorm; exit 0' INT TERM
tput civis 2>/dev/null
while true; do
  out=$(render)
  clear
  echo "$out"
  sleep 2
done
EMBEDDED_claude-dashboard.sh
chmod +x "$SCRIPTS_DIR/claude-dashboard.sh"

# settings.json 에 statusLine + codex 훅 병합 (기존 설정 보존, 백업 생성)
SETTINGS="$CLAUDE_DIR/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"

jq '
  .statusLine = {type: "command", command: "~/.claude/scripts/statusline-codex.sh", refreshInterval: 2}
  | .hooks = (.hooks // {})
  | .hooks.PreToolUse = ((.hooks.PreToolUse // []) | map(select(.matcher != "mcp__codex__codex|mcp__codex__codex-reply")) + [{matcher: "mcp__codex__codex|mcp__codex__codex-reply", hooks: [{type: "command", command: "~/.claude/scripts/codex-status-set.sh inc 2>/dev/null || true"}]}])
  | .hooks.PostToolUse = ((.hooks.PostToolUse // []) | map(select(.matcher != "mcp__codex__codex|mcp__codex__codex-reply")) + [{matcher: "mcp__codex__codex|mcp__codex__codex-reply", hooks: [{type: "command", command: "~/.claude/scripts/codex-status-set.sh dec 2>/dev/null || true"}]}])
  | .hooks.PostToolUseFailure = ((.hooks.PostToolUseFailure // []) | map(select(.matcher != "mcp__codex__codex|mcp__codex__codex-reply")) + [{matcher: "mcp__codex__codex|mcp__codex__codex-reply", hooks: [{type: "command", command: "~/.claude/scripts/codex-status-set.sh dec 2>/dev/null || true"}]}])
' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"

# claude-dash alias (zsh/bash 중 있는 쪽에)
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  if [ -f "$rc" ] && ! grep -q 'claude-dash' "$rc"; then
    printf '\nalias claude-dash="$HOME/.claude/scripts/claude-dashboard.sh"\n' >> "$rc"
  fi
done

echo "✅ 설치 완료"
echo "   - 상태줄: Claude Code를 새로 시작하면 하단에 표시됩니다"
echo "   - 대시보드: 새 셸에서 claude-dash 실행"
echo "   - 백업: $SETTINGS.bak.*"
