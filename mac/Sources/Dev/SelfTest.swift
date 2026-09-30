import AppKit

// 개발용 자체 점검: FocusDraw --selftest <폴더>
// 가짜 마우스·키 입력으로 펜·도형·칠판·지우개·실행 취소를 차례로 해 보고,
// 위젯과 드로잉 화면을 PNG로 남긴 뒤 끝난다. (화면 기록 권한 없이도 결과를 눈으로 확인하려고)
@MainActor enum SelfTest {
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
            d.draw.controller.down(pts[0], mouse(right ? .rightMouseDown : .leftMouseDown, pts[0], f), right: right)
            for p in pts.dropFirst() { d.draw.controller.drag(p, mouse(right ? .rightMouseDragged : .leftMouseDragged, p, f)) }
            d.draw.controller.up(pts.last!)
        }
        func wiggle(_ x0: CGFloat, _ y: CGFloat, _ w: CGFloat) -> [CGPoint] {
            stride(from: 0, through: w, by: 6).map { P(x0 + $0, y + sin($0 / 25) * 30) }
        }

        d.draw.controller.keyDown(key(13, "w"))                        // 흰 칠판
        stroke(wiggle(80, 120, 400))                        // 빨강 자유선
        d.draw.controller.keyDown(key(21, "4"))                        // 초록
        stroke([P(80, 220), P(480, 320)], .shift)           // 사각형
        d.draw.controller.keyDown(key(23, "5"))                        // 파랑
        stroke([P(560, 80), P(900, 300)], .control)         // 원
        d.draw.controller.keyDown(key(8, "c")); stroke([P(80, 400), P(400, 470)]); d.draw.controller.keyUp(key(8, "c", up: true))  // 화살표
        d.draw.controller.keyDown(key(7, "x")); stroke([P(80, 520), P(460, 520)]); d.draw.controller.keyUp(key(7, "x", up: true))  // 물결
        d.draw.controller.keyDown(key(6, "z")); stroke([P(560, 400), P(900, 440)], .shift); d.draw.controller.keyUp(key(6, "z", up: true)) // 직선(수평 맞춤)
        d.draw.controller.keyDown(key(1, "s"))                         // 무지개 펜
        stroke(wiggle(560, 560, 400))
        d.draw.controller.keyDown(key(20, "3"))                        // 노랑 → 굵게, 반투명 형광펜
        for _ in 0..<3 { d.draw.controller.keyDown(key(24, "=")) }
        let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -10, wheel2: 0, wheel3: 0)!
        d.draw.controller.scroll(NSEvent(cgEvent: wheel)!)            // 진하기 50%
        stroke([P(60, 130), P(480, 130), P(480, 110), P(60, 110)])  // 겹쳐 지나가도 이음매가 진해지지 않아야
        stroke([P(100, 100), P(300, 300)], right: true)     // 지우개
        check("획 9개 (펜·도형 6·무지개·형광펜·지우개)", d.draw.controller.items.count == 9, "items=\(d.draw.controller.items.count)")
        snapshotInk(d, to: dir.appendingPathComponent("draw-board.png"))

        d.draw.controller.keyDown(key(6, "z", .command))               // ⌘Z: 지우개 되돌리기
        check("⌘Z로 하나 되돌림", d.draw.controller.items.count == 8, "items=\(d.draw.controller.items.count)")
        d.draw.controller.keyDown(key(12, "q"))                        // 칠판 치우기
        d.draw.controller.keyDown(key(51, "\u{7F}"))                   // 전부 지우기
        check("delete는 '전부 지우기' 한 단계", d.draw.controller.items.count == 9 && d.draw.controller.items.last?.kind == .clear, "items=\(d.draw.controller.items.count)")
        d.draw.controller.keyDown(key(6, "z", .command))
        check("전부 지우기도 되돌림", d.draw.controller.items.count == 8, "items=\(d.draw.controller.items.count)")
        snapshotInk(d, to: dir.appendingPathComponent("draw-clear-undone.png"))
        d.draw.controller.keyDown(key(53, "\u{1B}"))                   // Esc
        check("Esc로 드로잉 꺼짐", !d.draw.isOn)

        // ---- S1a: 수업 중 멈춤 버그 점검 ----
        // H1: 무지개 펜으로 긋는 도중 색 키·레이저 키를 눌러도 죽지 않고 points/hues 길이가 맞아야 한다
        d.draw.controller.keyDown(key(1, "s"))                                     // 무지개 펜
        d.draw.controller.down(P(80, 640), mouse(.leftMouseDown, P(80, 640)), right: false)
        d.draw.controller.drag(P(120, 640), mouse(.leftMouseDragged, P(120, 640)))
        d.draw.controller.keyDown(key(20, "3"))                                    // 긋는 도중 색 키 (다음 획부터 적용돼야 함)
        d.draw.controller.drag(P(200, 640), mouse(.leftMouseDragged, P(200, 640)))
        d.draw.controller.keyDown(key(0, "a"))                                     // 긋는 도중 레이저 키
        d.draw.controller.drag(P(280, 640), mouse(.leftMouseDragged, P(280, 640)))
        d.draw.controller.up(P(280, 640))
        let last = d.draw.controller.items.last
        check("H1 무지개 도중 키 변경: 색 개수 = 점 개수", last != nil && last?.points.count == last?.hues?.count,
              "points=\(last?.points.count ?? -1) hues=\(last?.hues?.count ?? -1)")

        // H1: 레이저로 긋는 도중 무지개 키를 눌러도 이번 획은 레이저로 끝나고(목록에 안 쌓임),
        // 새 획부터 무지개가 적용된다 — laserLive가 안 막히고 제대로 끝나야 다음 확인도 통과한다
        let beforeLaserSwap = d.draw.controller.items.count
        d.draw.controller.keyDown(key(0, "a"))                                     // 레이저 펜
        d.draw.controller.down(P(80, 700), mouse(.leftMouseDown, P(80, 700)), right: false)
        d.draw.controller.drag(P(150, 700), mouse(.leftMouseDragged, P(150, 700)))
        d.draw.controller.keyDown(key(1, "s"))                                     // 긋는 도중 무지개로 전환 시도
        d.draw.controller.drag(P(220, 700), mouse(.leftMouseDragged, P(220, 700)))
        d.draw.controller.up(P(220, 700))
        check("레이저 획은 목록에 안 쌓임", d.draw.controller.items.count == beforeLaserSwap)
        stroke([P(80, 750), P(200, 750)])                               // 새 획 → 이제 무지개여야 한다
        check("다음 획부터 무지개 적용", d.draw.controller.items.last?.hues != nil)

        // 제자리 오른쪽 클릭·⌥ 클릭(트랙패드 두 손가락 탭 포함)은 아무것도 지우지 않고 실행 취소 기록도 남기지 않는다
        let beforeStillClick = d.draw.controller.items.count
        d.draw.controller.down(P(400, 700), mouse(.rightMouseDown, P(400, 700)), right: true)
        d.draw.controller.up(P(400, 700))
        check("제자리 오른쪽 클릭 무변화", d.draw.controller.items.count == beforeStillClick)

        // L1: ⌘⇧Z는 실행 취소가 아니다
        let beforeShiftUndo = d.draw.controller.items.count
        d.draw.controller.keyDown(key(6, "z", [.command, .shift]))
        check("⌘⇧Z는 실행 취소가 아님", d.draw.controller.items.count == beforeShiftUndo)

        // H2: 위젯을 숨긴 채 드로잉을 두 번 켜고 꺼도 계속 숨어 있어야 한다
        Settings.shared.showWidget = false
        d.applySettings()
        d.draw.turnOn(); d.draw.turnOff(.hotkey)
        d.draw.turnOn(); d.draw.turnOff(.hotkey)
        check("숨긴 위젯이 드로잉 토글 후에도 숨어 있음", !d.widget.window.isVisible)
        Settings.shared.showWidget = true
        d.applySettings()

        session(d, check, dir: dir)

        log.append("DONE")
        try? log.joined(separator: "\n").write(to: dir.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    // ---- 판·드로잉 키·커서·진단 기록 ----
    static func session(_ d: AppDelegate, _ check: (String, Bool, String) -> Void, dir: URL) {
        let globalKeys = HotKeyRegistry.shared.count
        let diagURL = dir.appendingPathComponent("diag.log")
        try? FileManager.default.removeItem(at: diagURL)
        Log.start(at: diagURL, reason: "selftest")

        // 판은 키 창이 되지 않는 비활성 패널, 드로잉 키는 켜 있는 동안만 전역 단축키
        func inkWindows() -> [NSWindow] { d.draw.inkWindowNumbers.compactMap { NSApp.window(withWindowNumber: $0) } }
        // 판이 다시 만들어지면 옛 판이 풀려야 한다. 자체 점검은 한 덩어리로 돌므로, 실제 이벤트처럼 각자 풀(pool)에서 한다.
        weak var oldView: InkView?
        autoreleasepool { oldView = inkWindows().first?.contentView as? InkView }
        autoreleasepool { d.draw.surface.rebuild(reason: "selftest") } // 화면을 바꾼 것처럼 판을 새로 만든다
        autoreleasepool { d.draw.turnOn() }
        let panels = inkWindows()
        check("판은 키 창이 못 되는 비활성 패널",
              !panels.isEmpty && panels.allSatisfy { !$0.canBecomeKey && $0.styleMask.contains(.nonactivatingPanel) }, "")
        let registered = d.draw.keys.ids.count, blocked = d.draw.keys.blockIDs.count
        check("드로잉 키·막기 키 단축키 등록 (드로잉 실패 없음)", registered >= 40 && blocked >= 200
              && HotKeyRegistry.shared.count == globalKeys + registered + blocked,
              "드로잉=\(registered) 막기=\(blocked) 전체=\(HotKeyRegistry.shared.count) 켜는 데 \(Int(d.draw.keys.lastOnMs.rounded()))ms")
        check("드로잉 켜는 데 걸린 시간이 100ms 이하", d.draw.keys.lastOnMs <= 100, "\(Int(d.draw.keys.lastOnMs.rounded()))ms")
        check("드로잉 중에만 20Hz 살핌이 돎", d.draw.controller.watch.isRunning && d.draw.isWatching, "")
        check("판 커서: 시스템 커서 숨김", SystemCursor.hidden, "")
        // 전역 단축키로 들어온 키도 같은 길을 탄다: 그은 뒤 delete → 전부 지우기
        let p = NSEvent.mouseLocation
        let e = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        d.draw.controller.handleKey(18, [], isRepeat: false, source: "hk")   // 1: 빨강 펜
        d.draw.controller.down(p, e, right: false); d.draw.controller.drag(CGPoint(x: p.x + 40, y: p.y), e); d.draw.controller.up(CGPoint(x: p.x + 40, y: p.y))
        d.draw.controller.handleKey(51, [], isRepeat: false, source: "hk")
        check("단축키로 받은 delete가 전부 지우기", d.draw.controller.items.last?.kind == .clear, "")
        RunLoop.current.run(until: Date().addingTimeInterval(0.4)) // 창 서버가 새 판을 화면에 올릴 때까지
        let inkCount = NSApp.windows.filter { $0.contentView is InkView }.count
        check("판을 다시 만들어도 옛 판의 캐시 그림이 남지 않음", inkCount == NSScreen.screens.count && oldView?.hasCache != true,
              "판 \(inkCount)개 / 화면 \(NSScreen.screens.count)개, 옛 판 객체 \(oldView == nil ? "풀림" : "남음(캐시는 버림)")")
        Log.sample()
        d.draw.controller.handleKey(53, [], isRepeat: false, source: "hk")   // Esc
        check("Esc로 끄면 드로잉·막기 키가 풀리고 Esc 하나만 뗄 때까지 남음", !d.draw.isOn && d.draw.keys.left == 0
              && HotKeyRegistry.shared.count == globalKeys + 1 && d.draw.keys.escLingerID != nil,
              "남음=\(d.draw.keys.left) 전체=\(HotKeyRegistry.shared.count)")
        if let esc = d.draw.keys.escLingerID { HotKeyRegistry.shared.simulate(esc, pressed: false) }  // Esc를 뗌
        check("Esc를 떼면 남은 등록이 0", HotKeyRegistry.shared.count == globalKeys && d.draw.keys.escLingerID == nil,
              "전체=\(HotKeyRegistry.shared.count)")
        check("끄면 20Hz 살핌이 멈춤 (쉬는 동안 타이머 0)", !d.draw.controller.watch.isRunning && !d.draw.isWatching, "")
        check("Esc로 끄면 시스템 커서 돌아옴", !SystemCursor.hidden, "")
        check("AppState: 끄면 드로잉 꺼짐, 강조 원은 그대로 켬 상태", !d.state.drawOn && d.state.spotOn, "")

        // S1c: 키노트 쇼가 시작·끝날 때처럼 화면 알림이 쏟아져도, 화면 구성이 그대로면 판을 새로 만들지 않는다
        d.draw.turnOn()
        let boardsBefore = d.draw.inkWindowNumbers
        for _ in 0..<60 { NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        check("화면 알림 60번에도 판을 새로 만들지 않음", !boardsBefore.isEmpty && d.draw.inkWindowNumbers == boardsBefore,
              "판 \(boardsBefore) → \(d.draw.inkWindowNumbers)")
        Log.sample()
        d.draw.turnOff(.hotkey)

        // AppState 하나로 강조·클릭 링의 보임을 정한다
        check("강조 켬 + 드로잉 꺼짐이면 강조가 보임", d.state.highlightVisible && d.spotlight.windowNumber != nil, "")
        d.draw.turnOn()
        check("드로잉 중에는 강조가 함께 쉼", !d.state.highlightVisible, "")
        d.draw.turnOff(.hotkey)
        d.toggleSpotlight()
        check("강조를 끄면 보이지 않음", !d.state.spotOn && !d.state.highlightVisible, "")

        offReasons(d, check)
        cursors(d, check)
        longClass(d, check)

        HotKeyTests.realBackend(check)

        check("비공개 커서 API를 찾음 (강조 중 커서 숨기기용)", SystemCursor.privateAPIFound, "")

        Log.stop()
        let text = (try? String(contentsOf: diagURL, encoding: .utf8)) ?? ""
        check("진단 기록: 시스템·화면·샘플·키·단축키 줄이 있음",
              ["SYS macOS=", "SCREEN #0", "SAMPLE draw=1", "ink=[#", "KEY hk down code=51", "HK drawkeys off", "DRAW off"].allSatisfy(text.contains),
              "")
        check("진단 기록: 판을 새로 만든 까닭과 위젯이 지금 데스크톱에 있는지가 남음",
              text.contains("DRAW rebuilt reason=") && text.contains("widget=[on=1 space=1]"), "")
        check("진단 기록: 샘플에 판이 화면에 있다고 나옴", text.contains(" on=1 L=\(OVERLAY_LEVEL.rawValue)"), "")
    }

    // ---- S4: 끄는 이유마다 잉크를 남기거나 지운다 (가짜 시스템 알림) ----
    static func offReasons(_ d: AppDelegate, _ check: (String, Bool, String) -> Void) {
        let nc = NSWorkspace.shared.notificationCenter
        let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        let c = d.draw.controller
        func drawOneLine() {
            let p = NSEvent.mouseLocation
            let e = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            c.handleKey(18, [], isRepeat: false, source: "hk")
            c.down(p, e, right: false); c.drag(CGPoint(x: p.x + 60, y: p.y + 10), e); c.up(CGPoint(x: p.x + 60, y: p.y + 10))
        }
        func off(_ label: String, clears: Bool, _ trigger: () -> Void) {
            d.draw.turnOn()
            guard d.draw.isOn else { check(label, false, "켜지지 않음"); return }
            drawOneLine()
            let n = c.items.count
            trigger()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            let last = c.items.last?.kind
            let inkOK = clears ? last == .clear : (last == .stroke && c.items.count == n)
            check(label, !d.draw.isOn && inkOK && d.draw.keys.left == 0 && !d.draw.isWatching && !SystemCursor.hidden,
                  "켜짐=\(d.draw.isOn) 잉크=\(clears ? "지움" : "남김")\(inkOK ? "✓" : "✗") 남은 등록=\(d.draw.keys.left)")
            if let esc = d.draw.keys.escLingerID { HotKeyRegistry.shared.simulate(esc, pressed: false) }
        }
        func post(_ name: Notification.Name, _ info: [AnyHashable: Any]? = nil) { nc.post(name: name, object: NSWorkspace.shared, userInfo: info) }
        if let f = finder {
            off("끄는 이유 다른 앱이 앞으로: 끄고 그림·칠판 지움", clears: true) { post(NSWorkspace.didActivateApplicationNotification, [NSWorkspace.applicationUserInfoKey: f]) }
        } else {
            check("끄는 이유 다른 앱이 앞으로: 끄고 그림·칠판 지움", true, "Finder를 찾지 못해 건너뜀")
        }
        off("끄는 이유 데스크톱 바뀜: 끄고 지움", clears: true) { post(NSWorkspace.activeSpaceDidChangeNotification) }
        off("끄는 이유 잠자기: 끄고 지움", clears: true) { post(NSWorkspace.willSleepNotification) }
        off("끄는 이유 화면 꺼짐: 끄고 지움", clears: true) { post(NSWorkspace.screensDidSleepNotification) }
        off("끄는 이유 화면 잠금: 끄고 지움", clears: true) { post(NSWorkspace.sessionDidResignActiveNotification) }
        off("끄는 이유 F9·단축키: 끄고 그림은 남김", clears: false) { d.draw.turnOff(.hotkey) }
        off("끄는 이유 설정 열기: 끄고 그림은 남김", clears: false) { d.draw.turnOff(.settings) }
        off("끄는 이유 위젯 버튼: 끄고 지움", clears: true) { d.draw.turnOff(.widgetButton) }
        // 우리 앱이 앞으로 나오는 것(설정 창)은 끄는 이유가 아니다
        d.draw.turnOn()
        post(NSWorkspace.didActivateApplicationNotification, [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        check("우리 앱이 앞으로 나와도 드로잉은 꺼지지 않음", d.draw.isOn, "")
        d.draw.turnOff(.hotkey)
        // 꺼진 뒤의 알림에는 반응하지 않음 (감시가 풀려 있음)
        post(NSWorkspace.activeSpaceDidChangeNotification)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        check("꺼진 뒤에는 시스템 알림을 지켜보지 않음", !d.draw.isWatching && !d.draw.isOn, "")
    }

    // ---- S4: 붓 동그라미·⌥ 지우개 링·포인터 아래 창 ----
    static func cursors(_ d: AppDelegate, _ check: (String, Bool, String) -> Void) {
        let c = d.draw.controller
        func centerAlpha(_ img: NSImage?) -> Int {
            guard let img, let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
            ctx.draw(cg, in: CGRect(x: -CGFloat(cg.width) / 2 + 0.5, y: -CGFloat(cg.height) / 2 + 0.5, width: CGFloat(cg.width), height: CGFloat(cg.height)))
            return Int(ctx.data!.load(fromByteOffset: 3, as: UInt8.self))
        }
        d.draw.turnOn()
        c.handleKey(18, [], isRepeat: false, source: "hk")   // 빨강 펜 (진하기 100%)
        let expectBrush = max(ceil(penPx(c.penStep)) + 2, 4), expectRing = ceil(eraserPx(c.eraserStep) + 4)
        check("붓 동그라미는 지금 그어질 선의 굵기와 같음 (판에 그림)", c.cursorImage?.size.width == expectBrush && !c.optionHeld,
              "그림 \(c.cursorImage?.size.width ?? -1) 기대 \(expectBrush)")
        c.refreshOption(true)
        check("⌥만 눌러도 지우개 링 (클릭 없이)", c.optionHeld && c.cursorImage?.size.width == expectRing, "그림 \(c.cursorImage?.size.width ?? -1) 기대 \(expectRing)")
        c.refreshOption(false)
        check("⌥를 떼면 붓 동그라미로 돌아옴", !c.optionHeld && c.cursorImage?.size.width == expectBrush, "")
        c.handleKey(24, .option, isRepeat: false, source: "hk")   // ⌥= : 바로 링과 새 크기
        check("⌥= 단축키가 오면 바로 지우개 링과 새 크기", c.optionHeld && c.eraserStep == 6 && c.cursorImage?.size.width == ceil(eraserPx(6) + 4),
              "지우개 단계 \(c.eraserStep)")
        c.refreshOption(false)
        c.config.drawOpacity = 50
        c.handleKey(18, [], isRepeat: false, source: "hk")
        let a50 = centerAlpha(c.cursorImage)
        c.config.drawOpacity = 100
        c.updateCursor()
        let a100 = centerAlpha(c.cursorImage)
        check("붓 동그라미 진하기 = 색별 진하기 × 전체 진하기", abs(a50 - 128) <= 3 && a100 >= 252, "전체 50% → \(a50), 100% → \(a100)")
        c.syncPointer(.widget)
        check("위젯 위(포인터 아래가 위젯)에서는 화살표를 보임", !c.mouseInside && !SystemCursor.hidden, "")
        c.syncPointer(.board)
        check("판 위로 돌아오면 다시 붓 동그라미와 숨긴 커서", c.mouseInside && SystemCursor.hidden, "")
        c.syncPointer(.other)
        check("캡처 화면·시스템 창 위에서도 화살표를 보임", !c.mouseInside && !SystemCursor.hidden, "")
        d.draw.turnOff(.hotkey)
        check("끄면 시스템 커서가 돌아오고 Hide·Show 호출 수가 짝", !SystemCursor.hidden && SystemCursor.balanced, SystemCursor.callSummary)
    }

    // ---- S5: 긴 수업 — 바닥 굽기·실행 취소·화면 바뀜·끈 뒤 정리 ----
    static func longClass(_ d: AppDelegate, _ check: (String, Bool, String) -> Void) {
        let c = d.draw.controller
        func view() -> InkView? { d.draw.surface.views.first }
        func pixels(_ img: CGImage, _ w: Int, _ h: Int) -> [UInt8] {
            var buf = [UInt8](repeating: 0, count: w * h * 4)
            buf.withUnsafeMutableBytes { raw in
                if let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
                }
            }
            return buf
        }
        // 화면의 그림(바닥 그림 + 최근 획)과 기준 경로(renderScene: 목록 전체를 처음부터)가 같은가 — 다른 픽셀 수를 돌려준다
        func differing() -> Int {
            guard let v = view(), let snap = v.cacheSnapshot, let win = v.window else { return -1 }
            let scale = win.backingScaleFactor
            guard let ref = renderScene(items: c.model.items, size: v.bounds.size, scale: scale) else { return -1 }
            let w = snap.width, h = snap.height
            guard ref.width == w, ref.height == h else { return -1 }
            let a = pixels(snap, w, h), b = pixels(ref, w, h)
            var n = 0
            for i in stride(from: 0, to: a.count, by: 4) where abs(Int(a[i]) - Int(b[i])) > 4 || abs(Int(a[i + 1]) - Int(b[i + 1])) > 4
                || abs(Int(a[i + 2]) - Int(b[i + 2])) > 4 || abs(Int(a[i + 3]) - Int(b[i + 3])) > 4 { n += 1 }
            return n
        }
        let screen = NSScreen.screens[0].frame
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: screen.minX + x, y: screen.minY + y) }
        func mouse(_ t: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func line(_ i: Int) {
            let x = 100 + CGFloat((i * 37) % 700), y = 100 + CGFloat((i * 53) % 500)
            let erase = i % 20 == 19
            c.alpha = i % 4 == 3 ? 0.5 : 1
            let pts = (0..<12).map { P(x + CGFloat($0) * 9, y + sin(CGFloat($0) + CGFloat(i)) * 25) }
            c.down(pts[0], mouse(erase ? .rightMouseDown : .leftMouseDown, pts[0]), right: erase)
            for p in pts.dropFirst() { c.drag(p, mouse(erase ? .rightMouseDragged : .leftMouseDragged, p)) }
            c.up(pts.last!)
        }

        d.draw.turnOn()
        guard d.draw.isOn else { check("긴 수업 점검: 드로잉 켜짐", false, "켜지지 않음"); return }
        c.handleKey(18, [], isRepeat: false, source: "hk") // 1번 색 (빨강) 일반 펜
        for i in 0..<120 { line(i) }
        let baked = view()?.bakedUpTo ?? -1
        check("긴 수업: 120획 뒤 오래된 획이 바닥 그림에 구워짐", baked >= 70 && baked <= c.model.floorAbs, "구운 곳=\(baked) 되돌릴 수 없는 곳=\(c.model.floorAbs)")
        check("긴 수업: 바닥 그림을 쓴 화면이 목록 전체를 처음부터 그린 것과 같음", differing() == 0, "다른 픽셀 \(differing())")
        for _ in 0..<30 { c.undo() }
        check("긴 수업: ⌘Z 30번 뒤에도 같음 (바닥 그림 + 최근 획만 다시 그림)", differing() == 0 && c.items.count == 90, "다른 픽셀 \(differing()) 획 \(c.items.count)")
        c.clearAll()
        check("긴 수업: 바닥 굽기를 넘은 뒤 전부 지우기 → 빈 화면", differing() == 0, "다른 픽셀 \(differing())")
        c.undo()
        check("긴 수업: 전부 지우기를 취소하면 그림이 돌아옴", differing() == 0 && c.items.last?.kind != .clear, "다른 픽셀 \(differing())")

        // 긋는 도중 화면 구성이 바뀌면 획을 깔끔히 끝낸다
        let before = c.items.count, boards = d.draw.inkWindowNumbers
        c.down(P(300, 300), mouse(.leftMouseDown, P(300, 300)), right: false)
        c.drag(P(340, 330), mouse(.leftMouseDragged, P(340, 330)))
        c.drag(P(380, 330), mouse(.leftMouseDragged, P(380, 330)))
        d.draw.surface.checkScreens(forced: true)
        check("화면이 바뀌면 긋던 획이 끝남 (매달린 획·지우개 없음, 획은 목록에 남음)",
              c.live == nil && !c.erasing && !c.rightDown && c.items.count == before + 1, "live=\(c.live != nil) 획 \(before)→\(c.items.count)")
        check("화면이 바뀌면 판을 새로 만들고 그림을 다시 그림", d.draw.inkWindowNumbers != boards && d.draw.surface.views.allSatisfy(\.hasCache)
              && differing() == 0, "다른 픽셀 \(differing())")
        check("화면이 바뀐 뒤에도 위젯이 화면 안에 있음", NSScreen.screens.contains { $0.frame.intersects(d.widget.window.frame) }, "")

        // 레이저를 쓴 뒤 끄면 타이머가 모두 멈추고 그림이 버려짐
        c.handleKey(0, [], isRepeat: false, source: "hk") // 레이저 펜
        c.down(P(200, 200), mouse(.leftMouseDown, P(200, 200)), right: false)
        c.drag(P(260, 220), mouse(.leftMouseDragged, P(260, 220)))
        c.up(P(260, 220))
        check("레이저를 쓰는 동안은 레이저 타이머가 돎", c.laserTimer != nil, "")
        c.handleKey(18, [], isRepeat: false, source: "hk")
        d.draw.turnOff(.hotkey)
        check("끄면 그림(바닥·획·화면)이 모두 버려지고 타이머가 없음 (잉크 목록만 남음)",
              !d.draw.surface.hasImages && c.laserTimer == nil && !c.watch.isRunning && !d.draw.isWatching && !c.items.isEmpty,
              "그림=\(d.draw.surface.hasImages) 레이저타이머=\(c.laserTimer != nil) 살핌=\(c.watch.isRunning)")
        check("끄면 10분 뒤 정리 작업이 한 번만 예약됨", c.hasExpiryScheduled, "")
        d.draw.surface.checkScreens(forced: true)
        check("꺼진 채 화면이 바뀌면 판을 닫고 그림을 만들지 않음", d.draw.surface.windows.isEmpty && !d.draw.surface.hasImages, "판 \(d.draw.surface.windows.count)개")

        // 다시 켜면 목록에서 한 번 다시 그림
        d.draw.turnOn()
        let redraw = d.draw.surface.lastRebuildMS
        check("다시 켜면 남은 잉크가 목록에서 다시 그려짐, 정리 예약은 취소됨",
              d.draw.isOn && differing() == 0 && !c.hasExpiryScheduled, "다른 픽셀 \(differing()) \(String(format: "%.0f", redraw))ms")

        // 2,000획 뒤: 다시 그리기 시간과 실행 취소 시간 (SPIKES D4)
        for i in 0..<2000 { line(200 + i) }
        d.draw.turnOff(.hotkey)
        d.draw.turnOn()
        let redraw2000 = d.draw.surface.lastRebuildMS
        check("2,000획: 켤 때 다시 그리기 2초 이내 (선생님 판에서는 훨씬 빠르다)", redraw2000 < 2000, "\(String(format: "%.0f", redraw2000))ms, 획 \(c.items.count)개")
        var worst = 0.0
        for _ in 0..<30 {
            let t = DispatchTime.now().uptimeNanoseconds
            c.undo()
            worst = max(worst, Double(DispatchTime.now().uptimeNanoseconds - t) / 1_000_000)
        }
        check("2,000획 뒤 실행 취소 한 번이 50ms 이내", worst <= 50, "가장 느린 \(String(format: "%.1f", worst))ms")
        d.draw.turnOff(.hotkey)
        d.toggleSpotlightOffIfOn()
        check("드로잉·강조가 모두 꺼지면 도는 타이머가 없음", !c.watch.isRunning && c.laserTimer == nil && !d.spotlight.isRunning, "")
        check("깨어난 뒤 앱 단축키가 그대로이고 진단 한 줄을 남김", d.checkAfterWake(), "")
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
