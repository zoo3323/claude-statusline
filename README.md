# claude-statusline

Claude Code CLI 하단에 **Claude / Codex 사용량, 컨텍스트, Codex 실행 상태**를 한 줄로 보여주는 상태줄 커스터마이징입니다. 설치 스크립트 하나로 끝납니다.

![statusline preview](assets/statusline.svg)

## 기능

- **codex / claude 사용량 게이지** — 각자의 테마 색(OpenAI 그린 / Claude 코랄)으로 표시
  - 가로 길이 = 5시간 창 **남은 양** (100%에서 시작해 쓸수록 줄어듦)
  - 블록 높이(▁▂▃▄▅▆▇█) = **주간 남은 양** (주간을 쓸수록 낮아짐)
  - `↻1h23m` = 리셋까지 남은 시간
  - 남은 양 30% 이하 노랑, 10% 이하 빨강 경고색
- **Codex 실행 상태** — Codex MCP 호출을 훅으로 감지해 `◌ codex`(대기) / `◜ codex ×2 작업중`(스피너 회전, 병렬 개수 표시)
- **컨텍스트 게이지** — 터미널 오른쪽 끝에 정렬
- **진행 중 태스크** — Claude Code 태스크 목록의 in_progress 항목을 노란색으로 표시
- **세션 대시보드** (`claude-dash`) — 여러 Claude Code 세션을 별도 터미널에서 한눈에 모니터링
- 토큰/API 사용 없음 — 전부 로컬 셸 스크립트

## 설치

```bash
curl -fsSL https://raw.githubusercontent.com/zoo3323/claude-statusline/main/install-claude-statusline.sh | bash
```

또는 파일을 받아서 직접 실행:

```bash
bash install-claude-statusline.sh
```

설치 후 Claude Code를 재시작하면 하단에 상태줄이 나타납니다.

### 요구사항

- `jq` — macOS: `brew install jq` / Ubuntu: `sudo apt install -y jq`
  - sudo가 없는 서버: `mkdir -p ~/.local/bin && curl -sL -o ~/.local/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64 && chmod +x ~/.local/bin/jq`
- `perl` (한글 정렬 폭 계산용 — macOS/Linux 기본 포함)
- Codex 관련 표시는 [Codex CLI](https://github.com/openai/codex)와 Codex MCP 연동이 있을 때만 나타나고, 없으면 해당 부분만 조용히 생략됩니다.

## 설치되는 것

| 파일 | 역할 |
|---|---|
| `~/.claude/scripts/statusline-codex.sh` | 상태줄 렌더링 |
| `~/.claude/scripts/codex-status-set.sh` | Codex MCP 호출 감지 카운터 (훅) |
| `~/.claude/scripts/claude-dashboard.sh` | 멀티 세션 대시보드 (`claude-dash`) |
| `~/.claude/settings.json` | `statusLine` + Codex 훅 3개 병합 (기존 설정 보존, `.bak` 백업 생성) |

## 제거

```bash
# settings.json 백업 복원 (설치 시 만들어진 .bak 파일)
cp ~/.claude/settings.json.bak.<날짜> ~/.claude/settings.json
rm -rf ~/.claude/scripts/statusline-codex.sh ~/.claude/scripts/codex-status-set.sh \
       ~/.claude/scripts/claude-dashboard.sh ~/.claude/codex-status
```

## 업데이트

설치 명령을 다시 실행하면 됩니다 (settings.json은 중복 없이 재병합됩니다).
