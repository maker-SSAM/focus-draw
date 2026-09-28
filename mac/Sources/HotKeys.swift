import Carbon

// 어디서나 쓰는 단축키. Carbon의 전역 단축키는 "손쉬운 사용" 권한 없이 동작한다.
enum HotKeys {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false

    static func register(keyCode: Int, modifiers: Int = 0, _ handler: @escaping () -> Void) {
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                let h = HotKeys.handlers[id.id]
                DispatchQueue.main.async { h?() }
                return noErr
            }, 1, &spec, nil, nil)
        }
        let id = UInt32(handlers.count + 1)
        handlers[id] = handler
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: OSType(0x4644_5257), id: id),
                            GetApplicationEventTarget(), 0, &ref)
    }
}
