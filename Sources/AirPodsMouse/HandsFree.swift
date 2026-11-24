import AppKit
import AirPodsMouseCore
import ApplicationServices
import os

/// Aimant & détection de champs de saisie grâce à l'Accessibilité de macOS.
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
    private static let textRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField",
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

    /// Vrai si le point cliqué (ou l'élément qui vient de recevoir le focus) est une barre de recherche ou un champ de texte.
    static func isTextInput(at p: CGPoint) -> Bool {
        var el: AXUIElement?
        if AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &el) == .success, let hit = el {
            if elementIsTextInput(hit) { return true }
        }
        if let front = NSWorkspace.shared.frontmostApplication {
            let app = AXUIElementCreateApplication(front.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.05)
            var focused: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
               let f = focused, CFGetTypeID(f) == AXUIElementGetTypeID() {
                if elementIsTextInput(f as! AXUIElement) { return true }
            }
        }
        return false
    }

    private static func elementIsTextInput(_ start: AXUIElement) -> Bool {
        var e = start
        for _ in 0..<4 {
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &role) == .success,
               let r = role as? String, textRoles.contains(r) { return true }
            var subrole: CFTypeRef?
            if AXUIElementCopyAttributeValue(e, kAXSubroleAttribute as CFString, &subrole) == .success,
               let sr = subrole as? String, sr == "AXSearchField" { return true }
            var editable: CFTypeRef?
            if AXUIElementCopyAttributeValue(e, "AXEditable" as CFString, &editable) == .success,
               let ed = editable as? Bool, ed { return true }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(e, kAXParentAttribute as CFString, &parent) == .success,
                  let pe = parent, CFGetTypeID(pe) == AXUIElementGetTypeID() else { return false }
            e = pe as! AXUIElement
        }
        return false
    }

    /// Vérifie hors du thread principal (après un court délai pour laisser le clic donner le focus au champ)
    /// si l'utilisateur vient de cliquer dans une barre de recherche ou une zone de texte.
    static func probeTextInputAsync(at p: CGPoint, after delay: TimeInterval = 0.14, completion: @escaping @MainActor (Bool) -> Void) {
        queue.asyncAfter(deadline: .now() + delay) {
            let hit = isTextInput(at: p)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(hit) }
            }
        }
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

/// Écrire sans les mains : Librewispr, dictée de macOS et clavier d'accessibilité.
enum HandsFree {
    static let librewisprBundleID = "com.librewispr"
    static let librewisprAppURL = URL(fileURLWithPath: "/Applications/Librewispr.app")

    static var isLibrewisprInstalled: Bool {
        FileManager.default.fileExists(atPath: librewisprAppURL.path)
            || NSWorkspace.shared.urlForApplication(withBundleIdentifier: librewisprBundleID) != nil
    }

    /// Lit le raccourci actuel de Librewispr dans ses préférences (`Super+P` → `⌘P` par défaut).
    static func currentLibrewisprShortcut() -> LibrewisprShortcut {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.librewispr/settings.json")
        if let data = try? Data(contentsOf: url), let parsed = LibrewisprShortcut.fromSettingsJSON(data) {
            return parsed
        }
        return .defaultShortcut
    }

    /// Déclenche l'écoute vocale dans Librewispr en envoyant son raccourci global (et lance l'appli si nécessaire).
    @discardableResult
    static func triggerLibrewispr() -> Bool {
        let shortcut = currentLibrewisprShortcut()
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: librewisprBundleID).isEmpty
        if running {
            postShortcut(shortcut)
            Log.line("Librewispr déclenché (\(shortcut.label))")
            return true
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: librewisprBundleID)
                ?? (FileManager.default.fileExists(atPath: librewisprAppURL.path) ? librewisprAppURL : nil) else {
            Log.line("Librewispr introuvable : repli sur la dictée de macOS")
            return startDictation()
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, err in
            if let err {
                Log.line("Impossible de lancer Librewispr : \(err.localizedDescription)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                postShortcut(shortcut)
                Log.line("Librewispr lancé et déclenché (\(shortcut.label))")
            }
        }
        return true
    }

    /// Ouvre ou affiche la fenêtre de Librewispr.
    @discardableResult
    static func openLibrewisprApp() -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: librewisprBundleID)
                ?? (FileManager.default.fileExists(atPath: librewisprAppURL.path) ? librewisprAppURL : nil) else {
            Log.line("Librewispr introuvable")
            return false
        }
        NSWorkspace.shared.open(url)
        Log.line("Application Librewispr ouverte")
        return true
    }

    private static func postShortcut(_ s: LibrewisprShortcut) {
        let src = CGEventSource(stateID: .hidSystemState)
        var flags: CGEventFlags = []
        if s.command { flags.insert(.maskCommand) }
        if s.option { flags.insert(.maskAlternate) }
        if s.control { flags.insert(.maskControl) }
        if s.shift { flags.insert(.maskShift) }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(s.keyCode), keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Exécute l'action vocale choisie et renvoie le texte de la bulle de confirmation.
    @MainActor
    @discardableResult
    static func triggerVoiceInput(mode: VoiceInputMode) -> String {
        switch mode {
        case .librewispr:
            triggerLibrewispr()
            return String(localized: "Parle maintenant (Librewispr)")
        case .openLibrewispr:
            openLibrewisprApp()
            return String(localized: "Librewispr ouvert")
        case .macosDictation:
            startDictation()
            return String(localized: "Dictée activée")
        case .onScreenKeyboard:
            showKeyboard()
            return String(localized: "Clavier visuel")
        }
    }

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
