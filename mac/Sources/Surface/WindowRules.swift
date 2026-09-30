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

struct WindowInfo { var number: Int; var layer: Int; var alpha: Double; var ownedByUs: Bool; var frame: CGRect } // frame: 화면 왼쪽 위 기준(CG)

// windows: 앞에서 뒤 순서. point: 화면 왼쪽 위 기준(CG) 좌표.
func pointerTarget(at point: CGPoint, windows: [WindowInfo], boards: Set<Int>, boardLayer: Int, widgetLayer: Int) -> PointerTarget {
    for w in windows where w.frame.contains(point) {
        if boards.contains(w.number) { return .board }
        if w.ownedByUs {
            if w.layer == widgetLayer { return .widget }
            continue // 클릭이 통과하는 강조 원·클릭 링 등
        }
        if w.alpha < 0.05 { continue }
        return w.layer > boardLayer ? .other : .board // 판보다 위에 뜬 다른 창(캡처 화면·시스템 창)
    }
    return .board
}

@MainActor func currentPointerTarget(boards: Set<Int>) -> PointerTarget {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
          let primary = NSScreen.screens.first else { return .board }
    let mouse = NSEvent.mouseLocation
    let pt = CGPoint(x: mouse.x, y: primary.frame.height - mouse.y)
    let me = Int(ProcessInfo.processInfo.processIdentifier)
    let infos: [WindowInfo] = list.compactMap { d in
        guard let n = d[kCGWindowNumber as String] as? Int,
              let b = d[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: b) else { return nil }
        return WindowInfo(number: n, layer: d[kCGWindowLayer as String] as? Int ?? 0, alpha: d[kCGWindowAlpha as String] as? Double ?? 1,
                          ownedByUs: (d[kCGWindowOwnerPID as String] as? Int) == me, frame: r)
    }
    return pointerTarget(at: pt, windows: infos, boards: boards, boardLayer: OVERLAY_LEVEL.rawValue, widgetLayer: WIDGET_LEVEL.rawValue)
}
