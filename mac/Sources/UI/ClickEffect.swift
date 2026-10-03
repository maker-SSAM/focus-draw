import AppKit

// ================= 클릭하면 테두리 원이 가운데로 오므라드는 효과 =================
final class RingView: NSView {
    var radius: CGFloat = 0
    var width: CGFloat = 1
    var ringColor = NSColor.red
    override func draw(_ dirtyRect: NSRect) {
        guard radius >= 1 else { return }
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        let p = NSBezierPath(ovalIn: NSRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        p.lineWidth = width
        ringColor.setStroke()
        p.stroke()
    }
}

@MainActor final class ClickEffect {
    static let frames = 30
    private final class Side {
        var window: GlassPanel?
        var view = RingView()
        var frame = 0
        var timer: Timer?
    }
    private let sides = [Side(), Side()] // 0 = 왼쪽, 1 = 오른쪽
    var enabledNow: () -> Bool = { true } // 보임은 AppState가 정한다 (강조 켬 && 드로잉 꺼짐)

    // ⌃ 클릭은 맥에서 오른쪽(보조) 클릭이다 — 오른쪽 링과 같게 본다
    static func isRight(_ e: NSEvent) -> Bool {
        e.type == .rightMouseDown || (e.type == .leftMouseDown && e.modifierFlags.contains(.control))
    }

    func start() {
        // 다른 앱 위의 클릭(전역)과 위젯 위의 클릭(우리 앱)을 둘 다 받는다.
        // 마우스 클릭을 지켜보는 것은 "손쉬운 사용" 권한 없이도 된다.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            self?.fire(right: ClickEffect.isRight(e))
        }
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            self?.fire(right: ClickEffect.isRight(e))
            return e
        }
    }

    private func fire(right: Bool) {
        let s = Settings.shared
        guard enabledNow(), right ? s.rclickEffect : s.clickEffect else { return }
        let side = sides[right ? 1 : 0]
        let size = CGFloat(s.spotSize)
        if let old = side.window, isOffActiveSpace(old) {
            side.timer?.invalidate(); side.timer = nil
            old.orderOut(nil); old.close()
            side.window = nil
        }
        if side.window == nil {
            let w = makeClickThroughWindow(size: size, level: SPOT_LEVEL)
            w.contentView = side.view
            side.window = w
        }
        side.window!.setContentSize(NSSize(width: size, height: size))
        side.window!.alphaValue = CGFloat(right ? s.rclickOpacity : s.clickOpacity) / 100
        side.view.ringColor = color(right ? s.rclickColor : s.clickColor)
        side.frame = 0
        side.timer?.invalidate()
        // 빠르기 1~30 → 한 칸 간격 40~11ms (Windows 판과 같은 셈)
        let interval = Double(41 - (right ? s.rclickSpeed : s.clickSpeed)) / 1000
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.step(side, right: right) }
        RunLoop.main.add(t, forMode: .common)
        side.timer = t
        step(side, right: right)
        side.window!.orderFrontRegardless()
    }

    private func step(_ side: Side, right: Bool) {
        let s = Settings.shared
        guard let w = side.window else { return }
        let thickness = CGFloat(right ? s.rclickThickness : s.clickThickness)
        let size = w.frame.width
        guard let ring = clickRingFrame(side.frame, size: size, thickness: thickness) else {
            side.timer?.invalidate(); side.timer = nil
            w.orderOut(nil)
            return
        }
        side.view.width = ring.width
        side.view.radius = ring.radius
        side.view.alphaValue = ring.alpha
        side.view.needsDisplay = true
        let m = NSEvent.mouseLocation
        w.setFrameOrigin(NSPoint(x: (m.x - size / 2).rounded(), y: (m.y - size / 2).rounded()))
        side.frame += 1
    }
}

// ---------- 클릭 링 한 칸 (ClickEffect.step과 기준 그림이 같이 쓴다) ----------
// 처음엔 빠르게 줄다가 가운데 근처에서 천천히 멈추는 감속 곡선. nil이면 끝난 것.
func clickRingFrame(_ frame: Int, size: CGFloat, thickness: CGFloat) -> (radius: CGFloat, width: CGFloat, alpha: CGFloat)? {
    let t = CGFloat(frame) / CGFloat(ClickEffect.frames)
    let eased = 1 - pow(1 - t, 3)
    let radius = (size / 2 - thickness / 2 - 1) * (1 - eased)
    if frame >= ClickEffect.frames || radius < 1 { return nil }
    // 테두리가 반지름보다 두꺼워지면 찌그러진 덩어리로 보이므로, 끝까지 속이 빈 고리로 남게 가늘어진다
    return (radius, min(thickness, radius), min(1, radius / (thickness * 1.5)))
}
