import AppKit
import Darwin

// 속도 측정: FocusDraw --bench <결과 파일>
// 화면에 창을 띄우지 않고, 창이 하는 그리기와 똑같은 일을 화면 크기의 그림에 해 보며 시간을 잰다.
//   1) 50% 형광펜 3,000점 획을 긋는 동안 이벤트 하나당 걸리는 시간 (p50/p95)
//      - 지금 방식: 반투명 획은 지나온 자리 전체를 매번 다시 그린다
//      - 획 전용 그림 방식: 새 토막만 따로 그림에 더하고, 그 토막 자리만 합쳐 그린다
//   2) 손을 뗄 때 확정하는 시간  3) 실행 취소 재구성 (500·2,000·5,000개)  4) 5K 화면 하나의 메모리
//   5) 쉬는 동안 깨어남 횟수 (레이저를 쓴 뒤 타이머가 멈추는지)
// 창이 화면에 합성되는 시간(WindowServer)은 여기 들어가지 않는다 — 실제로는 이보다 조금 더 걸린다.
@MainActor enum Bench {
    static func run(_ d: AppDelegate, out: String) {
        var lines: [String] = []
        func say(_ s: String) { lines.append(s); print(s); fflush(stdout) }
        func finish() {
            try? (lines.joined(separator: "\n") + "\n").write(toFile: out, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }

        say("# Focus & Draw --bench  \(Date())")
        say("machine=\(Log.sysctlString("hw.model")) cpu=\(Log.sysctlString("machdep.cpu.brand_string")) "
            + "macOS=\(ProcessInfo.processInfo.operatingSystemVersionString) arch=\(Log.machineArch)")
        var failures: [String] = []
        func assertBench(_ name: String, _ value: Double, max limit: Double) {
            let ok = value <= limit
            say("  \(ok ? "OK  " : "FAIL") \(name): \(f(value))ms (기준 \(f(limit))ms 이하)")
            if !ok { failures.append(name) }
        }
        say("단위: ms. 형광펜 = 노랑 50%, 굵기 8단계(\(String(format: "%.1f", penPx(8)))pt), 점 간격 약 5pt, 배율 2")

        for (pw, ph) in [(3024, 1964), (5120, 2880)] {
            let scale: CGFloat = 2
            let size = CGSize(width: CGFloat(pw) / scale, height: CGFloat(ph) / scale)
            let cache = context(pw, ph, scale)
            for item in sampleItems(200, in: size, seed: 7) { renderInk(item, in: cache) }
            var cacheImage = cache.makeImage()!
            let target = context(pw, ph, scale)

            say("")
            say("## \(pw)×\(ph) px (\(Int(size.width))×\(Int(size.height)) pt), 이미 그려진 획 200개 위에서")
            for (shapeName, pts) in [("밑줄 왕복 (가로 80% × 200pt)", underlineScribble(size, count: 3000)),
                                     ("넓게 칠하기 (가로 70% × 세로 50%)", areaScribble(size, count: 3000))] {
                let a = eventsCurrent(pts, cacheImage: cacheImage, target: target, size: size)
                let b = eventsLiveLayer(pts, cacheImage: cacheImage, target: target, pw: pw, ph: ph, scale: scale, size: size)
                say("긋는 중 · \(shapeName)")
                say("  옛 방식(지나온 자리 전체 다시 그림) p50=\(f(pct(a, 0.5))) p95=\(f(pct(a, 0.95))) max=\(f(a.max() ?? 0))  (300개 표본)")
                say("  획 전용 그림 방식(지금 코드의 StrokeLayer) p50=\(f(pct(b, 0.5))) p95=\(f(pct(b, 0.95))) max=\(f(b.max() ?? 0))  (3,000개 전부)")
                if pw == 5120 { assertBench("5K 긋는 중 \(shapeName.split(separator: " ").first ?? "") p95", pct(b, 0.95), max: 8) }
            }

            // 확정: 캐시에 한 획 더 굽고 새 그림을 만든다 (앞 그림을 들고 있으므로 쓰기 전에 통째 복사가 일어난다)
            var commits: [Double] = []
            let big = InkItem(kind: .stroke, points: areaScribble(size, count: 3000), width: penPx(8), rgb: 0xFFFF00, alpha: 0.5)
            for _ in 0..<5 {
                let t = now()
                renderInk(big, in: cache)
                cacheImage = cache.makeImage()!
                commits.append(now() - t)
            }
            say("확정 (3,000점 50% 획)  p50=\(f(pct(commits, 0.5))) max=\(f(commits.max() ?? 0))")

            // 실행 취소: 옛 방식은 목록 전체를 다시 굽는다. 지금은 바닥 그림을 그대로 쓰고 최근 40개(30 + 굽기 묶음 10)만 다시 그린다
            for n in [500, 2000, 5000] {
                let items = sampleItems(n, in: size, seed: UInt64(n))
                let t = now()
                let c = context(pw, ph, scale)
                for item in items { renderInk(item, in: c) }
                _ = c.makeImage()
                say("실행 취소 재구성 \(n)개 (옛 방식, 전부)  \(f(now() - t))")
                let floorCtx = context(pw, ph, scale)
                for item in items.dropLast(40) { renderInk(item, in: floorCtx) }
                let cacheCtx = context(pw, ph, scale)
                var worst = 0.0
                for _ in 0..<5 {
                    let t2 = now()
                    cacheCtx.clear(CGRect(origin: .zero, size: size))
                    cacheCtx.draw(floorCtx.makeImage()!, in: CGRect(origin: .zero, size: size))
                    for item in items.suffix(40) { renderInk(item, in: cacheCtx) }
                    _ = cacheCtx.makeImage()
                    worst = max(worst, now() - t2)
                }
                say("실행 취소 \(n)개 (바닥 그림 + 최근 40개)  가장 느린 \(f(worst))")
                if n == 2000 && pw == 5120 { assertBench("5K 2,000개 실행 취소", worst, max: 50) }
            }
            _ = cacheImage
        }

        // 메모리: 5K 화면 하나의 캐시(그리는 판) + 화면에 내보낸 그림 + 복사본
        say("")
        let before = footprintMB()
        var keep: [AnyObject] = []
        autoreleasepool {
            let c = context(5120, 2880, 2)
            for item in sampleItems(200, in: CGSize(width: 2560, height: 1440), seed: 3) { renderInk(item, in: c) }
            let img = c.makeImage()!
            renderInk(InkItem(kind: .stroke, points: [CGPoint(x: 10, y: 10), CGPoint(x: 500, y: 500)], width: 8), in: c)
            keep = [c, img, c.makeImage()!]
        }
        let after = footprintMB()
        say("## 메모리 (5K 화면 하나)")
        say("캐시 + 그림 두 장 = \(f(after - before)) MB (측정, 붙든 것 \(keep.count)개). 창 버퍼는 따로 약 \(f(5120 * 2880 * 4 / 1_048_576)) MB 더 (추정)")
        keep = []

        // 쉬는 동안: 가만히 10초 → 레이저 한 번 긋고 사라진 뒤 → 다시 가만히 10초
        say("")
        say("## 쉬는 동안 깨어남 (10초씩)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let w0 = usage()
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                let w1 = usage()
                say("처음 쉴 때          " + usageText(w0, w1))
                // 레이저: 판을 띄우지 않고 그리기 동작만 (타이머가 스스로 멈추는지 보려고)
                d.draw.controller.handleKey(0, [], isRepeat: false, source: "bench")
                let p = NSEvent.mouseLocation
                let e = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                d.draw.controller.down(p, e, right: false)
                for i in 1...30 { d.draw.controller.drag(CGPoint(x: p.x + CGFloat(i * 5), y: p.y), e) }
                d.draw.controller.up(CGPoint(x: p.x + 150, y: p.y))
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    let w2 = usage()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                        let w3 = usage()
                        say("레이저를 쓴 뒤 쉴 때 " + usageText(w2, w3))
                        say("(깨어남은 초당 횟수. 두 줄이 비슷하면 레이저 타이머가 제대로 멈춘 것)")
                        say(failures.isEmpty ? "BENCH 기준 통과" : "BENCH 기준 실패: \(failures.joined(separator: ", "))")
                        finish()
                    }
                }
            }
        }
    }

    // ---------- 그리는 방식 두 가지 ----------
    // 지금 방식 (InkView.draw): 반투명 획은 bounds 전체를 다시 칠한다 — 캐시 그림 + 긋는 중인 획 전체
    static func eventsCurrent(_ pts: [CGPoint], cacheImage: CGImage, target: CGContext, size: CGSize) -> [Double] {
        var live = InkItem(kind: .stroke, points: [pts[0]], width: penPx(8), rgb: 0xFFFF00, alpha: 0.5)
        var times: [Double] = []
        let full = CGRect(origin: .zero, size: size)
        for i in 1..<pts.count {
            live.points.append(pts[i])
            guard i % 10 == 0 else { continue }
            let t = now()
            let dirty = live.bounds.intersection(full)
            target.saveGState()
            target.clip(to: dirty)
            target.clear(dirty)
            target.beginTransparencyLayer(auxiliaryInfo: nil)
            target.draw(cacheImage, in: full)
            renderInk(live, in: target)
            target.endTransparencyLayer()
            target.restoreGState()
            target.flush()
            times.append(now() - t)
        }
        return times
    }

    // 획 전용 그림 방식: 긋는 중인 획을 불투명하게 따로 쌓고, 화면에는 새 토막 자리만 50%로 얹는다
    static func eventsLiveLayer(_ pts: [CGPoint], cacheImage: CGImage, target: CGContext,
                                pw: Int, ph: Int, scale: CGFloat, size: CGSize) -> [Double] {
        let layer = StrokeLayer(size: size, scale: scale, origin: .zero)!
        let w = penPx(8)
        var times: [Double] = []
        let full = CGRect(origin: .zero, size: size)
        for i in 1..<pts.count {
            let t = now()
            let a = pts[i - 1], b = pts[i]
            layer.add(InkItem(kind: .stroke, points: [a, b], width: w, rgb: 0xFFFF00, alpha: 0.5))
            let seg = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                .insetBy(dx: -w - 2, dy: -w - 2).intersection(full)
            target.saveGState()
            target.clip(to: seg)
            target.clear(seg)
            target.draw(cacheImage, in: full)
            target.setAlpha(0.5)
            target.draw(layer.image, in: full)
            target.restoreGState()
            target.flush()
            times.append(now() - t)
        }
        return times
    }

    // ---------- 시험용 획 ----------
    static func underlineScribble(_ s: CGSize, count: Int) -> [CGPoint] {
        let left = s.width * 0.1, right = s.width * 0.9, top = s.height * 0.6
        var pts: [CGPoint] = []
        var x = left, y = top, dir: CGFloat = 1
        for _ in 0..<count {
            pts.append(CGPoint(x: x, y: y))
            x += 5 * dir
            if x > right || x < left { dir = -dir; y -= 200.0 / 8 }
        }
        return pts
    }

    static func areaScribble(_ s: CGSize, count: Int) -> [CGPoint] {
        let w = s.width * 0.7, h = s.height * 0.5
        let x0 = s.width * 0.15, y0 = s.height * 0.25
        // 가로로 크게 오가며 아래로 내려가는 지그재그 — 3,000점이 끝날 때 영역을 거의 덮는다
        let rows = 12
        let perRow = count / rows
        var pts: [CGPoint] = []
        for i in 0..<count {
            let row = i / perRow, k = CGFloat(i % perRow) / CGFloat(perRow)
            let x = x0 + (row % 2 == 0 ? k : 1 - k) * w
            let y = y0 + h - (CGFloat(row) + k) * h / CGFloat(rows)
            pts.append(CGPoint(x: x, y: y))
        }
        return pts
    }

    // 수업 중에 쌓일 법한 획: 40점짜리 구불구불한 선, 4개 중 1개는 반투명, 20개 중 1개는 지우개
    static func sampleItems(_ n: Int, in s: CGSize, seed: UInt64) -> [InkItem] {
        var rng = SplitMix(seed: seed)
        var items: [InkItem] = []
        for i in 0..<n {
            var p = CGPoint(x: rng.unit() * s.width, y: rng.unit() * s.height)
            var pts = [p]
            var ang = rng.unit() * 2 * .pi
            for _ in 0..<39 {
                ang += (rng.unit() - 0.5) * 0.8
                p = CGPoint(x: p.x + cos(ang) * 6, y: p.y + sin(ang) * 6)
                pts.append(p)
            }
            if i % 20 == 19 {
                items.append(InkItem(kind: .erase, points: pts, width: eraserPx(5)))
            } else {
                items.append(InkItem(kind: .stroke, points: pts, width: penPx(3 + i % 5), rgb: UInt32(truncatingIfNeeded: rng.next()) & 0xFFFFFF,
                                     alpha: i % 4 == 3 ? 0.5 : 1))
            }
        }
        return items
    }

    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }
    }

    // ---------- 작은 도구 ----------
    static func context(_ pw: Int, _ ph: Int, _ scale: CGFloat) -> CGContext {
        let c = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.scaleBy(x: scale, y: scale)
        return c
    }

    static func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000 }

    static func pct(_ xs: [Double], _ p: Double) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))]
    }

    static func f(_ v: Double) -> String { String(format: v < 10 ? "%.2f" : "%.1f", v) }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    struct Usage { var wakeups: UInt64; var idleWakeups: UInt64; var cpuNs: UInt64; var at: Double }

    static func usage() -> Usage {
        var info = rusage_info_v4()
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
        }
        // 애플 실리콘에서는 CPU 시간이 mach 시계 단위로 온다 → 나노초로 바꾼다
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let ticks = info.ri_user_time + info.ri_system_time
        return Usage(wakeups: info.ri_interrupt_wkups, idleWakeups: info.ri_pkg_idle_wkups,
                     cpuNs: ticks * UInt64(tb.numer) / UInt64(max(1, tb.denom)), at: now())
    }

    static func usageText(_ a: Usage, _ b: Usage) -> String {
        let sec = (b.at - a.at) / 1000
        return "깨어남 \(f(Double(b.wakeups - a.wakeups) / sec))/초, 절전 중 깨움 \(f(Double(b.idleWakeups - a.idleWakeups) / sec))/초, "
            + "CPU \(f(Double(b.cpuNs - a.cpuNs) / 1_000_000)) ms / \(f(sec))초"
    }
}
