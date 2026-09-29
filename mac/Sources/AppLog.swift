import Foundation

// 늘 켜져 있는 작은 기록: ~/Library/Logs/Focus & Draw/app.log (+ app.1.log). 각 256KB까지, 넘으면 한 번 밀어 둔다.
// 시작·종료, 설정 읽기/저장 실패, 메뉴 막대 아이콘이 빠진 일처럼 "나중에 무슨 일이 있었는지" 볼 만한 것만 적는다.
// (창·키·화면을 자세히 남기는 Diag와 다르다 — 그쪽은 메뉴에서 켰을 때만.) 입력한 글자·사용자 이름은 적지 않는다.
enum AppLog {
    static let maxBytes = 256 * 1024
    // nil이면 기록하지 않는다 (자체 점검·그림 점검은 사용자 기록을 건드리지 않는다)
    static var folder: URL? = Diag.folder
    static var url: URL? { folder?.appendingPathComponent("app.log") }
    private static var oldURL: URL? { folder?.appendingPathComponent("app.1.log") }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ tag: String, _ msg: String, now: Date = Date()) {
        guard let url, let old = oldURL, let folder else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let line = "\(stamp.string(from: now)) \(tag) \(msg.replacingOccurrences(of: "\n", with: " "))\n"
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size + line.utf8.count > maxBytes {
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        defer { try? h.close() }
        h.seekToEndOfFile()
        h.write(Data(line.utf8))
    }

    // 마지막 n줄 (옛 파일 뒤에 새 파일)
    static func tail(_ n: Int) -> [String] {
        var all: [String] = []
        for u in [oldURL, url] {
            guard let u, let text = try? String(contentsOf: u, encoding: .utf8) else { continue }
            all += text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        }
        return Array(all.suffix(n))
    }
}
