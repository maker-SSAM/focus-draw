import AppKit

// S5의 글 점검: 10분 규칙·바닥 굽기 경계·전부 지우기·화면 원점 옮김. 화면 없이 돈다(Golden.run).
// 창이 있어야 하는 것(긴 수업 그림 견주기·화면 바뀜·끈 뒤 정리)은 SelfTest.longClass가 본다.
@MainActor enum S5Tests {
    static func stroke(_ i: Int) -> InkItem {
        InkItem(kind: .stroke, points: [CGPoint(x: CGFloat(i), y: 10), CGPoint(x: CGFloat(i) + 5, y: 20)], width: 3, rgb: 0xFF0000)
    }

    static func run(_ report: (String, Bool, String) -> Void) {
        func check(_ name: String, _ ok: Bool, _ detail: String = "") { report(name, ok, detail) }

        check("실행 취소 기록은 끈 뒤 10분(600초), 30단계", UNDO_KEEP_S == 600 && UNDO_MAX == 30, "\(UNDO_KEEP_S)초 \(UNDO_MAX)단계")

        // ---- 10분 규칙 (가짜 시계) ----
        for (sec, canUndo) in [(599.0, true), (601.0, false)] {
            let m = InkModel(); var now = Date(timeIntervalSince1970: 2_000_000)
            m.clock = { now }
            for i in 0..<3 { m.commit(stroke(i)) }
            m.noteOff()
            now.addTimeInterval(sec); m.expireIfNeeded()
            let undone = m.undo()
            check("끈 뒤 \(Int(sec))초: \(canUndo ? "되살림 O" : "되살림 X")", undone == canUndo, "되돌림=\(undone)")
        }
        do { // 화면이 비어 있는 채(마지막이 전부 지우기)로 10분이 지나면 목록까지 빈다
            let m = InkModel(); var now = Date(timeIntervalSince1970: 2_000_000)
            m.clock = { now }
            for i in 0..<5 { m.commit(stroke(i)) }
            _ = m.clearAll()
            m.noteOff()
            now.addTimeInterval(601); m.expireIfNeeded()
            check("10분 뒤 화면이 비어 있으면 선 목록도 빔", m.items.isEmpty, "남은 \(m.items.count)개")
            let n = InkModel(); n.clock = { now }
            for i in 0..<5 { n.commit(stroke(i)) }
            n.noteOff(); now.addTimeInterval(601); n.expireIfNeeded()
            check("10분 뒤 화면에 그림이 있으면 목록은 그대로(되돌리기만 비움)", n.items.count == 5 && !n.undo(), "\(n.items.count)개")
        }

        // ---- 30단계 경계와 바닥 굽기 자리 ----
        do {
            let m = InkModel()
            for i in 0..<100 { m.commit(stroke(i)) }
            check("바닥 굽기 자리: 100획이면 앞 70획(절대 번호 0..<70)을 구워도 됨", m.floorAbs == 70 && m.slice(from: 0, to: 70).count == 70,
                  "floorAbs=\(m.floorAbs)")
            var undone = 0
            while m.undo() { undone += 1 }
            check("100획에서 실행 취소는 30번까지", undone == 30 && m.items.count == 70, "\(undone)번")
        }
        do { // 바닥 그림 경계를 넘나드는 전부 지우기: 지우기가 되돌릴 수 없는 곳으로 밀리면 그 앞 목록이 사라지고 절대 번호는 이어진다
            let m = InkModel()
            for i in 0..<10 { m.commit(stroke(i)) }
            _ = m.clearAll()                               // 절대 번호 10이 clear
            for i in 0..<40 { m.commit(stroke(100 + i)) }  // 그 뒤 40획 → 되돌릴 수 있는 것은 마지막 30개
            check("전부 지우기가 되돌릴 수 없는 곳으로 밀리면 그 앞 목록이 버려짐", m.removed == 11 && m.items.count == 40 && m.floorAbs == 21,
                  "removed=\(m.removed) items=\(m.items.count) floorAbs=\(m.floorAbs)")
            check("버려진 앞부분은 slice가 건너뜀 (절대 번호 기준)", m.slice(from: 0, to: m.floorAbs).count == 10, "\(m.slice(from: 0, to: m.floorAbs).count)개")
            let m2 = InkModel()
            for i in 0..<5 { m2.commit(stroke(i)) }
            _ = m2.clearAll()
            check("전부 지우기 직후에는 아직 되돌릴 수 있음 (목록 유지)", m2.items.count == 6 && m2.undo() && m2.items.count == 5)
        }

        // ---- 화면: 주 화면이 바뀌면 원점이 옮겨 가도 같은 화면의 잉크는 제자리 ----
        do {
            let laptop = ScreenSnap(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
            let proj = ScreenSnap(id: 2, frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080))
            let s0 = inkShift(old: [laptop], new: [laptop, proj])
            check("프로젝터를 더해도 맥북 화면의 잉크는 그대로 (옮김 0)", s0 == .zero, "\(s0)")
            let s1 = inkShift(old: [laptop, proj], new: [laptop])
            check("프로젝터를 빼도 잉크는 그대로", s1 == .zero, "\(s1)")
            let projMain = ScreenSnap(id: 2, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
            let laptopLeft = ScreenSnap(id: 1, frame: CGRect(x: -1440, y: 0, width: 1440, height: 900))
            let s2 = inkShift(old: [laptop, proj], new: [projMain, laptopLeft])
            check("주 화면이 프로젝터로 바뀌면 맥북 잉크를 (-1440, 0)만큼 옮겨 제자리에 둠", s2 == CGVector(dx: -1440, dy: 0), "\(s2)")
            let s3 = inkShift(old: [projMain, laptopLeft], new: [ScreenSnap(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))])
            check("주 화면이던 프로젝터가 빠지면 남은 맥북 화면 기준으로 (+1440, 0) 옮김", s3 == CGVector(dx: 1440, dy: 0), "\(s3)")
            check("같은 화면이 하나도 없으면 옮기지 않음", inkShift(old: [laptop], new: [projMain]) == .zero)
            var item = stroke(0)
            let m = InkModel(); m.commit(item)
            m.translate(dx: -1440, dy: 5)
            item = m.items[0]
            check("잉크 좌표 옮김", item.points[0] == CGPoint(x: -1440, y: 15), "\(item.points[0])")
        }
    }
}
