import Foundation

// 설정 파일(settings.ini)을 "고쳐 쓰는" 도구. Windows 판이 만든 파일(UTF-16, [Hotkeys]·HideCursor 같은 맥이 모르는 항목)을
// 맥에서 저장해도 하나도 잃지 않게 하려고, 줄을 통째로 들고 있다가 아는 값만 그 자리에서 바꾼다.
//  - 읽기: UTF-8 · BOM 있는 UTF-8 · UTF-16 LE/BE(BOM 있거나 없거나). 어느 것도 아니면 던진다(덮어쓰지 않기 위해).
//  - 쓰기: 읽은 인코딩·BOM·줄 끝(CRLF/LF)을 그대로. 새 파일은 BOM 없는 UTF-8, LF.
//  - 절·키 이름은 대소문자를 구분하지 않고, 앞뒤 공백은 무시한다. 같은 키가 여럿이면 첫째가 이긴다(Windows IniRead와 같음).
struct IniFile {
    enum Failure: Error, CustomStringConvertible {
        case undecodable(String)
        var description: String { if case .undecodable(let s) = self { return s } else { return "" } }
    }

    enum Format: Equatable {
        case utf8, utf16LE, utf16BE
    }

    private(set) var format = Format.utf8
    private(set) var hasBOM = false
    // 줄 하나 = 글 + 줄 끝. 마지막 줄에 줄 끝이 없으면 eol은 ""
    private var lines: [(text: String, eol: String)] = []

    init() {}

    init(data: Data) throws {
        var body = data
        let b = [UInt8](data.prefix(3))
        if b.starts(with: [0xEF, 0xBB, 0xBF]) {
            format = .utf8; hasBOM = true; body = data.dropFirst(3)
        } else if b.starts(with: [0xFF, 0xFE]) {
            format = .utf16LE; hasBOM = true; body = data.dropFirst(2)
        } else if b.starts(with: [0xFE, 0xFF]) {
            format = .utf16BE; hasBOM = true; body = data.dropFirst(2)
        } else if data.count >= 2, data.contains(0) {
            // BOM 없는 UTF-16: 영문 글자 뒤(또는 앞)의 0 바이트로 짐작한다
            if b[1] == 0 && b[0] != 0 { format = .utf16LE } else if b[0] == 0 && b[1] != 0 { format = .utf16BE }
            else { throw Failure.undecodable("글자 코드를 알 수 없습니다") }
        }
        let text: String?
        switch format {
        case .utf8: text = String(data: body, encoding: .utf8)
        case .utf16LE: text = body.count % 2 == 0 ? String(data: body, encoding: .utf16LittleEndian) : nil
        case .utf16BE: text = body.count % 2 == 0 ? String(data: body, encoding: .utf16BigEndian) : nil
        }
        guard let text else { throw Failure.undecodable("글자로 읽을 수 없습니다 (\(format))") }
        guard !text.unicodeScalars.contains("\u{0}") else { throw Failure.undecodable("글자 사이에 빈 바이트가 있습니다") }
        var cur = ""
        for ch in text {
            if ch == "\r\n" || ch == "\n" || ch == "\r" {
                lines.append((cur, String(ch))); cur = ""
            } else {
                cur.append(ch)
            }
        }
        if !cur.isEmpty { lines.append((cur, "")) }
    }

    func serialized() -> Data {
        let text = lines.map { $0.text + $0.eol }.joined()
        switch format {
        case .utf8:
            return (hasBOM ? Data([0xEF, 0xBB, 0xBF]) : Data()) + Data(text.utf8)
        case .utf16LE:
            return (hasBOM ? Data([0xFF, 0xFE]) : Data()) + (text.data(using: .utf16LittleEndian) ?? Data())
        case .utf16BE:
            return (hasBOM ? Data([0xFE, 0xFF]) : Data()) + (text.data(using: .utf16BigEndian) ?? Data())
        }
    }

    // ---------- 줄 해석 ----------
    private enum Kind { case section(String), entry(key: String, eq: String.Index), other }

    private static func kind(_ text: String) -> Kind {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("[") && t.hasSuffix("]") && t.count >= 2 {
            return .section(String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces))
        }
        if t.hasPrefix(";") || t.hasPrefix("#") { return .other }
        if let eq = text.firstIndex(of: "=") {
            let key = text[..<eq].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { return .entry(key: key, eq: eq) }
        }
        return .other
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    // 값 찾기: (줄 번호, 값). 절 이름이 같은 곳이 여럿이면 앞에서부터 본다
    private func find(_ section: String, _ key: String) -> (index: Int, value: String, eq: String.Index)? {
        var current = ""
        for (i, l) in lines.enumerated() {
            switch IniFile.kind(l.text) {
            case .section(let s): current = s
            case .entry(let k, let eq):
                if IniFile.same(current, section) && IniFile.same(k, key) {
                    let v = l.text[l.text.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                    return (i, v, eq)
                }
            case .other: break
            }
        }
        return nil
    }

    func value(_ section: String, _ key: String) -> String? { find(section, key)?.value }

    // 모든 항목 (절, 키, 값) — 점검과 진단용
    var entries: [(section: String, key: String, value: String)] {
        var current = ""
        var out: [(String, String, String)] = []
        for l in lines {
            switch IniFile.kind(l.text) {
            case .section(let s): current = s
            case .entry(let k, let eq):
                out.append((current, k, l.text[l.text.index(after: eq)...].trimmingCharacters(in: .whitespaces)))
            case .other: break
            }
        }
        return out
    }

    // ---------- 고치기 ----------
    private var newEOL: String {
        lines.last(where: { !$0.eol.isEmpty })?.eol ?? "\n"
    }

    // 값을 바꾼다. 이미 같은 값(대소문자 무시)이면 줄을 건드리지 않는다.
    // 키가 없으면 그 절의 마지막 항목 뒤에, 절이 없으면 파일 끝에 덧붙인다.
    mutating func set(_ section: String, _ key: String, _ value: String) {
        if let f = find(section, key) {
            guard !IniFile.same(f.value, value) else { return }
            let text = lines[f.index].text
            let afterEq = text[text.index(after: f.eq)...]
            let gap = afterEq.prefix(while: { $0 == " " || $0 == "\t" })
            lines[f.index].text = String(text[...f.eq]) + gap + value
            return
        }
        let eol = newEOL
        // 마지막 줄에 줄 끝이 없으면 먼저 붙여 둔다
        if let last = lines.indices.last, lines[last].eol.isEmpty { lines[last].eol = eol }
        var current = ""
        var insertAfter: Int? = nil // 그 절의 마지막 항목(없으면 머리글) 줄
        for (i, l) in lines.enumerated() {
            switch IniFile.kind(l.text) {
            case .section(let s):
                current = s
                if IniFile.same(s, section) && insertAfter == nil { insertAfter = i }
            case .entry:
                if IniFile.same(current, section) { insertAfter = i }
            case .other: break
            }
        }
        let entry = "\(key)=\(value)"
        if let at = insertAfter {
            lines.insert((entry, eol), at: at + 1)
        } else {
            lines.append(("[\(section)]", eol))
            lines.append((entry, eol))
        }
    }
}
