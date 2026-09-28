import AppKit

// ================= 드로잉 =================
// 그린 것은 그림(픽셀)이 아니라 "획 목록"으로 들고 있다. 화면마다 그 목록을 한 장의 그림(cache)에
// 구워 두고, 새 획이 끝날 때마다 그 한 획만 더 굽는다. 실행 취소는 목록에서 마지막 하나를 빼고
// 처음부터 다시 굽는 것 — 화면 전체를 30장씩 복사해 두던 Windows 판보다 메모리를 거의 쓰지 않는다.
// 좌표는 모두 전체 화면 좌표(맥 기준: 왼쪽 아래가 원점)라서 모니터가 여럿이어도 한 목록으로 된다.

enum ShapeMode { case free, rect, ellipse, line, wave, arrow }
enum PenKind { case normal, laser, rainbow }

struct InkItem {
    enum Kind { case stroke, erase, clear }
    var kind: Kind
    var points: [CGPoint] = []
    var width: CGFloat = 1
    var rgb: UInt32 = 0
    var alpha: CGFloat = 1
    var hues: [CGFloat]? = nil // 무지개 펜: 점마다 색상(0~360)

    var bounds: CGRect {
        guard let f = points.first else { return .null }
        var r = CGRect(origin: f, size: .zero)
        for p in points { r = r.union(CGRect(origin: p, size: .zero)) }
        return r.insetBy(dx: -width - 2, dy: -width - 2)
    }
}

func hueColor(_ h: CGFloat) -> CGColor {
    let hh = h.truncatingRemainder(dividingBy: 360)
    let x = 1 - abs((hh / 60).truncatingRemainder(dividingBy: 2) - 1)
    let rgb: (CGFloat, CGFloat, CGFloat) =
        hh < 60 ? (1, x, 0) : hh < 120 ? (x, 1, 0) : hh < 180 ? (0, 1, x) :
        hh < 240 ? (0, x, 1) : hh < 300 ? (x, 0, 1) : (1, 0, x)
    return CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
}

let RAINBOW_CYCLE_PX: CGFloat = 700

// 획 하나를 그린다. 반투명한 획은 먼저 불투명하게 그린 뒤 통째로 한 번에 옅게 얹는다 —
// 그래야 한 획 안에서 같은 자리를 여러 번 지나가도 이음매가 진해지지 않는다.
func renderInk(_ item: InkItem, in ctx: CGContext) {
    ctx.saveGState()
    defer { ctx.restoreGState() }
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(item.width)
    switch item.kind {
    case .clear:
        ctx.clear(ctx.boundingBoxOfClipPath)
    case .erase:
        ctx.setBlendMode(.clear)
        strokePoints(item.points, width: item.width, in: ctx)
    case .stroke:
        let translucent = item.alpha < 1
        if translucent {
            ctx.clip(to: item.bounds) // 화면 전체가 아니라 이 획 크기만큼만 임시 그림을 만든다
            ctx.setAlpha(item.alpha)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        if let hues = item.hues, !hues.isEmpty, item.points.count > 1 {
            // hues가 점 수보다 짧아도(방어적으로) 배열 밖을 읽지 않는다
            for i in 1..<item.points.count {
                ctx.setStrokeColor(hueColor(hues[min(i, hues.count - 1)]))
                ctx.move(to: item.points[i - 1])
                ctx.addLine(to: item.points[i])
                ctx.strokePath()
            }
        } else {
            let c = color(item.rgb).cgColor
            ctx.setStrokeColor(c)
            ctx.setFillColor(item.hues.map { hueColor($0.first ?? 0) } ?? c)
            strokePoints(item.points, width: item.width, in: ctx)
        }
        if translucent { ctx.endTransparencyLayer() }
    }
}

private func strokePoints(_ pts: [CGPoint], width: CGFloat, in ctx: CGContext) {
    guard let first = pts.first else { return }
    if pts.allSatisfy({ $0 == first }) {
        // 제자리에서 찍은 점 — 선 굵기만 한 동그라미 (채울 색은 부르는 쪽에서 맞춰 둔다)
        ctx.fillEllipse(in: CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width))
        return
    }
    ctx.addLines(between: pts)
    ctx.strokePath()
}

// ---------- 도형의 점들 (Windows 판과 같은 셈) ----------
func arrowPoints(_ a: CGPoint, _ b: CGPoint, width: CGFloat) -> [CGPoint] {
    let dx = b.x - a.x, dy = b.y - a.y
    let len = hypot(dx, dy)
    guard len >= 1 else { return [a, b] }
    let ux = dx / len, uy = dy / len
    let px = -uy, py = ux
    let head = min(max(width * 4, 14), len * 0.5)
    let halfW = head * 0.45
    let base = CGPoint(x: b.x - ux * head, y: b.y - uy * head)
    let l = CGPoint(x: base.x + px * halfW, y: base.y + py * halfW)
    let r = CGPoint(x: base.x - px * halfW, y: base.y - py * halfW)
    return [a, base, l, b, r, base]
}

func wavePoints(_ a: CGPoint, _ b: CGPoint, width: CGFloat) -> [CGPoint] {
    let dx = b.x - a.x, dy = b.y - a.y
    let len = hypot(dx, dy)
    let amp = max(width * 0.75, 3)
    guard len >= amp else { return [a, b] }
    let ux = dx / len, uy = dy / len
    let px = -uy, py = ux
    let cycles = max(1, (len / max(width * 5.5, 18)).rounded())
    let count = max(2, Int(ceil(len / 2)) + 1)
    return (0..<count).map { i in
        let t = CGFloat(i) / CGFloat(count - 1)
        let d = t * len
        let off = amp * sin(t * cycles * 2 * .pi)
        return CGPoint(x: a.x + ux * d + px * off, y: a.y + uy * d + py * off)
    }
}

func shapePoints(_ mode: ShapeMode, _ a: CGPoint, _ b: CGPoint, width: CGFloat) -> [CGPoint] {
    switch mode {
    case .free, .line: return [a, b]
    case .wave: return wavePoints(a, b, width: width)
    case .arrow: return arrowPoints(a, b, width: width)
    case .rect:
        let lx = min(a.x, b.x), rx = max(a.x, b.x), ty = min(a.y, b.y), by = max(a.y, b.y)
        return [CGPoint(x: lx, y: ty), CGPoint(x: rx, y: ty), CGPoint(x: rx, y: by), CGPoint(x: lx, y: by), CGPoint(x: lx, y: ty)]
    case .ellipse:
        let cx = (a.x + b.x) / 2, cy = (a.y + b.y) / 2
        let ax = abs(b.x - a.x) / 2, ay = abs(b.y - a.y) / 2
        let steps = max(16, min(160, Int(((ax + ay) / 6).rounded())))
        return (0...steps).map { i in
            let t = CGFloat(i) * 2 * .pi / CGFloat(steps)
            return CGPoint(x: cx + ax * cos(t), y: cy + ay * sin(t))
        }
    }
}

// 직선·물결·화살표에 Shift: 방향을 0°·45°·90°로 맞춘다
func snap45(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    let dx = b.x - a.x, dy = b.y - a.y
    let len = hypot(dx, dy)
    let ang = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
    return CGPoint(x: a.x + cos(ang) * len, y: a.y + sin(ang) * len)
}

// ---------- 사라지는 펜 (레이저) ----------
struct LaserPt { var p: CGPoint; var t: TimeInterval; var hue: CGFloat? }
let LASER_HOLD: TimeInterval = 0.5
let LASER_FADE: TimeInterval = 0.5
let LASER_MIN_WIDTH: CGFloat = 8
// [굵기 배율, 진하기, 흰색 섞는 정도] — 바깥의 옅은 번짐부터 가운데 흰 심지까지
let LASER_LAYERS: [(CGFloat, CGFloat, CGFloat)] = [(3.0, 0.16, 0), (1.7, 0.40, 0), (0.75, 1.0, 0), (0.3, 0.9, 0.6)]

func laserLife(_ t: TimeInterval, _ now: TimeInterval) -> CGFloat {
    let age = now - t
    return age <= LASER_HOLD ? 1 : CGFloat(max(0, 1 - (age - LASER_HOLD) / LASER_FADE))
}

func tint(_ c: CGColor, _ mix: CGFloat) -> CGColor {
    guard mix > 0, let comp = NSColor(cgColor: c)?.usingColorSpace(.sRGB) else { return c }
    func m(_ v: CGFloat) -> CGFloat { v + (1 - v) * mix }
    return CGColor(srgbRed: m(comp.redComponent), green: m(comp.greenComponent), blue: m(comp.blueComponent), alpha: 1)
}

func renderLaser(_ strokes: [[LaserPt]], baseColor: CGColor, width: CGFloat, now: TimeInterval, in ctx: CGContext) {
    ctx.saveGState()
    defer { ctx.restoreGState() }
    ctx.setLineCap(.round)
    for (mul, alpha, mix) in LASER_LAYERS {
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        for s in strokes {
            if s.count == 1 {
                let life = laserLife(s[0].t, now)
                let d = width * mul * life
                ctx.setFillColor(tint(s[0].hue.map(hueColor) ?? baseColor, mix))
                ctx.fillEllipse(in: CGRect(x: s[0].p.x - d / 2, y: s[0].p.y - d / 2, width: d, height: d))
                continue
            }
            for i in 1..<max(1, s.count) {
                let life = laserLife(s[i - 1].t, now)
                guard life > 0 else { continue }
                ctx.setLineWidth(max(0.5, width * mul * life))
                ctx.setStrokeColor(tint(s[i].hue.map(hueColor) ?? baseColor, mix))
                ctx.move(to: s[i - 1].p)
                ctx.addLine(to: s[i].p)
                ctx.strokePath()
            }
        }
        ctx.endTransparencyLayer()
    }
}

// ================= 화면마다 하나씩 까는 투명 판 =================
final class InkWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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

    override var acceptsFirstResponder: Bool { true }
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
        for item in ctl.items { renderInk(item, in: c) }
        cache = c
        cacheImage = c.makeImage()
        needsDisplay = true
    }

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
        if let b = ctl.boardColor {
            ctx.setFillColor(b)
            ctx.fill(dirtyRect)
        }
        ctx.saveGState()
        ctx.setAlpha(CGFloat(Settings.shared.drawOpacity) / 100)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        if let img = cacheImage { ctx.draw(img, in: bounds) }
        ctx.translateBy(x: -origin.x, y: -origin.y)
        if let live = ctl.live { renderInk(live, in: ctx) } // 긋는 중인 획 / 도형 미리보기 / 문지르는 중인 지우개
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.translateBy(x: -origin.x, y: -origin.y)
        ctl.renderOverlays(in: ctx)
        ctx.restoreGState()
    }

    // ---- 입력은 모두 DrawController가 받는다 ----
    private func globalPoint(_ e: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: e.locationInWindow) ?? NSEvent.mouseLocation
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with e: NSEvent) { ctl.cursor.set() }
    override func mouseMoved(with e: NSEvent) { ctl.mouseMoved(globalPoint(e)) }
    override func mouseDown(with e: NSEvent) { window?.makeKey(); ctl.down(globalPoint(e), e, right: false) }
    override func mouseDragged(with e: NSEvent) { ctl.drag(globalPoint(e), e) }
    override func mouseUp(with e: NSEvent) { ctl.up(globalPoint(e)) }
    override func rightMouseDown(with e: NSEvent) { window?.makeKey(); ctl.down(globalPoint(e), e, right: true) }
    override func rightMouseDragged(with e: NSEvent) { ctl.drag(globalPoint(e), e) }
    override func rightMouseUp(with e: NSEvent) { ctl.up(globalPoint(e)) }
    override func scrollWheel(with e: NSEvent) { ctl.scroll(e) }
    override func keyDown(with e: NSEvent) { ctl.keyDown(e) }
    override func keyUp(with e: NSEvent) { ctl.keyUp(e) }
    override func flagsChanged(with e: NSEvent) { ctl.flagsChanged(e) }
    // Cmd+Z 같은 조합이 메뉴로 가서 "삑" 소리가 나지 않도록 여기서 먼저 받는다
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        if e.type == .keyDown { ctl.keyDown(e); return true }
        return false
    }
}

// ================= 드로잉 상태와 동작 =================
final class DrawController {
    private(set) var isOn = false
    var onStateChange: (Bool) -> Void = { _ in }

    private var windows: [InkWindow] = []
    private var views: [InkView] { windows.compactMap { $0.contentView as? InkView } }

    // 그린 것
    private(set) var items: [InkItem] = []
    private var undoFloor = 0 // 이보다 앞은 되돌리지 않는다 (최대 30단계, 끈 뒤 30초)
    private var offSince: Date?

    // 지금 펜
    private var rgb: UInt32 = 0xFF0000
    private var alpha: CGFloat = 1
    private var penStep = 5
    private var eraserStep = 5
    private var pen: PenKind = .normal
    // 마우스를 누른 순간의 펜 종류를 잠근다. 긋는 도중 키로 pen을 바꿔도 이번 획은 끝까지
    // activePen대로 그려지고(hues·points 길이가 어긋나 죽는 일이 없다), 새 pen은 다음 획부터 적용된다.
    private var activePen: PenKind = .normal
    private var rainbowHue: CGFloat = 0
    private var board = 0 // 0 = 투명(Q), 1~3 = W/E/R

    // 긋는 중
    private(set) var live: InkItem?
    private var mode: ShapeMode = .free
    private var start: CGPoint = .zero
    private var lastPoint: CGPoint = .zero
    private var liveBounds: CGRect = .null
    private var erasing = false
    private var rightDown = false
    private var held: Set<UInt16> = [] // 누르고 있는 Z/X/C
    private var scrollAccum: CGFloat = 0

    // 레이저
    private var laser: [[LaserPt]] = []
    private var laserLive: [LaserPt]? = nil
    private var laserTimer: Timer?
    private var mouse: CGPoint = .zero

    // 굵기·진하기를 바꿀 때 잠깐 뜨는 숫자
    private var badge: (text: String, until: Date)?
    private var badgeRect: CGRect = .null

    private var previousApp: NSRunningApplication?
    private(set) var cursor = NSCursor.arrow

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.rebuildWindows()
        }
    }

    // ---------- 켜고 끄기 ----------
    func toggle() { isOn ? turnOff(clear: false) : turnOn() }

    func turnOn() {
        guard !isOn else { return }
        let s = Settings.shared
        // 숫자키로 바꾼 색·굵기는 임시값 — 켤 때마다 설정 창의 값으로 돌아온다
        rgb = s.drawColor; alpha = 1
        penStep = Int(s.drawStep); eraserStep = Int(s.eraserStep)
        pen = .normal
        if let off = offSince, Date().timeIntervalSince(off) > 30 { setUndoFloor(items.count) }
        offSince = nil
        if windows.isEmpty { rebuildWindows() }

        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        isOn = true
        NSApp.activate(ignoringOtherApps: true)
        for w in windows { w.orderFrontRegardless() }
        keyWindowUnderMouse()
        updateCursor()
        onStateChange(true)
    }

    // clear: Esc·위젯 버튼(그린 것과 칠판을 정리하고 나감) / F9(그대로 남겨 두고 나감)
    func turnOff(clear: Bool) {
        guard isOn else { return }
        if clear {
            clearAll()
            board = 0
        }
        cancelLive()
        laser = []; laserLive = nil
        isOn = false
        offSince = Date()
        for w in windows { w.orderOut(nil) }
        NSCursor.arrow.set()
        if let app = previousApp, !app.isTerminated { app.activate() }
        previousApp = nil
        onStateChange(false)
    }

    private func keyWindowUnderMouse() {
        let m = NSEvent.mouseLocation
        (windows.first { $0.frame.contains(m) } ?? windows.first)?.makeKey()
    }

    private func rebuildWindows() {
        for w in windows { w.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let w = InkWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
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
            let v = InkView(frame: NSRect(origin: .zero, size: screen.frame.size), controller: self)
            w.contentView = v
            w.initialFirstResponder = v
            w.makeFirstResponder(v)
            v.rebuildCache()
            return w
        }
        if isOn {
            for w in windows { w.orderFrontRegardless() }
            keyWindowUnderMouse()
        }
    }

    private func invalidate(_ r: CGRect) { for v in views { v.invalidate(global: r) } }
    private func invalidateAll() { for v in views { v.needsDisplay = true } }

    // ---------- 칠판 ----------
    var boardColor: CGColor? {
        guard board > 0 else { return nil }
        let s = Settings.shared
        return color(s.boardColors[board - 1], CGFloat(s.boardAlphas[board - 1]) / 100).cgColor
    }

    // 지우개 테두리는 칠판의 보색 — 어느 칠판 위에서도 묻히지 않는다 (칠판이 없으면 검정)
    private var eraserRingColor: NSColor {
        guard board > 0 else { return .black }
        return color(~Settings.shared.boardColors[board - 1] & 0xFFFFFF)
    }

    // ---------- 커서: 지금 그어질 선과 똑같은 동그라미 ----------
    private func updateCursor() {
        let d: CGFloat
        let img: NSImage
        if erasing || rightDown {
            d = eraserPx(eraserStep)
            let side = ceil(d + 4)
            img = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
                let p = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: d, height: d))
                p.lineWidth = 1.5
                self.eraserRingColor.setStroke()
                p.stroke()
                return true
            }
        } else if pen == .laser {
            d = max(penPx(penStep), LASER_MIN_WIDTH) * 3
            let c = color(rgb)
            img = NSImage(size: NSSize(width: d, height: d), flipped: false) { _ in
                for (mul, a, mix) in LASER_LAYERS {
                    let dd = d / 3 * mul * 1.1
                    NSColor(cgColor: tint(c.cgColor, mix))!.withAlphaComponent(a).setFill()
                    NSBezierPath(ovalIn: NSRect(x: (d - dd) / 2, y: (d - dd) / 2, width: dd, height: dd)).fill()
                }
                return true
            }
        } else {
            d = penPx(penStep)
            let side = max(ceil(d) + 2, 4)
            let fill = pen == .rainbow ? NSColor(cgColor: hueColor(rainbowHue))!.withAlphaComponent(alpha) : color(rgb, alpha)
            img = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
                fill.setFill()
                NSBezierPath(ovalIn: NSRect(x: (side - d) / 2, y: (side - d) / 2, width: d, height: d)).fill()
                return true
            }
        }
        cursor = NSCursor(image: img, hotSpot: NSPoint(x: img.size.width / 2, y: img.size.height / 2))
        if isOn { cursor.set() }
    }

    // ---------- 마우스 ----------
    func mouseMoved(_ p: CGPoint) {
        mouse = p
        cursor.set()
    }

    func down(_ p: CGPoint, _ e: NSEvent, right: Bool) {
        mouse = p
        start = p; lastPoint = p
        activePen = pen
        if right { rightDown = true }
        if right || e.modifierFlags.contains(.option) {
            // 지우개: 오른쪽 버튼으로 문지르기 (트랙패드에서는 ⌥ Option을 누른 채 끌기)
            erasing = true
            updateCursor()
            live = InkItem(kind: .erase, points: [p], width: eraserPx(eraserStep))
            liveBounds = live!.bounds
            invalidate(liveBounds)
            return
        }
        mode = currentShape(e.modifierFlags)
        if activePen == .laser {
            if mode == .free {
                laserLive = [LaserPt(p: p, t: Date.timeIntervalSinceReferenceDate, hue: nil)]
                startLaserTimer()
            } else {
                laserLive = []
            }
            return
        }
        let w = penPx(penStep)
        live = InkItem(kind: .stroke, points: [p], width: w, rgb: rgb, alpha: alpha,
                       hues: activePen == .rainbow ? [rainbowHue] : nil)
        liveBounds = live!.bounds
        invalidate(liveBounds)
    }

    func drag(_ p: CGPoint, _ e: NSEvent) {
        mouse = p
        if erasing, var item = live {
            item.points.append(p)
            live = item
            invalidate(segmentBounds(lastPoint, p, item.width))
            lastPoint = p
            return
        }
        if activePen == .laser, laserLive != nil {
            let now = Date.timeIntervalSinceReferenceDate
            if mode == .free {
                laserLive!.append(LaserPt(p: p, t: now, hue: nil))
            } else {
                let end = shapeEnd(p, e.modifierFlags)
                laserLive = shapePoints(mode, start, end, width: laserWidth).map { LaserPt(p: $0, t: now, hue: nil) }
            }
            lastPoint = p
            return
        }
        guard var item = live else { return }
        if mode == .free {
            if activePen == .rainbow {
                rainbowHue = (rainbowHue + hypot(p.x - lastPoint.x, p.y - lastPoint.y) * 360 / RAINBOW_CYCLE_PX)
                    .truncatingRemainder(dividingBy: 360)
                item.hues?.append(rainbowHue)
            }
            item.points.append(p)
            live = item
            // 반투명 획은 획 전체를 한 겹으로 다시 얹으므로 지나온 자리 전체를, 불투명하면 새 토막만 다시 그린다
            invalidate(item.alpha < 1 || activePen == .rainbow ? item.bounds : segmentBounds(lastPoint, p, item.width))
        } else {
            refreshShape(end: shapeEnd(p, e.modifierFlags))
        }
        lastPoint = p
    }

    func up(_ p: CGPoint) {
        rightDown = false
        if erasing {
            erasing = false
            // 움직이지 않은 오른쪽 클릭·⌥ 클릭(트랙패드 두 손가락 탭 포함)은 아무것도 지우지 않고
            // 실행 취소 단계도 남기지 않는다
            if let item = live, item.points.count > 1 { commit(item) }
            live = nil
            updateCursor()
            return
        }
        if activePen == .laser, let pts = laserLive {
            // 도형은 손을 뗀 순간부터 함께 사라진다
            let now = Date.timeIntervalSinceReferenceDate
            if !pts.isEmpty { laser.append(mode == .free ? pts : pts.map { LaserPt(p: $0.p, t: now, hue: $0.hue) }) }
            laserLive = nil
            startLaserTimer()
            return
        }
        guard let item = live else { return }
        if activePen == .rainbow, mode != .free, let h = item.hues?.last { rainbowHue = h }
        commit(item)
        live = nil
        updateCursor()
    }

    private var laserWidth: CGFloat { max(penPx(penStep), LASER_MIN_WIDTH) }

    private func currentShape(_ f: NSEvent.ModifierFlags) -> ShapeMode {
        if held.contains(6) { return .line }   // Z
        if held.contains(7) { return .wave }   // X
        if held.contains(8) { return .arrow }  // C
        if f.contains(.shift) { return .rect }
        if f.contains(.control) { return .ellipse }
        return .free
    }

    private func shapeEnd(_ p: CGPoint, _ f: NSEvent.ModifierFlags) -> CGPoint {
        [.line, .wave, .arrow].contains(mode) && f.contains(.shift) ? snap45(start, p) : p
    }

    private func refreshShape(end: CGPoint) {
        guard var item = live else { return }
        item.points = shapePoints(mode, start, end, width: item.width)
        if activePen == .rainbow {
            // 테두리를 따라 색이 돈다. 미리보기는 매번 획을 시작한 색에서 다시 출발한다.
            var h = item.hues?.first ?? rainbowHue
            var hues: [CGFloat] = [h]
            for i in 1..<item.points.count {
                h += hypot(item.points[i].x - item.points[i - 1].x, item.points[i].y - item.points[i - 1].y) * 360 / RAINBOW_CYCLE_PX
                hues.append(h.truncatingRemainder(dividingBy: 360))
            }
            item.hues = hues
        }
        let nb = item.bounds
        invalidate(liveBounds.union(nb))
        liveBounds = nb
        live = item
    }

    private func segmentBounds(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)).insetBy(dx: -w - 2, dy: -w - 2)
    }

    private func cancelLive() {
        if live != nil { invalidate(liveBounds.union(live!.bounds)) }
        live = nil; erasing = false; rightDown = false; held = []
    }

    // ---------- 목록 다루기 ----------
    private func commit(_ item: InkItem) {
        items.append(item)
        for v in views { v.commit(item) }
        setUndoFloor(max(undoFloor, items.count - 30))
    }

    private func setUndoFloor(_ f: Int) {
        undoFloor = f
        // 되돌릴 수 없는 곳에 "전부 지우기"가 있으면 그 앞은 더 들고 있을 이유가 없다
        if let idx = items[..<undoFloor].lastIndex(where: { $0.kind == .clear }) {
            items.removeSubrange(0...idx)
            undoFloor -= idx + 1
        }
    }

    func undo() {
        guard items.count > undoFloor else { return }
        items.removeLast()
        for v in views { v.rebuildCache() }
    }

    func clearAll() {
        guard let last = items.last, last.kind != .clear else { return }
        commit(InkItem(kind: .clear))
    }

    // ---------- 휠: 지금 쓰는 색을 진하게 / 연하게 ----------
    func scroll(_ e: NSEvent) {
        scrollAccum += e.hasPreciseScrollingDeltas ? e.scrollingDeltaY / 12 : e.scrollingDeltaY
        while abs(scrollAccum) >= 1 {
            let dir: CGFloat = scrollAccum > 0 ? 1 : -1
            scrollAccum -= dir
            alpha = max(0.05, min(1, ((alpha * 100).rounded() + 5 * dir) / 100))
        }
        showBadge("\(Int((alpha * 100).rounded()))%")
        updateCursor()
    }

    // ---------- 키보드 ----------
    // 글자가 아니라 키 자리(keyCode)로 본다 — 한글 입력 상태에서도 똑같이 동작하게.
    private static let digitKeys: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 0,
                                                   83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9, 82: 0]

    func keyDown(_ e: NSEvent) {
        let k = e.keyCode
        let f = e.modifierFlags
        // ⌘Z / Ctrl+Z만 실행 취소로 쓴다. ⌘⇧Z(다시 실행이 아니다, 그냥 무시)는 걸러낸다.
        if !f.contains(.shift), f.contains(.command) || f.contains(.control), k == 6 { undo(); return }
        if f.contains(.command) { return }
        switch k {
        case 53: turnOff(clear: true)                              // Esc
        case 51, 117: clearAll()                                   // delete / 앞으로 지우기
        case 6, 7, 8: if !e.isARepeat { held.insert(k) }           // Z X C: 누르고 있는 동안 도형
        case 0: pen = .laser; updateCursor()                       // A
        case 1: pen = .rainbow; updateCursor()                     // S
        case 12: board = 0; invalidateAll(); updateCursor()        // Q
        case 13: board = 1; invalidateAll(); updateCursor()        // W
        case 14: board = 2; invalidateAll(); updateCursor()        // E
        case 15: board = 3; invalidateAll(); updateCursor()        // R
        case 24, 69: adjustSize(+1, eraser: rightDown || f.contains(.option)) // = + (키패드 +)
        case 27, 78: adjustSize(-1, eraser: rightDown || f.contains(.option)) // - (키패드 -)
        default:
            if let d = DrawController.digitKeys[k] {
                let s = Settings.shared
                if d == 0 { rgb = s.drawColor; alpha = 1 } else {
                    rgb = s.drawKeyColors[d - 1]; alpha = CGFloat(s.drawKeyAlphas[d - 1]) / 100
                }
                pen = .normal
                updateCursor()
            }
        }
    }

    func keyUp(_ e: NSEvent) { held.remove(e.keyCode) }

    func flagsChanged(_ e: NSEvent) {
        // Shift를 드래그 도중에 눌러도 방향 맞춤이 바로 따라온다
        if live != nil, !erasing, mode != .free { refreshShape(end: shapeEnd(mouse, e.modifierFlags)) }
    }

    private func adjustSize(_ delta: Int, eraser: Bool) {
        if eraser {
            eraserStep = max(1, min(STEP_MAX, eraserStep + delta))
            showBadge("\(eraserStep)")
        } else {
            penStep = max(1, min(STEP_MAX, penStep + delta))
            showBadge("\(penStep)")
        }
        updateCursor()
    }

    // ---------- 레이저·숫자 표시 그리기 ----------
    func renderOverlays(in ctx: CGContext) {
        let now = Date.timeIntervalSinceReferenceDate
        var strokes = laser
        if let l = laserLive, !l.isEmpty {
            strokes.append(mode == .free ? l : l.map { LaserPt(p: $0.p, t: now, hue: $0.hue) })
        }
        if !strokes.isEmpty {
            renderLaser(strokes, baseColor: color(rgb).cgColor, width: laserWidth, now: now, in: ctx)
        }
        if let b = badge, Date() < b.until {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                                                        .foregroundColor: NSColor.white]
            let str = NSAttributedString(string: b.text, attributes: attrs)
            let r = badgeRect
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSColor(white: 0.1, alpha: 0.8).setFill()
            NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7).fill()
            str.draw(at: NSPoint(x: r.midX - str.size().width / 2, y: r.midY - str.size().height / 2))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // 커서 오른쪽 위, 늘 같은 자리에 잠깐 뜬다 (굵기가 바뀌어도 숫자가 따라 움직이지 않는다)
    private func showBadge(_ text: String) {
        invalidate(badgeRect)
        let m = NSEvent.mouseLocation
        let w = CGFloat(max(34, text.count * 10 + 16))
        badgeRect = CGRect(x: m.x + 28, y: m.y + 14, width: w, height: 26)
        let until = Date().addingTimeInterval(0.5)
        badge = (text, until)
        invalidate(badgeRect)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self, let b = self.badge, b.until == until else { return }
            self.badge = nil
            self.invalidate(self.badgeRect)
        }
    }

    private func startLaserTimer() {
        guard laserTimer == nil else { return }
        var lastBox: CGRect = .null
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let now = Date.timeIntervalSinceReferenceDate
            // 다 사라진 점은 버린다
            self.laser = self.laser.compactMap { s in
                let alive = s.filter { laserLife($0.t, now) > 0 }
                return alive.isEmpty ? nil : alive
            }
            var box = CGRect.null
            for s in self.laser + [self.laserLive ?? []] { for p in s { box = box.union(CGRect(origin: p.p, size: .zero)) } }
            let pad = self.laserWidth * 3 + 4
            box = box.isNull ? box : box.insetBy(dx: -pad, dy: -pad)
            self.invalidate(lastBox.union(box))
            lastBox = box
            if self.laser.isEmpty && self.laserLive == nil {
                timer.invalidate()
                self.laserTimer = nil
            }
        }
        RunLoop.main.add(t, forMode: .common)
        laserTimer = t
    }

    func applySettings() { invalidateAll() }
}
