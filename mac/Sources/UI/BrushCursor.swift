import AppKit

// ================= 커서: 지금 그어질 선과 똑같은 동그라미 =================
// 붓 동그라미는 NSCursor가 아니라 판에 직접 그린다 — NSCursor는 맥의 "포인터 크기" 설정을 따라 커지기 때문이다(D3).
// 시스템 커서는 드로잉 중에 숨긴다 (UI/SystemCursor.swift).

extension DrawController {
    func updateCursor() {
        let d: CGFloat
        let img: NSImage
        if erasing || rightDown || optionHeld {
            d = eraserPx(eraserStep)
            img = eraserRingImage(diameter: d, ring: currentEraserRing)
        } else if pen == .laser {
            d = max(penPx(penStep), LASER_MIN_WIDTH) * 3
            img = laserCursorImage(side: d, base: color(rgb))
        } else {
            d = penPx(penStep)
            // 붓 동그라미의 진하기 = 색별 진하기 × 전체 진하기: 지금 그으면 나올 선과 같은 모양
            let a = alpha * CGFloat(config.drawOpacity) / 100
            let fill = pen == .rainbow ? NSColor(cgColor: hueColor(rainbowHue))!.withAlphaComponent(a) : color(rgb, a)
            img = brushCursorImage(diameter: d, fill: fill)
        }
        surface.invalidate(cursorRect)
        cursorImage = img
        surface.invalidate(cursorRect)
    }

    // 판에 직접 그릴 때 붓 동그라미가 차지하는 자리
    var cursorRect: CGRect {
        guard let img = cursorImage else { return .null }
        return CGRect(x: mouse.x - img.size.width / 2 - 1, y: mouse.y - img.size.height / 2 - 1,
                      width: img.size.width + 2, height: img.size.height + 2)
    }

    func moveMouse(_ p: CGPoint) {
        guard isOn else { mouse = p; return }
        refreshOption()
        if mouseInside { SystemCursor.reassert() }
        surface.invalidate(cursorRect)
        mouse = p
        surface.invalidate(cursorRect)
    }

    // 붓 동그라미를 판 위에 그린다 (InkView.draw가 renderOverlays 안에서 부른다)
    func drawBrushCursor(in ctx: CGContext) {
        guard isOn, mouseInside, let img = cursorImage else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        img.draw(in: cursorRect.insetBy(dx: 1, dy: 1))
        NSGraphicsContext.restoreGraphicsState()
    }
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
        p.lineWidth = 1 // 1px로 가늘게
        ring.setStroke()
        p.stroke()
        return true
    }
}

func laserCursorImage(side d: CGFloat, base: NSColor) -> NSImage {
    // d = 가장 바깥 번짐의 지름. 그림 크기는 그보다 2pt 크게 잡아야 바깥 원이 사각형으로 잘리지 않는다
    let side = ceil(d) + 2
    return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
        for (mul, a, mix) in LASER_LAYERS {
            let dd = d / 3 * mul
            NSColor(cgColor: tint(base.cgColor, mix))!.withAlphaComponent(a).setFill()
            NSBezierPath(ovalIn: NSRect(x: (side - dd) / 2, y: (side - dd) / 2, width: dd, height: dd)).fill()
        }
        return true
    }
}
