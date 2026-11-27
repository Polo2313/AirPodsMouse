import CoreGraphics

/// Clic automatique : clique quand le curseur reste immobile (à quelques pixels près) pendant `delay`.
/// Pour les personnes qui ne peuvent pas faire de geste rapide.
/// Après un clic, il faut déplacer le curseur d'au moins `rearmDistance` avant le suivant :
/// garder la tête immobile ne déclenche pas une rafale de clics.
public struct DwellClicker {
    public var delay = 1.0            // s (réglable 0,6 – 2)
    public var radius = 6.0           // px : tolérance au tremblement
    public var rearmDistance = 40.0   // px

    private var sum = CGPoint.zero    // centre des positions depuis le début de l'immobilité
    private var count = 0.0
    private var since = 0.0
    private var lastFire: CGPoint?    // position du dernier clic tant qu'on ne s'en est pas éloigné

    public init() {}

    public mutating func reset() { count = 0; lastFire = nil }

    /// Désarme le clic automatique à la position `p` : aucun clic tant que le curseur ne s'est pas déplacé
    /// d'au moins `rearmDistance` (évite un clic surprise 1 s après le démarrage, la reprise ou un recentrage).
    public mutating func disarm(at p: CGPoint) { count = 0; lastFire = p }

    /// - Returns: `progress` 0…1 (pour l'anneau autour du curseur) et `fire` au moment du clic.
    public mutating func update(cursor p: CGPoint, t: Double, realMouseMoved: Bool) -> (progress: Double, fire: Bool) {
        guard p.x.isFinite, p.y.isFinite, t.isFinite else { return (0, false) }
        // La vraie souris a la main : on désarme jusqu'à ce que la tête déplace le curseur
        // (sinon lâcher le trackpad déclencherait un clic une seconde plus tard).
        if realMouseMoved { count = 0; lastFire = p; return (0, false) }
        if let f = lastFire {
            guard hypot(p.x - f.x, p.y - f.y) >= rearmDistance else { return (0, false) }
            lastFire = nil; count = 0
        }
        if count > 0 {
            let c = CGPoint(x: sum.x / count, y: sum.y / count)
            if hypot(p.x - c.x, p.y - c.y) > radius || t < since { count = 0 }  // le curseur bouge : on repart
        }
        if count == 0 { sum = .zero; since = t }
        sum.x += p.x; sum.y += p.y; count += 1

        let effectiveDelay = delay.isFinite ? max(delay, 0.1) : 1.0
        let progress = min(max((t - since) / effectiveDelay, 0), 1)
        if progress >= 1 {
            lastFire = p; count = 0
            return (1, true)
        }
        return (progress, false)
    }
}
