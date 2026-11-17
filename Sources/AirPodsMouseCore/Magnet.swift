/// Force de l'aimant : de combien le curseur ralentit en visée fine au-dessus d'un bouton, d'un lien ou d'une case.
public enum MagnetStrength: Int, CaseIterable, Sendable {
    case light, medium, strong

    /// Part de la vitesse retirée en visée fine (0 = aucun ralentissement). Avant : ×0,5 fixe, soit 0,5.
    public var slowdown: Double {
        switch self { case .light: 0.4; case .medium: 0.6; case .strong: 0.75 }
    }
}

/// Aimant : ralentit la visée fine sur un élément cliquable pour s'y arrêter plus facilement.
/// Le freinage diminue progressivement avec la vitesse (plus de saut à 8 px comme avant) et disparaît
/// pour un mouvement franc, qui sort du bouton sans effort.
public enum Magnet {
    /// px par mesure (~50 mesures/s) : en dessous, freinage complet (visée fine, ≈ 100 px/s).
    public static let fineStep = 2.0
    /// px par mesure : au-delà, aucun freinage (≈ 600 px/s, on traverse l'écran).
    public static let freeStep = 12.0

    /// Multiplicateur à appliquer à un déplacement de `step` px quand le curseur est sur un élément cliquable.
    public static func factor(step: Double, slowdown: Double) -> Double {
        1 - slowdown * (1 - smoothstep(fineStep, freeStep, step))
    }
}
