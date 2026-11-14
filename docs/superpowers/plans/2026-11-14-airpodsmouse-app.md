# AirPodsMouse « vraie appli » — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn AirPodsMouse into a polished, self-installing SwiftUI menu-bar app (onboarding, settings, dwell click, icon, DMG) while keeping the validated pointer engine unchanged.

**Architecture:** Swift Package with three targets: `AirPodsMouseCore` (pure logic: `PointerEngine`, `DwellClicker`, click presets, CSV replay), `AirPodsMouse` (SwiftUI app + AppKit/CoreMotion services, observable `AppModel`), `AirPodsMouseChecks` (executable test runner — no XCTest/Testing with Command Line Tools). Scripts assemble a signed universal `.app` and a `.dmg`.

**Tech Stack:** Swift 6.2 toolchain (language mode 5), SwiftUI (macOS 14: `MenuBarExtra`, `Window`, `Settings`-style `NavigationSplitView`), CoreMotion `CMHeadphoneMotionManager`, CoreGraphics events, `SMAppService`, `hdiutil`, `iconutil`, `lipo`, `codesign`.

**Spec:** `docs/superpowers/specs/2026-11-14-airpodsmouse-app-design.md`

## Global Constraints

- macOS 14.0 minimum (`LSMinimumSystemVersion` 14.0).
- Bundle id stays `local.airpodsmouse`; app name `AirPodsMouse`; UserDefaults keys stay (`sensitivity`, `invertX`, `invertY`, `nodClick`, `tiltClick`, `vAxis`, `settingsVersion`=3) — existing users keep settings + Accessibility grant.
- Sign every build with identity `AirPodsMouse Dev` (fallback ad-hoc + warning).
- `PointerEngine` behaviour must not change: replay of `Tests/Fixtures/motion2.csv` → exactly 5 left clicks in phase `click`, 0 elsewhere; `motion1.csv` → 0 clicks outside phase `click`.
- Languages: French (development region) + English; all user-facing strings through `Localizable.strings` in `Contents/Resources/{fr,en}.lproj` (Bundle.main — no SwiftPM resource bundle).
- Hotkeys: ⌃⌥P pause, ⌃⌥C calibrate, ⌃⌥Q quit, ⌃⌥V open Settings.
- Sensor restart only after 45 s of silence (shorter restarts kill a starting stream — measured).
- Never publish to GitHub in this plan (license of original author unresolved).

## Review Focus

1. **AirPods disconnect / taken out mid-use** → cursor stops immediately (no drift from pending motion), status says so, recovers on reconnect. *(Task 3 check: `CursorController` drops pending when samples are > 0.3 s old.)*
2. **Dwell click while the real trackpad is used** → never clicks. *(Task 2 check `dwellIgnoresRealMouse`.)*
3. **Head held still on one spot** → one dwell click, not a burst. *(Task 2 check `dwellNoRepeatWithoutMove`.)*
4. **Accessibility revoked while running** → no crash, no events posted, Settings › Général and menu show the fix button. *(Task 3: `AppModel.axTrusted` polled each second; `CursorController.post` guarded.)*
5. **No compatible AirPods / motion unavailable** → onboarding step 2 explains and offers “Continuer quand même”; app never hangs. *(Task 5 manual check.)*

---

### Task 1: Package skeleton, core library, regression checks

**Files:**
- Create: `Package.swift`, `Sources/AirPodsMouseCore/PointerEngine.swift` (= current `Pointer.swift`, `public` API), `Sources/AirPodsMouseCore/Replay.swift`, `Sources/AirPodsMouseChecks/main.swift`, `Tests/Fixtures/motion1.csv`, `Tests/Fixtures/motion2.csv`
- Delete: `Pointer.swift`, `tools/replay/`

**Interfaces — Produces:**
- `public struct PointerEngine` with existing members made `public` (`sensitivity, verticalRatio, invertX, invertY, nodClick, tiltClick, axis, step(w:g:dt:t:) -> PointerOutput, rates(w:g:), axes(g:), reset()`), `public struct PointerOutput { dx, dy, click: ClickKind? }`, `public enum ClickKind { case left, right }`, `public typealias V3`.
- `public struct ReplayResult { public var clicksByPhase: [String: [Double]] }` ; `public func replay(csv: String, engine: PointerEngine) -> ReplayResult` (uses `ts` column when present, else uniform spacing — same as old tool).
- Checks runner: `check(_ name: String, _ cond: Bool)`; exits 1 if any failed, prints `✅/❌ name`.

- [ ] Step 1: Write checks `replayMotion2FiveClicks` (`clicksByPhase["click"].count == 5`, all other phases empty) and `replayMotion1NoFalseClicks` (all phases except `click` empty).
- [ ] Step 2: `swift run AirPodsMouseChecks` → FAIL (targets missing).
- [ ] Step 3: Create Package (`swift-tools-version: 6.0`, `swiftLanguageModes: [.v5]`, platforms `.macOS(.v14)`), move engine, implement `replay`.
- [ ] Step 4: `swift run AirPodsMouseChecks` → all ✅.
- [ ] Step 5: Commit `feat: Swift package with core pointer engine and replay checks`.

### Task 2: Click presets and dwell click

**Files:** Create `Sources/AirPodsMouseCore/ClickPresets.swift`, `Sources/AirPodsMouseCore/DwellClicker.swift`; Modify `PointerEngine.swift` (expose `nodPreset`), checks `main.swift`.

**Interfaces — Produces:**
- `public enum NodPreset: Int, CaseIterable { case careful, normal, easy }` with `threshold` (0.85 / 0.65 / 0.5 rad/s) and `maxTotal` (0.4 / 0.5 / 0.6 s); `PointerEngine.nodPreset` (default `.normal` = today's values) applied to its nod `FlickDetector`.
- `public struct DwellClicker { public var delay: Double /*0.6…2.0, default 1.0*/; public var radius = 6.0; public var rearmDistance = 40.0; public mutating func update(cursor: CGPoint, t: Double, realMouseMoved: Bool) -> (progress: Double, fire: Bool) ; public mutating func reset() }` — progress 0…1 for the ring; fires once when cursor stays within `radius` for `delay`, then needs `rearmDistance` of movement before arming again; `realMouseMoved` resets.

- [ ] Step 1: Checks: `presetNormalMatchesReplay` (normal → motion2 still 5 clicks), `presetCarefulNoMoreClicks` (careful ≤ normal on both files, 0 false), `dwellFiresOnce` (still 1.0 s at delay 1.0 → exactly one fire, progress reaches 1), `dwellNoRepeatWithoutMove` (still 5 s → 1 fire), `dwellRearmsAfterMove` (still, move 50 px, still → 2 fires), `dwellIgnoresRealMouse` (realMouseMoved true every frame → 0 fires), `dwellJitterTolerated` (±3 px noise → fires).
- [ ] Step 2: Run → FAIL. Step 3: implement. Step 4: Run → ✅. Step 5: Commit `feat: nod presets and dwell clicker`.

### Task 3: App services and model (no UI yet)

**Files:** Create in `Sources/AirPodsMouse/`: `Log.swift`, `AudioOutput.swift`, `HotKeys.swift`, `Permissions.swift`, `MotionService.swift`, `CursorController.swift`, `AppModel.swift`, `App.swift` (temporary minimal `MenuBarExtra`). Port logic from current `main.swift` (then delete `main.swift`).

**Interfaces — Produces:**
- `@MainActor final class AppModel: ObservableObject` — `@Published` `status: Status` (`.searching, .active, .noMotion(hint: String), .paused, .motionDenied, .unavailable`), `axTrusted`, `motionAuth`, `isPaused`, `dwellProgress: Double`, `lastClickAt: Date?`; settings as `@Published` mirrored to UserDefaults (`sensitivity, verticalRatio, invertX, invertY, nodClick, nodPreset, dwellEnabled, dwellDelay, tiltClick, launchAtLogin, onboardingDone`); actions `togglePause(), startCalibration(), resetSettings(), openAccessibilitySettings(), requestMotion(), routeAudioToAirPods()`; `static let shared`.
- `MotionService`: `onSample: (CMDeviceMotion) -> Void`, `start()`, health per 1 s timer (restart only after 45 s silence), connect/disconnect callbacks (no restart on connect).
- `CursorController`: `add(dx:dy:)`, `tick()` at 120 Hz (35 % catch-up, drop pending if last sample > 0.3 s), `click(right:)` with double-click clickState window `max(NSEvent.doubleClickInterval, 0.9)`, `syncWithRealMouse() -> Bool` (returns true when real mouse moved), multi-screen clamp.
- `Permissions`: `axTrusted()`, `promptAX()`, `motionStatus()`.

- [ ] Step 1: Build `swift build` → succeeds; checks still ✅.
- [ ] Step 2: Run unbundled? No — assemble with Task 8 script early: add minimal `scripts/build-app.sh` now (arm64 only) and verify log shows `✅ Actif` and cursor moves (cursor sampler: >100 px extent while user moves head).
- [ ] Step 3: Commit `feat: app model and services ported to package`.

### Task 4: Menu bar and Settings window

**Files:** `Views/MenuBarContent.swift`, `Views/Settings/SettingsView.swift`, `GeneralPane.swift`, `PointerPane.swift`, `ClickPane.swift`, `AboutPane.swift`; `App.swift`.

- Menu: status line, Pause toggle, “Clic automatique” toggle, “Réglages…”, “Quitter”. Icon: SF Symbols `airpodspro` / `exclamationmark.triangle` / `pause.circle`.
- Settings: `Window(id: "settings")` with `NavigationSplitView` sidebar (Général, Pointeur, Clic, Essai, À propos), `Form` + `.formStyle(.grouped)`. General shows live status rows (AirPods, Mouvements, Accessibilité) with fix buttons, “Ouvrir au démarrage” (`SMAppService.mainApp`). Pointer: Slider vitesse 0.3–3 (×1.2 steps shown as %), vertical ratio 1.5–3.5, invert toggles, Recalibrer, Réinitialiser. Clic: nod toggle + segmented preset, dwell toggle + delay slider 0.6–2 s, tilt right-click toggle. About: version, GitHub link, Vue 3D, Journal, Revoir l'accueil.
- Reopen (double-click app while running) → opens Settings; activation policy `.regular` while a window is open, `.accessory` otherwise.

- [ ] Step 1: Build + launch; screenshot each pane (computer-use `app_screenshot`), light + dark. Step 2: toggles persist after relaunch (`defaults read local.airpodsmouse`). Step 3: Commit `feat: menu bar and settings window`.

### Task 5: Onboarding and practice

**Files:** `Views/Onboarding/OnboardingView.swift` (+ one file per step), `Views/PracticeView.swift`.

- `Window(id: "onboarding")` shown at launch when `!onboardingDone`. Steps per spec §2 (Bienvenue, Tes AirPods with live head-indicator from `rates`, Mouvements, Accessibilité with live detection, Comment cliquer (two cards → sets `nodClick`/`dwellEnabled`), Essai). Page dots, Back/Next, auto-advance when a permission becomes granted. Step 2 has “Continuer quand même” after 10 s without motion.
- `PracticeView`: 3 large circular targets at random positions; hovered target highlights; click (any source) on it → success animation; counter “2 / 3”; restart button.

- [ ] Step 1: Build, `defaults delete local.airpodsmouse onboardingDone`, launch, walk all steps (screenshots). Step 2: Commit `feat: onboarding and practice targets`.

### Task 6: Cursor overlay

**Files:** `CursorOverlay.swift`.
- Borderless, click-through (`ignoresMouseEvents`), `.screenSaver`-level transparent `NSPanel` 64×64 following the cursor at 120 Hz; SwiftUI ring: trim = `dwellProgress` (accent colour), pulse on `lastClickAt` (0.25 s scale+fade); hidden when paused or dwell off and idle; `collectionBehavior` `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`.
- [ ] Step 1: Build, enable dwell, hold still → ring fills then click (verify on a Finder item). Step 2: Commit `feat: cursor ring for dwell and click feedback`.

### Task 7: Localization FR/EN

**Files:** `Resources/fr.lproj/Localizable.strings`, `Resources/en.lproj/Localizable.strings`; all views use `String(localized:)`/`Text("key")` with French keys = French text.
- [ ] Step 1: Check script: every key used in sources exists in both files (grep-based, part of `scripts/check-strings.sh`). Step 2: Launch with `-AppleLanguages '(en)'`, screenshot. Step 3: Commit `feat: French and English`.

### Task 8: Icon, universal build, signing

**Files:** `scripts/make-icon.swift` (draws 1024 px icon: rounded squircle, blue→indigo gradient, white AirPods Pro SF Symbol + small cursor arrow; outputs iconset → `iconutil` → `Resources/AppIcon.icns`), `scripts/build-app.sh` (build arm64 + x86_64 release separately, `lipo`, bundle with Info.plist incl. `CFBundleIconFile`, `CFBundleDevelopmentRegion fr`, `CFBundleLocalizations [fr,en]`, version `2.0`, `NSMotionUsageDescription`, `LSUIElement`; copy lproj + icns; sign; install to /Applications), `build.sh` → calls it.
- [ ] Step 1: `lipo -archs` shows `x86_64 arm64`; `codesign -dv` Authority=AirPodsMouse Dev; Finder shows icon. Step 2: Commit `build: icon and universal signed app`.

### Task 9: DMG and docs

**Files:** `scripts/make-dmg.sh` (+ `scripts/dmg-background.swift`), `docs/installation.md` (FR, with Gatekeeper « Ouvrir quand même » steps), README rewritten (FR first, EN section).
- DMG: `AirPodsMouse-2.0.dmg`, window 640×400, background illustration, app icon left, Applications link right, `Si macOS bloque l'ouverture.txt`.
- [ ] Step 1: Mount DMG, screenshot Finder window. Step 2: Commit `build: dmg and install guide`.

### Task 10: End-to-end verification with the user
- [ ] Fresh-user simulation: `defaults delete local.airpodsmouse`, install from DMG, run onboarding with the user; nod click and dwell click on Finder items; disconnect AirPods mid-use (cursor stops); `swift run AirPodsMouseChecks` ✅.
