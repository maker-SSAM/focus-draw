# 맥용 배포 절차서 (RELEASE)

**맥 시험판(0.x.x) 절차다.** 정식판은 윈도우와 함께 2.0.0 한 릴리스로 낸다 — `design/stages.md`의 S12 (2026-10-07 결정).

새 Haiku 세션이 이 순서대로 한다. **게시(5~6번)는 늘 선생님이 "올려" 하고 승인한 뒤에만 한다.** 맥 세션이므로 `mac/**`만 고친다.

1. **버전 올리기**: `mac/Info.plist`의 `CFBundleShortVersionString`(예 0.5.1)과 `CFBundleVersion`(1 올림), `mac/맥용 읽어주세요.txt` 첫 줄과 `mac/beta/한장안내.txt` 제목의 버전을 맞춘다.
2. **점검과 빌드**: `mac/build.sh --test`가 통과한 뒤 `mac/build.sh --release`. 실패하면 멈추고 알린다.
3. **zip 확인**: `mac/build/Focus-Draw-<버전>-test-mac.zip`과 `.sha256`. `unzip -l`로 앱·읽어주세요·LICENSE뿐인지, settings*.ini가 없는지 본다(빌드가 이미 검사한다). SHA-256을 선생님께 알린다.
4. **커밋과 태그**: 버전 파일을 경로별로 `git add` → `git status` → 커밋 → `git tag mac-v<버전>`. (`git add -A` 금지, autocrlf 설정 금지 — CLAUDE.md)
5. **게시 (승인 필요)**: 시험판이고 최신이 아님을 지켜 올린다.
   ```
   git push origin master mac-v<버전>
   gh release create mac-v<버전> mac/build/Focus-Draw-<버전>-test-mac.zip --prerelease --latest=false \
     --title "Focus & Draw 맥용 시험판 <버전>" --notes-file <변경 내용 파일>
   ```
6. **확인**: `gh release view --json tagName,isPrerelease` 로 새 릴리스가 시험판인지, `gh release list`에서 **Latest가 여전히 Windows v1.0.0**인지, README의 Windows 내려받기 링크가 Windows zip을 주는지 본다. 하나라도 어긋나면 즉시 선생님께 알린다(`gh release edit mac-v<버전> --latest=false`로 고친다).
7. **기록**: `mac/ROADMAP.md` 진행 기록에 한 줄(버전, SHA-256, 태그).

## 2.0.0 버전 올릴 곳 (두 판 함께, 2026-10-29 점검 5번)

2.0.0은 위 시험판 절차가 아니라 `design/stages.md` S12대로 낸다. 그때 숫자를 고칠 곳이 흩어져 있으니 이 목록을 하나씩 지운다. `[윈도우]` 줄은 윈도우 PC 세션이 고친다(파일 형식 — CRLF+BOM 등 — 은 그대로).

- [x] `windows/focus-draw.ahk` 11행 `SetVersion`·27행 `APP_VERSION` → `2.0.0` (맥에서 고침, 2026-10-29)
- [x] `windows/소개자료/slides.html` "버전 2.0.0"·"Focus &amp; Draw 2.0.0" (글만. 그림은 아래 윈도우 몫)
- [x] `[윈도우]` `windows/소개자료/build.ps1`로 그림을 다시 뽑는다(`소개자료-한장.png` 아래 "1.0.0" → 2.0.0)
- [x] `[윈도우]` `windows/읽어주세요.txt`에 맥 안내 한 줄 (문구는 `docs/windows-todo.md` "2.0.0 배포" 줄, CRLF+BOM 그대로)
- [x] `[윈도우]` exe 컴파일 → 실행 확인(점검 4번 ini 이상값, 새 버전 확인 글자·[받으러 가기]·제작자 링크) → `windows/배포용/`에서 `Focus-Draw-2.0.0.zip`(폴더 `Focus & Draw/` 안에 exe·읽어주세요) (윈도우 2026-10-29)
- [x] `mac/Info.plist` 2.0.0 / 6, `mac/맥용 읽어주세요.txt`·`mac/beta/한장안내.txt`(CRLF+BOM 그대로) 2.0.0 정식 문구
- [x] `mac/build.sh` 28행: 2.0.0이면 저절로 `Focus-Draw-2.0.0-mac.zip` (고칠 것 없음)
- [x] 루트 `README.md`: 내려받기 두 줄(`v2.0.0` 각 zip 주소), "맥에서 쓰기" 절, 결정 6·12 문구, 새 버전 확인·제작자 링크 (점검 2번, S12)
- [x] `docs/PARITY.md` 마무리, 릴리스 노트 초안 `docs/release-notes-2.0.0.md`
- [x] **게시 (선생님 승인 뒤)**: 두 zip이 다 모이면, 두 판이 모두 들어간 커밋에 태그 `v2.0.0` →
  ```
  git push origin master v2.0.0
  gh release create v2.0.0 mac/build/Focus-Draw-2.0.0-mac.zip "windows/배포용/Focus-Draw-2.0.0.zip" \
    --latest --title "Focus & Draw 2.0.0 (Windows · 맥)" --notes-file docs/release-notes-2.0.0.md
  ```
- [x] 게시 직후 README 내려받기 두 줄의 링크를 각 zip 주소(`releases/download/v2.0.0/Focus-Draw-2.0.0.zip`, `…-mac.zip`)로 바꿔 push (게시 전에는 없는 파일이라 `releases/latest`로 둠)
- [x] **확인**: README의 두 내려받기 링크가 `curl -sIL`로 200, `gh release list`에서 Latest가 `v2.0.0`
- [x] (2026-10-30 윈도우에서 게시: 태그 `v2.0.0` = `b91755b`, Latest, 두 zip SHA-256 로컬과 같음, 링크 200)
- [x] **맨 마지막**: 저장소 맨 위 `version.txt`를 만들어 push (`docs/update-check.md` 모양: `windows=2.0.0`, `windows_url=https://github.com/maker-SSAM/focus-draw/releases/tag/v2.0.0`, `mac=`·`mac_url=` 같음). 그 뒤 두 판 설정 창에서 "최신 2.0.0 — 최신 버전입니다"가 나오는지

되돌리기: 수업 날 아침 문제가 생기면 이전 `mac-v…` 태그의 zip을 다시 받아 쓴다(태그와 zip은 지우지 않는다).
