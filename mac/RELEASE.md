# 맥용 배포 절차서 (RELEASE)

새 Haiku 세션이 이 순서대로 한다. **게시(5~6번)는 늘 선생님이 "올려" 하고 승인한 뒤에만 한다.** 맥 세션이므로 `mac/**`만 고친다.

1. **버전 올리기**: `mac/Info.plist`의 `CFBundleShortVersionString`(예 0.5.1)과 `CFBundleVersion`(1 올림), `mac/맥용 읽어주세요.txt` 첫 줄과 `mac/beta/quick-guide.md` 제목의 버전을 맞춘다.
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

되돌리기: 수업 날 아침 문제가 생기면 이전 `mac-v…` 태그의 zip을 다시 받아 쓴다(태그와 zip은 지우지 않는다).
