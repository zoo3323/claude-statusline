#!/bin/bash
# Claude Code 상태줄 + Codex 훅 설치 스크립트.
# 이 파일 하나만 다른 머신에 복사해서 실행하면 됨:
#   curl -fsSL https://raw.githubusercontent.com/zoo3323/claude-statusline/main/install-claude-statusline.sh | bash
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
input=$(cat)

session_id=$(echo "$input" | jq -r '.session_id // empty')

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

# Codex 계정 사용량 — 5분마다 백그라운드로 API 조회(모델 요청 아님, 사용량 소모 없음).
# 캐시와 codex 세션 로그 중 더 최신 데이터를 사용한다.
# (테마: OpenAI 그린 #10A37F, 가로 = 5h 남은 양, 높이 = 주간 사용량, ↻ = 리셋까지 남은 시간)
mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
CU_CACHE="$HOME/.claude/codex-status/codex-usage.json"
CU_MARK="$HOME/.claude/codex-status/codex-usage.last"
now_s=$(date +%s)
cache_m=0; [ -f "$CU_CACHE" ] && cache_m=$(mtime_of "$CU_CACHE")
mark_m=0; [ -f "$CU_MARK" ] && mark_m=$(mtime_of "$CU_MARK")
# 캐시가 5분 넘게 오래됐으면 백그라운드 새로고침 (실패 반복 방지: 시도 간격 60초)
if [ $((now_s - cache_m)) -gt 300 ] && [ $((now_s - mark_m)) -gt 60 ] && [ -f "$HOME/.codex/auth.json" ]; then
  touch "$CU_MARK"
  ( "$HOME/.claude/scripts/codex-usage-refresh.sh" >/dev/null 2>&1 & )
fi

# 세션 로그의 최신 rate_limits (codex 실행 직후엔 이쪽이 더 최신일 수 있음)
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

# Codex 사용량 게이지 세그먼트 (claude 게이지와 같은 형식, 라벨은 OpenAI 그린)
cu_part=""
if [ -n "$cu_pct" ]; then
  cu_part="$(printf '\033[38;2;16;163;127mcodex\033[0m ')$(usage_gauge "$cu_pct" "$cu7_pct" '\033[38;2;16;163;127m')"
  crt=$(reset_txt "$cu_reset")
  [ -n "$crt" ] && cu_part="$cu_part $crt"
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

cat > "$SCRIPTS_DIR/codex-usage-refresh.sh" <<'EMBEDDED_codex-usage-refresh.sh'
#!/bin/bash
# Codex 계정 사용량을 백엔드 API에서 조회해 캐시에 저장.
# 모델 요청이 아니라 계정 정보 조회라 사용량을 소모하지 않는다.
# statusline-codex.sh 가 5분에 한 번 백그라운드로 호출한다.
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

# 유효한 응답일 때만 캐시 갱신 (원자적 쓰기)
if printf '%s' "$out" | jq -e '.rate_limit.primary_window.used_percent' >/dev/null 2>&1; then
  printf '%s' "$out" > "$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
fi
EMBEDDED_codex-usage-refresh.sh
chmod +x "$SCRIPTS_DIR/codex-usage-refresh.sh"

# cu-refresh alias (zsh/bash 둘 다, 있는 쪽에만)
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  if [ -f "$rc" ] && ! grep -q 'alias cu-refresh=' "$rc"; then
    printf '\n# Codex 사용량 즉시 새로고침 (상태줄 캐시 강제 갱신)\nalias cu-refresh="$HOME/.claude/scripts/codex-usage-refresh.sh"\n' >> "$rc"
  fi
done

# refresh Claude Code 스킬 (/refresh 로 어느 세션에서나 호출 가능)
SKILLS_DIR="$CLAUDE_DIR/skills/refresh"
mkdir -p "$SKILLS_DIR"
cat > "$SKILLS_DIR/SKILL.md" <<'EMBEDDED_refresh-SKILL.md'
---
name: refresh
description: Codex/Claude 사용량을 즉시 새로고침해서 보여준다. 사용자가 "/refresh", "사용량 새로고침", "codex 사용량 지금 보여줘" 등을 요청할 때 사용.
---

# refresh

Codex 사용량 게이지는 기본적으로 5분에 한 번만 백그라운드로 자동 갱신된다. 사용자가 지금 당장 최신 값을 보고 싶어 할 때 이 스킬로 즉시 새로고침한다.

## 절차

1. `~/.claude/scripts/codex-usage-refresh.sh` 가 있는지 확인하고 Bash로 실행한다.
   - 없으면: claude-statusline이 설치되지 않은 환경이라는 뜻이므로 그대로 사용자에게 알리고 끝낸다.
2. `~/.codex/auth.json` 이 없어서 스크립트가 조용히 종료된 경우(캐시 파일 mtime이 갱신되지 않음): Codex에 로그인되어 있지 않다고 안내한다.
3. `~/.claude/codex-status/codex-usage.json` 을 읽어 5시간 사용량(`rate_limit.primary_window.used_percent`), 주간 사용량(`rate_limit.secondary_window.used_percent`), 리셋 시각(`rate_limit.primary_window.reset_at`, Unix epoch)을 확인한다.
4. Claude 자체 사용량(5시간/주간 rate limit)은 별도 새로고침이 필요 없다 — Claude Code가 상태줄을 그릴 때마다 항상 최신 값을 직접 넘겨주기 때문. 이 점을 참고해 "Claude는 이미 실시간"이라고 설명에 곁들인다.
5. 새로고침된 수치를 한두 줄로 짧게 보고한다. 상태줄은 refreshInterval(2초) 안에 자동으로 반영된다고 알려준다.
EMBEDDED_refresh-SKILL.md

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

echo "✅ 설치 완료"
echo "   - 상태줄: Claude Code를 새로 시작하면 하단에 표시됩니다"
echo "   - 사용량 즉시 새로고침: 터미널에서 cu-refresh (새 셸부터 적용), Claude Code 안에서 /refresh"
echo "   - 백업: $SETTINGS.bak.*"
