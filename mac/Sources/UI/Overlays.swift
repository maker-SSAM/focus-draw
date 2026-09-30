import AppKit

// ================= 레이저와 굵기·진하기 숫자 =================
// 둘 다 판 위에 그려지고, 타이머는 그릴 것이 있는 동안에만 돈다 (쉬는 동안 0).

extension DrawController {
    func renderOverlays(in ctx: CGContext) {
        let now = Date.timeIntervalSinceReferenceDate
        var strokes = laser
        if let l = laserLive, !l.isEmpty {
            strokes.append(mode == .free ? l : l.map { LaserPt(p: $0.p, t: now, hue: $0.hue, rgb: $0.rgb) })
        }
        if !strokes.isEmpty {
            renderLaser(strokes, baseColor: color(rgb).cgColor, width: laserWidth, now: now, in: ctx)
        }
        if let b = badge, Date() < b.until {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                                                        .foregroundColor: NSColor(white: 0.1, alpha: 1)]
            let str = NSAttributedString(string: b.text, attributes: attrs)
            let r = badgeRect
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            // macOS 도움말 풍선 모양: 밝은 바탕, 얇은 회색 테, 반경 5, 진한 글자
            let balloon = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            NSColor(white: 0.97, alpha: 1).setFill()
            balloon.fill()
            NSColor(white: 0.6, alpha: 1).setStroke()
            balloon.lineWidth = 1
            balloon.stroke()
            str.draw(at: NSPoint(x: r.midX - str.size().width / 2, y: r.midY - str.size().height / 2))
            NSGraphicsContext.restoreGraphicsState()
        }
        drawBrushCursor(in: ctx)
    }

    // 커서 중심에서 오른쪽 아래 22pt, 화면 가장자리에서는 안쪽으로 뒤집는다. 늘 같은 자리에 잠깐 뜬다 (굵기가 바뀌어도 숫자가 따라 움직이지 않는다)
    func showBadge(_ text: String, seconds: Double = Double(STEP_BADGE_MS) / 1000) {
        surface.invalidate(badgeRect)
        let m = NSEvent.mouseLocation
        let textWidth = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium)]).size().width
        let w = max(STEP_BADGE_W, ceil(textWidth) + 16)
        let screen = NSScreen.screens.first { $0.frame.contains(m) }?.frame ?? NSScreen.screens.first?.frame ?? .zero
        badgeRect = balloonRect(mouse: m, size: CGSize(width: w, height: STEP_BADGE_H), screen: screen)
        let until = Date().addingTimeInterval(seconds)
        badge = (text, until)
        surface.invalidate(badgeRect)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.05) { [weak self] in
            guard let self, let b = self.badge, b.until == until else { return }
            self.badge = nil
            self.surface.invalidate(self.badgeRect)
        }
    }

    func stopLaserTimer() {
        laserTimer?.invalidate()
        laserTimer = nil
    }

    func startLaserTimer() {
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
            self.surface.invalidate(lastBox.union(box))
            lastBox = box
            if self.laser.isEmpty && self.laserLive == nil {
                timer.invalidate()
                self.laserTimer = nil
            }
        }
        RunLoop.main.add(t, forMode: .common)
        laserTimer = t
    }
}

// 굵기 숫자 풍선의 자리: 커서 중심에서 오른쪽 아래(AppKit은 위가 +y라 y를 뺀다) 22pt. 화면 밖으로 나가면 그쪽만 뒤집는다.
func balloonRect(mouse m: CGPoint, size: CGSize, screen: CGRect, offset: CGFloat = 22) -> CGRect {
    var x = m.x + offset, y = m.y - offset - size.height
    if x + size.width > screen.maxX { x = m.x - offset - size.width }
    if y < screen.minY { y = m.y + offset }
    return CGRect(x: x, y: y, width: size.width, height: size.height)
}
