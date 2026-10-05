import AppKit

// 레이저 모양 그림 뽑기: FocusDraw --laserpic <폴더>
// 앱이 레이저를 그리는 코드(renderLaser)를 그대로 불러 몇 시점의 그림을 PNG로 저장한다. 화면 캡처 없이 모양을 눈으로 볼 수 있게 하려는 것.
// (화면 합성이 더해지기 전의 그림이라 실제 화면과 아주 조금 다를 수 있다.)
@MainActor enum LaserPic {
    static func run(out: String) {
        let dir = URL(fileURLWithPath: out)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let size = CGSize(width: 520, height: 150)
        let scale: CGFloat = 3
        let width = max(penPx(5), LASER_MIN_WIDTH)
        // 천천히 그은 S자 (60Hz, 점 간격 약 3pt) — 처음 쪽은 사라지고 끝 쪽은 선명한 모양이 나오게 1초 동안
        func curve(_ t0: TimeInterval, count: Int = 60) -> [LaserPt] {
            (0..<count).map { i in
                let u = CGFloat(i) / CGFloat(count - 1)
                return LaserPt(p: CGPoint(x: 30 + u * 460, y: 75 + sin(u * 6.28) * 38), t: t0 + Double(i) / Double(count) , hue: nil, rgb: nil)
            }
        }
        func panel(_ title: String, rgb: UInt32, bg: NSColor, count: Int = 60, width width: CGFloat = width, now: (TimeInterval) -> TimeInterval) -> CGImage? {
            let s = curve(0, count: count)
            let laser = LaserScene(strokes: [s], color: color(rgb).cgColor, width: width)
            guard let img = renderScene(items: [], size: size, scale: scale, laser: laser, now: now(s.last!.t)) else { return nil }
            guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.setFillColor(bg.cgColor); ctx.fill(CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
            ctx.draw(img, in: CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
            return ctx.makeImage()
        }
        // 위에서부터: 긋는 중(끝점 now) 빨강·어두운 바탕, 긋고 0.25초 뒤, 노랑·흰 바탕
        // 위로 곧게 긋다가 빨리 내려오는 획 (맨 위에 머무는 시간이 짧다) — 가장 굵은 펜
        func uturn(_ now: TimeInterval, w: CGFloat) -> CGImage? {
            let up = (0..<40).map { i in LaserPt(p: CGPoint(x: 260, y: 20 + CGFloat(i) * 3), t: Double(i) / 120, hue: nil, rgb: nil) }
            let down = (1..<14).map { i in LaserPt(p: CGPoint(x: 270, y: 137 - CGFloat(i) * 8.5), t: 0.33 + Double(i) / 120, hue: nil, rgb: nil) }
            let s = up + down
            let laser = LaserScene(strokes: [s], color: color(0xFF0000).cgColor, width: w)
            guard let img = renderScene(items: [], size: size, scale: scale, laser: laser, now: now) else { return nil }
            guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.setFillColor(NSColor(white: 0.16, alpha: 1).cgColor); ctx.fill(CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
            ctx.draw(img, in: CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
            return ctx.makeImage()
        }
        let mx = max(penPx(STEP_MAX), LASER_MIN_WIDTH)
        let panels: [CGImage?] = [
            uturn(0.45, w: mx), uturn(0.62, w: mx), uturn(0.8, w: mx), uturn(0.62, w: width),
            panel("drawing", rgb: 0xFF0000, bg: NSColor(white: 0.16, alpha: 1), now: { $0 }),
            panel("after0.25", rgb: 0xFF0000, bg: NSColor(white: 0.16, alpha: 1), now: { $0 + 0.25 }),
            panel("yellow-white", rgb: 0xFFFF00, bg: .white, now: { $0 }),
            panel("fast", rgb: 0xFF0000, bg: NSColor(white: 0.16, alpha: 1), count: 11, now: { $0 }),   // 빨리 움직여 점이 듬성듬성한 획
            // 펜 굵기를 가장 굵게 했을 때: 긋는 중, 긋고 0.2·0.4·0.6초 뒤
            panel("max-draw", rgb: 0xFF0000, bg: NSColor(white: 0.16, alpha: 1), width: max(penPx(STEP_MAX), LASER_MIN_WIDTH), now: { $0 }),
            panel("max-0.2", rgb: 0xFF0000, bg: NSColor(white: 0.16, alpha: 1), width: max(penPx(STEP_MAX), LASER_MIN_WIDTH), now: { $0 + 0.2 }),
            panel("max-0.4", rgb: 0xFF0000, bg: NSColor(white: 0.16, alpha: 1), width: max(penPx(STEP_MAX), LASER_MIN_WIDTH), now: { $0 + 0.4 }),
            panel("max-0.6", rgb: 0xFF0000, bg: NSColor(white: 0.16, alpha: 1), width: max(penPx(STEP_MAX), LASER_MIN_WIDTH), now: { $0 + 0.6 }),
        ]
        let h = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: h * panels.count, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        for (i, p) in panels.enumerated() {
            if let p { ctx.draw(p, in: CGRect(x: 0, y: (panels.count - 1 - i) * h, width: Int(size.width * scale), height: h)) }
        }
        if let all = ctx.makeImage() {
            let rep = NSBitmapImageRep(cgImage: all)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("laser-now.png"))
        }
        // 무지개: 자유선 레이저(보통·가장 굵게), 도형, 커서(무지개 펜 점·무지개 레이저)
        do {
            let W = 520.0, H = 420.0
            let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.scaleBy(x: scale, y: scale)
            ctx.setFillColor(NSColor(white: 0.16, alpha: 1).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            func free(_ y: CGFloat) -> [LaserPt] {
                var h: CGFloat = 0
                var out: [LaserPt] = []
                for i in 0..<70 {
                    let u = CGFloat(i) / 69
                    let p = CGPoint(x: 30 + u * 460, y: y + sin(u * 6.28) * 30)
                    if let l = out.last { h = (h + hypot(p.x - l.p.x, p.y - l.p.y) * 360 / RAINBOW_CYCLE_PX).truncatingRemainder(dividingBy: 360) }
                    out.append(LaserPt(p: p, t: Double(i) / 70, hue: h, rgb: nil))
                }
                return out
            }
            renderLaser([free(360)], baseColor: color(0xFF0000).cgColor, width: width, now: 1.0, in: ctx)
            renderLaser([free(270)], baseColor: color(0xFF0000).cgColor, width: max(penPx(STEP_MAX), LASER_MIN_WIDTH), now: 1.0, in: ctx)
            let shapes = [rainbowize(laserShape(.rect, CGPoint(x: 40, y: 120), CGPoint(x: 160, y: 190), width: width, t: 0, rgb: nil), from: 0),
                          rainbowize(laserShape(.ellipse, CGPoint(x: 190, y: 120), CGPoint(x: 330, y: 190), width: width, t: 0, rgb: nil), from: 120),
                          rainbowize(laserShape(.wave, CGPoint(x: 360, y: 130), CGPoint(x: 490, y: 180), width: width, t: 0, rgb: nil), from: 240)]
            renderLaser(shapes, baseColor: color(0xFF0000).cgColor, width: width, now: 0.1, in: ctx)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            for (i, img) in [rainbowDotImage(diameter: penPx(5), alpha: 1), rainbowDotImage(diameter: penPx(STEP_MAX), alpha: 1),
                             laserCursorImage(side: width * 3, base: .red, rainbowGlowHue: 200),
                             laserCursorImage(side: max(penPx(STEP_MAX), LASER_MIN_WIDTH) * 3, base: .red, rainbowGlowHue: 200)].enumerated() {
                let cx = 70 + CGFloat(i) * 120
                img.draw(in: NSRect(x: cx - img.size.width / 2, y: 55 - img.size.height / 2, width: img.size.width, height: img.size.height))
            }
            NSGraphicsContext.restoreGraphicsState()
            if let img = ctx.makeImage() {
                try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("rainbow.png"))
            }
        }
        // 겹쳐 긋기: 같은 자리를 좌우로 여러 번 오가는 획과, 고리처럼 자기 자신을 가로지르는 획 (보통 레이저·무지개 레이저)
        do {
            let W = 520.0, H = 300.0
            let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.scaleBy(x: scale, y: scale)
            ctx.setFillColor(NSColor(white: 0.16, alpha: 1).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            func zig(_ x0: CGFloat, _ y: CGFloat) -> [LaserPt] {
                var out: [LaserPt] = []
                for i in 0..<160 {
                    let u = CGFloat(i) / 40                       // 4번 오감
                    let f = u.truncatingRemainder(dividingBy: 2)
                    let x = x0 + (f < 1 ? f : 2 - f) * 180
                    out.append(LaserPt(p: CGPoint(x: x, y: y + CGFloat(i) * 0.15), t: Double(i) / 160, hue: nil, rgb: nil))
                }
                return out
            }
            func loop(_ cx: CGFloat, _ cy: CGFloat) -> [LaserPt] {
                (0..<120).map { i in
                    let u = CGFloat(i) / 119 * 2.2 * .pi
                    return LaserPt(p: CGPoint(x: cx + CGFloat(i) * 0.9 - 50 + cos(u) * 45, y: cy + sin(u) * 45), t: Double(i) / 120, hue: nil, rgb: nil)
                }
            }
            func hue(_ s: [LaserPt]) -> [LaserPt] {
                var h: CGFloat = 0
                return s.enumerated().map { i, pt in
                    if i > 0 { h = (h + hypot(pt.p.x - s[i - 1].p.x, pt.p.y - s[i - 1].p.y) * 360 / RAINBOW_CYCLE_PX).truncatingRemainder(dividingBy: 360) }
                    return LaserPt(p: pt.p, t: pt.t, hue: h, rgb: nil)
                }
            }
            let big = max(penPx(8), LASER_MIN_WIDTH)
            renderLaser([zig(40, 225)], baseColor: color(0xFF0000).cgColor, width: big, now: 1.0, in: ctx)
            renderLaser([hue(zig(290, 225))], baseColor: color(0xFF0000).cgColor, width: big, now: 1.0, in: ctx)
            renderLaser([loop(130, 80)], baseColor: color(0xFF0000).cgColor, width: big, now: 1.0, in: ctx)
            renderLaser([hue(loop(380, 80))], baseColor: color(0xFF0000).cgColor, width: big, now: 1.0, in: ctx)
            // 무지개 레이저로 선 4개를 차례로 겹쳐 긋기 (색은 획마다 이어진다 → 둘레 빛이 획마다 다르다)
            do {
                let ctx2 = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx2.scaleBy(x: scale, y: scale)
                ctx2.setFillColor(NSColor(white: 0.16, alpha: 1).cgColor); ctx2.fill(CGRect(x: 0, y: 0, width: W, height: H))
                var h: CGFloat = 0
                var strokes: [[LaserPt]] = []
                let paths: [[CGPoint]] = [
                    (0..<60).map { CGPoint(x: 40 + CGFloat($0) * 7, y: 150 + sin(CGFloat($0) / 9) * 60) },
                    (0..<60).map { CGPoint(x: 80 + CGFloat($0) * 6, y: 60 + CGFloat($0) * 3.5) },
                    (0..<60).map { CGPoint(x: 460 - CGFloat($0) * 6, y: 70 + CGFloat($0) * 2.8) },
                    (0..<70).map { i in let u = CGFloat(i) / 69 * 2 * .pi; return CGPoint(x: 260 + cos(u) * 70, y: 150 + sin(u) * 70) },
                ]
                for (k, ps) in paths.enumerated() {
                    var st: [LaserPt] = []
                    for (i, p) in ps.enumerated() {
                        if i > 0 { h = (h + hypot(p.x - ps[i - 1].x, p.y - ps[i - 1].y) * 360 / RAINBOW_CYCLE_PX).truncatingRemainder(dividingBy: 360) }
                        st.append(LaserPt(p: p, t: Double(k) * 0.05 + Double(i) * 0.002, hue: h, rgb: nil))
                    }
                    strokes.append(st)
                }
                renderLaser(strokes, baseColor: color(0xFF0000).cgColor, width: big, now: 0.4, in: ctx2)
                if let img = ctx2.makeImage() {
                    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("rainbow-strokes.png"))
                }
            }
            if let img = ctx.makeImage() {
                try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("overlap.png"))
            }
        }
        // 속도: 120점(1초) 획 하나를 그리는 데 걸리는 시간 (움직이는 동안 매 프레임 불린다)
        let ctx2 = CGContext(data: nil, width: 3024, height: 1964, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx2.scaleBy(x: 2, y: 2)
        let long = (0..<120).map { i in LaserPt(p: CGPoint(x: 100 + CGFloat(i) * 9, y: 500 + sin(CGFloat(i) / 12) * 120), t: Double(i) / 120, hue: nil, rgb: nil) }
        var ms: [Double] = []
        for _ in 0..<60 {
            let t = CFAbsoluteTimeGetCurrent()
            ctx2.saveGState()
            ctx2.clip(to: CGRect(x: 100, y: 380, width: 1100, height: 240)) // 실제로는 획의 바깥 상자만 다시 그린다
            ctx2.clear(CGRect(x: 0, y: 0, width: 1512, height: 982))
            renderLaser([long], baseColor: color(0xFF0000).cgColor, width: width, now: 1.0, in: ctx2)
            ctx2.restoreGState()
            ms.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
        }
        ms.sort()
        var ms2: [Double] = []
        var hh: CGFloat = 0
        let longR = long.enumerated().map { i, pt -> LaserPt in
            if i > 0 { hh = (hh + hypot(pt.p.x - long[i - 1].p.x, pt.p.y - long[i - 1].p.y) * 360 / RAINBOW_CYCLE_PX).truncatingRemainder(dividingBy: 360) }
            return LaserPt(p: pt.p, t: pt.t, hue: hh, rgb: nil)
        }
        for _ in 0..<30 {
            let t = CFAbsoluteTimeGetCurrent()
            ctx2.saveGState(); ctx2.clip(to: CGRect(x: 100, y: 380, width: 1100, height: 240))
            renderLaser([longR], baseColor: color(0xFF0000).cgColor, width: width, now: 1.0, in: ctx2)
            ctx2.restoreGState()
            ms2.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
        }
        ms2.sort()
        try? String(format: "renderLaser 120점 획(상자 1100×240pt만): p50=%.2fms p95=%.2fms max=%.2fms / 무지개 p50=%.2fms max=%.2fms\n", ms[30], ms[57], ms[59], ms2[15], ms2[29]).write(to: dir.appendingPathComponent("laser-speed.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
