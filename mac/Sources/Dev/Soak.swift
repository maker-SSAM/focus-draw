import AppKit

// 오래 쓰기 시험: FocusDraw --soak <결과 파일>
// 수업 한 학기를 줄여서 돌린다: 100번 켜고 끄기 → 5,000획 → 30번 취소 → 가짜 화면 변경 20번 → 지우고 끄기(70초 기다려 메모리 확인).
// 단계마다 물리 메모리(활동 모니터와 같은 값)를 적고, 끝난 뒤 처음보다 얼마나 늘었는지 기준(+80MB) 안인지 본다.
// (`leaks`는 하드닝된 앱이라 못 돌린다 → 메모리가 단계마다 되돌아오는지로 대신 본다.) 사용자 settings.ini는 읽지 않는다.
@MainActor enum Soak {
    static func run(_ d: AppDelegate, out: String) {
        var lines: [String] = []
        func say(_ s: String) { lines.append(s); print(s); fflush(stdout) }
        func mb() -> String { String(format: "%.0fMB", Bench.footprintMB()) }
        func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }
        say("# Focus & Draw --soak  \(Date())")
        say("machine=\(Log.sysctlString("hw.model")) macOS=\(ProcessInfo.processInfo.operatingSystemVersionString) screens=\(NSScreen.screens.count)")
        var failures: [String] = []
        let base = Bench.footprintMB()
        say("처음                      \(mb())")

        let screen = NSScreen.screens[0].frame
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: screen.origin.x + x, y: screen.origin.y + y) }
        func mouse(_ t: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }

        // 1) 100번 켜고 끄기
        var t0 = Date()
        for _ in 0..<100 { autoreleasepool { d.draw.turnOn(); d.draw.turnOff(.hotkey) } }
        say("100번 켜고 끄기          \(mb())  \(String(format: "%.1f", Date().timeIntervalSince(t0)))초")
        if d.draw.isOn { failures.append("켜고 끄기 뒤 드로잉이 켜져 있음") }

        // 2) 5,000획 (짧은 획 5,000개, 색은 숫자키로 돌려 가며)
        d.draw.turnOn()
        t0 = Date()
        for i in 0..<5000 {
            autoreleasepool {
                if i % 50 == 0 { d.draw.controller.handleKey(UInt16(18 + (i / 50) % 4), [], isRepeat: false, source: "soak") }
                let x = CGFloat(100 + (i * 37) % 1000), y = CGFloat(150 + (i * 53) % 500)
                let pts = (0..<8).map { P(x + CGFloat($0) * 9, y + sin(CGFloat($0)) * 12) }
                d.draw.controller.down(pts[0], mouse(.leftMouseDown, pts[0]), right: false)
                for p in pts.dropFirst() { d.draw.controller.drag(p, mouse(.leftMouseDragged, p)) }
                d.draw.controller.up(pts.last!)
            }
        }
        settle()
        let strokesSecs = Date().timeIntervalSince(t0)
        say("5,000획                  \(mb())  \(String(format: "%.1f", strokesSecs))초  (목록 \(d.draw.controller.items.count)개)")
        if strokesSecs > 120 { failures.append("5,000획이 120초를 넘음") }

        // 3) 30번 취소
        t0 = Date()
        for _ in 0..<30 { autoreleasepool { d.draw.controller.undo() } }
        settle()
        say("30번 취소                \(mb())  \(String(format: "%.2f", Date().timeIntervalSince(t0)))초")

        // 4) 가짜 화면 변경 20번 (판을 새로 만든다)
        t0 = Date()
        for _ in 0..<20 { autoreleasepool { d.draw.surface.rebuild(reason: "soak") } }
        settle()
        say("화면 변경 20번           \(mb())  \(String(format: "%.1f", Date().timeIntervalSince(t0)))초")

        // 5) 지우고 끄기 (Esc와 같음) → 메모리가 돌아오는가
        d.draw.turnOff(.esc)
        settle()
        let afterOff = Bench.footprintMB()
        say("지우고 끈 직후            \(mb())")
        // 끈 뒤 1분(결정 15)은 ⌘Z로 되살릴 수 있게 그림을 들고 있다가 버린다 → 70초 기다린 뒤 잰다
        RunLoop.current.run(until: Date().addingTimeInterval(70))
        let settled = Bench.footprintMB()
        say("70초 뒤                  \(mb())")
        let growth = settled - base
        say(String(format: "처음 대비 증가 %.0fMB (기준 80MB 이하)", growth))
        _ = afterOff
        if growth > 80 { failures.append("끝난 뒤 메모리가 처음보다 80MB 넘게 늚") }

        say(failures.isEmpty ? "SOAK 기준 통과" : "SOAK 기준 실패: \(failures.joined(separator: ", "))")
        try? (lines.joined(separator: "\n") + "\n").write(toFile: out, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
