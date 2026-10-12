# usage-statusline

[English](README.md) · **한국어**

Claude Code 상태줄입니다. Claude와 Codex 한도가 얼마나 남았는지, 컨텍스트가 얼마나
찼는지를 한 줄로 보여줍니다.

![세션이 일하는 동안의 상태줄](assets/statusline.png)

## 설치

Claude Code 안에서:

```
/plugin install usage-statusline --marketplace zoo3323/usage-statusline
/usage-statusline:setup
```

셸에서:

```bash
curl -fsSL https://raw.githubusercontent.com/zoo3323/usage-statusline/main/install.sh | bash
```

macOS, Linux, WSL에서 동작합니다. `jq`가 없으면 받아옵니다. 로고 자리에 빈 상자가
보이면 글꼴에 글리프가 없는 것입니다. [표시 항목 고르기](#표시-항목-고르기)를 보세요.

## 읽는 법

![넉넉할 때, 줄어들 때, 거의 다 썼을 때](assets/levels.png)

| | |
| --- | --- |
| 바 길이 | 5시간 한도에서 남은 양 |
| 바 높이 | 주간 한도에서 남은 양 |
| 노랑, 빨강 | 30% 미만, 10% 미만 남음 |
| `↻2h13m` | 리셋까지 남은 시간 |

컨텍스트 게이지는 반대로 찰수록 채워집니다. 70%부터 노랑, 90%부터 빨강입니다.
사용량은 백그라운드로 조회해서 쉬는 동안에도 숫자가 갱신됩니다. Codex 게이지는
Codex CLI에 로그인돼 있어야 나옵니다.

## 사용 중 표시

![아무도 안 쓸 때, 다른 세션이 쓸 때, 이 세션이 쓸 때](assets/in-use.png)

1. 아무도 한도를 쓰고 있지 않습니다.
2. 이 머신의 다른 세션이 쓰는 중입니다. 바가 끝으로 갈수록 밝아집니다.
3. 이 세션이 쓰는 중입니다. 바 위로 빛이 지나갑니다.

## 폭에 맞춤

![150칸에서 52칸까지 같은 줄](assets/widths.png)

게이지는 터미널 폭에 따라 줄어들고, 자리가 없으면 숫자만 남습니다.

## 표시 항목 고르기

![리셋 시간 숨김, 일부만 표시](assets/choose.png)

`/usage-statusline:setup`을 다시 실행하거나, 스크립트에 옵션을 주거나(`--help`),
`~/.claude/codex-status/config`를 고칩니다.

```
show=folder model codex claude ctx
countdown=on
light=on
```

아이콘은 Nerd Fonts 3.5 글리프가 있는 터미널 글꼴이 필요합니다. Ghostty 1.3은
3.4를 내장하므로 *Symbols Nerd Font*를 설치하고
`font-codepoint-map = U+EC81-U+EC82=Symbols Nerd Font`를 추가합니다. 그런 글꼴이
없으면 설정에 `icons=off`를 적어 글자 라벨로 바꿉니다.

## 그 밖에

- **지금 새로고침** — `/usage-statusline:refresh`, 셸에서는 `cu-refresh`.
- **제거** — `/usage-statusline:uninstall`, 또는 `curl -fsSL https://raw.githubusercontent.com/zoo3323/usage-statusline/main/uninstall.sh | bash`.
- **비용** — 쉬는 세션은 직전 줄을 다시 내보냅니다. 초당 약 3ms이고, 다른
  프로세스를 띄우지 않으며 메모리에 남는 것이 없습니다.
- **개인정보** — 사용량은 Claude Code와 Codex가 이미 이 머신에 저장해 둔 토큰으로
  읽습니다. 다른 곳으로 보내는 것은 없습니다.

## 개발

스크립트는 `src/`에 있고 `./build.sh`가 `install.sh`를 만듭니다. `./test.sh`로
테스트하고, `tools/render-assets.sh`로 이미지를 다시 그리고,
`claude plugin validate .`로 플러그인을 검사합니다.

[MIT](LICENSE)
