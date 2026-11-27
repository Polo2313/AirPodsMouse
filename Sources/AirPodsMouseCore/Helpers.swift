import CoreGraphics
import Foundation
import simd

// MARK: - Calibrage de l'axe haut / bas

/// Extrait l'axe de tangage (haut/bas) à partir de 3 secondes de hochements de tête (« oui »).
/// Robuste aux petits mouvements naturels (≥ ~5,2° crête-à-crête) et insensible au fait que l'utilisateur
/// commence par baisser ou lever la tête (aligne le signe sur l'axe anatomique par défaut de l'écouteur).
public enum CalibrationSolver {
    public static func solvePitchAxis(samples: [(w: V3, g: V3, dt: Double)]) -> V3? {
        guard samples.count > 15 else { return nil }
        var cov = simd_double3x3(0)
        var hs: [(V3, Double)] = []
        hs.reserveCapacity(samples.count)
        var gSum = V3.zero
        for s in samples {
            let h = s.w - simd_dot(s.w, s.g) * s.g
            hs.append((h, s.dt))
            cov += simd_double3x3(columns: (h * h.x, h * h.y, h * h.z))
            gSum += s.g
        }
        var axis = V3(1, 1, 1)
        for _ in 0..<50 {
            let n = cov * axis
            if simd_length(n) < 1e-9 { return nil }
            axis = simd_normalize(n)
        }
        var theta = 0.0, minTheta = 0.0, maxTheta = 0.0, extreme = 0.0
        for (h, dt) in hs {
            theta += simd_dot(h, axis) * dt
            minTheta = min(minTheta, theta)
            maxTheta = max(maxTheta, theta)
            if abs(theta) > abs(extreme) { extreme = theta }
        }
        let span = maxTheta - minTheta
        guard span >= 0.09 else { return nil } // ~5,2° crête-à-crête minimum

        // Oriente le signe de l'axe (+ = lever la tête) selon le repère écouteur d'Apple,
        // pour qu'un hochement vers le bas en premier n'inverse jamais le haut et le bas.
        let gMean = simd_length(gSum) > 1e-6 ? simd_normalize(gSum) : V3(0, 0, -1)
        var defSide = PointerEngine.defaultAxis(gMean)
        defSide -= simd_dot(defSide, gMean) * gMean
        if simd_length(defSide) > 0.2 {
            defSide = simd_normalize(defSide)
            let d = simd_dot(axis, defSide)
            if abs(d) > 0.25 {
                if d < 0 { axis = -axis }
                return axis
            }
        }
        if extreme < 0 { axis = -axis }
        return axis
    }
}

// MARK: - Pause pendant la frappe

/// Quand on tape, on regarde le clavier : la tête baisse et le curseur partirait. On fige le pointeur à la tête
/// jusqu'à `hold` secondes après la dernière touche.
public struct TypingGuard {
    public var hold = 1.5               // s (1 s coupait la pause des personnes qui tapent lentement)
    private var lastKey: Double?
    private var wasFrozen = false

    public init() {}

    public mutating func keyPressed(at t: Double) { lastKey = t; wasFrozen = true }

    public func isFrozen(at t: Double) -> Bool { lastKey.map { t - $0 >= 0 && t - $0 < hold } ?? false }

    /// Vrai une seule fois, au moment où la pause se termine (pour repartir sans saut).
    public mutating func justResumed(at t: Double) -> Bool {
        guard wasFrozen, !isFrozen(at: t) else { return false }
        wasFrozen = false
        return true
    }
}

// MARK: - Défilement à la tête

/// Mode défilement : le curseur est figé, pencher la tête vers le haut/bas au-delà de la zone morte fait défiler,
/// d'autant plus vite qu'on penche. Regarder franchement de côté fait sortir du mode.
public struct HeadScroller {
    public var deadZone = 0.05          // rad (~3°)
    public var gain = 4000.0            // px/s par radian au-delà de la zone morte
    public var maxSpeed = 3000.0        // px/s
    public var exitYaw = 0.26           // rad (~15°)
    private var refYaw = 0.0, refPitch = 0.0

    public init() {}

    public mutating func start(yaw: Double, pitch: Double) { refYaw = yaw; refPitch = pitch }

    /// Vitesse de défilement en px/s (> 0 = vers le haut du document).
    public func velocity(pitch: Double) -> Double {
        let d = pitch - refPitch
        let beyond = abs(d) - deadZone
        guard beyond > 0 else { return 0 }
        return (d > 0 ? 1 : -1) * min(beyond * gain * (1 + beyond * 4), maxSpeed)
    }

    public func shouldExit(yaw: Double) -> Bool { abs(yaw - refYaw) > exitYaw }
}

// MARK: - Menu de clic rapide

/// Menu circulaire ouvert par le clic automatique : viser une action et rester immobile la choisit.
public struct DwellMenu {
    public enum Action: CaseIterable, Sendable { case click, doubleClick, rightClick, drag, scroll }
    public enum Outcome: Equatable { case pending(hovered: Action?, progress: Double), chosen(Action), cancelled }

    public let origin: CGPoint
    public var radius = 90.0            // distance des actions au centre
    public var itemRadius = 36.0
    public var dwell = 0.6
    public var timeout = 4.0
    private let openedAt: Double
    private var hovered: Action?
    private var hoverSince = 0.0
    private var lastActivity: Double

    public init(origin: CGPoint, openedAt: Double) { self.origin = origin; self.openedAt = openedAt; lastActivity = openedAt }

    /// Position d'une action : régulièrement autour du centre, la première en haut.
    public func itemCenter(_ a: Action) -> CGPoint {
        let i = Double(Action.allCases.firstIndex(of: a)!), n = Double(Action.allCases.count)
        let angle = -Double.pi / 2 + 2 * Double.pi * i / n
        return CGPoint(x: origin.x + radius * cos(angle), y: origin.y + radius * sin(angle))
    }

    public mutating func update(cursor p: CGPoint, t: Double) -> Outcome {
        if hypot(p.x - origin.x, p.y - origin.y) > radius + itemRadius + 40 { return .cancelled }
        let over = Action.allCases.first { hypot(p.x - itemCenter($0).x, p.y - itemCenter($0).y) <= itemRadius }
        if over != hovered { hovered = over; hoverSince = t; lastActivity = t }
        guard let h = hovered else {
            return t - lastActivity > timeout ? .cancelled : .pending(hovered: nil, progress: 0)
        }
        let progress = min((t - hoverSince) / dwell, 1)
        return progress >= 1 ? .chosen(h) : .pending(hovered: h, progress: progress)
    }
}

// MARK: - Geste « non »

/// Secouer la tête gauche-droite : au moins 3 inversions rapides du lacet en peu de temps, petite amplitude,
/// peu de tangage. Seuils prudents : la visée et les hochements ne doivent jamais le déclencher.
public struct ShakeDetector {
    public var minRate = 1.2            // rad/s : chaque aller doit être rapide
    public var window = 1.2             // s : pour réunir les inversions
    public var minReversals = 3
    public var maxAmplitude = 0.44      // rad (~25°)
    public var pitchRatio = 0.6         // le tangage doit rester petit devant le lacet
    private var peaks: [(t: Double, sign: Double)] = []
    private var currentSign = 0.0
    private var yawAngle = 0.0, minAngle = 0.0, maxAngle = 0.0
    private var maxYaw = 0.0, maxPitch = 0.0
    private var cooldownUntil = -1.0

    public init() {}

    public mutating func update(yawRate: Double, pitchRate: Double, t: Double, dt: Double) -> Bool {
        yawAngle += yawRate * dt
        guard t >= cooldownUntil else { return false }
        peaks.removeAll { t - $0.t > window }
        if peaks.isEmpty { minAngle = yawAngle; maxAngle = yawAngle; maxYaw = 0; maxPitch = 0 }
        minAngle = min(minAngle, yawAngle); maxAngle = max(maxAngle, yawAngle)
        maxYaw = max(maxYaw, abs(yawRate)); maxPitch = max(maxPitch, abs(pitchRate))
        if abs(yawRate) > minRate {
            let s: Double = yawRate > 0 ? 1 : -1
            if s != currentSign { peaks.append((t, s)); currentSign = s }
        }
        let reversals = max(peaks.count - 1, 0)
        if reversals >= minReversals, maxAngle - minAngle < maxAmplitude, maxPitch < maxYaw * pitchRatio {
            peaks.removeAll(); currentSign = 0; cooldownUntil = t + 1
            return true
        }
        return false
    }
}

// MARK: - Saisie vocale au clic dans un champ de recherche / texte

/// Action lancée automatiquement quand on clique dans une barre de recherche ou un champ de texte.
public enum VoiceInputMode: Int, CaseIterable, Sendable {
    case librewispr = 0
    case openLibrewispr = 1
    case macosDictation = 2
    case onScreenKeyboard = 3
}

/// Règles pures de classification d'un élément d'Accessibilité comme barre de recherche / champ de saisie court.
/// Exige que le clic `point` soit dans (ou tout près de) la barre et que la hauteur soit celle d'une barre (≤ 92 px),
/// pour ne jamais confondre un éditeur de code, une page web entière ou un champ focalisé ailleurs à l'écran.
public enum SearchBarClassifier {
    private static let textRoles: Set<String> = ["AXTextField", "AXComboBox", "AXSearchField"]
    private static let nonInputRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXMenuItem",
        "AXMenuBarItem", "AXMenuButton", "AXDisclosureTriangle", "AXTabGroup",
        "AXSegment", "AXDockItem", "AXScrollBar",
    ]
    private static let searchKeywords: [String] = [
        "recherch", "search", "chercher", "trouver", "find", "adresse", "address",
        "url", "google", "query", "filter", "filtrer", "ask", "demander", "question", "prompt",
        "spotlight", "raycast", "message", "écrire", "write", "chat", "commande", "command",
    ]

    public static func isDirectNonInput(role: String, subrole: String) -> Bool {
        nonInputRoles.contains(role) && subrole != "AXSearchField"
    }

    public static func matches(role: String, subrole: String, hints: String, rect: CGRect,
                               clickedAt p: CGPoint, isFocusedElement: Bool) -> Bool {
        // Jamais de saisie vocale dans un champ de mot de passe
        if subrole == "AXSecureTextField" || role == "AXSecureTextField" { return false }
        // Une barre de recherche ou de saisie fait entre 12 et 92 px de haut (jamais 400 px comme un éditeur de code)
        guard rect.height >= 12, rect.height <= 92, rect.width >= 40 else { return false }
        // Tolérance horizontale plus large pour l'élément focalisé (clic sur la loupe ou la marge interne de la barre)
        let dx: CGFloat = isFocusedElement ? -110 : -16
        let dy: CGFloat = isFocusedElement ? -28 : -16
        guard rect.insetBy(dx: dx, dy: dy).contains(p) else { return false }

        let lowerHints = hints.lowercased()
        let hasKeyword = searchKeywords.contains { lowerHints.contains($0) }
        if subrole == "AXSearchField" || role == "AXSearchField" { return true }
        if textRoles.contains(role) && rect.height <= 84 { return true }
        if role == "AXTextArea" && rect.height <= 84 && (hasKeyword || isFocusedElement) { return true }
        if (role == "AXGroup" || role == "AXUnknown") && rect.height <= 64 && hasKeyword { return true }
        return false
    }
}

/// Raccourci global configuré dans Librewispr (`~/Library/Application Support/com.librewispr/settings.json`).
public struct LibrewisprShortcut: Equatable, Sendable {
    public let keyCode: UInt16
    public let command: Bool
    public let option: Bool
    public let control: Bool
    public let shift: Bool
    public let label: String

    public init(keyCode: UInt16, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false, label: String) {
        self.keyCode = keyCode
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
        self.label = label
    }

    public static let defaultShortcut = LibrewisprShortcut(keyCode: 35, command: true, label: "⌘P")

    private static let keyCodes: [String: (code: UInt16, label: String)] = [
        "a": (0, "A"), "s": (1, "S"), "d": (2, "D"), "f": (3, "F"), "h": (4, "H"), "g": (5, "G"),
        "z": (6, "Z"), "x": (7, "X"), "c": (8, "C"), "v": (9, "V"), "b": (11, "B"), "q": (12, "Q"),
        "w": (13, "W"), "e": (14, "E"), "r": (15, "R"), "y": (16, "Y"), "t": (17, "T"),
        "1": (18, "1"), "2": (19, "2"), "3": (20, "3"), "4": (21, "4"), "6": (22, "6"), "5": (23, "5"),
        "9": (25, "9"), "7": (26, "7"), "8": (28, "8"), "0": (29, "0"),
        "o": (31, "O"), "u": (32, "U"), "i": (34, "I"), "p": (35, "P"), "l": (37, "L"), "j": (38, "J"),
        "k": (40, "K"), "n": (45, "N"), "m": (46, "M"),
        "space": (49, "Space"), "tab": (48, "Tab"), "enter": (36, "↩"), "return": (36, "↩"),
        "escape": (53, "Esc"), "esc": (53, "Esc"),
        "f1": (122, "F1"), "f2": (120, "F2"), "f3": (99, "F3"), "f4": (118, "F4"),
        "f5": (96, "F5"), "f6": (97, "F6"), "f7": (98, "F7"), "f8": (100, "F8"),
        "f9": (101, "F9"), "f10": (109, "F10"), "f11": (103, "F11"), "f12": (111, "F12"),
    ]

    /// Décode une chaîne de raccourci Tauri/Librewispr comme `"Super+P"` ou `"Alt+Space"`.
    public static func parse(_ raw: String) -> LibrewisprShortcut? {
        let parts = raw.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        var cmd = false, opt = false, ctrl = false, shift = false
        var mainKey: (code: UInt16, label: String)?
        for part in parts {
            switch part.lowercased() {
            case "super", "cmd", "command", "meta", "cmdorctrl", "commandorcontrol": cmd = true
            case "alt", "option", "opt": opt = true
            case "ctrl", "control": ctrl = true
            case "shift": shift = true
            default:
                guard mainKey == nil, let k = keyCodes[part.lowercased()] else { return nil }
                mainKey = k
            }
        }
        guard let key = mainKey else { return nil }
        var lbl = ""
        if ctrl { lbl += "⌃" }
        if opt { lbl += "⌥" }
        if shift { lbl += "⇧" }
        if cmd { lbl += "⌘" }
        lbl += key.label
        return LibrewisprShortcut(keyCode: key.code, command: cmd, option: opt, control: ctrl, shift: shift, label: lbl)
    }

    /// Lit `app_settings.shortcut` depuis les données JSON de `settings.json` de Librewispr.
    public static func fromSettingsJSON(_ data: Data) -> LibrewisprShortcut? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let appSettings = root["app_settings"] as? [String: Any],
              let raw = appSettings["shortcut"] as? String else { return nil }
        return parse(raw)
    }
}
