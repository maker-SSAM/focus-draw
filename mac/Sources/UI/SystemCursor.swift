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

    static func hide(_ reason: CursorReason) { reasons.insert(reason); apply() }
    static func show(_ reason: CursorReason) { reasons.remove(reason); apply() }
    static func showAll() { reasons = []; apply() }

    private static func apply() {
        let want = !reasons.isEmpty
        guard want != hidden else { return }
        if want {
            let bg = enableBackground()
            let r = CGDisplayHideCursor(CGMainDisplayID())
            hidden = true
            Log.log("CURSOR", "hide reasons=\(reasons.map(\.rawValue).sorted()) background=\(bg) result=\(r.rawValue)")
        } else {
            let r = CGDisplayShowCursor(CGMainDisplayID())
            hidden = false
            Log.log("CURSOR", "show result=\(r.rawValue)")
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
