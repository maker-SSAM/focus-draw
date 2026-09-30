import Carbon

// 단축키 글자 표기. settings.ini의 [Hotkeys]는 Windows(AutoHotkey)와 같은 표기를 쓴다:
//   ^ = ⌃(Ctrl)  ! = ⌥(Alt)  + = ⇧(Shift)  # = ⌘(Win에 해당)  뒤에 키 이름: F9, 1, h, Space …
// 예: "F9", "^!1", "+F8", "#!h". 알아보지 못하는 표기(<, >, *, ~, $ 같은 AHK 옵션 포함)는 nil.
enum HotkeyNotation {
    struct Combo: Equatable, Hashable {
        var code: Int      // 키 자리 번호 (kVK_*)
        var mods: Int      // Carbon 수식키 (cmdKey | controlKey | optionKey | shiftKey)
    }

    // 키 이름 → 자리 번호. 글자가 아니라 키 자리를 쓰므로 한글 입력 상태와 상관없다.
    private static let names: [String: Int] = {
        var t: [String: Int] = [:]
        let letters: [(String, Int)] = [("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8), ("v", 9),
                                        ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("o", 31), ("u", 32),
                                        ("i", 34), ("p", 35), ("l", 37), ("j", 38), ("k", 40), ("n", 45), ("m", 46)]
        for (n, c) in letters { t[n] = c }
        let digits: [(String, Int)] = [("1", 18), ("2", 19), ("3", 20), ("4", 21), ("5", 23), ("6", 22), ("7", 26), ("8", 28), ("9", 25), ("0", 29)]
        for (n, c) in digits { t[n] = c }
        let fkeys = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90] // F1~F20
        for (i, c) in fkeys.enumerated() { t["f\(i + 1)"] = c }
        for (n, c) in [("space", 49), ("tab", 48), ("enter", 36), ("esc", 53), ("escape", 53),
                       ("left", 123), ("right", 124), ("down", 125), ("up", 126)] { t[n] = c }
        return t
    }()

    // 자리 번호 → 쓰는 이름 ("escape"는 "esc"의 다른 이름일 뿐이다)
    private static let canonical: [Int: String] = {
        var t: [Int: String] = [:]
        for (n, c) in names where n != "escape" { t[c] = n }
        return t
    }()

    // ⌘⌃⌥⇧ 표기 순서: # ^ ! + (AHK 관례). 왕복해도 같은 글자가 나오게 늘 이 순서로 쓴다.
    private static let prefixes: [(Character, Int)] = [("#", cmdKey), ("^", controlKey), ("!", optionKey), ("+", shiftKey)]

    static func parse(_ text: String) -> Combo? {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        var mods = 0
        while let c = rest.first, let p = prefixes.first(where: { $0.0 == c }) {
            guard mods & p.1 == 0 else { return nil } // 같은 수식키를 두 번 쓴 표기
            mods |= p.1
            rest = rest.dropFirst()
        }
        guard !rest.isEmpty, let code = names[rest.lowercased()] else { return nil }
        return Combo(code: code, mods: mods)
    }

    static func format(_ c: Combo) -> String? {
        guard let name = canonical[c.code] else { return nil }
        let pre = prefixes.filter { c.mods & $0.1 != 0 }.map { String($0.0) }.joined()
        let isF = name.hasPrefix("f") && Int(name.dropFirst()) != nil
        let shown = isF ? name.uppercased() : name.count > 1 ? name.prefix(1).uppercased() + name.dropFirst() : name
        return pre + shown
    }

    // 맥에서 받아들이는 조합인가: ⌃ 또는 ⌥가 있거나, F1~F20 단독(⇧만 허용). (Windows의 IsSafeHotkey와 같은 취지)
    static func isSafe(_ c: Combo) -> Bool {
        if c.mods & (controlKey | optionKey) != 0 { return true }
        let f: Set<Int> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        return f.contains(c.code) && c.mods & cmdKey == 0
    }
}
