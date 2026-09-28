> 2026-09-28 로드맵 재점검 때 에이전트가 만든 원자료(영어). 사실 확인용 참고 자료이며, 결정의 기준은 mac/ROADMAP.md와 mac/design/stages.md다.

# Critique of `mac/ROADMAP.md` (Mac port of Focus & Draw)

Sources read: `mac/ROADMAP.md`, `mac/README.md`, the root `README.md`, all of `mac/Sources/*.swift`, `mac/build.sh`, `mac/Info.plist`, `.gitignore` and `.git/config`. Every Bash call was rejected by the permission check, so I could not run `git diff`, `wc` or `grep`. The git findings below come from the harness's git-status snapshot and from `.git/config`.

## Summary

The plan has good bones. It has the Opus → Sonnet → Haiku pattern, "don't read the whole ahk", selftest as eyes and a progress log. Its main weaknesses:

1. It back-loads the riskiest unknowns: Keynote/PowerPoint full screen, focus activation, whiteboard touch, cursor hiding, 5K performance.
2. It puts a generic refactor first, before the real dependencies are known.
3. It has no early feedback loop with colleague teachers.
4. It carries a live git hazard (Korean filenames split into two Unicode forms) that a "Haiku commits" session would trip over.

## Critique points

**1. [High] Riskiest unknowns are back-loaded.**
- Stages 3–5 hold everything that could invalidate earlier work:
  - Keynote and PowerPoint full-screen slideshows: is the overlay visible, and do keys reach it?
  - Activation: `NSApp.activate(ignoringOtherApps:)` is deprecated in macOS 14 and activation became cooperative.
  - Whiteboard touch.
  - Cursor-hide feasibility, which the Stage 2 settings UI already reserves a slot for.
  - 5K performance, which may trigger a GPU rewrite after Stage 1 has already split `Draw.swift`.
- **Fix:** add a "classroom risk check" stage right after housekeeping. Opus writes the probes, the teacher runs them on real hardware for 30–45 minutes, and the results go into `mac/SPIKES.md` with a decision per item. Re-rank the later stages from those results.

**2. [High] Git hazard: Korean filenames exist in two Unicode forms, plus uncommitted edits to Windows files, plus "Haiku commits".**
- Evidence from the git snapshot:
  - Tracked files are stored in composed Korean (NFC) and show up again as untracked copies in decomposed Korean (NFD). This affects `읽어주세요.txt`, `터치펜-확인.ahk`, `소개자료/` and `배포용/`.
  - `배포용/` and `터치펜-확인-결과.txt` appear as untracked even though `.gitignore` lists them. The NFC ignore patterns don't match the NFD names on disk.
  - `.git/config` was made on Windows and has no `core.precomposeunicode` setting. There is no `~/.gitconfig`.
  - Three Windows files are also modified but uncommitted: `소개자료/build.ps1`, `읽어주세요.txt`, `터치펜-확인.ahk`.
- What goes wrong: a `git add -A` would commit duplicate paths (Windows would then see two files with identical-looking names), the distribution folder, and Windows edits nobody reviewed.
- **Fix, as Stage 0 with the teacher's OK:**
  - Run `git config core.precomposeunicode true` in this repo.
  - Have the teacher decide what to do with the three modified Windows files.
  - Rule in `CLAUDE.md`: "stage only `mac/**` or files named explicitly; never `add -A` or `add .`; run `git status` before every commit".

**3. [Medium] The repo, including `.git`, lives in OneDrive and is synced between the Windows PC and the Mac.**
- The codesign/extended-attribute problem is already one symptom.
- Two machines writing the same `.git` through OneDrive risks corrupted indexes and packs and "conflict copy" files.
- **Fix:** never work on both machines at once, and wait for OneDrive to finish syncing. Better: make a separate Mac clone outside OneDrive and use GitHub push/pull as the sync channel (Claude can do the one-time setup). Optionally move `mac/build` output out of the synced folder.

**4. [High] Whiteboard/touch parity is missing.**
- On Windows it is a first-class feature: palm eraser, two-finger-tap undo, contact-size thresholds, the `터치펜-확인` tool. The README's pitch is "works the same on any board".
- The Mac plan only has a trackpad gesture in the optional Stage 5.
- macOS most likely treats a USB touch board as a single-pointer mouse. There is no public contact-size or multi-touch API for touchscreens (trackpad `NSTouch` doesn't apply), and some boards need third-party drivers.
- **Fix:** add a spike: connect the Mac to a real classroom board. Does touch draw? Do widget taps work? Is there any multi-touch? Record it in the parity table. If it's impossible, say so plainly in `mac/README`, and suggest the Mac alternatives: the widget draw button, ⌘Z, `delete`.

**5. [High] Done-criteria can't be tested or assigned.**
- "Checked after the teacher tries it", "one lesson without problems" and "all items exist" have no steps, no expected results, and no record of which Mac or macOS version was used.
- **Fix:** each stage gets three lists:
  - (a) Claude-verifiable: build, selftest with golden images, text assertions, exit code.
  - (b) Teacher checklist: at most 15 steps / 15 minutes, each with its expected result, run on the MacBook with a projector.
  - (c) Beta-verifiable items.
- The progress-log line records Mac model, macOS version, pass/fail and the commit hash. Keep "one real lesson" only as the final sign-off of the reliability stage.

**6. [Medium-High] Stage 1 is generic and misses what later stages actually need.**
- Current gaps that later stages depend on:
  - `HotKeys.swift` can't unregister, uses handler ids based on a count, and ignores the `RegisterEventHotKey` return value. Hotkey rebinding and conflict reporting need a refactor.
  - `Settings.save()` rewrites only the keys it knows, which silently drops unknown or Windows-only keys. There is no schema or version key, so later migrations have nothing to work from.
  - `SelfTest` calls `DrawController.down/drag/keyDown` directly. It bypasses `InkView`, NSEvent routing, key-window status and activation, which are exactly the parts that break in class.
  - `APP_VERSION` is hardcoded in `Settings.swift`.
- **Fix:** re-scope Stage 1 after the spikes:
  - Hotkey registry: register, unregister, report failures.
  - Settings: keep unknown keys, add `[Meta] Version=`, test that save → load gives back the same values.
  - A single version source (`Info.plist`).
  - A small rolling log file.
  - Selftest events sent through `InkView`/NSEvent.
  - Split `Draw.swift` only along the renderer/controller line, and only if a performance fix needs it.

**7. [Medium-High] Golden-image regression, as written, will be flaky.**
- Selftest draws on the real `NSScreen.screens[0]` at its backing scale. That changes with a projector attached and between Retina and non-Retina screens.
- The laser, rainbow and badge depend on the clock. Anti-aliasing may differ between macOS versions.
- Full-screen PNGs at 2x also bloat the OneDrive-synced repo.
- **Fix:**
  - Render `renderInk` into an offscreen canvas of fixed size (for example 800×600, at 1x and 2x), with an injected clock.
  - Compare with a per-pixel tolerance and a maximum percentage of differing pixels.
  - Print a text summary (for example "2 scenes changed: …"). Claude opens only the changed PNGs, which saves image tokens.
  - Store small reference images in `mac/Tests/golden/`. Update them only with `--update-golden` after the teacher has looked at them.
  - Add assertions that don't need images: undo floor, settings round-trip, pen/eraser px table equal to the README table.

**8. [Medium] "Haiku for build and commit" probably doesn't save money.**
- Prompt caches are per model. Switching models mid-session makes the new model re-read the whole context without cache, while the build command itself costs almost nothing.
- **Fix:** the model that implemented a stage also builds, tests and commits at the end.
- Use Haiku only for fresh, self-contained chore sessions that follow a script: release packaging, typo and link fixes, version bumps.
- Opus reviews should cover only that stage's diff, and only for architecture or risk stages, not every stage.

**9. [Medium] Context hygiene gaps.**
- There is no `CLAUDE.md`, which Claude loads automatically at the start of every session.
- The ROADMAP will keep growing with "design memos", yet every session reads it first.
- `NOTES.md` (about 155KB) isn't marked off-limits.
- The root README (about 290 lines) is the real spec, and is much cheaper to read than the ahk.
- **Fix:**
  - Add a short root `CLAUDE.md` with a "Mac work" section: allowed paths, never read `focus-draw.ahk` or `NOTES.md` whole (targeted grep only), build/test commands, commit rules.
  - Put design memos in `mac/design/stage-N.md`.
  - Keep the ROADMAP under about 150 lines and move finished stages to `mac/HISTORY.md`.
  - Use `/clear` between sub-tasks.

**10. [Medium] Stages are mis-sized, and "one stage = one session" contradicts "2–3 sessions".**
- Stage 3 bundles full screen, multiple displays, a possible GPU rewrite, undo rules, cursor details and sleep/wake.
- Stage 2 bundles General settings, 12 color rows, a hotkey recorder and a keyboard-diagram image.
- **Fix:** sub-stages of at most about 5 checkboxes, one session each. Each ends with a handoff line ("next session: start at X"). The GPU work happens only behind a measured trigger, for example "long highlighter stroke visibly lags on display Y".

**11. [Medium] The feedback loop with colleague teachers starts only at Stage 7.**
- **Fix:** send a pre-release to 3–5 beta teachers right after the reliability stage.
  - A Korean feedback form or GitHub issue template.
  - A menu-bar item "진단 정보 복사" that copies version, macOS, Mac model, displays and settings.
  - A small log file plus the crash-report location (`~/Library/Logs/DiagnosticReports`).
- This also replaces the unrealistic OS test matrix (see point 15).

**12. [Medium] Signing is treated as a late optional stage, but it shapes design now.**
- On macOS 15+, "Open Anyway" needs a trip to System Settings and an admin password. Colleagues on school-managed Macs may be blocked entirely.
- An ad-hoc signature changes with every build. Any permission the app ever needs (Accessibility, Input Monitoring, Screen Recording) would be asked again after every update.
- A login item (`SMAppService`) and App Translocation (the app run straight from Downloads) are also affected.
- **Fix:**
  - Design principle: "no permission prompts" while the app is unsigned.
  - Detect translocation at launch and tell the user to move the app to Applications.
  - Make "$99 Developer ID?" a decision point after beta 1, based on how many testers got stuck.

**13. [Medium] Release and versioning pitfalls.**
- Stage 9 ties the Mac version number to the Windows one. That couples two codebases that move at different speeds.
- The Windows README uses `releases/latest`. A Mac-only release marked "latest" would break the Windows download link.
- **Fix:**
  - Independent tags: `v1.x` for Windows, `mac-v0.x` then `mac-v1.x` for Mac.
  - Tag and pre-release a zip at the end of every Mac stage, which also gives a rollback before class.
  - Always untick "Set as latest" on Mac-only releases.
  - The Mac section of the README links to the Mac release page.
  - The parity table records which Windows version a Mac release matches.

**14. [Medium] The Windows-vs-Mac difference list already exists in two copies and will drift.**
- It is in the ROADMAP and in `mac/README`; the root README and `읽어주세요.txt` would add more copies later.
- **Fix:**
  - `mac/PARITY.md` becomes the single source: one row per user-visible Windows behavior, with Mac status (done / planned stage / different by design / impossible, with reason) and how it is tested.
  - `mac/README` summarizes it and links to it.
  - Every stage's done-criteria include "PARITY and mac/README updated".

**15. [Medium] The OS test matrix is unrealistic for a teacher.**
- The plan asks the teacher to test on macOS 13, 14, 15 and 26.
- macOS 27 is probably shipping around now (please verify), and 26 is the last release for Intel Macs.
- **Fix:**
  - `-target macos13` already catches newer-API misuse at compile time.
  - Claude can smoke-test the Intel half of the app under Rosetta: `arch -x86_64 …/FocusDraw --selftest` on Apple Silicon.
  - Real OS coverage comes from beta teachers, recording model and OS.
  - Decide explicitly whether to keep macOS 13 as the minimum if nobody can test it.

**16. [Medium] 1:1 `[Hotkeys]` parity in Stage 1 hides a design decision.**
- Open questions: key-string format (AHK `^!1` or a readable `Ctrl+Alt+1`, and F-keys); physical key position or typed character; Windows-only and Mac-only keys.
- Hotkeys also behave differently: Windows passes F8/F9 through to the front app, while Carbon hotkeys on Mac swallow them.
- **Fix:** move `[Hotkeys]` to the hotkey sub-stage. Opus defines the format in a design memo, and the pass-through difference gets a parity row.

**17. [Low-Medium] macOS accessibility and system settings interactions are missing.**
- Pointer size (Accessibility → Display) may scale the custom draw cursor so it no longer matches the stroke width. The Windows version fixed this exact problem by drawing its own cursor.
- Also: Reduce Motion for click rings, VoiceOver labels on widget buttons, and the notch on MacBooks hiding the menu-bar icon when there are many status items.
- Screen sharing (Zoom/Meet) and AirPlay mirroring are untested.
- **Fix:** add these to the spike list and the classroom checklist. Add `accessibilityLabel` to the widget buttons and a first-run hint ("the icon is in the menu bar; the widget is bottom-right").

**18. [Low-Medium] Performance and energy are unmeasured.**
- The spotlight polls the mouse at 120 Hz even when it isn't moving.
- For a long semi-transparent or rainbow stroke, every drag event invalidates and re-renders the whole stroke inside a transparency layer. The cost grows with the square of the stroke length.
- `makeImage` copies a full-screen bitmap on each commit.
- **Fix:** measure in the spike: CPU % in Activity Monitor at idle, with the spotlight on, and during long highlighter strokes on the largest display. Then set numeric thresholds as done-criteria.

**19. [Low] Over-scoped or low-value items.**
- Splitting `Draw.swift` as a goal in itself.
- A keyboard-diagram PNG made from HTML: Claude can't screenshot here. Build it as a native SwiftUI view that shows the current 13 colors live.
- A placeholder "hide cursor" UI before feasibility is known.
- Pressure/Sidecar and trackpad gestures: note that a two-finger click is right-click on Mac, which already means eraser.
- Menu-bar icon color: trivial, fold it into the settings stage.
- A GPU rewrite without measurements.

**20. [Low] Decisions to state explicitly.**
- Korean only: no Localizable.strings, English out of scope.
- Rule: Mac sessions touch only `mac/**`. The docs stage may also edit specific lines of the root `README.md`, `읽어주세요.txt` and one slide in `소개자료/`. Never touch `focus-draw.ahk` or `NOTES.md`.
- Keep the existing "don't change both versions in one session" rule.
- Add uninstall instructions: delete the app, `~/Library/Application Support/Focus & Draw`, and the login item.

## Proposed stage list

Each stage lists model, sessions, who verifies, and the goal.

0. **Housekeeping** (Sonnet, 1 short session; teacher approves the git config)
   - Fix the Korean filename handling in git and settle the modified Windows files.
   - Add `CLAUDE.md` with session rules; commit the ROADMAP.
   - Tag `mac-0.1`. Optionally move to a separate Mac clone outside OneDrive.
1. **Classroom risk check** (Opus at high effort, 1 session + 45 minutes of teacher hands-on)
   - Probe: Keynote/PPT full screen and key focus, activation on the current macOS, projector hot-plug, whiteboard touch, 5K/long-stroke performance, cursor-hide feasibility, pointer-size cursor, screen sharing.
   - Output: `mac/SPIKES.md` with a decision for each.
2. **Parity table and backlog** (Sonnet, 1 session)
   - Build `mac/PARITY.md` from the root README plus the spike results; this becomes the single difference table and the backlog.
3. **Foundations** (Opus design memo → Sonnet, 1–2 sessions)
   - Hotkey registry (unregister, report failures).
   - Settings: keep unknown keys, schema version, round-trip test.
   - Single version source, log file, "진단 정보 복사" menu item.
   - Selftest routed through real NSEvents.
   - Split the renderer/controller only if the spikes call for it.
4. **Deterministic self-test** (Sonnet, 1 session)
   - Offscreen fixed-size golden images with tolerance, fixed clock, text assertions.
   - `build.sh --test` with a non-zero exit on failure, plus a Rosetta Intel run.
5. **Classroom reliability** (Sonnet; Opus only for unexplained bugs; 1–2 sessions)
   - Full screen and Spaces, multiple displays and hot-plug, sleep/wake, return to the previous app, cursor details.
   - Performance fix only if the measured trigger is met.
   - Pass the 15-item checklist, then one real lesson.
6. **Beta 1 to 3–5 colleagues** (Sonnet for the guide; packaging by the same model or a fresh Haiku session; 1 session)
   - `mac-v0.2` pre-release (not "latest"), Korean install/uninstall guide, feedback form.
   - Decision point: buy Developer ID?
7. **Settings window completeness** (Sonnet with Opus review of the hotkey format; 2 sessions)
   - 7a: General tab (login item, reset, version/diagnostics), key and board color list, menu-bar state icon.
   - 7b: hotkey recorder with conflicts shown, `[Hotkeys]` format, native keyboard-help view.
8. **Focus completeness** (Sonnet; Opus only if the Stage 1 cursor spike left it open; 1 session)
   - Cursor hiding as decided in the spike, Dock magnet, spotlight lag and energy.
9. **Touch and Mac extras** (optional, only what the spikes showed is feasible; 1 session)
   - Whiteboard as a pointer, stylus pressure, macOS Zoom guide.
10. **Stabilization and beta 2** (Opus reviewing the diff since the last review, 1 session)
    - Triage beta feedback, test a clean install on a new user account, fix or document the results.
11. **Signing and notarization** (only if decided in Stage 6; Opus once, then a scripted release session)
12. **Mac 1.0 release and docs sync** (Sonnet for text, scripted packaging)
    - Two-way README entry point, a Mac section in `읽어주세요.txt`, `mac-v1.0.0`, parity table final.
13. **Ongoing maintenance rules** (no session)
    - How a feature moves from one version to the other (parity row first), release checklist, tag per release.
