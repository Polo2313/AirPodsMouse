import AppKit
import ApplicationServices
import CoreMotion

/// Les deux autorisations dont l'appli a besoin.
enum Permissions {
    /// Accessibilité : nécessaire pour déplacer le curseur et cliquer.
    static var axTrusted: Bool { AXIsProcessTrusted() }

    /// Affiche la demande système d'Accessibilité (une fois par lancement au plus) et ajoute l'appli à la liste.
    static func promptAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Mouvements et forme : nécessaire pour lire les capteurs des AirPods.
    static var motion: CMAuthorizationStatus { CMHeadphoneMotionManager.authorizationStatus() }

    static func openMotionSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Motion")!)
    }
}
