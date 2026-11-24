import AppKit
import ApplicationServices
import os

/// Aimant : savoir si le curseur survole un élément cliquable, grâce à l'Accessibilité de macOS.
enum ClickableProbe {
    private static let system: AXUIElement = {
        let s = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(s, 0.05)   // ne jamais bloquer si une appli ne répond pas
        return s
    }()
    private static let roles: Set<String> = [
        kAXButtonRole, "AXLink", kAXCheckBoxRole, kAXRadioButtonRole, kAXPopUpButtonRole, kAXMenuItemRole,
        kAXMenuBarItemRole, kAXMenuButtonRole, kAXDisclosureTriangleRole, kAXTabGroupRole, kAXIncrementorRole,
        kAXComboBoxRole, kAXTextFieldRole, kAXCellRole, "AXSegment", "AXDockItem",
    ]
    private static let queue = DispatchQueue(label: "local.airpodsmouse.ax-probe", qos: .userInteractive)
    private static let inFlight = OSAllocatedUnfairLock(initialState: false)

    /// - Parameter p: position en coordonnées écran (origine en haut à gauche).
    static func isClickable(at p: CGPoint) -> Bool {
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &el) == .success, var e = el else { return false }
        for _ in 0..<3 {   // le texte d'un bouton est souvent un enfant du bouton
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &role) == .success,
               let r = role as? String, roles.contains(r) { return true }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(e, kAXParentAttribute as CFString, &parent) == .success,
                  let pe = parent, CFGetTypeID(pe) == AXUIElementGetTypeID() else { return false }
            e = pe as! AXUIElement
        }
        return false
    }

    /// Version non bloquante pour la boucle à 120 Hz : interroge l'Accessibilité hors du thread principal
    /// et ignore la demande si une vérification précédente est encore en cours.
    static func probeAsync(at p: CGPoint, completion: @escaping @MainActor (Bool) -> Void) {
        let started = inFlight.withLock { busy -> Bool in
            if busy { return false }
            busy = true
            return true
        }
        guard started else { return }
        queue.async {
            let hit = isClickable(at: p)
            inFlight.withLock { $0 = false }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(hit) }
            }
        }
    }
}

/// Écrire sans les mains : clavier d'accessibilité et dictée de macOS.
enum HandsFree {
    /// Clavier visuel de macOS (clavier d'accessibilité). macOS refuse qu'une appli le lance directement
    /// (essai réel : « Impossible de lancer Assistive Control ») : on ouvre le réglage où on l'active d'un interrupteur.
    static func showKeyboard() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?Keyboard")!)
        Log.line("Réglage du clavier d'accessibilité ouvert")
    }

    /// Actionne « Démarrer la dictée » dans le menu Édition de l'appli au premier plan.
    /// - Returns: false si l'appli au premier plan n'a pas cette commande.
    @discardableResult
    static func startDictation() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let bar: AXUIElement = attribute(app, kAXMenuBarAttribute) else { return false }
        if let item = find(in: bar, depth: 0) {
            let ok = AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            Log.line(ok ? "Dictée lancée dans \(front.localizedName ?? "?")" : "Dictée : échec")
            return ok
        }
        Log.line("Dictée : pas de commande dans \(front.localizedName ?? "?")")
        return false
    }

    private static func find(in e: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 4 else { return nil }
        if let title: String = attribute(e, kAXTitleAttribute) {
            let t = title.lowercased()
            if t.contains("dictée") || t.contains("dictation") { return e }
        }
        guard let children: [AXUIElement] = attribute(e, kAXChildrenAttribute) else { return nil }
        for c in children { if let f = find(in: c, depth: depth + 1) { return f } }
        return nil
    }

    private static func attribute<T>(_ e: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
        return v as? T
    }
}
