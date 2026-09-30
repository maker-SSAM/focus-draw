import AppKit

// 그림을 만드는 공통 길 (S2a). 화면(InkView)도 자체 점검의 기준 그림(Dev/Golden.swift)도 여기를 지난다.
// 창·화면·설정 파일을 읽지 않는다 — 넘겨받은 값만으로 그려서, 어디서 돌려도 같은 그림이 나와야 한다.

// ---------- 색 ----------
func color(_ rgb: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
}

func rgbOf(_ c: NSColor) -> UInt32 {
    guard let s = c.usingColorSpace(.sRGB) else { return 0 }
    func b(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
    return (b(s.redComponent) << 16) | (b(s.greenComponent) << 8) | b(s.blueComponent)
}

func hueColor(_ h: CGFloat) -> CGColor {
    let hh = h.truncatingRemainder(dividingBy: 360)
    let x = 1 - abs((hh / 60).truncatingRemainder(dividingBy: 2) - 1)
    let rgb: (CGFloat, CGFloat, CGFloat) =
        hh < 60 ? (1, x, 0) : hh < 120 ? (x, 1, 0) : hh < 180 ? (0, 1, x) :
        hh < 240 ? (0, x, 1) : hh < 300 ? (x, 0, 1) : (1, 0, x)
    return CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
}

// ---------- 획 하나 ----------
// 반투명한 획은 먼저 불투명하게 그린 뒤 통째로 한 번에 옅게 얹는다 —
// 그래야 한 획 안에서 같은 자리를 여러 번 지나가도 이음매가 진해지지 않는다.
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

// ---------- 사라지는 펜 (레이저) ----------
struct LaserPt { var p: CGPoint; var t: TimeInterval; var hue: CGFloat? }

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
