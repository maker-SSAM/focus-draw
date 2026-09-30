import AppKit

// ================= 시스템 커서 숨기기 =================
// 우리 앱이 뒤에 있을 때(드로잉 중, 강조 중)는 공개 API로 커서를 숨길 수 없다. 비공개 연결 속성
// "SetsCursorInBackground"를 켠 뒤 CGDisplayHideCursor를 부른다 (권한 필요 없음, Cursorcerer 등이 쓰는 방법).
// 숨김/보임은 짝이 맞아야 하므로 이유(board·spot)를 모아 한 곳에서만 부른다.
enum CursorReason: String { case board, spot }

enum SystemCursor {
    private static var reasons: Set<CursorReason> = []
    private(set) static var hidden = false
    private static var backgroundReady: Bool?
    // 부른 횟수: Hide는 부른 만큼 Show를 불러야 보인다. 짝이 어긋나면 커서가 영영 안 돌아오므로 센다.
    private(set) static var hideCalls = 0
    private(set) static var showCalls = 0
    private(set) static var rehides = 0        // 시스템이 커서를 다시 보이게 한 것을 다시 숨긴 횟수
    private static var pendingHides = 0        // 지금 부른 Hide 중 아직 Show로 갚지 않은 수
    private static var lastReassert = Date.distantPast
    // 자체 점검이 가짜 커서 상태를 쓰게: 화면이 실제로 커서를 보이는가
    static var systemVisible: () -> Bool = { Log.cursorVisible == 1 } // 못 찾으면(-1) 보인다고 치지 않는다
    static var hideAction: () -> Void = { CGDisplayHideCursor(CGMainDisplayID()) }
    static var showAction: () -> Void = { CGDisplayShowCursor(CGMainDisplayID()) }

    static var testMode = false                // 자체 점검이 비공개 API를 부르지 않게
    static var callSummary: String { "hide=\(hideCalls)/show=\(showCalls)/rehide=\(rehides)" }
    static var balanced: Bool { pendingHides == 0 }

    static func hide(_ reason: CursorReason) { reasons.insert(reason); apply() }
    static func show(_ reason: CursorReason) { reasons.remove(reason); apply() }
    static func showAll() { reasons = []; apply() }

    private static func apply() {
        let want = !reasons.isEmpty
        guard want != hidden else { return }
        if want {
            let bg = testMode ? false : enableBackground()
            doHide()
            hidden = true
            Log.log("CURSOR", "hide reasons=\(reasons.map(\.rawValue).sorted()) background=\(bg)")
        } else {
            // 부른 만큼 되돌리고, 그래도 안 보이면(시스템이 셈을 어긋나게 했다) 보일 때까지 더 부른다
            while pendingHides > 0 { doShow() }
            var extra = 0
            while !systemVisible(), extra < 8 { doShow(); extra += 1 }
            hidden = false
            Log.log("CURSOR", "show calls=\(callSummary) extra=\(extra) visible=\(systemVisible())")
        }
    }

    // 다시 숨기기 (D5): 숨기고 싶은데 시스템이 커서를 다시 보이게 했으면(앞 앱·데스크톱이 바뀌거나 Dock을 지나면 그렇다) 다시 숨긴다.
    // 마우스가 움직일 때 부르므로 0.25초에 한 번까지만 본다. 쉬는 동안 타이머는 없다.
    static func reassert(now: Date = Date()) {
        guard hidden, now.timeIntervalSince(lastReassert) >= 0.25 else { return }
        lastReassert = now
        guard systemVisible() else { return }
        if !testMode { _ = enableBackground() }
        doHide()
        rehides += 1
        Log.log("CURSOR", "rehide n=\(rehides)")
    }

    private static func doHide() { hideAction(); hideCalls += 1; pendingHides += 1 }
    private static func doShow() { showAction(); showCalls += 1; pendingHides = max(0, pendingHides - 1) }

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
            Log.log("CURSOR", "private API not found")
            backgroundReady = false
            return false
        }
        let cid = conn()
        let err = setProp(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        Log.log("CURSOR", "SetsCursorInBackground err=\(err)")
        backgroundReady = err == 0
        return err == 0
    }
}
