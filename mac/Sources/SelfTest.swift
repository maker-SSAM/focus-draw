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

        // ---- S1a: 수업 중 멈춤 버그 점검 ----
        // H1: 무지개 펜으로 긋는 도중 색 키·레이저 키를 눌러도 죽지 않고 points/hues 길이가 맞아야 한다
        d.draw.keyDown(key(1, "s"))                                     // 무지개 펜
        d.draw.down(P(80, 640), mouse(.leftMouseDown, P(80, 640)), right: false)
        d.draw.drag(P(120, 640), mouse(.leftMouseDragged, P(120, 640)))
        d.draw.keyDown(key(20, "3"))                                    // 긋는 도중 색 키 (다음 획부터 적용돼야 함)
        d.draw.drag(P(200, 640), mouse(.leftMouseDragged, P(200, 640)))
        d.draw.keyDown(key(0, "a"))                                     // 긋는 도중 레이저 키
        d.draw.drag(P(280, 640), mouse(.leftMouseDragged, P(280, 640)))
        d.draw.up(P(280, 640))
        if let last = d.draw.items.last {
            log.append("H1 무지개 도중 키 변경 (안 죽음): points=\(last.points.count) hues=\(last.hues?.count ?? -1)")
        }

        // H1: 레이저로 긋는 도중 무지개 키를 눌러도 이번 획은 레이저로 끝나고(목록에 안 쌓임),
        // 새 획부터 무지개가 적용된다 — laserLive가 안 막히고 제대로 끝나야 다음 확인도 통과한다
        let beforeLaserSwap = d.draw.items.count
        d.draw.keyDown(key(0, "a"))                                     // 레이저 펜
        d.draw.down(P(80, 700), mouse(.leftMouseDown, P(80, 700)), right: false)
        d.draw.drag(P(150, 700), mouse(.leftMouseDragged, P(150, 700)))
        d.draw.keyDown(key(1, "s"))                                     // 긋는 도중 무지개로 전환 시도
        d.draw.drag(P(220, 700), mouse(.leftMouseDragged, P(220, 700)))
        d.draw.up(P(220, 700))
        log.append("레이저 획은 목록에 안 쌓임: \(d.draw.items.count == beforeLaserSwap)")
        stroke([P(80, 750), P(200, 750)])                               // 새 획 → 이제 무지개여야 한다
        log.append("다음 획부터 무지개 적용: \(d.draw.items.last?.hues != nil)")

        // 제자리 오른쪽 클릭·⌥ 클릭(트랙패드 두 손가락 탭 포함)은 아무것도 지우지 않고 실행 취소 기록도 남기지 않는다
        let beforeStillClick = d.draw.items.count
        d.draw.down(P(400, 700), mouse(.rightMouseDown, P(400, 700)), right: true)
        d.draw.up(P(400, 700))
        log.append("제자리 오른쪽 클릭 무변화: \(d.draw.items.count == beforeStillClick)")

        // L1: ⌘⇧Z는 실행 취소가 아니다
        let beforeShiftUndo = d.draw.items.count
        d.draw.keyDown(key(6, "z", [.command, .shift]))
        log.append("cmd-shift-z는 실행 취소가 아님: \(d.draw.items.count == beforeShiftUndo)")

        // H2: 위젯을 숨긴 채 드로잉을 두 번 켜고 꺼도 계속 숨어 있어야 한다
        Settings.shared.showWidget = false
        d.applySettings()
        d.draw.turnOn(); d.draw.turnOff(clear: false)
        d.draw.turnOn(); d.draw.turnOff(clear: false)
        log.append("숨긴 위젯이 드로잉 토글 후에도 숨어 있음: \(!d.widget.window.isVisible)")
        Settings.shared.showWidget = true
        d.applySettings()

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
