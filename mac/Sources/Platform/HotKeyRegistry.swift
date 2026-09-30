import Carbon

// 어디서나 쓰는 단축키의 등록부. Carbon의 전역 단축키는 "손쉬운 사용" 권한 없이 동작한다.
// - 이름 붙인 묶음(app·draw·block)을 한꺼번에 등록·해제한다 (설계도 4절).
//     app   앱이 도는 동안 늘 (F8·F9 등)      draw  드로잉 중에만: 하나라도 실패하면 묶음 전체를 되돌린다
//     block 드로잉 중에만: 실패한 조합만 빼고 나머지는 등록 (S4가 채운다)
// - 같은 조합은 한 번만 등록한다. 두 번째 호출은 오류(-9878)를 받는다. (draw가 block보다 먼저 등록되므로 draw가 이긴다)
// - 등록 결과(OSStatus)를 돌려준다. 흔한 실패: -9878 이미 다른 앱이 쓰는 조합, -9868 시스템이 거절한 조합(macOS 15.0~15.1의 ⌥ 조합)
// - 아이디는 묶음마다 정해진 범위에서 차례로 준다 (app 1~, draw 100~, block 1000~). 묶음을 풀면 처음부터 다시 — 껐다 켜도 같은 번호다.
// - Carbon 호출은 HotKeyBackend 뒤에 있어서, 자체 점검이 가짜 백엔드로 실패 상황(-9868·-9878)을 흉내 낸다.

enum HotKeyGroup: String, CaseIterable {
    case app, draw, block
    var firstID: UInt32 {
        switch self { case .app: return 1; case .draw: return 100; case .block: return 1000 }
    }
}

let hotKeyExistsStatus = OSStatus(eventHotKeyExistsErr)   // -9878
let hotKeyRejectedStatus: OSStatus = -9868

// 등록 결과를 사람이 읽는 말로
func describeHotKeyStatus(_ st: OSStatus) -> String {
    switch st {
    case noErr: return "성공"
    case hotKeyExistsStatus: return "\(st) 다른 앱이 이미 사용 중"
    case hotKeyRejectedStatus: return "\(st) 시스템이 거절"
    default: return "\(st)"
    }
}

struct HotKeyEntry {
    var name: String
    var combo: HotkeyNotation.Combo
    var press: (UInt32) -> Void = { _ in }       // 받는 것: 이 항목의 아이디
    var release: ((UInt32) -> Void)? = nil
}

struct HotKeyGroupResult {
    var registered: [UInt32] = []
    var failed: [(name: String, status: OSStatus)] = []
    var ok: Bool { failed.isEmpty }
}

protocol HotKeyBackend: AnyObject {
    var onEvent: (_ id: UInt32, _ pressed: Bool) -> Void { get set }
    func register(_ combo: HotkeyNotation.Combo, id: UInt32) -> (token: Any?, status: OSStatus)
    func unregister(_ token: Any?) -> OSStatus
}

// 진짜 Carbon
final class CarbonHotKeyBackend: HotKeyBackend {
    var onEvent: (UInt32, Bool) -> Void = { _, _ in }
    private var installed = false
    private static weak var current: CarbonHotKeyBackend?

    func register(_ combo: HotkeyNotation.Combo, id: UInt32) -> (token: Any?, status: OSStatus) {
        installIfNeeded()
        var ref: EventHotKeyRef?
        let st = RegisterEventHotKey(UInt32(combo.code), UInt32(combo.mods), EventHotKeyID(signature: OSType(0x4644_5257), id: id),
                                     GetApplicationEventTarget(), 0, &ref)
        return (ref, st)
    }

    func unregister(_ token: Any?) -> OSStatus {
        guard let t = token else { return noErr }
        return UnregisterEventHotKey(t as! EventHotKeyRef)
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        CarbonHotKeyBackend.current = self
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let id = hk.id
            DispatchQueue.main.async { CarbonHotKeyBackend.current?.onEvent(id, pressed) }
            return noErr
        }, 2, &specs, nil, nil)
    }
}

final class HotKeyRegistry {
    static let shared = HotKeyRegistry()

    enum Policy { case allOrNothing, skipFailures }

    private struct Item {
        var id: UInt32
        var group: HotKeyGroup
        var entry: HotKeyEntry
        var token: Any?
    }
    private let backend: HotKeyBackend
    private var items: [UInt32: Item] = [:]
    private var nextID: [HotKeyGroup: UInt32] = [:]

    init(backend: HotKeyBackend = CarbonHotKeyBackend()) {
        self.backend = backend
        backend.onEvent = { [weak self] id, pressed in self?.fire(id, pressed: pressed) }
    }

    var count: Int { items.count }
    func count(_ group: HotKeyGroup) -> Int { items.values.filter { $0.group == group }.count }
    func ids(_ group: HotKeyGroup) -> [UInt32] { items.values.filter { $0.group == group }.map(\.id).sorted() }
    func isRegistered(_ combo: HotkeyNotation.Combo) -> Bool { items.values.contains { $0.entry.combo == combo } }

    // 한 조합을 등록한다. 이미 (어느 묶음에서든) 등록된 조합이면 등록하지 않고 -9878.
    @discardableResult
    func register(_ group: HotKeyGroup, _ entry: HotKeyEntry) -> (id: UInt32, status: OSStatus) {
        let id = allocateID(group)
        if isRegistered(entry.combo) {
            giveBackID(id, group)
            Log.log("HK", "reg \(group.rawValue)/\(entry.name) status=\(hotKeyExistsStatus) (같은 조합이 이미 등록됨)")
            return (id, hotKeyExistsStatus)
        }
        let r = backend.register(entry.combo, id: id)
        if r.status == noErr {
            items[id] = Item(id: id, group: group, entry: entry, token: r.token)
        } else {
            giveBackID(id, group)
        }
        if group == .app || r.status != noErr { Log.log("HK", "reg \(group.rawValue)/\(entry.name) status=\(r.status)") }
        return (id, r.status)
    }

    // 묶음을 한꺼번에 등록한다. allOrNothing이면 하나라도 실패할 때 이미 등록한 것까지 모두 되돌린다.
    @discardableResult
    func registerGroup(_ group: HotKeyGroup, _ entries: [HotKeyEntry], policy: Policy) -> HotKeyGroupResult {
        var result = HotKeyGroupResult()
        for e in entries {
            let r = register(group, e)
            if r.status == noErr { result.registered.append(r.id) } else { result.failed.append((e.name, r.status)) }
            if policy == .allOrNothing, !result.ok {
                let undone = unregisterGroup(group)
                result.registered = []
                Log.log("HK", "group \(group.rawValue) rolled back removed=\(undone.removed) first-failure=\(e.name) \(describeHotKeyStatus(r.status))")
                return result
            }
        }
        Log.log("HK", "group \(group.rawValue) on ok=\(result.registered.count) failed=\(result.failed.count) total=\(count)")
        return result
    }

    @discardableResult
    func unregister(_ id: UInt32) -> OSStatus {
        guard let it = items.removeValue(forKey: id) else { return noErr }
        return backend.unregister(it.token)
    }

    // 묶음을 풀고 아이디를 처음부터 다시 쓰게 한다. removed = 푼 개수, errors = 풀다가 실패한 개수
    @discardableResult
    func unregisterGroup(_ group: HotKeyGroup) -> (removed: Int, errors: Int) {
        var removed = 0, errors = 0
        for id in ids(group) {
            if unregister(id) != noErr { errors += 1 }
            removed += 1
        }
        nextID[group] = nil
        if removed > 0 { Log.log("HK", "group \(group.rawValue) off removed=\(removed) errors=\(errors) left=\(count)") }
        return (removed, errors)
    }

    // 종료할 때: 모든 묶음을 푼다
    func unregisterAll() { for g in HotKeyGroup.allCases { unregisterGroup(g) } }

    private func allocateID(_ group: HotKeyGroup) -> UInt32 {
        let id = nextID[group] ?? group.firstID
        nextID[group] = id + 1
        return id
    }

    // 실패한 등록이 아이디를 쓰지 않은 것으로 되돌린다 (마지막에 준 번호일 때만)
    private func giveBackID(_ id: UInt32, _ group: HotKeyGroup) {
        if nextID[group] == id + 1 { nextID[group] = id }
    }

    private func fire(_ id: UInt32, pressed: Bool) {
        guard let it = items[id] else { return }
        if pressed { it.entry.press(id) } else { it.entry.release?(id) }
    }

    // 자체 점검이 가짜 백엔드로 누름·뗌을 흉내 낸다
    func simulate(_ id: UInt32, pressed: Bool) { fire(id, pressed: pressed) }
}
