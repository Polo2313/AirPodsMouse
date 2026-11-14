import AppKit
import CoreGraphics

/// Déplace le curseur et clique, en envoyant de vrais événements souris (autorisation Accessibilité requise).
@MainActor
final class CursorController {
    private let source = CGEventSource(stateID: .hidSystemState)
    private(set) var pos = CGPoint.zero
    /// Faux tant que l'Accessibilité n'est pas accordée (mis à jour chaque seconde par AppModel).
    var allowed = false
    private var pending = CGPoint.zero          // reçu des capteurs, pas encore appliqué
    private var recentPosted: [CGPoint] = []    // derniers points envoyés, pour reconnaître le vrai trackpad
    private var screens: [CGRect] = []

    private var lastClick = Date.distantPast
    private var lastClickRight = false
    private var lastClickPos = CGPoint.zero
    private var clickCount = 0

    init() {
        pos = CGEvent(source: nil)?.location ?? .zero
        refreshScreens()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshScreens() }
        }
    }

    func add(dx: Double, dy: Double) { pending.x += dx; pending.y += dy }

    func dropPending() { pending = .zero }

    /// Applique tout le déplacement en attente d'un coup (avant un clic).
    func flush() { move(by: pending); pending = .zero }

    /// 120 fois par seconde : applique progressivement le déplacement reçu. Les capteurs envoient ~50 mesures/s
    /// par paquets irréguliers ; sans ça, le curseur avance par à-coups.
    /// - Parameter sensorsFresh: false si la dernière mesure date de plus de 0,3 s (AirPods retirés…) :
    ///   on jette le reste pour que le curseur s'arrête net.
    /// - Returns: true si le vrai trackpad/souris a bougé le curseur depuis le dernier appel.
    @discardableResult
    func tick(sensorsFresh: Bool) -> Bool {
        let real = syncWithRealMouse()
        guard sensorsFresh else { pending = .zero; return real }
        guard pending != .zero else { return real }
        var step = CGPoint(x: pending.x * 0.35, y: pending.y * 0.35)
        if abs(pending.x) < 0.6 && abs(pending.y) < 0.6 { step = pending }
        pending.x -= step.x; pending.y -= step.y
        move(by: step)
        return real
    }

    /// Si le curseur n'est sur aucun des derniers points envoyés, c'est le vrai trackpad qui l'a bougé : on repart de là.
    /// (Comparer au seul dernier point ramenait le curseur en arrière quand il allait vite : la position lue
    /// a parfois un événement de retard.)
    @discardableResult
    func syncWithRealMouse() -> Bool {
        guard let cur = CGEvent(source: nil)?.location else { return false }
        let ours = recentPosted.contains { abs($0.x - cur.x) <= 2 && abs($0.y - cur.y) <= 2 }
        let movedAway = abs(cur.x - pos.x) > 2 || abs(cur.y - pos.y) > 2
        if !ours && movedAway { pos = cur; recentPosted = [cur]; return true }
        return false
    }

    private func move(by d: CGPoint) {
        guard d != .zero, allowed else { return }
        pos = clampToScreens(CGPoint(x: pos.x + d.x, y: pos.y + d.y), from: pos)
        let p = CGPoint(x: pos.x.rounded(), y: pos.y.rounded())
        guard p != recentPosted.last else { return }
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        recentPosted.append(p)
        if recentPosted.count > 6 { recentPosted.removeFirst() }
    }

    /// Clique là où se trouve le curseur. Deux clics rapprochés au même endroit = double-clic.
    func click(right: Bool) {
        guard allowed else { return }
        let now = Date()
        guard now.timeIntervalSince(lastClick) > 0.3 else { return }
        syncWithRealMouse()
        let p = CGPoint(x: pos.x.rounded(), y: pos.y.rounded())
        let near = hypot(p.x - lastClickPos.x, p.y - lastClickPos.y) < 6
        let window = max(NSEvent.doubleClickInterval, 0.9)
        clickCount = (near && right == lastClickRight && now.timeIntervalSince(lastClick) < window) ? min(clickCount + 1, 3) : 1
        lastClick = now; lastClickRight = right; lastClickPos = p

        let (down, up, button): (CGEventType, CGEventType, CGMouseButton) =
            right ? (.rightMouseDown, .rightMouseUp, .right) : (.leftMouseDown, .leftMouseUp, .left)
        for type in [down, up] {
            let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button)
            e?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            e?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Écrans

    private func refreshScreens() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        screens = ids.prefix(Int(count)).map { CGDisplayBounds($0) }
        if screens.isEmpty { screens = [CGDisplayBounds(CGMainDisplayID())] }
    }

    /// Laisse passer d'un écran à l'autre, sinon bloque au bord de l'écran courant.
    private func clampToScreens(_ p: CGPoint, from old: CGPoint) -> CGPoint {
        if screens.contains(where: { $0.contains(p) }) { return p }
        let home = screens.first { $0.contains(old) } ?? screens[0]
        return CGPoint(x: min(max(p.x, home.minX), home.maxX - 1), y: min(max(p.y, home.minY), home.maxY - 1))
    }
}
