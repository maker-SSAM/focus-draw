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
        try? String(format: "renderLaser 120점 획(상자 1100×240pt만): p50=%.2fms p95=%.2fms max=%.2fms\n", ms[30], ms[57], ms[59]).write(to: dir.appendingPathComponent("laser-speed.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
