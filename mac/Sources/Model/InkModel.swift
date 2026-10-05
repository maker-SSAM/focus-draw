import CoreGraphics
import Foundation

// 그린 것은 그림(픽셀)이 아니라 "획 목록"으로 들고 있다. 화면마다 그 목록을 한 장의 그림에 구워 두고,
// 새 획이 끝날 때마다 그 한 획만 더 굽는다. 실행 취소는 목록에서 마지막 하나를 빼고 처음부터 다시 굽는 것.
// 좌표는 모두 전체 화면 좌표(맥 기준: 왼쪽 아래가 원점)라서 모니터가 여럿이어도 한 목록으로 된다.
// 이 파일은 AppKit 없이 돈다.

struct InkItem {
    enum Kind { case stroke, erase, clear }
    var kind: Kind
    var points: [CGPoint] = []
    var width: CGFloat = 1
    var rgb: UInt32 = 0
    var alpha: CGFloat = 1
    var hues: [CGFloat]? = nil // 무지개 펜: 점마다 색상(0~360)
    var head: [CGPoint]? = nil // 화살표 머리: 채운 삼각형의 세 점 (Windows와 같다). 무지개는 몸통이 끝난 색으로 채운다.

    var bounds: CGRect {
        guard let f = points.first else { return .null }
        var r = CGRect(origin: f, size: .zero)
        for p in points + (head ?? []) { r = r.union(CGRect(origin: p, size: .zero)) }
        return r.insetBy(dx: -width - 2, dy: -width - 2)
    }
}

final class InkModel {
    private(set) var items: [InkItem] = []
    private(set) var removed = 0   // 앞에서 버린 항목 수. 항목의 "절대 번호" = removed + items 안의 자리 (화면의 바닥 그림이 어디까지 구웠는지 적는 데 쓴다)
    private(set) var undoFloor = 0 // 이보다 앞은 되돌리지 않는다 (최대 UNDO_MAX단계, 끈 뒤 UNDO_KEEP_S초)
    private var offSince: Date?
    var clock: () -> Date = Date.init // 자체 점검이 가짜 시계를 넣는다

    // 되돌릴 수 없게 된 곳까지의 절대 번호: 이 앞은 바닥 그림에 구워도 된다
    var floorAbs: Int { removed + undoFloor }

    // 절대 번호 [from, to) 항목 (버려진 앞부분은 건너뛴다)
    func slice(from: Int, to: Int) -> ArraySlice<InkItem> {
        let a = max(0, from - removed), b = min(items.count, to - removed)
        return a < b ? items[a..<b] : []
    }

    // 끈 지 UNDO_KEEP_S초가 넘었으면 그 앞 그림은 되돌리지 않는다 (켤 때, 그리고 끌 때 예약한 작업이 부른다)
    func expireIfNeeded() {
        if let off = offSince, clock().timeIntervalSince(off) > UNDO_KEEP_S { setUndoFloor(items.count) }
        offSince = nil
    }

    func noteOff() { offSince = clock() }
    var isOffTimed: Bool { offSince != nil }

    func commit(_ item: InkItem) {
        items.append(item)
        setUndoFloor(max(undoFloor, items.count - UNDO_MAX))
    }

    private func setUndoFloor(_ f: Int) {
        undoFloor = f
        // 되돌릴 수 없는 곳에 "전부 지우기"가 있으면 그 앞은 더 들고 있을 이유가 없다
        // (화면이 비어 있는 채로 1분이 지나면 이 길로 목록까지 빈다)
        if let idx = items[..<undoFloor].lastIndex(where: { $0.kind == .clear }) {
            items.removeSubrange(0...idx)
            undoFloor -= idx + 1
            removed += idx + 1
        }
    }

    // 되돌렸으면 true (화면 그림을 다시 구워야 한다)
    func undo() -> Bool {
        guard items.count > undoFloor else { return false }
        items.removeLast()
        return true
    }

    // 이미 비어 있으면(마지막이 "전부 지우기") 새 단계를 만들지 않고 nil
    func clearAll() -> InkItem? {
        guard let last = items.last, last.kind != .clear else { return nil }
        let c = InkItem(kind: .clear)
        commit(c)
        return c
    }

    // 주 화면이 바뀌어 전역 좌표의 원점이 옮겨 가면 잉크도 같이 옮겨 원래 화면 자리에 있게 한다
    func translate(dx: CGFloat, dy: CGFloat) {
        guard dx != 0 || dy != 0 else { return }
        for i in items.indices {
            for j in items[i].points.indices {
                items[i].points[j].x += dx
                items[i].points[j].y += dy
            }
        }
    }
}

// 그리기 코드가 설정을 직접 읽지 않도록, 켤 때(그리고 설정이 바뀔 때) 설정에서 복사해 넘기는 값.
// 만드는 자리는 Platform/Settings.swift (DrawConfig.init(_:)).
struct DrawConfig: Equatable {
    var drawOpacity: Double = 100
    var drawColor: UInt32 = DRAW_COLORS[0]
    var drawStep = 5
    var eraserStep = 5
    var drawKeyColors: [UInt32] = DRAW_COLORS
    var drawKeyAlphas: [Double] = Array(repeating: 100, count: 9)
    var boardColors: [UInt32] = BOARD_COLORS
    var boardAlphas: [Double] = [100, 100, 100]
    var laserHold: Double = LASER_HOLD * 1000   // ms
    var laserFade: Double = LASER_FADE * 1000   // ms
    var laserGlow: Double = 100                 // %
}
