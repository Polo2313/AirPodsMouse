// Vérifications automatiques (pas de XCTest/Testing avec les seuls outils en ligne de commande).
// Lancer : swift run AirPodsMouseChecks   — sort avec le code 1 si une vérification échoue.
import Foundation
import AirPodsMouseCore
import CoreGraphics
import simd

var failures = 0
func check(_ name: String, _ cond: Bool, _ detail: @autoclosure () -> String = "") {
    if cond { print("✅ \(name)") } else { failures += 1; print("❌ \(name) \(detail())") }
}

let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Tests/Fixtures")
func fixture(_ name: String) -> String {
    (try? String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)) ?? ""
}

// MARK: - Non-régression du moteur sur de vrais enregistrements

let m1 = fixture("motion1.csv"), m2 = fixture("motion2.csv")
check("fixtures présentes", !m1.isEmpty && !m2.isEmpty)

let r2 = replay(csv: m2, engine: PointerEngine())
check("replayMotion2FiveClicks", (r2.clicksByPhase["click"] ?? []).count == 5, "\(r2.clicksByPhase)")
check("replayMotion2NoFalseClicks", r2.clicksByPhase.filter { $0.key != "click" }.allSatisfy { $0.value.isEmpty }, "\(r2.clicksByPhase)")

let r1 = replay(csv: m1, engine: PointerEngine())
check("replayMotion1NoFalseClicks", r1.clicksByPhase.filter { $0.key != "click" }.allSatisfy { $0.value.isEmpty }, "\(r1.clicksByPhase)")

// MARK: - Sensibilité du hochement

func clicks(_ csv: String, _ preset: NodPreset) -> ReplayResult {
    var e = PointerEngine(); e.nodPreset = preset
    return replay(csv: csv, engine: e)
}
func falseClicks(_ r: ReplayResult) -> Int { r.clicksByPhase.filter { $0.key != "click" }.reduce(0) { $0 + $1.value.count } }
func trueClicks(_ r: ReplayResult) -> Int { (r.clicksByPhase["click"] ?? []).count }

let n2 = clicks(m2, .normal), c2 = clicks(m2, .careful), e2 = clicks(m2, .easy)
let n1 = clicks(m1, .normal), c1 = clicks(m1, .careful)
check("presetNormalMatchesReplay", trueClicks(n2) == 5 && falseClicks(n2) == 0, "\(n2.clicksByPhase)")
check("presetCarefulNoMoreClicks", trueClicks(c2) <= 5 && falseClicks(c2) == 0 && falseClicks(c1) == 0 && trueClicks(c1) <= trueClicks(n1))
check("presetEasyKeepsTrueClicks", trueClicks(e2) == 5, "\(e2.clicksByPhase)")

// MARK: - Clic automatique

/// Simule le curseur à 120 Hz : `path(t)` donne la position, `real(t)` si le vrai trackpad bouge.
func dwellRun(seconds: Double, delay: Double = 1.0, path: (Double) -> CGPoint,
              real: (Double) -> Bool = { _ in false }) -> (fires: Int, maxProgress: Double) {
    var d = DwellClicker(); d.delay = delay
    var fires = 0, maxP = 0.0, t = 0.0
    while t <= seconds {
        let r = d.update(cursor: path(t), t: t, realMouseMoved: real(t))
        if r.fire { fires += 1 }
        maxP = max(maxP, r.progress)
        t += 1.0 / 120
    }
    return (fires, maxP)
}
let here = CGPoint(x: 500, y: 400)
let once = dwellRun(seconds: 1.2) { _ in here }
check("dwellFiresOnce", once.fires == 1 && once.maxProgress >= 0.99, "\(once)")
check("dwellNoRepeatWithoutMove", dwellRun(seconds: 5) { _ in here }.fires == 1)
let rearm = dwellRun(seconds: 4) { t in t < 1.5 ? here : (t < 1.7 ? CGPoint(x: 500 + (t - 1.5) * 250, y: 400) : CGPoint(x: 550, y: 400)) }
check("dwellRearmsAfterMove", rearm.fires == 2, "\(rearm)")
check("dwellIgnoresRealMouse", dwellRun(seconds: 3, path: { _ in here }, real: { _ in true }).fires == 0)
let jitter = dwellRun(seconds: 1.5) { t in CGPoint(x: 500 + 3 * sin(t * 40), y: 400 + 3 * cos(t * 33)) }
check("dwellJitterTolerated", jitter.fires == 1, "\(jitter)")
let moving = dwellRun(seconds: 3) { t in CGPoint(x: 100 + t * 200, y: 400) }
check("dwellNotWhileMoving", moving.fires == 0, "\(moving)")
check("dwellRespectsDelay", dwellRun(seconds: 1.4, delay: 1.5) { _ in here }.fires == 0)
// Trackpad utilisé puis lâché : aucun clic (seul un mouvement de tête réarme le clic automatique)
check("dwellNotAfterRealMouseStops", dwellRun(seconds: 4, path: { _ in here }, real: { t in t < 0.5 }).fires == 0)
// Trackpad, puis la tête déplace le curseur de 60 px, puis immobile : un clic
let afterHead = dwellRun(seconds: 4, path: { t in t < 1 ? here : (t < 1.3 ? CGPoint(x: 500 + (t - 1) * 200, y: 400) : CGPoint(x: 560, y: 400)) },
                         real: { t in t < 0.5 })
check("dwellAfterRealMouseThenHead", afterHead.fires == 1, "\(afterHead)")
var disarmed = DwellClicker(); disarmed.disarm(at: here)
check("dwellDisarmedDoesNotFireAtStart", disarmed.update(cursor: here, t: 0, realMouseMoved: false).fire == false
      && disarmed.update(cursor: here, t: 2.0, realMouseMoved: false).fire == false)

// MARK: - Alignement tête ↔ curseur

let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
let center = CGPoint(x: screen.midX, y: screen.midY)

/// Simule une tête qui tourne (lacet, rad/s ; + = vers la gauche) à 50 mesures/s, avec un curseur bloqué aux bords.
/// `yawRate(t)` donne la vitesse ; renvoie la position finale du curseur et le moteur.
func simulateHead(seconds: Double, alignment: Bool = true, engine start: PointerEngine = PointerEngine(),
                  yawRate: (Double) -> Double) -> (cursor: CGPoint, engine: PointerEngine, path: [CGPoint]) {
    var e = start; e.alignment = alignment
    var p = center, t = 0.0, path: [CGPoint] = []
    let g = V3(0, 0, -1)                        // tête droite : gravité vers le bas
    while t < seconds {
        let w = V3(0, 0, yawRate(t))             // lacet = -w·g = w.z
        let o = e.step(w: w, g: g, dt: 0.02, t: t, screen: ScreenContext(cursor: p, bounds: screen))
        p = CGPoint(x: min(max(p.x + o.dx, screen.minX), screen.maxX - 1), y: min(max(p.y + o.dy, screen.minY), screen.maxY - 1))
        path.append(p)
        t += 0.02
    }
    return (p, e, path)
}

// Regarder bien au-delà du bord droit (~34°), puis revenir en face à la même vitesse → curseur au centre
let pastEdge = simulateHead(seconds: 3.4) { t in t < 1.2 ? -0.5 : (t < 1.7 ? 0 : (t < 2.9 ? 0.5 : 0)) }
check("edgeReturnToCenter", abs(pastEdge.cursor.x - center.x) < 60, "x=\(Int(pastEdge.cursor.x)) (centre \(Int(center.x)))")

// Aller rapide (13°), retour lent du même angle → curseur au centre
// (bornes à mi-pas : 8 mesures × 0,02 s × 1,5 = 0,24 rad ; 60 mesures × 0,02 s × 0,2 = 0,24 rad)
let fastSlow = simulateHead(seconds: 2.0) { t in t < 0.15 ? -1.5 : (t < 0.29 ? 0 : (t < 1.49 ? 0.2 : 0)) }
check("fastOutSlowBackReturnsToCenter", abs(fastSlow.cursor.x - center.x) < 60, "x=\(Int(fastSlow.cursor.x))")
print("   retour du bord : x=\(Int(pastEdge.cursor.x)) ; aller rapide/retour lent : x=\(Int(fastSlow.cursor.x)) (centre \(Int(center.x)))")

// Visée fine (mouvements lents) : l'alignement ne touche à rien
let slowAim: (Double) -> Double = { t in 0.05 * sin(t * 2) }   // ~1,4° : vraie visée fine
let withA = simulateHead(seconds: 4, alignment: true, yawRate: slowAim).path
let withoutA = simulateHead(seconds: 4, alignment: false, yawRate: slowAim).path
let maxDiff = zip(withA, withoutA).map { abs($0.x - $1.x) + abs($0.y - $1.y) }.max() ?? 0
check("fineAimUnchangedByAlignment", maxDiff < 1, "écart max \(maxDiff) px")

// Recentrer : la position idéale devient le centre de l'écran
var turned = simulateHead(seconds: 1) { _ in -0.4 }.engine
turned.recenter()
let ideal = turned.idealPosition(in: screen)
check("recenterPutsIdealAtCenter", ideal.map { hypot($0.x - center.x, $0.y - center.y) < 2 } ?? false, "\(String(describing: ideal))")

// Les clics restent identiques avec l'écran simulé
let s2 = replay(csv: m2, engine: PointerEngine(), screen: screen)
let s1 = replay(csv: m1, engine: PointerEngine(), screen: screen)
check("replayWithScreenKeepsClicks", trueClicks(s2) == 5 && falseClicks(s2) == 0 && falseClicks(s1) == 0,
      "m2 \(s2.clicksByPhase) m1 faux=\(falseClicks(s1))")

// Bug signalé : « la souris reste bloquée en haut ». L'alignement ne doit pas coller le curseur aux bords haut/bas.
for (name, csv) in [("motion1", m1), ("motion2", m2)] {
    var on = PointerEngine(); on.sensitivity = 0.694
    var off = on; off.alignment = false
    let a = replay(csv: csv, engine: on, screen: screen).verticalEdgeFraction
    let b = replay(csv: csv, engine: off, screen: screen).verticalEdgeFraction
    check("alignmentDoesNotStickVertically[\(name)]", a <= b + 0.01,
          String(format: "collé haut/bas %.1f %% avec alignement contre %.1f %% sans", a * 100, b * 100))
}

// MARK: - Défilement par glissement sur la tige

/// Rejoue des notifications de volume (instant, valeur) ; le détecteur remet la référence après chaque glissement,
/// comme l'appli (la remise produit elle-même une notification au volume de référence).
func swipes(_ events: [(Double, Double)], start: Double, keyAt: Double? = nil) -> [StemSwipe] {
    var d = StemSwipeDetector(reference: start)
    var out: [StemSwipe] = []
    for (t, v) in events {
        let key = keyAt.map { t - $0 >= 0 && t - $0 < 0.4 } ?? false
        if let s = d.volumeChanged(to: v, at: t, keyPressedRecently: key) { out.append(s) }
    }
    return out
}
// Séquence réelle de l'essai (glisser haut ×3 puis bas ×4), notifications doublées, avec remise à la référence
let realUp = swipes([(19.9, 0.386), (19.9, 0.386), (19.95, 0.323), (20.8, 0.386), (20.85, 0.323), (21.8, 0.386), (21.85, 0.323)], start: 0.323)
check("swipeUpDetectedOncePerSwipe", realUp == [.up, .up, .up], "\(realUp)")
let realDown = swipes([(22.3, 0.260), (22.35, 0.323), (22.8, 0.260), (22.8, 0.260), (22.85, 0.323)], start: 0.323)
check("swipeDownDetected", realDown == [.down, .down], "\(realDown)")
check("sliderChangeIsNotASwipe", swipes([(1, 0.5)], start: 0.323).isEmpty)
check("keyboardVolumeIsNotASwipe", swipes([(1.1, 0.386)], start: 0.323, keyAt: 1.0).isEmpty)
var keyThenSwipe = StemSwipeDetector(reference: 0.323)
_ = keyThenSwipe.volumeChanged(to: 0.386, at: 1.1, keyPressedRecently: true)      // touche clavier : nouvelle référence
check("referenceFollowsKeyboard", keyThenSwipe.volumeChanged(to: 0.449, at: 3, keyPressedRecently: false) == .up
      && keyThenSwipe.reference == 0.386)

var stepper = ScrollStepper(baseStep: 240)
let first = stepper.distance(at: 0, up: true), second = stepper.distance(at: 0.5, up: true), third = stepper.distance(at: 1.0, up: true)
let fourth = stepper.distance(at: 1.4, up: true), fifth = stepper.distance(at: 1.8, up: true)
let later = stepper.distance(at: 5, up: true)
check("scrollStepMedium", first == 240, "\(first)")
check("scrollAccelerates", second == 360 && third == 540, "\(second) \(third)")
check("scrollAccelerationCapped", fourth == 720 && fifth == 720, "\(fourth) \(fifth)")
check("scrollResetsAfterPause", later == 240, "\(later)")
var turn = ScrollStepper(baseStep: 240)
_ = turn.distance(at: 0, up: true); _ = turn.distance(at: 0.4, up: true)
let reversed = turn.distance(at: 0.8, up: false)
check("scrollResetsOnDirectionChange", reversed == 240, "\(reversed)")

// MARK: - Pause pendant la frappe

var typing = TypingGuard()
typing.keyPressed(at: 10)
check("typingFreezes", typing.isFrozen(at: 11.2) && !typing.isFrozen(at: 11.7))
check("typingResumesOnce", typing.justResumed(at: 11.7) && !typing.justResumed(at: 11.8))
check("typingNotFrozenInitially", !TypingGuard().isFrozen(at: 0))

// MARK: - Défilement à la tête

var hs = HeadScroller()
hs.start(yaw: 0, pitch: 0)
check("headScrollDeadZone", hs.velocity(pitch: 0.03) == 0)
check("headScrollUp", hs.velocity(pitch: 0.17) > 0)                 // tête levée ~10° → défile vers le haut
check("headScrollDown", hs.velocity(pitch: -0.17) < 0)
check("headScrollFasterWhenTilted", hs.velocity(pitch: 0.3) > hs.velocity(pitch: 0.15))
check("headScrollCapped", hs.velocity(pitch: 2) <= hs.maxSpeed)
check("headScrollExitsWhenLookingAway", hs.shouldExit(yaw: 0.3) && !hs.shouldExit(yaw: 0.1))

// MARK: - Menu de clic rapide

func runMenu(_ path: (Double) -> CGPoint, seconds: Double) -> DwellMenu.Outcome {
    var m = DwellMenu(origin: CGPoint(x: 500, y: 400), openedAt: 0)
    var t = 0.0
    while t <= seconds {
        let r = m.update(cursor: path(t), t: t)
        if case .pending = r {} else { return r }
        t += 1.0 / 120
    }
    return .pending(hovered: nil, progress: 0)
}
let menu0 = DwellMenu(origin: CGPoint(x: 500, y: 400), openedAt: 0)
let rightPos = menu0.itemCenter(.rightClick), dragPos = menu0.itemCenter(.drag)
check("menuItemsAroundOrigin", DwellMenu.Action.allCases.allSatisfy { hypot(menu0.itemCenter($0).x - 500, menu0.itemCenter($0).y - 400) > 50 })
check("menuChoosesAfterDwell", runMenu({ t in t < 0.2 ? CGPoint(x: 500, y: 400) : rightPos }, seconds: 1.5) == .chosen(.rightClick))
check("menuSwitchResetsDwell", runMenu({ t in t < 0.5 ? rightPos : dragPos }, seconds: 1.3) == .chosen(.drag))
check("menuCancelsWhenLeaving", runMenu({ _ in CGPoint(x: 900, y: 400) }, seconds: 1) == .cancelled)
check("menuCancelsOnTimeout", runMenu({ _ in CGPoint(x: 500, y: 400) }, seconds: 5) == .cancelled)

// MARK: - Geste « non » (secouer la tête) = Échap

func shakes(_ yawRate: (Double) -> Double, pitchRate: (Double) -> Double = { _ in 0 }, seconds: Double) -> Int {
    var s = ShakeDetector(); var n = 0; var t = 0.0
    while t < seconds { if s.update(yawRate: yawRate(t), pitchRate: pitchRate(t), t: t, dt: 0.02) { n += 1 }; t += 0.02 }
    return n
}
check("shakeDetected", shakes({ t in t < 1 ? 2.6 * sin(2 * .pi * 3 * t) : 0 }, seconds: 2) == 1)          // « non » ±8°, 3 Hz
check("shakeIgnoresSlowAiming", shakes({ t in 0.6 * sin(2 * .pi * 0.5 * t) }, seconds: 6) == 0)
check("shakeIgnoresSingleTurn", shakes({ t in t < 0.4 ? 2.0 : 0 }, seconds: 2) == 0)
check("shakeIgnoresNods", shakes({ _ in 0.2 }, pitchRate: { t in 2.6 * sin(2 * .pi * 3 * t) }, seconds: 2) == 0)
for (name, csv) in [("motion1", m1), ("motion2", m2)] {
    check("shakeNoFalsePositive[\(name)]", replayShakes(csv: csv) == 0, "\(replayShakes(csv: csv)) faux « non »")
}

// MARK: - Aimant : ralentir sur les boutons

let medium = MagnetStrength.medium.slowdown
check("magnetSlowsFineAimMoreThanBefore", Magnet.factor(step: 1, slowdown: medium) < 0.5,   // avant : ×0,5
      "\(Magnet.factor(step: 1, slowdown: medium))")
check("magnetLeavesFastMovesAlone", Magnet.factor(step: 15, slowdown: MagnetStrength.strong.slowdown) == 1)
check("magnetOffDoesNothing", Magnet.factor(step: 1, slowdown: 0) == 1)
let curve = stride(from: 0.0, through: 15, by: 0.25).map { Magnet.factor(step: $0, slowdown: MagnetStrength.strong.slowdown) }
check("magnetIsProgressive", zip(curve, curve.dropFirst()).allSatisfy { $1 >= $0 && $1 - $0 < 0.06 },
      "saut max \(zip(curve, curve.dropFirst()).map { $1 - $0 }.max() ?? 0)")
check("magnetStrengthsOrdered", MagnetStrength.light.slowdown < medium && medium < MagnetStrength.strong.slowdown)
check("magnetNeverStops", MagnetStrength.allCases.allSatisfy { Magnet.factor(step: 0.5, slowdown: $0.slowdown) >= 0.2 })

// MARK: - État affiché

func status(streaming: Bool = true, sinceStart: Double = 60, paused: Bool = false,
            calibrating: Bool = false, denied: Bool = false, available: Bool = true) -> AppStatus {
    AppStatus.resolve(available: available, motionDenied: denied, calibrating: calibrating,
                      streaming: streaming, sinceStart: sinceStart, paused: paused)
}
check("statusActive", status() == .active)
check("statusNoMotion", status(streaming: false) == .noMotion)
check("statusSearchingJustStarted", status(streaming: false, sinceStart: 1) == .searching)
check("statusPaused", status(paused: true) == .paused)
// Bug du 16/11 : en pause, AirPods silencieux → « Aucun mouvement reçu » cachait la pause pendant des heures
check("statusPausedWinsOverNoMotion", status(streaming: false, paused: true) == .paused, "\(status(streaming: false, paused: true))")
check("statusPausedWinsOverSearching", status(streaming: false, sinceStart: 1, paused: true) == .paused)
check("statusDeniedWinsOverPause", status(paused: true, denied: true) == .motionDenied)
check("statusUnavailableFirst", status(paused: true, denied: true, available: false) == .unavailable)
check("statusCalibrating", status(calibrating: true) == .calibrating)

// MARK: - Saisie vocale & raccourci Librewispr

check("librewisprShortcutSuperP", LibrewisprShortcut.parse("Super+P") == LibrewisprShortcut(keyCode: 35, command: true, label: "⌘P"))
check("librewisprShortcutAltSpace", LibrewisprShortcut.parse("Alt+Space") == LibrewisprShortcut(keyCode: 49, option: true, label: "⌥Space"))
check("librewisprShortcutCtrlShiftD", LibrewisprShortcut.parse("Ctrl+Shift+D") == LibrewisprShortcut(keyCode: 2, control: true, shift: true, label: "⌃⇧D"))
check("librewisprShortcutInvalid", LibrewisprShortcut.parse("") == nil && LibrewisprShortcut.parse("Super+UnknownKey") == nil)
let sampleSettings = Data(#"{"onboarding_complete":true,"app_settings":{"shortcut":"Super+P","auto_paste":true}}"#.utf8)
check("librewisprShortcutFromJSON", LibrewisprShortcut.fromSettingsJSON(sampleSettings) == .defaultShortcut)
check("voiceInputModesComplete", VoiceInputMode.allCases.count == 4 && VoiceInputMode(rawValue: 0) == .librewispr)

let searchRect = CGRect(x: 400, y: 80, width: 500, height: 38)
let editorRect = CGRect(x: 200, y: 120, width: 1100, height: 700)
check("searchClassifierAcceptsSearchBar",
      SearchBarClassifier.matches(role: "AXTextField", subrole: "AXSearchField", hints: "Rechercher",
                                  rect: searchRect, clickedAt: CGPoint(x: 520, y: 95), isFocusedElement: false))
check("searchClassifierAcceptsGoogleCompactTextArea",
      SearchBarClassifier.matches(role: "AXTextArea", subrole: "", hints: "Rechercher sur Google",
                                  rect: CGRect(x: 400, y: 300, width: 580, height: 48),
                                  clickedAt: CGPoint(x: 550, y: 320), isFocusedElement: false))
check("searchClassifierRejectsClickFarFromFocusedSearchBar",
      !SearchBarClassifier.matches(role: "AXTextField", subrole: "AXSearchField", hints: "Rechercher",
                                   rect: searchRect, clickedAt: CGPoint(x: 1307, y: 599), isFocusedElement: true))
check("searchClassifierRejectsLargeCodeEditor",
      !SearchBarClassifier.matches(role: "AXTextArea", subrole: "", hints: "Editor",
                                   rect: editorRect, clickedAt: CGPoint(x: 600, y: 400), isFocusedElement: true))
check("searchClassifierRejectsPasswordField",
      !SearchBarClassifier.matches(role: "AXTextField", subrole: "AXSecureTextField", hints: "Mot de passe",
                                   rect: searchRect, clickedAt: CGPoint(x: 520, y: 95), isFocusedElement: true))
check("searchClassifierAcceptsSpotlightPrompt",
      SearchBarClassifier.matches(role: "AXGroup", subrole: "", hints: "Spotlight Recherche",
                                  rect: CGRect(x: 420, y: 200, width: 620, height: 48),
                                  clickedAt: CGPoint(x: 520, y: 224), isFocusedElement: false))
check("searchClassifierRejectsButtons",
      SearchBarClassifier.isDirectNonInput(role: "AXButton", subrole: ""))

// MARK: - Résilience Bluetooth HFP (paquets espacés de 0,22 s pendant l'écoute micro) & Calibrage haut/bas

do {
    var hfpEngine = PointerEngine()
    let g = V3(0, 0, -1)
    _ = hfpEngine.step(w: V3(0, 0, -0.4), g: g, dt: 0.02, t: 0.0)
    let burstOut = hfpEngine.step(w: V3(0, 0, -0.4), g: g, dt: 0.22, t: 0.22)
    check("hfpBurstDoesNotDropHeadMovement", abs(burstOut.dx) > 1.0, "dx=\(burstOut.dx)")

    // Calibrage : commencer en baissant la tête (signe négatif) ne doit JAMAIS inverser l'axe haut/bas (+X)
    let trueAxis = simd_normalize(V3(0.94, 0.34, 0))
    var downFirstSamples: [(w: V3, g: V3, dt: Double)] = []
    for i in 0..<100 {
        let t = Double(i) * 0.03
        // D'abord vers le bas (-0.6 rad/s), puis petit retour (+0.4 rad/s) : amplitude modérée (~7°)
        let rate = -0.55 * sin(2 * .pi * 0.8 * t)
        downFirstSamples.append((w: trueAxis * rate, g: g, dt: 0.03))
    }
    let solved = CalibrationSolver.solvePitchAxis(samples: downFirstSamples)
    check("calibrationDownFirstDoesNotInvertAxis",
          solved.map { simd_dot($0, trueAxis) > 0.98 } ?? false, "\(String(describing: solved))")

    let stillSamples = (0..<60).map { _ in (w: V3(0.01, -0.01, 0), g: g, dt: 0.03) }
    check("calibrationRejectsStillHead", CalibrationSolver.solvePitchAxis(samples: stillSamples) == nil)

    // Mémoire des 4 bords (même si `alignment` est désactivé) : dépasser le bord haut ou droit puis revenir ne perd pas le fil
    var edgeOnly = PointerEngine()
    edgeOnly.alignment = false
    edgeOnly.edgeMemory = true
    var ep = center
    var et = 0.0
    // 1. Tourne fort à droite pendant 1,0 s (dépasse largement le bord droit x=1469), puis revient exactement du même angle
    while et < 2.2 {
        let rate = et < 1.0 ? -0.45 : (et < 1.2 ? 0.0 : 0.45)
        let o = edgeOnly.step(w: V3(0, 0, rate), g: g, dt: 0.02, t: et, screen: ScreenContext(cursor: ep, bounds: screen))
        ep = CGPoint(x: min(max(ep.x + o.dx, screen.minX), screen.maxX - 1),
                     y: min(max(ep.y + o.dy, screen.minY), screen.maxY - 1))
        et += 0.02
    }
    check("edgeMemoryHorizontalKeepsSync", ep.x > center.x - 120 && ep.x < screen.maxX - 100, "ep.x=\(Int(ep.x))")

    // 2. Zéro dérive à vide avec biais gyroscope constant (+0,012 rad/s pendant 60 s d'immobilité)
    var driftEngine = PointerEngine()
    driftEngine.alignment = true
    var dp = center
    var dtClock = 0.0
    while dtClock < 60.0 {
        let o = driftEngine.step(w: V3(0, 0, 0.012), g: g, dt: 0.02, t: dtClock, screen: ScreenContext(cursor: dp, bounds: screen))
        dp = CGPoint(x: min(max(dp.x + o.dx, screen.minX), screen.maxX - 1),
                     y: min(max(dp.y + o.dy, screen.minY), screen.maxY - 1))
        dtClock += 0.02
    }
    // Puis un mouvement rapide : l'alignement ne doit PAS tirer le curseur de 1 400 px à cause du biais accumulé !
    let afterStill = driftEngine.step(w: V3(0, 0, -0.6), g: g, dt: 0.02, t: 60.02, screen: ScreenContext(cursor: dp, bounds: screen))
    check("stationaryGyroBiasDoesNotPullCursor", abs(afterStill.dx) < 80, "dx=\(afterStill.dx)")
}

print(failures == 0 ? "\nTout est vert." : "\n\(failures) échec(s).")
exit(failures == 0 ? 0 : 1)
