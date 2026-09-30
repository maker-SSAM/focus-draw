import AppKit

// 드로잉을 끄는 이유. 끄는 길은 모두 DrawSession.turnOff(_:) 하나를 지난다.
// 지금은 실제로 쓰이는 이유만 있다. 나머지(다른 앱·데스크톱으로 넘어감, 잠자기, 화면 잠금)는 S4가 채운다.
// (설계도 3절 표: architecture.md)
enum OffReason: String {
    case esc            // Esc: 그린 것과 칠판을 지우고 나간다 (⌘Z로 되살릴 수 있다)
    case widgetButton   // 위젯의 드로잉 버튼: Esc와 같다 (Windows와 같음)
    case hotkey         // F9·⌃⌥2: 그린 것을 그대로 남긴다 (Windows와 같음)
    case settings       // 설정 창 열기: 남긴다 (우리 앱이 앞으로 나오므로 끈다)
    case quit           // 종료: 남긴다 (의미 없음)

    // 그린 것과 칠판을 지우고 나가는가
    var clearsInk: Bool { self == .esc || self == .widgetButton }
}

// 드로잉 켜기·끄기의 순서를 지킨다. 그림·펜 상태는 DrawController가, 판(창)은 InkSurface가,
// 드로잉 키 단축키는 DrawKeys가 든다. "켜졌는가"는 AppState.drawOn이 유일한 출처다.
@MainActor final class DrawSession {
    let state: AppState
    let controller: DrawController
    let keys = DrawKeys()
    var surface: InkSurface { controller.surface }
    // 설정에서 복사본을 만들어 주는 곳 (AppDelegate가 채운다 — 그리기 코드는 Settings를 읽지 않는다)
    var makeConfig: () -> DrawConfig = { DrawConfig() }

    var isOn: Bool { state.drawOn }
    var inkWindowNumbers: [Int] { surface.windowNumbers }

    init(state: AppState) {
        self.state = state
        controller = DrawController(state: state)
        controller.requestOff = { [weak self] reason in self?.turnOff(reason) }
        keys.isDrawing = { [weak self] in self?.state.drawOn == true }
        keys.onKey = { [weak self] code, flags, rep in self?.controller.handleKey(code, flags, isRepeat: rep, source: "hk") }
        keys.onKeyUp = { [weak self] code in self?.controller.handleKeyUp(code, source: "hk") }
    }

    func toggle() { isOn ? turnOff(.hotkey) : turnOn() }

    func turnOn() {
        guard !isOn else { return }
        controller.config = makeConfig()
        controller.resetTemporaries()
        controller.expireUndoIfNeeded()
        surface.prepare()
        state.drawOn = true
        surface.show() // 앱을 앞으로 부르지 않는다 — 발표 앱이 앞에 그대로 있다
        keys.registerAll()
        controller.begin()
        Log.log("DRAW", "on front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-") windows=\(surface.windows.count)")
    }

    func turnOff(_ reason: OffReason) {
        guard isOn else { return }
        controller.finishSession(clear: reason.clearsInk)
        // 드로잉 키 단축키를 반드시 푼다 (안 풀리면 시스템 전체에서 그 글자를 못 친다)
        let freed = keys.unregisterAll()
        state.drawOn = false
        surface.hide()
        SystemCursor.show(.board)
        NSCursor.arrow.set()
        Log.log("DRAW", "off reason=\(reason.rawValue) drawkeysFreed=\(freed.removed) errors=\(freed.errors) "
                 + "left=\(keys.ids.count) cursorHidden=\(SystemCursor.hidden)")
    }

    // 설정이 바뀌면: 새 복사본을 넘기고 다시 그린다
    func applySettings() {
        controller.config = makeConfig()
        surface.invalidateAll()
    }
}
