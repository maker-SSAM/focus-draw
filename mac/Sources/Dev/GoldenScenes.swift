import AppKit

// 그림 기준 점검의 장면 목록 (Golden.swift의 일부)
extension Golden {
    // ---------- 장면 ----------
    static func scenes() -> [Scene] {
        var list: [Scene] = []
        let small = CGSize(width: 320, height: 200) // 색이 부드러운 장면은 작게 (기준 그림 40KB 이하)
        func add(_ name: String, size: CGSize = CGSize(width: W, height: H), scale: CGFloat = 1, note: String = "",
                 _ body: @escaping (Sim) -> Void) {
            list.append(Scene(name: name, scale: scale, note: note) {
                resetSettings()
                let sim = Sim(size: size)
                body(sim)
                return sim.image(scale: scale)
            })
        }
        func addImage(_ name: String, scale: CGFloat = 1, note: String = "", _ make: @escaping () -> CGImage?) {
            list.append(Scene(name: name, scale: scale, note: note) { resetSettings(); return make() })
        }

        // 펜과 도형
        func penFree(_ s: Sim) {
            s.stroke(s.wiggle(40, 45, 240, amp: 18))                         // 빨강
            s.key(K.n4); s.stroke(s.wiggle(40, 100, 240, amp: 18))          // 초록
            s.key(K.n5); for _ in 0..<3 { s.key(K.plus) }; s.stroke(s.wiggle(40, 160, 240, amp: 18)) // 굵은 파랑
            s.key(K.n1); s.key(K.minus)                                      // 숫자키가 굵기를 5로 돌리므로 한 번만 → 4
            s.stroke([s.P(300, 40), s.P(300, 160), s.P(270, 40)])            // 가는 빨강
        }
        add("pen-free", size: small, penFree)
        add("pen-free-2x", size: CGSize(width: 160, height: 125), scale: 2) { s in
            s.stroke(s.wiggle(15, 45, 120, amp: 14)); s.key(K.n5); s.stroke(s.wiggle(15, 95, 120, amp: 14))
        }

        func shapes(_ s: Sim) {
            s.key(K.n1)
            s.stroke([s.P(50, 40), s.P(220, 150)], .shift)                                   // 사각형
            s.key(K.n5); s.stroke([s.P(260, 40), s.P(430, 150)], .control)                  // 원
            s.key(K.n4); s.hold(K.z) { s.stroke([s.P(50, 210), s.P(240, 260)]) }            // 직선
            s.key(K.n3); s.hold(K.x) { s.stroke([s.P(270, 210), s.P(480, 270)]) }           // 물결
            s.key(K.n2); s.hold(K.c) { s.stroke([s.P(460, 60), s.P(600, 190)]) }            // 화살표
            s.key(K.n1); s.hold(K.c) { s.stroke([s.P(60, 330), s.P(300, 370)]) }
        }
        add("shapes", note: "S6: 속 빈 화살촉", shapes)
        add("shapes-2x", size: CGSize(width: 160, height: 100), scale: 2, note: "S6: 속 빈 화살촉") { s in
            s.key(K.n1); s.stroke([s.P(15, 15), s.P(70, 50)], .shift)
            s.key(K.n5); s.hold(K.c) { s.stroke([s.P(85, 20), s.P(145, 80)]) }
        }

        add("shapes-shift", note: "S6: 속 빈 화살촉") { s in     // Shift로 0°·45°·90°에 맞춘 직선·물결·화살표
            s.key(K.n1)
            s.hold(K.z) { s.stroke([s.P(50, 80), s.P(280, 110)], .shift) }
            s.hold(K.z) { s.stroke([s.P(340, 60), s.P(480, 200)], .shift) }
            s.key(K.n5); s.hold(K.x) { s.stroke([s.P(50, 170), s.P(280, 200)], .shift) }
            s.key(K.n4); s.hold(K.c) { s.stroke([s.P(340, 280), s.P(560, 300)], .shift) }
            s.hold(K.c) { s.stroke([s.P(80, 240), s.P(120, 380)], .shift) }
        }

        // 무지개
        add("rainbow-free", size: small) { s in
            s.key(K.s)
            s.stroke(s.wiggle(20, 60, 280, amp: 25))
            s.key(K.plus); s.key(K.plus)
            s.stroke(s.wiggle(20, 140, 280, amp: 25))
        }
        add("rainbow-shapes", note: "S6: 무지개 화살촉은 Windows와 다름") { s in
            s.key(K.s)
            s.stroke([s.P(50, 40), s.P(230, 160)], .shift)
            s.stroke([s.P(270, 40), s.P(450, 160)], .control)
            s.hold(K.c) { s.stroke([s.P(60, 230), s.P(300, 300)]) }
            s.hold(K.z) { s.stroke([s.P(340, 230), s.P(560, 300)]) }
            s.hold(K.x) { s.stroke([s.P(60, 340), s.P(400, 370)]) }
        }

        // 겹침
        add("overlap-self") { s in     // 반투명 한 획이 자기 자리를 지나가도 이음매가 진해지지 않아야 한다
            Settings.shared.drawKeyAlphas[2] = 50
            s.key(K.n3); s.key(K.plus); s.key(K.plus); s.key(K.plus); s.key(K.plus)
            s.stroke([s.P(80, 100), s.P(500, 100), s.P(500, 220), s.P(120, 220), s.P(120, 60), s.P(300, 60), s.P(300, 300)])
        }
        add("overlap-red-blue") { s in
            Settings.shared.drawKeyAlphas[4] = 50
            s.key(K.n1); s.key(K.plus); s.key(K.plus); s.key(K.plus)
            s.stroke([s.P(80, 120), s.P(560, 120)])
            s.key(K.n5); s.key(K.plus); s.key(K.plus); s.key(K.plus)        // 숫자키가 굵기를 5로 돌리므로 다시 8로
            s.stroke([s.P(280, 40), s.P(280, 340)])
            s.stroke([s.P(360, 50), s.P(440, 330)])
        }

        // 지우개와 칠판
        for (name, key) in [("q", K.q), ("w", K.w), ("e", K.e), ("r", K.r)] {
            add("erase-board-\(name)") { s in
                s.key(key)
                s.stroke(s.wiggle(60, 100, 460)); s.key(K.n4)
                s.stroke([s.P(80, 200), s.P(420, 300)], .shift)
                s.key(K.n5); s.stroke(s.wiggle(60, 340, 460, amp: 20))
                s.stroke([s.P(240, 40), s.P(300, 380)], right: true)           // 지우개
                s.key(K.plus); s.key(K.plus)
                s.d.down(s.P(420, 60), s.ev(.rightMouseDown, s.P(420, 60)), right: true)  // 굵은 지우개
                for y in stride(from: 60, through: 360, by: 20) { s.d.drag(s.P(420, CGFloat(y)), s.ev(.rightMouseDragged, s.P(420, CGFloat(y)))) }
                s.d.up(s.P(420, 360))
            }
        }
        for (name, key, idx) in [("w", K.w, 0), ("e", K.e, 1), ("r", K.r, 2)] {
            add("board-alpha50-\(name)") { s in
                Settings.shared.boardAlphas[idx] = 50
                s.key(key); s.stroke(s.wiggle(60, 200, 480, amp: 60))
            }
        }
        add("opacity-multiply") { s in // 드로잉 진하기 50%: 1번 50%, 3번(50%) 25% — 겹친 곳은 진해짐, 휠로 100%까지 올린 선은 불투명
            Settings.shared.drawOpacity = 50
            Settings.shared.drawKeyAlphas[2] = 50
            s.key(K.n1); s.stroke([s.P(60, 120), s.P(560, 120)])
            s.key(K.n3); for _ in 0..<4 { s.key(K.plus) }; s.stroke([s.P(300, 40), s.P(300, 360)])
            s.key(K.n1); s.wheel(10); s.stroke([s.P(60, 280), s.P(560, 280)])
        }

        // 실행 취소
        add("undo-one") { s in
            s.stroke(s.wiggle(60, 100, 460)); s.key(K.n4)
            s.stroke(s.wiggle(60, 200, 460)); s.key(K.n5)
            s.stroke(s.wiggle(60, 300, 460))
            s.key(K.z, .command)                                              // 마지막 파랑이 사라진다
        }
        add("clear-undo") { s in
            s.stroke(s.wiggle(60, 100, 460)); s.key(K.n5)
            s.stroke(s.wiggle(60, 250, 460))
            s.key(K.delete)                                                   // 전부 지우기
            s.key(K.z, .command)                                              // 다시 돌아온다
        }

        // 레이저
        // 도형은 모든 점이 같은 시각, 자유선은 점마다 조금씩 늦은 시각 (실제 그을 때와 같다 — 레이저 곡선 보간은 둘을 이 차이로 구별한다)
        func laserPoints(_ pts: [CGPoint], t: TimeInterval = 0, freehand: Bool = false) -> [LaserPt] {
            pts.enumerated().map { LaserPt(p: $0.element, t: t + (freehand ? Double($0.offset) * 0.003 : 0), hue: nil) }
        }
        func laserImage(now: TimeInterval, shapes: Bool = false) -> CGImage? {
            let s = Sim(size: small)
            var strokes = [laserPoints(s.wiggle(30, 60, 260, amp: 25), freehand: true), laserPoints(s.wiggle(30, 140, 260, amp: 12), freehand: true)]
            if shapes {
                strokes = [laserShape(.rect, s.P(30, 30), s.P(130, 90), width: 8, t: 0, rgb: nil),
                           laserShape(.ellipse, s.P(160, 30), s.P(290, 90), width: 8, t: 0, rgb: nil),
                           laserShape(.arrow, s.P(30, 130), s.P(150, 175), width: 8, t: 0, rgb: nil),
                           laserShape(.wave, s.P(170, 130), s.P(290, 175), width: 8, t: 0, rgb: nil)]
            }
            let laser = LaserScene(strokes: strokes, color: color(0xFF0000).cgColor, width: max(penPx(5), LASER_MIN_WIDTH))
            return renderScene(items: [], board: nil, size: small, scale: 1, laser: laser, now: now)
        }
        addImage("laser-t0.2", note: "S6: 레이저 꼬리 색") { laserImage(now: 0.2) }
        addImage("laser-t0.7", note: "S6: 레이저 꼬리 색") { laserImage(now: 0.7) }
        addImage("laser-t0.95", note: "S6: 레이저 꼬리 색") { laserImage(now: 0.95) }
        addImage("laser-shapes-t0.6") { laserImage(now: 0.6, shapes: true) }

        // 커서와 링
        addImage("cursor-brush") {
            bitmap(CGSize(width: 320, height: 120)) { ctx in
                withNS(ctx) {
                    for (i, step) in [1, 5, 10].enumerated() {
                        let img = brushCursorImage(diameter: penPx(step), fill: color(0xFF0000))
                        let cx = 60 + CGFloat(i) * 100
                        img.draw(in: NSRect(x: cx - img.size.width / 2, y: 60 - img.size.height / 2, width: img.size.width, height: img.size.height))
                    }
                }
            }
        }
        addImage("cursor-eraser-boards") {
            let f = Settings()
            let boards: [UInt32?] = [nil, f.boardColors[0], f.boardColors[1], f.boardColors[2]]
            return bitmap(CGSize(width: 4 * 150, height: 150)) { ctx in
                for (i, b) in boards.enumerated() {
                    let tile = CGRect(x: CGFloat(i) * 150, y: 0, width: 150, height: 150)
                    ctx.setFillColor(b.map { color($0).cgColor } ?? CGColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1))
                    ctx.fill(tile)
                    let img = eraserRingImage(diameter: eraserPx(5), ring: eraserRingColor(boardRGB: b))
                    withNS(ctx) { img.draw(in: NSRect(x: tile.midX - img.size.width / 2, y: 75 - img.size.height / 2, width: img.size.width, height: img.size.height)) }
                }
            }
        }
        addImage("cursor-laser") {
            bitmap(CGSize(width: 360, height: 130)) { ctx in
                withNS(ctx) {
                    for (i, step) in [1, 5, 10].enumerated() {
                        let img = laserCursorImage(side: max(penPx(step), LASER_MIN_WIDTH) * 3, base: color(0xFF0000))
                        let cx = 65 + CGFloat(i) * 115
                        img.draw(in: NSRect(x: cx - img.size.width / 2, y: 65 - img.size.height / 2, width: img.size.width, height: img.size.height))
                    }
                }
            }
        }
        // 무지개: S 다음 A로 긋는 무지개 레이저(자유선·사각형·원), 무지개 펜 점과 무지개 레이저 커서
        addImage("laser-rainbow", note: "무지개 레이저") {
            let s = Sim(size: small)
            let w = max(penPx(5), LASER_MIN_WIDTH)
            let free = rainbowize(laserPoints(s.wiggle(30, 60, 260, amp: 20), freehand: true), from: 0)
            let shapes = [rainbowize(laserShape(.rect, s.P(30, 110), s.P(140, 175), width: w, t: 0, rgb: nil), from: 60),
                          rainbowize(laserShape(.ellipse, s.P(170, 110), s.P(290, 175), width: w, t: 0, rgb: nil), from: 200)]
            return renderScene(items: [], board: nil, size: small, scale: 1,
                               laser: LaserScene(strokes: [free] + shapes, color: color(0xFF0000).cgColor, width: w), now: 0.3)
        }
        addImage("cursor-rainbow") {
            bitmap(CGSize(width: 360, height: 130)) { ctx in
                withNS(ctx) {
                    let imgs = [rainbowDotImage(diameter: penPx(5), alpha: 1), rainbowDotImage(diameter: penPx(10), alpha: 1),
                                laserCursorImage(side: max(penPx(10), LASER_MIN_WIDTH) * 3, base: color(0xFF0000), rainbowGlowHue: 200)]
                    for (i, img) in imgs.enumerated() {
                        let cx = 65 + CGFloat(i) * 115
                        img.draw(in: NSRect(x: cx - img.size.width / 2, y: 65 - img.size.height / 2, width: img.size.width, height: img.size.height))
                    }
                }
            }
        }
        addImage("click-rings-f0-10-20") { // 클릭 링 0·10·20프레임 (강조 원 크기 130, 두께 7, 진하기 50%)
            bitmap(CGSize(width: 3 * 160, height: 160)) { ctx in
                for (i, frame) in [0, 10, 20].enumerated() {
                    guard let ring = clickRingFrame(frame, size: 130, thickness: 7) else { continue }
                    let v = RingView(frame: NSRect(x: 0, y: 0, width: 130, height: 130))
                    v.radius = ring.radius; v.width = ring.width; v.ringColor = color(0xFF0000)
                    guard let img = snapshot(v) else { continue }
                    ctx.saveGState()
                    ctx.setAlpha(ring.alpha * 0.5)
                    ctx.draw(img, in: CGRect(x: CGFloat(i) * 160 + 15, y: 15, width: 130, height: 130))
                    ctx.restoreGState()
                }
            }
        }

        // 위젯 (켬·끔, 크기, 어두운 배경)
        func widget(_ name: String, scale: CGFloat = 1, spot: Bool, draw: Bool, size: Double, bg: UInt32? = nil) {
            addImage(name, scale: scale) {
                Settings.shared.widgetScale = size
                if let bg { Settings.shared.widgetColor = bg }
                let st = AppState()
                st.spotOn = spot; st.drawOn = draw
                let v = WidgetView(state: st)
                v.frame = NSRect(origin: .zero, size: WidgetView.size)
                v.reloadIcons()
                return snapshot(v, scale: scale)
            }
        }
        widget("widget-off-100", spot: false, draw: false, size: 100)
        widget("widget-on-100", spot: true, draw: true, size: 100)
        widget("widget-on-60", spot: true, draw: true, size: 60)
        widget("widget-on-250", spot: true, draw: true, size: 250)
        widget("widget-dark-100", spot: true, draw: false, size: 100, bg: 0x202020)
        widget("widget-on-100-2x", scale: 2, spot: true, draw: true, size: 100)
        // 진하기 20%: 진하기는 위젯 창의 투명도라서, 체크무늬 바탕 위에 20%로 얹어 그린다
        addImage("widget-opacity-20") {
            let st = AppState()
            st.spotOn = true; st.drawOn = false
            let v = WidgetView(state: st)
            v.frame = NSRect(origin: .zero, size: WidgetView.size)
            v.reloadIcons()
            guard let img = snapshot(v, scale: 1) else { return nil }
            let w = img.width, h = img.height
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            for y in stride(from: 0, to: h, by: 8) {
                for x in stride(from: 0, to: w, by: 8) {
                    ctx.setFillColor(((x / 8 + y / 8) % 2 == 0 ? CGColor(gray: 0.85, alpha: 1) : CGColor(gray: 0.55, alpha: 1)))
                    ctx.fill(CGRect(x: x, y: y, width: 8, height: 8))
                }
            }
            ctx.setAlpha(0.2)
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return ctx.makeImage()
        }
        return list
    }
}
