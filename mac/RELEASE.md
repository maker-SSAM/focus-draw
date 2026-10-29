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

- [ ] `[윈도우]` `windows/focus-draw.ahk` 11행 `;@Ahk2Exe-SetVersion 1.0.0` → `2.0.0`
- [ ] `[윈도우]` `windows/focus-draw.ahk` 27행 `APP_VERSION := "1.0.0"` → `"2.0.0"` (위 줄과 늘 같이)
- [ ] `[윈도우]` `windows/소개자료/slides.html` 313행 "버전 1.0.0", 735행 "Focus &amp; Draw 1.0.0" → `build.ps1`로 그림을 다시 뽑는다(`소개자료-한장.png` 아래 "1.0.0"도 여기서 나온다)
- [ ] `[윈도우]` `windows/읽어주세요.txt`: 버전 숫자는 없음(6행은 `releases/latest`). 맥 사용자 안내 한 줄만 S12대로 더한다
- [ ] `mac/Info.plist` `CFBundleShortVersionString` → `2.0.0`, `CFBundleVersion` 1 올림
- [ ] `mac/Sources/Platform/Settings.swift` 12행 `displayVersion`의 "(시험판)" 고정 → 0.x일 때만 붙게
- [ ] `mac/맥용 읽어주세요.txt` 1행 "맥용 시험판 0.5.0", 5행 "맥용 시험판", 43행 "시험판의 한계" 절 → 정식판 문구로
- [ ] `mac/beta/한장안내.txt` 1행 "시험판 0.5.0" → 내보낼 버전 (CRLF+BOM 그대로, 점검 3번)
- [ ] `mac/build.sh` 28행: 버전이 `0.*`일 때만 이름에 `-test`가 붙는다 → 2.0.0이면 저절로 `Focus-Draw-2.0.0-mac.zip`. 고칠 것 없음, zip 이름만 확인
- [ ] 루트 `README.md` 8행 내려받기 줄을 "Windows / 맥" 두 줄로, 14행 "맥 판, 준비 중" 지우기 → 맥 설치 안내로 연결 (점검 2번, S12 README 절과 함께)
- [ ] **새 버전 확인 단추**(두 판, `docs/update-check.md`)를 2.0.0에 넣었는지
- [ ] **맨 마지막**: `v2.0.0` 릴리스를 만든 뒤 저장소 맨 위 `version.txt`(`windows=`·`mac=`·`_url`)를 만들어 push (`docs/update-check.md` 순서 — 파일을 먼저 올리면 없는 릴리스를 가리킨다)

되돌리기: 수업 날 아침 문제가 생기면 이전 `mac-v…` 태그의 zip을 다시 받아 쓴다(태그와 zip은 지우지 않는다).
