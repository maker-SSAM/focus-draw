# Focus & Draw — 세션 규칙

Windows 판과 맥 판을 한 저장소에서 같이 관리한다. 두 판은 같은 높이의 폴더로 나뉜다(2026-10-07 정리).
맥 로드맵은 [mac/ROADMAP.md](mac/ROADMAP.md), 단계별 계획은 [mac/design/stages.md](mac/design/stages.md).

```
README.md, LICENSE, CLAUDE.md, .github/, (2.0 때) version.txt   ← 저장소 공용
windows/  Windows 판: focus-draw.ahk, .ico, NOTES.md, 읽어주세요.txt, 터치펜-확인.ahk, shortcuts.*, 소개자료/
mac/      맥 판: Sources, Tests, build.sh, design/, ROADMAP …
shared/   두 판이 같이 쓰는 그림: icon*.png, settings.png (ahk는 FileInstall로 ..\shared\…, 맥은 build.sh가 복사)
docs/     두 판 공통 문서: PARITY.md(차이표), windows-todo.md(판 사이 할 일), update-check.md …
```

## 두 판은 따로

- **맥 세션**은 `mac/**`를 고친다. **Windows 세션**은 `windows/**`를 고친다.
- `shared/`·`docs/`·저장소 공용 파일은 어느 세션이든 고칠 수 있다. 단 `shared/`의 그림을 바꾸면 두 판 모두 다시 확인한다.
- 맥 세션은 `windows/focus-draw.ahk`·`windows/NOTES.md`를 읽기만, 그것도 `grep -n 이름` 뒤 앞뒤 40줄만 읽는다.
- `windows/읽어주세요.txt`, `windows/소개자료/build.ps1`, `windows/터치펜-확인.ahk`는 줄바꿈(CRLF/mixed)과 인코딩(UTF-8 BOM)이 맥과 달라도 **맥 세션에서 손대거나 되돌리지 않는다**.

## 설정 파일은 두 판이 같게 (배포판 2.0 목표, 2026-10-06 결정)

- `settings.ini`의 항목 이름·범위·기본값·쓰는 방식을 윈도우 판과 맥 판이 똑같이 한다.
- 모든 설정은 **기본값이어도 늘 파일에 쓴다**. "기본값이면 생략" 같은 예외를 새로 만들지 않는다.
- 한쪽에 설정을 먼저 넣으면 다른 쪽 할 일을 `docs/windows-todo.md`(또는 HANDOFF)에 남긴다.

## 새 버전 확인 (배포판 2.0, 2026-10-07 결정)

- 2.0부터 두 판 모두 설정 창에 **"새 버전 확인" 단추 하나만** 둔다. 누를 때만 저장소 맨 위 `version.txt`를 읽는다.
- **자동 업데이트·자동 확인·알림은 넣지 않는다.** 자세한 동작은 [docs/update-check.md](docs/update-check.md).
- 맥 판도 곧 GitHub에 배포한다. **맥도 2.0.0으로 맞추고, 두 판을 함께 진행해 한 릴리스 `v2.0.0`에 두 zip을 올린다**(맥 1.0은 따로 내지 않는다).

## 2.0 뒤에 넣을 기능 (2026-10-09 기록)

- 확대·핀홀 조명·타이머·위젯 펼치기 계획과 조언은 [docs/next-features.md](docs/next-features.md). **맥 판(2.0.0)을 출시한 뒤에 시작한다**(선생님 결정). 그 전에는 손대지 않는다.

## git

- `.git/config`에 `core.autocrlf`는 **절대 설정하지 않는다** — OneDrive로 Windows PC와 공유되어 그쪽 CRLF 규칙을 깬다.
- `core.precomposeunicode = true`로 켜져 있다 (한글 파일명이 APFS에서 분해형으로 저장되어도 git 인덱스와 어긋나지 않게).
- 커밋 시: 경로를 하나씩 `git add` (`add -A`/`add .` 금지) → 커밋 전 `git status` → 커밋 후 `git show --stat`.
- 메시지는 영어 명령형, 사용자가 보는 변화를 말로 쓰고 접두어 없음. 끝에 Co-Authored-By 줄.
- 한글 텍스트를 perl로 고치지 않는다.

## OneDrive에서 작업할 때

`.git`까지 OneDrive로 Windows PC와 공유된다.

- 두 PC에서 동시에 작업하지 않는다. git을 쓰기 전에 동기화(초록 체크)를 확인한다.
- 프로젝트 폴더는 Finder에서 "항상 이 기기에 유지"로 둔다.
- `…-컴퓨터이름` 같은 충돌 사본이 보이면 그 세션에서 멈추고 알린다.
- PC 간 일회성 요청·결과는 루트(`Claude-code/`)의 `HANDOFF.md`에 `[focus-draw]` 태그로 주고받는다(이 저장소에 HANDOFF 파일을 만들지 않는다). Windows 판에도 넣어야 할 기능 목록은 `docs/windows-todo.md`에 쌓고, HANDOFF에서는 그 항목을 가리키기만 한다.
- 빌드는 임시 폴더에서 조립한다(서명 문제 방지) — `mac/build.sh`가 이미 그렇게 한다.

## 맥 세션 금지 사항

- 권한이 필요한 API 금지: 손쉬운 사용, 입력 모니터링, 화면 기록, `CGEventPost`, 이벤트 탭.
- `SMAppService`는 `--selftest`·`--diag`·`--bench`·개발 실행에서 호출하지 않는다(로그인 항목이 옮겨 감).

## 빌드·점검

```
mac/build.sh --quick   # 애플 실리콘만, 고치는 동안
mac/build.sh --test    # 빌드 → 자체 점검 → 요약 한 줄 (커밋 전 한 번)
mac/build.sh --release # 배포용 zip + SHA-256
```

## 막히면

같은 증상을 두 번 고쳐도 안 되면 멈춘다. 증상·시도·실패한 점검을 적어 두고 새 Opus 세션으로 넘긴다.

## 세션을 끝낼 때

`mac/ROADMAP.md`의 "진행 기록"에 한 줄 남기고 "다음 세션" 칸을 고친다.
설계를 결정했으면 `mac/design/`(두 판 공통이면 `docs/`)에 메모를 남긴다. 끝난 단계 기록은 `mac/HISTORY.md`로 옮긴다.
