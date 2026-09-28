import AppKit

// 개발용 자체 점검: FocusDraw --selftest <폴더>
// 가짜 마우스·키 입력으로 펜·도형·칠판·지우개·실행 취소를 차례로 해 보고,
// 위젯과 드로잉 화면을 PNG로 남긴 뒤 끝난다. (화면 기록 권한 없이도 결과를 눈으로 확인하려고)
enum SelfTest {
    static func run(_ d: AppDelegate, out: String) {
        let dir = URL(fileURLWithPath: out)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 한 줄에 하나: "OK 이름" / "FAIL 이름 — 자세히" / "INFO ...". 마지막 줄은 DONE (build.sh --test가 센다)
        var log: [String] = []
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            log.append("\(ok ? "OK" : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }

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
        check("획 9개 (펜·도형 6·무지개·형광펜·지우개)", d.draw.items.count == 9, "items=\(d.draw.items.count)")
        snapshotInk(d, to: dir.appendingPathComponent("draw-board.png"))

        d.draw.keyDown(key(6, "z", .command))               // ⌘Z: 지우개 되돌리기
        check("⌘Z로 하나 되돌림", d.draw.items.count == 8, "items=\(d.draw.items.count)")
        d.draw.keyDown(key(12, "q"))                        // 칠판 치우기
        d.draw.keyDown(key(51, "\u{7F}"))                   // 전부 지우기
        check("delete는 '전부 지우기' 한 단계", d.draw.items.count == 9 && d.draw.items.last?.kind == .clear, "items=\(d.draw.items.count)")
        d.draw.keyDown(key(6, "z", .command))
        check("전부 지우기도 되돌림", d.draw.items.count == 8, "items=\(d.draw.items.count)")
        snapshotInk(d, to: dir.appendingPathComponent("draw-clear-undone.png"))
        d.draw.keyDown(key(53, "\u{1B}"))                   // Esc
        check("Esc로 드로잉 꺼짐", !d.draw.isOn)

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
        let last = d.draw.items.last
        check("H1 무지개 도중 키 변경: 색 개수 = 점 개수", last != nil && last?.points.count == last?.hues?.count,
              "points=\(last?.points.count ?? -1) hues=\(last?.hues?.count ?? -1)")

        // H1: 레이저로 긋는 도중 무지개 키를 눌러도 이번 획은 레이저로 끝나고(목록에 안 쌓임),
        // 새 획부터 무지개가 적용된다 — laserLive가 안 막히고 제대로 끝나야 다음 확인도 통과한다
        let beforeLaserSwap = d.draw.items.count
        d.draw.keyDown(key(0, "a"))                                     // 레이저 펜
        d.draw.down(P(80, 700), mouse(.leftMouseDown, P(80, 700)), right: false)
        d.draw.drag(P(150, 700), mouse(.leftMouseDragged, P(150, 700)))
        d.draw.keyDown(key(1, "s"))                                     // 긋는 도중 무지개로 전환 시도
        d.draw.drag(P(220, 700), mouse(.leftMouseDragged, P(220, 700)))
        d.draw.up(P(220, 700))
        check("레이저 획은 목록에 안 쌓임", d.draw.items.count == beforeLaserSwap)
        stroke([P(80, 750), P(200, 750)])                               // 새 획 → 이제 무지개여야 한다
        check("다음 획부터 무지개 적용", d.draw.items.last?.hues != nil)

        // 제자리 오른쪽 클릭·⌥ 클릭(트랙패드 두 손가락 탭 포함)은 아무것도 지우지 않고 실행 취소 기록도 남기지 않는다
        let beforeStillClick = d.draw.items.count
        d.draw.down(P(400, 700), mouse(.rightMouseDown, P(400, 700)), right: true)
        d.draw.up(P(400, 700))
        check("제자리 오른쪽 클릭 무변화", d.draw.items.count == beforeStillClick)

        // L1: ⌘⇧Z는 실행 취소가 아니다
        let beforeShiftUndo = d.draw.items.count
        d.draw.keyDown(key(6, "z", [.command, .shift]))
        check("⌘⇧Z는 실행 취소가 아님", d.draw.items.count == beforeShiftUndo)

        // H2: 위젯을 숨긴 채 드로잉을 두 번 켜고 꺼도 계속 숨어 있어야 한다
        Settings.shared.showWidget = false
        d.applySettings()
        d.draw.turnOn(); d.draw.turnOff(clear: false)
        d.draw.turnOn(); d.draw.turnOff(clear: false)
        check("숨긴 위젯이 드로잉 토글 후에도 숨어 있음", !d.widget.window.isVisible)
        Settings.shared.showWidget = true
        d.applySettings()

        experiments(d, check, dir: dir)

        log.append("DONE")
        try? log.joined(separator: "\n").write(to: dir.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    // ---- S1b: 실험 스위치·진단 기록 ----
    // 스위치는 메모리에만 적으므로(Experiments.memoryOnly) 사용자가 고른 실험 설정은 바뀌지 않는다.
    static func experiments(_ d: AppDelegate, _ check: (String, Bool, String) -> Void, dir: URL) {
        let globalKeys = HotKeys.count
        let diagURL = dir.appendingPathComponent("diag.log")
        try? FileManager.default.removeItem(at: diagURL)
        Diag.start(at: diagURL, reason: "selftest")

        // C안: 판은 키 창이 되지 않는 비활성 패널, 드로잉 키는 켜 있는 동안만 전역 단축키
        Experiments.memoryOnly = ["key": "C", "cursor": "board"]
        d.experimentsChanged()
        func inkWindows() -> [NSWindow] { d.draw.inkWindowNumbers.compactMap { NSApp.window(withWindowNumber: $0) } }
        // B안 판 — C안으로 바꾸면 풀려야 한다. 자체 점검은 한 덩어리로 돌므로, 실제 이벤트처럼 각자 풀(pool)에서 한다.
        weak var oldView: InkView?
        autoreleasepool { oldView = inkWindows().first?.contentView as? InkView }
        autoreleasepool { d.draw.turnOn() }
        let panels = inkWindows()
        check("C안 판은 키 창이 못 되는 비활성 패널",
              !panels.isEmpty && panels.allSatisfy { ($0 as? InkPanel)?.keyable == false && $0.styleMask.contains(.nonactivatingPanel) }, "")
        let registered = d.draw.carbonKeys.ids.count
        check("C안 드로잉 키 단축키 등록 (실패 없음)", registered >= 40 && HotKeys.count == globalKeys + registered,
              "등록=\(registered) 전체=\(HotKeys.count)")
        check("C안 판 커서: 시스템 커서 숨김", SystemCursor.hidden, "")
        // 전역 단축키로 들어온 키도 같은 길을 탄다: 그은 뒤 delete → 전부 지우기
        let p = NSEvent.mouseLocation
        let e = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        d.draw.handleKey(18, [], isRepeat: false, source: "hk")   // 1: 빨강 펜
        d.draw.down(p, e, right: false); d.draw.drag(CGPoint(x: p.x + 40, y: p.y), e); d.draw.up(CGPoint(x: p.x + 40, y: p.y))
        d.draw.handleKey(51, [], isRepeat: false, source: "hk")
        check("C안 단축키로 받은 delete가 전부 지우기", d.draw.items.last?.kind == .clear, "")
        RunLoop.current.run(until: Date().addingTimeInterval(0.4)) // 창 서버가 새 판을 화면에 올릴 때까지
        let inkCount = NSApp.windows.filter { $0.contentView is InkView }.count
        check("판을 다시 만들어도 옛 판의 캐시 그림이 남지 않음", inkCount == NSScreen.screens.count && oldView?.hasCache != true,
              "판 \(inkCount)개 / 화면 \(NSScreen.screens.count)개, 옛 판 객체 \(oldView == nil ? "풀림" : "남음(캐시는 버림)")")
        Diag.sample()
        d.draw.handleKey(53, [], isRepeat: false, source: "hk")   // Esc
        check("C안 끄면 드로잉 키 단축키가 모두 풀림", !d.draw.isOn && d.draw.carbonKeys.ids.isEmpty && HotKeys.count == globalKeys,
              "남음=\(d.draw.carbonKeys.ids.count) 전체=\(HotKeys.count)")
        check("C안 끄면 시스템 커서 돌아옴", !SystemCursor.hidden, "")

        // A안: 비활성 패널이지만 키 창은 될 수 있다
        Experiments.memoryOnly = ["key": "A"]
        d.experimentsChanged()
        d.draw.turnOn()
        let aPanels = inkWindows()
        check("A안 판은 키 창이 될 수 있는 비활성 패널",
              !aPanels.isEmpty && aPanels.allSatisfy { $0.canBecomeKey && $0.styleMask.contains(.nonactivatingPanel) }, "")
        check("A안은 드로잉 키 단축키를 쓰지 않음", d.draw.carbonKeys.ids.isEmpty, "")
        d.draw.turnOff(clear: false)

        // S1c: 키노트 쇼가 시작·끝날 때처럼 화면 알림이 쏟아져도, 화면 구성이 그대로면 판을 새로 만들지 않는다
        d.draw.turnOn()
        if Experiments.enabled {
            check("켤 때 실험 이름이 커서 옆에 뜸", d.draw.badgeText == Experiments.label, "표시=\(d.draw.badgeText ?? "-")")
        }
        let boardsBefore = d.draw.inkWindowNumbers
        for _ in 0..<60 { NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        check("화면 알림 60번에도 판을 새로 만들지 않음", !boardsBefore.isEmpty && d.draw.inkWindowNumbers == boardsBefore,
              "판 \(boardsBefore) → \(d.draw.inkWindowNumbers)")
        Diag.sample()
        d.draw.turnOff(clear: false)

        // 창 동작 조합 바꾸기가 떠 있는 창(위젯)에 바로 들어간다
        Experiments.memoryOnly = ["behavior": "joinAllApps"]
        d.experimentsChanged()
        check("창 동작 조합이 위젯에 적용됨", d.widget.window.collectionBehavior.contains(.canJoinAllApplications), "")
        Experiments.memoryOnly = [:]
        d.experimentsChanged()
        check("기본값으로 돌아옴 (.stationary)", d.widget.window.collectionBehavior.contains(.stationary), "")

        check("비공개 커서 API를 찾음 (강조 중 커서 숨기기용)", SystemCursor.privateAPIFound, "")

        Diag.stop()
        let text = (try? String(contentsOf: diagURL, encoding: .utf8)) ?? ""
        check("진단 기록: 시스템·화면·샘플·키·단축키 줄이 있음",
              ["SYS macOS=", "SCREEN #0", "SAMPLE draw=1", "ink=[#", "KEY hk down code=51", "HK drawkeys off", "DRAW off"].allSatisfy(text.contains),
              "")
        check("진단 기록: 판을 새로 만든 까닭과 위젯이 지금 데스크톱에 있는지가 남음",
              text.contains("DRAW rebuilt reason=") && text.contains("widget=[on=1 space=1]"), "")
        check("진단 기록: 샘플에 판이 화면에 있다고 나옴", text.contains(" on=1 L=\(OVERLAY_LEVEL.rawValue)"), "")
    }

    static func snapshot(_ v: NSView, to url: URL) {
        v.display()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    // 드로잉 판은 투명하므로 체크무늬 위에 얹어 저장한다 (투명한 곳이 보이도록)
    // 그림이 판(InkView)을 붙들고 남지 않도록 자기 풀 안에서 끝낸다
    static func snapshotInk(_ d: AppDelegate, to url: URL) {
        autoreleasepool { snapshotInkNow(d, to: url) }
    }

    private static func snapshotInkNow(_ d: AppDelegate, to url: URL) {
        guard let v = d.draw.inkWindowNumbers.compactMap({ NSApp.window(withWindowNumber: $0)?.contentView as? InkView }).first else { return }
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
