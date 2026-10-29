# Focus & Draw — 맥 판 (2.0.0)

Windows 판(`windows/focus-draw.ahk`)과 같은 쓰임새를 Swift로 다시 만든 맥 판입니다. 2.0.0부터 Windows 판과 같은 번호로, 한 릴리스(`v2.0.0`)에 함께 나갑니다.
macOS 15 Sequoia 이상(15에서 확인), 애플 실리콘(M1~)과 인텔 맥 모두에서 돌아갑니다. macOS 13·14는 확인한 적이 없어 지원한다고 말하지 않습니다.

쓰는 분을 위한 안내는 저장소 맨 위 [README](../README.md)의 "맥에서 쓰기" 절과, zip에 함께 들어가는 [맥용 읽어주세요.txt](맥용%20읽어주세요.txt)에 있습니다. Windows 판과 무엇이 같고 다른지는 **[PARITY.md](../docs/PARITY.md)** (기능 144개 차이표)에 있습니다.

## 알려진 문제

- **노치 있는 맥북에서 메뉴 막대 아이콘이 안 보일 수 있음**: 메뉴 막대가 다른 앱 아이콘으로 꽉 차면 macOS가 나중에 추가된 아이콘부터 노치 뒤로 숨깁니다. 앱 버그가 아니라 macOS 동작입니다.
  - `⌘`(커맨드) 키를 누른 채 다른 메뉴 막대 아이콘을 좌우로 옮겨 자리를 만들면 다시 나타납니다.
  - 위젯을 오른쪽 클릭(또는 control+클릭)하면 같은 메뉴가 열립니다.
  - **시스템 설정 → 디스플레이 → 해상도**를 "더 많은 공간" 쪽으로 바꾸면 메뉴 막대가 넓어져 덜 가려집니다.

## 만들기

Xcode 없이 명령줄 도구만 있으면 됩니다 (`xcode-select --install`).

- `mac/build.sh --quick`: 이 맥의 칩용으로만 빨리 (고치는 동안)
- `mac/build.sh --test`: 빨리 만든 뒤 그림 기준 점검(`Tests/golden/`)과 자체 점검을 돌려 결과를 한 줄로. 그림이 달라지면 `build/test-out/`에 차이 그림과 축소 모음이 남습니다
- `mac/build.sh --run`: 빨리 만든 뒤 켜져 있던 앱을 끄고 새 앱을 띄움
- `mac/build.sh --update-goldens`: 기준 그림을 새로 저장 (그림이 일부러 바뀌었을 때, 선생님이 새 그림을 확인한 뒤에만)
- `mac/build.sh --release`: 배포용 (애플 실리콘+인텔, 실험 메뉴 없음) → `mac/build/Focus-Draw-<버전>-mac.zip`과 SHA-256. 0.x 버전이면 이름에 `-test`가 붙습니다

배포 순서는 [RELEASE.md](RELEASE.md)에 있습니다.

문제를 쫓을 때는 `"build/Focus & Draw.app/Contents/MacOS/FocusDraw" --diag`로 실행하세요. `~/Library/Logs/Focus & Draw/diag.log`에 창·키·화면 상태가 남습니다(입력한 글자는 남지 않음). 메뉴 막대의 "진단 기록" 항목은 개발용이라 2.0.0 교체본에서 뺐고, 사용자에게는 도움말 › **진단 정보 복사**만 부탁합니다.
