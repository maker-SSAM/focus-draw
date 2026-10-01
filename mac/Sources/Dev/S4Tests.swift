import AppKit
import Carbon

// S4의 글 점검: 막기 키 표·두 묶음의 등록과 해제·Esc 남기기·포인터 아래 창·시스템 커서 호출 수.
// 가짜 백엔드와 가짜 커서로 화면 없이 돈다(Golden.run). 창·알림이 필요한 것은 SelfTest.session이 따로 본다.
@MainActor enum S4Tests {
    static func run(_ report: (String, Bool, String) -> Void) {
        func check(_ name: String, _ ok: Bool, _ detail: String = "") { report(name, ok, detail) }
        let appCombos: [HotkeyNotation.Combo] = ["F8", "F9", "^!1", "^!2"].map { HotKeyTests.combo($0) }

        // ---- 키 표 ----
        let draw = KeyMap.drawKeys.map(\.combo)
        let block = KeyMap.blockKeys(excluding: Set(appCombos))
        check("키 표: 드로잉 키 47개, 서로 겹치지 않음", draw.count == 47 && Set(draw).count == 47, "\(draw.count)개")
        check("키 표: 막기 키에 ⌘·⌃ 조합이 없음 (캡처·Spotlight·데스크톱 전환을 지킴)",
              !block.contains { $0.mods & (cmdKey | controlKey) != 0 })
        check("키 표: 막기 키와 드로잉 키·앱 키가 겹치지 않고, 막기 키끼리도 겹치지 않음",
              Set(block).count == block.count && Set(block).isDisjoint(with: Set(draw)) && Set(block).isDisjoint(with: Set(appCombos)),
              "막기 \(block.count)개")
        func has(_ code: Int, _ mods: Int = 0) -> Bool { block.contains(.init(code: code, mods: mods)) }
        check("키 표: 화살표·스페이스·return·tab·PageUp/Down·F키·키패드·글자가 × {없음,⇧,⌥,⌥⇧}로 막힘",
              [123, 124, 125, 126, 49, 36, 48, 116, 121, 115, 119, 122, 111, 76, 65, 2, 5, 38, 40].allSatisfy { c in
                  KeyMap.blockMods.allSatisfy { has(c, $0) } },
              "")
        check("키 표: 드로잉 키(1·Q·A·Z·=·delete·Esc)는 막기에 없고, 다른 앱 조합도 뺌",
              !has(18) && !has(12) && !has(0) && !has(6) && !has(24) && !has(51) && !has(53) && !has(100) /* F8 */ && !has(101) /* F9 */,
              "")
        check("키 표: ⌘Z·⌃Z는 실행 취소(드로잉 키), 그 밖의 ⌘·⌃ 조합은 그대로 지나감",
              draw.contains(.init(code: 6, mods: cmdKey)) && draw.contains(.init(code: 6, mods: controlKey))
              && !block.contains(.init(code: 6, mods: cmdKey)) && !block.contains(.init(code: 8, mods: cmdKey)))

        // ---- 두 묶음의 등록·해제 ----
        do {
            let fake = HotKeyTests.FakeBackend(), reg = HotKeyRegistry(backend: fake)
            reg.registerGroup(.app, appCombos.map { HotKeyEntry(name: "app", combo: $0) }, policy: .skipFailures)
            let keys = DrawKeys(registry: reg)
            var drawing = true
            keys.isDrawing = { drawing }
            keys.blockExcluding = { Set(appCombos) }
            let r = keys.registerAll()
            check("드로잉 켜기: 드로잉 묶음과 막기 묶음이 모두 등록됨 (실패 0)",
                  r.ok && reg.count(.draw) == draw.count && reg.count(.block) == block.count && fake.live.count == reg.count,
                  "draw=\(reg.count(.draw)) block=\(reg.count(.block)) 백엔드=\(fake.live.count)")

            if let id = reg.ids(.block).first {
                reg.simulate(id, pressed: true)
                check("막기 키를 드로잉 중에 누르면 아무 일도 없음 (등록 그대로)", reg.count(.block) == block.count && reg.count(.draw) == draw.count)
                drawing = false
                reg.simulate(id, pressed: true)
                check("끈 뒤에 막기 키가 들어오면(STRAY) 두 묶음이 모두 풀림", reg.count(.block) == 0 && reg.count(.draw) == 0 && reg.count(.app) == 4
                      && fake.live.count == 4, "draw=\(reg.count(.draw)) block=\(reg.count(.block))")
            }
            drawing = true
            keys.registerAll()
            drawing = false
            let off = keys.unregisterAll()
            check("드로잉 끄기: 두 묶음을 모두 풀고 남은 등록 0, 앱 묶음은 그대로",
                  off.removed == draw.count + block.count && off.errors == 0 && keys.left == 0 && reg.count == 4 && fake.live.count == 4,
                  "푼=\(off.removed) 남음=\(keys.left)")
            var same = true, clean = true
            for _ in 0..<30 {
                drawing = true; keys.registerAll(); drawing = false; keys.unregisterAll()
                if keys.left != 0 || reg.count != 4 { clean = false }
                if reg.count(.draw) != 0 { same = false }
            }
            check("드로잉을 30번 켜고 꺼도 등록이 하나도 남지 않음", clean && same && fake.live.count == 4, "백엔드=\(fake.live.count)")

            // Esc로 끌 때: Esc 하나만 뗄 때까지 남긴다 (누르고 있는 Esc의 반복이 쇼로 새지 않게)
            drawing = true; keys.registerAll(); drawing = false
            keys.unregisterAll(lingerEsc: true)
            let escID = keys.escLingerID
            check("Esc로 끄면 Esc 하나만 잠깐 남고 나머지는 모두 풀림 (남은 등록 0으로 셈)",
                  escID != nil && reg.count(.draw) == 1 && reg.count(.block) == 0 && keys.left == 0, "draw=\(reg.count(.draw))")
            if let e = escID {
                reg.simulate(e, pressed: true)
                check("남겨 둔 Esc의 반복 누름은 삼키고 STRAY로 세지 않음", reg.count(.draw) == 1 && keys.escLingerID == e)
                reg.simulate(e, pressed: false)
                check("Esc를 떼면 남은 Esc도 풀려 두 번째 Esc는 그대로 쇼로 감", reg.count == 4 && keys.escLingerID == nil && fake.live.count == 4,
                      "전체=\(reg.count)")
            }
            drawing = true; keys.registerAll(); drawing = false
            keys.unregisterAll(lingerEsc: true)
            drawing = true
            let again = keys.registerAll()
            check("Esc를 남겨 둔 채 바로 다시 켜도 등록이 성공함", again.ok && reg.count(.draw) == draw.count && keys.escLingerID == nil)
            drawing = false; keys.unregisterAll()
            check("Esc를 안 남기고 끄면(F9·위젯) 모두 풀림", keys.left == 0 && reg.count == 4)
        }

        // ---- 실패 처리 ----
        do {
            let fake = HotKeyTests.FakeBackend(), reg = HotKeyRegistry(backend: fake)
            let keys = DrawKeys(registry: reg)
            keys.isDrawing = { true }
            fake.failing[.init(code: 18, mods: 0)] = -9878   // 1 키를 다른 앱이 쓴다
            let r = keys.registerAll()
            check("드로잉 키 하나가 -9878이면 드로잉 묶음 전체를 되돌리고 막기 묶음은 등록하지 않음",
                  !r.ok && reg.count == 0 && fake.live.isEmpty, "남음=\(reg.count)")
            fake.failing = [.init(code: 49, mods: 0): -9878, .init(code: 49, mods: optionKey): -9878]  // 스페이스는 다른 앱이 씀
            let r2 = keys.registerAll()
            let blocks = KeyMap.blockKeys().count
            check("막기 키 일부가 실패해도(다른 앱 사용) 드로잉은 켜지고 나머지 막기 키는 등록됨",
                  r2.ok && reg.count(.block) == blocks - 2 && reg.count(.draw) == draw.count, "막기 \(reg.count(.block))/\(blocks)")
            keys.unregisterAll()
        }

        // ---- 포인터 아래 창 ----
        do {
            let boardL = OVERLAY_LEVEL.rawValue, widgetL = WIDGET_LEVEL.rawValue
            func w(_ n: Int, _ layer: Int, _ f: CGRect, ours: Bool = false, alpha: Double = 1) -> WindowInfo {
                WindowInfo(number: n, layer: layer, alpha: alpha, ownedByUs: ours, frame: f)
            }
            let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
            let widget = w(3, widgetL, CGRect(x: 800, y: 600, width: 150, height: 40), ours: true)
            let spot = w(4, boardL + 2, CGRect(x: 400, y: 300, width: 100, height: 100), ours: true)
            let board = w(1, boardL, screen, ours: true)
            let capture = w(9, 2_147_483_000, CGRect(x: 100, y: 100, width: 300, height: 200))
            let list = [spot, widget, capture, board]
            func at(_ x: CGFloat, _ y: CGFloat) -> PointerTarget {
                pointerTarget(at: CGPoint(x: x, y: y), windows: list, boards: [1], boardLayer: boardL, widgetLayer: widgetL)
            }
            check("포인터 아래: 판 위는 board, 위젯 위는 widget, 캡처 화면 위는 other",
                  at(50, 50) == .board && at(850, 620) == .widget && at(200, 150) == .other, "")
            check("포인터 아래: 클릭이 통과하는 강조 원은 무시하고 판으로 봄", at(450, 350) == .board)
            check("포인터 아래: 투명한 남의 창은 무시", pointerTarget(at: CGPoint(x: 50, y: 50), windows: [w(8, boardL + 5, screen, alpha: 0), board],
                                                          boards: [1], boardLayer: boardL, widgetLayer: widgetL) == .board)
        }

        // ---- 네 손가락 제스처 ----
        do {
            let scr = CGRect(x: 0, y: 0, width: 1512, height: 982)
            check("제스처: 판이 화면 자리에 있으면 아님, 밀려났으면(데스크톱 넘기는 중) 감지",
                  !boardMovedAway(boardFrames: [scr], screenFrames: [scr]) && boardMovedAway(boardFrames: [scr.offsetBy(dx: -1575, dy: 0)], screenFrames: [scr]))
            let L = OVERLAY_LEVEL.rawValue
            func dock(_ layer: Int, ours: Bool = false, owner: String = "Dock") -> WindowInfo {
                WindowInfo(number: 5, layer: layer, alpha: 1, ownedByUs: ours, frame: scr, owner: owner)
            }
            let small = WindowInfo(number: 6, layer: 20, alpha: 1, ownedByUs: false, frame: CGRect(x: 500, y: 900, width: 400, height: 80), owner: "Dock")
            let band = [scr]
            check("Dock 띠: 아래·왼쪽·오른쪽 가장자리 160pt 안이면 가까움, 화면 가운데·위쪽은 아님",
                  pointerNearDockEdge(CGPoint(x: scr.midX, y: scr.minY + 5), screens: band) && pointerNearDockEdge(CGPoint(x: scr.minX + 20, y: scr.midY), screens: band)
                  && pointerNearDockEdge(CGPoint(x: scr.maxX - 20, y: scr.midY), screens: band)
                  && !pointerNearDockEdge(CGPoint(x: scr.midX, y: scr.midY), screens: band) && !pointerNearDockEdge(CGPoint(x: scr.midX, y: scr.maxY - 5), screens: band))
            check("제스처: Dock의 높은 창(1000·1001)이나 화면만 한 창(레벨 18·20)이 뜨면 Mission Control, 평소 Dock 창이나 다른 앱은 아님",
                  missionControlShowing([dock(L + 1), dock(L)], boardLayer: L) && missionControlShowing([dock(20), dock(18)], boardLayer: L)
                  && !missionControlShowing([dock(20)], boardLayer: L) // Dock이 나올 때의 창 하나는 제스처가 아님 (가장자리 판단과 무관하게)
                  && !missionControlShowing([dock(-2147483624), small], boardLayer: L)
                  && !missionControlShowing([dock(L + 1), dock(L + 2)], boardLayer: L, nearDockEdge: true)
                  && !missionControlShowing([dock(20)], boardLayer: L, nearDockEdge: true)   // Dock이 자동 숨김에서 나올 때: 레벨 20 하나
                  && missionControlShowing([dock(20), dock(18)], boardLayer: L, nearDockEdge: true) && missionControlShowing([dock(20), dock(20)], boardLayer: L, nearDockEdge: true)
                  && !missionControlShowing([dock(L + 1, owner: "Keynote")], boardLayer: L))
        }

        // ---- 시스템 커서 호출 수 ----
        do {
            var depth = 0, hides = 0, shows = 0
            let saved = (SystemCursor.systemVisible, SystemCursor.hideAction, SystemCursor.showAction, SystemCursor.testMode)
            SystemCursor.testMode = true
            SystemCursor.systemVisible = { depth == 0 }
            SystemCursor.hideAction = { depth += 1; hides += 1 }
            SystemCursor.showAction = { depth = max(0, depth - 1); shows += 1 }
            SystemCursor.showAll()
            SystemCursor.hide(.board)
            check("커서: 숨기면 숨겨지고 Hide를 한 번 부름", SystemCursor.hidden && depth == 1 && hides == 1)
            depth = 0 // 앞 앱·데스크톱이 바뀌어 시스템이 커서를 다시 보이게 함
            let t0 = Date()
            SystemCursor.reassert(now: t0.addingTimeInterval(1))
            check("커서: 시스템이 다시 보이게 하면 다시 숨김", depth == 1 && SystemCursor.rehides >= 1 && SystemCursor.hidden)
            depth = 0
            SystemCursor.reassert(now: t0.addingTimeInterval(1.1))
            check("커서: 다시 숨기기는 0.25초에 한 번까지", depth == 0)
            SystemCursor.reassert(now: t0.addingTimeInterval(1.5))
            SystemCursor.show(.board)
            check("커서: 보이게 하면 Hide 호출 수만큼 Show를 부르고 실제로 보임", !SystemCursor.hidden && depth == 0 && SystemCursor.balanced && shows >= hides - 1,
                  "hide=\(hides) show=\(shows)")
            SystemCursor.hide(.board)
            depth = 3 // 시스템이 셈을 어긋나게 해 두어도 끝에 실제로 보일 때까지 되돌림
            SystemCursor.show(.board)
            check("커서: 셈이 어긋나도 끝에 보일 때까지 되돌림", depth == 0 && SystemCursor.balanced)
            SystemCursor.hide(.board); SystemCursor.hide(.spot); SystemCursor.show(.board)
            check("커서: 이유가 하나라도 남아 있으면 숨긴 채로 (드로잉 이유·강조 이유)", SystemCursor.hidden && depth == 1)
            SystemCursor.showAll()
            check("커서: showAll로 모두 돌아옴", !SystemCursor.hidden && depth == 0)
            (SystemCursor.systemVisible, SystemCursor.hideAction, SystemCursor.showAction, SystemCursor.testMode) = saved
        }
    }
}
