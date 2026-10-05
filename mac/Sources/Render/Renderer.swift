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
        if let h = item.head, h.count == 3 {
            // 머리는 테두리가 아니라 채운다. 무지개는 몸통이 끝난 색.
            let c = item.hues.flatMap(\.last).map(hueColor) ?? color(item.rgb).cgColor
            ctx.setFillColor(c)
            ctx.move(to: h[0]); ctx.addLine(to: h[1]); ctx.addLine(to: h[2]); ctx.closePath()
            ctx.fillPath()
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
// rgb: 그은 때의 색 — 꼬리가 사라지는 동안 펜 색을 바꿔도 이 획은 자기 색 그대로 (nil이면 그리는 쪽이 넘긴 기본색)
struct LaserPt { var p: CGPoint; var t: TimeInterval; var hue: CGFloat?; var rgb: UInt32? = nil }

func laserLife(_ t: TimeInterval, _ now: TimeInterval) -> CGFloat {
    let age = now - t
    return age <= LASER_HOLD ? 1 : CGFloat(max(0, 1 - (age - LASER_HOLD) / LASER_FADE))
}

func tint(_ c: CGColor, _ mix: CGFloat) -> CGColor {
    guard mix > 0, let comp = NSColor(cgColor: c)?.usingColorSpace(.sRGB) else { return c }
    func m(_ v: CGFloat) -> CGFloat { v + (1 - v) * mix }
    return CGColor(srgbRed: m(comp.redComponent), green: m(comp.greenComponent), blue: m(comp.blueComponent), alpha: 1)
}

// 빛 번짐: 바깥쪽을 겹친 층 몇 장이 아니라 촘촘한 층 여러 장으로 그려서 가장자리가 계단 없이 부드럽게 옅어진다.
// (굵기 배율, 진하기, 흰빛 섞기). 바깥에서 안쪽으로 갈수록 좁고 진하다. 붓 동그라미(BrushCursor)도 이 층을 쓴다. (옛 LASER_LAYERS는 Windows 판과 같은 값을 확인하는 점검에만 남겨 둔다)
let LASER_GLOW_LAYERS: [(CGFloat, CGFloat, CGFloat)] = {
    var l: [(CGFloat, CGFloat, CGFloat)] = []
    let n = 9
    for i in 0..<n {
        let u = CGFloat(i) / CGFloat(n - 1)              // 0 = 가장 바깥, 1 = 번짐의 안쪽 끝
        let mul = 3.0 - (3.0 - 1.0) * u                   // 3.0 → 1.0
        let alpha = 0.045 + 0.10 * u * u                  // 안쪽으로 갈수록 진해지는 완만한 곡선
        l.append((mul, alpha, 0))
    }
    l.append((0.75, 1.0, 0))                              // 본체
    l.append((0.3, 0.9, 0.6))                             // 흰 심
    return l
}()

// 빨리 움직여 점이 듬성듬성해도 선이 꺾이거나 끊겨 보이지 않게, 점 사이를 부드러운 곡선(Catmull-Rom)으로 이어
// 약 3pt 간격의 점으로 채운다. 시각·색조는 양 끝에서 이어 준다.
func smoothLaser(_ s: [LaserPt], step: CGFloat = 5) -> [LaserPt] {
    guard s.count > 2 else { return s }
    var out: [LaserPt] = [s[0]]
    for i in 0..<(s.count - 1) {
        let p0 = s[max(0, i - 1)].p, p1 = s[i].p, p2 = s[i + 1].p, p3 = s[min(s.count - 1, i + 2)].p
        let dist = hypot(p2.x - p1.x, p2.y - p1.y)
        let n = min(40, max(1, Int((dist / step).rounded(.up))))
        if n > 1 {
            for k in 1..<n {
                let t = CGFloat(k) / CGFloat(n), t2 = t * t, t3 = t2 * t
                func c(_ a: CGFloat, _ b: CGFloat, _ cc: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * ((2 * b) + (-a + cc) * t + (2 * a - 5 * b + 4 * cc - d) * t2 + (-a + 3 * b - 3 * cc + d) * t3)
                }
                let hue: CGFloat? = {
                    guard let h1 = s[i].hue, let h2 = s[i + 1].hue else { return s[i].hue }
                    return h1 + (h2 - h1) * t
                }()
                out.append(LaserPt(p: CGPoint(x: c(p0.x, p1.x, p2.x, p3.x), y: c(p0.y, p1.y, p2.y, p3.y)),
                                   t: s[i].t + (s[i + 1].t - s[i].t) * Double(t), hue: hue, rgb: s[i].rgb))
            }
        }
        out.append(s[i + 1])
    }
    return out
}

func renderLaser(_ strokes: [[LaserPt]], baseColor: CGColor, width: CGFloat, now: TimeInterval, in ctx: CGContext) {
    ctx.saveGState()
    defer { ctx.restoreGState() }
    let strokes = strokes.map { smoothLaser($0) }
    func colorOf(_ p: LaserPt) -> CGColor { p.hue.map(hueColor) ?? p.rgb.map { color($0).cgColor } ?? baseColor }
    func colorKey(_ p: LaserPt) -> Int { p.hue.map { Int($0 / 3) } ?? p.rgb.map { Int($0) } ?? -1 }
    // 한 획을 "리본"(점마다 굵기가 다른 띠)으로 만들어 한 번에 채운다. 선분마다 따로 그으면 이음매가 점처럼 보이고(둥근 끝이 겹침)
    // 느리다. 층 사이는 투명 층(transparency layer)을 쓰지 않고 차례로 얹는다 — 층마다 큰 그림을 만드는 비용이 가장 컸다.
    // 색이 점마다 달라지는 획(색조·획마다 다른 색)만 색이 같은 구간별로 나눈다.
    func ribbon(_ s: [LaserPt], _ lo: Int, _ hi: Int, _ mul: CGFloat) -> CGPath {
        let path = CGMutablePath()
        // 보이는 점만 (사라진 꼬리 앞쪽 점과 겹친 점은 뺀다)
        var idx: [Int] = []
        for i in lo...hi where laserLife(s[i].t, now) > 0 {
            if let l = idx.last, hypot(s[i].p.x - s[l].p.x, s[i].p.y - s[l].p.y) < 0.05 { continue }
            idx.append(i)
        }
        guard idx.count >= 2 else { return path }
        // 굵기는 남은 수명을 부드럽게(smoothstep) 바꾼 값을 쓴다: 머무는 시간이 끝나는 순간 굵기가 일정한 비율로 줄기 시작하면
        // 그 자리에서 꺾여 "뚝 끊기는" 느낌이 나므로, 줄기 시작할 때는 천천히 시작해 서서히 빨라지게 한다.
        func half(_ i: Int) -> CGFloat { let l = laserLife(s[i].t, now); return max(0.25, width * mul * l * l * (3 - 2 * l) / 2) }
        // 선분마다 굵기가 이어지는 사각형(앞 점 굵기 → 뒤 점 굵기)을 놓고, 크게 꺾이는 점에는 원을 얹어 바깥쪽 틈을 메운다.
        // 모두 같은 감는 방향이라 한 길로 채우면 합집합이 된다 — 겹쳐도 진해지지 않고, 위로 긋다 급히 내려올 때처럼 뾰족하게
        // 되꺾이는 곳도 끊기지 않는다. (양쪽 가장자리 두 줄을 이어 한 띠로 만드는 방식은 굵기가 꺾이는 반지름보다 크면 꼬여 뚝 끊겨 보였다)
        func dot(_ i: Int) {
            let r = half(i)
            path.addEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r),
                            transform: CGAffineTransform(translationX: s[i].p.x, y: s[i].p.y).scaledBy(x: 1, y: -1))
        }
        var prevDir: CGPoint?
        for n in 1..<idx.count {
            let a = s[idx[n - 1]].p, b = s[idx[n]].p
            let dx = b.x - a.x, dy = b.y - a.y
            let len = hypot(dx, dy)
            let ux = dx / len, uy = dy / len
            let ha = half(idx[n - 1]), hb = half(idx[n])
            path.move(to: CGPoint(x: a.x - uy * ha, y: a.y + ux * ha))
            path.addLine(to: CGPoint(x: b.x - uy * hb, y: b.y + ux * hb))
            path.addLine(to: CGPoint(x: b.x + uy * hb, y: b.y - ux * hb))
            path.addLine(to: CGPoint(x: a.x + uy * ha, y: a.y - ux * ha))
            path.closeSubpath()
            if let d = prevDir {
                let turn = abs(atan2(d.x * uy - d.y * ux, d.x * ux + d.y * uy))   // 꺾인 각도
                if ha * turn > 0.6 { dot(idx[n - 1]) }
            }
            prevDir = CGPoint(x: ux, y: uy)
        }
        dot(idx[0])
        dot(idx[idx.count - 1])
        return path
    }
    for (mul, alpha, mix) in LASER_GLOW_LAYERS {
        ctx.setAlpha(alpha)
        for s in strokes {
            if s.count == 1 {
                let life = laserLife(s[0].t, now)
                let d = width * mul * life
                ctx.setFillColor(tint(colorOf(s[0]), mix))
                ctx.fillEllipse(in: CGRect(x: s[0].p.x - d / 2, y: s[0].p.y - d / 2, width: d, height: d))
                continue
            }
            var lo = 0
            while lo < s.count - 1 {
                var hi = lo + 1
                let k = colorKey(s[lo + 1])
                while hi + 1 < s.count && colorKey(s[hi + 1]) == k { hi += 1 }
                ctx.setFillColor(tint(colorOf(s[lo + 1]), mix))
                ctx.addPath(ribbon(s, lo, hi, mul))
                ctx.fillPath(using: .winding)
                lo = hi
            }
        }
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
