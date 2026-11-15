import CoreGraphics
import Foundation

// MARK: - Pause pendant la frappe

/// Quand on tape, on regarde le clavier : la tête baisse et le curseur partirait. On fige le pointeur à la tête
/// jusqu'à `hold` secondes après la dernière touche.
public struct TypingGuard {
    public var hold = 1.5               // s (1 s coupait la pause des personnes qui tapent lentement)
    private var lastKey: Double?
    private var wasFrozen = false

    public init() {}

    public mutating func keyPressed(at t: Double) { lastKey = t; wasFrozen = true }

    public func isFrozen(at t: Double) -> Bool { lastKey.map { t - $0 >= 0 && t - $0 < hold } ?? false }

    /// Vrai une seule fois, au moment où la pause se termine (pour repartir sans saut).
    public mutating func justResumed(at t: Double) -> Bool {
        guard wasFrozen, !isFrozen(at: t) else { return false }
        wasFrozen = false
        return true
    }
}

// MARK: - Défilement à la tête

/// Mode défilement : le curseur est figé, pencher la tête vers le haut/bas au-delà de la zone morte fait défiler,
/// d'autant plus vite qu'on penche. Regarder franchement de côté fait sortir du mode.
public struct HeadScroller {
    public var deadZone = 0.05          // rad (~3°)
    public var gain = 4000.0            // px/s par radian au-delà de la zone morte
    public var maxSpeed = 3000.0        // px/s
    public var exitYaw = 0.26           // rad (~15°)
    private var refYaw = 0.0, refPitch = 0.0

    public init() {}

    public mutating func start(yaw: Double, pitch: Double) { refYaw = yaw; refPitch = pitch }

    /// Vitesse de défilement en px/s (> 0 = vers le haut du document).
    public func velocity(pitch: Double) -> Double {
        let d = pitch - refPitch
        let beyond = abs(d) - deadZone
        guard beyond > 0 else { return 0 }
        return (d > 0 ? 1 : -1) * min(beyond * gain * (1 + beyond * 4), maxSpeed)
    }

    public func shouldExit(yaw: Double) -> Bool { abs(yaw - refYaw) > exitYaw }
}

// MARK: - Menu de clic rapide

/// Menu circulaire ouvert par le clic automatique : viser une action et rester immobile la choisit.
public struct DwellMenu {
    public enum Action: CaseIterable, Sendable { case click, doubleClick, rightClick, drag, scroll }
    public enum Outcome: Equatable { case pending(hovered: Action?, progress: Double), chosen(Action), cancelled }

    public let origin: CGPoint
    public var radius = 90.0            // distance des actions au centre
    public var itemRadius = 36.0
    public var dwell = 0.6
    public var timeout = 4.0
    private let openedAt: Double
    private var hovered: Action?
    private var hoverSince = 0.0
    private var lastActivity: Double

    public init(origin: CGPoint, openedAt: Double) { self.origin = origin; self.openedAt = openedAt; lastActivity = openedAt }

    /// Position d'une action : régulièrement autour du centre, la première en haut.
    public func itemCenter(_ a: Action) -> CGPoint {
        let i = Double(Action.allCases.firstIndex(of: a)!), n = Double(Action.allCases.count)
        let angle = -Double.pi / 2 + 2 * Double.pi * i / n
        return CGPoint(x: origin.x + radius * cos(angle), y: origin.y + radius * sin(angle))
    }

    public mutating func update(cursor p: CGPoint, t: Double) -> Outcome {
        if hypot(p.x - origin.x, p.y - origin.y) > radius + itemRadius + 40 { return .cancelled }
        let over = Action.allCases.first { hypot(p.x - itemCenter($0).x, p.y - itemCenter($0).y) <= itemRadius }
        if over != hovered { hovered = over; hoverSince = t; lastActivity = t }
        guard let h = hovered else {
            return t - lastActivity > timeout ? .cancelled : .pending(hovered: nil, progress: 0)
        }
        let progress = min((t - hoverSince) / dwell, 1)
        return progress >= 1 ? .chosen(h) : .pending(hovered: h, progress: progress)
    }
}

// MARK: - Geste « non »

/// Secouer la tête gauche-droite : au moins 3 inversions rapides du lacet en peu de temps, petite amplitude,
/// peu de tangage. Seuils prudents : la visée et les hochements ne doivent jamais le déclencher.
public struct ShakeDetector {
    public var minRate = 1.2            // rad/s : chaque aller doit être rapide
    public var window = 1.2             // s : pour réunir les inversions
    public var minReversals = 3
    public var maxAmplitude = 0.44      // rad (~25°)
    public var pitchRatio = 0.6         // le tangage doit rester petit devant le lacet
    private var peaks: [(t: Double, sign: Double)] = []
    private var currentSign = 0.0
    private var yawAngle = 0.0, minAngle = 0.0, maxAngle = 0.0
    private var maxYaw = 0.0, maxPitch = 0.0
    private var cooldownUntil = -1.0

    public init() {}

    public mutating func update(yawRate: Double, pitchRate: Double, t: Double, dt: Double) -> Bool {
        yawAngle += yawRate * dt
        guard t >= cooldownUntil else { return false }
        peaks.removeAll { t - $0.t > window }
        if peaks.isEmpty { minAngle = yawAngle; maxAngle = yawAngle; maxYaw = 0; maxPitch = 0 }
        minAngle = min(minAngle, yawAngle); maxAngle = max(maxAngle, yawAngle)
        maxYaw = max(maxYaw, abs(yawRate)); maxPitch = max(maxPitch, abs(pitchRate))
        if abs(yawRate) > minRate {
            let s: Double = yawRate > 0 ? 1 : -1
            if s != currentSign { peaks.append((t, s)); currentSign = s }
        }
        let reversals = max(peaks.count - 1, 0)
        if reversals >= minReversals, maxAngle - minAngle < maxAmplitude, maxPitch < maxYaw * pitchRatio {
            peaks.removeAll(); currentSign = 0; cooldownUntil = t + 1
            return true
        }
        return false
    }
}
