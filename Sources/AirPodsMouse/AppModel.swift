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

    typealias Status = AppStatus

    // MARK: État affiché
    @Published private(set) var status: Status = .searching
    @Published private(set) var axTrusted = false
    @Published private(set) var motionAuth: CMAuthorizationStatus = .notDetermined
    @Published private(set) var airPodsConnected = false
    @Published private(set) var isPaused = false
    @Published private(set) var dwellProgress = 0.0
    @Published private(set) var lastClickAt: Date?
    @Published private(set) var calibrationMessage: String?
    @Published private(set) var calibrationProgress = 0.0
    /// Vitesses de la tête (rad/s), ~15 fois par seconde : pour l'indicateur de l'accueil.
    @Published private(set) var headRates = SIMD2<Double>(0, 0)
    @Published private(set) var isDragging = false
    @Published private(set) var scrollMode = false
    @Published private(set) var quickMenu: DwellMenu?
    @Published private(set) var quickMenuHovered: DwellMenu.Action?
    @Published private(set) var quickMenuProgress = 0.0
    @Published private(set) var isVoiceListening = false
    /// Suspend automatiquement le curseur quand AirDance est au premier plan (pour ne pas déplacer la souris en dansant).
    @Published private(set) var suspendedForAirDance = false

    // MARK: Réglages
    private let defaults = UserDefaults.standard
    static let settingsVersion = 6

    @Published var sensitivity = 1.0 { didSet { engine.sensitivity = sensitivity; defaults.set(sensitivity, forKey: "sensitivity") } }
    @Published var verticalRatio = 2.4 { didSet { engine.verticalRatio = verticalRatio; defaults.set(verticalRatio, forKey: "verticalRatio") } }
    @Published var invertX = false { didSet { engine.invertX = invertX; defaults.set(invertX, forKey: "invertX") } }
    @Published var invertY = false { didSet { engine.invertY = invertY; defaults.set(invertY, forKey: "invertY") } }
    @Published var nodClick = true { didSet { engine.nodClick = nodClick; defaults.set(nodClick, forKey: "nodClick") } }
    @Published var nodPreset: NodPreset = .normal { didSet { engine.nodPreset = nodPreset; defaults.set(nodPreset.rawValue, forKey: "nodPreset") } }
    @Published var edgeMemory = true { didSet { engine.edgeMemory = edgeMemory; defaults.set(edgeMemory, forKey: "edgeMemory") } }
    @Published var alignment = true { didSet { engine.alignment = alignment; defaults.set(alignment, forKey: "alignment") } }
    @Published var tiltClick = false { didSet { engine.tiltClick = tiltClick; defaults.set(tiltClick, forKey: "tiltClick") } }
    @Published var dwellEnabled = false { didSet { dwell.disarm(at: cursor.pos); dwellProgress = 0; defaults.set(dwellEnabled, forKey: "dwellEnabled") } }
    @Published var dwellDelay = 1.0 { didSet { dwell.delay = dwellDelay; defaults.set(dwellDelay, forKey: "dwellDelay") } }
    @Published var stemScroll = false { didSet { stem.setEnabled(stemScroll && !isPaused); defaults.set(stemScroll, forKey: "stemScroll") } }
    /// Pas de défilement en fraction de hauteur d'écran : petit ⅛, moyen ¼, grand ½.
    @Published var scrollStep = 0.25 { didSet { defaults.set(scrollStep, forKey: "scrollStep") } }
    @Published var toasts = true { didSet { defaults.set(toasts, forKey: "toasts") } }
    @Published var typingPause = true { didSet { defaults.set(typingPause, forKey: "typingPause") } }
    @Published var magnet = true { didSet { if !magnet { cursor.magnetSlowdown = 0 }; defaults.set(magnet, forKey: "magnet") } }
    @Published var magnetStrength: MagnetStrength = .medium { didSet { defaults.set(magnetStrength.rawValue, forKey: "magnetStrength") } }
    @Published var dwellMenu = false { didSet { defaults.set(dwellMenu, forKey: "dwellMenu") } }
    @Published var shakeEscape = false { didSet { defaults.set(shakeEscape, forKey: "shakeEscape") } }
    @Published var autoVoiceOnTextClick = true { didSet { defaults.set(autoVoiceOnTextClick, forKey: "autoVoiceOnTextClick") } }
    @Published var voiceInputMode: VoiceInputMode = .librewispr { didSet { defaults.set(voiceInputMode.rawValue, forKey: "voiceInputMode") } }
    @Published var onboardingDone = false { didSet { defaults.set(onboardingDone, forKey: "onboardingDone") } }
    @Published private(set) var isCalibrated = false

    // MARK: Moteur
    private(set) var engine = PointerEngine()
    private var dwell = DwellClicker()
    private let stem = StemScrollService()
    private var stepper = ScrollStepper(baseStep: 240)
    private var typing = TypingGuard()
    private var scroller = HeadScroller()
    private var shake = ShakeDetector()
    private var keyMonitor: Any?
    private var lastMagnetCheck = Date.distantPast
    private var lastMagnetPos = CGPoint(x: -9999, y: -9999)
    /// Dernière barre de recherche où la saisie vocale a été lancée automatiquement : évite que le clic automatique
    /// ne relance et n'arrête Librewispr en boucle tant que le curseur reste dans cette même barre.
    private var activeSearchBarRect: CGRect?
    private var quickMenuTarget: CGPoint?
    private var lastVoiceTriggerAt = Date.distantPast
    private var voiceListening = false
    private var foreignMovesSince = Date()
    private let motion = MotionService()
    let cursor = CursorController()
    private var lastTimestamp: TimeInterval?
    private var calibSamples: [(w: V3, g: V3, dt: Double)]?
    private var calibEnd = Date.distantPast
    private var lastRatesPublish = Date.distantPast
    private var timers: [Timer] = []
    private var outputTimer: Timer?
    private var wasActiveOnce = false

    /// Bulle près du curseur (si activé).
    private func toast(_ text: String, _ symbol: String) { if toasts { ToastOverlay.shared.show(text, symbol: symbol) } }

    /// La boucle à 120 images/s ne tourne que si elle sert : au repos (AirPods inactifs, pause), l'appli ne réveille
    /// plus le Mac 120 fois par seconde (mesuré : 1,6 % de processeur au repos avant).
    private func updateOutputLoop() {
        let effectivePaused = isPaused || suspendedForAirDance
        let needed = (status == .active && !effectivePaused) || scrollMode || quickMenu != nil || cursor.hasPendingScroll
        if needed, outputTimer == nil {
            let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.outputTick() } }
            RunLoop.main.add(t, forMode: .common)
            outputTimer = t
        } else if !needed, let t = outputTimer {
            t.invalidate(); outputTimer = nil
            cursor.dropPending(); dwell.disarm(at: cursor.pos); dwellProgress = 0
            CursorOverlay.shared.update(visible: false)
        }
    }
    var onSample: ((CMDeviceMotion) -> Void)?   // vue 3D

    private init() {}

    func start() {
        Log.line("— Démarrage AirPodsMouse \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") —")
        loadSettings()
        motion.onSample = { [weak self] m in self?.handle(m) }
        stem.onSwipe = { [weak self] s in self?.stemSwiped(s) }
        stem.setEnabled(stemScroll)
        // Pause pendant la frappe (les raccourcis ⌃⌥ de l'appli ne comptent pas)
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard !e.modifierFlags.contains([.control, .option]) else { return }
            // Seulement le vrai clavier : les touches du clavier visuel (envoyées par une appli, pid ≠ 0)
            // ne doivent pas figer le curseur, sinon impossible de viser la touche suivante avec la tête.
            guard (e.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) ?? 0) == 0 else { return }
            MainActor.assumeIsolated {
                guard let self, !self.isPaused, self.status == .active else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if self.typingPause && !self.typing.isFrozen(at: now) { Log.line("Frappe : curseur figé") }
                self.typing.keyPressed(at: now)
            }
        }
        // Retour de veille : les capteurs restent souvent muets → on les relance, puis on recentre si actif
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                Log.line("Réveil du Mac : relance des capteurs")
                self?.motion.start()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if !self.isPaused && self.status == .active { self.recenter() }
                        else { self.engine.recenter(); self.dwell.disarm(at: self.cursor.pos) }
                    }
                }
            }
        }
        // Écran réellement branché, débranché ou redimensionné : on recentre seulement si l'appli est active
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated {
                    guard let self, self.cursor.refreshScreens() else { return }
                    Log.line("Écrans modifiés")
                    if !self.isPaused && self.status == .active { self.recenter() }
                    else { self.engine.recenter(); self.dwell.disarm(at: self.cursor.pos) }
                }
            }
        }
        motion.onConnectionChange = { [weak self] c in self?.airPodsConnected = c; if !c { self?.cursor.dropPending() } }
        axTrusted = Permissions.axTrusted
        cursor.allowed = axTrusted
        dwell.disarm(at: cursor.pos)
        // Premier lancement : la demande système « Mouvements » attend son étape de l'accueil
        // (sinon elle apparaît par-dessus l'écran de bienvenue, sans explication).
        if onboardingDone || Permissions.motion != .notDetermined { motion.start() }
        let health = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.healthCheck() } }
        timers = [health]
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
            let rem = calibEnd.timeIntervalSinceNow
            let p = min(max(1.0 - rem / 3.0, 0), 1)
            if abs(p - calibrationProgress) > 0.03 || rem <= 0 { calibrationProgress = p }
            if rem <= 0 { finishCalibration() }
            return
        }
        let out = engine.step(w: w, g: g, dt: rawDt, t: m.timestamp, screen: cursor.screenContext)
        guard !isPaused, !suspendedForAirDance, axTrusted else { cursor.dropPending(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(max(rawDt, 0.001), 0.1)

        // Pause pendant la frappe ou utilisation du vrai trackpad : le moteur suit la tête, mais rien ne bouge ni ne clique
        if cursor.isRealMouseActive { cursor.dropPending(); dwell.disarm(at: cursor.pos); return }
        if cursor.consumeRealMouseResume() { engine.reanchorAfterExternalMove(); cursor.dropPending(); dwell.disarm(at: cursor.pos); return }
        if typingPause && typing.isFrozen(at: now) { cursor.dropPending(); dwell.disarm(at: cursor.pos); return }
        if typing.justResumed(at: now) { engine.reset(); cursor.dropPending(); dwell.disarm(at: cursor.pos); return }   // reprise sans saut

        // Geste « non » = Échap
        if shakeEscape {
            let r = engine.rates(w: w, g: g)
            if shake.update(yawRate: r.yaw, pitchRate: r.pitch, t: now, dt: dt) {
                cursor.dropPending(); cursor.pressEscape(); Log.line("Échap (geste « non »)")
                toast(String(localized: "Échap"), "escape")
                return
            }
        }

        // Mode défilement à la tête : curseur figé, pencher fait défiler ; hochement ou regard de côté pour sortir
        if scrollMode, let a = engine.headAngles {
            if out.click != nil || scroller.shouldExit(yaw: a.yaw) { exitScrollMode(); return }
            cursor.scroll(by: scroller.velocity(pitch: a.pitch) * dt)
            return
        }

        cursor.add(dx: out.dx, dy: out.dy)
        if let c = out.click {
            if quickMenu != nil { closeQuickMenu() }   // un hochement referme le menu de clic rapide
            cursor.flush()   // applique le reste (dont la correction du glissement), puis clique à cet endroit
            click(right: c == .right, source: c == .right ? "inclinaison" : "hochement")
        }
    }

    private func stemSwiped(_ s: StemSwipe) {
        guard !isPaused, axTrusted else { return }
        stepper.baseStep = cursor.screenContext.bounds.height * scrollStep
        let d = stepper.distance(at: ProcessInfo.processInfo.systemUptime, up: s == .up)
        cursor.scroll(by: s == .up ? d : -d)
        updateOutputLoop()
        Log.line("Défilement \(s == .up ? "haut" : "bas") (\(Int(d)) px)")
    }

    private func outputTick() {
        cursor.scrollTick()
        let fresh = motion.lastSampleAt.map { Date().timeIntervalSince($0) < 0.3 } ?? false
        let realMoved = cursor.tick(sensorsFresh: fresh && !isPaused && axTrusted)
        if let rect = activeSearchBarRect, !rect.insetBy(dx: -24, dy: -24).contains(cursor.pos) {
            activeSearchBarRect = nil
        }
        let recentClick = lastClickAt.map { Date().timeIntervalSince($0) < 0.4 } ?? false
        CursorOverlay.shared.update(visible: dwellProgress > 0.03 || recentClick || isDragging || scrollMode)
        let now = ProcessInfo.processInfo.systemUptime

        // Aimant : ~10 fois par seconde en arrière-plan (sans bloquer la boucle à 120 Hz) si le curseur a bougé
        if magnet && status == .active && Date().timeIntervalSince(lastMagnetCheck) > 0.1 {
            let p = cursor.pos
            if hypot(p.x - lastMagnetPos.x, p.y - lastMagnetPos.y) > 1.5 {
                lastMagnetCheck = Date()
                lastMagnetPos = p
                let strength = magnetStrength.slowdown
                ClickableProbe.probeAsync(at: p) { [weak self] hit in
                    guard let self else { return }
                    self.cursor.magnetSlowdown = (self.magnet && hit) ? strength : 0
                }
            }
        }

        // Menu de clic rapide ouvert : viser une action et rester immobile
        if var menu = quickMenu {
            let r = menu.update(cursor: cursor.pos, t: now)
            quickMenu = menu
            switch r {
            case .pending(let h, let p):
                if h != quickMenuHovered { quickMenuHovered = h }
                if abs(p - quickMenuProgress) > 0.02 || (p == 0) != (quickMenuProgress == 0) { quickMenuProgress = p }
            case .chosen(let a):
                let target = quickMenuTarget ?? menu.origin
                closeQuickMenu()
                perform(a, at: target)
            case .cancelled: closeQuickMenu(); Log.line("Menu de clic annulé")
            }
            return
        }

        let typingFrozen = typingPause && typing.isFrozen(at: now)
        let headStillTurning = hypot(headRates.x, headRates.y) > 0.14
        // Empêche les clics automatiques fantômes quand le curseur est bloqué contre un bord de l'écran
        // (ex. quand on tourne la tête sur le côté ou vers le bas hors de l'écran).
        guard dwellEnabled, status == .active, !scrollMode, !typingFrozen,
              !cursor.isPinnedAtScreenEdge, !headStillTurning else {
            if cursor.isPinnedAtScreenEdge || headStillTurning { dwell.reset() }
            if dwellProgress != 0 { dwellProgress = 0 }
            return
        }
        let r = dwell.update(cursor: cursor.pos, t: now, realMouseMoved: realMoved)
        if abs(r.progress - dwellProgress) > 0.02 || (r.progress == 0) != (dwellProgress == 0) { dwellProgress = r.progress }
        guard r.fire else { return }
        if dwellMenu && !isDragging { openQuickMenu(at: cursor.pos, t: now) }
        else { click(right: false, source: "automatique") }
    }

    // MARK: - Menu de clic rapide

    private func openQuickMenu(at p: CGPoint, t: Double) {
        let b = cursor.screenContext.bounds
        let margin: CGFloat = 140
        let clamped = CGPoint(x: min(max(p.x, b.minX + margin), b.maxX - margin),
                              y: min(max(p.y, b.minY + margin), b.maxY - margin))
        if clamped != p { cursor.moveTo(clamped) }
        quickMenuTarget = p
        quickMenu = DwellMenu(origin: clamped, openedAt: t)
        quickMenuHovered = nil; quickMenuProgress = 0; dwellProgress = 0
        QuickMenuOverlay.shared.show(at: clamped)
        Log.line("Menu de clic ouvert")
    }

    private func closeQuickMenu() {
        quickMenu = nil; quickMenuHovered = nil; quickMenuProgress = 0; quickMenuTarget = nil
        QuickMenuOverlay.shared.hide()
        dwell.disarm(at: cursor.pos)
    }

    private func perform(_ a: DwellMenu.Action, at origin: CGPoint) {
        cursor.moveTo(origin)
        switch a {
        case .click: click(right: false, source: "menu")
        case .doubleClick:
            cursor.doubleClick()
            lastClickAt = Date()
            Log.line("Double-clic (menu) en \(Int(cursor.pos.x)),\(Int(cursor.pos.y))")
        case .rightClick: click(right: true, source: "menu")
        case .drag: toggleDrag()
        case .scroll: toggleScrollMode()
        }
    }

    // MARK: - Glisser-déposer et défilement à la tête

    /// Attrape (bouton enfoncé) ou lâche. Le clic suivant (hochement, clic auto) lâche aussi.
    func toggleDrag() {
        guard axTrusted, !isPaused else { return }
        if cursor.dragging { cursor.endDrag(); isDragging = false; Log.line("Lâché"); toast(String(localized: "Lâché"), "hand.raised.fill") }
        else {
            cursor.startDrag(); isDragging = true; Log.line("Attrapé (glisser)")
            toast(String(localized: "Attrapé — hoche la tête pour lâcher"), "hand.draw.fill")
        }
        lastClickAt = Date()
    }

    func toggleScrollMode() {
        if scrollMode { exitScrollMode(); return }
        guard axTrusted, !isPaused, let a = engine.headAngles else { return }
        scroller.start(yaw: a.yaw, pitch: a.pitch)
        cursor.dropPending()
        scrollMode = true
        updateOutputLoop()
        Log.line("Mode défilement : penche la tête")
        toast(String(localized: "Défilement : penche la tête, hoche pour arrêter"), "arrow.up.and.down.circle.fill")
    }

    private func exitScrollMode() {
        guard scrollMode else { return }
        scrollMode = false
        engine.reset(); cursor.dropPending()
        Log.line("Fin du mode défilement")
        toast(String(localized: "Fin du défilement"), "checkmark.circle.fill")
    }

    func startVoiceInput() {
        if voiceListening { stopVoiceInput(); return }
        lastVoiceTriggerAt = Date()
        let msg = HandsFree.triggerVoiceInput(mode: voiceInputMode)
        if voiceInputMode == .librewispr {
            voiceListening = true
            isVoiceListening = true
            toast(String(localized: "Parle — reclique dans la barre pour arrêter"), "mic.fill")
        } else {
            toast(msg, "mic.fill")
        }
    }

    /// Arrête l'écoute Librewispr (même raccourci qu'au lancement : Librewispr colle alors le texte).
    func stopVoiceInput() {
        voiceListening = false
        isVoiceListening = false
        activeSearchBarRect = nil
        if HandsFree.stopLibrewispr() {
            Log.line("Fin d'écoute Librewispr")
            toast(String(localized: "Écoute arrêtée"), "mic.slash.fill")
        }
    }

    private func click(right: Bool, source: String) {
        if cursor.dragging && !right { toggleDrag(); return }   // pendant un glisser, « cliquer » lâche
        cursor.click(right: right)
        lastClickAt = Date()
        let clickedPos = cursor.pos
        Log.line("Clic \(right ? "droit" : "gauche") (\(source)) en \(Int(clickedPos.x)),\(Int(clickedPos.y))")
        if !right, autoVoiceOnTextClick {
            // Si on est déjà dans la même barre de recherche et que le clic automatique se redéclenche,
            // on ne coupe pas l'enregistrement en cours et on ne relance pas en boucle.
            if let activeRect = activeSearchBarRect, activeRect.insetBy(dx: -16, dy: -16).contains(clickedPos) {
                if source == "automatique" { return }
                // Un hochement volontaire pendant que Librewispr écoute permet d'arrêter et coller le texte
                if voiceInputMode == .librewispr, HandsFree.isLibrewisprRecording(),
                   Date().timeIntervalSince(lastVoiceTriggerAt) > 1.2 {
                    Log.line("Hochement dans la barre de recherche → fin d'écoute Librewispr")
                    startVoiceInput()
                }
                return
            }
            // Si Librewispr est déjà en train d'enregistrer, on ne le coupe pas sur un clic ailleurs
            if voiceInputMode == .librewispr, HandsFree.isLibrewisprRecording() { return }
            ClickableProbe.probeSearchBarAsync(at: clickedPos) { [weak self] match in
                guard let self, self.autoVoiceOnTextClick, !self.isPaused, let match else { return }
                if self.voiceInputMode == .librewispr, HandsFree.isLibrewisprRecording() { return }
                self.activeSearchBarRect = match.rect
                Log.line("Barre de recherche détectée : \(match.summary) → lancement vocal")
                self.startVoiceInput()
            }
        }
    }

    private func healthCheck() {
        let airDanceFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.paul.airdance"
        if airDanceFront != suspendedForAirDance {
            suspendedForAirDance = airDanceFront
            if airDanceFront {
                if cursor.dragging { toggleDrag() }
                exitScrollMode()
                if quickMenu != nil { closeQuickMenu() }
                cursor.dropPending(); dwell.disarm(at: cursor.pos); dwellProgress = 0
                // Ne JAMAIS appeler motion.stop() ici : chaque stop/start provoque une déconnexion/reconnexion
                // dans audioaccessoryd qui coupe aussi le flux d'AirDance ! On ignore simplement les mesures.
                Log.line("AirDance au premier plan : pointeur mis en veille automatique")
            } else {
                engine.reanchorAfterExternalMove(); cursor.dropPending(); dwell.disarm(at: cursor.pos)
                Log.line("AirDance quitté/arrière-plan : reprise automatique du pointeur")
            }
        }
        motion.healthCheck(paused: isPaused || suspendedForAirDance)
        // Synchronise l'état d'écoute Librewispr si l'utilisateur l'a coupé au clavier ou par silence.
        if voiceListening {
            if Date().timeIntervalSince(lastVoiceTriggerAt) > 180
                || (Date().timeIntervalSince(lastVoiceTriggerAt) > 3.5 && !HandsFree.isLibrewisprRecording()) {
                voiceListening = false
                isVoiceListening = false
                activeSearchBarRect = nil
            }
        }
        // Diagnostic : beaucoup de reprises « vraie souris » sans toucher au trackpad = une autre appli bouge le curseur
        if Date().timeIntervalSince(foreignMovesSince) >= 60 {
            if cursor.foreignMoves > 30 && status == .active {
                Log.line("⚠️ Curseur déplacé \(cursor.foreignMoves) fois par une autre source en 1 min (trackpad, ou autre appli qui bouge la souris)")
            }
            cursor.foreignMoves = 0
            foreignMovesSince = Date()
        }
        motionAuth = Permissions.motion
        let trusted = Permissions.axTrusted
        if trusted != axTrusted {
            Log.line(trusted ? "Accessibilité accordée ✅" : "Accessibilité retirée")
            if !trusted && cursor.dragging { cursor.endDrag(); isDragging = false }   // relâcher avant de perdre la main
            axTrusted = trusted
            cursor.allowed = trusted
        }
        let new = Status.resolve(available: motion.isAvailable,
                                 motionDenied: motionAuth == .denied || motionAuth == .restricted,
                                 calibrating: calibSamples != nil,
                                 streaming: motion.isStreaming,
                                 sinceStart: motion.secondsSinceInitialStart,
                                 paused: isPaused || suspendedForAirDance)
        if new != status {
            if new != .active && new != .paused && cursor.dragging { toggleDrag(); Log.line("Glisser relâché (plus de mouvement)") }
            if status == .active && new == .noMotion { toast(String(localized: "AirPods : plus de mouvement"), "exclamationmark.triangle.fill") }
            if new == .active && wasActiveOnce && (status == .noMotion || status == .searching) { toast(String(localized: "AirPods de retour"), "airpodspro") }
            if new == .active { wasActiveOnce = true }
            status = new; Log.line("État : \(new)")
        }
        updateOutputLoop()
    }

    // MARK: - Actions

    func togglePause() {
        isPaused.toggle()
        Log.line(isPaused ? "Pause" : "Reprise")
        toast(isPaused ? String(localized: "En pause — ⌃⌥P pour reprendre") : String(localized: "Reprise"),
              isPaused ? "pause.circle.fill" : "play.circle.fill")
        if isPaused { if cursor.dragging { toggleDrag() }; exitScrollMode(); if quickMenu != nil { closeQuickMenu() } }
        stem.setEnabled(stemScroll && !isPaused)   // en pause, la tige règle à nouveau le volume
        cursor.dropPending(); engine.reset(); dwell.disarm(at: cursor.pos); dwellProgress = 0
        healthCheck()
    }

    /// « Je regarde le centre de l'écran » : la direction actuelle de la tête devient le centre.
    func recenter() {
        engine.recenter()
        cursor.moveToCenter()
        dwell.disarm(at: cursor.pos)
        dwellProgress = 0
        toast(String(localized: "Recentré"), "scope")
        Log.line("Recentré")
    }

    func startCalibration() {
        guard motion.isStreaming else { calibrationMessage = String(localized: "Les AirPods n'envoient aucun mouvement : mets-les dans tes oreilles."); return }
        calibrationMessage = String(localized: "Hoche la tête de haut en bas…")
        calibrationProgress = 0
        calibSamples = []
        calibEnd = Date().addingTimeInterval(3)
        toast(String(localized: "Hoche la tête de haut en bas…"), "arrow.up.and.down.circle.fill")
        NSSound(named: "Tink")?.play()
        healthCheck()
    }

    /// Trouve l'axe haut/bas : axe principal des rotations horizontales pendant 3 s de « oui » de la tête.
    private func finishCalibration() {
        guard let samples = calibSamples else { return }
        calibSamples = nil
        calibrationProgress = 0
        defer { healthCheck() }
        guard let axis = CalibrationSolver.solvePitchAxis(samples: samples) else {
            let s = samples.count <= 15
                ? String(localized: "Aucun mouvement reçu pendant le calibrage.")
                : String(localized: "Pas assez de mouvement : lève la tête plus franchement.")
            calibrationMessage = s; NSSound(named: "Basso")?.play(); Log.line(s)
            return
        }
        engine.axis = axis
        engine.reset(); cursor.dropPending()
        defaults.set([axis.x, axis.y, axis.z], forKey: "vAxis")
        isCalibrated = true
        calibrationMessage = String(localized: "Calibré ✅")
        toast(String(localized: "Calibré ✅"), "checkmark.circle.fill")
        NSSound(named: "Glass")?.play()
        Log.line("Calibré : \(axis)")
    }

    func resetSettings() {
        for k in ["sensitivity", "verticalRatio", "invertX", "invertY", "nodClick", "nodPreset", "tiltClick", "dwellEnabled", "dwellDelay", "vAxis", "edgeMemory", "alignment", "stemScroll", "scrollStep", "typingPause", "magnet", "magnetStrength", "dwellMenu", "shakeEscape", "autoVoiceOnTextClick", "voiceInputMode", "toasts"] {
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
        let version = defaults.integer(forKey: "settingsVersion")
        if version < 3 {
            for k in ["gain", "click", "flickEnabled", "rightClick", "vAxis"] { defaults.removeObject(forKey: k) }
        }
        if version < 4 {
            // Alignement tête ↔ écran et aimant désormais désactivés par défaut : l'alignement dérive avec le
            // gyroscope des AirPods (mesuré ~1 400 px/min sur un enregistrement) et tirait le curseur loin de la visée ;
            // l'aimant freinait la visée sur chaque icône de la barre des menus. Sans eux, le pointage est celui de la
            // version 2.0 d'origine. Le calibrage haut/bas est conservé.
            for k in ["alignment", "magnet"] { defaults.removeObject(forKey: k) }
        }
        if version < 5 {
            // Aimant refait (progressif, réglable, plus fort par défaut) : de nouveau activé
            defaults.removeObject(forKey: "magnet")
        }
        if version < 6 {
            // Dérive à vide du gyroscope corrigée + mémoire des 4 bords : alignement tête ↔ écran réactivé par défaut !
            for k in ["alignment", "edgeMemory"] { defaults.removeObject(forKey: k) }
        }
        if version < Self.settingsVersion { defaults.set(Self.settingsVersion, forKey: "settingsVersion") }
        func d(_ k: String, _ def: Double) -> Double { defaults.object(forKey: k) != nil ? defaults.double(forKey: k) : def }
        func b(_ k: String, _ def: Bool) -> Bool { defaults.object(forKey: k) != nil ? defaults.bool(forKey: k) : def }
        sensitivity = min(max(d("sensitivity", 1), 0.3), 3)
        verticalRatio = min(max(d("verticalRatio", 2.4), 1.5), 3.5)
        invertX = b("invertX", false)
        invertY = b("invertY", false)
        nodClick = b("nodClick", true)
        nodPreset = NodPreset(rawValue: defaults.integer(forKey: "nodPreset")).flatMap { defaults.object(forKey: "nodPreset") != nil ? $0 : nil } ?? .normal
        tiltClick = b("tiltClick", false)
        edgeMemory = b("edgeMemory", true)
        alignment = b("alignment", true)
        stemScroll = b("stemScroll", false)
        typingPause = b("typingPause", true)
        toasts = b("toasts", true)
        magnet = b("magnet", true)
        magnetStrength = defaults.object(forKey: "magnetStrength") != nil
            ? MagnetStrength(rawValue: defaults.integer(forKey: "magnetStrength")) ?? .medium : .medium
        dwellMenu = b("dwellMenu", false)
        shakeEscape = b("shakeEscape", false)
        autoVoiceOnTextClick = b("autoVoiceOnTextClick", true)
        voiceInputMode = defaults.object(forKey: "voiceInputMode") != nil
            ? VoiceInputMode(rawValue: defaults.integer(forKey: "voiceInputMode")) ?? .librewispr : .librewispr
        scrollStep = [0.125, 0.25, 0.5].contains(d("scrollStep", 0.25)) ? d("scrollStep", 0.25) : 0.25
        dwellEnabled = b("dwellEnabled", false)
        dwellDelay = min(max(d("dwellDelay", 1), 0.6), 2)
        onboardingDone = b("onboardingDone", false)
        if let a = defaults.array(forKey: "vAxis") as? [Double], a.count == 3 {
            engine.axis = V3(a[0], a[1], a[2]); isCalibrated = true
        } else { engine.axis = nil; isCalibrated = false }
    }
}
