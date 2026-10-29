import AppKit

// 새 버전 확인 (docs/update-check.md). 저장소 맨 위 version.txt 하나를 읽어 지금 버전과 견준다.
// 설정 창을 열 때만 읽는다 — 앱을 켤 때·수업 중에는 접속하지 않고, 알림 창도 띄우지 않는다(선생님 결정 2026-10-29).
// 보내는 정보는 없다. 결과는 설정 창 "정보" 칸의 글자로만 보인다.
@MainActor final class UpdateCheck: ObservableObject {
    static let shared = UpdateCheck()
    nonisolated static let fileURL = URL(string: "https://raw.githubusercontent.com/maker-SSAM/focus-draw/master/version.txt")!
    nonisolated static let releasesURL = URL(string: "https://github.com/maker-SSAM/focus-draw/releases/latest")!
    nonisolated static let authorURL = URL(string: "https://maker-ssam.github.io/")!

    enum Status: Equatable {
        case idle                 // 아직 읽지 않음 (자체 점검 그림도 이 모양)
        case checking
        case latest(String)       // 최신 버전 번호
        case newer(String, URL)   // 새 버전 번호, 받는 곳
        case failed               // 인터넷이 없거나 학교망이 막음, 파일 모양이 이상함
    }

    @Published private(set) var status: Status = .idle
    private var task: URLSessionDataTask?

    // 받는 곳: 새 버전이면 version.txt가 가리키는 릴리스, 아니면 GitHub 최신 릴리스
    var downloadURL: URL {
        if case .newer(_, let u) = status { return u }
        return Self.releasesURL
    }

    func refresh() {
        guard status != .checking else { return }
        status = .checking
        let req = URLRequest(url: Self.fileURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        let current = AppInfo.version
        task = URLSession(configuration: .ephemeral).dataTask(with: req) { data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let text = ok ? data.flatMap { String(data: $0, encoding: .utf8) } : nil
            let result = Self.evaluate(text, current: current)
            Task { @MainActor in self.status = result }
        }
        task?.resume()
    }

    // ---- 글 점검으로 확인하는 부분 (인터넷 없이) ----

    // version.txt의 mac=·mac_url= 줄. `이름=값` 모양, 모르는 줄과 ; 주석은 무시
    nonisolated static func parse(_ text: String) -> (version: String, url: URL?)? {
        var values: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix(";"), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            values[key] = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        }
        guard let v = values["mac"], numbers(v) != nil else { return nil }
        // 받는 곳은 이 저장소의 GitHub 주소만 연다 (이상하면 최신 릴리스 쪽)
        let url = values["mac_url"].flatMap(URL.init(string:)).flatMap {
            $0.absoluteString.hasPrefix("https://github.com/maker-SSAM/focus-draw/") ? $0 : nil
        }
        return (v, url)
    }

    // "2.10.0" → [2, 10, 0]. 숫자가 아닌 조각이 있으면 nil
    nonisolated static func numbers(_ v: String) -> [Int]? {
        let parts = v.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        return parts.map { $0! }
    }

    // a가 b보다 새 버전인가 (숫자 단위: 2.10.0 > 2.9.0, 2.0 = 2.0.0)
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        guard let x = numbers(a), let y = numbers(b) else { return false }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    // 지금 버전이 더 높으면(개발판) "최신"으로 본다
    nonisolated static func evaluate(_ text: String?, current: String) -> Status {
        guard let text, let (v, url) = parse(text) else { return .failed }
        return isNewer(v, than: current) ? .newer(v, url ?? releasesURL) : .latest(v)
    }
}
