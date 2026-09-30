import Carbon

// 단축키 등록부의 글 점검. 가짜 백엔드로 실패 상황(-9868·-9878)까지 흉내 내므로 화면 없이 돈다(Golden.run).
// 진짜 Carbon 등록은 창이 있는 --selftest에서 따로 본다(realBackend).
enum HotKeyTests {
    final class FakeBackend: HotKeyBackend {
        var onEvent: (UInt32, Bool) -> Void = { _, _ in }
        var failing: [HotkeyNotation.Combo: OSStatus] = [:]   // 이 조합은 이 오류로 거절
        var live: [UInt32: HotkeyNotation.Combo] = [:]
        func register(_ combo: HotkeyNotation.Combo, id: UInt32) -> (token: Any?, status: OSStatus) {
            if let st = failing[combo] { return (nil, st) }
            live[id] = combo
            return (id, noErr)
        }
        func unregister(_ token: Any?) -> OSStatus {
            if let id = token as? UInt32 { live[id] = nil }
            return noErr
        }
    }

    static func combo(_ text: String) -> HotkeyNotation.Combo { HotkeyNotation.parse(text)! }
    static func entries(_ names: [String], press: @escaping (UInt32) -> Void = { _ in }, release: ((UInt32) -> Void)? = nil) -> [HotKeyEntry] {
        names.map { HotKeyEntry(name: $0, combo: combo($0), press: press, release: release) }
    }

    static func run(_ report: (String, Bool, String) -> Void) {
        func check(_ name: String, _ ok: Bool, _ detail: String = "") { report(name, ok, detail) }

        // 등록·해제 반복: 묶음을 풀면 하나도 남지 않고, 아이디는 늘 같은 번호로 다시 나온다
        do {
            let fake = FakeBackend(), reg = HotKeyRegistry(backend: fake)
            reg.registerGroup(.app, entries(["F8", "F9", "^!1", "^!2"]), policy: .skipFailures)
            let drawNames = ["^!3", "^!4", "^!q", "^!w", "^z", "+F1", "^!a"]
            var firstIDs: [UInt32] = [], allClean = true, sameIDs = true
            for round in 0..<50 {
                let r = reg.registerGroup(.draw, entries(drawNames), policy: .allOrNothing)
                if round == 0 { firstIDs = r.registered } else if r.registered != firstIDs { sameIDs = false }
                reg.unregisterGroup(.draw)
                if reg.count(.draw) != 0 || reg.count != 4 || fake.live.count != 4 { allClean = false }
            }
            check("등록부: 드로잉 묶음을 50번 켜고 꺼도 하나도 남지 않고 app 묶음은 그대로", allClean, "count=\(reg.count) 백엔드=\(fake.live.count)")
            check("등록부: 아이디는 묶음마다 정해진 범위에서, 껐다 켜도 같은 번호", sameIDs && firstIDs.first == HotKeyGroup.draw.firstID
                  && reg.ids(.app) == [1, 2, 3, 4], "\(firstIDs.prefix(3)) app=\(reg.ids(.app))")
            reg.unregisterAll()
            check("등록부: 종료할 때 모든 묶음을 풂", reg.count == 0 && fake.live.isEmpty)
        }

        // 같은 조합 두 번: 호출한 쪽이 오류를 받는다
        do {
            let fake = FakeBackend(), reg = HotKeyRegistry(backend: fake)
            let a = reg.register(.app, HotKeyEntry(name: "F9", combo: combo("F9")))
            let b = reg.register(.draw, HotKeyEntry(name: "F9(draw)", combo: combo("F9")))
            check("등록부: 같은 조합을 두 번 등록하면 두 번째가 -9878을 받고 하나만 남음", a.status == noErr && b.status == hotKeyExistsStatus && reg.count == 1
                  && fake.live.count == 1, "\(a.status) \(b.status)")
            let again = reg.register(.draw, HotKeyEntry(name: "x", combo: combo("^!1")))
            check("등록부: 실패한 등록이 아이디를 낭비하지 않음", again.id == HotKeyGroup.draw.firstID, "\(again.id)")
        }

        // 묶음 되돌리기: draw는 하나라도 실패하면 모두 되돌림, block은 실패한 조합만 뺌
        do {
            let fake = FakeBackend(), reg = HotKeyRegistry(backend: fake)
            reg.registerGroup(.app, entries(["F8", "F9"]), policy: .skipFailures)
            fake.failing[combo("^!4")] = -9878                       // 다른 앱이 이미 쓰는 조합
            let r = reg.registerGroup(.draw, entries(["^!1", "^!2", "^!3", "^!4", "^!5"]), policy: .allOrNothing)
            check("등록부: 드로잉 묶음 중 하나가 -9878이면 묶음 전체를 되돌리고 실패를 돌려줌",
                  !r.ok && r.failed.first?.name == "^!4" && r.failed.first?.status == -9878 && r.registered.isEmpty
                  && reg.count(.draw) == 0 && fake.live.count == 2 && reg.count(.app) == 2,
                  "실패=\(r.failed.map { "\($0.name) \($0.status)" }) 남음=\(reg.count(.draw)) 백엔드=\(fake.live.count)")
            fake.failing = [combo("^!2"): hotKeyRejectedStatus]
            let r2 = reg.registerGroup(.draw, entries(["^!1", "^!2"]), policy: .allOrNothing)
            check("등록부: 시스템이 거절(-9868)해도 같은 방식으로 되돌리고 오류 번호를 돌려줌",
                  r2.failed.first?.status == -9868 && reg.count(.draw) == 0 && describeHotKeyStatus(-9868).contains("거절")
                  && describeHotKeyStatus(-9878).contains("다른 앱"))
            fake.failing = [combo("^!2"): -9878]
            let b = reg.registerGroup(.block, entries(["^!1", "^!2", "^!3"]), policy: .skipFailures)
            check("등록부: 막기 묶음은 실패한 조합만 빼고 나머지를 등록", b.registered.count == 2 && b.failed.count == 1 && reg.count(.block) == 2,
                  "등록 \(b.registered.count) 실패 \(b.failed.count)")
            let dup = reg.registerGroup(.block, entries(["F9"]), policy: .skipFailures)
            check("등록부: 이미 있는 조합은 다른 묶음에도 등록하지 않음", dup.registered.isEmpty && dup.failed.first?.status == hotKeyExistsStatus)
            reg.unregisterGroup(.block)
            check("등록부: 끈 뒤 드로잉·막기 묶음이 남지 않음", reg.count(.draw) == 0 && reg.count(.block) == 0 && reg.count(.app) == 2)
        }

        // 누름·뗌 콜백
        do {
            let fake = FakeBackend(), reg = HotKeyRegistry(backend: fake)
            var log: [String] = []
            let r = reg.registerGroup(.draw, entries(["^!1"], press: { log.append("down\($0)") }, release: { log.append("up\($0)") }), policy: .allOrNothing)
            fake.onEvent(r.registered[0], true); fake.onEvent(r.registered[0], false)
            reg.unregisterGroup(.draw)
            fake.onEvent(r.registered[0], true) // 풀린 뒤의 누름은 무시
            check("등록부: 누름과 뗌 콜백이 아이디와 함께 옴, 풀린 뒤에는 오지 않음", log == ["down100", "up100"], "\(log)")
        }
    }

    // 진짜 Carbon: 창이 있는 --selftest에서. 다른 앱이 쓰지 않을 만한 조합(⌃⌥⇧⌘ + F19)을 쓴다.
    static func realBackend(_ report: (String, Bool, String) -> Void) {
        let reg = HotKeyRegistry()
        let c = HotkeyNotation.Combo(code: kVK_F19, mods: controlKey | optionKey | shiftKey | cmdKey)
        let a = reg.register(.app, HotKeyEntry(name: "real-1", combo: c))
        let b = reg.register(.draw, HotKeyEntry(name: "real-2", combo: c))
        report("진짜 단축키: 같은 조합을 두 번 등록하면 두 번째가 -9878", a.status == noErr && b.status == hotKeyExistsStatus, "\(a.status) \(b.status)")
        var clean = true
        for _ in 0..<20 {
            let r = reg.registerGroup(.draw, [HotKeyEntry(name: "a", combo: .init(code: kVK_F18, mods: controlKey | optionKey | shiftKey | cmdKey)),
                                              HotKeyEntry(name: "b", combo: .init(code: kVK_F17, mods: controlKey | optionKey | shiftKey | cmdKey))], policy: .allOrNothing)
            if !r.ok || reg.count(.draw) != 2 { clean = false }
            reg.unregisterGroup(.draw)
            if reg.count(.draw) != 0 { clean = false }
        }
        reg.unregisterAll()
        // 풀린 조합은 다시 등록할 수 있어야 한다 (진짜로 풀렸다는 뜻)
        let again = reg.register(.app, HotKeyEntry(name: "real-3", combo: c))
        reg.unregisterAll()
        report("진짜 단축키: 20번 등록·해제해도 깨끗하고, 푼 조합을 다시 등록할 수 있음", clean && again.status == noErr && reg.count == 0, "clean=\(clean) again=\(again.status)")
    }
}
