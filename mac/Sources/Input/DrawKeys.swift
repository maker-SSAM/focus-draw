import AppKit
import Carbon

// ================= 드로잉 키를 드로잉 중에만 전역 단축키로 =================
// 판은 키 창이 되지 않으므로 키보드 이벤트가 오지 않는다. 대신 드로잉 키만 Carbon 단축키로 등록해 두었다가
// 드로잉을 끄는 순간 모두 푼다. 풀리지 않으면 시스템 전체에서 그 글자를 칠 수 없게 되므로,
// 끈 뒤에 드로잉 키가 한 번이라도 들어오면 그 자리에서 전부 풀고 기록에 남긴다.
@MainActor final class DrawKeys {
    var onKey: (_ code: UInt16, _ flags: NSEvent.ModifierFlags, _ isRepeat: Bool) -> Void = { _, _, _ in }
    var onKeyUp: (_ code: UInt16) -> Void = { _ in }
    var isDrawing: () -> Bool = { false }

    private(set) var ids: [UInt32] = []
    private var repeatID: UInt32?
    private var repeatTimer: Timer?
    private var loggedRepeat = false

    private static let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 83, 84, 85, 86, 87, 88, 89, 91, 92, 82]
    private static let letters: [UInt16] = [12, 13, 14, 15, 0, 1] // Q W E R A S
    private static let edits: [UInt16] = [51, 117, 53]            // delete, 앞으로 지우기, Esc

    var isRegistered: Bool { !ids.isEmpty }

    @discardableResult
    func registerAll() -> (ok: Int, failed: Int) {
        guard ids.isEmpty else { return (ids.count, 0) }
        var failed = 0
        loggedRepeat = false
        func add(_ code: UInt16, _ mods: Int = 0, release: Bool = false, repeats: Bool = false) {
            var myID: UInt32 = 0
            let flags = DrawKeys.flags(mods)
            let r = HotKeys.register(keyCode: Int(code), modifiers: mods, name: "draw-\(code)+\(mods)", quiet: true,
                                     onRelease: { [weak self] in self?.released(myID, code, release) }) { [weak self] in
                self?.pressed(myID, code, flags, repeats)
            }
            myID = r.id
            if r.status == noErr { ids.append(r.id) } else { failed += 1 }
        }
        for k in DrawKeys.digits + DrawKeys.letters + DrawKeys.edits { add(k) }
        for k: UInt16 in [6, 7, 8] { add(k, release: true); add(k, shiftKey, release: true) } // Z X C (⇧와 함께 눌러도)
        for m in [0, shiftKey, optionKey, optionKey | shiftKey] { add(24, m, repeats: true) } // = +  (⌥: 지우개)
        for k: UInt16 in [27, 69, 78] { add(k, repeats: true); add(k, optionKey, repeats: true) } // - 키패드+ 키패드-
        add(6, cmdKey); add(6, controlKey)                                                    // ⌘Z ⌃Z
        Log.log("HK", "drawkeys on ok=\(ids.count) failed=\(failed) total=\(HotKeys.count)")
        return (ids.count, failed)
    }

    @discardableResult
    func unregisterAll() -> (removed: Int, errors: Int) {
        stopRepeat()
        var errors = 0
        let n = ids.count
        for id in ids where HotKeys.unregister(id) != noErr { errors += 1 }
        ids = []
        if n > 0 { Log.log("HK", "drawkeys off removed=\(n) errors=\(errors) left=\(HotKeys.count)") }
        return (n, errors)
    }

    private func pressed(_ id: UInt32, _ code: UInt16, _ flags: NSEvent.ModifierFlags, _ repeats: Bool) {
        guard isDrawing() else {
            Log.log("HK", "STRAY draw key \(code) while drawing is off — unregistering all")
            unregisterAll()
            return
        }
        if repeats, repeatID == id {
            // 시스템이 누르고 있는 키를 반복해서 보내 준다 → 우리 반복 타이머는 멈추고 그대로 쓴다
            if !loggedRepeat { Log.log("KEY", "repeat=system code=\(code)"); loggedRepeat = true }
            repeatTimer?.invalidate(); repeatTimer = nil
            onKey(code, flags, true)
            return
        }
        onKey(code, flags, false)
        guard repeats else { return }
        stopRepeat()
        repeatID = id
        // 시스템이 반복을 안 보내 주면 누르고 있는 동안 우리가 반복한다
        let t = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
            guard let self, self.repeatID == id else { return }
            if !self.loggedRepeat { Log.log("KEY", "repeat=self code=\(code)"); self.loggedRepeat = true }
            let r = Timer(timeInterval: 0.07, repeats: true) { [weak self] _ in
                guard let self, self.repeatID == id, self.isDrawing() else { self?.stopRepeat(); return }
                self.onKey(code, flags, true)
            }
            RunLoop.main.add(r, forMode: .common)
            self.repeatTimer = r
        }
        RunLoop.main.add(t, forMode: .common)
        repeatTimer = t
    }

    private func released(_ id: UInt32, _ code: UInt16, _ report: Bool) {
        if repeatID == id { stopRepeat() }
        if report { onKeyUp(code) }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        repeatID = nil
    }

    static func flags(_ carbon: Int) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if carbon & shiftKey != 0 { f.insert(.shift) }
        if carbon & optionKey != 0 { f.insert(.option) }
        if carbon & cmdKey != 0 { f.insert(.command) }
        if carbon & controlKey != 0 { f.insert(.control) }
        return f
    }
}
