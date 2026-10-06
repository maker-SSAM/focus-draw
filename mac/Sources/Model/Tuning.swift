import CoreGraphics
import Foundation

// 조절 상수 모음. 이름은 Windows 판(focus-draw.ahk)과 같게 두었다 — Dev/Golden.swift가 ahk의 값과 견준다.
// 여기 숫자를 바꾸면 그림이나 손맛이 달라지므로, 바꿀 때는 기준 그림(Tests/golden)과 ahk를 함께 본다.

// ---------- 펜·지우개 굵기 (단계 1~STEP_MAX) ----------
// 한 단계마다 비율만큼 커진다: 펜 3 · 3.9 · 5.1 … 31.8px, 지우개 10 · 15 · 23 … 384px
let STEP_MAX = 10
let DRAW_KEY_STEP_DEFAULT = 5   // 숫자키 1~9의 굵기 단계 기본값 ([DrawKeys] Step1~9, ahk DRAW_STEP_DEFAULT)
let PEN_BASE_PX: CGFloat = 3.0, PEN_STEP_RATIO: CGFloat = 1.3
let ERASER_BASE_PX: CGFloat = 10.0, ERASER_STEP_RATIO: CGFloat = 1.5

func penPx(_ step: Int) -> CGFloat { PEN_BASE_PX * pow(PEN_STEP_RATIO, CGFloat(max(1, min(STEP_MAX, step)) - 1)) }
func eraserPx(_ step: Int) -> CGFloat { ERASER_BASE_PX * pow(ERASER_STEP_RATIO, CGFloat(max(1, min(STEP_MAX, step)) - 1)) }


// ---------- 굵기·진하기 숫자 배지 ----------
// Windows는 30×24. 맥은 "100%"까지 들어가야 해서 너비는 글자에 맞춰 늘리고 최소만 34로 둔다.
let STEP_BADGE_W: CGFloat = 34   // 최소 너비
let STEP_BADGE_H: CGFloat = 22
let STEP_BADGE_MS = 500          // 화면에 머무는 시간(ms)

// ---------- 숫자키 색 1~9, 칠판 Q/W/E/R ----------
// ahk의 DRAW_COLOR_DEFAULTS와 BOARD_KEYS. 칠판 Q는 색이 없는 "투명"(nil).
let DRAW_COLORS: [UInt32] = [0xFF0000, 0xFF7F00, 0xFFFF00, 0x00FF00, 0x0000FF, 0x4B0082, 0x9400D3, 0x000000, 0xFFFFFF]
let BOARD_KEYS: [(key: String, rgb: UInt32?)] = [("Q", nil), ("W", 0xFFFFFF), ("E", 0x14472F), ("R", 0x000000)]
var BOARD_COLORS: [UInt32] { BOARD_KEYS.compactMap(\.rgb) } // W·E·R의 기본색

// ---------- 사라지는 펜(레이저) ----------
let LASER_HOLD: TimeInterval = 0.5      // 그어진 뒤 그대로 있는 시간 (ahk의 LASER_HOLD_MS)
let LASER_FADE: TimeInterval = 0.5      // 그 뒤 사라지는 데 걸리는 시간
let LASER_MIN_WIDTH: CGFloat = 8        // 펜을 가늘게 해도 레이저는 이만큼은 굵게 (너무 가늘면 빛나 보이지 않는다)
// 빛 겹(번짐·본체·흰 심)은 Render/Renderer.swift의 makeLaserGlowLayers

// ---------- 무지개 펜 ----------
let RAINBOW_CYCLE_PX: CGFloat = 700     // 이만큼 그으면 색이 한 바퀴

// ---------- 실행 취소 (선생님 결정 ③: 끈 뒤 1분, 사용자 결정 2026-09-30) ----------
let UNDO_MAX = 30
let UNDO_KEEP_S: TimeInterval = 60
// 30단계보다 오래된 획은 바닥 그림에 굽는다. 획마다 굽지 않고 이만큼 쌓였을 때 한꺼번에 (실행 취소 때 다시 그리는 획은 최대 UNDO_MAX + 이 값)
let FLOOR_CHUNK = 10
