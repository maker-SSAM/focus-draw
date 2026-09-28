import AppKit

// 창 높이(레벨). 드로잉 판은 화면보호기 높이에 두어 메뉴 막대·Dock·전체 화면 슬라이드쇼까지 덮고,
// 위젯은 그 위(드로잉 중에도 눌리도록), 강조 원과 클릭 링은 맨 위에 둔다.
let OVERLAY_LEVEL = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
let WIDGET_LEVEL = NSWindow.Level(rawValue: OVERLAY_LEVEL.rawValue + 1)
let SPOT_LEVEL = NSWindow.Level(rawValue: OVERLAY_LEVEL.rawValue + 2)

// 모든 데스크톱(Space)과 다른 앱의 전체 화면 위에도 뜨게 한다.
// 기본은 [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle] — 실험 메뉴에서 바꿔 볼 수 있다.
var EVERYWHERE: NSWindow.CollectionBehavior { Experiments.collectionBehavior }

// 그래도 한 번 숨긴(orderOut) 창은 숨긴 데스크톱에 묶여, 그 전부터 있던 다른 앱의 전체 화면에서는
// 다시 띄워도 나타나지 않는다 (S1 집 시험: 사파리·크롬 전체 화면에서 판·강조가 안 뜸, 기록에 space=0).
// 새로 만든 창은 지금 데스크톱에 뜨므로, 띄우기 전에 이것으로 확인하고 아니면 새로 만든다.
func isOffActiveSpace(_ w: NSWindow?) -> Bool { w.map { !$0.isOnActiveSpace } ?? false }

// 화면 구성(번호·자리·크기·배율). 키노트 쇼가 시작·끝날 때는 화면이 그대로인데도 "화면 설정 바뀜" 알림이
// 1~2초에 수십~수백 번 오므로(S1 집 시험), 이 값이 정말 바뀌었을 때만 판을 새로 만든다.
func screenSignature() -> String {
    NSScreen.screens.map { s in
        let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let f = s.frame
        return "\(id):\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width))x\(Int(f.height))@\(s.backingScaleFactor)"
    }.joined(separator: " ")
}

final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// 클릭이 그대로 통과하는 투명 창 (강조 원, 클릭 링)
func makeClickThroughWindow(size: CGFloat, level: NSWindow.Level) -> GlassPanel {
    let w = GlassPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                       styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.ignoresMouseEvents = true
    w.level = level
    w.collectionBehavior = EVERYWHERE
    w.hidesOnDeactivate = false
    w.isReleasedWhenClosed = false
    return w
}

// ================= 커서 주위 강조 원 =================
final class SpotView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let s = Settings.shared
        color(s.spotColor, CGFloat(s.spotOpacity) / 100).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
    }
}

final class Spotlight {
    private var window: GlassPanel?
    private var timer: Timer?
    private(set) var isOn = false
    var suspended = false { didSet { refresh() } } // 드로잉 중에는 쉰다
    var windowNumber: Int? { window?.windowNumber }

    init() {
        // 켜 둔 채 다른 데스크톱으로 넘어갔는데 원이 따라오지 않았으면 그 자리에서 새로 만든다
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isOn, !self.suspended, isOffActiveSpace(self.window) else { return }
            self.refresh()
        }
    }

    func toggle() { isOn.toggle(); refresh() }

    func applySettings() {
        guard let w = window else { return }
        let size = CGFloat(Settings.shared.spotSize)
        w.setContentSize(NSSize(width: size, height: size))
        w.contentView?.needsDisplay = true
        follow()
    }

    private func refresh() {
        if isOn && !suspended {
            if let old = window, isOffActiveSpace(old) {
                old.orderOut(nil); old.close()
                window = nil
                Diag.log("SPOT", "rebuilt reason=offSpace")
            }
            if window == nil {
                let w = makeClickThroughWindow(size: CGFloat(Settings.shared.spotSize), level: SPOT_LEVEL)
                w.contentView = SpotView()
                window = w
            }
            applySettings()
            window?.orderFrontRegardless()
            if timer == nil {
                let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.follow() }
                RunLoop.main.add(t, forMode: .common)
                timer = t
            }
        } else {
            timer?.invalidate(); timer = nil
            window?.orderOut(nil)
        }
    }

    private func follow() {
        guard let w = window else { return }
        let m = NSEvent.mouseLocation
        let half = w.frame.width / 2
        let o = NSPoint(x: (m.x - half).rounded(), y: (m.y - half).rounded())
        if w.frame.origin != o { w.setFrameOrigin(o) }
    }
}

// ================= 클릭하면 테두리 원이 가운데로 오므라드는 효과 =================
final class RingView: NSView {
    var radius: CGFloat = 0
    var width: CGFloat = 1
    var ringColor = NSColor.red
    override func draw(_ dirtyRect: NSRect) {
        guard radius >= 1 else { return }
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        let p = NSBezierPath(ovalIn: NSRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        p.lineWidth = width
        ringColor.setStroke()
        p.stroke()
    }
}

final class ClickEffect {
    static let frames = 30
    private final class Side {
        var window: GlassPanel?
        var view = RingView()
        var frame = 0
        var timer: Timer?
    }
    private let sides = [Side(), Side()] // 0 = 왼쪽, 1 = 오른쪽
    var enabledNow: () -> Bool = { true }

    func start() {
        // 다른 앱 위의 클릭(전역)과 위젯 위의 클릭(우리 앱)을 둘 다 받는다.
        // 마우스 클릭을 지켜보는 것은 "손쉬운 사용" 권한 없이도 된다.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            self?.fire(right: e.type == .rightMouseDown)
        }
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            self?.fire(right: e.type == .rightMouseDown)
            return e
        }
    }

    private func fire(right: Bool) {
        let s = Settings.shared
        guard enabledNow(), right ? s.rclickEffect : s.clickEffect else { return }
        let side = sides[right ? 1 : 0]
        let size = CGFloat(s.spotSize)
        if let old = side.window, isOffActiveSpace(old) {
            side.timer?.invalidate(); side.timer = nil
            old.orderOut(nil); old.close()
            side.window = nil
        }
        if side.window == nil {
            let w = makeClickThroughWindow(size: size, level: SPOT_LEVEL)
            w.contentView = side.view
            side.window = w
        }
        side.window!.setContentSize(NSSize(width: size, height: size))
        side.window!.alphaValue = CGFloat(right ? s.rclickOpacity : s.clickOpacity) / 100
        side.view.ringColor = color(right ? s.rclickColor : s.clickColor)
        side.frame = 0
        side.timer?.invalidate()
        // 빠르기 1~30 → 한 칸 간격 40~11ms (Windows 판과 같은 셈)
        let interval = Double(41 - (right ? s.rclickSpeed : s.clickSpeed)) / 1000
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.step(side, right: right) }
        RunLoop.main.add(t, forMode: .common)
        side.timer = t
        step(side, right: right)
        side.window!.orderFrontRegardless()
    }

    private func step(_ side: Side, right: Bool) {
        let s = Settings.shared
        guard let w = side.window else { return }
        let thickness = CGFloat(right ? s.rclickThickness : s.clickThickness)
        let size = w.frame.width
        // 처음엔 빠르게 줄다가 가운데 근처에서 천천히 멈추는 감속 곡선
        let t = CGFloat(side.frame) / CGFloat(ClickEffect.frames)
        let eased = 1 - pow(1 - t, 3)
        let radius = (size / 2 - thickness / 2 - 1) * (1 - eased)
        if side.frame >= ClickEffect.frames || radius < 1 {
            side.timer?.invalidate(); side.timer = nil
            w.orderOut(nil)
            return
        }
        // 테두리가 반지름보다 두꺼워지면 찌그러진 덩어리로 보이므로, 끝까지 속이 빈 고리로 남게 가늘어진다
        side.view.width = min(thickness, radius)
        side.view.radius = radius
        side.view.alphaValue = min(1, radius / (thickness * 1.5))
        side.view.needsDisplay = true
        let m = NSEvent.mouseLocation
        w.setFrameOrigin(NSPoint(x: (m.x - size / 2).rounded(), y: (m.y - size / 2).rounded()))
        side.frame += 1
    }
}
