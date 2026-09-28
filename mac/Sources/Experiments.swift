import AppKit
import Carbon

// ================= 시험용 스위치 (S1b) =================
// 개발 빌드(build.sh 기본·--quick)에만 메뉴 막대 › "실험" 메뉴가 생긴다. 배포 빌드(--release)는 늘 기본값(B안)이다.
// 선생님은 재시험 목록(mac/spikes/checklist-2.md)의 항목(R1~R5)을 메뉴에서 고르기만 하면 된다 —
// 그 항목에 맞는 스위치가 한꺼번에 켜지고, 진단 기록에 "MARK 항목 R1"이 남는다.
// 드로잉을 켤 때마다 커서 옆에 "R1 · C안"처럼 지금 안이 2초 뜬다 (S1 집 시험은 항목을 안 고른 채 모두 B안으로 돌았다).
//
// 키 받기 방식
//   B안: 드로잉을 켜면 우리 앱이 앞으로 나와 모든 키를 받는다 (지금 방식). 끌 때 macOS 14+의 양보 방식으로 돌려준다.
//   A안: 앱을 앞으로 부르지 않고, 판(비활성 패널)이 키 창이 되어 키를 받는다.
//   C안: 앱도 판도 키를 받지 않는다. 드로잉 키만 드로잉 중에 전역 단축키(Carbon)로 잡고, 나머지 키(→, PageDown,
//        리모컨, B)는 발표 앱으로 그대로 간다 — Windows 판(NOACTIVATE)과 같은 방식.

enum KeyMode: String, CaseIterable {
    case b = "B", a = "A", c = "C"
    var title: String {
        switch self {
        case .b: return "B안: 앱을 앞으로 (지금 방식)"
        case .a: return "A안: 비활성 판이 키 창"
        case .c: return "C안: 드로잉 키만 단축키로"
        }
    }
}

enum WindowBehavior: String, CaseIterable {
    case current, noStationary, joinAllApps
    var title: String {
        switch self {
        case .current: return "지금 조합 (+stationary +fullScreenAuxiliary)"
        case .noStationary: return ".stationary 뺌"
        case .joinAllApps: return ".canJoinAllApplications"
        }
    }
    var flags: NSWindow.CollectionBehavior {
        switch self {
        case .current: return [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        case .noStationary: return [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        case .joinAllApps: return [.canJoinAllSpaces, .canJoinAllApplications, .ignoresCycle]
        }
    }
}

struct ExperimentPreset {
    let id: String
    let title: String
    var key: KeyMode = .c
    var panel = true            // B안에서 판을 NSPanel로 (A·C안은 늘 패널)
    var behavior: WindowBehavior = .current
    var boardCursor = true      // 붓 동그라미를 판에 직접 그리고 시스템 커서를 숨긴다
    var hideSpotCursor = false  // 강조 중 커서 숨기기 (비공개 API)
}

enum Experiments {
    #if EXPERIMENTS
    static let enabled = true
    #else
    static let enabled = false
    #endif

    // 자체 점검·속도 측정은 사용자의 스위치를 건드리지 않도록 메모리에만 적는다
    static var memoryOnly: [String: String]? = nil
    static var onChange: () -> Void = {}

    private static func value(_ k: String) -> String? {
        guard enabled || memoryOnly != nil else { return nil }
        return memoryOnly != nil ? memoryOnly![k] : UserDefaults.standard.string(forKey: "exp." + k)
    }
    private static func store(_ k: String, _ v: String?) {
        if memoryOnly != nil { memoryOnly![k] = v } else { UserDefaults.standard.set(v, forKey: "exp." + k) }
    }

    static var keyMode: KeyMode { KeyMode(rawValue: value("key") ?? "") ?? .b }
    static var panelInB: Bool { value("panel") == "1" }
    static var behavior: WindowBehavior { WindowBehavior(rawValue: value("behavior") ?? "") ?? .current }
    static var boardCursor: Bool { value("cursor") == "board" }
    static var hideSpotCursor: Bool { value("spotHide") == "1" }
    static var item: String? { value("item") }

    static var collectionBehavior: NSWindow.CollectionBehavior { behavior.flags }

    static var summary: String {
        "item=\(item ?? "-") key=\(keyMode.rawValue) inkWindow=\(keyMode == .b && !panelInB ? "NSWindow" : "NSPanel") "
            + "behavior=\(behavior.rawValue) cursor=\(boardCursor ? "board" : "system") spotHide=\(hideSpotCursor ? 1 : 0)"
    }

    // 드로잉을 켤 때 커서 옆에 잠깐 뜨는 이름: "R1 · C안", 항목을 안 골랐으면 "항목 없음 · B안"
    static var label: String { "\(item ?? "항목 없음") · \(keyMode.rawValue)안" }

    static func apply(_ p: ExperimentPreset?) {
        let p = p ?? ExperimentPreset(id: "", title: "", key: .b, panel: false, behavior: .current, boardCursor: false)
        store("key", p.key.rawValue)
        store("panel", p.panel ? "1" : "0")
        store("behavior", p.behavior.rawValue)
        store("cursor", p.boardCursor ? "board" : "system")
        store("spotHide", p.hideSpotCursor ? "1" : "0")
        store("item", p.id.isEmpty ? nil : p.id)
        Diag.log("MARK", p.id.isEmpty ? "실험 끝 (기본값)" : "항목 \(p.id) — \(p.title)")
        changed()
    }

    private static func change(_ k: String, _ v: String) {
        store(k, v)
        store("item", nil)
        changed()
    }

    private static func changed() {
        Diag.log("EXP", summary)
        onChange()
    }

    // 재시험 목록(mac/spikes/checklist-2.md)의 항목과 같다. 첫 집 시험(checklist.md)의 B안 결과는 이미 있으므로
    // B안 항목은 두지 않는다. 판 커서(판에 직접 그리기)는 D3 규칙대로 모두 켠다(포인터 크기를 따라 커지는 것이 확인됨).
    static let presets: [ExperimentPreset] = [
        ExperimentPreset(id: "R1", title: "C안 (재시험 대부분)"),
        ExperimentPreset(id: "R2", title: "A안 · 키노트만", key: .a),
        ExperimentPreset(id: "R3", title: "C안 · 창 동작 .stationary 뺌", behavior: .noStationary),
        ExperimentPreset(id: "R4", title: "C안 · 창 동작 canJoinAllApplications", behavior: .joinAllApps),
        ExperimentPreset(id: "R5", title: "C안 · 강조 중 커서 숨기기", hideSpotCursor: true),
    ]

    // ---------- 메뉴 ----------
    static func appendMenu(to menu: NSMenu) {
        guard enabled else { return }
        let root = NSMenu()
        let top = NSMenuItem(title: "실험 (\(item.map { "항목 " + $0 } ?? summaryShort))", action: nil, keyEquivalent: "")
        top.submenu = root

        let items = NSMenu()
        for p in presets {
            items.addItem(ActionItem("\(p.id) · \(p.title)", on: item == p.id) { apply(p) })
        }
        let itemsTop = NSMenuItem(title: "재시험 항목 고르기", action: nil, keyEquivalent: "")
        itemsTop.submenu = items
        root.addItem(itemsTop)
        root.addItem(ActionItem("실험 끝 — 모두 기본값으로") { apply(nil) })
        root.addItem(.separator())

        func sub(_ title: String, _ build: (NSMenu) -> Void) {
            let m = NSMenu()
            build(m)
            let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            it.submenu = m
            root.addItem(it)
        }
        sub("키 받기") { m in
            for k in KeyMode.allCases { m.addItem(ActionItem(k.title, on: keyMode == k) { change("key", k.rawValue) }) }
        }
        sub("판 창 종류 (B안에서만)") { m in
            m.addItem(ActionItem("NSWindow", on: !panelInB) { change("panel", "0") })
            m.addItem(ActionItem("NSPanel", on: panelInB) { change("panel", "1") })
        }
        sub("창 동작 조합") { m in
            for b in WindowBehavior.allCases { m.addItem(ActionItem(b.title, on: behavior == b) { change("behavior", b.rawValue) }) }
        }
        sub("붓 커서") { m in
            m.addItem(ActionItem("시스템 커서 (NSCursor)", on: !boardCursor) { change("cursor", "system") })
            m.addItem(ActionItem("판에 직접 그리기 + 시스템 커서 숨김", on: boardCursor) { change("cursor", "board") })
        }
        root.addItem(ActionItem("강조 중 커서 숨기기", on: hideSpotCursor) { change("spotHide", hideSpotCursor ? "0" : "1") })
        root.addItem(.separator())
        let info = NSMenuItem(title: summary, action: nil, keyEquivalent: "")
        info.isEnabled = false
        root.addItem(info)
        menu.addItem(top)
    }

    private static var summaryShort: String { "\(keyMode.rawValue)안" }
}

// 누르면 클로저를 부르는 메뉴 항목
final class ActionItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, on: Bool = false, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = on ? .on : .off
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
}

// ================= 시스템 커서 숨기기 =================
// 우리 앱이 뒤에 있을 때(C안, 강조 중)는 공개 API로 커서를 숨길 수 없다. 비공개 연결 속성
// "SetsCursorInBackground"를 켠 뒤 CGDisplayHideCursor를 부른다 (권한 필요 없음, Cursorcerer 등이 쓰는 방법).
// 숨김/보임은 짝이 맞아야 하므로 이유(board·spot)를 모아 한 곳에서만 부른다.
enum SystemCursor {
    private static var reasons: Set<String> = []
    private(set) static var hidden = false
    private static var backgroundReady: Bool?

    static func hide(_ reason: String) { reasons.insert(reason); apply() }
    static func show(_ reason: String) { reasons.remove(reason); apply() }
    static func showAll() { reasons = []; apply() }

    private static func apply() {
        let want = !reasons.isEmpty
        guard want != hidden else { return }
        if want {
            let bg = enableBackground()
            let r = CGDisplayHideCursor(CGMainDisplayID())
            hidden = true
            Diag.log("CURSOR", "hide reasons=\(reasons.sorted()) background=\(bg) result=\(r.rawValue)")
        } else {
            let r = CGDisplayShowCursor(CGMainDisplayID())
            hidden = false
            Diag.log("CURSOR", "show result=\(r.rawValue)")
        }
    }

    typealias DefaultConnection = @convention(c) () -> Int32
    typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    // 비공개 함수를 찾을 수 있는지 (자체 점검용, 부르지는 않는다)
    static var privateAPIFound: Bool { lookup() != nil }

    private static func lookup() -> (DefaultConnection, SetProperty)? {
        let any = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        _ = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        func find(_ names: [String]) -> UnsafeMutableRawPointer? {
            for n in names { if let p = dlsym(any, n) { return p } }
            return nil
        }
        let conn = find(["_CGSDefaultConnection", "CGSMainConnectionID", "SLSMainConnectionID"])
        let prop = find(["CGSSetConnectionProperty", "SLSSetConnectionProperty"])
        guard let c = conn, let p = prop else { return nil }
        return (unsafeBitCast(c, to: DefaultConnection.self), unsafeBitCast(p, to: SetProperty.self))
    }

    private static func enableBackground() -> Bool {
        if let done = backgroundReady { return done }
        guard let (conn, setProp) = lookup() else {
            Diag.log("CURSOR", "private API not found")
            backgroundReady = false
            return false
        }
        let cid = conn()
        let err = setProp(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        Diag.log("CURSOR", "SetsCursorInBackground err=\(err)")
        backgroundReady = err == 0
        return err == 0
    }
}

// ================= C안: 드로잉 키를 드로잉 중에만 전역 단축키로 =================
// 판은 키 창이 되지 않으므로 키보드 이벤트가 오지 않는다. 대신 드로잉 키만 Carbon 단축키로 등록해 두었다가
// 드로잉을 끄는 순간 모두 푼다. 풀리지 않으면 시스템 전체에서 그 글자를 칠 수 없게 되므로,
// 끈 뒤에 드로잉 키가 한 번이라도 들어오면 그 자리에서 전부 풀고 기록에 남긴다.
final class CarbonDrawKeys {
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
            let flags = CarbonDrawKeys.flags(mods)
            let r = HotKeys.register(keyCode: Int(code), modifiers: mods, name: "draw-\(code)+\(mods)", quiet: true,
                                     onRelease: { [weak self] in self?.released(myID, code, release) }) { [weak self] in
                self?.pressed(myID, code, flags, repeats)
            }
            myID = r.id
            if r.status == noErr { ids.append(r.id) } else { failed += 1 }
        }
        for k in CarbonDrawKeys.digits + CarbonDrawKeys.letters + CarbonDrawKeys.edits { add(k) }
        for k: UInt16 in [6, 7, 8] { add(k, release: true); add(k, shiftKey, release: true) } // Z X C (⇧와 함께 눌러도)
        for m in [0, shiftKey, optionKey, optionKey | shiftKey] { add(24, m, repeats: true) } // = +  (⌥: 지우개)
        for k: UInt16 in [27, 69, 78] { add(k, repeats: true); add(k, optionKey, repeats: true) } // - 키패드+ 키패드-
        add(6, cmdKey); add(6, controlKey)                                                    // ⌘Z ⌃Z
        Diag.log("HK", "drawkeys on ok=\(ids.count) failed=\(failed) total=\(HotKeys.count)")
        return (ids.count, failed)
    }

    @discardableResult
    func unregisterAll() -> (removed: Int, errors: Int) {
        stopRepeat()
        var errors = 0
        let n = ids.count
        for id in ids where HotKeys.unregister(id) != noErr { errors += 1 }
        ids = []
        if n > 0 { Diag.log("HK", "drawkeys off removed=\(n) errors=\(errors) left=\(HotKeys.count)") }
        return (n, errors)
    }

    private func pressed(_ id: UInt32, _ code: UInt16, _ flags: NSEvent.ModifierFlags, _ repeats: Bool) {
        guard isDrawing() else {
            Diag.log("HK", "STRAY draw key \(code) while drawing is off — unregistering all")
            unregisterAll()
            return
        }
        if repeats, repeatID == id {
            // 시스템이 누르고 있는 키를 반복해서 보내 준다 → 우리 반복 타이머는 멈추고 그대로 쓴다
            if !loggedRepeat { Diag.log("KEY", "repeat=system code=\(code)"); loggedRepeat = true }
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
            if !self.loggedRepeat { Diag.log("KEY", "repeat=self code=\(code)"); self.loggedRepeat = true }
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
