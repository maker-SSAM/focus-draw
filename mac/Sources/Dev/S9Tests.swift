import AppKit

// S9의 글 점검: 위젯 Dock 자석 계산표, 쉬는 동안 강조 감시자 0, ⌃클릭 링, 위젯 접근성 이름. 화면 없이 돈다(Golden.run).
@MainActor enum S9Tests {
    static func run(_ report: (String, Bool, String) -> Void) {
        func check(_ name: String, _ ok: Bool, _ detail: String = "") { report(name, ok, detail) }
        let size = CGSize(width: 200, height: 40)
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        // 아래 Dock(높이 70, 메뉴 막대 25) / 왼쪽 Dock(폭 60) / 오른쪽 Dock / 자동 숨김(메뉴 막대만)
        let bottom = CGRect(x: 0, y: 70, width: 1000, height: 605)
        let left = CGRect(x: 60, y: 0, width: 940, height: 675)
        let right = CGRect(x: 0, y: 0, width: 940, height: 675)
        let hidden = CGRect(x: 0, y: 0, width: 1000, height: 675)
        func place(_ vis: CGRect, at o: CGPoint) -> CGPoint {
            widgetDragPlace(cursor: CGPoint(x: o.x + 10, y: o.y + 10), grab: CGVector(dx: 10, dy: 10), size: size, frame: frame, visible: vis).origin
        }
        for gap: CGFloat in [14, 15, 16] {
            let b = place(bottom, at: CGPoint(x: 300, y: 70 + gap))
            check("자석 아래 Dock \(Int(gap))pt: " + (gap <= 15 ? "붙음" : "안 붙음"), gap <= 15 ? b.y == 70 : b.y == 70 + gap, "y=\(b.y)")
            let l = place(left, at: CGPoint(x: 60 + gap, y: 300))
            check("자석 왼쪽 Dock \(Int(gap))pt: " + (gap <= 15 ? "붙음" : "안 붙음"), gap <= 15 ? l.x == 60 : l.x == 60 + gap, "x=\(l.x)")
            let r = place(right, at: CGPoint(x: 940 - size.width - gap, y: 300))
            check("자석 오른쪽 Dock \(Int(gap))pt: " + (gap <= 15 ? "붙음" : "안 붙음"), gap <= 15 ? r.x == 940 - size.width : r.x == 940 - size.width - gap, "x=\(r.x)")
        }
        check("자석: Dock 위(visibleFrame 아래)로 더 끌면 지나가 Dock 위에 놓임", place(bottom, at: CGPoint(x: 300, y: 20)).y == 20)
        check("자석: 자동 숨김이면 아래·왼쪽·오른쪽 모두 자석이 없음",
              place(hidden, at: CGPoint(x: 300, y: 10)).y == 10 && place(hidden, at: CGPoint(x: 10, y: 300)).x == 10
              && place(hidden, at: CGPoint(x: 790 - 10, y: 300)).x == 780)
        check("화면 가장자리(Dock 아닌 쪽)에는 자석이 없음", place(bottom, at: CGPoint(x: 10, y: 300)).x == 10)
        check("위로는 메뉴 막대·노치 아래(visibleFrame 위쪽)에서 멈춤", place(bottom, at: CGPoint(x: 300, y: 690)).y == bottom.maxY - size.height)
        // 벽에서 누적 없음: 오른쪽 벽을 한참 넘어 끌었다가 돌아오면 바로 따라온다
        var grab = CGVector(dx: 10, dy: 10)
        let far = widgetDragPlace(cursor: CGPoint(x: 1500, y: 300), grab: grab, size: size, frame: frame, visible: hidden)
        grab = far.grab
        let back = widgetDragPlace(cursor: CGPoint(x: 1000, y: 300), grab: grab, size: size, frame: frame, visible: hidden)
        check("벽 밖으로 끌었다 돌아와도 누적 없이 잡은 거리가 다시 잡힘", far.origin.x == 800 && back.origin.x == 300, "far=\(far.origin.x) back=\(back.origin.x)")

        // ---- 쉬는 동안 비용 0 ----
        let spot = Spotlight()
        check("강조가 꺼져 있으면 마우스 감시자가 없음", !spot.isRunning)
        spot.visible = true
        check("강조가 켜지면 감시자가 생기고 (타이머는 없음)", spot.isRunning)
        spot.visible = false
        check("강조를 끄면 감시자가 모두 사라짐", !spot.isRunning)

        // ---- 드로잉 중 메뉴 막대 아이콘 위의 포인터 ----
        let board = WindowInfo(number: 1, layer: OVERLAY_LEVEL.rawValue, alpha: 1, ownedByUs: true, frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let tray = WindowInfo(number: 2, layer: NSWindow.Level.statusBar.rawValue, alpha: 1, ownedByUs: true, frame: CGRect(x: 800, y: 0, width: 80, height: 37))
        let other = WindowInfo(number: 3, layer: NSWindow.Level.statusBar.rawValue, alpha: 1, ownedByUs: false, frame: CGRect(x: 900, y: 0, width: 40, height: 37))
        func target(_ x: CGFloat, _ wins: [WindowInfo]) -> PointerTarget {
            pointerTarget(at: CGPoint(x: x, y: 10), windows: wins, boards: [1], boardLayer: OVERLAY_LEVEL.rawValue, widgetLayer: WIDGET_LEVEL.rawValue)
        }
        // (실제로는 판이 늘 앞이라 창 목록으로는 [tray, board] 순서가 생기지 않는다. 우리 아이콘 위는 currentPointerTarget이 아이콘 칸 자리로 먼저 가린다)
        check("메뉴 막대: 창 목록 규칙은 그대로, 다른 앱 아이콘·빈 곳은 판",
              target(820, [board, tray, other]) == .board && target(820, [tray, board]) == .widget && target(920, [other, board]) == .board)

        // ---- 접근성 이름 ----
        let names = [WidgetView.Part.grip, .spot, .draw, .settings, .close].map { WidgetView.accessibilityName($0, spotOn: false, drawOn: true) }
        check("위젯 버튼 접근성 이름이 모두 있고 켜짐에 따라 바뀜",
              names.allSatisfy { !$0.isEmpty } && Set(names).count == 5
              && WidgetView.accessibilityName(.spot, spotOn: true, drawOn: false) == "강조 끄기"
              && WidgetView.accessibilityName(.draw, spotOn: false, drawOn: true) == "드로잉 끄기")

        // ---- 레이저 옵션 (LaserHold·LaserFade·LaserGlow) ----
        applyLaserTuning(holdMs: 1000, fadeMs: 2000, glowPercent: 0)
        let tuned = laserLife(0, 1.0) == 1 && abs(laserLife(0, 2.0) - 0.5) < 0.001 && LASER_GLOW_LAYERS.count == 2
        applyLaserTuning(holdMs: 500, fadeMs: 500, glowPercent: 200)
        let wide = abs(laserGlowMaxMul - 5) < 0.001
        applyLaserTuning(holdMs: LASER_HOLD * 1000, fadeMs: LASER_FADE * 1000, glowPercent: 100)
        check("레이저 옵션: 머묾·사라짐 시간이 수명에, 번짐 0%는 빛 없음·200%는 두 배 넓게, 기본값으로 되돌림",
              tuned && wide && abs(laserGlowMaxMul - 3) < 0.001 && laserLife(0, LASER_HOLD) == 1)
        let st = Settings()
        st.laserHold = 800; st.laserFade = 1200; st.laserGlow = 150
        let cfg = DrawConfig(st)
        check("레이저 옵션: 설정 → 드로잉 설정으로 전달", cfg.laserHold == 800 && cfg.laserFade == 1200 && cfg.laserGlow == 150)
    }
}
