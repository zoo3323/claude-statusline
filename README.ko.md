# claude-statusline

[English](README.md) · **한국어**

Claude Code 하단에 Claude/Codex 사용량, 컨텍스트 사용률(%), 진행 중인
태스크를 한 줄로 보여주는 상태줄. 상태줄 자체의 표시는 영어입니다.

![statusline preview](assets/statusline.svg)

## 설치

```bash
curl -fsSL https://raw.githubusercontent.com/zoo3323/claude-statusline/main/install-claude-statusline.sh | bash
```

설치 후 Claude Code를 재시작하면 상태줄이 나타납니다. `jq`가 없으면 관리자 권한
없이 `~/.local/bin`에 받아옵니다. 설치되는 건 `~/.claude/scripts/`의 스크립트,
`/refresh` 스킬, `~/.claude/codex-status/` 캐시, `~/.local/bin/cu-refresh`
링크입니다.

## 사용량 게이지 읽는 법

| 요소 | 의미 |
| --- | --- |
| 바 길이 | 5시간 창에서 남은 비율 |
| 블록 높이 `▁▂▃▄▅▆▇█` | 주간 한도에서 남은 양 |
| 색 | 남은 양 30% 미만이면 노랑, 10% 미만이면 빨강 |
| `↻1h23m` | 창 리셋까지 남은 시간 |

사용량은 아무것도 안 하고 있어도 갱신됩니다 — 프롬프트를 넣을 때만이 아니라
백그라운드로 조회합니다. 즉시 새로고침은 터미널에서 `cu-refresh`, Claude Code
안에서 `/refresh`. Codex 관련 표시는 Codex MCP가 연동되어 있을 때만 나타납니다.

조회는 Claude Code와 Codex가 이미 이 머신에 저장해 둔 OAuth 토큰을 재사용해 계정
사용량을 읽습니다. 모델 요청이 아니라 계정 정보 조회라서 사용량을 소모하지 않고,
다른 어디로도 전송되지 않습니다. 두 엔드포인트 모두 공식 문서화된 API가 아니므로
오류가 오면 Claude Code가 주는 값으로 폴백합니다.

## 제거

```bash
curl -fsSL https://raw.githubusercontent.com/zoo3323/claude-statusline/main/uninstall-claude-statusline.sh | bash
```

설치가 건드린 것만 정확히 되돌리고, 다른 설정은 그대로 둡니다.

## 개발

스크립트 원본은 `src/`에 있습니다. `install-claude-statusline.sh`는 `./build.sh`가
거기서 생성하므로, installer가 아니라 `src/`를 고쳐야 합니다. `./build.sh --check`는
커밋된 installer가 최신이 아니면 실패합니다.
