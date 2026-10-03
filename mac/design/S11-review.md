# S11 검토 (2026-10-03, Opus 5.5 · 높음)

**범위**: `git diff 6be5a96..HEAD -- mac/Sources` (24파일, +1486 −120).
`mac-v0.5.0` 태그가 없어서 베타 1 zip을 만든 커밋 `6be5a96`(2026-10-01 10:19, zip 10:20)을 기준으로 삼았다.
방법: `/code-review high` + 계획서의 "볼 것"(메모리, 남은 창과 감시자, 남은 단축키, 설정 손상, 비공개 API 보호, 오류 경로)을 전체 코드에서 따로 grep.

다음 Sonnet 세션은 아래 순서대로 고치거나, 고치지 않을 이유를 적는다.

## 순위표

| # | 무게 | 곳 | 무엇이 문제인가 | 고치는 방향 |
|---|---|---|---|---|
| 1 | **높음** | `UI/StatusMenu.swift` `showStatusMenu` | 기본 모드(합친 아이콘 꺼짐)에서 드로잉 중 메뉴 막대 아이콘을 누르면 메뉴는 열리지만, 그 뒤 `statusItem.menu = nil`로 남는다. `updateTrayIcons`는 옵션이 켜져 있을 때만 다시 불리므로, 앱을 다시 켤 때까지 **아이콘을 눌러도 아무 일도 없다**. | 끝에 `statusItem.menu = Settings.shared.showTrayIcons ? nil : statusMenu`. 자체 점검: 기본 모드에서 `handleClickOverStatusItem` 뒤 `statusItem.menu != nil` |
| 2 | 중간 | `UI/SettingsWindow.swift` `HotkeyCaptureView` | 녹화 칸이 키를 기다리는 동안에도 앱 단축키(Carbon)가 살아 있다. F9·⌃⌥2를 누르면 드로잉이 켜지면서 설정 창이 숨는다. 지금 키(F8)를 대체 칸에 넣어 보려 해도 강조만 바뀌고 녹화되지 않는다. | `becomeFirstResponder`에서 `.app` 묶음을 내리고 `resignFirstResponder`에서 다시 등록(창이 닫히거나 키 창을 잃을 때도) |
| 3 | 중간 | `Surface/WindowRules.swift:80` | "우리 메뉴 막대 아이콘 위에서는 화살표" 갈래가 실제로는 닿지 않는다. 판(레벨 1000)이 메뉴 막대 칸(25)보다 늘 앞이라 `.board`가 먼저 걸린다. S9 점검도 `[board, tray]` 순서면 `.board`라고 단언하고, 통과하는 `[tray, board]` 순서는 실제로 생기지 않는다. | `currentPointerTarget`에서 창 목록을 보기 전에 `statusItem.button.window.frame`(handleClickOverStatusItem과 같은 판정)을 먼저 본다. **선생님 확인 1번 중 "화살표 보임"은 아마 안 될 것** |
| 4 | 중간 | `UI/StatusMenu.swift` `menuKeyboard` | 이제 드로잉 중에도 메뉴를 열 수 있는데, "드로잉 모드 단축키 보기"는 드로잉을 끄지 않아 그림 창이 판 **아래**에 뜬다(안 보이고 눌리지 않음). 닫으려고 Esc를 누르면 드로잉 Esc가 받아 **그림이 지워진다**. | `openSettings`처럼 먼저 `draw.turnOff(.settings)`(그림은 남김) |
| 5 | 낮음 | `Input/DrawController.swift:206` | `statusClick`이 "긋는 중 다른 버튼은 무시" 규칙보다 앞에 있다. 왼쪽으로 메뉴 막대 쪽에 긋다가 오른쪽 클릭(전자칠판 손바닥)이 아이콘에 닿으면, 획 도중에 드로잉이 꺼지고 지워지거나 메뉴가 열린다. | 순서를 바꿔 긋는 중 검사를 먼저 |
| 6 | 낮음 | `UI/SettingsWindow.swift` `valueBinding` | 슬라이더 한 칸마다 `objectWillChange`가 2~3번 나가고, 그때마다 `applySettings`(위젯·강조·드로잉 설정 다시 만들기)와 설정 창 전체 다시 그리기가 일어난다. | 배열에 든 값(숫자키·칠판)일 때만 한 번 보낸다 |
| 7 | 낮음 | `UI/StatusMenu.swift` `trayRetries` | 정적 계수가 줄지 않는다. 앱이 도는 동안 5번을 다 쓰면, 그 뒤로는 칸 높이를 못 읽을 때 추정 높이로 굳는다. | 실제 높이를 읽으면 0으로 |
| 8 | 정리 | `UI/KeyboardView.swift` | `KeyboardWindowController`가 `NSWindowDelegate`를 따르고 delegate를 달지만 구현한 메서드가 없다. | 지우거나, 창을 재사용 |

## 계획서의 "볼 것" 전체 확인

- **감시자**: 강조는 켤 때 둘을 달고 끌 때 모두 뗀다(S9 점검 있음). 클릭 링 감시자 둘은 앱이 도는 동안 계속 있다(의도). 남는 것 없음.
- **단축키**: 종료할 때 `unregisterAll`. 단축키를 바꿀 때 등록에 실패하면 원래 키로 되돌리고 계수를 다시 셈. #2 말고는 문제 없음.
- **비공개 API**: `SystemCursor`(CGS/SLS)·`Notice`(SecTranslocate)·`Log`(CGCursorIsVisible) 모두 `dlsym`으로 찾고, 없으면 nil로 넘어간다. 새로 들어온 비공개 API는 없음.
- **로그인 항목**: `--selftest`·`--bench`·`--diag`에서 `LoginItem.allowed = false`. 응용 프로그램 폴더 밖에서는 SMAppService를 부르지 않음. CLAUDE.md 규칙에 맞음.
- **설정 손상**: `readIni`는 크기 제한 없이 `Data(contentsOf:)`로 통째로 읽는다. 아주 큰 파일을 다루는 방법은 다음 세션의 "설정 파일 튼튼함" 항목에서 시험해 정한다(빈 파일, 잘린 파일, 아주 큰 파일, UTF-16, 읽기 전용, Application Support 폴더 없음).
- **모든 설정 초기화**: 지우지 못하면 아무것도 바꾸지 않음, 읽기 막힘(`writeBlocked`)도 풀림. 문제 없음.
- **단축키 규칙과 읽기 규칙이 맞는가**: `HotkeyRules.check`가 받아 주는 조합은 모두 `HotkeyNotation.isSafe`도 받아 준다. 저장한 키가 다음 실행에서 몰래 기본값으로 돌아가는 일은 없음.

## 베타 1에서 남은 것

- 동료 답은 "대체로 잘 된다, 큰 문제 없다" 한 줄뿐이다(2026-10-02). 분류할 자세한 보고가 없다.
- 알려진 한계(맥용 읽어주세요에 적음): F8·F9 전달 안 됨, 제자리 클릭 점 없음, 프로젝터·주 화면 바뀜. 모두 결정대로 둔다.
- 미룬 것: S6 확인 8번(태블릿), 노치 없는 맥에서 메뉴 막대 아이콘 모양, 위젯 취소·지우기 버튼(Windows 판이 먼저).

## 덧붙임

- 앞으로 검토 범위를 정하기 쉽도록 `6be5a96`에 `mac-v0.5.0` 태그를 다는 것을 권한다(선생님 승인 뒤).
