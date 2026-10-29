import Foundation

// 새 버전 확인의 글 점검 (docs/update-check.md). 실제 인터넷 접속은 하지 않는다. Golden.run이 부른다.
enum UpdateCheckTests {
    static func run(_ report: (String, Bool, String) -> Void) {
        func check(_ name: String, _ ok: Bool, _ detail: String = "") { report(name, ok, detail) }
        typealias U = UpdateCheck

        check("새 버전 비교: 숫자 단위 (2.10.0 > 2.9.0, 2.0 = 2.0.0, 1.0.0 < 2.0.0)",
              U.isNewer("2.10.0", than: "2.9.0") && !U.isNewer("2.0", than: "2.0.0") && !U.isNewer("2.0.0", than: "2.0")
              && U.isNewer("2.0.0", than: "1.0.0") && !U.isNewer("1.0.0", than: "2.0.0") && U.isNewer("2.0.0", than: "0.5.0"))
        check("새 버전 비교: 숫자가 아니면 새 버전으로 보지 않음", !U.isNewer("2.x", than: "1.0.0") && !U.isNewer("", than: "1.0.0"))

        let file = """
        ; Focus & Draw 최신 버전
        windows=2.1.0
        windows_url=https://github.com/maker-SSAM/focus-draw/releases/tag/v2.1.0
         mac = 2.1.0 \r
        mac_url=https://github.com/maker-SSAM/focus-draw/releases/tag/v2.1.0
        모르는줄=무시
        """
        let p = U.parse(file)
        check("version.txt 읽기: mac 줄·주소 (공백·CRLF·주석·모르는 줄 무시)",
              p?.version == "2.1.0" && p?.url?.absoluteString == "https://github.com/maker-SSAM/focus-draw/releases/tag/v2.1.0", "\(String(describing: p))")
        check("version.txt 읽기: 다른 곳 주소는 쓰지 않음",
              U.parse("mac=2.1.0\nmac_url=https://example.com/x")?.url == nil && U.parse("mac=2.1.0")?.url == nil)
        check("version.txt 읽기: mac 줄이 없거나 이상하면 실패",
              U.parse("windows=2.0.0") == nil && U.parse("mac=abc") == nil && U.parse("<html>404</html>") == nil)

        check("결과: 새 버전이면 그 번호와 받는 곳", U.evaluate(file, current: "2.0.0")
              == .newer("2.1.0", URL(string: "https://github.com/maker-SSAM/focus-draw/releases/tag/v2.1.0")!))
        check("결과: 같거나 지금이 높으면(개발판) 최신", U.evaluate(file, current: "2.1.0") == .latest("2.1.0")
              && U.evaluate(file, current: "3.0.0") == .latest("2.1.0"))
        check("결과: 주소가 없으면 GitHub 최신 릴리스", U.evaluate("mac=9.0.0", current: "2.0.0") == .newer("9.0.0", U.releasesURL))
        check("결과: 파일을 못 받으면 실패", U.evaluate(nil, current: "2.0.0") == .failed)
    }
}
