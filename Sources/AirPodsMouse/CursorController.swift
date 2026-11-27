import AppKit
import AirPodsMouseCore
import CoreGraphics

/// Déplace le curseur et clique, en envoyant de vrais événements souris (autorisation Accessibilité requise).
@MainActor
final class CursorController {
    /// Signature unique posée sur chaque événement `CGEvent` émis par AirPodsMouse (`"APMS20"`),
    /// pour distinguer à 100 % nos propres déplacements de ceux du vrai trackpad/souris physique sans faux positifs.
    nonisolated static let eventTag: Int64 = 0x4150_4D53_3230
    nonisolated static let myPID = Int64(ProcessInfo.processInfo.processIdentifier)

    private let source = CGEventSource(stateID: .hidSystemState)
    private(set) var pos = CGPoint.zero
    /// Faux tant que l'Accessibilité n'est pas accordée (mis à jour chaque seconde par AppModel).
    var allowed = false
    private var pending = CGPoint.zero          // reçu des capteurs, pas encore appliqué
    private var lastPosted = CGPoint(x: -9999, y: -9999)
    private var screens: [CGRect] = []
    private var lastRealMouseAt: TimeInterval = -10
    private var wasRealMouseActive = false
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    /// Nombre de fois où le curseur a été déplacé par autre chose que nous (diagnostic, remis à zéro par l'appelant).
    var foreignMoves = 0

    private var lastClick = Date.distantPast
    private var lastClickRight = false
    private var lastClickPos = CGPoint.zero
    private var clickCount = 0

    init() {
        pos = CGEvent(source: nil)?.location ?? .zero
        _ = refreshScreens()
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] e in
            Self.handleMonitorEvent(e, controller: self)
        }
        // Indispensable quand la fenêtre de réglages d'AirPodsMouse est au premier plan !
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
            Self.handleMonitorEvent(e, controller: self)
            return e
        }
    }

    nonisolated private static func handleMonitorEvent(_ e: NSEvent, controller: CursorController?) {
        guard let cg = e.cgEvent else { return }
        if cg.getIntegerValueField(.eventSourceUserData) == Self.eventTag { return }
        if cg.getIntegerValueField(.eventSourceUnixProcessID) == Self.myPID { return }
        let loc = cg.location
        let t = ProcessInfo.processInfo.systemUptime
        MainActor.assumeIsolated {
            guard let controller else { return }
            guard hypot(loc.x - controller.pos.x, loc.y - controller.pos.y) > 1.5 else { return }
            controller.pos = loc
            controller.lastPosted = loc
            controller.pending = .zero
            controller.lastRealMouseAt = t
            controller.wasRealMouseActive = true
            controller.foreignMoves += 1
        }
    }

    /// Vrai pendant que l'utilisateur déplace la vraie souris ou le trackpad (et 0,35 s après),
    /// pour laisser la main au trackpad sans figer la tête longtemps après l'arrêt.
    var isRealMouseActive: Bool {
        ProcessInfo.processInfo.systemUptime - lastRealMouseAt < 0.35
    }

    /// Vrai une seule fois au moment où la main repasse du trackpad à la tête (reprise sans saut).
    func consumeRealMouseResume() -> Bool {
        guard wasRealMouseActive, !isRealMouseActive else { return false }
        wasRealMouseActive = false
        return true
    }

    /// Aimant : > 0 quand le curseur survole un élément cliquable (part de vitesse retirée en visée fine).
    var magnetSlowdown = 0.0

    func add(dx: Double, dy: Double) {
        // Freinage progressif : fort en visée fine, nul pour un mouvement franc (voir Magnet)
        let k = magnetSlowdown > 0 ? Magnet.factor(step: hypot(dx, dy), slowdown: magnetSlowdown) : 1
        pending.x += dx * k; pending.y += dy * k
    }

    // MARK: - Glisser-déposer
    private(set) var dragging = false

    func startDrag() {
        guard allowed, !dragging else { return }
        flush()
        let p = CGPoint(x: pos.x.rounded(), y: pos.y.rounded())
        let e = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)
        e?.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        e?.post(tap: .cghidEventTap)
        dragging = true
    }

    func endDrag() {
        guard dragging else { return }
        flush()
        let p = CGPoint(x: pos.x.rounded(), y: pos.y.rounded())
        let e = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)
        e?.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        e?.post(tap: .cghidEventTap)
        dragging = false
    }

    /// Place le curseur à un point précis (retour au point d'origine après le menu de clic rapide).
    func moveTo(_ p: CGPoint) { pending = .zero; move(by: CGPoint(x: p.x - pos.x, y: p.y - pos.y)) }

    /// Envoie la touche Échap (geste « non »).
    func pressEscape() {
        guard allowed else { return }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: down)
            e?.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
            e?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Défilement (réparti sur quelques images pour être fluide)
    private var pendingScroll = 0.0
    var hasPendingScroll: Bool { abs(pendingScroll) >= 1 }

    /// - Parameter pixels: > 0 = vers le haut du document, < 0 = vers le bas.
    func scroll(by pixels: Double) { pendingScroll += pixels }

    /// À chaque image : envoie une part du défilement en attente.
    func scrollTick() {
        guard allowed, abs(pendingScroll) >= 1 else { pendingScroll = 0; return }
        var step = (pendingScroll * 0.2).rounded()
        if abs(step) < 1 { step = pendingScroll > 0 ? 1 : -1 }
        pendingScroll -= step
        let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1, wheel1: Int32(step), wheel2: 0, wheel3: 0)
        e?.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        e?.post(tap: .cghidEventTap)
    }

    func dropPending() { pending = .zero }

    /// Applique tout le déplacement en attente d'un coup (avant un clic).
    func flush() { move(by: pending); pending = .zero }

    /// 120 fois par seconde : applique progressivement le déplacement reçu. Les capteurs envoient ~50 mesures/s
    /// par paquets irréguliers ; sans ça, le curseur avance par à-coups.
    /// - Parameter sensorsFresh: false si la dernière mesure date de plus de 0,3 s (AirPods retirés…) :
    ///   on jette le reste pour que le curseur s'arrête net.
    /// - Returns: true si le vrai trackpad/souris a bougé le curseur récemment.
    @discardableResult
    func tick(sensorsFresh: Bool) -> Bool {
        let real = isRealMouseActive
        guard sensorsFresh, !real else { pending = .zero; return real }
        guard pending != .zero else { return false }
        var step = CGPoint(x: pending.x * 0.35, y: pending.y * 0.35)
        if abs(pending.x) < 0.6 && abs(pending.y) < 0.6 { step = pending }
        pending.x -= step.x; pending.y -= step.y
        move(by: step)
        return false
    }

    /// Vrai si le curseur est collé contre un bord extérieur de l'écran (ex. tête tournée hors de l'écran).
    var isPinnedAtScreenEdge: Bool {
        let b = screenContext.bounds
        return pos.x <= b.minX + 1.5 || pos.x >= b.maxX - 2.5 || pos.y >= b.maxY - 2.5
    }

    private func move(by d: CGPoint) {
        guard d != .zero, allowed else { return }
        let old = pos
        pos = clampToScreens(CGPoint(x: pos.x + d.x, y: pos.y + d.y), from: old)
        let p = CGPoint(x: pos.x.rounded(), y: pos.y.rounded())
        guard p != lastPosted else { return }
        let prev = lastPosted.x < -9000 ? old : lastPosted
        let e = CGEvent(mouseEventSource: source, mouseType: dragging ? .leftMouseDragged : .mouseMoved,
                        mouseCursorPosition: p, mouseButton: .left)
        e?.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        e?.setDoubleValueField(.mouseEventDeltaX, value: Double(p.x - prev.x))
        e?.setDoubleValueField(.mouseEventDeltaY, value: Double(p.y - prev.y))
        e?.post(tap: .cghidEventTap)
        lastPosted = p
    }

    /// Clique là où se trouve le curseur. Deux clics rapprochés au même endroit = double-clic.
    func click(right: Bool) {
        guard allowed else { return }
        let now = Date()
        guard now.timeIntervalSince(lastClick) > 0.3 else { return }
        if isRealMouseActive, let cur = CGEvent(source: nil)?.location { pos = cur }
        let p = CGPoint(x: pos.x.rounded(), y: pos.y.rounded())
        let near = hypot(p.x - lastClickPos.x, p.y - lastClickPos.y) < 6
        let window = max(NSEvent.doubleClickInterval, 0.9)
        clickCount = (near && right == lastClickRight && now.timeIntervalSince(lastClick) < window) ? min(clickCount + 1, 3) : 1
        lastClick = now; lastClickRight = right; lastClickPos = p

        let (down, up, button): (CGEventType, CGEventType, CGMouseButton) =
            right ? (.rightMouseDown, .rightMouseUp, .right) : (.leftMouseDown, .leftMouseUp, .left)
        for type in [down, up] {
            let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button)
            e?.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
            e?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Double-clic gauche immédiat à la position courante (utilisé par le menu de clic rapide).
    func doubleClick() {
        guard allowed else { return }
        let p = CGPoint(x: pos.x.rounded(), y: pos.y.rounded())
        lastClick = Date(); lastClickRight = false; lastClickPos = p; clickCount = 2
        for state: Int64 in [1, 2] {
            for type: CGEventType in [.leftMouseDown, .leftMouseUp] {
                let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
                e?.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
                e?.setIntegerValueField(.mouseEventClickState, value: state)
                e?.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Écrans

    /// Curseur (y compris le mouvement pas encore appliqué) et écran qui le contient, pour l'alignement tête ↔ écran.
    var screenContext: ScreenContext {
        let p = CGPoint(x: pos.x + pending.x, y: pos.y + pending.y)
        let b = screens.first { $0.contains(pos) } ?? screens.first ?? CGDisplayBounds(CGMainDisplayID())
        return ScreenContext(cursor: p, bounds: b)
    }

    /// Place le curseur au centre de l'écran où il se trouve.
    func moveToCenter() {
        pending = .zero
        let b = screenContext.bounds
        move(by: CGPoint(x: b.midX - pos.x, y: b.midY - pos.y))
    }

    /// Met à jour la géométrie des écrans et renvoie `true` uniquement si les dimensions/positions ont changé
    /// (macOS émet `didChangeScreenParametersNotification` aussi pour True Tone, Night Shift ou le plein écran).
    @discardableResult
    func refreshScreens() -> Bool {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        var next = ids.prefix(Int(count)).map { CGDisplayBounds($0) }
        if next.isEmpty { next = [CGDisplayBounds(CGMainDisplayID())] }
        let changed = next != screens
        screens = next
        return changed
    }

    /// Laisse passer d'un écran à l'autre, sinon bloque au bord de l'écran courant.
    private func clampToScreens(_ p: CGPoint, from old: CGPoint) -> CGPoint {
        if screens.contains(where: { $0.contains(p) }) { return p }
        let home = screens.first { $0.contains(old) } ?? screens[0]
        return CGPoint(x: min(max(p.x, home.minX), home.maxX - 1), y: min(max(p.y, home.minY), home.maxY - 1))
    }
}
