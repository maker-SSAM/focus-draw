import Carbon

// 어디서나 쓰는 단축키. Carbon의 전역 단축키는 "손쉬운 사용" 권한 없이 동작한다.
// 누름과 뗌을 둘 다 받고, 등록 결과(OSStatus)를 돌려준다. 드로잉 키처럼 잠깐만 쓰는 것은 풀 수 있다.
//   흔한 실패: -9878 이미 다른 앱이 쓰는 조합, -9868 macOS 15.0~15.1이 거절한 ⌥ 조합
enum HotKeys {
    private struct Entry {
        var ref: EventHotKeyRef?
        var name: String
        var press: () -> Void
        var release: (() -> Void)?
    }
    private static var entries: [UInt32: Entry] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false

    static var count: Int { entries.count }

    @discardableResult
    static func register(keyCode: Int, modifiers: Int = 0, name: String, quiet: Bool = false,
                         onRelease: (() -> Void)? = nil, _ press: @escaping () -> Void) -> (id: UInt32, status: OSStatus) {
        installIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let st = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: OSType(0x4644_5257), id: id),
                                     GetApplicationEventTarget(), 0, &ref)
        if st == noErr { entries[id] = Entry(ref: ref, name: name, press: press, release: onRelease) }
        if !quiet || st != noErr { Diag.log("HK", "reg \(name) status=\(st)") }
        return (id, st)
    }

    @discardableResult
    static func unregister(_ id: UInt32) -> OSStatus {
        guard let e = entries.removeValue(forKey: id) else { return noErr }
        return e.ref.map(UnregisterEventHotKey) ?? noErr
    }

    private static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let id = hk.id
            DispatchQueue.main.async { HotKeys.fire(id, pressed: pressed) }
            return noErr
        }, 2, &specs, nil, nil)
    }

    private static func fire(_ id: UInt32, pressed: Bool) {
        guard let e = entries[id] else { return }
        if pressed { e.press() } else { e.release?() }
    }
}
