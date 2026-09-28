> 2026-09-28 로드맵 재점검 때 에이전트가 만든 원자료(영어). 사실 확인용 참고 자료이며, 결정의 기준은 mac/ROADMAP.md와 mac/design/stages.md다.

# macOS platform research for the Focus & Draw Mac port (as of 2026-09-28)

## 0. Current baseline

- **Current macOS:** macOS 27 "Golden Gate" came out on 2026-09-14. It runs only on Apple silicon, and it is the last release with full Rosetta. Tahoe 26.7 and Sequoia 15.8 shipped the same day. Tahoe 26 is the last macOS that supports Intel. ([Apple security releases](https://support.apple.com/en-us/100100), [Wikipedia: Golden Gate](https://en.wikipedia.org/wiki/MacOS_Golden_Gate), [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes))
- **Teacher's MacBook (checked locally):** macOS 15.7.3, Command Line Tools with the 26.1 SDK, Swift 6.2.1. `notarytool` and `stapler` are installed. `actool`, `ibtool` and `xcstringstool` are not.
  - So the only real-hardware test OS is Sequoia. Tahoe 26 and Golden Gate 27 need another Mac, or free macOS VMs (UTM) on the MacBook. A VM also gives the clean "first install" environment that stage 6 needs.
- **No release note for 26 or 27 mentions** Carbon hotkeys, NSEvent monitors, cursors, sharingType, Accessibility Zoom or SMAppService. The only Gatekeeper item is `spctl --purge`.

## 1. Hiding or replacing the cursor while another app is frontmost

**Feasibility.** There is no public API for this.
- While our app is active (during drawing), `NSCursor.hide`/`set` work normally.
- In focus mode our app is in the background. Hiding the cursor there needs the private `CGSSetConnectionProperty(_CGSDefaultConnection(), cid, "SetsCursorInBackground", true)` followed by `CGDisplayHideCursor`.
- This still works in current releases: Cursorcerer 4.1 (signed and notarized) says it supports Golden Gate, Tahoe and Sequoia.

**Gotchas**
- The window server never lets a background app hide the cursor over the Dock. Apple DTS confirmed this.
- Hide/show calls must stay balanced.
- On Tahoe 26.2 the cursor can come back after the full-screen menu bar is revealed. Deskflow had to hide it again, and the maintainers closed that PR because they did not want to rely on undocumented calls.
- The accessibility cursor-size setting belongs to the system (it is a user setting). Changing it would count as modifying system settings, so it is rejected.

**Recommendation for stage 4**
- Default: draw a crosshair or ring inside the spotlight window and leave the system arrow visible.
- Optional: an "experimental" toggle that uses the private API. Notarization is an automated malware scan, not App Review, so private API use does not block it.
- Tell users about the built-in alternative: Accessibility > Display > Pointer size, outline and fill colour.

Sources: [DTS thread](https://developer.apple.com/forums/thread/756199), [Cursorcerer](https://doomlaser.com/cursorcerer-hide-your-cursor-at-will/), [Deskflow PR 10184](https://github.com/deskflow/deskflow/pull/10184), [Notarization docs](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## 2. Overlays above full-screen apps and presentations

**Feasibility.** Mostly possible, but it has to be checked on real hardware.
- The proven setup is an accessory (LSUIElement) app with NSPanel windows that use `.nonactivatingPanel`. Our app is already an accessory app.
- A regular app's panels do *not* join another app's full-screen Space (measured on macOS 26 via `kCGWindowIsOnscreen`).
- Apple's documented behaviour for "floating windows and system overlays" is `.canJoinAllApplications` (macOS 13+). It keeps windows out of Stage Manager's layout and lets them join other apps' full-screen Spaces.
  - Apple says it is mutually exclusive with `.fullScreenAuxiliary`/`.fullScreenPrimary` for windows Stage Manager handles.
  - Our `EVERYWHERE` constant (`Spotlight.swift:10`) currently uses `.fullScreenAuxiliary + .stationary`.
  - One 2026 report found that `.stationary` stopped an overlay from appearing over full-screen video. Other projects use it without problems. The spike should test these combinations.

**Window level**
- Screen-saver level (our current level) is fine.
- Do **not** use `CGShieldingWindowLevel()`. At that level the overlay blocks system password and Touch ID sheets.

**Presentations**
- **Google Slides in a browser's full screen:** this is a normal full-screen Space, so the overlay should work.
- **Keynote:**
  - Old Keynote took over the display unless "Allow Mission Control… to use screen" was turned on.
  - Keynote 14's Settings only has General, Rulers and Auto-Correction, so that option appears to be gone.
  - Current Keynote has two play modes: Play > In Fullscreen and Play > In Window. "In Window" is a safe fallback.
  - Presentify says it works in Keynote's Presentation mode after "a simple setup step" but does not say what the step is.
- **PowerPoint slideshow:** no reliable information. It must be tested.

**Verifying without screenshots.** `CGWindowListCopyWindowInfo` returns onscreen status, layer and bounds without Screen Recording permission (only window titles need it). A `--diag` mode can log whether our overlay is onscreen while the teacher plays Keynote or PowerPoint, and Claude can read that log.

Sources: [canJoinAllApplications](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications), [classroom-widgets PR 162](https://github.com/tinkertanker/classroom-widgets/pull/162), [overlay regression report](https://github.com/yuki-f-saka/live-football-transcriber/issues/33), [shielding-level issue](https://github.com/vorssaint/vorssaint-utils/issues/1917), [Keynote play modes](https://support.apple.com/en-kg/guide/keynote/tan72233051/mac), [Keynote 14 settings](https://support.apple.com/lt-lt/guide/keynote/change-keynote-settings-on-mac-tan003125d0e/14.1/mac/1.0), [Presentify FAQ](https://presentifyapp.com/faq)

## 3. Keyboard input while drawing

**Current code**
- Turning drawing on calls `NSApp.activate(ignoringOtherApps: true)` and uses an ordinary `NSWindow` (`Draw.swift:196, 365`).
- Turning drawing off calls `previousApp.activate()` (`Draw.swift:385`).

**Platform facts**
- Since macOS 14, activation is cooperative. `activate()` is only a request, and a hand-back is supposed to use `yieldActivation(to:)` first. `activate(ignoringOtherApps:)` is formally deprecated in the macOS 27 SDK.
- If a password field or Terminal's Secure Keyboard Entry is active in another app, the hotkey handler still runs, but activating our app and `makeKeyAndOrderFront` silently fail. Apple calls this r.118404381 and says there is no workaround.
- Activating an accessory app over a full-screen Space can hide the menu bar (FB13544993).

**Option A: a non-activating key panel**
- NSPanel with `[.borderless, .nonactivatingPanel]` and `canBecomeKey = true`, and never call `NSApp.activate`.
- The other app stays frontmost, so the Space never switches and nothing has to be handed back.
- Cost: a non-active app cannot reliably set the cursor. `cursorUpdate` is not delivered, and `NSCursor.set/push` is reported to fail. That would lose our pen-dot cursor unless we hide the arrow with the private API from §1.

**Option B: keep activating (current behaviour)**
- Keep the current activation, but hand focus back with `yieldActivation(to:)` then `activate(from:)` on macOS 14+.
- Test whether activating switches Spaces in full-screen apps.

Decide between A and B in the stage-3 spike.

**Korean input**
- Reading `keyCode` (as `Draw.swift:658` does) is correct. Because we never call `interpretKeyEvents`, the input method never gets the keys.

**Presenter clickers**
- While drawing, the arrow and PageDown keys from a clicker come to us, not to Keynote.
- Passing them on needs synthesised events, which need Accessibility permission. Don't.

Sources: [activate()](https://developer.apple.com/documentation/appkit/nsapplication/activate()), [activate(from:options:)](https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(from:options:)), [secure input and activation thread](https://developer.apple.com/forums/thread/741701), [TN2150](https://developer.apple.com/library/archive/technotes/tn2150/_index.html), [FB13544993](https://github.com/feedback-assistant/reports/issues/457), [non-activating key panel design](https://github.com/tomada1114/hintjump/issues/44), [cursor in a non-active app](https://developer.apple.com/forums/thread/738051), [NonActivatingPanelIssue](https://github.com/PitNikola/NonActivatingPanelIssue)

## 4. Global hotkeys

**Carbon `RegisterEventHotKey`**
- It still works on 26 and 27, and it is still the only global-hotkey API that needs **no** permission. It has been deprecated on paper since 10.8.
- **macOS 15.0 and 15.1** rejected hotkeys whose only modifiers are Option or Option+Shift (error -9868). Apple relaxed this in 15.2.
- Plain F-keys were never affected.

**Gotchas**
- Tahoe's window server drops *synthesised* events before they reach Carbon hotkeys. Our SelfTest builds NSEvents inside the app and calls the handlers directly, so it is not affected. Keep it that way and never use `CGEventPost`.
- `HotKeys.swift:24` ignores the returned status. It should check it so the stage-2 shortcut field can show "rejected" (-9868) or "already in use by another app" (-9878).
- Rule for stage 2: require ⌘ or ⌃ in letter combinations. F-keys alone are fine.

**MacBook F-keys**
- By default F7, F8 and F9 are media keys. F8 without fn triggers play/pause (it can start the Music app) and never reaches us.
- Users can switch this in System Settings > Keyboard > Keyboard Shortcuts > Function Keys > "Use F1, F2, etc. keys as standard function keys".
- Keep ⌃⌥1 and ⌃⌥2, and explain this in the guide.

**Alternatives**
- `NSEvent` global key monitors need Accessibility. `CGEventTap` needs Input Monitoring.
- Both kinds of permission break on every ad-hoc rebuild (see §7), so avoid them.

Sources: [Sequoia hotkey thread](https://developer.apple.com/forums/thread/763878), [synthesised hotkeys on Tahoe](https://www.nick-liu.com/posts/tahoe-hotkey-dead-end/), [Carbon vs NSEvent](https://github.com/blackboardsh/electrobun/issues/334), [Apple function keys](https://support.apple.com/en-us/102439)

## 5. Global click monitoring for click rings

- `addGlobalMonitorForEvents` for mouse-down events needs **no** permission. Only key events need Accessibility. This matches our code and the pilot.
- Handlers never fire for events aimed at our own app, which is why the local monitor is also needed. The current code already has one.
- Tablet point and proximity events can also be watched globally.

Source: [NSEvent docs](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))

## 6. Launch at login (SMAppService.mainApp)

**Feasibility.** It works with an ad-hoc signature (verified by one project on macOS 26.6.2).
- The system keeps one login-item record per bundle ID, not per code hash, so the login item survives rebuilds.
- `register()` is subject to user approval. The user sees a "Login item added" notification and can turn it off in System Settings > General > Login Items without our app being told. Always read `.status`; never store a flag of our own.

**Gotchas**
- Reading `.status` from a *different copy* of the app (a dev build, or a copy made by the temp-folder build) moves the login item to that copy. Never touch SMAppService in `--selftest` or dev runs.
- If the app runs from Downloads, Gatekeeper's App Translocation gives it a random path. Detect `/AppTranslocation/` in the path and ask the user to move the app to Applications before registering.
- macOS 27 refuses LaunchAgent plists that carry the quarantine attribute. This only matters for a fallback path.

Sources: [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [ad-hoc findings, CreativeNotch PR 12](https://github.com/GcdZ03/CreativeNotch/pull/12)

## 7. Distribution without a paid account, then Developer ID

**Ad-hoc signed download on Sequoia, Tahoe and Golden Gate**
- Since 15.0, Control-click > Open no longer works.
- The user's steps:
  1. Launch the app and get the "Not Opened" dialog; click Done.
  2. Open System Settings > Privacy & Security > Open Anyway.
  3. Click Open again.
  4. Enter an **admin password**.
- Consequences:
  - Teachers on managed school Macs without admin rights, or under MDM policy, may not be able to open it at all.
  - **Every new version** downloaded goes through this again.
  - Homebrew stopped accepting casks that fail Gatekeeper on 2026-09-01 and removed `--no-quarantine`, so Homebrew is not an option either.

**Permission trap**
- macOS stores Accessibility, Input Monitoring and Screen Recording grants for an ad-hoc app against that exact build. Every update silently invalidates them.
- So avoid any permission-gated feature until the app is Developer ID signed. The other option is a stable self-signed certificate, which suits development only.

**Developer ID and notarization**
- Price: US$99 a year, about ₩129,000 in Korea.
- Fee waivers only go to nonprofits, accredited schools and government bodies, not to individuals. The school itself might apply.
- Build steps: `codesign --options runtime --timestamp`, then `xcrun notarytool submit --wait`, then `xcrun stapler staple`. All of this works with the Command Line Tools alone.
- Only the Account Holder can create the certificate, and the teacher must do the enrolment.
- After the membership lapses, users can still download, install and run apps already signed with Developer ID. New builds cannot be signed or notarized.

Sources: [Apple Gatekeeper news](https://developer.apple.com/news/?id=saqachfa), [Apple Open Anyway](https://support.apple.com/en-us/102445), [idownloadblog](https://www.idownloadblog.com/2024/08/07/apple-macos-sequoia-gatekeeper-change-install-unsigned-apps-mac/), [Homebrew 5.0](https://workbrew.com/blog/homebrew-5-0-0), [ad-hoc permission loss](https://github.com/tomada1114/macos-app-template/pull/82), [enrol and price](https://developer.apple.com/kr/programs/enroll/), [KRW price](https://www.threads.com/@seonggoos/post/DVKxujxjoEI), [fee waivers](https://developer.apple.com/kr/help/account/membership/fee-waivers), [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates), [notarytool in CLT](https://scriptingosx.com/2021/07/notarize-a-command-line-tool-with-notarytool/)

## 8. Pen, touch and trackpad

- **Wacom and Sidecar Apple Pencil:** they arrive as mouse events with a tablet subtype.
  - Read `pressure` only when `subtype == .tabletPoint`. A normal mouse reports 1.0, and a Force Touch trackpad reports click force.
  - Detect the eraser end from `pointingDeviceType` on proximity events.
  - Sidecar pressure is reported as uneven. Turn off mouse coalescing for smoother pen strokes.
- **New in macOS 27 and iPadOS 27:** Sidecar has much wider support for finger touch on Mac windows.
- **Interactive whiteboards:** macOS has no touchscreen or multi-touch support. A whiteboard connected to a Mac acts as a single-point absolute mouse, unless a driver is installed (UPDD is paid; Touch-Up is open source).
  - Plan for no two-finger-tap undo on whiteboards. Test with the school's real board.
- **Trackpad:** multi-finger taps **do not** need private MultitouchSupport while our window is under the pointer.
  - Pinch, rotate, swipe and smart-zoom events reach our view.
  - For raw touches, set `allowedTouchTypes = [.indirect]` and handle them in `touchesBegan`.
  - A two-finger tap is already a system right-click, which in our app means eraser. Any gesture mapping has to account for that.
  - Global (background) touch access would need the private framework.

Sources: [Sidecar](https://support.apple.com/en-us/102597), [Wacom NSEvents](https://developer-docs.wacom.com/docs/icbt/macos/ns-events/ns-events-basics/), [Sidecar pressure reports](https://forums.macrumors.com/threads/sidecar-how-come-no-one-mentions-pressure-sensitivity.2190465/), [UPDD / Promethean](https://support.prometheanworld.com/s/article/2858?language=en_US), [Touch-Up](https://github.com/shueber/Touch-Up), [trackpad touches](https://rymc.io/blog/2018/swipeable-nscollectionview/)

## 9. Accessibility Zoom and screen sharing

- **Accessibility Zoom:** it magnifies the finished screen image, so our overlays are magnified too, and our global coordinates should still line up. Zoom itself does not appear in screen recordings. Worth a visual check.
- **Screen sharing:** since macOS 15, ScreenCaptureKit captures every visible window whatever its `sharingType`.
  - So our overlays **will** appear when the teacher shares the **whole screen** in Zoom, Meet or Teams.
  - They will not appear when sharing a single app window.
  - We can't hide them from capture, and we don't want to.

Sources: [tauri issue 14200](https://github.com/tauri-apps/tauri/issues/14200), [Apple forum 792152](https://developer.apple.com/forums/thread/792152)

## 10. Building without Xcode, and CI

**swiftc build**
- `swiftc` with SwiftUI, AppKit and Carbon and `lipo` universal binaries works. Minimum macOS 13 is reasonable because SMAppService and `canJoinAllApplications` both need 13.
- Cost of that choice: 2017 MacBook Airs, which stop at macOS 12, are excluded.
- Guard APIs newer than 13 with `#available`, for example `activate()` and `yieldActivation` on 14+.
- Without Xcode there are no asset catalogs, Icon Composer icons, `.xcstrings` or previews.
- On Tahoe, an `.icns` that does not fill the rounded square gets a grey "squircle" frame. Use a full-bleed rounded-square artwork.
- Building against the 26 SDK gives Liquid Glass controls automatically. The opt-out key is expected to disappear with the 27 SDK.
- Keep the x86_64 slice: Intel Macs are supported up to Tahoe 26.

**GitHub Actions**
- Hosted runners are free for public repos. Labels: `macos-15`, `macos-26` (arm64, with Xcode, so `actool` is available), `macos-15-intel` and `macos-26-intel`.
- GitHub will drop Intel runners after macos-15 retires in autumn 2027.
- Signing and notarizing in CI would need the certificate and an App Store Connect API key stored as secrets. Keep it local until stage 8.

**Tahoe menu bar**
- Users can turn off our menu-bar icon under "Allow in the Menu Bar", and apps cannot detect that.
- Set `NSStatusItem.behavior = .removalAllowed` and watch it with KVO.
- Handle `applicationShouldHandleReopen` to show Settings, so the app can always be reached even with the widget and icon both hidden.

Sources: [GitHub runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [macos-26 image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md), [runner retirement notice](https://github.blog/changelog/2025-07-11-upcoming-changes-to-macos-hosted-runners-macos-latest-migration-and-xcode-support-policy-updates/), [squircle icons](https://lapcatsoftware.com/articles/2025/6/2.html), [Liquid Glass opt-out](https://www.donnywals.com/opting-your-app-out-of-the-liquid-glass-redesign-with-xcode-26/), [menu bar thread](https://developer.apple.com/forums/thread/788101)

## Top platform risks, in the order to test them early

1. **Overlay over presentations (make this a new stage-1 spike, run on Opus):** Keynote In Fullscreen and In Window, PowerPoint slideshow, Chrome and Safari full screen, a second display or projector, Stage Manager, and "Displays have separate Spaces".
   - Compare `.canJoinAllApplications` against `.fullScreenAuxiliary`, with and without `.stationary`, and NSPanel against NSWindow.
   - Log `kCGWindowIsOnscreen` in `--diag`. This affects the architecture of every window.
2. **How drawing mode gets keyboard focus (same spike):** a non-activating key panel versus activation plus hand-back. Measure Space switching, cursor control, the pen-dot cursor and the password-field case. This choice decides stage 3.
3. **Distribution friction:** admin password, repeating the steps on every update, managed Macs.
   - Test the stage-7 "Open Anyway" guide in a fresh VM on 15, 26 and 27.
   - Decide early whether stage 8 (₩129,000 a year) happens before a wide release.
4. **No permission-gated features while ad-hoc signed:** keep Carbon hotkeys, the mouse-only global monitor, and no key forwarding.
5. **Cursor hiding in focus mode:** make the private-API decision early (stage 4), with a crosshair fallback.
6. **OS coverage:** the only real device runs 15.7.3. Set up UTM VMs for 26 and 27 before stage 3.
7. **Whiteboards and pen input:** test with the school's actual board. Expect mouse-only input.
8. **Rendering speed on 5K and Retina displays** (stage 3): measure early. The current CoreGraphics transparency-layer redraw may need layer or GPU drawing.

## Effectively impossible with public APIs or without payment

- Hiding the cursor from the background, or over the Dock at all.
- Showing overlays over a presentation app that takes over the display. Old Keynote did this; current Keynote needs testing.
- Multi-finger gestures from touchscreens or whiteboards without a third-party driver.
- Global trackpad gestures while our window isn't under the pointer (private framework only).
- Forwarding clicker or arrow keys to Keynote while drawing without Accessibility permission.
- Hotkeys that fire under someone else's password field *and* get keyboard focus.
- Hiding overlays from screen capture on macOS 15+.
- Passing Gatekeeper on first open without Developer ID and notarization.
- Keeping Accessibility, Input Monitoring or Screen Recording grants across ad-hoc updates.

Files I read (nothing was modified):
- `mac/ROADMAP.md`
- `mac/build.sh`
- `mac/Info.plist`
- `mac/Sources/main.swift`
- `mac/Sources/Spotlight.swift`
- `mac/Sources/Draw.swift`
- `mac/Sources/HotKeys.swift`
- `mac/Sources/SelfTest.swift` (searched only)
