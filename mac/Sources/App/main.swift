import AppKit

// 프로그램의 시작점은 메인 스레드에서 도는 최상위 코드다. UI 타입은 @MainActor라서 그대로는 부를 수 없으므로
// (macOS 14의 MainActor.assumeIsolated는 배포 대상 13에서 쓸 수 없다) 메인 스레드임을 우리가 보증하고 부른다.
func onMainThread(_ body: @escaping @MainActor () -> Void) {
    precondition(Thread.isMainThread)
    unsafeBitCast(body, to: (() -> Void).self)()
}

onMainThread {
    // 그림 기준 점검(--golden)은 창도 앱 실행 고리도 없이 한 번 돌고 끝난다 (화면 없는 컴퓨터에서도 돈다)
    if CommandLine.arguments.contains("--golden") {
        _ = NSApplication.shared
        exit(Golden.run(CommandLine.arguments))
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // Dock에 아이콘 없이 메뉴 막대에만
    app.run() // 앱이 끝날 때까지 돌아오지 않는다 — delegate는 그때까지 이 함수 안에서 산다
}
