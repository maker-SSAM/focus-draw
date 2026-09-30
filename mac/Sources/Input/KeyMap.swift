import Carbon

// ================= 드로잉 중에 잡는 키 표 =================
// 두 묶음이 여기서 나온다 (설계도 4절). 화면도 AppKit도 쓰지 않아 자체 점검이 그대로 검사한다.
//   draw  = 드로잉 키: 눌리면 무언가 한다
//   block = 막기 키: 글자·숫자·기호·스페이스·return·tab·화살표·PageUp/Down·Home/End·키패드·F1~F12 × {없음, ⇧, ⌥, ⌥⇧} − draw − app.
//           눌려도 아무 일도 하지 않는다 (슬라이드가 넘어가거나 글자가 쳐지지 않게). ⌘·⌃ 조합은 넣지 않는다
//           — 캡처(⌘⇧3/4/5)·Spotlight(⌘Space)·데스크톱 전환(⌃←→)을 지킨다.
// 글자가 아니라 키 자리(keyCode)로만 본다 — 한글 입력 상태에서도 같다.
enum KeyMap {
    struct DrawKey: Equatable {
        var combo: HotkeyNotation.Combo
        var release = false   // 뗄 때도 알려 준다 (Z X C: 누르고 있는 동안 도형)
        var repeats = false   // 누르고 있으면 되풀이한다 (= + − 굵기)
    }

    static let escCode = 53
    static let digits: [Int] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 83, 84, 85, 86, 87, 88, 89, 91, 92, 82]
    static let letters: [Int] = [12, 13, 14, 15, 0, 1]   // Q W E R A S
    static let edits: [Int] = [51, 117, escCode]         // delete, 앞으로 지우기, Esc

    // 드로잉 묶음: 지금 47개
    static let drawKeys: [DrawKey] = {
        var k: [DrawKey] = []
        func add(_ code: Int, _ mods: Int = 0, release: Bool = false, repeats: Bool = false) {
            k.append(DrawKey(combo: .init(code: code, mods: mods), release: release, repeats: repeats))
        }
        for c in digits + letters + edits { add(c) }
        for c in [6, 7, 8] { add(c, release: true); add(c, shiftKey, release: true) }         // Z X C (⇧와 함께 눌러도)
        for m in [0, shiftKey, optionKey, optionKey | shiftKey] { add(24, m, repeats: true) } // = +  (⌥: 지우개)
        for c in [27, 69, 78] { add(c, repeats: true); add(c, optionKey, repeats: true) }     // - 키패드+ 키패드-
        add(6, cmdKey); add(6, controlKey)                                                    // ⌘Z ⌃Z (실행 취소)
        return k
    }()

    // 막을 수 있는 키 자리(⌘·⌃ 없이 쓰는 것들)
    static let blockableCodes: [Int] = {
        var c: [Int] = []
        c += [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 31, 32, 34, 35, 37, 38, 40, 45, 46] // 글자 26
        c += [18, 19, 20, 21, 22, 23, 25, 26, 28, 29]                                                        // 숫자
        c += [24, 27, 30, 33, 39, 41, 42, 43, 44, 47, 50, 10]                                                // = - ] [ ' ; \ , / . ` §
        c += [49, 36, 48, 51, 53, 117, 114]                                                                  // space return tab delete esc 앞으로지우기 help
        c += [123, 124, 125, 126, 116, 121, 115, 119]                                                        // 화살표 PageUp PageDown Home End
        c += [65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]                        // 키패드
        c += [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]                                        // F1~F12
        return c
    }()
    static let blockMods: [Int] = [0, shiftKey, optionKey, optionKey | shiftKey]

    // 막기 묶음: 막을 수 있는 키 × 수식키 − 드로잉 묶음 − 빼 달라고 한 조합(앱 묶음: F8·F9 등)
    static func blockKeys(excluding: Set<HotkeyNotation.Combo> = []) -> [HotkeyNotation.Combo] {
        let draw = Set(drawKeys.map(\.combo))
        var out: [HotkeyNotation.Combo] = []
        for code in blockableCodes {
            for m in blockMods {
                let c = HotkeyNotation.Combo(code: code, mods: m)
                if !draw.contains(c), !excluding.contains(c) { out.append(c) }
            }
        }
        return out
    }
}
