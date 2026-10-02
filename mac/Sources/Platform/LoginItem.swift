import AppKit
import ServiceManagement

// 로그인 시 자동 실행. SMAppService는 로그인 항목을 바꾸므로 다음 경우에는 부르지 않는다:
//   --selftest·--bench·--diag·--golden 실행(allowed = false), 응용 프로그램 폴더 밖에서 실행 중인 앱(개발 빌드 포함).
// 부른 횟수를 세어 두어 자체 점검이 "0번"인지 확인한다.
enum LoginItem {
    enum State: Equatable {
        case on
        case off
        case needsApproval   // 시스템 설정 › 일반 › 로그인 항목에서 허용해야 함
        case unavailable
    }

    static var allowed = true
    private(set) static var calls = 0

    static func isInstalledLocation(_ path: String = Bundle.main.bundlePath) -> Bool {
        path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    // 설정 창을 열 때마다 읽는다. 다른 곳(시스템 설정)에서 바뀌었을 수 있기 때문이다.
    static func state(path: String = Bundle.main.bundlePath) -> State {
        guard allowed, isInstalledLocation(path) else { return .off }
        calls += 1
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        case .notRegistered: return .off
        default: return .unavailable
        }
    }

    // 켜거나 끈다. 호출하는 쪽이 먼저 isInstalledLocation을 확인해 안내를 띄운다.
    static func set(_ on: Bool) -> (state: State, error: Error?) {
        guard allowed, isInstalledLocation() else { return (.off, nil) }
        calls += 1
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            AppLog.write("LOGINITEM", "\(on ? "register" : "unregister") failed: \(error)")
            return (state(), error)
        }
        let s = state()
        AppLog.write("LOGINITEM", "\(on ? "on" : "off") -> \(s)")
        return (s, nil)
    }

    static func openSystemSettings() {
        guard allowed else { return }
        SMAppService.openSystemSettingsLoginItems()
    }
}
