> 2026-09-28 로드맵 재점검 때 에이전트가 만든 원자료(영어). 사실 확인용 참고 자료이며, 결정의 기준은 mac/ROADMAP.md와 mac/design/stages.md다.

# Audit of the Mac pilot (commit 763df4f)

**Focus & Draw Mac port audit (static read of mac/Sources/*.swift, build.sh, Info.plist, mac/README.md, ROADMAP.md, root README.md, the head of focus-draw.ahk; nothing was modified)**

The shell was unavailable for this whole session (the auto-mode check never returned a verdict), so I read the code but did not compile or run it. Anything marked "verify" is inferred from reading and has not been reproduced.

Several things are already done well and should be kept:
- Keys are matched by keyCode, so they work with the Korean input source.
- Global hotkeys (Carbon) and the global mouse monitor need no Accessibility permission.
- Each window keeps its own backing scale.
- Coordinate conversion for strokes that cross between monitors is correct.
- Settings are stored in Application Support.
- The build is staged outside OneDrive.

---

## (a) Correctness bugs and risky spots, ranked

### CRITICAL / HIGH

**H1. Crash: switching pen during a rainbow drag.** (Draw.swift:60-66, caused by 536-541, 593, 671-687)
- Scenario: start a rainbow (`S`) drag, then press any digit, `0` or `A` before releasing.
- `pen` becomes `.normal` or `.laser`. The next `drag()` appends a point but no hue, so `hues.count < points.count`.
- `renderInk` then reads `hues[i]` out of range and the app stops with a fatal error. All ink is lost.
- Rainbow shapes crash the same way: `refreshShape` stops recomputing hues, while ellipse and wave point counts keep changing.
- Related: pressing `S` or a digit during a laser drag leaves `laserLive` non-nil forever (523, 560). The 60 Hz laser timer then runs until drawing is turned off.
- Fix: capture a "stroke session" (tool, colour, width, alpha, mode) at mouseDown and apply key changes only to the next stroke. Also guard `hues[min(i, hues.count-1)]`. Add a selftest scene for it.
- Stage: immediate hotfix (Sonnet).

**H2. A hidden widget reappears every time drawing is turned on or off.** (main.swift:29)
- `onStateChange` calls `widget.window.orderFrontRegardless()` unconditionally, so it shows the widget even when `showWidget == false`.
- The call is also unnecessary: WIDGET_LEVEL is already above OVERLAY_LEVEL.
- Stage: immediate hotfix (Haiku or Sonnet).

**H3. Keyboard focus depends on the app being activated.** (Draw.swift:362-365, 385; SettingsWindow.swift:142)
- `turnOn` calls the deprecated `NSApp.activate(ignoringOtherApps:)` and makes an ordinary NSWindow key. Until activation completes, keys go to the app underneath while the overlay is visible. The same happens after ⌘Tab, a notification or a system dialog steals focus mid-drawing.
- In those moments Esc can end a Keynote slideshow and digits can type into a document. Nothing listens for `didResignActive` while drawing.
- It works on the teacher's machine (Darwin 24.6 = macOS 15.6). Verify on 13, 14 and 26, where activation rules changed.
- Design alternative to spike: a non-activating NSPanel that can become key. The presenting app never loses active status, and "return to previous app" disappears as a problem. The cost is cursor ownership, because an inactive app cannot reliably set the cursor (see M7).
- Stage: 3, Opus spike. The decision affects the InkWindow class, so record it before the stage 1 split if possible.

**H4. Full-bitmap transparency layers when saving translucent strokes.** (Draw.swift:56-59, used by 226 and 234)
- `beginTransparencyLayer(auxiliaryInfo:nil)` on the cache context uses the whole bitmap as the layer, because there is no clip. On a 5K screen that is about 59 MB per layer.
- This happens for every highlighter stroke on commit, and again for every translucent item on every undo and rebuild, on every screen.
- Fix (one line): `beginTransparencyLayer(in: item.bounds, …)` or `clip(to: item.bounds)` first.
- Stage: cheap enough for the hotfix batch; otherwise stage 3.

**H5. A translucent or rainbow live stroke redraws its whole bounding box on every mouse event.** (Draw.swift:544, 256, 21-26)
- Each drag event invalidates `item.bounds`, recomputed from all points (O(n)).
- `draw` then re-strokes the entire live path inside two nested transparency layers.
- A long highlighter stroke on 5K therefore means near full-screen compositing at input rate. Even opaque strokes re-stroke all n points every frame (O(n²) per stroke).
- Opaque rainbow does not need full-bounds invalidation at all.
- Fix: accumulate the live stroke opaque in its own bitmap or CAShapeLayer and composite it with alpha. Invalidation can then stay segment-sized, with no darkened seams.
- Stage: 3 (Opus design, Sonnet implementation).

### MEDIUM

**M1. Stroke list is unbounded; undo is O(everything).** (Draw.swift:304, 619-638, 218-230)
- Items are trimmed only before a `.clear` that lies below the undo floor.
- `undo()` rebuilds every screen's cache from all items since the last clear. There is no culling to each screen's rect, and each rebuild allocates a new full-size context.
- A 40-minute lesson becomes a noticeable hitch per undo.
- The undo-floor arithmetic itself is correct. `items[..<undoFloor]` cannot go out of bounds, and the 30-step and 30-second rules match Windows lazily at the next `turnOn`.
- Fix: bake items below the floor into a per-screen base bitmap and replay at most 30 items. This interacts with M5.
- Stage: 3 (Opus).

**M2. Laser trail never prunes `laserLive`.** (Draw.swift:756-763)
- Only `laser` is pruned. While the button is held, the invalidation box grows to the whole path, with four clip-sized transparency layers at 60 Hz.
- Stage: 3 (Sonnet); the stuck-`laserLive` part is fixed together with H1.

**M3. Settings save and load problems.** (Settings.swift:73-82, 129-156, 160-166)
- `save()` rewrites the whole file and drops keys it does not know: Windows `[Hotkeys]`, `HideCursor`, `ShowTrayIcons`, and any future key. Windows `IniWrite` keeps unknown keys.
- `saveWidgetPosition` makes a second `Settings()`, loads, and re-saves the entire file on every grip release, including a click with no movement.
- If the file cannot be parsed, the load fails silently and that save overwrites the file with defaults. AHK v2 creates new ini files as UTF-16 LE, so a settings.ini copied from Windows would be wiped by the first widget drag.
- A UTF-8 BOM would hide the whole first section (verify).
- The parser does not trim key or value whitespace (`Size = 130` is ignored) and is case-sensitive, unlike IniRead.
- Everything runs on the main thread, so there is no thread race; the "race" is purely about what gets written.
- Fix: a table-driven schema (section, key, keyPath, type, default, range) that drives load, save, reset and parity checks; keep an ini model that round-trips unknown keys; decode UTF-16 and BOM.
- Stage: 1 (Opus schema, Sonnet implementation).

**M4. Wheel direction and momentum.** (Draw.swift:646-655)
- Natural scrolling is on by default for both mouse and trackpad, so rolling the wheel up gives negative deltaY and makes ink lighter. That is the opposite of the Windows rule "휠 위로 = 진하게". The selftest encodes the current behaviour (wheel1:-10 → 50%).
- Trackpad momentum keeps changing opacity after the fingers lift.
- Fix: use `isDirectionInvertedFromDevice` and ignore `momentumPhase`. The teacher decides the direction.
- Stage: 3 (Sonnet).

**M5. Multi-monitor coordinate model.** (Draw.swift:7, 342-345, 395-421; Widget.swift has no screen observer)
- Strokes are stored in global coordinates. When the primary display or the arrangement changes (projector plugged in and placed to the left), existing ink shifts or goes off-screen.
- A rebuild during a live drag strands `live` / `erasing`.
- The widget is not re-clamped when a screen disappears.
- Caches are allocated for every screen on every display change, even if drawing was never used.
- Stage: 3 (Opus). Decide global coordinates vs per-display coordinates keyed by display UUID.

**M6. Window levels are too aggressive, and fullscreen still needs testing.** (Spotlight.swift:5-7; Widget.swift:164)
- The widget (screenSaver+1) and spotlight (+2) sit above the screensaver and every system UI, even when not drawing.
- While drawing, system dialogs, the ⌘⇧5 toolbar and Notification Center are underneath and cannot be clicked.
- Keynote may take over the whole display during a slideshow (a "let other apps use the screen"-type setting), which could hide the overlay. Verify with current Keynote.
- Fix: put the widget at a floating or status level when idle and raise it only while drawing.
- Stage: 3 test matrix; the widget level change in stage 4.

**M7. Cursor strategy.** (Draw.swift:276, 481, 440-476; Widget.swift:113-114)
- `NSCursor.set()` runs on every mouseMoved, while the widget sets the arrow over itself, so the two fight (already a stage 3 item).
- `NSCursor` images are enlarged by macOS Accessibility "Pointer size". That breaks the Windows guarantee that "cursor = exact stroke size" (Windows draws its own cursor for exactly this reason).
- The eraser cursor at step 9-10 is 260-388 pt; verify the maximum cursor size.
- Fix: use cursor rects or `cursorUpdate`, or hide the system cursor and draw it in the overlay.
- Stage: 3 (Opus, together with H3).

**M8. `makeImage` per commit.** (Draw.swift:228, 235)
- The CGImage shares memory copy-on-write, so the next draw into the context copies the full bitmap. A new image also means a full texture upload.
- Memory is about 3 × (5120×2880×4 bytes) per 5K screen: layer backing, cache, and the copy-on-write copy.
- Fix: layer contents or IOSurface-backed cache.
- Stage: 3.

**M9. HotKeys cannot support custom shortcuts.** (HotKeys.swift:5-26)
- The `RegisterEventHotKey` status is ignored, the `EventHotKeyRef` is thrown away (so no unregister), and IDs are `handlers.count+1`, which will collide once removal exists.
- Stage 2 also needs to parse the AHK combo syntax (`^!+#`) if `[Hotkeys]` is to be 1:1 with Windows.
- Carbon hotkeys consume the key. Windows passes F8/F9 through to the front app (`~`); document this difference.
- Stage: 2 (Opus review).

**M10. The settings window can be visible but unclickable.** (main.swift:81-84)
- Opening settings turns drawing off, but turning drawing on while settings is open leaves the window under the overlay: visible but unclickable. Windows hides it and restores it after drawing.
- Stage: 2.

### LOW
- **L1.** `performKeyEquivalent` swallows every ⌘/⌃ key without checking `isOn` or key-window status, and ⌘⇧Z also undoes (Draw.swift:289-292, 665). Stage 3.
- **L2.** Pressing the right button mid-stroke replaces `live` without invalidating it, leaving ghost pixels (Draw.swift:484-496). `up()` drops the final mouseUp point (551). Stage 3.
- **L3.** The ⌥ eraser ring appears only after mouseDown; `flagsChanged` does not call `updateCursor` (693-696). A trackpad two-finger tap (secondary click) erases a dot (281). Stage 3.
- **L4.** Esc key-repeat or keyUp can reach the re-activated app (668, 385). Stage 3 verify.
- **L5.** Widget:
  - it flashes at (0,0) before being positioned (Widget.swift:172-179);
  - `moveToDefault` uses `NSScreen.main` (the key window's screen), not the primary screen (198);
  - the shadow is not invalidated after a scale change (163, 185);
  - it can be dragged under the menu bar or notch (133-137);
  - `lockFocus` icon tint is fixed at one resolution (11-17).
  
  Stages 2 and 4.
- **L6.** The ColorPicker binding round-trips through 8-bit sRGB on every set, so the colour panel's hue or brightness may jump near black or grey (SettingsWindow.swift:7-10). Verify; use local @State. Stage 2.
- **L7.** With no main menu, ⌘W, ⌘Q, ⌘C and ⌘V do not work in the settings window or colour panel. Focus is not handed back after settings closes. Save failure is silent: only the button label changes, while Windows shows a dialog (Settings.swift:152-155). Stage 2.
- **L8.** Rainbow arrowhead: the Mac continues the hue gradient; Windows uses the body's end colour (Draw.swift:593-601 with 100). Stage 3.
- **L9.** The Spotlight follow timer polls at 120 Hz permanently (battery), and window moves lag the hardware cursor (Spotlight.swift:66). Stage 4: a global `.mouseMoved` monitor or display link.
- **L10.** Swift 6 readiness: static mutable state (HotKeys.swift:5-6), Timer closures that will be @Sendable, and no @MainActor annotations. Swift 5 mode is fine today. Stage 6, or annotate @MainActor in stage 1.
- **L11.** Every settings change triggers `objectWillChange`, which runs `applySettings` for every subsystem, including widget `setFrame` and `orderFront` (main.swift:40-42, Widget.swift:182-190). Low.

---

## (b) Performance summary for 5K
In priority order: H4 (one line, big win), H5, M1, M8, M2. Also:
- The outer `drawOpacity` layer runs even at 100% (Draw.swift:252-253). It is only needed when the live item is an eraser.
- `rebuildCache` renders items that lie on other screens (226).
- The sRGB cache is colour-converted to P3 on every draw.

Recommended stage 3 direction (Opus): a CALayer-based surface.
- Cache = layer contents, set once per commit.
- Live stroke = a separate opaque layer or bitmap with `opacity = alpha`.
- Laser = its own layer, with pruning.

This makes invalidation nearly free. Because it changes what the Draw.swift split should look like, make the decision in the stage 1 design so the code is not split twice.

---

## (c) Architecture and testability
1. **Draw.swift (776 lines) mixes everything.** Suggested split:
   - InkModel: items, undo floor, commit, undo, clear. Pure, no AppKit.
   - Geometry: shapePoints, arrow, wave, snap45.
   - Renderer: `renderInk`, `renderLaser`, and one `renderScene(items, board, opacity, size, scale, now) -> CGImage`.
   - Surface: per-screen window and view.
   - Input state machine: stroke session.
   - KeyMap: keyCode table, reusable for the shortcuts picture.
   - Cursors, Badge, Laser.
2. **`Settings.shared` is read inside rendering code** (Draw.swift:252, 429-436, 681-684; Spotlight.swift:34; Widget.swift:33, 44, 79). Pass in value-type style snapshots instead; that is what makes deterministic tests possible.
3. **Duplicated state**: `widget.view.spotOn` / `drawOn` are mirrored by hand (main.swift:28, 66). Use a single AppState.
4. **Settings schema** is listed three times (properties, load, save) and will be four with reset. Make it table-driven (M3).
5. **Version** is duplicated (Settings.swift:9 vs Info.plist:18). The zip name `Focus-Draw-mac-$VERSION` (build.sh:13) does not match ROADMAP stage 7's `Focus-Draw-<버전>-mac.zip`. build.sh deletes the old build before compiling (15). Stage 1, Haiku.
6. **Turning SelfTest into a regression suite** (SelfTest.swift:12-69). Today it:
   - uses the real `NSScreen.screens[0]`;
   - reads the user's real settings.ini;
   - opens real windows and activates the app;
   - captures a wall-clock-timed badge ("50%" appears in draw-board.png depending on timing) and laser;
   - asserts nothing, and always exits 0.
   
   Plan:
   - a `--settings <path>` option or defaults-only mode;
   - an injected clock and a fixed virtual screen (e.g. 640×400 @1x);
   - golden images rendered offscreen through `renderScene`, one scene per feature: free, 5 shapes plus snap, rainbow free and shapes, translucent seam, eraser on board, undo, clear+undo, laser at fixed t, boards with alpha, cursor images, widget at 60/100/250%, ring frames;
   - comparison with a per-channel tolerance of about ±2 and a small pixel budget, because anti-aliasing differs between arm64, x86_64 and macOS versions;
   - diff PNGs on failure, `--update-goldens`, and exit code 1 on failure, so `build.sh --test` can fail;
   - model asserts: 31 strokes → floor, the 30 s rule with the fake clock, the H1 crash scenario, and an ini round-trip using a UTF-16 CRLF Windows fixture;
   - a separate event-routing smoke test that sends synthetic NSEvents through `window.sendEvent`, to cover InkView, `performKeyEquivalent` and keyUp.

---

## (d) Parity gaps vs the Windows README
| Gap | Stage |
|---|---|
| `[Hotkeys]` customisation, conflict rules, AHK combo format | 2 |
| `HideCursor` (crosshair); key is dropped on save today | 4 (research); keep the key in stage 1 |
| 1-9 and W/E/R colour/opacity editor; shortcuts picture; reset all; autostart (SMAppService — a translocated app must first be moved to /Applications); save-failure dialog; slider ±/number entry; "닫기" button | 2 |
| Settings window hidden while drawing, restored after | 2 |
| "처음 자리로" = always primary screen, bottom-right | 2 |
| Widget magnet to Dock edge | 4 |
| Exact-size cursor unaffected by pointer-size setting; arrow cursor over other windows (⌘⇧4/⌘⇧5, dialogs) and over the widget | 3 |
| Wheel up = darker | 3 |
| Rainbow arrowhead colour | 3 |
| Monitor hot-plug keeps ink | 3 (Mac can do better than Windows' "restart") |
| Tray shortcut icons (`ShowTrayIcons`) → status-item click toggles / on-state colour | 5 |
| Whiteboard touch: palm eraser, two-finger-tap undo, pen-back eraser, long-press suppression; macOS has no multitouch touchscreen API, so document it. Wacom eraser end via `pointingDeviceType` | 5 / 7 |
| Magnifier guidance → macOS Zoom | 5 |
| F8/F9 not passed through to the front app; README lines 126 vs 128 contradict each other on whether the board survives F9 (Mac keeps it) | 7 docs; confirm with the teacher |

---

## Proposed roadmap changes
1. **New stage 0.5 "hotfix" (Sonnet, 1 short session), so the teacher gets a safe classroom build now.** H1, H2, H4, the laserLive pruning, and an L1 guard, plus selftest scenes for each.
2. **Stage 1 design session (Opus) decides before the split:**
   - the stroke-session model;
   - the render surface (CPU bitmap vs CALayer);
   - the coordinate model;
   - the settings schema with ini round-trip (UTF-16/BOM, unknown keys, AHK hotkey syntax).
   
   Then Sonnet implements the split, the deterministic golden-image selftest and `build.sh --test`. Haiku handles version single-sourcing and build order.
3. **Split stage 3 into two Opus-led sessions:**
   - 3a: focus, activation and cursor spike (H3, M7, L1, L4), plus the fullscreen/Spaces test matrix: Keynote display-capture setting, PowerPoint, Preview, Zoom, screensaver, ⌘⇧4/⌘⇧5, sleep/wake.
   - 3b: performance and multi-monitor (H5, M1, M2, M5, M8), with a 5K timing budget checked by the selftest.
   
   Then Sonnet polish: M4, L2, L3, L8.
4. **Stage 2 additions:** HotKeys redesign (M9), main Edit menu (L7), settings hide/restore (M10), colour picker check (L6).
5. **Stage 4 additions:** event-driven spotlight follow (L9) and a lower idle widget level (M6).
6. **Stage 6 additions:** Swift 6 concurrency readiness (L10), memory checks with the `leaks` and `footprint` tools, and a long-session soak test (about 5,000 strokes plus 30 undos under a time limit).
7. **Stage 7:** fix the zip naming mismatch and document the F8/F9 pass-through difference.
