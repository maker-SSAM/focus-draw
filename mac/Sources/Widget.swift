import AppKit

// 화면 구석의 작은 조작판: ⋮(옮기기) · 강조 · 드로잉 · 설정 · ✕(숨기기)
// Windows 판과 같은 크기 비율(칩 32, 모서리 12, 아이콘 22)을 쓴다.

let ON_COLOR: UInt32 = 0x0A84FF

func tintedIcon(_ name: String, _ tint: NSColor) -> NSImage? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
          let src = NSImage(contentsOf: url),
          let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    // 원본 그림 크기 그대로 색만 입힌다 — 화면 배율(Retina 여부)에 따라 결과가 달라지지 않게 화면 그림을 거치지 않는다
    let r = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
    ctx.draw(cg, in: r)
    ctx.setBlendMode(.sourceAtop) // 모양(알파)은 두고 색만 바꾼다
    ctx.setFillColor(tint.cgColor)
    ctx.fill(r)
    return ctx.makeImage().map { NSImage(cgImage: $0, size: src.size) }
}

final class WidgetView: NSView {
    enum Part { case grip, spot, draw, settings, close }

    var spotOn = false { didSet { needsDisplay = true } }
    var drawOn = false { didSet { needsDisplay = true } }
    var onAction: (Part) -> Void = { _ in }
    var onMoved: (NSPoint) -> Void = { _ in }
    // 오른쪽 클릭(⌃ 클릭)하면 메뉴 막대 아이콘과 같은 메뉴 — 노치 뒤로 아이콘이 숨었을 때를 위해
    var contextMenu: () -> NSMenu? = { nil }

    override func rightMouseDown(with event: NSEvent) {
        guard let m = contextMenu() else { return }
        NSMenu.popUpContextMenu(m, with: event, for: self)
    }

    private var icons: [String: NSImage] = [:]
    private var dragStart: NSPoint?
    private var windowStart: NSPoint = .zero
    private var pressed: Part?

    static func px(_ base: CGFloat) -> CGFloat { max(1, (base * CGFloat(Settings.shared.widgetScale) / 100).rounded()) }
    static var chip: CGFloat { px(32) }
    static var pad: CGFloat { px(6) }
    static var top: CGFloat { px(4) }
    static var narrow: CGFloat { px(14) }
    static var gap: CGFloat { px(4) }
    static var size: NSSize {
        NSSize(width: pad * 2 + narrow * 2 + chip * 3 + gap * 4, height: chip + top * 2)
    }

    private var isDark: Bool {
        let c = Settings.shared.widgetColor
        let lum = 0.299 * Double((c >> 16) & 0xFF) + 0.587 * Double((c >> 8) & 0xFF) + 0.114 * Double(c & 0xFF)
        return lum < 128
    }

    private func rect(_ part: Part) -> NSRect {
        let chip = WidgetView.chip, gap = WidgetView.gap, narrow = WidgetView.narrow
        var x = WidgetView.pad
        let y = WidgetView.top
        let order: [(Part, CGFloat)] = [(.grip, narrow), (.spot, chip), (.draw, chip), (.settings, chip), (.close, narrow)]
        for (p, w) in order {
            if p == part { return NSRect(x: x, y: y, width: w, height: chip) }
            x += w + gap
        }
        return .zero
    }

    private func part(at p: NSPoint) -> Part? {
        for part in [Part.grip, .spot, .draw, .settings, .close] where rect(part).insetBy(dx: -2, dy: -WidgetView.top).contains(p) {
            return part
        }
        return nil
    }

    func reloadIcons() {
        icons = [:]
        icons["spotOff"] = tintedIcon("icon_spotlight_dark", .black)
        icons["spotOn"] = tintedIcon("icon_spotlight_dark", color(ON_COLOR))
        icons["drawOff"] = tintedIcon("icon_draw_dark", .black)
        icons["drawOn"] = tintedIcon("icon_draw_dark", color(ON_COLOR))
        icons["settings"] = tintedIcon("settings", .black)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let s = Settings.shared
        color(s.widgetColor).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: WidgetView.px(8), yRadius: WidgetView.px(8)).fill()

        let corner = WidgetView.px(12) / 2
        let iconSize = WidgetView.px(22)
        for (part, key) in [(Part.spot, spotOn ? "spotOn" : "spotOff"), (.draw, drawOn ? "drawOn" : "drawOff"), (.settings, "settings")] {
            let r = rect(part)
            (pressed == part ? NSColor(white: 0.88, alpha: 1) : NSColor.white).setFill()
            NSBezierPath(roundedRect: r, xRadius: corner, yRadius: corner).fill()
            let ir = NSRect(x: r.midX - iconSize / 2, y: r.midY - iconSize / 2, width: iconSize, height: iconSize)
            icons[key]?.draw(in: ir)
        }

        let textColor = isDark ? NSColor(white: 0.9, alpha: 1) : NSColor.black
        let font = NSFont.systemFont(ofSize: max(8, WidgetView.px(13)), weight: .medium)
        for (part, text) in [(Part.grip, "⋮"), (.close, "✕")] {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            let str = NSAttributedString(string: text, attributes: attrs)
            let sz = str.size()
            let r = rect(part)
            str.draw(at: NSPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    // 드로잉 중에도 위젯 위에서는 평소 화살표가 보여야 어디를 누르는지 안다
    override func mouseEntered(with event: NSEvent) { NSCursor.arrow.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.arrow.set() }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        let p = convert(event.locationInWindow, from: nil)
        let hit = part(at: p)
        if hit == .grip || hit == nil {
            dragStart = NSEvent.mouseLocation
            windowStart = window?.frame.origin ?? .zero
        } else {
            pressed = hit
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let w = window else { return }
        let m = NSEvent.mouseLocation
        var o = NSPoint(x: windowStart.x + m.x - start.x, y: windowStart.y + m.y - start.y)
        // 화면 밖으로는 나가지 않게. 모니터가 여럿이면 커서가 있는 화면을 따른다.
        let screen = NSScreen.screens.first { $0.frame.contains(m) } ?? NSScreen.main
        if let f = screen?.frame {
            o.x = min(max(o.x, f.minX), f.maxX - w.frame.width)
            o.y = min(max(o.y, f.minY), f.maxY - w.frame.height)
        }
        w.setFrameOrigin(o)
    }

    override func mouseUp(with event: NSEvent) {
        if dragStart != nil {
            dragStart = nil
            if let o = window?.frame.origin { onMoved(o) }
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        if let pr = pressed, part(at: p) == pr { onAction(pr) }
        pressed = nil
        needsDisplay = true
    }
}

final class Widget {
    let view = WidgetView()
    private(set) var window: GlassPanel!

    init() {
        window = Widget.makeWindow(view)
        view.reloadIcons()
        view.onMoved = { Settings.shared.saveWidgetPosition($0) }
        applySettings()
        let s = Settings.shared
        if let x = s.widgetX, let y = s.widgetY {
            window.setFrameOrigin(NSPoint(x: x, y: y))
            clampIntoScreen()
        } else {
            moveToDefault()
        }
        // 다른 데스크톱으로 넘어갔는데 위젯이 따라오지 않았으면 새로 만든다 (판·강조 원과 같은 까닭)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            guard let self, Settings.shared.showWidget, isOffActiveSpace(self.window) else { return }
            self.setVisible(true)
        }
    }

    private static func makeWindow(_ view: WidgetView) -> GlassPanel {
        let w = GlassPanel(contentRect: NSRect(origin: .zero, size: WidgetView.size),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = WIDGET_LEVEL
        w.collectionBehavior = EVERYWHERE
        w.hidesOnDeactivate = false
        w.becomesKeyOnlyIfNeeded = true
        w.isReleasedWhenClosed = false
        w.contentView = view
        return w
    }

    func applySettings() {
        let s = Settings.shared
        let o = window.frame.origin
        window.setFrame(NSRect(origin: o, size: WidgetView.size), display: true)
        window.alphaValue = CGFloat(s.widgetOpacity) / 100
        view.needsDisplay = true
        clampIntoScreen()
        setVisible(s.showWidget)
    }

    func setVisible(_ on: Bool) {
        guard on else { window.orderOut(nil); return }
        if isOffActiveSpace(window) {
            // 숨겼던 위젯을 전체 화면 데스크톱에서 다시 띄우면 나타나지 않으므로, 새 창으로 옮겨 띄운다
            let old: GlassPanel = window
            let w = Widget.makeWindow(view) // view가 새 창으로 옮겨 간다
            w.setFrame(old.frame, display: false)
            w.alphaValue = old.alphaValue
            old.orderOut(nil); old.close()
            window = w
            Diag.log("WIDGET", "rebuilt reason=offSpace")
        }
        window.orderFrontRegardless()
    }

    // 늘 주 화면 오른쪽 아래(Dock 위)로
    func moveToDefault() {
        guard let f = NSScreen.main?.visibleFrame else { return }
        let sz = WidgetView.size
        window.setFrameOrigin(NSPoint(x: f.maxX - sz.width - 20, y: f.minY + 20))
    }

    // 모니터 구성이 바뀌어 저장된 자리가 화면 밖이면 들여놓는다
    func clampIntoScreen() {
        let fr = window.frame
        if NSScreen.screens.contains(where: { $0.frame.intersects(fr.insetBy(dx: fr.width / 3, dy: fr.height / 3)) }) {
            return
        }
        moveToDefault()
    }
}
