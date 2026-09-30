import AppKit

// ================= 시험용 스위치 =================
// S1의 실험(A·B안, 창 동작 조합, NSCursor 붓 커서, 재시험 항목)은 결론이 나서 모두 지웠다(S3a).
// 남은 것은 "강조 중 커서 숨기기" 하나 — 기본값은 선생님 결정 10까지 지금처럼 끔.
// 개발 빌드(build.sh 기본·--quick)에만 메뉴 막대 › "실험" 메뉴가 생긴다. 배포 빌드(--release)는 늘 기본값이다.
// 새 실험이 생기면 여기에 다시 항목을 더한다.
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

    static var hideSpotCursor: Bool { value("spotHide") == "1" } // 강조 중 커서 숨기기 (비공개 API)

    static var summary: String { "spotHide=\(hideSpotCursor ? 1 : 0)" }

    // ---------- 메뉴 ----------
    static func appendMenu(to menu: NSMenu) {
        guard enabled else { return }
        let sub = NSMenu()
        sub.addItem(ActionItem("강조 중 커서 숨기기", on: hideSpotCursor) {
            store("spotHide", hideSpotCursor ? "0" : "1")
            Log.log("EXP", summary)
            onChange()
        })
        let top = NSMenuItem(title: "실험", action: nil, keyEquivalent: "")
        top.submenu = sub
        menu.addItem(top)
    }
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
