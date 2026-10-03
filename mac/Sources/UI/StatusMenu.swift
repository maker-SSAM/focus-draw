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
        if let url = Bundle.main.url(forResource: "icon_menubar", withExtension: "png"),
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
        add("메뉴 막대에 강조·드로잉 아이콘 표시", #selector(menuTray), on: Settings.shared.showTrayIcons)
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
    @objc func menuTray() { Settings.shared.showTrayIcons.toggle() }
    // 눌린 자리가 왼쪽 반이면 강조, 오른쪽 반이면 드로잉
    @objc func trayClicked(_ sender: NSStatusBarButton) {
        guard let w = sender.window else { return }
        if NSEvent.mouseLocation.x - w.frame.minX < w.frame.width / 2 { toggleSpotlight() } else { draw.isOn ? draw.turnOff(.widgetButton) : draw.turnOn() }
    }

    // 어느 아이콘이 어디 있고 시스템이 보이게 두었는지 (노치·메뉴 막대 넘침으로 가려졌는지 찾으려고)
    func logStatusItems() {
        for (n, i) in [("main", statusItem), ("tray", spotTray)] {
            guard let i else { continue }
            let f = i.button?.window?.frame ?? .zero
            AppLog.write("STATUSITEM", "\(n) visible=\(i.isVisible) x=\(Int(f.minX)) w=\(Int(f.width)) image=\(i.button?.image != nil) screenW=\(Int(i.button?.window?.screen?.frame.width ?? 0)) notchLeftInset=\(i.button?.window?.screen?.auxiliaryTopLeftArea.map { Int($0.width) } ?? -1) rightArea=\(i.button?.window?.screen?.auxiliaryTopRightArea.map { Int($0.minX) } ?? -1)")
        }
    }

    // ---------- 강조·드로잉 전용 메뉴 막대 아이콘 (선택, 기본 꺼짐) ----------
    // 메뉴 막대 자리를 아끼려고 한 칸에 두 아이콘(강조 | 드로잉)을 나란히 그린다. 왼쪽 반을 누르면 강조, 오른쪽 반이면 드로잉.
    // 꺼져 있으면 메뉴 막대 색을 따르고, 켜져 있으면 파랑(0A84FF).
    func updateTrayIcons() {
        guard Settings.shared.showTrayIcons else {
            if let t = spotTray { NSStatusBar.system.removeStatusItem(t) }
            spotTray = nil
            return
        }
        let item: NSStatusItem
        if let t = spotTray { item = t } else {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "FocusDrawTrayItem"
            item.behavior = .removalAllowed
            item.button?.target = self
            item.button?.action = #selector(trayClicked(_:))
            item.button?.toolTip = "왼쪽 강조 · 오른쪽 드로잉 (누를 때마다 켜고 끔)"
            spotTray = item
        }
        func part(_ name: String, on: Bool) -> NSImage? {
            let img = on ? tintedIcon(name, color(ON_COLOR))
                         : Bundle.main.url(forResource: name, withExtension: "png").flatMap { NSImage(contentsOf: $0) }
            img?.size = NSSize(width: 18, height: 18)
            return img
        }
        let spotOn = state.spotOn, drawOn = draw.isOn
        let both = NSImage(size: NSSize(width: 40, height: 18), flipped: false) { _ in
            // 꺼진 쪽은 메뉴 막대 색을 따라야 하므로 따로 칠하지 않고, 켜진 쪽만 파랑 그림을 쓴다.
            // 템플릿 이미지는 한 장 전체가 한 색이라, 꺼진 쪽은 현재 메뉴 막대에 맞는 색으로 칠해 둔다.
            let base = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor.white : NSColor.black // 메뉴 막대가 그리는 중의 밝기(앱 창 모양이 아니라)
            let off: (String) -> NSImage? = { n in tintedIcon(n, base) }
            (spotOn ? part("icon_spotlight_dark", on: true) : off("icon_spotlight_dark"))?.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            (drawOn ? part("icon_draw_dark", on: true) : off("icon_draw_dark"))?.draw(in: NSRect(x: 22, y: 0, width: 18, height: 18))
            return true
        }
        both.isTemplate = !spotOn && !drawOn // 둘 다 꺼졌으면 시스템이 메뉴 막대 색으로 칠한다(가장 확실)
        item.button?.image = both
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.logStatusItems() }
    }
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
