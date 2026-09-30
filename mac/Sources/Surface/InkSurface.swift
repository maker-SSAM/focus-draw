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
    private var cache: CGContext?       // 화면에 보이는 그림 = 바닥 그림 + 최근 획 (+ 아직 안 구운 오래된 획)
    private var cacheImage: CGImage?
    private var floor: CGContext?       // 바닥 그림: 되돌릴 수 없게 된 오래된 획을 구워 둔 것
    private var floorAbs = 0            // 바닥 그림이 구운 곳까지의 절대 번호 (InkModel.floorAbs)
    private var strokeLayer: StrokeLayer?

    init(frame: NSRect, controller: DrawController) {
        ctl = controller
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }

    private var origin: CGPoint { window?.frame.origin ?? .zero }
    private var globalFrame: CGRect { CGRect(origin: origin, size: bounds.size) }

    private func makeContext() -> CGContext? {
        let scale = window?.backingScaleFactor ?? 2
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.scaleBy(x: scale, y: scale)
        c.translateBy(x: -origin.x, y: -origin.y)
        return c
    }

    // 이 화면에 걸친 획만 그린다 (다른 모니터에만 있는 획은 건너뛴다)
    private func paint(_ items: ArraySlice<InkItem>, in c: CGContext) {
        let f = globalFrame
        for item in items where item.kind == .clear || item.bounds.intersects(f) { renderInk(item, in: c) }
    }

    // 되돌릴 수 없게 된 오래된 획을 바닥 그림에 굽는다. 획마다 굽지 않고 FLOOR_CHUNK개 쌓였을 때 한꺼번에(force면 지금 전부).
    private func bakeFloor(force: Bool) {
        let m = ctl.model
        if floorAbs < m.removed { floor = nil; floorAbs = m.removed } // 버려진 앞부분에 "전부 지우기"가 있었으면 바닥도 비운다
        let target = m.floorAbs
        guard target - floorAbs >= (force ? 1 : FLOOR_CHUNK) else { return }
        if floor == nil { floor = makeContext() }
        if let f = floor { paint(m.slice(from: floorAbs, to: target), in: f) }
        floorAbs = target
    }

    // 전체를 다시 그린다. keepFloor: 실행 취소는 바닥 그림을 그대로 쓰고 그 뒤 획만 다시 그린다. 켤 때는 바닥부터 새로 굽는다.
    func rebuildCache(keepFloor: Bool = false) {
        if !keepFloor { floor = nil; floorAbs = ctl.model.removed }
        bakeFloor(force: !keepFloor)
        cacheImage = nil
        if cache == nil { cache = makeContext() }
        guard let c = cache else { return }
        c.clear(globalFrame)
        if let f = floor, let img = f.makeImage() { c.draw(img, in: globalFrame) }
        paint(ctl.model.slice(from: floorAbs, to: .max), in: c)
        cacheImage = c.makeImage()
        needsDisplay = true
    }

    var hasCache: Bool { cache != nil || cacheImage != nil }
    var cacheSnapshot: CGImage? { cacheImage }   // 자체 점검이 기준 경로(renderScene)와 견준다
    var bakedUpTo: Int { floorAbs }              // 바닥 그림이 구운 곳 (절대 번호)
    var hasImages: Bool { cache != nil || cacheImage != nil || floor != nil || strokeLayer != nil }
    func releaseCache() { cache = nil; cacheImage = nil; floor = nil; floorAbs = 0; strokeLayer = nil }

    func commit(_ item: InkItem) {
        guard let c = cache else { return } // 그림은 켤 때 목록에서 만든다
        cacheImage = nil                    // 그림을 들고 있으면 쓰는 순간 통째로 복사된다 — 먼저 놓는다
        paint([item], in: c)
        bakeFloor(force: false)
        cacheImage = c.makeImage()
        strokeLayer?.clear(item.bounds)
        invalidate(global: item.kind == .clear ? .infinite : item.bounds)
    }

    func invalidate(global r: CGRect) {
        if r.isInfinite { needsDisplay = true; return }
        let local = r.offsetBy(dx: -origin.x, dy: -origin.y).intersection(bounds)
        if !local.isNull && !local.isEmpty { setNeedsDisplay(local.insetBy(dx: -2, dy: -2)) }
    }

    // ---- 긋는 중인 획 전용 그림 ----
    private func layer() -> StrokeLayer? {
        if strokeLayer == nil {
            strokeLayer = StrokeLayer(size: bounds.size, scale: window?.backingScaleFactor ?? 2, origin: origin)
        }
        return strokeLayer
    }
    func strokeAdd(_ item: InkItem) { layer()?.add(item) }
    // 도형 미리보기: 지난 그림이 있던 자리를 지우고 새로 그린다
    func strokeReplace(clear old: CGRect, with item: InkItem) {
        let l = layer()
        l?.clear(old.union(item.bounds))
        l?.add(item)
    }
    func strokeClear(_ r: CGRect) { strokeLayer?.clear(r) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        paintInkLayer(in: ctx, fill: dirtyRect, board: ctl.boardColor, opacity: ctl.config.drawOpacity) {
            if let img = cacheImage { ctx.draw(img, in: bounds) }
            if let live = ctl.live, live.kind == .stroke, let l = strokeLayer {
                // 긋는 중인 획 / 도형 미리보기: 전용 그림을 획 진하기로 얹는다
                ctx.saveGState()
                ctx.setAlpha(live.alpha)
                ctx.draw(l.image, in: bounds)
                ctx.restoreGState()
            }
            ctx.translateBy(x: -origin.x, y: -origin.y)
            if let live = ctl.live, live.kind == .erase { renderInk(live, in: ctx) } // 문지르는 중인 지우개
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
    private var lastSignature = screenSignature()   // 마지막으로 처리한 화면 구성 (screenSignature)
    private var lastScreens = screenSnapshots()     // 그때의 화면 번호·자리 (주 화면이 바뀌어 원점이 옮겨 갔는지 보려고)
    private var screenCheck: DispatchWorkItem?
    var onScreensChanged: (CGVector) -> Void = { _ in } // 화면 구성이 정말 바뀐 뒤 (잉크를 옮긴 만큼) — 위젯을 같이 옮기고 들이는 데 쓴다

    init() {
        // 키노트 쇼가 시작·끝날 때는 화면이 그대로인데도 이 알림이 1~2초에 수십~수백 번 온다(S1 집 시험: 2,504번).
        // 잠깐 모았다가 화면 구성이 정말 바뀌었을 때만 처리한다.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.screenCheck?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.checkScreens() }
            self.screenCheck = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    // 화면 구성이 정말 바뀌었으면 (D6):
    //  1) 긋던 획은 깔끔히 끝낸다  2) 주 화면이 바뀌어 전역 좌표 원점이 옮겨 갔으면 잉크도 같이 옮긴다(화면에 있던 자리 그대로)
    //  3) 판은 새로 만든다 — 켜져 있을 때만. 꺼져 있으면 판을 닫고 그림도 만들지 않는다(쓸 때 만든다)
    func checkScreens(forced: Bool = false) { // forced: 자체 점검이 화면이 바뀐 것처럼 처리해 본다
        let sig = screenSignature()
        guard forced || sig != lastSignature else { return }
        let now = screenSnapshots()
        let shift = inkShift(old: lastScreens, new: now)
        Log.log("SCREEN", "changed screens=\(now.count) shift=\(Int(shift.dx)),\(Int(shift.dy)) primary=\(now.first?.id ?? 0) drawing=\(isShown)")
        lastSignature = sig
        lastScreens = now
        if let c = controller {
            c.endStroke()
            c.model.translate(dx: shift.dx, dy: shift.dy)
        }
        if !windows.isEmpty {
            if isShown { rebuild(reason: "screens") } else { closeWindows() }
        }
        onScreensChanged(shift)
    }

    // 켜기 전에: 한 번 숨긴 판은 지금 데스크톱(다른 앱의 전체 화면)에 다시 뜨지 않을 수 있다 → 그때는 새로 만든다
    func prepare() {
        if windows.isEmpty {
            rebuild(reason: "first")
        } else if windows.contains(where: isOffActiveSpace) {
            rebuild(reason: "offSpace")
        }
    }

    // 드로잉을 쓸 때 그림을 만든다: 끄면 버렸으므로 선 목록에서 한 번 다시 그린다
    func show() {
        isShown = true
        let t0 = DispatchTime.now().uptimeNanoseconds
        var built = 0
        for v in views where !v.hasCache { v.rebuildCache(); built += 1 }
        if built > 0 {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
            lastRebuildMS = ms
            Log.log("DRAW", "redraw from list items=\(controller?.model.items.count ?? 0) screens=\(built) \(String(format: "%.1f", ms))ms")
        }
        for w in windows { w.orderFrontRegardless() }
    }
    private(set) var lastRebuildMS = 0.0

    // 끄면 그림(바닥 그림·획 그림·화면 그림)을 모두 버린다. 선 목록만 남는다.
    func hide() {
        isShown = false
        for w in windows { w.orderOut(nil) }
        for v in views { v.releaseCache() }
    }

    var hasImages: Bool { views.contains { $0.hasImages } }

    private func makeWindow(_ frame: NSRect) -> NSWindow {
        let p = InkPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.becomesKeyOnlyIfNeeded = false
        return p
    }

    private func closeWindows() {
        // 옛 판은 닫고 화면 크기만 한 그림을 직접 버린다. 앞서 키 창이었던 판(InkView)은 닫고 떼어 내도
        // 무언가가 계속 붙들고 있어서(원인 미확인, S1b 기록), 그림을 버리지 않으면 모니터를 바꿀 때마다 쌓인다.
        for w in windows {
            w.orderOut(nil)
            (w.contentView as? InkView)?.releaseCache()
            w.close()
            w.contentView = nil
        }
        windows = []
    }

    func rebuild(reason: String) {
        guard let controller else { return }
        closeWindows()
        lastSignature = screenSignature()
        lastScreens = screenSnapshots()
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
            w.colorSpace = NSColorSpace.sRGB // 그림이 모두 sRGB — 창도 sRGB로 받아 그릴 때마다 색 공간 변환을 하지 않는다
            let v = InkView(frame: NSRect(origin: .zero, size: screen.frame.size), controller: controller)
            w.contentView = v
            if isShown { v.rebuildCache() }
            return w
        }
        if isShown { for w in windows { w.orderFrontRegardless() } }
    }

    func invalidate(_ r: CGRect) { for v in views { v.invalidate(global: r) } }
    func invalidateAll() { for v in views { v.needsDisplay = true } }
    func commit(_ item: InkItem) { for v in views { v.commit(item) } }
    func rebuildCaches() { for v in views where v.hasCache { v.rebuildCache(keepFloor: true) } }

    // 긋는 중인 획 전용 그림
    func strokeAdd(_ item: InkItem) { for v in views { v.strokeAdd(item) } }
    func strokeReplace(clear old: CGRect, with item: InkItem) { for v in views { v.strokeReplace(clear: old, with: item) } }
    func strokeClear(_ r: CGRect) { for v in views { v.strokeClear(r) } }
}
