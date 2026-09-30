import AppKit

// ================= 드로잉의 펜 상태와 마우스 =================
// 그림 원본(선 목록)은 InkModel이, 판(창)은 InkSurface가 든다. 여기는 "지금 어떤 펜으로 무엇을 긋고 있는가"와
// 마우스 입력을 맡는다. 키는 Input/DrawKeyboard.swift, 커서 모양은 UI/BrushCursor.swift, 레이저·숫자 배지는 UI/Overlays.swift.
// 설정은 직접 읽지 않고 켤 때 받은 복사본(config)만 쓴다.

enum PenKind { case normal, laser, rainbow }

@MainActor final class DrawController {
    let state: AppState
    let surface = InkSurface()
    let model = InkModel()
    var config = DrawConfig()
    var requestOff: (OffReason) -> Void = { _ in } // Esc가 들어오면 DrawSession에 끄기를 부탁한다

    var isOn: Bool { state.drawOn }
    var items: [InkItem] { model.items }
    var clock: () -> Date { get { model.clock } set { model.clock = newValue } } // 자체 점검이 가짜 시계를 넣는다

    // 지금 펜
    var rgb: UInt32 = 0xFF0000
    var alpha: CGFloat = 1
    var penStep = 5
    var eraserStep = 5
    var pen: PenKind = .normal
    // 마우스를 누른 순간의 펜 종류를 잠근다. 긋는 도중 키로 pen을 바꿔도 이번 획은 끝까지
    // activePen대로 그려지고(hues·points 길이가 어긋나 죽는 일이 없다), 새 pen은 다음 획부터 적용된다.
    var activePen: PenKind = .normal
    var rainbowHue: CGFloat = 0
    var board = 0 // 0 = 투명(Q), 1~3 = W/E/R

    // 긋는 중
    private(set) var live: InkItem?
    var mode: ShapeMode = .free
    var start: CGPoint = .zero
    var lastPoint: CGPoint = .zero
    var liveBounds: CGRect = .null
    var erasing = false
    var rightDown = false
    var held: Set<UInt16> = [] // 누르고 있는 Z/X/C
    var scrollAccum: CGFloat = 0
    var mouse: CGPoint = .zero
    var mouseInside = true      // 포인터 아래가 판인가 (위젯·캡처 화면 위면 false → 화살표를 보인다)
    var optionHeld = false      // ⌥를 누르고 있는가 → 지우개 링 (ModifierWatch가 읽는다)
    let watch = ModifierWatch()
    private var lastCheckedMouse = CGPoint(x: -1e9, y: -1e9)

    // 레이저 (UI/Overlays.swift)
    var laser: [[LaserPt]] = []
    var laserLive: [LaserPt]? = nil
    var laserTimer: Timer?
    // 굵기·진하기를 바꿀 때 잠깐 뜨는 숫자 (UI/Overlays.swift)
    var badge: (text: String, until: Date)?
    var badgeRect: CGRect = .null
    var badgeText: String? { badge?.text }
    // 판에 직접 그리는 붓 동그라미 (UI/BrushCursor.swift)
    var cursorImage: NSImage?

    init(state: AppState) {
        self.state = state
        surface.controller = self
    }

    // 드로잉을 막 켰을 때: 커서 자리를 잡고 붓 동그라미를 그린다
    func begin() {
        mouse = NSEvent.mouseLocation
        mouseInside = true
        optionHeld = ModifierWatch.optionDown()
        SystemCursor.hide(.board)
        surface.invalidateAll() // 지난번 자리에 남은 동그라미까지 지운다
        updateCursor()
        watch.onTick = { [weak self] in self?.tick() }
        watch.start()
    }

    // 끄는 자리: 살핌을 멈추고 커서 상태를 되돌린다
    func end() {
        watch.stop()
        optionHeld = false
        mouseInside = true
        lastCheckedMouse = CGPoint(x: -1e9, y: -1e9)
    }

    // 20Hz (드로잉 중에만): ⌥ 상태, 포인터 아래 창, 커서 숨김이 풀렸는지
    func tick() {
        guard isOn else { return }
        refreshOption()
        tickCount += 1
        if tickCount % 2 == 0, gestureStarted() { requestOff(.gesture); return } // 10Hz
        let m = NSEvent.mouseLocation
        if m != lastCheckedMouse { lastCheckedMouse = m; syncPointer() }
        if mouseInside { SystemCursor.reassert() }
    }

    // 네 손가락 제스처가 시작됐는가: 판이 화면에서 밀려났거나 Mission Control(Dock의 높은 창)이 떴다
    private var tickCount = 0
    func gestureStarted() -> Bool {
        if boardMovedAway(boardFrames: surface.windows.map(\.frame), screenFrames: NSScreen.screens.map(\.frame)) { return true }
        return missionControlShowing(currentWindowInfos(), boardLayer: OVERLAY_LEVEL.rawValue)
    }

    // ⌥만 눌러도 지우개 링, 떼면 붓 동그라미 (판이 키 창이 아니라 flagsChanged가 오지 않으므로 직접 읽는다)
    func refreshOption(_ held: Bool = ModifierWatch.optionDown()) {
        guard held != optionHeld else { return }
        optionHeld = held
        updateCursor()
    }

    // 실제 포인터 아래 창으로 판단한다: 판이면 붓 동그라미와 숨긴 커서, 위젯·캡처 화면·시스템 창이면 화살표
    func syncPointer(_ target: PointerTarget? = nil) {
        guard isOn else { return }
        let t = target ?? currentPointerTarget(boards: Set(surface.windowNumbers))
        let over = t == .board
        guard over != mouseInside else { return }
        mouseInside = over
        surface.invalidate(cursorRect)
        if over { SystemCursor.hide(.board) } else { SystemCursor.show(.board) }
    }

    // 숫자키로 바꾼 색·굵기는 임시값 — 켤 때마다 설정 창의 값으로 돌아온다
    func resetTemporaries() {
        rgb = config.drawColor; alpha = 1
        penStep = config.drawStep; eraserStep = config.eraserStep
        pen = .normal
    }

    func expireUndoIfNeeded() { model.expireIfNeeded() }

    // 끄는 순간의 그림·칠판 정리. clear: Esc·위젯 버튼은 다 지우고 나가고, F9는 그대로 남긴다
    func finishSession(clear: Bool) {
        if clear {
            clearAll()
            board = 0
        }
        cancelLive()
        laser = []; laserLive = nil
        model.noteOff()
    }

    // 지금 펜 상태 (자체 점검용)
    var penState: (rgb: UInt32, alpha: CGFloat, penStep: Int, eraserStep: Int, pen: PenKind, board: Int) {
        (rgb, alpha, penStep, eraserStep, pen, board)
    }

    // ---------- 칠판 ----------
    var boardColor: CGColor? {
        guard board > 0 else { return nil }
        return color(config.boardColors[board - 1], CGFloat(config.boardAlphas[board - 1]) / 100).cgColor
    }

    // 지우개 테두리는 칠판의 보색 — 어느 칠판 위에서도 묻히지 않는다 (칠판이 없으면 검정)
    var currentEraserRing: NSColor {
        eraserRingColor(boardRGB: board > 0 ? config.boardColors[board - 1] : nil)
    }

    // ---------- 마우스 ----------
    func mouseMoved(_ p: CGPoint) {
        Log.moves += 1
        moveMouse(p)
    }

    func mouseEntered(_ p: CGPoint) {
        guard isOn else { return }
        moveMouse(p)
        syncPointer()
    }

    // 판 밖(위젯 위, 판이 없는 곳)으로 나가면 평소 화살표를 돌려준다 — 지금 포인터 아래 창을 보고 정한다
    func mouseExited() {
        guard isOn else { return }
        syncPointer()
    }

    func down(_ p: CGPoint, _ e: NSEvent, right: Bool) {
        moveMouse(p)
        start = p; lastPoint = p
        activePen = pen
        if right { rightDown = true }
        if right || e.modifierFlags.contains(.option) {
            // 지우개: 오른쪽 버튼으로 문지르기 (트랙패드에서는 ⌥ Option을 누른 채 끌기)
            erasing = true
            updateCursor()
            live = InkItem(kind: .erase, points: [p], width: eraserPx(eraserStep))
            liveBounds = live!.bounds
            surface.invalidate(liveBounds)
            return
        }
        mode = currentShape(e.modifierFlags)
        if activePen == .laser {
            if mode == .free {
                laserLive = [LaserPt(p: p, t: Date.timeIntervalSinceReferenceDate, hue: nil)]
                startLaserTimer()
            } else {
                laserLive = []
            }
            return
        }
        let w = penPx(penStep)
        live = InkItem(kind: .stroke, points: [p], width: w, rgb: rgb, alpha: alpha,
                       hues: activePen == .rainbow ? [rainbowHue] : nil)
        liveBounds = live!.bounds
        surface.invalidate(liveBounds)
    }

    func drag(_ p: CGPoint, _ e: NSEvent) {
        moveMouse(p)
        if erasing, var item = live {
            item.points.append(p)
            live = item
            surface.invalidate(segmentBounds(lastPoint, p, item.width))
            lastPoint = p
            return
        }
        if activePen == .laser, laserLive != nil {
            let now = Date.timeIntervalSinceReferenceDate
            if mode == .free {
                laserLive!.append(LaserPt(p: p, t: now, hue: nil))
            } else {
                let end = shapeEnd(p, e.modifierFlags)
                laserLive = shapePoints(mode, start, end, width: laserWidth).map { LaserPt(p: $0, t: now, hue: nil) }
            }
            lastPoint = p
            return
        }
        guard var item = live else { return }
        if mode == .free {
            if activePen == .rainbow {
                rainbowHue = (rainbowHue + hypot(p.x - lastPoint.x, p.y - lastPoint.y) * 360 / RAINBOW_CYCLE_PX)
                    .truncatingRemainder(dividingBy: 360)
                item.hues?.append(rainbowHue)
            }
            item.points.append(p)
            live = item
            // 반투명 획은 획 전체를 한 겹으로 다시 얹으므로 지나온 자리 전체를, 불투명하면 새 토막만 다시 그린다
            surface.invalidate(item.alpha < 1 || activePen == .rainbow ? item.bounds : segmentBounds(lastPoint, p, item.width))
        } else {
            refreshShape(end: shapeEnd(p, e.modifierFlags))
        }
        lastPoint = p
    }

    func up(_ p: CGPoint) {
        rightDown = false
        if erasing {
            erasing = false
            // 움직이지 않은 오른쪽 클릭·⌥ 클릭(트랙패드 두 손가락 탭 포함)은 아무것도 지우지 않고
            // 실행 취소 단계도 남기지 않는다
            if let item = live, item.points.count > 1 { commit(item) }
            live = nil
            updateCursor()
            return
        }
        if activePen == .laser, let pts = laserLive {
            // 도형은 손을 뗀 순간부터 함께 사라진다
            let now = Date.timeIntervalSinceReferenceDate
            if !pts.isEmpty { laser.append(mode == .free ? pts : pts.map { LaserPt(p: $0.p, t: now, hue: $0.hue) }) }
            laserLive = nil
            startLaserTimer()
            return
        }
        guard let item = live else { return }
        if activePen == .rainbow, mode != .free, let h = item.hues?.last { rainbowHue = h }
        commit(item)
        live = nil
        updateCursor()
    }

    var laserWidth: CGFloat { max(penPx(penStep), LASER_MIN_WIDTH) }

    private func currentShape(_ f: NSEvent.ModifierFlags) -> ShapeMode {
        if held.contains(6) { return .line }   // Z
        if held.contains(7) { return .wave }   // X
        if held.contains(8) { return .arrow }  // C
        if f.contains(.shift) { return .rect }
        if f.contains(.control) { return .ellipse }
        return .free
    }

    func shapeEnd(_ p: CGPoint, _ f: NSEvent.ModifierFlags) -> CGPoint {
        [.line, .wave, .arrow].contains(mode) && f.contains(.shift) ? snap45(start, p) : p
    }

    func refreshShape(end: CGPoint) {
        guard var item = live else { return }
        item.points = shapePoints(mode, start, end, width: item.width)
        if activePen == .rainbow {
            // 테두리를 따라 색이 돈다. 미리보기는 매번 획을 시작한 색에서 다시 출발한다.
            var h = item.hues?.first ?? rainbowHue
            var hues: [CGFloat] = [h]
            for i in 1..<item.points.count {
                h += hypot(item.points[i].x - item.points[i - 1].x, item.points[i].y - item.points[i - 1].y) * 360 / RAINBOW_CYCLE_PX
                hues.append(h.truncatingRemainder(dividingBy: 360))
            }
            item.hues = hues
        }
        let nb = item.bounds
        surface.invalidate(liveBounds.union(nb))
        liveBounds = nb
        live = item
    }

    private func segmentBounds(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)).insetBy(dx: -w - 2, dy: -w - 2)
    }

    private func cancelLive() {
        if live != nil { surface.invalidate(liveBounds.union(live!.bounds)) }
        live = nil; erasing = false; rightDown = false; held = []
    }

    // ---------- 목록 다루기 ----------
    private func commit(_ item: InkItem) {
        model.commit(item)
        surface.commit(item)
    }

    func undo() {
        if model.undo() { surface.rebuildCaches() }
    }

    func clearAll() {
        if let c = model.clearAll() { surface.commit(c) }
    }
}
