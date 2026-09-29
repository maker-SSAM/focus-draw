import AppKit
import Darwin

// "진단 정보 복사": 문제가 생겼을 때 메모나 메신저에 붙여 보낼 글을 만든다.
// 담는 것: 버전, macOS, 모델·칩, 아키텍처, 화면 크기, 기본값과 다른 설정, 설정 경로(~로 줄임), 마지막 기록 30줄.
// 담지 않는 것: 사용자 이름, 컴퓨터 이름, 화면(모니터) 이름, 입력한 글자.
enum DiagReport {
    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    static var architecture: String {
        #if arch(arm64)
        return "arm64 (애플 실리콘)"
        #else
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let rosetta = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
        return rosetta ? "x86_64 (Rosetta로 실행 중)" : "x86_64 (인텔)"
        #endif
    }

    // 이름·홈 폴더를 가린다. 홈 폴더는 ~로, 사용자·컴퓨터 이름이 어디에 끼어 있어도 <user>·<computer>로.
    static func sanitize(_ s: String, home: String = NSHomeDirectory(), user: String = NSUserName(),
                         fullName: String = NSFullUserName(), host: String? = Host.current().localizedName) -> String {
        var t = s
        if home.count > 1 { t = t.replacingOccurrences(of: home, with: "~") }
        for (name, label) in [(fullName, "<user>"), (user, "<user>"), (host ?? "", "<computer>")] where name.count >= 3 {
            t = t.replacingOccurrences(of: name, with: label, options: .caseInsensitive)
        }
        return t
    }

    static func nonDefaultSettings(_ s: Settings) -> [String] {
        let defaults = Dictionary(uniqueKeysWithValues: Settings().pairs().map { ("\($0.0).\($0.1)", $0.2) })
        return s.pairs().compactMap { p in
            let k = "\(p.0).\(p.1)"
            return defaults[k] == p.2 ? nil : "\(k)=\(p.2)"
        }
    }

    static func build(settings: Settings = .shared, screens: [NSScreen] = NSScreen.screens) -> String {
        var out: [String] = []
        #if EXPERIMENTS
        let kind = "개발용(실험 메뉴 포함)"
        #else
        let kind = "배포용"
        #endif
        out.append("Focus & Draw \(AppInfo.displayVersion) · \(kind)")
        out.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        out.append("모델: \(sysctlString("hw.model") ?? "?") · 칩: \(sysctlString("machdep.cpu.brand_string") ?? "?")")
        out.append("아키텍처: \(architecture)")
        let sc = screens.enumerated().map { i, s in
            "\(i + 1)) \(Int(s.frame.width))×\(Int(s.frame.height)) @\(Int(s.backingScaleFactor))x"
        }
        out.append("화면: \(sc.isEmpty ? "없음" : sc.joined(separator: ", "))")
        let diffs = nonDefaultSettings(settings)
        out.append("기본값과 다른 설정: \(diffs.isEmpty ? "없음" : diffs.joined(separator: ", "))")
        out.append("설정 파일: \((Settings.path.path as NSString).abbreviatingWithTildeInPath)")
        out.append("상세 진단 기록: \(Diag.isOn ? "켜짐" : "꺼짐")")
        out.append("--- 최근 기록 (app.log 마지막 30줄) ---")
        let tail = AppLog.tail(30)
        out += tail.isEmpty ? ["(기록 없음)"] : tail
        return sanitize(out.joined(separator: "\n"))
    }
}
