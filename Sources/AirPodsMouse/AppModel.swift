import AppKit
import AVFoundation
import AirPodsMouseCore
import CoreMotion
import ServiceManagement
import simd

/// Cœur de l'appli : relie capteurs → moteur de pointage → curseur, garde l'état affiché par l'interface
/// et les réglages (enregistrés dans les préférences, mêmes clés que la version 1).
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Status: Equatable { case searching, active, noMotion, paused, calibrating, motionDenied, unavailable }

    // MARK: État affiché
    @Published private(set) var status: Status = .searching
    @Published private(set) var axTrusted = false
    @Published private(set) var motionAuth: CMAuthorizationStatus = .notDetermined
    @Published private(set) var airPodsConnected = false
    @Published private(set) var isPaused = false
    @Published private(set) var dwellProgress = 0.0
    @Published private(set) var lastClickAt: Date?
    @Published private(set) var calibrationMessage: String?
    /// Vitesses de la tête (rad/s), ~15 fois par seconde : pour l'indicateur de l'accueil.
    @Published private(set) var headRates = SIMD2<Double>(0, 0)

    // MARK: Réglages
    private let defaults = UserDefaults.standard
    static let settingsVersion = 3

    @Published var sensitivity = 1.0 { didSet { engine.sensitivity = sensitivity; defaults.set(sensitivity, forKey: "sensitivity") } }
    @Published var verticalRatio = 2.4 { didSet { engine.verticalRatio = verticalRatio; defaults.set(verticalRatio, forKey: "verticalRatio") } }
    @Published var invertX = false { didSet { engine.invertX = invertX; defaults.set(invertX, forKey: "invertX") } }
    @Published var invertY = false { didSet { engine.invertY = invertY; defaults.set(invertY, forKey: "invertY") } }
    @Published var nodClick = true { didSet { engine.nodClick = nodClick; defaults.set(nodClick, forKey: "nodClick") } }
    @Published var nodPreset: NodPreset = .normal { didSet { engine.nodPreset = nodPreset; defaults.set(nodPreset.rawValue, forKey: "nodPreset") } }
    @Published var tiltClick = false { didSet { engine.tiltClick = tiltClick; defaults.set(tiltClick, forKey: "tiltClick") } }
    @Published var dwellEnabled = false { didSet { dwell.reset(); dwellProgress = 0; defaults.set(dwellEnabled, forKey: "dwellEnabled") } }
    @Published var dwellDelay = 1.0 { didSet { dwell.delay = dwellDelay; defaults.set(dwellDelay, forKey: "dwellDelay") } }
    @Published var onboardingDone = false { didSet { defaults.set(onboardingDone, forKey: "onboardingDone") } }
    @Published private(set) var isCalibrated = false

    // MARK: Moteur
    private(set) var engine = PointerEngine()
    private var dwell = DwellClicker()
    private let motion = MotionService()
    let cursor = CursorController()
    private var lastTimestamp: TimeInterval?
    private var calibSamples: [(w: V3, g: V3, dt: Double)]?
    private var calibEnd = Date.distantPast
    private var lastRatesPublish = Date.distantPast
    private var timers: [Timer] = []
    var onSample: ((CMDeviceMotion) -> Void)?   // vue 3D

    private init() {}

    func start() {
        Log.line("— Démarrage AirPodsMouse \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") —")
        loadSettings()
        motion.onSample = { [weak self] m in self?.handle(m) }
        motion.onConnectionChange = { [weak self] c in self?.airPodsConnected = c; if !c { self?.cursor.dropPending() } }
        axTrusted = Permissions.axTrusted
        cursor.allowed = axTrusted
        // Premier lancement : la demande système « Mouvements » attend son étape de l'accueil
        // (sinon elle apparaît par-dessus l'écran de bienvenue, sans explication).
        if onboardingDone || Permissions.motion != .notDetermined { motion.start() }
        let health = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.healthCheck() } }
        let output = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.outputTick() } }
        timers = [health, output]
        timers.forEach { RunLoop.main.add($0, forMode: .common) }
        healthCheck()
    }

    // MARK: - Boucle

    private func handle(_ m: CMDeviceMotion) {
        let rawDt = lastTimestamp.map { m.timestamp - $0 } ?? 0.02   // horloge du capteur (mesures par paquets)
        lastTimestamp = m.timestamp
        let w = V3(m.rotationRate.x, m.rotationRate.y, m.rotationRate.z)
        let g = simd_normalize(V3(m.gravity.x, m.gravity.y, m.gravity.z))
        onSample?(m)

        if Date().timeIntervalSince(lastRatesPublish) > 1.0 / 15 {
            let r = engine.rates(w: w, g: g)
            headRates = SIMD2(r.yaw, r.pitch)
            lastRatesPublish = Date()
        }
        if calibSamples != nil {
            calibSamples!.append((w, g, min(max(rawDt, 0.001), 0.1)))
            if Date() >= calibEnd { finishCalibration() }
            return
        }
        let out = engine.step(w: w, g: g, dt: rawDt, t: m.timestamp)
        guard !isPaused, axTrusted else { cursor.dropPending(); return }
        cursor.add(dx: out.dx, dy: out.dy)
        if let c = out.click {
            cursor.flush()   // applique le reste (dont la correction du glissement), puis clique à cet endroit
            click(right: c == .right, source: c == .right ? "inclinaison" : "hochement")
        }
    }

    private func outputTick() {
        let fresh = motion.lastSampleAt.map { Date().timeIntervalSince($0) < 0.3 } ?? false
        let realMoved = cursor.tick(sensorsFresh: fresh && !isPaused && axTrusted)
        let recentClick = lastClickAt.map { Date().timeIntervalSince($0) < 0.4 } ?? false
        CursorOverlay.shared.update(visible: dwellProgress > 0.03 || recentClick)
        guard dwellEnabled, status == .active else {
            if dwellProgress != 0 { dwellProgress = 0 }
            return
        }
        let r = dwell.update(cursor: cursor.pos, t: ProcessInfo.processInfo.systemUptime, realMouseMoved: realMoved)
        if abs(r.progress - dwellProgress) > 0.02 || (r.progress == 0) != (dwellProgress == 0) { dwellProgress = r.progress }
        if r.fire { click(right: false, source: "automatique") }
    }

    private func click(right: Bool, source: String) {
        cursor.click(right: right)
        lastClickAt = Date()
        Log.line("Clic \(right ? "droit" : "gauche") (\(source)) en \(Int(cursor.pos.x)),\(Int(cursor.pos.y))")
    }

    private func healthCheck() {
        motion.healthCheck()
        motionAuth = Permissions.motion
        let trusted = Permissions.axTrusted
        if trusted != axTrusted {
            Log.line(trusted ? "Accessibilité accordée ✅" : "Accessibilité retirée")
            axTrusted = trusted
            cursor.allowed = trusted
        }
        let new: Status
        if !motion.isAvailable { new = .unavailable }
        else if motionAuth == .denied || motionAuth == .restricted { new = .motionDenied }
        else if calibSamples != nil { new = .calibrating }
        else if !motion.isStreaming { new = Date().timeIntervalSince(motion.startedAt) < 3 ? .searching : .noMotion }
        else if isPaused { new = .paused }
        else { new = .active }
        if new != status { status = new; Log.line("État : \(new)") }
    }

    // MARK: - Actions

    func togglePause() {
        isPaused.toggle()
        cursor.dropPending(); engine.reset(); dwell.reset()
        healthCheck()
    }

    func startCalibration() {
        guard motion.isStreaming else { calibrationMessage = String(localized: "Les AirPods n'envoient aucun mouvement : mets-les dans tes oreilles."); return }
        calibrationMessage = nil
        calibSamples = []
        calibEnd = Date().addingTimeInterval(3)
        NSSound(named: "Tink")?.play()
        healthCheck()
    }

    /// Trouve l'axe haut/bas : axe principal des rotations horizontales pendant 3 s de « oui » de la tête.
    private func finishCalibration() {
        guard let samples = calibSamples else { return }
        calibSamples = nil
        defer { healthCheck() }
        guard samples.count > 20 else { fail(String(localized: "Aucun mouvement reçu pendant le calibrage.")); return }
        var cov = simd_double3x3(0)
        var hs: [(V3, Double)] = []
        for s in samples {
            let h = s.w - simd_dot(s.w, s.g) * s.g
            hs.append((h, s.dt))
            cov += simd_double3x3(columns: (h * h.x, h * h.y, h * h.z))
        }
        var axis = V3(1, 1, 1)
        for _ in 0..<50 { let n = cov * axis; if simd_length(n) < 1e-9 { break }; axis = simd_normalize(n) }
        var theta = 0.0, extreme = 0.0       // signe : le premier grand mouvement doit être vers le haut
        for (h, dt) in hs { theta += simd_dot(h, axis) * dt; if abs(theta) > abs(extreme) { extreme = theta } }
        guard abs(extreme) > 0.15 else { fail(String(localized: "Pas assez de mouvement : lève la tête plus franchement.")); return }
        if extreme < 0 { axis = -axis }
        engine.axis = axis
        engine.reset(); cursor.dropPending()
        defaults.set([axis.x, axis.y, axis.z], forKey: "vAxis")
        isCalibrated = true
        calibrationMessage = String(localized: "Calibré ✅")
        NSSound(named: "Glass")?.play()
        Log.line("Calibré : \(axis)")

        func fail(_ s: String) { calibrationMessage = s; NSSound(named: "Basso")?.play(); Log.line(s) }
    }

    func resetSettings() {
        for k in ["sensitivity", "verticalRatio", "invertX", "invertY", "nodClick", "nodPreset", "tiltClick", "dwellEnabled", "dwellDelay", "vAxis"] {
            defaults.removeObject(forKey: k)
        }
        loadSettings()
        engine.reset(); cursor.dropPending()
        calibrationMessage = nil
        Log.line("Réglages réinitialisés")
    }

    /// Déclenche la demande système d'accès aux mouvements (étape de l'accueil).
    func requestMotion() { motion.start() }

    /// Les AirPods basculent tout seuls entre l'iPhone et le Mac ; quand ils sont sur l'iPhone, le Mac ne reçoit
    /// plus leurs mouvements. Mesuré : jouer une voix dans les AirPods fait que le Mac les reprend aussitôt
    /// (un silence ou un son très faible ne suffit pas). Proposé en bouton, jamais automatiquement.
    func wakeAirPods() {
        if !airPodsAreAudioOutput { routeAudioToAirPods() }
        speech.stopSpeaking(at: .immediate)
        speech.speak(AVSpeechUtterance(string: String(localized: "AirPodsMouse est prêt.")))
        Log.line("Reprise des AirPods demandée")
    }
    private let speech = AVSpeechSynthesizer()

    func routeAudioToAirPods() {
        guard let ap = AudioOutput.airPods() else { return }
        Log.line(AudioOutput.setDefaultOutput(ap) ? "Sortie audio → \(AudioOutput.name(ap))" : "Impossible de changer la sortie audio")
    }

    /// Que dire quand rien n'arrive des capteurs.
    var noMotionHint: String {
        if AudioOutput.airPods() == nil {
            return String(localized: "Tes AirPods sont peut-être connectés à ton iPhone : choisis-les dans le menu Son, en haut à droite de l'écran.")
        }
        return String(localized: "Mets les AirPods dans tes oreilles. S'ils y sont déjà, ils sont peut-être passés sur ton iPhone.")
    }

    var airPodsAreAudioOutput: Bool { AudioOutput.airPods().map { $0 == AudioOutput.defaultOutput } ?? false }

    // MARK: - Ouverture au démarrage

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { Log.line("Ouverture au démarrage : \(error.localizedDescription)") }
        }
    }

    // MARK: - Réglages enregistrés

    private func loadSettings() {
        if defaults.integer(forKey: "settingsVersion") < Self.settingsVersion {
            for k in ["gain", "click", "flickEnabled", "rightClick", "vAxis"] { defaults.removeObject(forKey: k) }
            defaults.set(Self.settingsVersion, forKey: "settingsVersion")
        }
        func d(_ k: String, _ def: Double) -> Double { defaults.object(forKey: k) != nil ? defaults.double(forKey: k) : def }
        func b(_ k: String, _ def: Bool) -> Bool { defaults.object(forKey: k) != nil ? defaults.bool(forKey: k) : def }
        sensitivity = min(max(d("sensitivity", 1), 0.3), 3)
        verticalRatio = min(max(d("verticalRatio", 2.4), 1.5), 3.5)
        invertX = b("invertX", false)
        invertY = b("invertY", false)
        nodClick = b("nodClick", true)
        nodPreset = NodPreset(rawValue: defaults.integer(forKey: "nodPreset")).flatMap { defaults.object(forKey: "nodPreset") != nil ? $0 : nil } ?? .normal
        tiltClick = b("tiltClick", false)
        dwellEnabled = b("dwellEnabled", false)
        dwellDelay = min(max(d("dwellDelay", 1), 0.6), 2)
        onboardingDone = b("onboardingDone", false)
        if let a = defaults.array(forKey: "vAxis") as? [Double], a.count == 3 {
            engine.axis = V3(a[0], a[1], a[2]); isCalibrated = true
        } else { engine.axis = nil; isCalibrated = false }
    }
}
