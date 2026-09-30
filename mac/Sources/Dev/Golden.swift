import AppKit

// 그림 기준 점검(골든): FocusDraw --golden <결과 폴더> [--goldens <기준 폴더>] [--ahk <focus-draw.ahk>] [--update-goldens]
// 창·화면·사용자 설정 없이 고정 크기(640×400, 일부 @2x)로 장면을 그려 기준 그림과 견준다.
// 글 점검(단언)도 여기서 같이 돈다. 끝나면 결과 폴더에 log.txt · 축소 모음(contact-sheet.png) · 실패한 장면의 차이 그림을 남긴다.
// 마우스·키는 DrawController에 직접 넣는다 (창을 통한 경로는 --selftest가 본다).
@MainActor enum Golden {
    static let W: CGFloat = 640, H: CGFloat = 400
    static let channelTolerance = 2        // 채널당 ±2까지는 같은 것으로 본다
    static let pixelTolerance = 0.001      // 다른 픽셀이 0.1% 넘으면 실패
    static let maxGoldenCount = 40, maxGoldenBytes = 30 * 1024

    struct Scene {
        let name: String
        let scale: CGFloat
        var note = ""                      // 지금 알려진 차이 등 ("S6" 표시)
        let make: () -> CGImage?
    }

    // ---------- 키와 마우스를 흉내 내는 도우미 ----------
    @MainActor final class Sim {
        let d = DrawController(state: AppState()) // 드로잉 꺼짐 상태의 따로 만든 상태 (창 없이 입력만 흉내)
        let size: CGSize
        init(size: CGSize = CGSize(width: W, height: H)) { self.size = size; refresh() }
        // 그리기 코드는 설정을 읽지 않고 복사본만 쓰므로, 점검이 설정을 바꾼 뒤에는 복사본을 새로 넘긴다
        func refresh() { d.config = DrawConfig(Settings.shared) }
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: size.height - y) } // 위에서부터 y
        func ev(_ t: NSEvent.EventType, _ p: CGPoint, _ f: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: t, location: p, modifierFlags: f, timestamp: 0, windowNumber: 0,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func key(_ c: UInt16, _ f: NSEvent.ModifierFlags = []) { refresh(); d.handleKey(c, f, isRepeat: false, source: "golden") }
        func keyUp(_ c: UInt16) { d.handleKeyUp(c, source: "golden") }
        func hold(_ c: UInt16, _ body: () -> Void) { key(c); body(); keyUp(c) }
        func stroke(_ pts: [CGPoint], _ f: NSEvent.ModifierFlags = [], right: Bool = false) {
            d.down(pts[0], ev(right ? .rightMouseDown : .leftMouseDown, pts[0], f), right: right)
            for p in pts.dropFirst() { d.drag(p, ev(right ? .rightMouseDragged : .leftMouseDragged, p, f)) }
            d.up(pts.last!)
        }
        func wiggle(_ x0: CGFloat, _ y: CGFloat, _ w: CGFloat, amp: CGFloat = 30) -> [CGPoint] {
            stride(from: 0, through: w, by: 6).map { P(x0 + $0, y + sin($0 / 25) * amp) }
        }
        func image(scale: CGFloat = 1) -> CGImage? {
            refresh()
            return renderScene(items: d.items, live: d.live, board: d.boardColor, opacity: d.config.drawOpacity,
                               size: size, scale: scale)
        }
    }

    // 키 자리 번호 (글자가 아니라 자리로 본다)
    enum K {
        static let n1: UInt16 = 18, n2: UInt16 = 19, n3: UInt16 = 20, n4: UInt16 = 21, n5: UInt16 = 23, n0: UInt16 = 29
        static let q: UInt16 = 12, w: UInt16 = 13, e: UInt16 = 14, r: UInt16 = 15, a: UInt16 = 0, s: UInt16 = 1
        static let z: UInt16 = 6, x: UInt16 = 7, c: UInt16 = 8, plus: UInt16 = 24, minus: UInt16 = 27
        static let delete: UInt16 = 51, esc: UInt16 = 53
    }

    static func resetSettings() {
        let s = Settings.shared, f = Settings()
        s.drawOpacity = f.drawOpacity; s.drawColor = f.drawColor; s.drawStep = f.drawStep; s.eraserStep = f.eraserStep
        s.drawKeyColors = f.drawKeyColors; s.drawKeyAlphas = f.drawKeyAlphas
        s.boardColors = f.boardColors; s.boardAlphas = f.boardAlphas
        s.widgetScale = f.widgetScale; s.widgetColor = f.widgetColor; s.widgetOpacity = f.widgetOpacity
    }

    // ---------- 그림 도우미 ----------
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    static func bitmap(_ size: CGSize, scale: CGFloat = 1, _ body: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        body(ctx)
        return ctx.makeImage()
    }

    static func withNS(_ ctx: CGContext, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    static func snapshot(_ v: NSView, scale: CGFloat = 1) -> CGImage? {
        let size = v.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep.cgImage
    }

    // 투명한 곳이 보이도록 고정 회색 위에 얹어 저장·비교한다
    static func flatten(_ img: CGImage) -> CGImage? {
        // 알파 없는 RGB로 저장해야 PNG가 작다 (기준 그림 각 30KB 이하)
        guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let r = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        ctx.setFillColor(CGColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1))
        ctx.fill(r)
        ctx.draw(img, in: r)
        return ctx.makeImage()
    }

    static func png(_ img: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    static func rgba(_ img: CGImage) -> [UInt8]? {
        var buf = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let ok = buf.withUnsafeMutableBytes { p -> Bool in
            guard let ctx = CGContext(data: p.baseAddress, width: img.width, height: img.height, bitsPerComponent: 8,
                                      bytesPerRow: img.width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            return true
        }
        return ok ? buf : nil
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    // ---------- 실행 ----------
    static func run(_ args: [String]) -> Int32 {
        func arg(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        AppLog.folder = nil // 그림·글 점검은 사용자 기록을 건드리지 않는다
        guard let outPath = arg("--golden") else { print("사용법: --golden <결과 폴더> [--goldens <기준 폴더>] [--ahk <파일>] [--update-goldens]"); return 2 }
        let out = URL(fileURLWithPath: outPath), fm = FileManager.default
        let goldenDir = arg("--goldens").map { URL(fileURLWithPath: $0) }
        let update = args.contains("--update-goldens")
        try? fm.removeItem(at: out)
        for sub in ["actual", "diff"] { try? fm.createDirectory(at: out.appendingPathComponent(sub), withIntermediateDirectories: true) }
        if update, let g = goldenDir { try? fm.createDirectory(at: g, withIntermediateDirectories: true) }

        var log: [String] = []
        var passed = 0, failed = 0, sceneOK = 0, sceneFail = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            log.append("\(ok ? "OK" : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
            if detail == "INFO" { return }
            if ok { passed += 1 } else { failed += 1 }
        }

        var sheet: [(name: String, image: CGImage, failed: Bool, note: String)] = []
        let list = scenes()
        check("기준 그림 장면 수 \(maxGoldenCount)개 이하", list.count <= maxGoldenCount, "\(list.count)개")
        for scene in list {
            var img: CGImage?
            autoreleasepool { img = scene.make().flatMap(flatten) }
            guard let flat = img, let data = png(flat) else {
                log.append("FAIL 장면 \(scene.name) — 그림을 만들지 못함"); sceneFail += 1
                continue
            }
            try? data.write(to: out.appendingPathComponent("actual/\(scene.name).png"))
            var bad = false
            if update, let g = goldenDir {
                try? data.write(to: g.appendingPathComponent("\(scene.name).png"))
                log.append("UPDATED \(scene.name)")
            } else if let g = goldenDir {
                let url = g.appendingPathComponent("\(scene.name).png")
                if let want = (try? Data(contentsOf: url)).flatMap(decode), let a = rgba(want), let b = rgba(flat) {
                    if want.width != flat.width || want.height != flat.height {
                        bad = true
                        log.append("FAIL 장면 \(scene.name) — 크기가 다름 (기준 \(want.width)×\(want.height), 지금 \(flat.width)×\(flat.height))")
                    } else {
                        var diffCount = 0
                        var diffPixels = [UInt8](b)
                        for i in stride(from: 0, to: a.count, by: 4) {
                            let d = (0..<3).map { abs(Int(a[i + $0]) - Int(b[i + $0])) }.max()!
                            if d > channelTolerance {
                                diffCount += 1
                                diffPixels[i] = 255; diffPixels[i + 1] = 0; diffPixels[i + 2] = 0; diffPixels[i + 3] = 255
                            } else {
                                for c in 0..<3 { diffPixels[i + c] = UInt8(60 + Int(b[i + c]) * 2 / 5) }
                            }
                        }
                        let frac = Double(diffCount) / Double(a.count / 4)
                        if frac > pixelTolerance {
                            bad = true
                            log.append(String(format: "FAIL 장면 %@ — 다른 픽셀 %.2f%% (허용 %.1f%%)", scene.name, frac * 100, pixelTolerance * 100))
                            diffPixels.withUnsafeMutableBytes { p in
                                if let ctx = CGContext(data: p.baseAddress, width: flat.width, height: flat.height, bitsPerComponent: 8, bytesPerRow: flat.width * 4,
                                                       space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   let di = ctx.makeImage(), let dd = png(di) {
                                    try? dd.write(to: out.appendingPathComponent("diff/\(scene.name).png"))
                                }
                            }
                        }
                    }
                } else {
                    bad = true
                    log.append("FAIL 장면 \(scene.name) — 기준 그림이 없음 (선생님 승인 뒤 --update-goldens)")
                }
            }
            if bad { sceneFail += 1 } else { sceneOK += 1 }
            sheet.append((scene.name, flat, bad, scene.note))
        }

        // 기준 그림 규칙: 40개 이하, 각 30KB 이하
        if let g = goldenDir, let files = try? fm.contentsOfDirectory(at: g, includingPropertiesForKeys: [.fileSizeKey]) {
            let pngs = files.filter { $0.pathExtension == "png" }
            let big = pngs.filter { ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > maxGoldenBytes }
            check("기준 그림 \(maxGoldenCount)개 이하 (지금 \(pngs.count)개)", pngs.count <= maxGoldenCount)
            check("기준 그림은 각 \(maxGoldenBytes / 1024)KB 이하", big.isEmpty, big.map(\.lastPathComponent).joined(separator: ", "))
            let names = Set(list.map(\.name))
            let stale = pngs.map { $0.deletingPathExtension().lastPathComponent }.filter { !names.contains($0) }
            check("장면에 없는 옛 기준 그림이 없음", stale.isEmpty, stale.joined(separator: ", "))
        }

        assertions(check, ahk: arg("--ahk"))
        SettingsTests.run(check, fixtures: arg("--fixtures"))
        SettingsSchemaTests.run(check, ahk: arg("--ahk"))
        HotKeyTests.run(check)
        S4Tests.run(check)
        S5Tests.run(check)

        contactSheet(sheet, to: out.appendingPathComponent("contact-sheet.png"))
        log.append("INFO 장면 통과 \(sceneOK) 실패 \(sceneFail) · 글 점검 통과 \(passed) 실패 \(failed)")
        log.append("DONE")
        try? log.joined(separator: "\n").write(to: out.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)

        let failures = log.filter { $0.hasPrefix("FAIL") }
        if failures.isEmpty {
            print("그림 점검 통과: 장면 \(sceneOK)개, 글 점검 \(passed)개" + (update ? " (기준 그림을 새로 저장함)" : ""))
            return 0
        }
        print("그림 점검 실패: 장면 \(sceneFail)개, 글 점검 \(failed)개")
        failures.forEach { print("  " + $0) }
        print("  차이 그림·축소 모음: \(outPath)")
        return 1
    }

    // 모든 장면을 작게 줄여 한 장에 모은다 (실패한 장면은 빨간 테두리) — 선생님께 보내는 "기준 그림 한 장"
    static func contactSheet(_ items: [(name: String, image: CGImage, failed: Bool, note: String)], to url: URL) {
        guard !items.isEmpty else { return }
        let cols = 5, cell = CGSize(width: 250, height: 165), pad: CGFloat = 10
        let rows = (items.count + cols - 1) / cols
        let size = CGSize(width: CGFloat(cols) * (cell.width + pad) + pad, height: CGFloat(rows) * (cell.height + pad) + pad)
        let img = bitmap(size) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.interpolationQuality = .high
            for (i, it) in items.enumerated() {
                let col = i % cols, row = i / cols
                let x = pad + CGFloat(col) * (cell.width + pad)
                let y = size.height - pad - CGFloat(row + 1) * (cell.height + pad) + pad
                let box = CGRect(x: x, y: y + 16, width: cell.width, height: cell.height - 16)
                let k = min(box.width / CGFloat(it.image.width), box.height / CGFloat(it.image.height))
                let w = CGFloat(it.image.width) * k, h = CGFloat(it.image.height) * k
                let r = CGRect(x: box.minX, y: box.maxY - h, width: w, height: h)
                ctx.draw(it.image, in: r)
                ctx.setStrokeColor(it.failed ? CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1) : CGColor(srgbRed: 0.6, green: 0.6, blue: 0.6, alpha: 1))
                ctx.setLineWidth(it.failed ? 3 : 1)
                ctx.stroke(r)
                withNS(ctx) {
                    let label = it.name + (it.note.isEmpty ? "" : "  [\(it.note.prefix(3))]")
                    (label as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: 11),
                                                                                       .foregroundColor: it.failed ? NSColor.red : NSColor.black])
                }
            }
        }
        if let img, let data = png(img) { try? data.write(to: url) }
    }
}
