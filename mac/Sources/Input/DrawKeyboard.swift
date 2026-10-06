import AppKit

// ================= 드로잉 키 =================
// 글자가 아니라 키 자리(keyCode)로 본다 — 한글 입력 상태에서도 똑같이 동작하게.
// 판은 키 창이 아니므로 키는 전역 단축키(Input/DrawKeys.swift)로 들어온다. keyDown(_:)은 자체 점검이 가짜 키를 넣는 입구다.

extension DrawController {
    static let digitKeys: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 0,
                                           83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9, 82: 0]

    func keyDown(_ e: NSEvent) { handleKey(e.keyCode, e.modifierFlags, isRepeat: e.isARepeat, source: "view") }
    func keyUp(_ e: NSEvent) { handleKeyUp(e.keyCode, source: "view") }

    func handleKey(_ k: UInt16, _ f: NSEvent.ModifierFlags, isRepeat: Bool, source: String) {
        Log.keys += 1
        Log.log("KEY", "\(source) down code=\(k) mods=\(modsText(f))\(isRepeat ? " repeat" : "")")
        // ⌘Z / Ctrl+Z만 실행 취소로 쓴다. ⌘⇧Z(다시 실행이 아니다, 그냥 무시)는 걸러낸다.
        if !f.contains(.shift), f.contains(.command) || f.contains(.control), k == 6 { undo(); return }
        if f.contains(.command) { return }
        switch k {
        case 53: requestOff(.esc)                                  // Esc
        case 51, 117: clearAll()                                   // delete / 앞으로 지우기
        case 6, 7, 8: if !isRepeat { held.insert(k) }              // Z X C: 누르고 있는 동안 도형
        case 0: pen = .laser; updateCursor()                       // A
        case 1: pen = .rainbow; rainbowColor = true; updateCursor() // S (이 뒤에 A를 누르면 무지개 레이저)
        case 12: board = 0; surface.invalidateAll(); updateCursor()        // Q
        case 13: board = 1; surface.invalidateAll(); updateCursor()        // W
        case 14: board = 2; surface.invalidateAll(); updateCursor()        // E
        case 15: board = 3; surface.invalidateAll(); updateCursor()        // R
        case 24, 69: adjustSize(+1, eraser: rightDown || optionHeld || f.contains(.option)) // = + (키패드 +)
        case 27, 78: adjustSize(-1, eraser: rightDown || optionHeld || f.contains(.option)) // - (키패드 -)
        default:
            if let d = DrawController.digitKeys[k] {
                if d == 0 { rgb = config.drawColor; alpha = startAlpha(100) } else {
                    rgb = config.drawKeyColors[d - 1]; alpha = startAlpha(config.drawKeyAlphas[d - 1])
                    penStep = config.drawKeySteps[d - 1] // 굵기도 그 숫자키의 단계로 (0은 굵기를 그대로 둔다 — Windows와 같음)
                }
                pen = .normal
                rainbowColor = false
                updateCursor()
            }
        }
    }

    func handleKeyUp(_ k: UInt16, source: String) {
        if [6, 7, 8].contains(k) { Log.log("KEY", "\(source) up code=\(k)") }
        held.remove(k)
    }

    private func modsText(_ f: NSEvent.ModifierFlags) -> String {
        let s = (f.contains(.control) ? "⌃" : "") + (f.contains(.option) ? "⌥" : "") + (f.contains(.shift) ? "⇧" : "") + (f.contains(.command) ? "⌘" : "")
        return s.isEmpty ? "-" : s
    }

    func flagsChanged(_ e: NSEvent) {
        // Shift를 드래그 도중에 눌러도 방향 맞춤이 바로 따라온다
        if live != nil, !erasing, mode != .free { refreshShape(end: shapeEnd(mouse, e.modifierFlags)) }
    }

    private func adjustSize(_ delta: Int, eraser: Bool) {
        if eraser {
            optionHeld = true // ⌥= 단축키가 오면 바로 지우개 링과 새 크기를 보인다 (20Hz 살핌을 기다리지 않는다)
            eraserStep = max(1, min(STEP_MAX, eraserStep + delta))
            showBadge("\(eraserStep)")
        } else {
            penStep = max(1, min(STEP_MAX, penStep + delta))
            showBadge("\(penStep)")
        }
        updateCursor()
    }

    // ---------- 휠: 지금 쓰는 색을 진하게 / 연하게 ----------
    // 위로 굴리면(트랙패드는 손가락을 위로 밀면) 진해진다 — "자연스러운 스크롤" 설정과 관계없이(결정 7: 트랙패드도 같음).
    // 튕긴 뒤 손을 뗀 관성 스크롤은 무시한다.
    func scroll(_ e: NSEvent) {
        if !e.momentumPhase.isEmpty { return }
        if e.phase.contains(.began) { scrollAccum = 0 }
        let dy = physicalScrollUp(e.scrollingDeltaY, inverted: e.isDirectionInvertedFromDevice)
        scrollAccum += e.hasPreciseScrollingDeltas ? dy / 12 : dy
        while abs(scrollAccum) >= 1 {
            let dir: CGFloat = scrollAccum > 0 ? 1 : -1
            scrollAccum -= dir
            stepAlpha(dir)
        }
        showBadge("\(Int((alpha * 100).rounded()))%")
        updateCursor()
    }

    // 휠 한 칸: 5%씩, 5~100%. 판 전체에 곱하는 값이 없으므로 이 숫자가 실제 진하기다.
    func stepAlpha(_ dir: CGFloat) {
        alpha = max(0.05, min(1, ((alpha * 100).rounded() + 5 * dir) / 100))
    }
}

// "자연스러운 스크롤"을 켜면 시스템이 방향을 뒤집어 보내므로, 장치에서 실제로 "위로" 굴린 양으로 되돌린다
func physicalScrollUp(_ delta: CGFloat, inverted: Bool) -> CGFloat { inverted ? -delta : delta }
