import AppKit

// 그림을 만드는 공통 길 (S2a). 화면(InkView)도 자체 점검의 기준 그림(Golden.swift)도 여기를 지난다.
// 창·화면·설정 파일을 읽지 않는다 — 넘겨받은 값만으로 그려서, 어디서 돌려도 같은 그림이 나와야 한다.

// 되돌리기 30단계, 끈 뒤 이 시간이 지나면 되돌리기를 비운다 (선생님 결정 ③은 10분 — S5에서 600으로 바꾼다)
let UNDO_MAX = 30
let UNDO_KEEP_S: TimeInterval = 30

// 판에 그림을 합치는 순서: 칠판 색을 깔고, 잉크는 층 하나로 묶어 전체 진하기를 한 번에 곱한다.
// body 안에서 잉크를 그린다. (InkView.draw와 renderScene이 같이 쓴다)
func paintInkLayer(in ctx: CGContext, fill: CGRect, board: CGColor?, opacity: Double, _ body: () -> Void) {
    if let b = board {
        ctx.setFillColor(b)
        ctx.fill(fill)
    }
    ctx.saveGState()
    ctx.setAlpha(CGFloat(opacity) / 100)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    body()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

struct LaserScene {
    var strokes: [[LaserPt]]
    var color: CGColor
    var width: CGFloat
}

// 획 목록 → 그림 한 장. 좌표는 왼쪽 아래가 원점인 포인트, 픽셀은 scale로만 곱한다. 바탕은 투명.
func renderScene(items: [InkItem], live: InkItem? = nil, board: CGColor? = nil, opacity: Double = 100,
                 size: CGSize, scale: CGFloat = 1, laser: LaserScene? = nil, now: TimeInterval = 0) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                              bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.scaleBy(x: scale, y: scale)
    paintInkLayer(in: ctx, fill: CGRect(origin: .zero, size: size), board: board, opacity: opacity) {
        for item in items { renderInk(item, in: ctx) }
        if let live { renderInk(live, in: ctx) }
    }
    if let l = laser, !l.strokes.isEmpty {
        renderLaser(l.strokes, baseColor: l.color, width: l.width, now: now, in: ctx)
    }
    return ctx.makeImage()
}

// ---------- 커서 그림 (판 위에 붓 모양·지우개 링·레이저 점) ----------
func brushCursorImage(diameter d: CGFloat, fill: NSColor) -> NSImage {
    let side = max(ceil(d) + 2, 4)
    return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
        fill.setFill()
        NSBezierPath(ovalIn: NSRect(x: (side - d) / 2, y: (side - d) / 2, width: d, height: d)).fill()
        return true
    }
}

// 지우개 테두리는 칠판의 보색 — 어느 칠판 위에서도 묻히지 않는다 (칠판이 없으면 검정)
func eraserRingColor(boardRGB: UInt32?) -> NSColor {
    guard let rgb = boardRGB else { return .black }
    return color(~rgb & 0xFFFFFF)
}

func eraserRingImage(diameter d: CGFloat, ring: NSColor) -> NSImage {
    let side = ceil(d + 4)
    return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
        let p = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: d, height: d))
        p.lineWidth = 1.5
        ring.setStroke()
        p.stroke()
        return true
    }
}

func laserCursorImage(side d: CGFloat, base: NSColor) -> NSImage {
    NSImage(size: NSSize(width: d, height: d), flipped: false) { _ in
        for (mul, a, mix) in LASER_LAYERS {
            let dd = d / 3 * mul * 1.1
            NSColor(cgColor: tint(base.cgColor, mix))!.withAlphaComponent(a).setFill()
            NSBezierPath(ovalIn: NSRect(x: (d - dd) / 2, y: (d - dd) / 2, width: dd, height: dd)).fill()
        }
        return true
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
