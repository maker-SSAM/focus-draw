import AppKit

// ================= 레이저와 굵기·진하기 숫자 =================
// 둘 다 판 위에 그려지고, 타이머는 그릴 것이 있는 동안에만 돈다 (쉬는 동안 0).

extension DrawController {
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
        drawBrushCursor(in: ctx)
    }

    // 커서 오른쪽 위, 늘 같은 자리에 잠깐 뜬다 (굵기가 바뀌어도 숫자가 따라 움직이지 않는다)
    func showBadge(_ text: String, seconds: Double = Double(STEP_BADGE_MS) / 1000) {
        surface.invalidate(badgeRect)
        let m = NSEvent.mouseLocation
        let textWidth = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold)]).size().width
        let w = max(STEP_BADGE_W, ceil(textWidth) + 20)
        badgeRect = CGRect(x: m.x + 28, y: m.y + 14, width: w, height: STEP_BADGE_H)
        let until = Date().addingTimeInterval(seconds)
        badge = (text, until)
        surface.invalidate(badgeRect)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.05) { [weak self] in
            guard let self, let b = self.badge, b.until == until else { return }
            self.badge = nil
            self.surface.invalidate(self.badgeRect)
        }
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
