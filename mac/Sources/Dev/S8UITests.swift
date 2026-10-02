import AppKit
import SwiftUI

// 설정 창 칸이 값이 바뀌면 다시 그려지는지 (--selftest 안에서만: 화면과 실행 고리가 필요하다)
@MainActor enum S8UITests {
    static func spin(_ t: TimeInterval = 0.4) { RunLoop.current.run(until: Date(timeIntervalSinceNow: t)) }

    static func bytes(_ v: NSView) -> Data? {
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    static func run(_ check: (String, Bool, String) -> Void, dir: URL) {
        let s = Settings.shared
        let saved = s.spotSize
        defer { s.spotSize = saved }
        s.spotSize = 130
        let field = SettingsLayout.Field(id: "Highlight.Size", label: "크기", suffix: "px", step: 5)
        let host = NSHostingView(rootView: NumberRow(field).padding(8).frame(width: 520))
        let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 520, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
        w.contentView = host
        w.orderFront(nil)
        spin(0.5)
        let before = bytes(host)

        let b = valueBinding("Highlight.Size")
        b.wrappedValue = 131            // −/+ 단추와 숫자 칸이 하는 일
        check("설정 칸: 값 쓰기가 설정에 닿음 (131)", s.spotSize == 131, "\(s.spotSize)")
        spin(0.5)
        let after = bytes(host)
        check("설정 칸: 값이 바뀌면 칸(슬라이더·숫자)이 다시 그려짐", before != nil && after != nil && before != after, "")
        if let d = after { try? d.write(to: dir.appendingPathComponent("number-row-131.png")) }

        b.wrappedValue = 9999           // 범위 밖은 끝값으로
        check("설정 칸: 범위 밖 입력은 끝값(200)으로 잘림", s.spotSize == 200, "\(s.spotSize)")
        w.orderOut(nil)
    }
}
