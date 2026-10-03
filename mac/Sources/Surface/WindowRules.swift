import AppKit

// 창 높이(레벨). 드로잉 판은 화면보호기 높이에 두어 메뉴 막대·Dock·전체 화면 슬라이드쇼까지 덮고,
// 위젯은 그 위(드로잉 중에도 눌리도록), 강조 원과 클릭 링은 맨 위에 둔다.
let OVERLAY_LEVEL = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
let WIDGET_LEVEL = NSWindow.Level(rawValue: OVERLAY_LEVEL.rawValue + 1)
let SPOT_LEVEL = NSWindow.Level(rawValue: OVERLAY_LEVEL.rawValue + 2)

// 모든 데스크톱(Space)과 다른 앱의 전체 화면 위에도 뜨게 한다 (S1 재시험에서 이 조합이 가장 안정적이었다).
let EVERYWHERE: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

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

// 화면 번호와 자리. 주 화면이 바뀌면 AppKit의 전역 좌표 원점이 다른 화면으로 옮겨 가므로(프로젝터를 주 화면으로 고른 경우 등),
// 그 전후에 같은 화면이 얼마나 움직였는지로 잉크를 옮긴다.
struct ScreenSnap: Equatable { var id: UInt32; var frame: CGRect }

@MainActor func screenSnapshots() -> [ScreenSnap] {
    NSScreen.screens.map { s in
        ScreenSnap(id: (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0, frame: s.frame)
    }
}

// 잉크를 옮길 양. 예전 화면 중 지금도 있는 첫 화면(주 화면 먼저)이 전역 좌표에서 움직인 만큼 — 그 화면의 잉크가 제자리에 있게.
// 같은 화면이 하나도 없으면 옮기지 않는다.
func inkShift(old: [ScreenSnap], new: [ScreenSnap]) -> CGVector {
    for o in old {
        if let n = new.first(where: { $0.id == o.id }) {
            return CGVector(dx: n.frame.minX - o.frame.minX, dy: n.frame.minY - o.frame.minY)
        }
    }
    return .zero
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

// ================= 포인터 아래에 무엇이 있는가 =================
// 붓 동그라미를 그릴지(판 위), 화살표를 보일지(위젯·캡처 화면·시스템 창 위)를 "저장해 둔 표시"가 아니라
// 지금 포인터 아래 창으로 정한다 (CGWindowListCopyWindowInfo — 권한 불필요, 설계도 6절).
enum PointerTarget: Equatable { case board, widget, other }

struct WindowInfo { var number: Int; var layer: Int; var alpha: Double; var ownedByUs: Bool; var frame: CGRect; var owner = "" } // frame: 화면 왼쪽 위 기준(CG)

// windows: 앞에서 뒤 순서. point: 화면 왼쪽 위 기준(CG) 좌표.
func pointerTarget(at point: CGPoint, windows: [WindowInfo], boards: Set<Int>, boardLayer: Int, widgetLayer: Int) -> PointerTarget {
    for w in windows where w.frame.contains(point) {
        if boards.contains(w.number) { return .board }
        if w.ownedByUs {
            if w.layer == widgetLayer || w.layer == NSWindow.Level.statusBar.rawValue { return .widget } // 위젯과 우리 메뉴 막대 아이콘 위에서는 화살표
            continue // 클릭이 통과하는 강조 원·클릭 링 등
        }
        if w.alpha < 0.05 { continue }
        return w.layer > boardLayer ? .other : .board // 판보다 위에 뜬 다른 창(캡처 화면·시스템 창)
    }
    return .board
}

// 네 손가락 제스처(Mission Control·데스크톱 넘기기)는 앱 전환·데스크톱 바뀜 알림이 늦게(끝난 뒤에) 온다.
// 그 사이에 보이는 신호로 바로 끈다 (S4 확인에서 발견, 진단 기록의 표본에서 찾음):
//  - 데스크톱을 넘기는 중에는 판 창의 자리가 화면에서 밀려난다 (ink 자리 x=-1575 등)
//  - Mission Control이 뜨면 Dock 소유의 큰 창이 레벨 18·20에 생기고, 넘기는 중에는 판과 같거나 높은 레벨(1000·1001)에도 나타난다
// 포인터가 Dock이 나올 만한 가장자리 띠(아래·왼쪽·오른쪽 끝에서 160pt 안)에 있는가. mouse와 screens는 AppKit 좌표.
func pointerNearDockEdge(_ mouse: CGPoint, screens: [CGRect], band: CGFloat = 160) -> Bool {
    guard let s = screens.first(where: { $0.contains(mouse) }) else { return false }
    return mouse.y - s.minY < band || mouse.x - s.minX < band || s.maxX - mouse.x < band
}

func boardMovedAway(boardFrames: [CGRect], screenFrames: [CGRect]) -> Bool {
    boardFrames.contains { b in !screenFrames.contains { $0.equalTo(b) } }
}

// nearDockEdge: 포인터가 화면 아래·왼쪽·오른쪽 가장자리 띠 안에 있는가. Dock을 자동 숨김으로 두면 포인터를 가장자리에 대는 것만으로
// Dock 창이 판과 같거나 높은 레벨에 생기므로, 그때는 그 신호로 "넘기는 중"이라고 보지 않는다 (데스크톱 넘기기는 boardMovedAway가,
// Mission Control은 아래 두 번째 조건이 잡는다).
func missionControlShowing(_ windows: [WindowInfo], boardLayer: Int, nearDockEdge: Bool = false) -> Bool {
    let dock = windows.filter { !$0.ownedByUs && $0.owner == "Dock" && $0.alpha > 0.05 }
    // Mission Control이 뜬 뒤: 화면만 한 Dock 창이 레벨 18·20에 생긴다 (평소의 Dock 창은 레벨 -2147483624 등 아주 낮은 것뿐 —
    // 이 맥에서 open -a "Mission Control" 중에 창 목록을 떠서 확인)
    let big = dock.filter { $0.layer > 0 && $0.layer < boardLayer && $0.frame.width >= 500 && $0.frame.height >= 300 }
    // 진단 기록(2026-10-01)에서 본 것: Dock이 자동 숨김에서 나올 때는 화면만 한 Dock 창이 레벨 20에 하나만 생긴다
    // (포인터 자리가 가장자리로 읽히지 않는 때도 있었다). 진짜 Mission Control은 레벨 18 창이 함께 있거나 화면만 한 창이 둘 이상이다.
    if big.contains(where: { $0.layer == 18 }) || big.count >= 2 { return true }
    // 데스크톱을 넘기는 중: Dock 창이 판과 같거나 높은 레벨 (Dock이 나오는 가장자리에서는 이 신호를 쓰지 않는다)
    return !nearDockEdge && dock.contains { $0.layer >= boardLayer }
}
@MainActor func currentWindowInfos() -> [WindowInfo] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
    let me = Int(ProcessInfo.processInfo.processIdentifier)
    return list.compactMap { d in
        guard let n = d[kCGWindowNumber as String] as? Int,
              let b = d[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: b) else { return nil }
        return WindowInfo(number: n, layer: d[kCGWindowLayer as String] as? Int ?? 0, alpha: d[kCGWindowAlpha as String] as? Double ?? 1,
                          ownedByUs: (d[kCGWindowOwnerPID as String] as? Int) == me, frame: r, owner: d[kCGWindowOwnerName as String] as? String ?? "")
    }
}

// statusItemFrame: 우리 메뉴 막대 아이콘 칸의 화면 자리(AppKit 좌표). 드로잉 판(레벨 1000)이 메뉴 막대 칸보다 늘 앞이라 창 목록으로는 아이콘 위를 가려낼 수 없어서 따로 본다.
@MainActor func currentPointerTarget(boards: Set<Int>, statusItemFrame: CGRect? = nil) -> PointerTarget {
    guard let primary = NSScreen.screens.first else { return .board }
    let mouse = NSEvent.mouseLocation
    if let f = statusItemFrame, f.contains(mouse) { return .widget }
    let pt = CGPoint(x: mouse.x, y: primary.frame.height - mouse.y)
    let infos = currentWindowInfos()
    return pointerTarget(at: pt, windows: infos, boards: boards, boardLayer: OVERLAY_LEVEL.rawValue, widgetLayer: WIDGET_LEVEL.rawValue)
}
