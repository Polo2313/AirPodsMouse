import Foundation

/// État affiché par l'appli (menu, réglages, icône de la barre des menus).
public enum AppStatus: Equatable {
    case searching, active, noMotion, paused, calibrating, motionDenied, unavailable

    /// Choisit l'état à afficher, du plus prioritaire au moins prioritaire.
    /// La pause passe avant « aucun mouvement » : sinon, AirPods retirés, une pause oubliée s'affichait
    /// « Aucun mouvement reçu » (⚠️) et, AirPods remis, le curseur restait figé sans raison visible.
    /// - Parameters:
    ///   - sinceStart: secondes depuis le dernier lancement des capteurs.
    public static func resolve(available: Bool, motionDenied: Bool, calibrating: Bool,
                               streaming: Bool, sinceStart: Double, paused: Bool) -> AppStatus {
        if !available { return .unavailable }
        if motionDenied { return .motionDenied }
        if calibrating { return .calibrating }
        if paused { return .paused }
        if !streaming { return sinceStart < 3 ? .searching : .noMotion }
        return .active
    }
}
