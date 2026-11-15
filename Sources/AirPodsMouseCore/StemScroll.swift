/// Glissement sur la tige des AirPods Pro 2 : le Mac ne transmet pas le geste lui-même, mais chaque glissement
/// change le volume des AirPods d'un cran exact (1/16), notifié aussitôt (souvent en double).
/// L'appli remet ensuite le volume à la référence ; cette remise produit elle-même une notification.
public enum StemSwipe: Equatable, Sendable { case up, down }

public struct StemSwipeDetector {
    public private(set) var reference: Double
    public var step = 1.0 / 16
    public var tolerance = 0.02
    private var lastSwipe: (value: Double, t: Double)?

    public init(reference: Double) { self.reference = reference }

    /// - Parameter keyPressedRecently: une touche volume du clavier vient d'être pressée (ce n'est pas un glissement).
    /// - Returns: le glissement détecté, ou nil (remise à la référence, doublon, curseur du menu Son, clavier).
    public mutating func volumeChanged(to v: Double, at t: Double, keyPressedRecently: Bool) -> StemSwipe? {
        let d = v - reference
        if abs(d) < 0.005 { lastSwipe = nil; return nil }                   // retour à la référence
        if let l = lastSwipe, abs(v - l.value) < 0.005, t - l.t < 0.5 { return nil }   // notification en double
        if keyPressedRecently { reference = v; lastSwipe = nil; return nil } // l'utilisateur règle le volume au clavier
        guard abs(abs(d) - step) <= tolerance else { reference = v; lastSwipe = nil; return nil }  // autre réglage
        lastSwipe = (v, t)
        return d > 0 ? .up : .down
    }

    /// Le volume a été changé volontairement (réglages, autre appareil) : nouvelle référence.
    public mutating func setReference(_ v: Double) { reference = v; lastSwipe = nil }
}

/// Distance de défilement par glissement : un pas de base, accéléré quand les glissements s'enchaînent.
public struct ScrollStepper {
    public var baseStep: Double
    public var chainWindow = 0.8       // s : glissements « enchaînés »
    public var growth = 1.5
    public var maxFactor = 3.0
    private var lastAt: Double?
    private var lastUp: Bool?
    private var factor = 1.0

    public init(baseStep: Double) { self.baseStep = baseStep }

    /// Changer de sens repart d'un pas normal.
    public mutating func distance(at t: Double, up: Bool) -> Double {
        if let l = lastAt, t - l >= 0, t - l < chainWindow, lastUp == up { factor = min(factor * growth, maxFactor) } else { factor = 1 }
        lastAt = t; lastUp = up
        return baseStep * factor
    }
}
