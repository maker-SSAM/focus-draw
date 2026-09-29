import AppKit
import SwiftUI

// 안내 창: 화면을 막지 않는 작은 창(모달이 아님). 드로잉·단축키는 창이 떠 있어도 그대로 동작한다.
// 오류 안내는 원인 → 할 일 → 안심 문구 순서로 쓰고, 경로와 오류 글은 맨 아래 작은 글씨로 둔다.
struct NoticeContent {
    var title: String
    var body: [String]
    var detail: String? = nil
    var buttons: [(title: String, action: () -> Void)] = []
}

private struct NoticeView: View {
    let n: NoticeContent
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(n.title).font(.headline)
            ForEach(Array(n.body.enumerated()), id: \.offset) { _, p in
                Text(p).fixedSize(horizontal: false, vertical: true)
            }
            if let d = n.detail {
                Text(d).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                ForEach(Array(n.buttons.enumerated()), id: \.offset) { _, b in
                    Button(b.title) { b.action(); close() }
                }
                Button("확인", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

enum Notice {
    private static var open: [NSWindow] = []

    static func show(_ n: NoticeContent) {
        var win: NSWindow?
        let host = NSHostingView(rootView: NoticeView(n: n, close: { win?.close() }))
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win = w
        w.title = "Focus & Draw"
        w.isReleasedWhenClosed = false
        w.contentView = host
        w.setContentSize(host.fittingSize)
        w.center()
        if let last = open.last { w.setFrameOrigin(NSPoint(x: last.frame.minX + 24, y: last.frame.minY - 24)) }
        open.append(w)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            open.removeAll { $0 === w }
        }
        NSApp.activate(ignoringOtherApps: true) // 안내는 사용자가 방금 한 일(실행·저장·메뉴)의 답이므로 앞으로 나온다
        w.makeKeyAndOrderFront(nil)
    }

    static func tilde(_ url: URL) -> String { (url.path as NSString).abbreviatingWithTildeInPath }

    // ---------- 안내 문구 ----------
    static func saveFailed(_ e: Settings.SaveError) -> NoticeContent {
        let ns = e.underlying as NSError?
        var cause = "저장할 폴더나 파일에 쓸 수 없었습니다."
        switch ns?.code {
        case NSFileWriteOutOfSpaceError: cause = "저장 공간(디스크)이 부족해서 쓸 수 없었습니다."
        case NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError:
            cause = "이 폴더에 쓸 권한이 없거나 읽기 전용이라 쓸 수 없었습니다."
        default: break
        }
        if case .blocked = e {
            cause = "설정 파일이 읽을 수 없는 상태인데 복사본을 만들지 못해서, 원래 파일을 지키려고 저장하지 않았습니다."
        }
        var detail = "설정 파일: \(tilde(Settings.path))"
        if let ns { detail += "\n오류: \(ns.localizedDescription) (\(ns.domain) \(ns.code))" }
        return NoticeContent(
            title: "설정을 저장하지 못했습니다",
            body: [cause,
                   "저장 공간을 확인한 뒤 [저장]을 다시 눌러 보세요. 계속 안 되면 메뉴 막대 아이콘 › 도움말 › 진단 정보 복사로 복사해서 보내 주세요.",
                   "지금 화면에 보이는 설정은 앱을 끌 때까지 그대로 쓰입니다. 이전에 저장해 둔 설정 파일은 바뀌지 않았습니다."],
            detail: DiagReport.sanitize(detail),
            buttons: [("설정 폴더 열기", { revealSettingsFolder() })])
    }

    static func unreadable(reason: String, backup: URL?) -> NoticeContent {
        let reassure = backup != nil
            ? "원래 파일은 지우지 않았고, 복사본(\(backup!.lastPathComponent))을 같은 폴더에 남겼습니다. 설정 창에서 [저장]을 누르기 전까지는 원래 파일을 건드리지 않습니다."
            : "복사본을 만들지 못해서, 원래 파일은 그대로 두고 [저장]도 막아 두었습니다."
        return NoticeContent(
            title: "설정 파일을 읽지 못했습니다",
            body: ["설정 파일(settings.ini)이 손상됐거나 알 수 없는 형식이라 읽을 수 없었습니다.",
                   "이번에는 기본 설정으로 시작했습니다. 필요하면 설정 창에서 다시 맞추세요. 파일을 살펴보려면 아래 버튼으로 폴더를 열 수 있습니다.",
                   reassure],
            detail: DiagReport.sanitize("설정 파일: \(tilde(Settings.path))\n이유: \(reason)"),
            buttons: [("설정 폴더 열기", { revealSettingsFolder() })])
    }

    static func translocated() -> NoticeContent {
        NoticeContent(
            title: "응용 프로그램 폴더로 옮겨 주세요",
            body: ["지금은 다운로드 폴더 같은 곳에서 바로 실행 중입니다. 이 상태에서는 맥이 앱을 임시 자리에서 실행해서, 로그인 시 실행이나 업데이트가 제대로 되지 않을 수 있습니다.",
                   "Focus & Draw를 Finder의 '응용 프로그램' 폴더로 끌어다 놓은 뒤 다시 열어 주세요.",
                   "옮기지 않아도 단축키와 드로잉은 지금 그대로 쓸 수 있습니다."],
            buttons: [("Finder에서 보기", { revealOriginalApp() })])
    }

    static func firstRun() -> NoticeContent {
        NoticeContent(
            title: "Focus & Draw를 시작했습니다",
            body: ["• 위젯은 화면 오른쪽 아래에 있습니다. 잡고 끌어서 옮길 수 있습니다.",
                   "• 화면 맨 위 메뉴 막대에 아이콘이 있습니다. 설정, 도움말, 종료는 여기서 합니다.",
                   "• 강조는 F8, 드로잉은 F9입니다. 맥북에서는 fn 키와 함께(fn+F8, fn+F9) 누르세요.",
                   "• fn 없이 쓰려면 ⌃⌥1(강조), ⌃⌥2(드로잉)을 누르세요.",
                   "이 안내는 메뉴 막대 아이콘 › 도움말 › 처음 안내 다시 보기에서 다시 볼 수 있습니다."])
    }

    // ---------- 동작 ----------
    static func revealSettingsFolder() {
        try? FileManager.default.createDirectory(at: Settings.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Settings.folder)
    }

    // 임시 자리(AppTranslocation)에서 실행 중이면 원래 앱이 있는 폴더를 보여 준다. 못 찾으면 다운로드 폴더.
    static func revealOriginalApp() {
        typealias Fn = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        if let h = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
           let sym = dlsym(h, "SecTranslocateCreateOriginalPathForURL") {
            let fn = unsafeBitCast(sym, to: Fn.self)
            if let orig = fn(Bundle.main.bundleURL as CFURL, nil)?.takeRetainedValue() {
                NSWorkspace.shared.activateFileViewerSelecting([orig as URL])
                return
            }
        }
        if let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first { NSWorkspace.shared.open(dl) }
    }

    static func isTranslocated(_ path: String = Bundle.main.bundlePath) -> Bool { path.contains("/AppTranslocation/") }
}
