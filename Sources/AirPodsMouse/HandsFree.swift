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

    /// Active l'arbre d'accessibilité DOM dans les navigateurs Chromium/Electron (Chrome, Brave, Arc…)
    /// pour que les barres de recherche web soient visibles par macOS.
    static func enableWebAccessibilityOnFrontmostApp() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.05)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    /// Détecte si le point `p` correspond réellement à une barre de recherche (ou un champ de saisie court)
    /// situé sous le curseur, et renvoie son rectangle écran pour éviter les déclenchements en boucle.
    /// Ne renvoie jamais `true` sur un éditeur de code, un document entier ou un élément hors du curseur.
    static func detectSearchBar(at p: CGPoint) -> (rect: CGRect, summary: String)? {
        if let front = NSWorkspace.shared.frontmostApplication {
            let app = AXUIElementCreateApplication(front.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.06)
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)

            // 1. Élément directement sous le curseur au point cliqué
            var el: AXUIElement?
            if AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &el) == .success, let hit = el {
                if let match = matchSearchBarHierarchy(startingAt: hit, point: p, isFocused: false) { return match }
            }

            // 2. Élément nouvellement focalisé (via l'appli ou le système), UNIQUEMENT s'il est situé à l'endroit du clic
            for candidate in [focusedElement(in: app), focusedElement(in: system)].compactMap({ $0 }) {
                if let match = matchSearchBarHierarchy(startingAt: candidate, point: p, isFocused: true) { return match }
            }
        }
        return nil
    }

    private static func focusedElement(in container: AXUIElement) -> AXUIElement? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(container, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let f = focused, CFGetTypeID(f) == AXUIElementGetTypeID() else { return nil }
        return (f as! AXUIElement)
    }

    private static func matchSearchBarHierarchy(startingAt start: AXUIElement, point p: CGPoint, isFocused: Bool) -> (rect: CGRect, summary: String)? {
        var e = start
        for depth in 0..<4 {
            let role = stringAttr(e, kAXRoleAttribute) ?? ""
            let subrole = stringAttr(e, kAXSubroleAttribute) ?? ""
            if depth == 0 && !isFocused && SearchBarClassifier.isDirectNonInput(role: role, subrole: subrole) {
                return nil
            }
            if let r = elementFrame(e) {
                let hints = textMetadata(of: e)
                if SearchBarClassifier.matches(role: role, subrole: subrole, hints: hints, rect: r,
                                               clickedAt: p, isFocusedElement: isFocused && depth == 0) {
                    let summary = "\(role)\(subrole.isEmpty ? "" : "/\(subrole)") (\(Int(r.width))×\(Int(r.height)))"
                    return (r, summary)
                }
                if depth > 0 && r.height > 120 { return nil }
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(e, kAXParentAttribute as CFString, &parent) == .success,
                  let pe = parent, CFGetTypeID(pe) == AXUIElementGetTypeID() else { return nil }
            e = pe as! AXUIElement
        }
        return nil
    }

    private static func stringAttr(_ e: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success, let s = v as? String else { return nil }
        return s
    }

    private static func textMetadata(of e: AXUIElement) -> String {
        let keys = ["AXPlaceholderValue", kAXDescriptionAttribute, kAXTitleAttribute,
                    kAXRoleDescriptionAttribute, kAXHelpAttribute, "AXDOMIdentifier"]
        var parts: [String] = []
        for k in keys {
            if let s = stringAttr(e, k), !s.isEmpty { parts.append(s.lowercased()) }
        }
        return parts.joined(separator: " ")
    }

    private static func elementFrame(_ e: AXUIElement) -> CGRect? {
        var pv: CFTypeRef?
        var sv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &pv) == .success,
              AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &sv) == .success,
              let pVal = pv, let sVal = sv,
              CFGetTypeID(pVal) == AXValueGetTypeID(),
              CFGetTypeID(sVal) == AXValueGetTypeID() else { return nil }
        var pt = CGPoint.zero
        var sz = CGSize.zero
        guard AXValueGetValue(pVal as! AXValue, .cgPoint, &pt),
              AXValueGetValue(sVal as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: pt, size: sz)
    }

    /// Vérifie hors du thread principal (après un court délai pour laisser le clic donner le focus au champ)
    /// si l'utilisateur vient de cliquer dans une barre de recherche. Réessaie une fois à 0,28 s pour les pages web lentes.
    static func probeSearchBarAsync(at p: CGPoint, completion: @escaping @MainActor ((rect: CGRect, summary: String)?) -> Void) {
        queue.async {
            enableWebAccessibilityOnFrontmostApp()
        }
        queue.asyncAfter(deadline: .now() + 0.14) {
            if let hit = detectSearchBar(at: p) {
                DispatchQueue.main.async { MainActor.assumeIsolated { completion(hit) } }
                return
            }
            queue.asyncAfter(deadline: .now() + 0.14) {
                let retry = detectSearchBar(at: p)
                DispatchQueue.main.async { MainActor.assumeIsolated { completion(retry) } }
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

    /// Lit la fin du journal de Librewispr pour savoir s'il est déjà en train d'enregistrer la voix.
    static func isLibrewisprRecording() -> Bool {
        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.librewispr.app/logs/librewispr.log")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let mtime = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(mtime) < 90,
              let fh = try? FileHandle(forReadingFrom: logURL) else { return false }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let readLen: UInt64 = min(size, 16384)
        try? fh.seek(toOffset: size - readLen)
        guard let data = try? fh.readToEnd(),
              let tail = String(data: data, encoding: .utf8) else { return false }
        let lastStart = tail.range(of: "start_recording: entry", options: .backwards)?.lowerBound
        let lastStop = tail.range(of: "stop_recording: entry", options: .backwards)?.lowerBound
        let lastCancel = tail.range(of: "cancel_recording: entry", options: .backwards)?.lowerBound
        guard let startIdx = lastStart else { return false }
        if let stopIdx = lastStop, stopIdx > startIdx { return false }
        if let cancelIdx = lastCancel, cancelIdx > startIdx { return false }
        return true
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
