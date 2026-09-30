import AppKit

// ================= 커서 주위 강조 원 =================
final class SpotView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let s = Settings.shared
        color(s.spotColor, CGFloat(s.spotOpacity) / 100).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
        // 시스템 커서는 숨겨져 있으므로 원 한가운데(= 포인터 자리)에 얇고 작은 검정 십자를 그린다.
        // 크기는 드로잉 모드 굵기 5단계 동그라미의 지름만큼.
        guard Experiments.hideSpotCursor else { return }
        let c = CGPoint(x: bounds.midX, y: bounds.midY), r = penPx(5) / 2
        let p = NSBezierPath()
        p.move(to: CGPoint(x: c.x - r, y: c.y)); p.line(to: CGPoint(x: c.x + r, y: c.y))
        p.move(to: CGPoint(x: c.x, y: c.y - r)); p.line(to: CGPoint(x: c.x, y: c.y + r))
        p.lineWidth = 1
        NSColor.black.setStroke()
        p.stroke()
    }
}

@MainActor final class Spotlight {
    private var window: GlassPanel?
    private var timer: Timer?
    // 보일지 말지는 AppState가 정한다 (강조 켬 && 드로잉 꺼짐). 여기서는 그대로 따른다.
    var visible = false { didSet { if visible != oldValue { refresh() } } }
    var windowNumber: Int? { window?.windowNumber }
    var isRunning: Bool { timer != nil }

    init() {
        // 켜 둔 채 다른 데스크톱으로 넘어갔는데 원이 따라오지 않았으면 그 자리에서 새로 만든다
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            guard let self, self.visible, isOffActiveSpace(self.window) else { return }
            self.refresh()
        }
    }

    func applySettings() {
        guard let w = window else { return }
        let size = CGFloat(Settings.shared.spotSize)
        w.setContentSize(NSSize(width: size, height: size))
        w.contentView?.needsDisplay = true
        follow()
    }

    private func refresh() {
        if visible {
            if let old = window, isOffActiveSpace(old) {
                old.orderOut(nil); old.close()
                window = nil
                Log.log("SPOT", "rebuilt reason=offSpace")
            }
            if window == nil {
                let w = makeClickThroughWindow(size: CGFloat(Settings.shared.spotSize), level: SPOT_LEVEL)
                w.contentView = SpotView()
                window = w
            }
            applySettings()
            window?.orderFrontRegardless()
            if timer == nil {
                let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.follow() }
                RunLoop.main.add(t, forMode: .common)
                timer = t
            }
        } else {
            timer?.invalidate(); timer = nil
            window?.orderOut(nil)
        }
    }

    private func follow() {
        guard let w = window else { return }
        let m = NSEvent.mouseLocation
        let half = w.frame.width / 2
        let o = NSPoint(x: (m.x - half).rounded(), y: (m.y - half).rounded())
        if w.frame.origin != o { w.setFrameOrigin(o) }
        SystemCursor.reassert() // 시스템이 커서를 다시 보이게 했으면(앞 앱이 바뀌거나 Dock을 지나면) 다시 숨긴다 (0.25초에 한 번까지)
    }
}
