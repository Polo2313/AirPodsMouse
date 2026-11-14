// Vérifications automatiques (pas de XCTest/Testing avec les seuls outils en ligne de commande).
// Lancer : swift run AirPodsMouseChecks   — sort avec le code 1 si une vérification échoue.
import Foundation
import AirPodsMouseCore

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

print(failures == 0 ? "\nTout est vert." : "\n\(failures) échec(s).")
exit(failures == 0 ? 0 : 1)
