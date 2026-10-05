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
        func curve(_ t0: TimeInterval) -> [LaserPt] {
            (0..<60).map { i in
                let u = CGFloat(i) / 59
                return LaserPt(p: CGPoint(x: 30 + u * 460, y: 75 + sin(u * 6.28) * 38), t: t0 + Double(i) / 60, hue: nil, rgb: nil)
            }
        }
        func panel(_ title: String, rgb: UInt32, bg: NSColor, now: (TimeInterval) -> TimeInterval) -> CGImage? {
            let s = curve(0)
            let laser = LaserScene(strokes: [s], color: color(rgb).cgColor, width: width)
            guard let img = renderScene(items: [], size: size, scale: scale, laser: laser, now: now(s.last!.t)) else { return nil }
            guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.setFillColor(bg.cgColor); ctx.fill(CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
            ctx.draw(img, in: CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
            return ctx.makeImage()
        }
        // 위에서부터: 긋는 중(끝점 now) 빨강·어두운 바탕, 긋고 0.25초 뒤, 노랑·흰 바탕
        let panels: [CGImage?] = [
            panel("drawing", rgb: 0xFF0000, bg: NSColor(white: 0.16, alpha: 1), now: { $0 }),
            panel("after0.25", rgb: 0xFF0000, bg: NSColor(white: 0.16, alpha: 1), now: { $0 + 0.25 }),
            panel("yellow-white", rgb: 0xFFFF00, bg: .white, now: { $0 }),
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
        NSApp.terminate(nil)
    }
}
