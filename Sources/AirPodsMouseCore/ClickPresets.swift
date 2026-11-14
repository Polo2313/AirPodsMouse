/// Sensibilité du clic par hochement. « normal » = réglage validé sur les enregistrements réels.
public enum NodPreset: Int, CaseIterable, Sendable {
    case careful, normal, easy

    /// Vitesse (rad/s) à partir de laquelle un hochement est candidat.
    public var threshold: Double {
        switch self { case .careful: 0.85; case .normal: 0.65; case .easy: 0.5 }
    }

    /// Durée maximale (s) de l'aller-retour.
    public var maxTotal: Double {
        switch self { case .careful: 0.4; case .normal: 0.5; case .easy: 0.6 }
    }
}
