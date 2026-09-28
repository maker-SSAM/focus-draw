import AppKit

// 개발용 자체 점검: FocusDraw --selftest <폴더>
// 가짜 마우스·키 입력으로 펜·도형·칠판·지우개·실행 취소를 차례로 해 보고,
// 위젯과 드로잉 화면을 PNG로 남긴 뒤 끝난다. (화면 기록 권한 없이도 결과를 눈으로 확인하려고)
enum SelfTest {
    static func run(_ d: AppDelegate, out: String) {
        let dir = URL(fileURLWithPath: out)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var log: [String] = []

        snapshot(d.widget.view, to: dir.appendingPathComponent("widget-off.png"))
        d.toggleSpotlight()
        d.draw.turnOn()
        snapshot(d.widget.view, to: dir.appendingPathComponent("widget-on.png"))

        let screen = NSScreen.screens[0].frame
        let o = screen.origin
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x, y: o.y + screen.height - y) } // 위에서부터 y
        func mouse(_ t: NSEvent.EventType, _ p: CGPoint, _ f: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: t, location: p, modifierFlags: f, timestamp: 0, windowNumber: 0,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func key(_ code: UInt16, _ ch: String, up: Bool = false, _ f: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: up ? .keyUp : .keyDown, location: .zero, modifierFlags: f, timestamp: 0, windowNumber: 0,
                             context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code)!
        }
        func stroke(_ pts: [CGPoint], _ f: NSEvent.ModifierFlags = [], right: Bool = false) {
            d.draw.down(pts[0], mouse(right ? .rightMouseDown : .leftMouseDown, pts[0], f), right: right)
            for p in pts.dropFirst() { d.draw.drag(p, mouse(right ? .rightMouseDragged : .leftMouseDragged, p, f)) }
            d.draw.up(pts.last!)
        }
        func wiggle(_ x0: CGFloat, _ y: CGFloat, _ w: CGFloat) -> [CGPoint] {
            stride(from: 0, through: w, by: 6).map { P(x0 + $0, y + sin($0 / 25) * 30) }
        }

        d.draw.keyDown(key(13, "w"))                        // 흰 칠판
        stroke(wiggle(80, 120, 400))                        // 빨강 자유선
        d.draw.keyDown(key(21, "4"))                        // 초록
        stroke([P(80, 220), P(480, 320)], .shift)           // 사각형
        d.draw.keyDown(key(23, "5"))                        // 파랑
        stroke([P(560, 80), P(900, 300)], .control)         // 원
        d.draw.keyDown(key(8, "c")); stroke([P(80, 400), P(400, 470)]); d.draw.keyUp(key(8, "c", up: true))  // 화살표
        d.draw.keyDown(key(7, "x")); stroke([P(80, 520), P(460, 520)]); d.draw.keyUp(key(7, "x", up: true))  // 물결
        d.draw.keyDown(key(6, "z")); stroke([P(560, 400), P(900, 440)], .shift); d.draw.keyUp(key(6, "z", up: true)) // 직선(수평 맞춤)
        d.draw.keyDown(key(1, "s"))                         // 무지개 펜
        stroke(wiggle(560, 560, 400))
        d.draw.keyDown(key(20, "3"))                        // 노랑 → 굵게, 반투명 형광펜
        for _ in 0..<3 { d.draw.keyDown(key(24, "=")) }
        let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -10, wheel2: 0, wheel3: 0)!
        d.draw.scroll(NSEvent(cgEvent: wheel)!)            // 진하기 50%
        stroke([P(60, 130), P(480, 130), P(480, 110), P(60, 110)])  // 겹쳐 지나가도 이음매가 진해지지 않아야
        stroke([P(100, 100), P(300, 300)], right: true)     // 지우개
        log.append("items after drawing: \(d.draw.items.count)")
        snapshotInk(d, to: dir.appendingPathComponent("draw-board.png"))

        d.draw.keyDown(key(6, "z", .command))               // ⌘Z: 지우개 되돌리기
        log.append("items after undo: \(d.draw.items.count)")
        d.draw.keyDown(key(12, "q"))                        // 칠판 치우기
        d.draw.keyDown(key(51, "\u{7F}"))                   // 전부 지우기
        log.append("items after delete: \(d.draw.items.count) (last is clear)")
        d.draw.keyDown(key(6, "z", .command))
        log.append("items after undo delete: \(d.draw.items.count)")
        snapshotInk(d, to: dir.appendingPathComponent("draw-clear-undone.png"))
        d.draw.keyDown(key(53, "\u{1B}"))                   // Esc
        log.append("draw on after Esc: \(d.draw.isOn)")

        try? log.joined(separator: "\n").write(to: dir.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    static func snapshot(_ v: NSView, to url: URL) {
        v.display()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    // 드로잉 판은 투명하므로 체크무늬 위에 얹어 저장한다 (투명한 곳이 보이도록)
    static func snapshotInk(_ d: AppDelegate, to url: URL) {
        guard let v = NSApp.windows.compactMap({ $0.contentView as? InkView }).first else { return }
        let size = v.bounds.size
        let img = NSImage(size: size, flipped: false) { r in
            for y in stride(from: 0, to: r.height, by: 40) {
                for x in stride(from: 0, to: r.width, by: 40) {
                    (Int(x / 40 + y / 40) % 2 == 0 ? NSColor(white: 0.85, alpha: 1) : NSColor(white: 0.7, alpha: 1)).setFill()
                    NSRect(x: x, y: y, width: 40, height: 40).fill()
                }
            }
            v.draw(r)
            return true
        }
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
