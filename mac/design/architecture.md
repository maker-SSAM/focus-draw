# 맥 판 설계도 (architecture)

> 2026-09-29 · S1c-2 (Claude Opus 5.5, 높음). 근거는 [SPIKES.md](SPIKES.md)의 D1~D8과 선생님 결정 ①~③.
> **S3이 이 문서를 한 번에 구현한다.** S4·S5·S9는 여기서 정한 자리에 기능을 채운다. 이 문서와 코드가 다르면 문서를 먼저 고친다.
> 지금 코드 이름(`DrawController` 등)은 커밋 `f487933` 기준이다.

## 1. 한 줄 요약

권한을 묻지 않는 **비활성 판(C안)** 이 발표 앱 위에 뜨고, 드로잉 중에만 **드로잉 키 + 막기 키**를 전역 단축키로 잡는다. 잉크는 **선 목록이 원본**이고 그림은 캐시다. 드로잉은 정해진 **"끄는 이유"** 하나로만 끈다.

## 2. 모듈과 파일

`mac/Sources/` 아래 폴더로 나눈다. 파일은 400줄 이하. **AppKit 없음** 표시가 있는 파일은 `import AppKit`을 하지 않는다(자체 점검이 화면 없이 돈다).

| 폴더 / 파일 | 타입 | 맡는 일 | 지금 코드 |
|---|---|---|---|
| `Model/InkModel.swift` (AppKit 없음) | `InkItem`, `InkModel` | 선 목록, 실행 취소 30단계, 전부 지우기 단계, 끈 뒤 10분 보관 | `Draw.swift`의 `items`·`undoFloor`·`setUndoFloor` |
| `Model/Geometry.swift` (AppKit 없음) | 함수 | `shapePoints`, `snap45`, `arrowPoints`, `wavePoints` | `Draw.swift` 91~150행 |
| `Model/Tuning.swift` (AppKit 없음) | 상수 | Windows와 같은 이름: `PEN_BASE_PX`, `PEN_STEP_RATIO`, `ERASER_*`, `STEP_MAX`, `DRAW_COLORS`, `BOARD_KEYS`, `LASER_*`, `RAINBOW_CYCLE_PX`, `UNDO_MAX=30`, `UNDO_KEEP_S=600` | `Settings.swift` 위쪽, 흩어진 숫자 |
| `Model/Clock.swift` (AppKit 없음) | `protocol Clock`, `SystemClock`, `FakeClock` | 시계 주입 (10분 규칙, 레이저, 배지) | `Date()` 직접 호출 |
| `Render/Renderer.swift` | `renderScene(items:board:opacity:size:scale:now:in:)` | 목록 → 그림. 기준 그림(골든)의 유일한 경로 | `renderInk`, `renderLaser` |
| `Render/StrokeLayer.swift` | `StrokeLayer` | 긋는 획 전용 그림: 불투명하게 쌓고 새 토막 자리만 진하기를 곱해 합침 (D4 ①) | Bench의 `eventsLiveLayer` |
| `Render/FloorImage.swift` | `FloorImage` | 30단계보다 오래된 항목을 구운 화면별 바닥 그림 (D4 ②) | 없음 (`InkView.cache`가 비슷) |
| `Surface/InkSurface.swift` | `InkPanel`, `InkView`, `InkSurface` | 화면마다 비활성 판, 추적 영역, 그림 합성, 판 커서 그리기 | `InkPanel`, `InkView`, `rebuildWindows` |
| `Surface/WindowRules.swift` | 함수·상수 | 레벨, `EVERYWHERE`, `isOffActiveSpace`, `screenSignature`, `ensureOnActiveSpace(_:rebuild:)` | `Spotlight.swift` 1~27행 |
| `Input/StrokeSession.swift` (AppKit 없음) | `StrokeSession`, `enum StrokeState` | 누름·끌기·뗌 상태 기계. 누른 순간 도구·색·굵기·진하기·도형을 잠금 | `down`·`drag`·`up`, `activePen` |
| `Input/KeyMap.swift` (AppKit 없음) | `enum DrawAction`, `KeyMap` | 키 코드+수식키 → 행동 표. 드로잉 묶음·막기 묶음 목록도 여기서 나온다 | `handleKey`, `CarbonDrawKeys`의 배열 |
| `Input/DrawKeys.swift` | `DrawKeys` | 두 묶음을 `HotKeyRegistry`로 등록·해제, 자체 반복, `STRAY` 감시 | `CarbonDrawKeys` |
| `Input/ModifierWatch.swift` | `ModifierWatch` | 드로잉 중에만 ⌥ 상태 읽기(이동 때 + 20Hz) → 지우개 링 | 없음 (D3 새 항목) |
| `Session/AppState.swift` | `AppState` | 강조 켬, 드로잉 켬, 위젯 보임, 드로잉 때문에 숨긴 설정 창 — **유일한 출처** | `Widget`의 `spotOn`·`drawOn` 등 |
| `Session/DrawSession.swift` | `DrawSession`, `enum OffReason` | 켜기·끄기 순서, 앱·데스크톱·잠자기 감시 | `DrawController.turnOn/turnOff` |
| `UI/BrushCursor.swift` | `BrushCursor` | 붓 동그라미·지우개 링·레이저 점 모양 (판에 그림) | `cursorImage`, `renderOverlays` 일부 |
| `UI/SystemCursor.swift` | `SystemCursor` | 시스템 커서 숨김 이유 모음, 호출 수 세기, 다시 숨기기 (D5) | `Experiments.swift`의 `SystemCursor` |
| `UI/Badge.swift`, `UI/Laser.swift` | `Badge`, `LaserTrail` | 굵기·진하기 숫자, 사라지는 펜 (타이머는 그릴 것이 있을 때만) | `badge`, `laser*` |
| `UI/Spotlight.swift`, `UI/ClickEffect.swift`, `UI/Widget.swift`, `UI/StatusMenu.swift`, `UI/SettingsWindow.swift` | 같은 이름 | 강조, 클릭 링, 위젯, 메뉴 막대·위젯 메뉴, 설정 창 | 같은 이름, 메뉴는 `main.swift` |
| `Platform/HotKeyRegistry.swift` | `HotKeyRegistry`, `HotKeyGroup` | `EventHotKeyRef` 보관, 고정 ID, 누름·뗌 콜백, 이름 붙인 묶음 등록(하나 실패하면 그 묶음만 되돌림), 결과 코드 | `HotKeys.swift` |
| `Platform/IniFile.swift` (AppKit 없음) | `IniFile` | 무손실 읽기·쓰기 (UTF-8/BOM/UTF-16, 모르는 절·키·주석·순서 보존) | `Settings.load/save` |
| `Platform/SettingsSchema.swift` (AppKit 없음) | `SettingKey` 표 | 절·키·형식·기본값·범위·Windows 의미·맥 의미. 읽기·쓰기·초기화·호환 단언이 이 표 하나를 쓴다 | `Settings.swift` |
| `Platform/Settings.swift` | `Settings` | 표 + 파일을 묶은 관찰 가능한 값. 그리기 코드는 **복사본**(`DrawConfig`)만 받는다 | `Settings.shared` |
| `Platform/Log.swift` | `Log` | 진단 기록 (`--diag`, 메뉴) | `Diag.swift` |
| `Dev/Bench.swift`, `Dev/SelfTest.swift` | 같은 이름 | `--bench`, `--selftest` | 같은 이름 |
| `App/main.swift`, `App/AppDelegate.swift` | `AppDelegate` | 조립만 한다. 상태를 들지 않는다 | `main.swift` |

**없애는 것 (S3a)**: `Experiments.swift`의 A·B안, 창 동작 세 가지 중 둘, `NSCursor` 붓 커서, 재시험 항목 메뉴. 개발용 빌드의 "실험" 메뉴는 비운다(나중에 새 실험이 생기면 다시 쓴다). `InkWindow`(B안용) 삭제.

**S3a 구현 현황 (2026-09-30)**: 아래 표 중 실제로 나뉜 것과 아직 아닌 것. 이 문서와 코드가 다르면 이 메모를 먼저 고친다.
- 나뉨: `InkModel`(+`DrawConfig`), `Geometry`, `Tuning`, `Renderer`, `InkSurface`(판 `InkPanel`·`InkView`·`InkSurface`), `WindowRules`, `AppState`, `DrawSession`(`OffReason`은 지금 쓰는 5개만), `DrawKeys`(옛 `CarbonDrawKeys`), `SystemCursor`(이유가 `CursorReason` enum), `Log`, `IniFile`, `Settings`, `SettingsSchema`(S3b), `HotkeyNotation`(S3b, AHK 표기), `HotKeyRegistry`(S3b, 옛 `HotKeys`), `Spotlight`·`ClickEffect`·`Widget`·`StatusMenu`·`SettingsWindow`.
- 아직 아님 (S4·S5가 채운다): `StrokeSession`(상태 기계는 `DrawController.down/drag/up`에 있다), `KeyMap`(키 표는 `DrawController.handleKey`), `ModifierWatch`, `StrokeLayer`·`FloorImage`(D4), `Clock`(시계는 `InkModel.clock` 클로저). `app`·`draw` 묶음은 등록부로 옮겼고 `block` 묶음은 등록부가 받을 수 있지만 아무도 등록하지 않는다(S4).
- 자리가 문서와 다른 것: 굵기·진하기 배지와 레이저는 `UI/Badge.swift`·`UI/Laser.swift`가 아니라 `UI/Overlays.swift`(`DrawController` 확장), 붓 동그라미·지우개 링은 `UI/BrushCursor.swift`, 키 처리는 `Input/DrawKeyboard.swift`, 앱 시작은 `App/main.swift` + `App/AppDelegate.swift`.
- S3b: 설정 읽기·쓰기·초기화·Windows 대조는 `SettingsSchema.keys` 한 표를 쓴다(45행: 절·키·형식·범위·기본값·Windows 뜻·맥 뜻). `[Hotkeys]`는 표 밖에서 AHK 표기 그대로 `Settings.hotkeys`에 들고, 기본값이고 파일에도 없으면 쓰지 않는다. 등록 아이디는 묶음마다 app 1~, draw 100~, block 1000~. 드로잉 키를 하나라도 못 잡으면 `DrawSession.turnOn`이 켜지 않고 안내 창을 띄운다.
- 앱 상태 흐름: `AppState` 값이 바뀌면 `AppDelegate.applyState()`가 강조·클릭 링(`highlightVisible`)·위젯·설정 창(드로잉 동안 숨김)을 한 번에 다시 정한다. 설정이 바뀌면 `applySettings()`가 강조·위젯·그리기 묶음 중 바뀐 것만 다시 적용한다.

## 3. 상태와 흐름

`AppState`는 값만 든다: `spotOn`, `drawOn`, `widgetVisible`, `settingsHiddenByDraw`. 바뀌면 `AppDelegate`가 강조·위젯·클릭 링의 보임을 **함수 하나**(`AppState.apply`)로 다시 정한다.

### 드로잉 켜기 (`DrawSession.turnOn`)
1. `DrawConfig` 복사본을 만든다(색·굵기는 설정 창 값으로 초기화 — 숫자키로 바꾼 것은 임시값).
2. `InkModel.expireIfNeeded(now)`: 끈 지 10분이 지났으면 실행 취소 기록을 비운다(보이는 잉크는 그대로).
3. 판마다 `ensureOnActiveSpace` → 없거나 다른 데스크톱에 묶였으면 새로 만든다. 남은 잉크가 있으면 목록에서 바닥 그림을 다시 굽는다.
4. `DrawKeys.register()` — 드로잉 묶음 → 막기 묶음 순서. 드로잉 묶음이 하나라도 실패하면 켜지 않고 알린다.
5. 판을 `orderFrontRegardless()`. **앱을 활성화하지 않는다.**
6. `SystemCursor.hide(.board)`, `ModifierWatch.start()`, 감시 시작(앱·데스크톱·잠자기).
7. 설정 창이 열려 있으면 숨기고 `settingsHiddenByDraw = true`.

### 드로잉 끄기 (`DrawSession.turnOff(_ reason: OffReason)`)

| `OffReason` | 언제 | 잉크·칠판 | 비고 |
|---|---|---|---|
| `.esc` | Esc | 지움 | ⌘Z로 10분 안에 되살림 |
| `.widgetButton` | 위젯 드로잉 버튼 | 지움 | Windows와 같음 |
| `.hotkey` | F9·⌃⌥2 | **남김** | Windows와 같음 |
| `.appSwitch` | 다른 앱이 앞으로 (`didActivateApplication`, 우리 앱 제외) | 지움 | 선생님 결정 ② |
| `.spaceChange` | `activeSpaceDidChange` | 지움 | 결정 ② |
| `.sleep` | `willSleep`, `screensDidSleep` | 지움 | D7 선생님 요청 |
| `.lock` | `sessionDidResignActive` | 지움 | 화면 잠금·사용자 전환 |
| `.settings` | 설정 창 열기 | 남김 | 우리 앱이 앞으로 나오므로 끔. "쇼가 꺼질 수 있음" 안내 |
| `.quit` | 종료 | 남김(의미 없음) | `applicationWillTerminate` |

순서: 긋던 획 취소 → (지움이면) `InkModel.clearAll()` = 실행 취소 한 단계 → `DrawKeys.unregister()`와 **남은 등록 0 확인** → 판 `orderOut` → 그림 캐시 모두 버림(`StrokeLayer`·`FloorImage`·`InkView` 버퍼) → `SystemCursor.show(.board)` → `ModifierWatch.stop()` → 감시 해제 → 10분 뒤 한 번 깨는 작업 예약(`InkModel.expire`) → 숨긴 설정 창 되살리기(`.settings` 제외) → 기록 한 줄 `DRAW off reason=… freed=… left=0`.

## 4. 키 (D2 · 결정 ①)

세 묶음을 `HotKeyRegistry`에 등록한다.

| 묶음 | 언제 | 내용 |
|---|---|---|
| `app` | 앱이 도는 동안 늘 | `[Hotkeys]`의 `Spotlight`·`Draw`(기본 F8·F9) + 맥 전용 `SpotlightAlt`·`DrawAlt`(기본 ⌃⌥1·⌃⌥2) |
| `draw` | 드로잉 중 | 1~0·키패드, Q W E R, A S, Z X C(누름·뗌, ⇧ 조합), = + − 키패드±(⇧·⌥ 조합, 반복), delete, 앞으로 지우기, Esc, ⌘Z, ⌃Z — 지금 47개 |
| `block` | 드로잉 중 | `KeyMap.blockKeys` − `draw`: 글자·숫자·기호·스페이스·return·tab·화살표·PageUp/Down·Home/End·키패드·F1~F12(`app` 조합 제외) × {없음, ⇧, ⌥, ⌥⇧}. 누르면 아무것도 안 함 |

- ⌘·⌃ 조합은 `block`에 넣지 않는다: 캡처(⌘⇧3/4/5)·Spotlight(⌘Space)·데스크톱 전환(⌃←→)을 지킨다. 데스크톱을 바꾸면 결정 ②로 드로잉이 꺼진다.
- 같은 조합은 한 번만 등록한다(`draw`가 먼저). 다른 앱이 쓰는 조합(-9878)은 `block`에서 빠지고 기록에만 남는다.
- **반복**: Carbon은 시스템 반복을 주지 않는다(`repeat=self`, 재시험). +·−는 0.45초 뒤 0.07초 간격으로 우리가 반복하고, 뗌 콜백에서 멈춘다.
- **안전**: 끌 때 두 묶음 모두 해제하고 `HotKeyRegistry.count(group:) == 0`을 확인한다. 끈 뒤 `draw`·`block` 키가 들어오면(`STRAY`) 그 자리에서 전부 해제하고 기록한다. 종료할 때 모든 묶음을 해제한다.
- **한글 입력**: 키 코드(자리)로만 판단한다. 입력 소스를 보지 않는다.
- **표기**: `[Hotkeys]`는 AHK 표기로 읽고 쓴다: `^`=⌃, `!`=⌥, `+`=⇧, `#`=⌘. Windows는 `#` 조합을 거절하고 자기 기본값을 쓰므로 서로 안전하다.

## 5. 창과 레벨 (D1)

| 창 | 타입 | 레벨 | 창 동작 | 클릭 |
|---|---|---|---|---|
| 판 (화면마다) | `InkPanel` `.nonactivatingPanel`, `canBecomeKey=false` | screenSaver (`OVERLAY_LEVEL`) | `.canJoinAllSpaces .fullScreenAuxiliary .stationary .ignoresCycle` | 받음, 추적 영역 `.activeAlways` |
| 위젯 | `NSPanel` 비활성 | 쉴 때 떠 있는 레벨, 드로잉 중 `OVERLAY+1` | 같음 | 받음, `acceptsFirstMouse` |
| 강조 원·클릭 링 | `GlassPanel` | `OVERLAY+2` | 같음 | 통과 |
| 설정 창 | 보통 창 | 보통 | 기본 | 열 때만 `NSApp.activate` |

- 띄우기 직전과 데스크톱이 바뀐 직후 `isOnActiveSpace`를 보고, 아니면 새로 만든다(판·강조·링·위젯).
- 화면 알림은 0.3초 모은 뒤 `screenSignature`(번호·자리·크기·배율)가 다를 때만 판을 새로 만든다. EDR만 바뀌는 알림은 센다(`SCREEN same xN`).
- `CGShieldingWindowLevel`은 쓰지 않는다(암호·Touch ID 창이 눌려야 한다). 잉크는 캡처에 찍힌다.
- 쇼 중 메뉴 막대가 없으므로 메뉴는 **위젯 오른쪽 클릭**으로도 연다. 메뉴는 앱을 활성화하지 않는다.

## 6. 커서 (D3 · D5)

- **판 커서**: `BrushCursor`가 붓 동그라미(선 굵기와 같은 지름, 진하기 = 색별 × 전체), 지우개 링(보색, 10단계 384pt까지), 레이저 점을 `InkView`에 그린다. 그린 자리만 무효화한다.
- **⌥ 지우개 링**: C안 판은 키 창이 아니어서 `flagsChanged`가 오지 않는다. `ModifierWatch`가 마우스 이동 때 `NSEvent.modifierFlags`를, 가만히 있을 때는 드로잉 중에만 20Hz로 `CGEventSource.flagsState(.combinedSessionState)`를 읽는다. ⌥= 단축키가 오면 바로 링을 보인다.
- **화살표를 보일 곳**: 위젯 위, 판보다 위에 뜬 다른 창(캡처 화면·시스템 창) 위. 저장해 둔 표시가 아니라 **지금 포인터 아래 창**(`CGWindowListCopyWindowInfo`, 권한 불필요)으로 판단한다.
- **`SystemCursor`**: 숨김 이유(`.board`·`.spot`)를 모아 한 곳에서만 `CGDisplayHideCursor`/`ShowCursor`를 부른다. 비공개 `SetsCursorInBackground`를 켠다.
  - 부른 횟수를 센다. 보일 때는 센 만큼 되돌리고, 끝에 `CGCursorIsVisible`로 확인한다.
  - **다시 숨기기**: 원하는 상태가 "숨김"인데 `CGCursorIsVisible()==1`이면 다시 숨긴다. 비교 시점: 앞 앱 바뀜, 데스크톱 바뀜, 강조·판이 마우스 이동을 받을 때(0.25초에 한 번까지). 쉬는 동안 타이머 없음.
  - 종료·잠자기·드로잉 전환 때 복구한다. Dock 위 화살표는 시스템 한계(안내문).

## 7. 그리기와 실행 취소 (D4 · 결정 ③)

- **원본은 `InkModel.items`**(포인트 단위 벡터). 그림은 모두 캐시다.
- 긋는 중: `StrokeLayer`에 불투명하게 쌓고, 판 합성 때 층 진하기로 곱한다. 갱신 범위는 새 토막 자리뿐.
- 뗄 때: 항목을 목록에 넣고, 화면별 `InkView` 버퍼에 그 항목 범위만 그린다.
- 실행 취소: 최대 30단계(`UNDO_MAX`). 그보다 오래된 항목은 `FloorImage`에 굽는다. ⌘Z는 바닥 그림 + 30개 이하만 다시 그리고, 그 화면에 걸친 것만 그린다. 전부 지우기는 한 단계(지운 항목 목록을 참조로 든다 — 복사 없음).
- **끄면 그림을 모두 버린다.** 다시 켤 때 잉크가 남아 있으면(`.hotkey`·`.settings`) 목록에서 한 번 다시 그린다.
- **10분 규칙**: 끈 뒤 600초(`UNDO_KEEP_S`)가 지나면 실행 취소 기록을 비우고, 화면이 비어 있으면 목록도 비운다. 끌 때 한 번 깨는 작업을 예약하고 켜면 취소한다. 켤 때도 `expireIfNeeded`로 한 번 더 본다(잠자기로 작업이 밀린 경우).
- 크기 단위는 포인트, 픽셀은 화면 배율로만 곱한다. 색 공간은 sRGB 하나.
- 레이저 타이머는 그릴 것이 있을 때만 돈다. 강조·드로잉이 모두 꺼지면 도는 타이머 0개.

## 8. 좌표와 화면 (D6)

- 잉크 좌표는 **주 화면 왼쪽 아래 기준 전역 포인트**(AppKit 좌표)로 둔다. 프로젝터를 더해도 맥북 화면의 잉크는 그대로다.
- S5가 "주 화면이 바뀜"과 "화면이 빠짐"을 명시적으로 처리한다. 긋는 도중 화면이 바뀌면 획을 끝낸다.
- 위젯 자리 `WidgetX/Y`는 **주 화면 왼쪽 위 기준 포인트**로 저장한다(Windows와 같은 방향). 화면 밖이면 기본 자리(주 화면 오른쪽 아래)로 돌린다. "처음 자리로"는 `NSScreen.screens.first`.

## 9. 설정 파일

- 위치: `~/Library/Application Support/Focus & Draw/settings.ini`. 배포 zip에 넣지 않는다.
- `IniFile`: UTF-8·BOM·UTF-16 LE/BE를 읽고, **읽은 형식 그대로** 쓴다. 모르는 절·키·주석·순서를 지킨다. 읽을 수 없으면 덮어쓰지 않고 `.bak`을 남긴 뒤 기본값으로 시작하고 안내한다.
- `SettingsSchema`: 칸은 절, 키, 형식, 기본값, 범위, Windows 의미, 맥 의미. 기본값·범위는 ahk `LoadSettings`와 대조한다. 잘못된 값은 기본값으로.
- 위젯 저장은 실제로 움직였을 때 `WidgetX/Y`만 쓴다. `save()`는 형식 있는 오류를 돌려주고, 성공했을 때만 "저장됨"을 보인다.

## 10. 점검

- `--selftest`는 기본값이나 `--settings <고정 파일>`만 쓰고, `NSScreen` 없이 고정 크기(640×400 @1x, 일부 @2x)로 `renderScene`을 부른다. 시계는 `FakeClock`.
- 단언으로 지킬 것: 끈 뒤 `draw`·`block` 등록 0, `OffReason` 표대로 잉크 남김·지움, 10분 규칙(가짜 시계로 599초·601초), 30단계 + 굽기 경계, 같은 조합 두 번 등록 거절, `SystemCursor` 호출 수 짝, 쉬는 동안 타이머 0, 화면 알림 60번에 판 새로 만들기 0.
- 기준 그림은 `mac/Tests/golden/`(40개 이하).

## 11. 하지 말 것

- 권한이 필요한 API: 손쉬운 사용, 입력 모니터링, 화면 기록, `CGEventPost`, 이벤트 탭, `addGlobalMonitorForEvents`의 키 이벤트.
- 드로잉·메뉴·위젯에서 `NSApp.activate` (설정 창만 예외). 판을 키 창으로 만들기.
- `NSCursor`로 붓 커서 만들기(포인터 크기를 따라 커진다).
- 드로잉 키·막기 키를 드로잉 밖에서 등록해 두기. ⌘·⌃ 조합 막기.
- 그리기 코드에서 `Settings.shared` 읽기. 그림(비트맵)을 원본처럼 들고 있기, 끈 뒤 그림 붙들기.
- 늘 도는 타이머(강조 따라가기의 120Hz 포함 — S9에서 없앤다). `ModifierWatch` 20Hz는 드로잉 중에만.
- `CGShieldingWindowLevel`. 사용자 settings.ini를 자체 점검에서 읽기. `SMAppService`를 `--selftest`·`--diag`·`--bench`·개발 실행에서 부르기.

## 12. 결정 → 자리

| 결정 | 구현 자리 | 단계 |
|---|---|---|
| D1 C안 판, 창 동작 유지 | `InkSurface`, `WindowRules` | S3a(정리), S4 |
| D2 C안 + ① 막기 | `KeyMap`, `DrawKeys`, `HotKeyRegistry` | S3b(등록부), S4(막기 묶음) |
| ② 넘어가면 끄기, D7 잠자기·잠금 | `DrawSession`, `OffReason` | S4 |
| D3 판 커서, ⌥ 링 | `BrushCursor`, `ModifierWatch` | S4 |
| D4 획 그림 + 굽기, ③ 끄면 그림 버림·10분 | `StrokeLayer`, `FloorImage`, `InkModel` | S5 |
| D5 커서 숨기기 + 다시 숨기기 | `SystemCursor` | S4(판), S9(강조) |
| D6 화면 | `WindowRules`, `InkSurface` | S5 |
| 설정 호환 | `IniFile`, `SettingsSchema` | S2b, S3b |
