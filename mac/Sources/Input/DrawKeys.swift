import AppKit
import Carbon

// ================= 드로잉 키·막기 키를 드로잉 중에만 전역 단축키로 =================
// 판은 키 창이 되지 않으므로 키보드 이벤트가 오지 않는다. 대신 드로잉 키(draw)와 막기 키(block)를
// Carbon 단축키로 등록해 두었다가 드로잉을 끄는 순간 모두 푼다 (표는 KeyMap). 풀리지 않으면 시스템 전체에서
// 그 글자를 칠 수 없게 되므로, 끈 뒤에 이 키가 한 번이라도 들어오면 그 자리에서 전부 풀고 기록에 남긴다.
@MainActor final class DrawKeys {
    var onKey: (_ code: UInt16, _ flags: NSEvent.ModifierFlags, _ isRepeat: Bool) -> Void = { _, _, _ in }
    var onKeyUp: (_ code: UInt16) -> Void = { _ in }
    var isDrawing: () -> Bool = { false }
    // 막기 묶음에서 뺄 조합 (앱 묶음의 F8·F9 등 — AppDelegate가 채운다)
    var blockExcluding: () -> Set<HotkeyNotation.Combo> = { [] }

    let registry: HotKeyRegistry
    var ids: [UInt32] { registry.ids(.draw) }
    var blockIDs: [UInt32] { registry.ids(.block) }
    // 끈 뒤 남은 드로잉·막기 등록 수. Esc로 끌 때 잠깐 남기는 Esc 하나(lingerEsc)는 세지 않는다.
    var left: Int { registry.count(.draw) + registry.count(.block) - (escLingerID == nil ? 0 : 1) }
    init(registry: HotKeyRegistry = .shared) { self.registry = registry }
    private var repeatID: UInt32?
    private var repeatTimer: Timer?
    private var loggedRepeat = false
    // Esc로 끌 때: 누르고 있는 Esc의 반복·뗌이 뒤 앱(키노트 쇼)으로 새어 쇼가 끝나지 않게, Esc 하나만 뗄 때까지(최대 0.5초) 남긴다.
    private var escID: UInt32?
    private(set) var escLingerID: UInt32?
    private var lingerTimer: Timer?
    private(set) var lastOnMs = 0.0

    var isRegistered: Bool { !ids.isEmpty }

    // 드로잉 묶음 → 막기 묶음 순서로 등록한다. 드로잉 묶음이 하나라도 실패하면 등록부가 묶음 전체를 되돌리고
    // 막기 묶음은 등록하지 않는다. 막기 묶음은 실패한 조합(다른 앱이 쓰는 것)만 빠진다.
    @discardableResult
    func registerAll() -> HotKeyGroupResult {
        finishEscLinger()
        guard ids.isEmpty else { return HotKeyGroupResult(registered: ids) }
        loggedRepeat = false
        let t0 = Date.timeIntervalSinceReferenceDate
        var entries: [HotKeyEntry] = []
        for k in KeyMap.drawKeys {
            let code = UInt16(k.combo.code), flags = DrawKeys.flags(k.combo.mods)
            entries.append(HotKeyEntry(name: "draw-\(code)+\(k.combo.mods)", combo: k.combo,
                                       press: { [weak self] id in self?.pressed(id, code, flags, k.repeats) },
                                       release: { [weak self] id in self?.released(id, code, k.release) }))
        }
        let r = registry.registerGroup(.draw, entries, policy: .allOrNothing)
        guard r.ok else { return r }
        escID = zip(KeyMap.drawKeys, r.registered).first { $0.0.combo.code == KeyMap.escCode }?.1
        let blocks = KeyMap.blockKeys(excluding: blockExcluding()).map { c in
            HotKeyEntry(name: "block-\(c.code)+\(c.mods)", combo: c, press: { [weak self] _ in self?.blockedPress(c.code) })
        }
        let b = registry.registerGroup(.block, blocks, policy: .skipFailures)
        lastOnMs = (Date.timeIntervalSinceReferenceDate - t0) * 1000
        Log.log("HK", "groups on ms=\(Int(lastOnMs.rounded())) draw=\(r.registered.count) block=\(b.registered.count) blockSkipped=\(b.failed.count) total=\(registry.count)")
        if lastOnMs > 100 { Log.log("HK", "SLOW groups on took \(Int(lastOnMs.rounded()))ms (over 100ms)") }
        return r
    }

    // 두 묶음을 모두 푼다. lingerEsc: Esc로 끄는 경우 — Esc 하나만 뗄 때까지 남긴다.
    @discardableResult
    func unregisterAll(lingerEsc: Bool = false) -> (removed: Int, errors: Int) {
        stopRepeat()
        finishEscLinger()
        var removed = 0, errors = 0
        if lingerEsc, let esc = escID, registry.ids(.draw).contains(esc) {
            for id in registry.ids(.draw) + registry.ids(.block) where id != esc {
                if registry.unregister(id) != noErr { errors += 1 }
                removed += 1
            }
            escLingerID = esc
            lingerTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.finishEscLinger() }
            }
            Log.log("HK", "drawkeys off removed=\(removed) errors=\(errors) escLinger=1 left=\(registry.count)")
            return (removed, errors)
        }
        let a = registry.unregisterGroup(.draw), b = registry.unregisterGroup(.block)
        escID = nil
        removed = a.removed + b.removed; errors = a.errors + b.errors
        if removed > 0 { Log.log("HK", "drawkeys off removed=\(removed) errors=\(errors) left=\(registry.count)") }
        return (removed, errors)
    }

    // 남겨 둔 Esc를 푼다 (뗐을 때, 0.5초가 지났을 때, 다시 켤 때)
    func finishEscLinger() {
        guard escLingerID != nil else { return }
        lingerTimer?.invalidate(); lingerTimer = nil
        escLingerID = nil
        escID = nil
        registry.unregisterGroup(.draw)
        Log.log("HK", "esc linger done left=\(registry.count)")
    }

    // 막기 키: 드로잉 중에는 아무것도 안 한다. 끈 뒤에 들어오면 STRAY.
    private func blockedPress(_ code: Int) {
        guard isDrawing() else { strayRelease("block key \(code)"); return }
    }

    private func strayRelease(_ what: String) {
        Log.log("HK", "STRAY \(what) while drawing is off — unregistering all")
        unregisterAll()
    }

    private func pressed(_ id: UInt32, _ code: UInt16, _ flags: NSEvent.ModifierFlags, _ repeats: Bool) {
        guard isDrawing() else {
            if escLingerID == id { return }          // 끈 직후 누르고 있는 Esc의 반복: 삼키고 뒤 앱에 넘기지 않는다
            strayRelease("draw key \(code)")
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
        if escLingerID == id { finishEscLinger(); return }   // Esc를 뗐다: 이제 두 번째 Esc는 그대로 쇼로 간다
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
