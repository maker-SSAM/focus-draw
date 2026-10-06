# Focus & Draw — 세션 규칙

Windows 판(`focus-draw.ahk`)과 맥 판(`mac/`)을 한 저장소에서 같이 관리한다.
자세한 로드맵은 [mac/ROADMAP.md](mac/ROADMAP.md), 단계별 계획은 [mac/design/stages.md](mac/design/stages.md).

## 두 판은 따로

- **맥 세션**은 `mac/**`와 그 단계가 이름을 댄 파일만 고친다.
  `focus-draw.ahk`·`NOTES.md`는 읽기만, 그것도 `grep -n 이름` 뒤 앞뒤 40줄만 읽는다.
- **Windows 세션**만 `읽어주세요.txt`, `소개자료/build.ps1`, `터치펜-확인.ahk`를 고친다.
  이 세 파일은 맥 쪽 줄바꿈(CRLF/mixed)과 인코딩(UTF-8 BOM)이 달라도 **맥 세션에서 손대거나 되돌리지 않는다**.

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
- PC 간 일회성 요청·결과는 루트(`Claude-code/`)의 `HANDOFF.md`에 `[focus-draw]` 태그로 주고받는다(이 저장소에 HANDOFF 파일을 만들지 않는다). Windows 판에도 넣어야 할 기능 목록은 `mac/design/windows-todo.md`에 쌓고, HANDOFF에서는 그 항목을 가리키기만 한다.
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
설계를 결정했으면 `mac/design/`에 메모를 남긴다. 끝난 단계 기록은 `mac/HISTORY.md`로 옮긴다.
