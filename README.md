# claude-statusline

Claude Code CLI 하단에 **Claude / Codex 사용량, 컨텍스트, Codex 실행 상태**를 한 줄로 보여주는 상태줄 커스터마이징입니다. 설치도 제거도 스크립트 하나로 끝납니다.

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
- **사용량 즉시 새로고침** — Codex 사용량은 기본 5분 캐시라, 터미널에서 `cu-refresh` 또는 Claude Code 안에서 `/refresh`로 바로 최신화 가능 (Claude 사용량은 항상 실시간이라 새로고침 불필요)
- 토큰/API 사용 없음 — 전부 로컬 셸 스크립트

## 설치

```bash
curl -fsSL https://raw.githubusercontent.com/zoo3323/claude-statusline/main/install-claude-statusline.sh | bash
```

`jq`가 없으면 관리자 권한 없이 설치 스크립트가 알아서 `~/.local/bin`에 받아서 씁니다 — `brew`나 `apt`, sudo 권한이 없는 서버에서도 별도 준비 없이 위 명령 한 줄로 끝납니다.

설치 후 Claude Code를 재시작하면 하단에 상태줄이 나타납니다.

### 참고

- Codex 관련 표시는 [Codex CLI](https://github.com/openai/codex)와 Codex MCP 연동이 있을 때만 나타나고, 없으면 해당 부분만 조용히 생략됩니다.
- 한글/CJK 정렬 폭 계산에 `perl`을 쓰는데, 없어도 동작에는 지장 없습니다(컨텍스트 게이지 오른쪽 정렬만 살짝 어긋날 수 있음). 대부분 시스템에 기본으로 깔려 있어 신경 쓸 필요 없습니다.

## 설치되는 것

| 파일 | 역할 |
|---|---|
| `~/.claude/scripts/statusline-codex.sh` | 상태줄 렌더링 |
| `~/.claude/scripts/codex-status-set.sh` | Codex MCP 호출 감지 카운터 (훅) |
| `~/.claude/scripts/codex-usage-refresh.sh` | Codex 계정 사용량 조회 (자동 5분 주기 + 수동 새로고침) |
| `~/.claude/skills/refresh/SKILL.md` | Claude Code 안에서 `/refresh`로 즉시 새로고침 |
| `cu-refresh` alias (`.zshrc`/`.bashrc`) | 터미널에서 즉시 새로고침 |
| `~/.local/bin/jq` | jq가 없던 경우에만, 관리자 권한 없이 설치 |
| `~/.claude/settings.json` | `statusLine` + Codex 훅 3개 병합 (기존 설정 보존, `.bak` 백업 생성) |

## 제거

```bash
curl -fsSL https://raw.githubusercontent.com/zoo3323/claude-statusline/main/uninstall-claude-statusline.sh | bash
```

설치가 건드린 것(위 표의 파일들, `settings.json`의 `statusLine`/Codex 훅, alias)만 정확히 되돌립니다. `settings.json`의 다른 설정(모델, 테마, 권한 등)은 전혀 건드리지 않습니다. 혹시 몰라 제거 전 `settings.json`도 자동으로 백업해둡니다.

## 업데이트

설치 명령을 다시 실행하면 됩니다 (settings.json은 중복 없이 재병합됩니다).
