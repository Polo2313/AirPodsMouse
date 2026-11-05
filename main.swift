// AirPodsMouse — utilise le boîtier ouvert (avec les AirPods dedans) comme pointeur.
// Gauche/droite : rotation autour de la verticale (calculée avec la gravité, indépendante
//                 de la façon dont les écouteurs sont couchés dans le boîtier)
// Haut/bas      : axe appris pendant le calibrage (⌃⌥C)
// Tourner le poignet (comme une clé) : clic gauche
// Petit coup sec haut/bas : clic droit (désactivable)
//
// Raccourcis globaux : ⌃⌥Q quitter · ⌃⌥P pause · ⌃⌥C calibrer · ⌃⌥V vue 3D
import AppKit
import CoreMotion
import ApplicationServices
import Carbon
import simd

typealias V3 = SIMD3<Double>

func registerHotKeys() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
        var hk = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
        switch hk.id {
        case 1: NSApp.terminate(nil)
        case 2: delegate.togglePause()
        case 3: delegate.startCalibration()
        case 4: delegate.showViewer()
        default: break
        }
        return noErr
    }, 1, &spec, nil, nil)
    let mods = UInt32(controlKey | optionKey)
    for (id, key) in [(UInt32(1), kVK_ANSI_Q), (UInt32(2), kVK_ANSI_P), (UInt32(3), kVK_ANSI_C), (UInt32(4), kVK_ANSI_V)] {
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(key), mods, EventHotKeyID(signature: OSType(0x41504D53), id: id),
                            GetApplicationEventTarget(), 0, &ref)
    }
}

/// Détecte un mouvement rapide « aller-retour » autour d'un axe.
struct QuickGesture {
    let threshold: Double
    var start: Date?
    var sign: Double = 0
    /// Retourne true quand le geste est complet. `freeze` passe à true pendant le geste.
    mutating func update(_ r: Double, now: Date, freeze: inout Date) -> Bool {
        if let s = start {
            if now.timeIntervalSince(s) > 0.5 { start = nil; return false }
            if abs(r) > threshold && (r < 0) != (sign < 0) {
                start = nil
                freeze = max(freeze, now.addingTimeInterval(0.3))
                return true
            }
        } else if abs(r) > threshold {
            start = now; sign = r
            freeze = max(freeze, now.addingTimeInterval(0.5))
        }
        return false
    }
}

final class AirPodsMouse: NSObject, NSApplicationDelegate, CMHeadphoneMotionManagerDelegate {
    let motion = CMHeadphoneMotionManager()
    let defaults = UserDefaults.standard
    var statusItem: NSStatusItem!
    lazy var viewer = Viewer3D()

    // État
    var paused = false
    var invertX = false
    var invertY = false
    var flickEnabled = false            // désactivé par défaut : évite les clics accidentels
    var twistEnabled = true
    var vAxis: V3?                      // axe haut/bas dans le repère des écouteurs
    var lastTimestamp: TimeInterval?
    var velocity = SIMD2<Double>(0, 0)  // px/s lissée
    var pos = CGPoint.zero
    var lastPosted = CGPoint(x: -1, y: -1)

    // Réglages
    var gain: Double = 900              // pixels par radian
    let accel: Double = 1.5             // accélération : mouvements rapides = plus loin
    let deadZone: Double = 0.06         // rad/s ignorés (tremblements)
    let smoothing: Double = 0.35        // 0..1, plus petit = plus lisse

    // Calibrage
    var calibSamples: [(w: V3, g: V3, dt: Double)]?
    var calibEnd = Date.distantPast

    // Gestes
    var flick = QuickGesture(threshold: 4.0)   // coup sec haut/bas -> clic droit
    var twist = QuickGesture(threshold: 3.5)   // rotation du poignet -> clic gauche
    var frozenUntil = Date.distantPast
    var lastClick = Date.distantPast

    func applicationDidFinishLaunching(_ n: Notification) {
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            viewer.renderSnapshot(to: CommandLine.arguments[i + 1]); exit(0)
        }
        loadSettings()
        buildMenu()
        registerHotKeys()
        print("Raccourcis : ⌃⌥Q quitter · ⌃⌥P pause · ⌃⌥C calibrer · ⌃⌥V vue 3D")
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            setStatus("⚠️ Autorise AirPodsMouse dans Accessibilité, puis relance.")
        }
        guard motion.isDeviceMotionAvailable else { setStatus("❌ Capteurs de mouvement indisponibles."); return }
        motion.delegate = self
        pos = CGEvent(source: nil)?.location ?? .zero
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, err in
            if let err { self?.setStatus("Erreur : \(err.localizedDescription)"); return }
            if let m { self?.handle(m) }
        }
        setStatus(vAxis == nil ? "Pas encore calibré : fais ⌃⌥C" : "Actif")
        if CommandLine.arguments.contains("--3d") { showViewer() }
    }

    // MARK: - Mouvement

    func handle(_ m: CMDeviceMotion) {
        let dt = min(max(lastTimestamp.map { m.timestamp - $0 } ?? 0.02, 0.001), 0.1)
        lastTimestamp = m.timestamp
        let w = V3(m.rotationRate.x, m.rotationRate.y, m.rotationRate.z)
        let g = simd_normalize(V3(m.gravity.x, m.gravity.y, m.gravity.z))

        if viewerOpen {
            let a0 = vAxis ?? defaultAxis(g)
            var ah = a0 - simd_dot(a0, g) * g
            if simd_length(ah) < 0.2 { ah = defaultAxis(g) }
            let fwd = simd_cross(simd_normalize(ah), g)
            let cq = m.attitude.quaternion
            viewer.update(q: simd_quatd(ix: cq.x, iy: cq.y, iz: cq.z, r: cq.w), g: g, forward: fwd,
                          yawRate: -simd_dot(w, g),
                          pitchRate: simd_dot(w, simd_normalize(ah)))
        }

        if calibSamples != nil {
            calibSamples!.append((w, g, dt))
            if Date() >= calibEnd { finishCalibration() }
            return
        }
        guard !paused else { return }

        // Vitesse de rotation autour de la verticale (gauche/droite)
        let yawRate = -simd_dot(w, g)   // + = vers la gauche
        // Vitesse autour de l'axe haut/bas (projeté à l'horizontale)
        var a = vAxis ?? defaultAxis(g)
        a = a - simd_dot(a, g) * g
        let pitchRate = simd_length(a) > 0.2 ? simd_dot(w, simd_normalize(a)) : 0   // + = vers le haut

        // Axe de pointage (vers l'écran) = perpendiculaire à la verticale et à l'axe haut/bas
        let now = Date()
        if twistEnabled, vAxis != nil, simd_length(a) > 0.2 {
            let forward = simd_normalize(simd_cross(simd_normalize(a), g))
            if twist.update(simd_dot(w, forward), now: now, freeze: &frozenUntil) { click(right: false) }   // tourner le poignet = clic gauche
        }
        if flickEnabled, twist.start == nil,
           flick.update(pitchRate, now: now, freeze: &frozenUntil) { click(right: true) }   // coup sec = clic droit
        if Date() < frozenUntil { velocity = .zero; return }

        let target = SIMD2(-curve(yawRate) * (invertX ? -1 : 1),
                           -curve(pitchRate) * (invertY ? -1 : 1))
        velocity += (target - velocity) * smoothing
        if velocity == .zero { return }

        // Si l'utilisateur a bougé la vraie souris/trackpad, on repart de là
        if let cur = CGEvent(source: nil)?.location,
           abs(cur.x - lastPosted.x) > 3 || abs(cur.y - lastPosted.y) > 3 { pos = cur }

        let bounds = CGDisplayBounds(CGMainDisplayID())
        pos.x = min(max(pos.x + velocity.x * dt, bounds.minX), bounds.maxX - 1)
        pos.y = min(max(pos.y + velocity.y * dt, bounds.minY), bounds.maxY - 1)
        let p = CGPoint(x: pos.x.rounded(), y: pos.y.rounded())
        if p != lastPosted {
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            lastPosted = p
        }
    }

    /// rad/s -> px/s avec zone morte et accélération
    func curve(_ r: Double) -> Double {
        let m = abs(r) - deadZone
        guard m > 0 else { return 0 }
        return (r < 0 ? -1 : 1) * m * gain * (1 + accel * m)
    }

    func defaultAxis(_ g: V3) -> V3 { abs(g.x) < 0.7 ? V3(1, 0, 0) : V3(0, 1, 0) }

    // MARK: - Calibrage

    @objc func startCalibration() {
        calibSamples = []
        calibEnd = Date().addingTimeInterval(3)
        statusItem.button?.title = "⬆️⬇️"
        setStatus("Calibrage : pointe l'écran, incline le boîtier VERS LE HAUT puis reviens, 2-3 fois (3 s)")
        NSSound(named: "Tink")?.play()
    }

    func finishCalibration() {
        guard let samples = calibSamples else { return }
        calibSamples = nil
        statusItem.button?.title = "🎧🖱"
        // Composantes horizontales des rotations, puis axe principal (analyse en composantes principales)
        var cov = simd_double3x3(0)
        var hs: [(V3, Double)] = []
        for s in samples {
            let h = s.w - simd_dot(s.w, s.g) * s.g
            hs.append((h, s.dt))
            cov += simd_double3x3(columns: (h * h.x, h * h.y, h * h.z))
        }
        var axis = V3(1, 1, 1)
        for _ in 0..<50 { let n = cov * axis; if simd_length(n) < 1e-9 { break }; axis = simd_normalize(n) }
        // Signe : le premier grand mouvement doit être vers le haut
        var theta = 0.0, extreme = 0.0
        for (h, dt) in hs {
            theta += simd_dot(h, axis) * dt
            if abs(theta) > abs(extreme) { extreme = theta }
        }
        guard abs(extreme) > 0.15 else {
            setStatus("❌ Pas assez de mouvement — refais ⌃⌥C en inclinant plus franchement")
            NSSound(named: "Basso")?.play()
            return
        }
        if extreme < 0 { axis = -axis }
        vAxis = axis
        defaults.set([axis.x, axis.y, axis.z], forKey: "vAxis")
        velocity = .zero
        pos = CGEvent(source: nil)?.location ?? pos
        if viewerOpen { viewer.recenter() }
        setStatus("✅ Calibré — Actif")
        NSSound(named: "Glass")?.play()
    }

    // MARK: - Clics

    func click(right: Bool) {
        let now = Date()
        guard now.timeIntervalSince(lastClick) > 0.6 else { return }
        lastClick = now
        if viewerOpen { viewer.flash(right ? .systemOrange : .systemBlue) }
        let p = CGEvent(source: nil)?.location ?? pos
        let (down, up, btn): (CGEventType, CGEventType, CGMouseButton) =
            right ? (.rightMouseDown, .rightMouseUp, .right) : (.leftMouseDown, .leftMouseUp, .left)
        CGEvent(mouseEventSource: nil, mouseType: down, mouseCursorPosition: p, mouseButton: btn)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: p, mouseButton: btn)?.post(tap: .cghidEventTap)
    }

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) { setStatus("AirPods connectés ✅") }
    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) { setStatus("AirPods déconnectés") }

    // MARK: - Réglages / menu

    func loadSettings() {
        if let a = defaults.array(forKey: "vAxis") as? [Double], a.count == 3 { vAxis = V3(a[0], a[1], a[2]) }
        if defaults.object(forKey: "gain") != nil { gain = defaults.double(forKey: "gain") }
        invertX = defaults.bool(forKey: "invertX")
        invertY = defaults.bool(forKey: "invertY")
        flickEnabled = defaults.bool(forKey: "click")
        if defaults.object(forKey: "rightClick") != nil { twistEnabled = defaults.bool(forKey: "rightClick") }
    }

    let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    lazy var pauseItem = item("Pause  (⌃⌥P)", #selector(togglePause))
    lazy var invertXItem = item("Inverser gauche/droite", #selector(toggleInvertX))
    lazy var invertYItem = item("Inverser haut/bas", #selector(toggleInvertY))
    lazy var flickItem = item("Clic droit : petit coup sec", #selector(toggleFlick))
    lazy var twistItem = item("Clic gauche : tourner le poignet", #selector(toggleTwist))

    func item(_ t: String, _ s: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: s, keyEquivalent: ""); i.target = self; return i
    }

    func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🎧🖱"
        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(item("Calibrer  (⌃⌥C)", #selector(startCalibration)))
        menu.addItem(item("Vue 3D  (⌃⌥V)", #selector(showViewer)))
        menu.addItem(pauseItem)
        menu.addItem(invertXItem); invertXItem.state = invertX ? .on : .off
        menu.addItem(invertYItem); invertYItem.state = invertY ? .on : .off
        menu.addItem(flickItem); flickItem.state = flickEnabled ? .on : .off
        menu.addItem(twistItem); twistItem.state = twistEnabled ? .on : .off
        menu.addItem(item("Sensibilité +", #selector(sensUp)))
        menu.addItem(item("Sensibilité −", #selector(sensDown)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter  (⌃⌥Q)", action: #selector(NSApp.terminate(_:)), keyEquivalent: ""))
        statusItem.menu = menu
    }

    func setStatus(_ s: String) { statusLine.title = s; print(s) }

    @objc func togglePause() { paused.toggle(); velocity = .zero; pauseItem.state = paused ? .on : .off
        statusItem.button?.title = paused ? "🎧⏸" : "🎧🖱" }
    @objc func toggleInvertX() { invertX.toggle(); invertXItem.state = invertX ? .on : .off; defaults.set(invertX, forKey: "invertX") }
    @objc func toggleInvertY() { invertY.toggle(); invertYItem.state = invertY ? .on : .off; defaults.set(invertY, forKey: "invertY") }
    @objc func toggleFlick() { flickEnabled.toggle(); flickItem.state = flickEnabled ? .on : .off; defaults.set(flickEnabled, forKey: "click") }
    var viewerOpen = false
    @objc func showViewer() { viewerOpen = true; viewer.show() }
    @objc func toggleTwist() { twistEnabled.toggle(); twistItem.state = twistEnabled ? .on : .off; defaults.set(twistEnabled, forKey: "rightClick") }
    @objc func sensUp() { gain *= 1.25; defaults.set(gain, forKey: "gain") }
    @objc func sensDown() { gain /= 1.25; defaults.set(gain, forKey: "gain") }
}

let app = NSApplication.shared
let delegate = AirPodsMouse()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
