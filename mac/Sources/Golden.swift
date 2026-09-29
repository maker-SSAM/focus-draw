import AppKit

// 그림 기준 점검(골든): FocusDraw --golden <결과 폴더> [--goldens <기준 폴더>] [--ahk <focus-draw.ahk>] [--update-goldens]
// 창·화면·사용자 설정 없이 고정 크기(640×400, 일부 @2x)로 장면을 그려 기준 그림과 견준다.
// 글 점검(단언)도 여기서 같이 돈다. 끝나면 결과 폴더에 log.txt · 축소 모음(contact-sheet.png) · 실패한 장면의 차이 그림을 남긴다.
// 마우스·키는 DrawController에 직접 넣는다 (창을 통한 경로는 --selftest가 본다).
enum Golden {
    static let W: CGFloat = 640, H: CGFloat = 400
    static let channelTolerance = 2        // 채널당 ±2까지는 같은 것으로 본다
    static let pixelTolerance = 0.001      // 다른 픽셀이 0.1% 넘으면 실패
    static let maxGoldenCount = 40, maxGoldenBytes = 30 * 1024

    struct Scene {
        let name: String
        let scale: CGFloat
        var note = ""                      // 지금 알려진 차이 등 ("S6" 표시)
        let make: () -> CGImage?
    }

    // ---------- 키와 마우스를 흉내 내는 도우미 ----------
    final class Sim {
        let d = DrawController()
        let size: CGSize
        init(size: CGSize = CGSize(width: W, height: H)) { self.size = size }
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: size.height - y) } // 위에서부터 y
        func ev(_ t: NSEvent.EventType, _ p: CGPoint, _ f: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: t, location: p, modifierFlags: f, timestamp: 0, windowNumber: 0,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func key(_ c: UInt16, _ f: NSEvent.ModifierFlags = []) { d.handleKey(c, f, isRepeat: false, source: "golden") }
        func keyUp(_ c: UInt16) { d.handleKeyUp(c, source: "golden") }
        func hold(_ c: UInt16, _ body: () -> Void) { key(c); body(); keyUp(c) }
        func stroke(_ pts: [CGPoint], _ f: NSEvent.ModifierFlags = [], right: Bool = false) {
            d.down(pts[0], ev(right ? .rightMouseDown : .leftMouseDown, pts[0], f), right: right)
            for p in pts.dropFirst() { d.drag(p, ev(right ? .rightMouseDragged : .leftMouseDragged, p, f)) }
            d.up(pts.last!)
        }
        func wiggle(_ x0: CGFloat, _ y: CGFloat, _ w: CGFloat, amp: CGFloat = 30) -> [CGPoint] {
            stride(from: 0, through: w, by: 6).map { P(x0 + $0, y + sin($0 / 25) * amp) }
        }
        func image(scale: CGFloat = 1) -> CGImage? {
            renderScene(items: d.items, live: d.live, board: d.boardColor, opacity: Settings.shared.drawOpacity,
                        size: size, scale: scale)
        }
    }

    // 키 자리 번호 (글자가 아니라 자리로 본다)
    enum K {
        static let n1: UInt16 = 18, n2: UInt16 = 19, n3: UInt16 = 20, n4: UInt16 = 21, n5: UInt16 = 23, n0: UInt16 = 29
        static let q: UInt16 = 12, w: UInt16 = 13, e: UInt16 = 14, r: UInt16 = 15, a: UInt16 = 0, s: UInt16 = 1
        static let z: UInt16 = 6, x: UInt16 = 7, c: UInt16 = 8, plus: UInt16 = 24, minus: UInt16 = 27
        static let delete: UInt16 = 51, esc: UInt16 = 53
    }

    static func resetSettings() {
        let s = Settings.shared, f = Settings()
        s.drawOpacity = f.drawOpacity; s.drawColor = f.drawColor; s.drawStep = f.drawStep; s.eraserStep = f.eraserStep
        s.drawKeyColors = f.drawKeyColors; s.drawKeyAlphas = f.drawKeyAlphas
        s.boardColors = f.boardColors; s.boardAlphas = f.boardAlphas
        s.widgetScale = f.widgetScale; s.widgetColor = f.widgetColor; s.widgetOpacity = f.widgetOpacity
    }

    // ---------- 그림 도우미 ----------
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    static func bitmap(_ size: CGSize, scale: CGFloat = 1, _ body: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        body(ctx)
        return ctx.makeImage()
    }

    static func withNS(_ ctx: CGContext, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    static func snapshot(_ v: NSView, scale: CGFloat = 1) -> CGImage? {
        let size = v.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep.cgImage
    }

    // 투명한 곳이 보이도록 고정 회색 위에 얹어 저장·비교한다
    static func flatten(_ img: CGImage) -> CGImage? {
        // 알파 없는 RGB로 저장해야 PNG가 작다 (기준 그림 각 30KB 이하)
        guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let r = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        ctx.setFillColor(CGColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1))
        ctx.fill(r)
        ctx.draw(img, in: r)
        return ctx.makeImage()
    }

    static func png(_ img: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    static func rgba(_ img: CGImage) -> [UInt8]? {
        var buf = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let ok = buf.withUnsafeMutableBytes { p -> Bool in
            guard let ctx = CGContext(data: p.baseAddress, width: img.width, height: img.height, bitsPerComponent: 8,
                                      bytesPerRow: img.width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            return true
        }
        return ok ? buf : nil
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    // ---------- 장면 ----------
    static func scenes() -> [Scene] {
        var list: [Scene] = []
        let small = CGSize(width: 320, height: 200) // 색이 부드러운 장면은 작게 (기준 그림 30KB 이하)
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
            s.key(K.n1); for _ in 0..<4 { s.key(K.minus) }
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
            s.key(K.n5)
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
        add("opacity-multiply") { s in // 전체 50% × 이 색 50% = 25%
            Settings.shared.drawOpacity = 50
            Settings.shared.drawKeyAlphas[2] = 50
            s.key(K.n1); s.stroke([s.P(60, 120), s.P(560, 120)])
            s.key(K.n3); for _ in 0..<4 { s.key(K.plus) }; s.stroke([s.P(300, 40), s.P(300, 360)])
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
        func laserPoints(_ pts: [CGPoint], t: TimeInterval = 0) -> [LaserPt] { pts.map { LaserPt(p: $0, t: t, hue: nil) } }
        func laserImage(now: TimeInterval, shapes: Bool = false) -> CGImage? {
            let s = Sim(size: small)
            var strokes = [laserPoints(s.wiggle(30, 60, 260, amp: 25)), laserPoints(s.wiggle(30, 140, 260, amp: 12))]
            if shapes {
                strokes = [laserPoints(shapePoints(.rect, s.P(30, 30), s.P(130, 90), width: 8)),
                           laserPoints(shapePoints(.ellipse, s.P(160, 30), s.P(290, 90), width: 8)),
                           laserPoints(shapePoints(.arrow, s.P(30, 130), s.P(150, 175), width: 8)),
                           laserPoints(shapePoints(.wave, s.P(170, 130), s.P(290, 175), width: 8))]
            }
            let laser = LaserScene(strokes: strokes, color: color(0xFF0000).cgColor, width: max(penPx(5), LASER_MIN_WIDTH))
            return renderScene(items: [], board: nil, opacity: 100, size: small, scale: 1, laser: laser, now: now)
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
                let v = WidgetView(frame: NSRect(origin: .zero, size: WidgetView.size))
                v.reloadIcons()
                v.spotOn = spot; v.drawOn = draw
                return snapshot(v, scale: scale)
            }
        }
        widget("widget-off-100", spot: false, draw: false, size: 100)
        widget("widget-on-100", spot: true, draw: true, size: 100)
        widget("widget-on-60", spot: true, draw: true, size: 60)
        widget("widget-on-250", spot: true, draw: true, size: 250)
        widget("widget-dark-100", spot: true, draw: false, size: 100, bg: 0x202020)
        widget("widget-on-100-2x", scale: 2, spot: true, draw: true, size: 100)
        return list
    }

    // ---------- 글 점검 ----------
    static func assertions(_ report: (String, Bool, String) -> Void, ahk: String?) {
        func check(_ name: String, _ ok: Bool, _ detail: String = "") { report(name, ok, detail) }
        resetSettings()
        func strokes(_ s: Sim, _ n: Int) {
            for i in 0..<n { s.stroke([s.P(20 + CGFloat(i) * 5, 40), s.P(60 + CGFloat(i) * 5, 80)]) }
        }

        // 실행 취소
        do {
            let s = Sim(); strokes(s, 31)
            for _ in 0..<40 { s.key(K.z, .command) }
            check("실행 취소: 31획 중 30개만 취소됨", s.d.items.count == 1, "남은 획 \(s.d.items.count)")
        }
        do {
            let s = Sim(); var now = Date(timeIntervalSince1970: 1_000_000)
            s.d.clock = { now }
            strokes(s, 3)
            s.d.finishSession(clear: false)
            now.addTimeInterval(UNDO_KEEP_S - 1); s.d.expireUndoIfNeeded()
            s.key(K.z, .command)
            check("끈 뒤 \(Int(UNDO_KEEP_S) - 1)초: 아직 되돌릴 수 있음", s.d.items.count == 2, "획 \(s.d.items.count)")

            let t = Sim(); var now2 = Date(timeIntervalSince1970: 1_000_000)
            t.d.clock = { now2 }
            strokes(t, 3)
            t.d.finishSession(clear: false)
            now2.addTimeInterval(UNDO_KEEP_S + 1); t.d.expireUndoIfNeeded()
            t.key(K.z, .command)
            check("끈 뒤 \(Int(UNDO_KEEP_S) + 1)초: 되돌리기 기록이 비워짐", t.d.items.count == 3, "획 \(t.d.items.count)")
        }
        do {
            let s = Sim(); strokes(s, 3)
            s.key(K.delete)
            let cleared = s.d.items.last?.kind == .clear
            s.key(K.z, .command)
            check("전부 지우기도 한 단계로 되돌림", cleared && s.d.items.count == 3 && s.d.items.last?.kind == .stroke,
                  "획 \(s.d.items.count)")
        }
        do {
            let s = Sim(); strokes(s, 2)
            s.d.down(s.P(300, 300), s.ev(.rightMouseDown, s.P(300, 300)), right: true); s.d.up(s.P(300, 300))
            check("제자리 오른쪽 클릭은 아무것도 남기지 않음", s.d.items.count == 2)
            s.key(K.z, [.command, .shift])
            check("⌘⇧Z는 실행 취소가 아님", s.d.items.count == 2)
        }

        // 켜고 끄기
        do {
            let s = Sim()
            s.key(K.n3); s.key(K.plus); s.key(K.plus); s.key(K.a)
            s.d.resetTemporaries()
            let st = s.d.penState, f = Settings()
            check("켤 때마다 임시 색·굵기·펜이 설정값으로 돌아옴",
                  st.rgb == f.drawColor && st.alpha == 1 && st.penStep == Int(f.drawStep) && st.eraserStep == Int(f.eraserStep) && st.pen == .normal,
                  "\(st)")
        }
        do {
            let s = Sim(); strokes(s, 2); s.key(K.w)
            s.d.finishSession(clear: false)
            check("F9(끄기 그대로): 잉크와 칠판을 남김", s.d.items.count == 2 && s.d.penState.board == 1,
                  "획 \(s.d.items.count) 칠판 \(s.d.penState.board)")
            s.d.finishSession(clear: true)
            check("Esc·위젯 버튼: 잉크와 칠판을 둘 다 지움", s.d.items.last?.kind == .clear && s.d.penState.board == 0,
                  "칠판 \(s.d.penState.board)")
        }
        do {
            let s = Sim(); s.key(K.w); s.key(K.s); strokes(s, 2); s.key(K.delete)
            let st = s.d.penState
            check("Delete는 지우기만 하고 칠판·펜 모드를 유지", st.board == 1 && st.pen == .rainbow && s.d.items.last?.kind == .clear,
                  "칠판 \(st.board) 펜 \(st.pen)")
        }

        // 키
        do {
            let s = Sim(); Settings.shared.drawColor = 0x00FF00
            s.key(K.n3); let yellow = s.d.penState.rgb
            s.key(K.n0)
            check("0은 그 순간의 기본색", yellow == Settings.shared.drawKeyColors[2] && s.d.penState.rgb == 0x00FF00 && s.d.penState.alpha == 1,
                  "rgb=\(String(s.d.penState.rgb, radix: 16))")
            resetSettings()
        }
        do {
            let s = Sim(); s.key(K.a); s.key(K.n4); let a = s.d.penState.pen
            s.key(K.s); s.key(K.n4); let b = s.d.penState.pen
            check("숫자키는 레이저(A)·무지개(S)를 끄고 보통 펜으로", a == .normal && b == .normal, "\(a) \(b)")
        }
        do {
            let s = Sim(); s.key(K.s)
            s.d.down(s.P(80, 100), s.ev(.leftMouseDown, s.P(80, 100)), right: false)
            s.d.drag(s.P(120, 100), s.ev(.leftMouseDragged, s.P(120, 100)))
            s.key(K.n3)                                                          // 긋는 도중 색 키
            s.d.drag(s.P(200, 100), s.ev(.leftMouseDragged, s.P(200, 100)))
            s.key(K.a)                                                           // 긋는 도중 레이저 키
            s.d.drag(s.P(280, 100), s.ev(.leftMouseDragged, s.P(280, 100)))
            s.d.up(s.P(280, 100))
            let last = s.d.items.last
            check("긋는 도중 색·펜 키를 눌러도 색 개수 = 점 개수", last != nil && last?.points.count == last?.hues?.count,
                  "점 \(last?.points.count ?? -1) 색 \(last?.hues?.count ?? -1)")
            let before = s.d.items.count
            s.key(K.a)
            s.d.down(s.P(80, 200), s.ev(.leftMouseDown, s.P(80, 200)), right: false)
            s.d.drag(s.P(150, 200), s.ev(.leftMouseDragged, s.P(150, 200)))
            s.key(K.s)
            s.d.drag(s.P(220, 200), s.ev(.leftMouseDragged, s.P(220, 200)))
            s.d.up(s.P(220, 200))
            check("레이저 획은 목록에 쌓이지 않음", s.d.items.count == before)
            s.stroke([s.P(80, 300), s.P(200, 300)])
            check("다음 획부터 새 펜(무지개)이 적용됨", s.d.items.last?.hues != nil)
        }
        do {
            let s = Sim()
            s.key(18); let a = s.d.penState.rgb
            s.key(19); let b = s.d.penState.rgb
            check("키 코드 표: 1·2는 입력 소스와 상관없이 자리 번호로 동작", a == Settings.shared.drawKeyColors[0] && b == Settings.shared.drawKeyColors[1])
        }

        // Windows와 같은 값인지
        let penExpect: [Double] = [3, 3.9, 5.1, 6.6, 8.6, 11.1, 14.5, 18.8, 24.5, 31.8]
        let eraserExpect: [Double] = [10, 15, 23, 34, 51, 76, 114, 171, 256, 384]
        let penNow = (1...10).map { (Double(penPx($0)) * 10).rounded() / 10 }
        let eraserNow = (1...10).map { Double(eraserPx($0)).rounded() }
        check("펜 굵기 표가 README와 같음 (3 … 31.8)", penNow == penExpect, "\(penNow)")
        check("지우개 굵기 표가 README와 같음 (10 … 384)", eraserNow == eraserExpect, "\(eraserNow)")
        do {
            let f = Settings()
            check("펜·지우개 기준값과 단계 수", STEP_MAX == 10 && abs(Double(penPx(2) / penPx(1)) - 1.3) < 1e-9 && abs(Double(eraserPx(2) / eraserPx(1)) - 1.5) < 1e-9)
            check("기본 숫자키 색 9개가 README 표와 같음",
                  f.drawKeyColors == [0xFF0000, 0xFF7F00, 0xFFFF00, 0x00FF00, 0x0000FF, 0x4B0082, 0x9400D3, 0x000000, 0xFFFFFF])
            check("칠판 W/E/R 기본색", f.boardColors == [0xFFFFFF, 0x14472F, 0x000000])
        }
        if let ahk, let text = try? String(contentsOfFile: ahk, encoding: .utf8) {
            func numbers(_ s: String) -> [Double] {
                guard let re = try? NSRegularExpression(pattern: "-?(?:0x[0-9A-Fa-f]+|[0-9]+(?:\\.[0-9]+)?)") else { return [] }
                return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
                    let t = String(s[Range(m.range, in: s)!])
                    return t.contains("0x") ? Double(Int(t.replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0) : Double(t)
                }
            }
            func ahkArray(_ name: String) -> [Double]? {
                guard let re = try? NSRegularExpression(pattern: "^\(name)\\s*:=\\s*\\[(.*)\\]", options: .anchorsMatchLines),
                      let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let r = Range(m.range(at: 1), in: text) else { return nil }
                return numbers(String(text[r]))
            }
            func ahkNumber(_ name: String) -> Double? {
                guard let re = try? NSRegularExpression(pattern: "\\b\(name)\\s*:=\\s*(-?[0-9]+(?:\\.[0-9]+)?)"),
                      let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let r = Range(m.range(at: 1), in: text) else { return nil }
                return Double(text[r])
            }
            let f = Settings()
            check("ahk와 같음: DRAW_COLOR_DEFAULTS", ahkArray("DRAW_COLOR_DEFAULTS") == f.drawKeyColors.map(Double.init),
                  "\(ahkArray("DRAW_COLOR_DEFAULTS") ?? [])")
            check("ahk와 같음: BOARD_COLOR_DEFAULTS (Q는 -1)", ahkArray("BOARD_COLOR_DEFAULTS") == [-1] + f.boardColors.map(Double.init),
                  "\(ahkArray("BOARD_COLOR_DEFAULTS") ?? [])")
            check("ahk와 같음: BOARD_KEYS의 칠판 색", ahkArray("BOARD_KEYS") == [-1] + f.boardColors.map(Double.init),
                  "\(ahkArray("BOARD_KEYS") ?? [])")
            check("ahk와 같음: LASER_HOLD·FADE·MIN_WIDTH",
                  ahkNumber("LASER_HOLD_MS") == LASER_HOLD * 1000 && ahkNumber("LASER_FADE_MS") == LASER_FADE * 1000
                  && ahkNumber("LASER_MIN_WIDTH") == Double(LASER_MIN_WIDTH))
            check("ahk와 같음: LASER_LAYERS", ahkArray("LASER_LAYERS") == LASER_LAYERS.flatMap { [Double($0.0), Double($0.1), Double($0.2)] },
                  "\(ahkArray("LASER_LAYERS") ?? [])")
            check("ahk와 같음: 펜·지우개 기준값·단계·무지개 한 바퀴",
                  ahkNumber("PEN_BASE_PX") == 3 && ahkNumber("PEN_STEP_RATIO") == 1.3 && ahkNumber("ERASER_BASE_PX") == 10
                  && ahkNumber("ERASER_STEP_RATIO") == 1.5 && ahkNumber("STEP_MAX") == Double(STEP_MAX)
                  && ahkNumber("RAINBOW_CYCLE_PX") == Double(RAINBOW_CYCLE_PX))
        } else {
            check("ahk와 같은 값 점검을 건너뜀 (--ahk 없음)", true, "INFO")
        }

        // 그림 만드는 길
        do {
            let s = Sim(); s.stroke(s.wiggle(40, 100, 300)); s.key(K.n3)
            Settings.shared.drawKeyAlphas[2] = 50
            s.key(K.n3); s.stroke(s.wiggle(40, 200, 300))
            let a = s.image().flatMap(rgba), b = s.image().flatMap(rgba)
            check("같은 목록은 늘 같은 그림 (renderScene은 순수함)", a != nil && a == b)
            resetSettings()
        }
    }

    // ---------- 실행 ----------
    static func run(_ args: [String]) -> Int32 {
        func arg(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard let outPath = arg("--golden") else { print("사용법: --golden <결과 폴더> [--goldens <기준 폴더>] [--ahk <파일>] [--update-goldens]"); return 2 }
        let out = URL(fileURLWithPath: outPath), fm = FileManager.default
        let goldenDir = arg("--goldens").map { URL(fileURLWithPath: $0) }
        let update = args.contains("--update-goldens")
        try? fm.removeItem(at: out)
        for sub in ["actual", "diff"] { try? fm.createDirectory(at: out.appendingPathComponent(sub), withIntermediateDirectories: true) }
        if update, let g = goldenDir { try? fm.createDirectory(at: g, withIntermediateDirectories: true) }

        var log: [String] = []
        var passed = 0, failed = 0, sceneOK = 0, sceneFail = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            log.append("\(ok ? "OK" : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
            if detail == "INFO" { return }
            if ok { passed += 1 } else { failed += 1 }
        }

        var sheet: [(name: String, image: CGImage, failed: Bool, note: String)] = []
        let list = scenes()
        check("기준 그림 장면 수 \(maxGoldenCount)개 이하", list.count <= maxGoldenCount, "\(list.count)개")
        for scene in list {
            var img: CGImage?
            autoreleasepool { img = scene.make().flatMap(flatten) }
            guard let flat = img, let data = png(flat) else {
                log.append("FAIL 장면 \(scene.name) — 그림을 만들지 못함"); sceneFail += 1
                continue
            }
            try? data.write(to: out.appendingPathComponent("actual/\(scene.name).png"))
            var bad = false
            if update, let g = goldenDir {
                try? data.write(to: g.appendingPathComponent("\(scene.name).png"))
                log.append("UPDATED \(scene.name)")
            } else if let g = goldenDir {
                let url = g.appendingPathComponent("\(scene.name).png")
                if let want = (try? Data(contentsOf: url)).flatMap(decode), let a = rgba(want), let b = rgba(flat) {
                    if want.width != flat.width || want.height != flat.height {
                        bad = true
                        log.append("FAIL 장면 \(scene.name) — 크기가 다름 (기준 \(want.width)×\(want.height), 지금 \(flat.width)×\(flat.height))")
                    } else {
                        var diffCount = 0
                        var diffPixels = [UInt8](b)
                        for i in stride(from: 0, to: a.count, by: 4) {
                            let d = (0..<3).map { abs(Int(a[i + $0]) - Int(b[i + $0])) }.max()!
                            if d > channelTolerance {
                                diffCount += 1
                                diffPixels[i] = 255; diffPixels[i + 1] = 0; diffPixels[i + 2] = 0; diffPixels[i + 3] = 255
                            } else {
                                for c in 0..<3 { diffPixels[i + c] = UInt8(60 + Int(b[i + c]) * 2 / 5) }
                            }
                        }
                        let frac = Double(diffCount) / Double(a.count / 4)
                        if frac > pixelTolerance {
                            bad = true
                            log.append(String(format: "FAIL 장면 %@ — 다른 픽셀 %.2f%% (허용 %.1f%%)", scene.name, frac * 100, pixelTolerance * 100))
                            diffPixels.withUnsafeMutableBytes { p in
                                if let ctx = CGContext(data: p.baseAddress, width: flat.width, height: flat.height, bitsPerComponent: 8, bytesPerRow: flat.width * 4,
                                                       space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   let di = ctx.makeImage(), let dd = png(di) {
                                    try? dd.write(to: out.appendingPathComponent("diff/\(scene.name).png"))
                                }
                            }
                        }
                    }
                } else {
                    bad = true
                    log.append("FAIL 장면 \(scene.name) — 기준 그림이 없음 (선생님 승인 뒤 --update-goldens)")
                }
            }
            if bad { sceneFail += 1 } else { sceneOK += 1 }
            sheet.append((scene.name, flat, bad, scene.note))
        }

        // 기준 그림 규칙: 40개 이하, 각 30KB 이하
        if let g = goldenDir, let files = try? fm.contentsOfDirectory(at: g, includingPropertiesForKeys: [.fileSizeKey]) {
            let pngs = files.filter { $0.pathExtension == "png" }
            let big = pngs.filter { ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > maxGoldenBytes }
            check("기준 그림 \(maxGoldenCount)개 이하 (지금 \(pngs.count)개)", pngs.count <= maxGoldenCount)
            check("기준 그림은 각 \(maxGoldenBytes / 1024)KB 이하", big.isEmpty, big.map(\.lastPathComponent).joined(separator: ", "))
            let names = Set(list.map(\.name))
            let stale = pngs.map { $0.deletingPathExtension().lastPathComponent }.filter { !names.contains($0) }
            check("장면에 없는 옛 기준 그림이 없음", stale.isEmpty, stale.joined(separator: ", "))
        }

        assertions(check, ahk: arg("--ahk"))

        contactSheet(sheet, to: out.appendingPathComponent("contact-sheet.png"))
        log.append("INFO 장면 통과 \(sceneOK) 실패 \(sceneFail) · 글 점검 통과 \(passed) 실패 \(failed)")
        log.append("DONE")
        try? log.joined(separator: "\n").write(to: out.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)

        let failures = log.filter { $0.hasPrefix("FAIL") }
        if failures.isEmpty {
            print("그림 점검 통과: 장면 \(sceneOK)개, 글 점검 \(passed)개" + (update ? " (기준 그림을 새로 저장함)" : ""))
            return 0
        }
        print("그림 점검 실패: 장면 \(sceneFail)개, 글 점검 \(failed)개")
        failures.forEach { print("  " + $0) }
        print("  차이 그림·축소 모음: \(outPath)")
        return 1
    }

    // 모든 장면을 작게 줄여 한 장에 모은다 (실패한 장면은 빨간 테두리) — 선생님께 보내는 "기준 그림 한 장"
    static func contactSheet(_ items: [(name: String, image: CGImage, failed: Bool, note: String)], to url: URL) {
        guard !items.isEmpty else { return }
        let cols = 5, cell = CGSize(width: 250, height: 165), pad: CGFloat = 10
        let rows = (items.count + cols - 1) / cols
        let size = CGSize(width: CGFloat(cols) * (cell.width + pad) + pad, height: CGFloat(rows) * (cell.height + pad) + pad)
        let img = bitmap(size) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.interpolationQuality = .high
            for (i, it) in items.enumerated() {
                let col = i % cols, row = i / cols
                let x = pad + CGFloat(col) * (cell.width + pad)
                let y = size.height - pad - CGFloat(row + 1) * (cell.height + pad) + pad
                let box = CGRect(x: x, y: y + 16, width: cell.width, height: cell.height - 16)
                let k = min(box.width / CGFloat(it.image.width), box.height / CGFloat(it.image.height))
                let w = CGFloat(it.image.width) * k, h = CGFloat(it.image.height) * k
                let r = CGRect(x: box.minX, y: box.maxY - h, width: w, height: h)
                ctx.draw(it.image, in: r)
                ctx.setStrokeColor(it.failed ? CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1) : CGColor(srgbRed: 0.6, green: 0.6, blue: 0.6, alpha: 1))
                ctx.setLineWidth(it.failed ? 3 : 1)
                ctx.stroke(r)
                withNS(ctx) {
                    let label = it.name + (it.note.isEmpty ? "" : "  [\(it.note.prefix(3))]")
                    (label as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: 11),
                                                                                       .foregroundColor: it.failed ? NSColor.red : NSColor.black])
                }
            }
        }
        if let img, let data = png(img) { try? data.write(to: url) }
    }
}
