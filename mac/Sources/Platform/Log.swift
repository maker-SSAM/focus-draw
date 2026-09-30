import AppKit
import Carbon

// 진단 기록: ~/Library/Logs/Focus & Draw/diag.log
// 스크린샷 없이도 "우리 창이 화면에 떠 있었는가, 키가 어디로 갔는가"를 나중에 읽을 수 있게 남긴다.
//   켜기: FocusDraw --diag, 또는 메뉴 막대 › 진단 기록 (켜 두면 다시 실행해도 이어서 기록)
//   한 줄 = "시각 꼬리표 내용". 꼬리표: SESSION SYS SCREEN MARK EXP DRAW KEY HK CURSOR APP FRONT SPACE WIN POWER SAMPLE SPOT WIDGET
//   키는 키 자리 번호(keyCode)만 적는다 — 무슨 글자를 쳤는지는 남기지 않는다.
//   화면 기록 권한이 필요 없는 정보만 쓴다 (CGWindowList의 창 제목은 읽지 않는다).
enum Log {
    static var folder: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Focus & Draw", isDirectory: true)
    }
    static var defaultURL: URL { folder.appendingPathComponent("diag.log") }

    private(set) static var isOn = false
    private static var handle: FileHandle?
    private static var observers: [NSObjectProtocol] = []
    private static var sampler: Timer?
    private static let maxBytes: UInt64 = 5_000_000

    // 앱 쪽 상태를 한 줄로 알려 주는 곳 (AppDelegate가 채운다)
    static var appState: () -> String = { "" }
    static var inkWindowNumbers: () -> [Int] = { [] }
    // 판 말고도 "지금 데스크톱에 떠 있는가"를 볼 창: ("spot", 번호), ("widget", 번호)
    static var otherWindows: () -> [(String, Int)] = { [] }
    // 1초 사이에 받은 입력 수 (C안에서 비활성 창이 마우스 이동을 받는지 보려고)
    static var moves = 0
    static var keys = 0
    private static var lastSecure: Bool?
    private static var lastInput = ""
    private static var lastScreens = ""
    private static var sameScreens = 0

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    // ---------- 켜고 끄기 ----------
    static var wanted: Bool {
        get { UserDefaults.standard.bool(forKey: "diag.on") }
        set { UserDefaults.standard.set(newValue, forKey: "diag.on") }
    }

    static func start(at url: URL = defaultURL, reason: String) {
        guard !isOn else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // 너무 커지면 한 번 밀어 둔다 (diag.1.log). 수업 몇 번 분량이면 5MB를 넘지 않는다.
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? UInt64, size > maxBytes {
            let old = url.deletingPathExtension().appendingPathExtension("1.log")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: url, to: old)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        h.seekToEndOfFile()
        handle = h
        isOn = true
        log("SESSION", "start reason=\(reason)")
        writeSystemInfo()
        installObservers()
    }

    static func stop() {
        guard isOn else { return }
        log("SESSION", "stop")
        setActive(false)
        for o in observers {
            NotificationCenter.default.removeObserver(o)
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        observers = []
        try? handle?.close()
        handle = nil
        isOn = false
    }

    static func log(_ tag: String, _ msg: String) {
        guard isOn, let h = handle else { return }
        let line = "\(stamp.string(from: Date())) \(tag) \(msg)\n"
        h.write(line.data(using: .utf8)!)
    }

    // 강조나 드로잉이 켜져 있는 동안만 1초마다 상태를 적는다 (쉬는 동안에는 타이머 없음)
    static func setActive(_ on: Bool) {
        if on && isOn {
            guard sampler == nil else { return }
            let t = Timer(timeInterval: 1, repeats: true) { _ in sample() }
            RunLoop.main.add(t, forMode: .common)
            sampler = t
            sample()
        } else {
            sampler?.invalidate()
            sampler = nil
        }
    }

    // ---------- 시스템·화면 ----------
    static func writeSystemInfo() {
        let info = Bundle.main.infoDictionary
        log("SYS", "macOS=\(ProcessInfo.processInfo.operatingSystemVersionString) model=\(sysctlString("hw.model")) "
            + "arch=\(machineArch) app=\(info?["CFBundleShortVersionString"] ?? "?") experiments=\(Experiments.enabled) "
            + "path=\(Bundle.main.bundlePath.contains("/AppTranslocation/") ? "translocated" : Bundle.main.bundlePath)")
        log("SYS", "separateSpaces=\(NSScreen.screensHaveSeparateSpaces) input=\(inputSourceID()) secure=\(IsSecureEventInputEnabled())")
        log("EXP", Experiments.summary)
        writeScreens()
    }

    // 화면 구성이 정말 바뀐 알림만 자세히 적는다. 같은 알림이 쏟아지면(키노트 쇼 시작·끝) 2초 뒤 한 줄로 센다
    // — S1 집 시험 기록 9,008줄 중 5,009줄이 이 알림이었다.
    private static func screenNotice() {
        if screenSignature() != lastScreens {
            flushSameScreens()
            log("SCREEN", "changed n=\(NSScreen.screens.count)")
            writeScreens()
            return
        }
        sameScreens += 1
        if sameScreens == 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { flushSameScreens() }
        }
    }

    private static func flushSameScreens() {
        guard sameScreens > 0 else { return }
        let edr = NSScreen.screens.map { String(format: "%.2f", $0.maximumExtendedDynamicRangeColorComponentValue) }
        log("SCREEN", "same x\(sameScreens) (알림만 오고 화면 구성은 그대로) visible=\(r(NSScreen.main?.visibleFrame ?? .zero)) "
            + "edr=\(edr.joined(separator: ","))")
        sameScreens = 0
    }

    static func writeScreens() {
        lastScreens = screenSignature()
        for (i, s) in NSScreen.screens.enumerated() {
            let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            var uuid = "?"
            if let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
                uuid = CFUUIDCreateString(nil, u) as String
            }
            let mirrorOf = CGDisplayMirrorsDisplay(id)
            log("SCREEN", "#\(i) id=\(id) uuid=\(uuid) name=\"\(s.localizedName)\" frame=\(r(s.frame)) visible=\(r(s.visibleFrame)) "
                + "scale=\(s.backingScaleFactor) px=\(CGDisplayPixelsWide(id))x\(CGDisplayPixelsHigh(id)) "
                + "main=\(CGDisplayIsMain(id) != 0) builtin=\(CGDisplayIsBuiltin(id) != 0) "
                + "mirrorSet=\(CGDisplayIsInMirrorSet(id) != 0) mirrors=\(mirrorOf == kCGNullDirectDisplay ? "-" : String(mirrorOf))")
        }
    }

    // ---------- 1초마다 ----------
    static func sample() {
        guard isOn else { return }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        let key = NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "-"
        let secure = IsSecureEventInputEnabled()
        if secure != lastSecure { log("KEY", "secureInput=\(secure)"); lastSecure = secure }
        let input = inputSourceID()
        if input != lastInput { log("KEY", "inputSource=\(input)"); lastInput = input }
        log("SAMPLE", "\(appState()) front=\(front) active=\(NSApp.isActive ? 1 : 0) key=\(key) "
            + "cgCursorVisible=\(cursorVisible) moves=\(moves) keys=\(keys) \(windowReport())")
        moves = 0
        keys = 0
    }

    // 우리 판 창이 정말 화면에 떠 있는지, 그 위에 다른 앱 창이 있는지 (창 제목은 읽지 않음)
    static func windowReport() -> String {
        let ink = Set(inkWindowNumbers())
        let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        // 강조 원·위젯도 지금 데스크톱에 떠 있는지 (S1 집 시험: 전체 화면 데스크톱에서 강조가 안 보임)
        var others: [String] = []
        for (name, n) in otherWindows() {
            let info = all.first { ($0[kCGWindowNumber as String] as? Int) == n }
            let on = (info?[kCGWindowIsOnscreen as String] as? Bool) == true
            let space = NSApp.window(withWindowNumber: n).map { $0.isOnActiveSpace ? 1 : 0 } ?? -1
            others.append("\(name)=[on=\(on ? 1 : 0) space=\(space)]")
        }
        let tail = others.isEmpty ? "" : " " + others.joined(separator: " ")
        guard !ink.isEmpty else { return "ink=[]" + tail }
        let onscreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        var parts: [String] = []
        for w in all {
            guard let n = w[kCGWindowNumber as String] as? Int, ink.contains(n) else { continue }
            let on = (w[kCGWindowIsOnscreen as String] as? Bool) == true
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let win = NSApp.window(withWindowNumber: n)
            let vis = win.map { $0.occlusionState.contains(.visible) ? 1 : 0 } ?? -1
            let space = win.map { $0.isOnActiveSpace ? 1 : 0 } ?? -1
            parts.append("#\(n) on=\(on ? 1 : 0) L=\(layer) vis=\(vis) space=\(space) "
                         + "(\(Int(b["X"] ?? 0)),\(Int(b["Y"] ?? 0)),\(Int(b["Width"] ?? 0)),\(Int(b["Height"] ?? 0)))")
        }
        // 화면에 보이는 창을 앞에서부터: 우리 판보다 앞에 있는 다른 앱 창(주인:레벨)
        var above: [String] = []
        for w in onscreen {
            if let n = w[kCGWindowNumber as String] as? Int, ink.contains(n) { break }
            let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
            let opid = w[kCGWindowOwnerPID as String] as? Int ?? 0
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            if opid == pid { continue }
            let tag = "\(owner):\(layer)"
            if !above.contains(tag) { above.append(tag) }
            if above.count >= 6 { break }
        }
        let inFront = onscreen.contains { ink.contains($0[kCGWindowNumber as String] as? Int ?? -1) }
        return "ink=[\(parts.joined(separator: "; "))] inkOnscreenList=\(inFront ? 1 : 0) above=[\(above.joined(separator: ","))]" + tail
    }

    // ---------- 알림 ----------
    private static func installObservers() {
        let nc = NotificationCenter.default
        let ws = NSWorkspace.shared.notificationCenter
        func on(_ c: NotificationCenter, _ name: Notification.Name, _ f: @escaping (Notification) -> Void) {
            observers.append(c.addObserver(forName: name, object: nil, queue: .main, using: f))
        }
        on(nc, NSApplication.didBecomeActiveNotification) { _ in log("APP", "active") }
        on(nc, NSApplication.didResignActiveNotification) { _ in log("APP", "resign") }
        on(nc, NSApplication.didChangeScreenParametersNotification) { _ in screenNotice() }
        on(ws, NSWorkspace.didActivateApplicationNotification) { n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            log("FRONT", app?.bundleIdentifier ?? "?")
        }
        on(ws, NSWorkspace.activeSpaceDidChangeNotification) { _ in log("SPACE", "changed") }
        on(ws, NSWorkspace.willSleepNotification) { _ in log("POWER", "willSleep") }
        on(ws, NSWorkspace.didWakeNotification) { _ in log("POWER", "didWake") }
        on(ws, NSWorkspace.screensDidSleepNotification) { _ in log("POWER", "screensSleep") }
        on(ws, NSWorkspace.screensDidWakeNotification) { _ in log("POWER", "screensWake") }
        on(ws, NSWorkspace.sessionDidResignActiveNotification) { _ in log("POWER", "sessionResign") }
        on(ws, NSWorkspace.sessionDidBecomeActiveNotification) { _ in log("POWER", "sessionActive") }
        func inkEvent(_ name: Notification.Name, _ what: @escaping (NSWindow) -> String) {
            on(nc, name) { n in
                guard let w = n.object as? NSWindow, w.contentView is InkView else { return }
                log("WIN", "#\(w.windowNumber) \(what(w))")
            }
        }
        inkEvent(NSWindow.didBecomeKeyNotification) { _ in "becameKey" }
        inkEvent(NSWindow.didResignKeyNotification) { _ in "resignedKey" }
        inkEvent(NSWindow.didChangeOcclusionStateNotification) { w in "visible=\(w.occlusionState.contains(.visible))" }
    }

    // ---------- 작은 도구 ----------
    // CGCursorIsVisible은 Swift에서 막혀 있지만 아직 들어 있다 (1 보임 / 0 숨김 / -1 찾지 못함)
    private static let cursorVisibleFn: (@convention(c) () -> Int32)? = {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGCursorIsVisible") else { return nil }
        return unsafeBitCast(p, to: (@convention(c) () -> Int32).self)
    }()
    static var cursorVisible: Int { cursorVisibleFn.map { $0() != 0 ? 1 : 0 } ?? -1 }

    static func sysctlString(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "?" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buf, &size, nil, 0)
        return String(cString: buf)
    }

    static var machineArch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    static func inputSourceID() -> String {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return "?" }
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }

    static func r(_ rect: CGRect) -> String {
        "(\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height)))"
    }
}
