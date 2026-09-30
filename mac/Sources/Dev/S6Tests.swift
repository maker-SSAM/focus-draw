import AppKit

// S6의 글 점검: 채운 화살촉·무지개 촉 색·레이저 꼬리 색·굵기 풍선 자리·휠 방향·제자리 클릭·오른쪽 버튼 규칙. 화면 없이 돈다(Golden.run).
@MainActor enum S6Tests {
    static func alpha(_ img: CGImage?, _ x: Int, _ yFromTop: Int) -> (r: Int, g: Int, b: Int, a: Int)? {
        guard let img, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        px.withUnsafeMutableBytes { raw in
            guard let c = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            c.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - yFromTop), width: img.width, height: img.height))
        }
        return (Int(px[0]), Int(px[1]), Int(px[2]), Int(px[3]))
    }

    static func run(_ report: (String, Bool, String) -> Void) {
        func check(_ name: String, _ ok: Bool, _ detail: String = "") { report(name, ok, detail) }

        // ---- 화살촉은 채운 삼각형 ----
        do {
            let s = Golden.Sim(); s.key(Golden.K.n1); s.key(Golden.K.c)
            s.stroke([s.P(60, 200), s.P(300, 200)])
            s.keyUp(Golden.K.c)
            let item = s.d.items.last
            check("화살표: 몸통은 머리 밑변까지, 머리는 세 점", item?.head?.count == 3 && item?.points.count == 2, "점 \(item?.points.count ?? -1) 머리 \(item?.head?.count ?? -1)")
            // 머리 한가운데(꼭짓점에서 머리 길이의 1/3 안쪽)가 칠해져 있어야 한다. 빈 삼각형이면 투명이다.
            let inside = alpha(s.image(), 300 - 8, 200)
            check("화살촉 안쪽이 채워져 있음", (inside?.a ?? 0) > 250 && (inside?.r ?? 0) > 200, "\(String(describing: inside))")
        }
        // ---- 무지개 화살촉은 몸통이 끝난 색 ----
        do {
            let s = Golden.Sim(); s.key(Golden.K.s); s.key(Golden.K.c)
            s.stroke([s.P(60, 200), s.P(400, 200)])
            s.keyUp(Golden.K.c)
            let item = s.d.items.last
            let endHue = item?.hues?.last ?? -1
            let want = NSColor(cgColor: hueColor(endHue))?.usingColorSpace(.sRGB)
            let got = alpha(s.image(), 400 - 8, 200)
            let ok = want != nil && got != nil && abs(Int(want!.redComponent * 255) - got!.r) <= 4 && abs(Int(want!.greenComponent * 255) - got!.g) <= 4
                && abs(Int(want!.blueComponent * 255) - got!.b) <= 4
            check("무지개 화살촉: 몸통이 끝난 색으로 채움", ok, "끝 색상 \(Int(endHue)) 칠한 색 \(String(describing: got))")
        }
        // ---- 레이저: 꼬리는 그은 때의 색 ----
        do {
            let s = Golden.Sim(); s.key(Golden.K.n1); s.key(Golden.K.a)
            s.stroke([s.P(60, 100), s.P(200, 100)])
            s.key(Golden.K.n5) // 파랑으로 바꿔도 앞 획은 빨강 그대로
            let first = s.d.laser.first?.first
            check("레이저 획은 그을 때의 색을 가짐", first?.rgb == DRAW_COLORS[0], "\(String(describing: first?.rgb))")
            let tailRed = firstTailIsRed(s)
            check("펜 색을 바꿔도 사라지는 꼬리는 자기 색(빨강)", tailRed)
        }
        // ---- 굵기 풍선의 자리 ----
        do {
            let screen = CGRect(x: 0, y: 0, width: 1000, height: 800), sz = CGSize(width: 40, height: 22)
            let a = balloonRect(mouse: CGPoint(x: 500, y: 400), size: sz, screen: screen)
            check("풍선: 커서 중심에서 오른쪽 아래 22pt", a.minX == 522 && a.maxY == 378, "\(a)")
            let b = balloonRect(mouse: CGPoint(x: 990, y: 400), size: sz, screen: screen)
            check("풍선: 오른쪽 가장자리에서 왼쪽으로 뒤집힘", b.maxX <= 990 - 22 + 0.1 && b.maxY == 378, "\(b)")
            let c = balloonRect(mouse: CGPoint(x: 500, y: 10), size: sz, screen: screen)
            check("풍선: 아래 가장자리에서 위로 뒤집힘", c.minY == 32 && c.minX == 522, "\(c)")
            check("풍선: 0.5초", STEP_BADGE_MS == 500)
        }
        // ---- 휠 방향 ----
        check("휠: 자연스러운 스크롤이 켜져 있어도 위로 굴리면 같은 방향", physicalScrollUp(3, inverted: false) == 3 && physicalScrollUp(-3, inverted: true) == 3
              && physicalScrollUp(3, inverted: true) == -3)
        // ---- 제자리 클릭은 점을 남기지 않는다 (결정 6) ----
        do {
            let s = Golden.Sim()
            s.stroke([s.P(100, 100)])
            check("움직이지 않은 한 번 클릭은 점을 남기지 않음", s.d.items.isEmpty && s.d.live == nil, "획 \(s.d.items.count)")
            s.key(Golden.K.c); s.stroke([s.P(100, 100)]); s.keyUp(Golden.K.c)
            check("화살표도 제자리 클릭은 남기지 않음", s.d.items.isEmpty)
        }
        // ---- 손을 뗀 점까지 획에 넣는다 ----
        do {
            let s = Golden.Sim()
            s.d.down(s.P(100, 100), s.ev(.leftMouseDown, s.P(100, 100)), right: false)
            s.d.drag(s.P(150, 100), s.ev(.leftMouseDragged, s.P(150, 100)))
            s.d.up(s.P(180, 100))
            check("뗀 점까지 획에 들어감", s.d.items.last?.points.last == s.P(180, 100), "\(String(describing: s.d.items.last?.points.last))")
        }
        // ---- 오른쪽 버튼 ----
        do {
            let s = Golden.Sim()
            s.d.down(s.P(100, 100), s.ev(.leftMouseDown, s.P(100, 100)), right: false)
            s.d.drag(s.P(150, 100), s.ev(.leftMouseDragged, s.P(150, 100)))
            s.d.down(s.P(150, 100), s.ev(.rightMouseDown, s.P(150, 100)), right: true) // 왼쪽 획 도중 오른쪽 버튼
            check("왼쪽 획 도중 오른쪽 버튼: 지우개가 시작되지 않고 획이 그대로", !s.d.erasing && !s.d.rightDown && s.d.live?.kind == .stroke)
            s.d.drag(s.P(160, 130), s.ev(.rightMouseDragged, s.P(160, 130)))
            s.d.up(s.P(160, 130), right: true)
            check("오른쪽 버튼을 떼도 왼쪽 획이 끝나지 않고 흔적도 없음", s.d.live != nil && s.d.items.isEmpty && s.d.live?.points.count == 2)
            s.d.drag(s.P(200, 100), s.ev(.leftMouseDragged, s.P(200, 100)))
            s.d.up(s.P(200, 100))
            check("왼쪽 획은 끝까지 이어져 하나로 남음", s.d.items.count == 1 && s.d.items[0].points.count == 3, "점 \(s.d.items.first?.points.count ?? -1)")
            // 반대: 오른쪽 지우개 도중 왼쪽 버튼
            s.d.down(s.P(100, 200), s.ev(.rightMouseDown, s.P(100, 200)), right: true)
            s.d.drag(s.P(140, 200), s.ev(.rightMouseDragged, s.P(140, 200)))
            s.d.down(s.P(140, 200), s.ev(.leftMouseDown, s.P(140, 200)), right: false)
            check("오른쪽 지우개 도중 왼쪽 버튼은 무시", s.d.erasing && s.d.live?.kind == .erase)
            s.d.up(s.P(140, 200), right: false)
            s.d.drag(s.P(180, 200), s.ev(.rightMouseDragged, s.P(180, 200)))
            s.d.up(s.P(180, 200), right: true)
            check("지우개는 오른쪽 버튼을 뗄 때 끝남", !s.d.erasing && s.d.items.last?.kind == .erase && s.d.items.last?.points.count == 3)
        }
    }

    // 레이저 꼬리의 그림을 직접 그려 본다: 그은 자리의 색이 빨강 계열이어야 한다
    static func firstTailIsRed(_ s: Golden.Sim) -> Bool {
        guard let first = s.d.laser.first else { return false }
        let img = renderScene(items: [], size: s.size, scale: 1, laser: LaserScene(strokes: [first], color: color(DRAW_COLORS[4]).cgColor, width: 8), now: first.first!.t)
        guard let px = alpha(img, 130, Int(s.size.height - first[0].p.y)) else { return false }
        return px.a > 0 && px.r > px.b
    }
}
