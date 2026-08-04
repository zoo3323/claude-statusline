# claude-statusline

[English](README.md) · **한국어**

Claude Code CLI 하단에 Claude/Codex 사용량, 컨텍스트, Codex 실행 상태, 진행 중인
태스크를 한 줄로 보여주는 상태줄.

> 상태줄에 표시되는 텍스트는 영어입니다(`context`, `working`). 이 문서는 한국어
> 번역본이고, 원본은 [README.md](README.md)입니다.

![statusline preview](assets/statusline.svg)

## 기능

- codex / claude 사용량 게이지 (5시간 창 남은 양 + 주간 사용량 + 리셋까지 남은 시간)
- 아무것도 안 하고 있어도 갱신되는 사용량 — 프롬프트를 넣을 때만이 아니라 백그라운드로 조회
- Codex 실행 상태 (대기/작업중, 병렬 호출 개수)
- 컨텍스트 게이지
- 진행 중 태스크 표시
- `/refresh` 또는 `cu-refresh` 로 사용량 즉시 새로고침

## 설치

```bash
curl -fsSL https://raw.githubusercontent.com/zoo3323/claude-statusline/main/install-claude-statusline.sh | bash
```

`jq`가 없으면 관리자 권한 없이 `~/.local/bin`에 자동으로 받아옵니다. 설치 후
Claude Code를 재시작하면 상태줄이 나타납니다.

## 사용량 게이지 읽는 법

| 요소 | 의미 |
| --- | --- |
| 바 길이 | 5시간 창에서 남은 비율 (100%에서 줄어듦) |
| 블록 높이 `▁▂▃▄▅▆▇█` | 주간 한도에서 남은 양 — 주간을 쓸수록 바가 납작해짐 |
| 색 | 평소엔 테마색, 남은 양 30% 미만이면 노랑, 10% 미만이면 빨강 |
| `↻1h23m` | 5시간 창 리셋까지 남은 시간 (주간 창만 있을 때는 `↻6d3h` 형태) |

## 숫자의 출처

Claude Code는 상태줄에 `rate_limits` 값을 넘겨주지만, 그 값은 API 응답이 있을 때만
갱신됩니다. 그래서 그 값만 쓰면 세션을 가만히 두는 동안엔 마지막에 본 숫자가 계속
그려지고, 창이 리셋된 뒤에도 몇 시간이나 지난 숫자를 붙들고 있게 됩니다. 그래서
상태줄은 세 곳을 읽고 그중 가장 최신값을 그립니다.

1. 방금 Claude Code가 넘겨준 값
2. 어느 세션이든 마지막으로 받은 값 (`~/.claude/codex-status/claude-last-input.json`)
3. 계정 사용량 백그라운드 조회 — 최대 5분에 한 번

사용량은 창이 리셋될 때까지 올라가기만 하기 때문에 "가장 최신"을 판정할 수 있습니다.
`resets_at`이 더 나중이면 더 새로운 창이고, 같은 창 안에서는 더 큰 값이 더 최근에
읽은 값입니다. 리셋 시각이 이미 지난 창은 이전 창의 숫자를 그대로 보여주는 대신 빈
창으로 그립니다.

조회는 Claude Code가 이미 이 머신에 저장해 둔 OAuth 토큰
(`~/.claude/.credentials.json`, 없으면 macOS 키체인)을 그대로 재사용해
`api.anthropic.com/api/oauth/usage` 를 호출합니다. Codex 사용량도 같은 방식으로
`~/.codex/auth.json` 을 써서 `chatgpt.com/backend-api/wham/usage` 를 호출합니다. 둘
다 모델 요청이 아니라 계정 정보 조회라서 사용량을 소모하지 않고, 다른 어디로도
전송되지 않습니다. 두 엔드포인트 모두 공식 문서화된 API가 아니므로, 스펙이 바뀌거나
오류가 오면 캐시를 건드리지 않고 Claude Code가 주는 값으로 자동 폴백합니다.

## 사용법

- 즉시 새로고침: 터미널에서 `cu-refresh`, Claude Code 안에서 `/refresh`
- Codex 관련 표시는 Codex MCP가 연동되어 있을 때만 나타납니다

## 제거

```bash
curl -fsSL https://raw.githubusercontent.com/zoo3323/claude-statusline/main/uninstall-claude-statusline.sh | bash
```

설치가 건드린 것만 정확히 되돌립니다 — 상태줄 스크립트, `settings.json`의
`statusLine`과 Codex 훅 항목, `cu-refresh` alias. 다른 설정은 그대로 둡니다.

## 설치되는 것들

| 경로 | 설명 |
| --- | --- |
| `~/.claude/scripts/statusline-codex.sh` | 상태줄 본체 |
| `~/.claude/scripts/claude-usage-refresh.sh` | Claude 계정 사용량을 조회해 캐시에 저장 |
| `~/.claude/scripts/codex-usage-refresh.sh` | Codex 계정 사용량을 조회해 캐시에 저장 |
| `~/.claude/scripts/usage-refresh.sh` | 둘 다 즉시 새로고침 (`cu-refresh`, `/refresh`) |
| `~/.claude/scripts/codex-status-set.sh` | 실행 중인 Codex 호출 수를 세는 훅 |
| `~/.claude/skills/refresh/SKILL.md` | `/refresh` 스킬 |
| `~/.claude/codex-status/` | 사용량 캐시와 세션별 카운터 |
