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
        statusMenu = menu
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
        add("메뉴 막대 아이콘을 위젯처럼 표시", #selector(menuTray), on: Settings.shared.showTrayIcons)
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
    // 합친 아이콘(강조 | 드로잉 | 설정)에서 눌린 자리: 왼쪽 = 강조, 가운데 = 드로잉, 오른쪽 = 메뉴(설정). 오른쪽 클릭·⌃클릭은 어디서나 메뉴.
    @objc func trayClicked(_ sender: NSStatusBarButton) {
        guard let w = sender.window else { return }
        let e = NSApp.currentEvent
        let menuClick = e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true
        let third = (NSEvent.mouseLocation.x - w.frame.minX) / max(1, w.frame.width) * 3
        if menuClick || third >= 2 { showStatusMenu() }
        else if third < 1 { toggleSpotlight() }
        else { draw.isOn ? draw.turnOff(.widgetButton) : draw.turnOn() }
    }

    private func showStatusMenu() {
        statusItem.menu = statusMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // ---------- 합친 메뉴 막대 아이콘 (선택, 기본 꺼짐) ----------
    // 켜면 한 칸에 위젯과 같은 차례로 강조 · 드로잉 · 설정을 얇은 테두리로 묶어 그린다. 꺼진 것은 메뉴 막대 색, 켜진 것은 파랑(0A84FF).
    func updateTrayIcons() {
        guard let item = statusItem, let button = item.button else { return }
        func load(_ name: String) -> NSImage? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png"), let img = NSImage(contentsOf: url) else { return nil }
            img.size = NSSize(width: 18, height: 18)
            return img
        }
        guard Settings.shared.showTrayIcons else {
            item.length = NSStatusItem.squareLength
            item.menu = statusMenu
            button.action = nil; button.target = nil; button.toolTip = nil
            if let img = load("icon_menubar") { img.isTemplate = true; button.image = img }
            return
        }
        item.length = NSStatusItem.variableLength
        item.menu = nil
        button.target = self
        button.action = #selector(trayClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "강조 · 드로잉 · 설정 메뉴"
        let spotOn = state.spotOn, drawOn = draw.isOn
        // NSStatusBar.thickness(22)는 옛 값이다. 노치 맥북의 실제 메뉴 막대는 더 높아(약 37) 칸 창 높이를 따라 테두리를 키운다.
        // 아이콘은 폭 때문에 키울 수 없다 — 폭은 노치와 오른쪽 이웃 아이콘 사이에 들어가야 하고(너무 넓으면 시스템이 통째로 숨긴다), 사이 여백 2, 양끝 여백 3.5
        let imgH = max(NSStatusBar.system.thickness, (button.window?.frame.height ?? 0) - 6)
        let icon: CGFloat = 23, gap: CGFloat = 2, margin: CGFloat = 3.5
        let imgW = 3 * icon + 2 * gap + 2 * margin
        let all = NSImage(size: NSSize(width: imgW, height: imgH), flipped: false) { r in
            // 템플릿 이미지는 한 장이 한 색이라, 켜진 것만 파랑으로 칠하려면 직접 칠한다. 색은 그리는 중인 메뉴 막대의 밝기를 따른다.
            let base = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor.white : NSColor.black
            // 위젯과 같은 차례(강조 · 드로잉 · 설정)를 얇은 둥근 테두리 하나로 묶는다
            base.withAlphaComponent(0.75).setStroke()
            let box = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            box.lineWidth = 1
            box.stroke()
            func glyph(_ name: String, on: Bool) -> NSImage? { tintedIcon(name, on ? color(ON_COLOR) : base) }
            for (i, g) in [glyph("icon_spotlight_dark", on: spotOn), glyph("icon_draw_dark", on: drawOn), glyph("settings", on: false)].enumerated() {
                g?.draw(in: NSRect(x: margin + CGFloat(i) * (icon + gap), y: (r.height - icon) / 2, width: icon, height: icon))
            }
            return true
        }
        all.isTemplate = !spotOn && !drawOn // 둘 다 꺼졌으면 시스템이 메뉴 막대 색으로 칠한다(가장 확실)
        button.image = all
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.logStatusItems() }
    }

    // 어느 아이콘이 어디 있고 시스템이 보이게 두었는지 (노치·메뉴 막대 넘침으로 가려졌는지 찾으려고)
    func logStatusItems() {
        for (n, i) in [("main", statusItem)] {
            guard let i else { continue }
            let f = i.button?.window?.frame ?? .zero
            AppLog.write("STATUSITEM", "\(n) visible=\(i.isVisible) x=\(Int(f.minX)) w=\(Int(f.width)) image=\(i.button?.image != nil) screenW=\(Int(i.button?.window?.screen?.frame.width ?? 0)) notchLeftInset=\(i.button?.window?.screen?.auxiliaryTopLeftArea.map { Int($0.width) } ?? -1) rightArea=\(i.button?.window?.screen?.auxiliaryTopRightArea.map { Int($0.minX) } ?? -1)")
        }
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
