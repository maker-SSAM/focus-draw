import CoreGraphics
import Foundation

// 도형의 점들 (Windows 판과 같은 셈). AppKit 없이 돈다.

enum ShapeMode { case free, rect, ellipse, line, wave, arrow }

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
