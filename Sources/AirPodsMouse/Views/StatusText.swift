import SwiftUI

/// Textes et couleurs de l'état, partagés par le menu et les réglages.
extension AppModel.Status {
    var title: LocalizedStringKey {
        switch self {
        case .searching: "Recherche des AirPods…"
        case .active: "Actif"
        case .noMotion: "Aucun mouvement reçu"
        case .paused: "En pause"
        case .calibrating: "Calibrage… lève la tête puis reviens"
        case .motionDenied: "Accès aux mouvements refusé"
        case .unavailable: "Capteurs indisponibles sur ce Mac"
        }
    }

    var color: Color {
        switch self {
        case .active: .green
        case .searching, .calibrating: .blue
        case .paused: .secondary
        case .noMotion, .motionDenied, .unavailable: .orange
        }
    }

    var symbol: String {
        switch self {
        case .active: "checkmark.circle.fill"
        case .searching: "antenna.radiowaves.left.and.right"
        case .paused: "pause.circle.fill"
        case .calibrating: "arrow.up.and.down.circle.fill"
        case .noMotion, .motionDenied, .unavailable: "exclamationmark.triangle.fill"
        }
    }
}

/// Icône carrée colorée, comme dans les Réglages Système.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

extension Color {
    /// Couleur de l'appli (celle de l'icône) : cibles, anneau du curseur, accueil.
    /// Les commandes standard gardent la couleur d'accent choisie par l'utilisateur.
    static let brand = Color(red: 0.32, green: 0.42, blue: 0.98)
}
