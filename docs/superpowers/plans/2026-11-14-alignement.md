# Alignement tête ↔ curseur — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep "facing the screen = cursor centred" without losing fine-aim precision.

**Architecture:** Extend `PointerEngine` (pure, testable) with head-angle tracking, a slowly-adapting "facing" reference, edge memory and speed-gated realignment; the app passes cursor position + screen bounds. Simulated head motions and the two real recordings verify it.

**Tech Stack:** Swift (AirPodsMouseCore), checks runner `swift run AirPodsMouseChecks`.

**Spec:** `docs/superpowers/specs/2026-11-14-alignement-tete-curseur-design.md`

## Global Constraints
- Slow-aim gain unchanged (gainSlow 1400 px/rad); realignment weight 0 below 0.3 rad/s.
- Replay: motion2 → 5 clicks / 0 false; motion1 → 0 false (with and without screen simulation).
- Return-to-facing target: cursor within 60 px of screen centre (1470×956 simulated screen).

## Review Focus
1. Nod in progress (cursor held) must not be realigned mid-gesture → realignment only on emitted movement.
2. Sensor gap (> 0.15 s) must not create a jump → angles continuous; ideal uses filtered angles.
3. Multiple screens: alignment uses the screen containing the cursor (app side).
4. Paused → resume: reference must not jump the cursor → `reset()` keeps reference; resume emits nothing until movement.
5. Sensitivity change → alignment gain scales with sensitivity (no sudden pull).

---

### Task 1: Alignment in PointerEngine
**Files:** Modify `Sources/AirPodsMouseCore/PointerEngine.swift`, `Sources/AirPodsMouseCore/Replay.swift`; Test `Sources/AirPodsMouseChecks/main.swift`.

**Interfaces — Produces:**
- `public struct ScreenContext { public var cursor: CGPoint; public var bounds: CGRect }`
- `PointerEngine.step(w:g:dt:t:screen: ScreenContext? = nil) -> PointerOutput` (nil = previous behaviour).
- `PointerEngine.recenter()` — facing reference = current head direction; caller moves cursor to bounds centre.
- `PointerEngine.alignment: Bool` (default true), `PointerEngine.idealPosition(in:) -> CGPoint?`.
- `replay(csv:engine:screen: CGRect? = nil)` — with a screen, simulates a clamped cursor and passes `ScreenContext`.

- [ ] Step 1: checks `edgeReturnToCenter`, `fastOutSlowBackReturnsToCenter`, `fineAimUnchangedByAlignment`, `recenterPutsIdealAtCenter`, `replayWithScreenKeepsClicks` (motion2 5/0, motion1 0 false).
- [ ] Step 2: run → FAIL (API missing / return-to-centre off by hundreds of px).
- [ ] Step 3: implement per spec (ideal = centre + Δangle × 2600 × sensitivity, vertical × verticalRatio; edge memory; correction += (ideal − next) × 0.08 × smoothstep(0.3, 1.0, speed); reference EMA τ = 120 s when not at an edge).
- [ ] Step 4: run → all ✅.

### Task 2: App wiring
**Files:** Modify `Sources/AirPodsMouse/AppModel.swift`, `CursorController.swift`, `HotKeys.swift`, `Views/SettingsView.swift`, `Resources/en.lproj/Localizable.strings`.
- Pass `ScreenContext(cursor: cursor.pos, bounds: screen containing cursor)` (CG coordinates) to `engine.step`.
- ⌃⌥C → `recenter()` (engine.recenter + cursor to centre of the screen containing it). Pointer pane: « Recentrer » button + footnote; calibration stays as a secondary button.
- [ ] Step 1: build, `scripts/check-strings.sh` ✅, checks ✅. Step 2: live test with the user (look past the edge and back → cursor back near centre; sampler logs).
