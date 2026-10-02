import AppKit

// 메뉴 막대 아이콘과 그 메뉴 (위젯을 오른쪽 클릭해도 같은 메뉴가 뜬다).
// 상태는 AppDelegate의 AppState에서 읽기만 한다.
extension AppDelegate {
    // ---------- 메뉴 막대 아이콘 ----------
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // ⌘를 누른 채 끌어서 아이콘을 치울 수 있게 두되(막으면 메뉴 막대가 좁은 맥북에서 곤란하다), 빠졌는지는 기록해 둔다
        statusItem.autosaveName = "FocusDrawStatusItem"
        statusItem.behavior = .removalAllowed
        statusVisibility = statusItem.observe(\.isVisible, options: [.new]) { _, change in
            AppLog.write("STATUSITEM", "visible=\(change.newValue ?? true)")
        }
        if let url = Bundle.main.url(forResource: "icon_draw_dark", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true // 메뉴 막대 색(밝게/어둡게)에 맞춰 칠해진다
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "F&D"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) { fillMenu(menu) }

    func fillMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector, key: String = "", on: Bool = false) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.state = on ? .on : .off
            menu.addItem(item)
        }
        func keys(_ a: String, _ b: String) -> String {
            [a, b].map { HotkeyDisplay.symbols(Settings.shared.hotkeys[$0] ?? SettingsSchema.hotkeyDefaults[$0] ?? "") }.joined(separator: " · ")
        }
        add("강조 (\(keys("Spotlight", "SpotlightAlt")))", #selector(menuSpot), on: state.spotOn)
        add("드로잉 (\(keys("Draw", "DrawAlt")))", #selector(menuDraw), on: draw.isOn)
        add("드로잉 모드 단축키 보기", #selector(menuKeyboard))
        menu.addItem(.separator())
        add("위젯 표시", #selector(menuWidget), on: Settings.shared.showWidget)
        add("설정...", #selector(openSettings), key: ",")
        menu.addItem(.separator())
        add("진단 기록", #selector(menuDiag), on: Log.isOn)
        add("진단 기록 폴더 열기", #selector(menuDiagFolder))
        let help = NSMenuItem(title: "도움말", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let ver = NSMenuItem(title: "Focus & Draw \(AppInfo.displayVersion)", action: nil, keyEquivalent: "")
        ver.isEnabled = false
        sub.addItem(ver)
        for (t, a) in [("진단 정보 복사", #selector(menuCopyDiag)), ("처음 안내 다시 보기", #selector(menuFirstRun))] {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: "")
            i.target = self
            sub.addItem(i)
        }
        help.submenu = sub
        menu.addItem(help)
        Experiments.appendMenu(to: menu)
        menu.addItem(.separator())
        add("Focus & Draw 종료", #selector(menuQuit), key: "q")
    }

    @objc func menuKeyboard() { keyboardWindow.show() }
    @objc func menuSpot() { toggleSpotlight() }
    @objc func menuDraw() { draw.toggle() }
    @objc func menuWidget() { Settings.shared.showWidget.toggle() }
    @objc func menuFirstRun() { Notice.show(Notice.firstRun()) }

    // 문제가 생겼을 때 붙여 보낼 글을 클립보드에 복사한다 (이름·컴퓨터 이름은 들어 있지 않다)
    @objc func menuCopyDiag() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(DiagReport.build(), forType: .string)
        Notice.show(NoticeContent(
            title: "진단 정보를 복사했습니다",
            body: ["메모나 메신저에 붙여 넣어(⌘V) 보내 주세요.",
                   "버전, macOS, 맥 모델, 화면 크기, 기본값과 다른 설정, 최근 기록이 들어 있습니다. 사용자·컴퓨터 이름과 입력한 글자는 들어 있지 않습니다."]))
    }

    @objc func menuQuit() { NSApp.terminate(nil) }

    // 켜 두면 앱을 다시 열어도 이어서 기록한다
    @objc func menuDiag() {
        if Log.isOn {
            Log.wanted = false
            Log.stop()
        } else {
            Log.wanted = true
            Log.start(reason: "menu")
            Log.setActive(state.drawOn || state.spotOn)
        }
    }

    @objc func menuDiagFolder() {
        try? FileManager.default.createDirectory(at: Log.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Log.folder)
    }
}
