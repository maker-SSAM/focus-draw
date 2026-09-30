import AppKit

// ================= 커서 주위 강조 원 =================
final class SpotView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let s = Settings.shared
        color(s.spotColor, CGFloat(s.spotOpacity) / 100).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
    }
}

@MainActor final class Spotlight {
    private var window: GlassPanel?
    private var timer: Timer?
    // 보일지 말지는 AppState가 정한다 (강조 켬 && 드로잉 꺼짐). 여기서는 그대로 따른다.
    var visible = false { didSet { if visible != oldValue { refresh() } } }
    var windowNumber: Int? { window?.windowNumber }

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
    }
}
