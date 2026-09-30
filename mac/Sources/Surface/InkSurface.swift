import AppKit

// ================= 화면마다 하나씩 까는 투명 판 =================
// 판은 앱을 앞으로 부르지 않는 비활성 패널(C안)이고 키 창이 되지 않는다. 키는 드로잉 중에만
// 전역 단축키로 받는다(Input/DrawKeys.swift). 마우스는 판이 그대로 받는다.

final class InkPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class InkView: NSView {
    unowned let ctl: DrawController
    private var cache: CGContext?
    private var cacheImage: CGImage?

    init(frame: NSRect, controller: DrawController) {
        ctl = controller
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }

    private var origin: CGPoint { window?.frame.origin ?? .zero }

    func rebuildCache() {
        let scale = window?.backingScaleFactor ?? 2
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        c.scaleBy(x: scale, y: scale)
        c.translateBy(x: -origin.x, y: -origin.y)
        for item in ctl.model.items { renderInk(item, in: c) }
        cache = c
        cacheImage = c.makeImage()
        needsDisplay = true
    }

    var hasCache: Bool { cache != nil || cacheImage != nil }
    func releaseCache() { cache = nil; cacheImage = nil }

    func commit(_ item: InkItem) {
        guard let c = cache else { rebuildCache(); return }
        renderInk(item, in: c)
        cacheImage = c.makeImage()
        invalidate(global: item.kind == .clear ? .infinite : item.bounds)
    }

    func invalidate(global r: CGRect) {
        if r.isInfinite { needsDisplay = true; return }
        let local = r.offsetBy(dx: -origin.x, dy: -origin.y).intersection(bounds)
        if !local.isNull && !local.isEmpty { setNeedsDisplay(local.insetBy(dx: -2, dy: -2)) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        paintInkLayer(in: ctx, fill: dirtyRect, board: ctl.boardColor, opacity: ctl.config.drawOpacity) {
            if let img = cacheImage { ctx.draw(img, in: bounds) }
            ctx.translateBy(x: -origin.x, y: -origin.y)
            if let live = ctl.live { renderInk(live, in: ctx) } // 긋는 중인 획 / 도형 미리보기 / 문지르는 중인 지우개
        }

        ctx.saveGState()
        ctx.translateBy(x: -origin.x, y: -origin.y)
        ctl.renderOverlays(in: ctx)
        ctx.restoreGState()
    }

    // ---- 마우스는 모두 DrawController가 받는다 ----
    private func globalPoint(_ e: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: e.locationInWindow) ?? NSEvent.mouseLocation
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with e: NSEvent) { ctl.mouseEntered(globalPoint(e)) }
    override func mouseExited(with e: NSEvent) { ctl.mouseExited() }
    override func mouseMoved(with e: NSEvent) { ctl.mouseMoved(globalPoint(e)) }
    override func mouseDown(with e: NSEvent) { ctl.down(globalPoint(e), e, right: false) }
    override func mouseDragged(with e: NSEvent) { ctl.drag(globalPoint(e), e) }
    override func mouseUp(with e: NSEvent) { ctl.up(globalPoint(e)) }
    override func rightMouseDown(with e: NSEvent) { ctl.down(globalPoint(e), e, right: true) }
    override func rightMouseDragged(with e: NSEvent) { ctl.drag(globalPoint(e), e) }
    override func rightMouseUp(with e: NSEvent) { ctl.up(globalPoint(e)) }
    override func scrollWheel(with e: NSEvent) { ctl.scroll(e) }
    override func flagsChanged(with e: NSEvent) { ctl.flagsChanged(e) }
}

// 판들을 만들고, 띄우고, 화면이 바뀌면 다시 만든다. 그림 원본(선 목록)은 들지 않는다 — DrawController의 모델을 읽는다.
@MainActor final class InkSurface {
    weak var controller: DrawController?
    private(set) var windows: [NSWindow] = []
    var views: [InkView] { windows.compactMap { $0.contentView as? InkView } }
    var windowNumbers: [Int] { windows.map(\.windowNumber) }
    private(set) var isShown = false
    private var builtForScreens = ""        // 판을 만든 때의 화면 구성 (screenSignature)
    private var screenCheck: DispatchWorkItem?

    init() {
        // 키노트 쇼가 시작·끝날 때는 화면이 그대로인데도 이 알림이 1~2초에 수십~수백 번 온다(S1 집 시험: 2,504번).
        // 잠깐 모았다가 화면 구성이 정말 바뀌었을 때만 판을 새로 만든다.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.screenCheck?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.windows.isEmpty, screenSignature() != self.builtForScreens else { return }
                self.rebuild(reason: "screens")
            }
            self.screenCheck = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
        // 드로잉 중에 다른 데스크톱으로 넘어갔는데 판이 따라오지 않았으면 새로 만든다
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isShown, self.windows.contains(where: isOffActiveSpace) else { return }
            self.rebuild(reason: "spaceChanged")
        }
    }

    // 켜기 전에: 한 번 숨긴 판은 지금 데스크톱(다른 앱의 전체 화면)에 다시 뜨지 않을 수 있다 → 그때는 새로 만든다
    func prepare() {
        if windows.isEmpty {
            rebuild(reason: "first")
        } else if windows.contains(where: isOffActiveSpace) {
            rebuild(reason: "offSpace")
        }
    }

    func show() {
        isShown = true
        for w in windows { w.orderFrontRegardless() }
    }

    func hide() {
        isShown = false
        for w in windows { w.orderOut(nil) }
    }

    private func makeWindow(_ frame: NSRect) -> NSWindow {
        let p = InkPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.becomesKeyOnlyIfNeeded = false
        return p
    }

    func rebuild(reason: String) {
        guard let controller else { return }
        // 옛 판은 닫고 화면 크기만 한 캐시 그림을 직접 버린다. 앞서 키 창이었던 판(InkView)은 닫고 떼어 내도
        // 무언가가 계속 붙들고 있어서(원인 미확인, S1b 기록), 캐시를 버리지 않으면 모니터를 바꿀 때마다 쌓인다.
        for w in windows {
            w.orderOut(nil)
            (w.contentView as? InkView)?.releaseCache()
            w.close()
            w.contentView = nil
        }
        builtForScreens = screenSignature()
        screenCheck?.cancel()
        Log.log("DRAW", "rebuilt reason=\(reason) screens=\(NSScreen.screens.count) on=\(isShown)")
        windows = NSScreen.screens.map { screen in
            let w = makeWindow(screen.frame)
            w.setFrame(screen.frame, display: false)
            w.isOpaque = false
            // 완전히 투명한 곳은 클릭이 뒤 창으로 빠져나가므로, 눈에 안 띌 만큼만 칠해 둔다
            w.backgroundColor = NSColor(white: 0, alpha: 0.004)
            w.hasShadow = false
            w.level = OVERLAY_LEVEL
            w.collectionBehavior = EVERYWHERE
            w.ignoresMouseEvents = false
            w.acceptsMouseMovedEvents = true
            w.isReleasedWhenClosed = false
            w.hidesOnDeactivate = false
            let v = InkView(frame: NSRect(origin: .zero, size: screen.frame.size), controller: controller)
            w.contentView = v
            v.rebuildCache()
            return w
        }
        if isShown { for w in windows { w.orderFrontRegardless() } }
    }

    func invalidate(_ r: CGRect) { for v in views { v.invalidate(global: r) } }
    func invalidateAll() { for v in views { v.needsDisplay = true } }
    func commit(_ item: InkItem) { for v in views { v.commit(item) } }
    func rebuildCaches() { for v in views { v.rebuildCache() } }
}
