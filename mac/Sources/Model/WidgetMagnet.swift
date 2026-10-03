import CoreGraphics

// 위젯을 끌 때의 자리 계산 (화면 없이 돈다).
// 자리 = 커서 − 잡은 거리. 벽에서는 잡은 거리를 다시 잡아 누적이 없게 한다.
// Dock 쪽 가장자리(visibleFrame이 frame보다 줄어든 쪽)에서만 15pt 안이면 붙고, 더 끌면 지나간다.
// 메뉴 막대·노치 아래로는 못 가지만(visibleFrame 위쪽) Dock 위에는 둘 수 있다(frame 아래쪽).
let WIDGET_MAGNET: CGFloat = 15

func widgetDragPlace(cursor: CGPoint, grab: CGVector, size: CGSize, frame: CGRect, visible: CGRect,
                     magnet: CGFloat = WIDGET_MAGNET) -> (origin: CGPoint, grab: CGVector) {
    var o = CGPoint(x: cursor.x - grab.dx, y: cursor.y - grab.dy)
    o.x = min(max(o.x, frame.minX), frame.maxX - size.width)
    o.y = min(max(o.y, frame.minY), visible.maxY - size.height)
    let newGrab = CGVector(dx: cursor.x - o.x, dy: cursor.y - o.y)

    // Dock이 자동 숨김이면 frame과 visibleFrame이 같아서 자석이 없다
    let eps: CGFloat = 1
    if visible.minY - frame.minY > eps, abs(o.y - visible.minY) <= magnet { o.y = visible.minY }
    if visible.minX - frame.minX > eps, abs(o.x - visible.minX) <= magnet { o.x = visible.minX }
    if frame.maxX - visible.maxX > eps, abs(o.x + size.width - visible.maxX) <= magnet { o.x = visible.maxX - size.width }
    return (o, newGrab)
}
