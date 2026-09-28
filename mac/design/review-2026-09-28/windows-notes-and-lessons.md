> 2026-09-28 로드맵 재점검 때 에이전트가 만든 원자료(영어). 사실 확인용 참고 자료이며, 결정의 기준은 mac/ROADMAP.md와 mac/design/stages.md다.

# Windows behaviours and lessons (from NOTES.md and focus-draw.ahk)

Findings are below, ranked by how much they matter for the Mac roadmap.

## (0) Where the current Mac pilot already differs from Windows
I checked the Mac pilot against the Windows rules below. These gaps are in the Mac code today:

1. **Keyboard focus (most important).** When drawing starts, `Draw.swift turnOn()` makes Focus & Draw the active app, so every key goes to it. On Windows the overlay never takes focus (ahk comments on `drawGui`: `+E0x8080000` NOACTIVATE, `OnDrawGuiMouseActivate` returns 3). Only the drawing keys are captured; everything else still reaches the front app. That is why Backspace was dropped (NOTES 09-16 item 4: it is PowerPoint's "previous slide"). With the current Mac design, a presentation clicker or arrow keys will not advance Keynote or PowerPoint while drawing is on. This needs an Opus design session (for example a non-activating panel plus an event tap that needs a macOS permission).
2. **Arrow head is hollow on Mac.** `arrowPoints` is only stroked. On Windows the head is a filled triangle (`DrawArrowGdip`; NOTES 09-18: "테두리만 그리면 화살표로 안 보인다").
3. **Settings window stays visible under the drawing layer.** Windows hides it when drawing starts and shows it again when drawing stops (`ToggleDraw`, `settingsHiddenByDraw`). The author calls "visible but not clickable" the most confusing state. The Mac only has the other half: opening settings turns drawing off.
4. **Save failure is silent.** Mac `Settings.save()` only writes a log line. Windows `SaveSettings` shows a dialog that says what to do and returns false.
5. **Saving deletes unknown keys.** `Settings.save()` rewrites the whole file, so `[Hotkeys]`, `HideCursor`, `ShowTrayIcons` and any future key are dropped. Windows `IniWrite` keeps them. This breaks the roadmap's "key names 1:1" goal.
6. **Widget position means different things.** Mac `WidgetX/Y` is measured from the bottom-left of the screen, in points. Windows measures from the top-left, in pixels. Same key names, different meaning.
7. **"처음 자리로" can land on the wrong screen.** `moveToDefault` uses `NSScreen.main`, the screen that has keyboard focus. That can be the projector. Windows always uses the primary screen.
8. **Step badge looks and sits differently.**
   - Mac: dark pill at +28/+14 from the cursor, with no flip at screen edges.
   - Windows: deliberately rebuilt to look like the Windows tooltip (white, 1px gray A0A0A0 border, radius 5, dark text), 22px down-right of the cursor centre, flips at screen edges (`ShowStepNumber`, NOTES 09-21).
9. **Brush circle does not match the line exactly.**
   - Mac cursor alpha ignores the overall drawing opacity (Draw Opacity). Windows uses per-colour alpha × Draw Opacity.
   - Mac uses an `NSCursor`. Windows found that cursors get scaled by the OS pointer-size setting (CursorBaseSize 80) and cannot be pixel-exact, so it uses a separate click-through window (`brushGui`). macOS has a Pointer size setting, so check this there. Also check a 384px eraser ring as a cursor image.
10. **⌥ +/- changes the eraser size without showing the eraser ring.** On Windows, +/- adjusts whichever tool's ring is visible (NOTES 09-21: "규칙이 눈에 보이는 상태와 일치").
11. **A click without moving leaves a dot and uses an undo step on Mac.** On Windows a plain click leaves nothing (`OnPointerDown` comment), and empty undo steps are skipped (`UndoDrawing`). Check whether the Mac behaviour is intended.
12. **Undo gets slower over a lesson.** Mac undo redraws every item since the last clear, on every screen (`rebuildCache`). Windows restores only the 32px bands that changed.
13. **Laser tails change colour.** Fading laser tails take the current pen colour; Windows stores the colour per laser stroke.
14. **Hotkeys.**
    - The result of `RegisterEventHotKey` is ignored, so a conflict with another app fails silently.
    - F8/F9 are swallowed on Mac. Windows passes them through to the front app (`RegisterHotkey` with `~`, after the 한글 F8 spell-check report on 09-28).
15. **Colour reading is looser.** Mac accepts values above 0xFFFFFF; Windows `ReadIniColor` checks the range and falls back to the default.
16. **README contradicts the code.** `README.md` line 128 says the board resets to transparent when drawing is toggled. Line 126 and the code say F9 keeps the board (`ToggleDraw` re-lays `boardColor`; only Esc and the widget button clear it). Line 128 is out of date and would mislead a port.

## (1) Behaviours and rules that are easy to miss

**What gets cleared, and what is only temporary**
- **Only the Delete key clears inside drawing mode.** Delete clears the ink but keeps drawing mode and the board.
- **F9 or a quick tray icon:** turns drawing off and keeps ink and board. Turning on again puts the board back *after* the ink layer is shown, so the board sits underneath.
- **Esc or the widget's draw button:** clears ink, removes the board, then turns off (`ExitDrawMode`, `ToggleDrawFromWidget`). The widget button only clears when turning *off*; turning on never clears.
- **Opening settings:** turns drawing off and keeps the ink.
- **Undo history:** dropped 30s after drawing is turned off (`UNDO_KEEP_MS`, `DiscardUndoHistory`). Turning drawing on within 30s cancels that, so an accidental Esc can still be undone.
- **Temporary values** reset every time drawing is toggled: colour, per-colour alpha (→ 100), pen step, eraser step, special pen (`ToggleDraw`). Settings values are never changed from inside drawing mode, so "Save" cannot freeze a value changed in the middle of a lesson.
- **Key 0** reads the *current* default colour at the moment it is pressed. Number keys also turn off the A/S special pens (`SetDrawColor`).
- **Board keys** read the board's current colour when pressed, not a copy made at start-up (`MakeBoardSetter` captures the index).

**Undo** (`PushUndo`, `CaptureUndoBands`, `TrimUndo`, `UndoDrawing`)
- One step = one stroke, one eraser pass, or one clear-all.
- Stored as 32px horizontal bands, only the bands that changed. A band is captured only the first time a stroke touches it.
- Limits: 30 steps and 80MB, whichever is hit first. A single remaining step is never dropped. Empty steps are skipped.
- Measured: one stroke 0.37MB (was 22MB), 12 steps 4.4MB.

**Drawing geometry** (`ArrowGeometry`, `WavePoints`, `ShapeOverhang`)
- Arrow head size = clamp(thickness×4, at least 14, at most half the length). Head half-width = head×0.45, about 48°. The body stops at the base of the head.
- Wave height = max(thickness×0.75, 3). Wave length = max(thickness×5.5, 18). Whole number of waves, points every 2px. Straight line if length < height.
- Ellipse uses 16–160 segments. Snap to 0/45/90° keeps the line length. Shift can be pressed in the middle of a drag.
- The amount a shape sticks out past its end points is computed in one function and used both for drawing and for undo/redraw bounds, so they cannot disagree.
- Pen steps grow ×1.3 per step, with one decimal kept (so steps 2 and 3 never round to the same size). Eraser steps grow ×1.5, whole pixels. Default step 5 for both (8.6px and 51px).

**Translucent ink** (`BeginInkStroke`, `InkCompose`)
- Each stroke is drawn opaque, then laid on top with the stroke's alpha. Overlaps inside one stroke do not darken; overlaps with other strokes show through (red + 50% blue = purple).
- The eraser overwrites and turns off smoothing; it must reset both afterwards.
- The empty background has alpha 1/255 so clicks do not fall through to the app below (`ClearBackBuffer`). The Mac already does this with 0.004.

**Laser pen (A)** (`LASER_*`, `LaserRender`, `LaserTick`)
- Stays 500ms, fades over 500ms, minimum width 8. Four layers: 3.0/0.16, 1.7/0.40, 0.75/1.0, 0.3/0.9 with 60% white.
- Tail width tapers to 0.08 + 0.92×life. Each layer is drawn opaque into a temporary layer, then composited (per-segment translucency looked like beads).
- Not recorded in undo. Drawn in its own layer.
- A laser dot stays at the cursor while the laser pen is selected.
- Laser shapes: every point is stamped with the current time during the drag, then the whole shape fades together after release. Wave points closer than 5px are skipped.
- The 16ms timer stops when there is nothing left to draw.

**Rainbow pen (S)** (`RAINBOW_*`, `DrawRainbowPolyline`)
- One full colour cycle per 700px. Colour carries over to the next stroke.
- Shapes are cut into 12px pieces. Preview always restarts from the shape's starting colour. The arrow head is filled with the body's final colour.

**Eraser**
- The ring is the board's complement colour (255 minus each channel): E board → EBB8D0; no board → black. 1px, fully opaque regardless of drawing opacity (`EraserRingColor`).
- Right-drag erases, but not if a left stroke is already in progress (`DrawPoll`).

**Touch and pen** (`OnPointerDown/Update/Up`, `EraserKind`, `IsWideContact`, `TwoFingerUndo`, `PrunePenContacts`)
- Touch and pen input is read directly; mouse input keeps the old path untouched ("더 좋아지거나 그대로").
- Touch-to-mouse conversion was measured at +46ms / 12px late.
- Eraser vs pen is decided **once, at first contact**, and kept for the whole stroke.
- Uses the pen's "inverted" and "eraser-end" flags; the side barrel button is deliberately ignored. If the device gives pen info, trust the flags and ignore contact size. If nothing can be read, treat it as pen.
- Wide-contact eraser threshold is 45 (0 turns it off), measured on the longer side (max of width and height), not area. Measured: pen 1–5, finger 6–38, hand edge 53–91.
- Hand-edge eraser width = the eraser setting × 2.0, a fixed factor (contact size changes every frame).
- Mouse input that follows a touch is ignored until the buttons are released, so strokes are not drawn twice and undo is not doubled.
- Long-press (which Windows turns into a right-click) can no longer erase.
- Two-finger undo:
  - fires once until all fingers lift;
  - if the first finger already left a mark, undoes that mark first;
  - blocked while erasing, and when the new contact is wide;
  - ghost contact IDs are pruned on each new contact.
- Shapes drawn by touch are redrawn every 10ms at the last position, not on every message (touch messages flood).
- Coordinates on secondary monitors can be negative and must be sign-extended.

**Pointer visuals** (`UpdateDrawCursorForWindow`, `UpdateCursorHiddenState`, `ClickAnimStepFor`)
- While drawing, the system cursor is hidden and a click-through circle window shows the exact line size.
- Over any other window (widget, screenshot tool) the normal arrow comes back. This state is read from the screen, never from a cached flag (a cached flag once got stuck).
- Highlight and click rings are hidden while drawing; one visibility function decides this.
- Click rings: ease-out cubic over 30 frames, interval = 41 − speed ms. Start radius = size/2 − thickness/2 − 1. Ring width never exceeds the radius; it fades below 1.5× thickness and stops below 1px.
- Right-click ring: off by default, blue 0020FF.
- Hide-cursor crosshair: 32×32, 2px arms, 1px thick. Cursors are restored on exit and reset at start-up, in case of a crash.

**Widget** (`OnWidgetMoving`, `SnapEdge`, `RaiseWidget`, `SaveWidgetPos`, `BuildWidget`)
- The widget is kept inside the monitor under the cursor, not the combined screen area (monitors of different sizes leave empty gaps).
- It can go over the taskbar. It snaps only to the taskbar's inner edge, within 15px, never to screen edges.
- Position is always recomputed as cursor minus grab offset, so snapping never builds up (this was the "won't let go" bug). The grab offset is re-set when the widget hits a wall, to avoid a rubber-band feel.
- The widget is raised again after every drawing toggle, and again 150ms later.
- Position is saved immediately on drop; a failed save is silent. "Reset position" goes to the computed default (primary screen, right −20, bottom −60) and saves it. The default is never stored in the defaults.
- Scale 60–250 (slider step 10); opacity floor 20%; text colour flips on dark backgrounds.

**Settings window** (`OpenSettingsWindow`, `AddSliderRow`)
- Changes apply live; they persist only on Save. Autorun and widget position apply immediately.
- Never always-on-top, so the highlight stays visible while tuning it.
- Slider steps: 5 for sizes and opacities, 10 for widget scale. A number typed into the box ignores the step. Typed numbers apply on Enter or when leaving the box.
- The save button shows "저장됨" only on success.
- Reset-all: asks first (No is the default), deletes the ini and reloads, keeps autorun, rebuilds the window, and explains if the file cannot be deleted.
- Autorun reads the real system state every time.
- Palette opacity floor is 5% (0% looks broken). Wheel changes opacity by 5% per step, only while drawing.

**Hotkeys** (`IsSafeHotkey`, `ChangeHotkey`, `RegisterHotkey`, `SetDrawModeHotkeys`)
- Global hotkeys must include Ctrl or Alt, or be (Shift+)F1–F24. The same combo cannot be used twice. If registration fails, the old combo is restored and a reason is shown. A bad ini value falls back to the default.
- The recorder control sends empty values while only modifiers are held (ignore them) and re-fires when set (guard against re-entry).
- Drawing-mode keys are active only while drawing is on. Z/X/C/A/S are also registered with Shift. Held keys are reset on every toggle. Ctrl+Z still works even though Z is a shape key.
- Badge shows even at the limit ("end reached"); lasts 500ms.

**Start-up and tray**
- The Ctrl+Alt+R reload key exists only when running from source.
- GDI+ is deliberately never shut down (doing so crashed on exit).
- Tray "off" icon colour follows the light/dark theme; "on" is 0A84FF.

**Touch diagnostic tool** (`터치펜-확인.ahk`)
- Full-screen window across all monitors.
- For each contact it shows: pointer type, whether pen info exists, pen flags (side button / inverted / eraser), contact width×height and longer side, position.
- Tracks the maximum number of simultaneous contacts (multitouch check), a 10px histogram of sizes, and counts per input kind.
- Suggests a threshold at the middle of the widest gap between observed sizes. If the gap is under 3, it recommends 0 (off).
- Esc writes `터치펜-확인-결과.txt` (UTF-8).
- The earlier version grouped results without contact size, which hid the signal.

## (2) Lessons in NOTES.md that should shape the Mac design
- **Feature filter:** "Does it draw attention to something on screen?" Timers, recording and capture-to-file are rejected. The cost of an app is what runs while idle; zero timers should run when nothing is on (NOTES 09-21, magnifier).
- **Never read the screen.** Screen capture causes the Win11 yellow border (and on macOS a recording indicator). Our overlays do appear in screenshots, which is a feature, and also a quick test: "not in a screenshot → not ours". Magnification is left to the OS magnifier, and ink magnifies correctly with it.
- **One path for each piece of state:** `SetWidgetVisible`, `UpdateSpotlightVisibility`, `UpdateCursorHiddenState`. Read real state instead of keeping a copy.
- **Thresholds need margin on both sides, measured on every class of input** (5 → 15 → 45 went wrong three times). A summary that looks too clean may be grouping on the wrong thing.
- **Fake input is not real input.** Injected events fail "physical" checks; synthetic pen input never arrived at the window. Always list what only the user can verify on real hardware.
- **Measure, do not guess:**
  - Frame rate is capped by the display refresh (64Hz); a faster timer does nothing. Update the screen at most once per frame.
  - Measure with timers, not tight loops.
  - On multiple monitors, keep the cursor on the screen you mean to test.
- **A bug report names one path; check all of them.** The hotkey path had the same widget bug as the click path.
- **When a fix only enforces a rule without finding the cause, write that down** (board raise in `SetBoardColor`).
- **Memory:** allocate full-screen buffers lazily and free them when drawing turns off. Compare against ZoomIt and SpotMouse; Focus & Draw idles at 14.3MB. Guard ticks against a toggle freeing buffers underneath them (`Critical`).
- **Look native.** Badges follow the OS tooltip style. The user decides colours; the app does not "fix" visibility, and the user rejected minimum sizes, alpha floors and outlines on the brush cursor.
- **New features that change what existing users see start off.** Legacy ini values are migrated so an update changes nothing on screen. Defaults are the author's tuned values, never machine-specific ones.
- **F8/F9 as defaults are marked "worth revisiting"** because they take over keys on other people's PCs.
- **Encoding:** never edit Korean text with perl. `.ps1` files and `읽어주세요.txt` need a UTF-8 BOM, and the txt also needs CRLF.
- **Privacy:** no school or PC names; noreply commit addresses.
- **Release:** the distributed `읽어주세요.txt` has a contact line that the repository copy lacks, so do not overwrite it. Update both the project exe and the distribution exe and compare hashes. Tags are plain (not annotated).
- **Roadmap hints for the Mac:** strokes are already kept as a list, so the planned 1.2 features (erase whole strokes with Ctrl+right-drag, patterned boards such as grid, English 4-line, Korean writing grid and music staff) are easier. Tap keys and hold keys must never overlap.

## (3) Author's preferences
- **NOTES.md**
  - Korean.
  - One dated line per change under "진행 로그", in the form "- YYYY-MM-DD: **bold summary** — why".
  - Sub-points for cause, fix, verification (with numbers and code blocks), 검증 함정 and **교훈**.
  - "(사용자 결정)" wherever the user decided.
  - Rollbacks and wrong conclusions are recorded honestly.
  - "다음에 할 일" is kept current, with finished items struck through and their outcome.
- **Code comments:** Korean, explaining *why*: the incident, measured values, the date, rejected alternatives, key rules in **bold**.
- **Commits:** English, imperative, plain wording about what the user sees, sometimes "X: details"; no prefixes (for example "Put the name on a card and tidy the drawing examples around it"). The user tests on real hardware (the classroom board) before committing.
- **User-facing tone:**
  - Polite Korean (합니다체) written for teachers.
  - Dialogs give the cause, a concrete next step, and reassurance ("끄기 전까지는 그대로 쓰실 수 있습니다"), with the technical detail last in parentheses.
  - Never show success after a failure. Explain every rejected input and restore the old value.
  - User-started actions never fail silently; background ones (start-up hotkey registration, widget position) stay silent.
  - Destructive or rare buttons are set apart and greyed (c999999).
  - Numbers shown as steps (1–10) and %, not pixels.
  - Grouping by purpose (the "포커스" tab); "드로잉", not "판서", in anything users see.
  - Checkbox labels are not clickable, to avoid accidental toggles.

Sources: `NOTES.md` (all 609 lines), `focus-draw.ahk` (all ~4,475 lines), `터치펜-확인.ahk`, `README.md`, and in `mac/Sources/`: `Settings.swift`, `Draw.swift`, `main.swift`, `Widget.swift`, `Spotlight.swift`, `SettingsWindow.swift`, `HotKeys.swift`. All under ``.
