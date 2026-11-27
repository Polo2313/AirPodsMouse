import SwiftUI
import AirPodsMouseCore

/// Fenêtre de réglages, organisée comme les Réglages Système.
struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, pointer, click, practice, about
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .general: "Général"
            case .pointer: "Pointeur"
            case .click: "Clic"
            case .practice: "Essai"
            case .about: "À propos"
            }
        }
        var symbol: String {
            switch self {
            case .general: "gearshape.fill"
            case .pointer: "cursorarrow.motionlines"
            case .click: "hand.tap.fill"
            case .practice: "target"
            case .about: "info.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .general: .gray
            case .pointer: .blue
            case .click: .indigo
            case .practice: .orange
            case .about: .teal
            }
        }
    }

    @EnvironmentObject var model: AppModel
    @AppStorage("settingsPane") private var lastPane = Pane.general.rawValue   // rouvre le dernier volet
    @State private var pane: Pane?

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: Binding(get: { pane ?? Pane(rawValue: lastPane) ?? .general },
                                                   set: { pane = $0; lastPane = ($0 ?? .general).rawValue })) { p in
                Label { Text(p.title) } icon: { SettingsIcon(symbol: p.symbol, color: p.color) }
                    .tag(p)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch pane ?? Pane(rawValue: lastPane) ?? .general {
                case .general: GeneralPane()
                case .pointer: PointerPane()
                case .click: ClickPane()
                case .practice: PracticeView()
                case .about: AboutPane()
                }
            }
            .navigationTitle(Text((pane ?? Pane(rawValue: lastPane) ?? .general).title))
        }
        .frame(minWidth: 680, minHeight: 480)
    }
}

// MARK: - Général

struct GeneralPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: model.status.symbol)
                        .font(.system(size: 30))
                        .foregroundStyle(model.status.color)
                        .symbolEffect(.pulse, isActive: model.status == .searching)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.status.title).font(.title3.weight(.semibold))
                        if model.status == .noMotion { Text(model.noMotionHint).foregroundStyle(.secondary) }
                        else if model.status == .active { Text("Bouge la tête pour déplacer le curseur.").foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if model.status == .noMotion {
                        Button("Ramener les AirPods sur ce Mac") { model.wakeAirPods() }
                    } else {
                        Button(model.isPaused ? LocalizedStringKey("Reprendre") : LocalizedStringKey("Pause")) { model.togglePause() }
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Vérifications") {
                CheckRow(ok: model.airPodsConnected || model.status == .active,
                         title: "AirPods connectés",
                         detail: "AirPods Pro, AirPods 3, 4 ou AirPods Max, dans tes oreilles.")
                CheckRow(ok: model.airPodsAreAudioOutput || model.status == .active,
                         title: "Son du Mac dans les AirPods",
                         detail: "Aide les AirPods à envoyer leurs mouvements.",
                         action: model.airPodsAreAudioOutput ? nil : ("Utiliser les AirPods", { model.routeAudioToAirPods() }))
                CheckRow(ok: model.motionAuth == .authorized,
                         title: "Accès aux mouvements",
                         detail: "Pour lire les capteurs des AirPods.",
                         action: model.motionAuth == .authorized ? nil : ("Ouvrir le réglage", { Permissions.openMotionSettings() }))
                CheckRow(ok: model.axTrusted,
                         title: "Accessibilité",
                         detail: "Pour déplacer le curseur et cliquer.",
                         action: model.axTrusted ? nil : ("Ouvrir le réglage", { Permissions.openAccessibilitySettings() }))
            }

            Section {
                Toggle("Afficher des messages près du curseur", isOn: $model.toasts)
            } footer: {
                Text("Une petite bulle signale les AirPods perdus ou retrouvés, la pause, le recentrage, le glisser et le défilement.")
            }

            Section {
                Toggle("Figer le curseur pendant la frappe", isOn: $model.typingPause)
            } footer: {
                Text("Quand tu tapes, tu regardes le clavier : le curseur reste en place jusqu'à une seconde après la dernière touche.")
            }

            Section {
                Toggle("Parler automatiquement au clic dans une barre de recherche", isOn: $model.autoVoiceOnTextClick)
                if model.autoVoiceOnTextClick {
                    Picker("Action vocale", selection: $model.voiceInputMode) {
                        Text("Dicter avec Librewispr").tag(VoiceInputMode.librewispr)
                        Text("Ouvrir Librewispr").tag(VoiceInputMode.openLibrewispr)
                        Text("Dictée de macOS").tag(VoiceInputMode.macosDictation)
                        Text("Clavier visuel").tag(VoiceInputMode.onScreenKeyboard)
                    }
                }
                HStack {
                    Button { model.startVoiceInput() } label: {
                        Label(model.isVoiceListening ? LocalizedStringKey("Arrêter l'écoute") : LocalizedStringKey("Parler maintenant"),
                              systemImage: model.isVoiceListening ? "mic.slash.fill" : "mic.fill")
                    }
                    Button { HandsFree.showKeyboard() } label: { Label("Clavier visuel", systemImage: "keyboard") }
                    Button { HandsFree.startDictation() } label: { Label("Dictée", systemImage: "mic") }
                }
            } header: {
                Text("Écrire sans les mains")
            } footer: {
                Text("Quand tu cliques dans une barre de recherche ou une zone de texte, AirPodsMouse lance automatiquement Librewispr (ou l'outil choisi) pour que tu puisses parler tout de suite.")
            }

            Section("Démarrage") {
                Toggle("Ouvrir AirPodsMouse au démarrage du Mac", isOn: Binding(get: { model.launchAtLogin },
                                                                              set: { model.launchAtLogin = $0 }))
            }

            Section("Raccourcis clavier") {
                LabeledContent("Pause / reprendre") { Text(verbatim: "⌃ ⌥ P").monospaced() }
                LabeledContent("Recentrer (je regarde le centre)") { Text(verbatim: "⌃ ⌥ C").monospaced() }
                LabeledContent("Glisser-déposer (attraper / lâcher)") { Text(verbatim: "⌃ ⌥ D").monospaced() }
                LabeledContent("Défiler avec la tête") { Text(verbatim: "⌃ ⌥ S").monospaced() }
                LabeledContent("Dicter avec la voix") { Text(verbatim: "⌃ ⌥ M").monospaced() }
                LabeledContent("Ouvrir les réglages") { Text(verbatim: "⌃ ⌥ V").monospaced() }
                LabeledContent("Quitter") { Text(verbatim: "⌃ ⌥ Q").monospaced() }
            }
        }
        .formStyle(.grouped)
    }
}

struct CheckRow: View {
    let ok: Bool
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    var action: (LocalizedStringKey, () -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let action { Button(action.0, action: action.1) }
        }
    }
}

// MARK: - Pointeur

struct PointerPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledSlider(title: "Vitesse", value: $model.sensitivity, range: 0.3...3,
                              low: "Lente", high: "Rapide", format: { "\(Int(($0 * 100).rounded())) %" })
                LabeledSlider(title: "Vitesse verticale", value: $model.verticalRatio, range: 1.5...3.5,
                              low: "Moins", high: "Plus", format: { String(format: "×%.1f", $0) })
            } footer: {
                Text("On bouge moins la tête de haut en bas que de gauche à droite : la vitesse verticale compense.")
            }

            Section {
                Toggle("Mémoire des bords (garder le fil hors de l'écran)", isOn: $model.edgeMemory)
                Toggle("Garder la tête alignée avec l'écran", isOn: $model.alignment)
                HStack {
                    Text("Recentrer maintenant")
                    Spacer()
                    Button("Recentrer") { model.recenter() }
                }
            } header: {
                Text("Alignement")
            } footer: {
                Text("Quand la souris touche un bord et que tu continues de tourner la tête, elle attend que ta tête revienne au bord avant de repartir. Regarder en face de l'écran ramène toujours le curseur au centre (⌃⌥C pour recentrer tout de suite).")
            }

            Section {
                Toggle("Aimant : ralentir sur les boutons", isOn: $model.magnet)
                if model.magnet {
                    Picker("Force", selection: $model.magnetStrength) {
                        Text("Léger").tag(MagnetStrength.light)
                        Text("Moyen").tag(MagnetStrength.medium)
                        Text("Fort").tag(MagnetStrength.strong)
                    }
                    .pickerStyle(.segmented)
                }
            } footer: {
                Text("Au-dessus d'un bouton, d'un lien ou d'une case, le curseur ralentit en visée fine : plus facile de s'arrêter dessus. Un mouvement franc n'est jamais freiné.")
            }

            Section("Sens") {
                Toggle("Inverser gauche / droite", isOn: $model.invertX)
                Toggle("Inverser haut / bas", isOn: $model.invertY)
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calibrage du haut / bas")
                        Text(model.isCalibrated ? LocalizedStringKey("Personnalisé") : LocalizedStringKey("Réglage par défaut (convient aux AirPods portés)"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Calibrer…") { model.startCalibration() }
                        .disabled(model.status == .calibrating)
                }
                if model.status == .calibrating {
                    ProgressView(value: model.calibrationProgress)
                        .tint(Color.brand)
                }
                if let msg = model.calibrationMessage {
                    Text(msg).font(.callout).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Facultatif. Utile seulement si le curseur part en diagonale quand tu lèves la tête. Clique « Calibrer », puis lève la tête et reviens, 2 ou 3 fois en 3 secondes.")
            }

            Section {
                Button("Réinitialiser tous les réglages", role: .destructive) { model.resetSettings() }
            }
        }
        .formStyle(.grouped)
    }
}

struct LabeledSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let low: LocalizedStringKey
    let high: LocalizedStringKey
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: format(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range) {
                EmptyView()
            } minimumValueLabel: {
                Text(low).font(.caption).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(high).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Clic

struct ClickPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.nodClick) {
                    Label { VStack(alignment: .leading, spacing: 2) {
                        Text("Hochement de tête")
                        Text("Un petit « oui » rapide : baisse la tête d'un coup et reviens.").font(.caption).foregroundStyle(.secondary)
                    } } icon: { SettingsIcon(symbol: "arrow.down.and.line.horizontal.and.arrow.up", color: .indigo) }
                }
                if model.nodClick {
                    Picker("Sensibilité", selection: $model.nodPreset) {
                        Text("Prudent").tag(NodPresetTag.careful)
                        Text("Normal").tag(NodPresetTag.normal)
                        Text("Facile").tag(NodPresetTag.easy)
                    }
                    .pickerStyle(.segmented)
                }
            } footer: {
                Text("« Prudent » évite les clics involontaires ; « Facile » accepte des hochements plus lents. Deux hochements de suite font un double-clic.")
            }

            Section {
                Toggle(isOn: $model.dwellEnabled) {
                    Label { VStack(alignment: .leading, spacing: 2) {
                        Text("Clic automatique")
                        Text("Garde le curseur immobile sur une cible : un anneau se remplit, puis ça clique.").font(.caption).foregroundStyle(.secondary)
                    } } icon: { SettingsIcon(symbol: "timer", color: .orange) }
                }
                if model.dwellEnabled {
                    Toggle("Ouvrir le menu de clic rapide au lieu de cliquer", isOn: $model.dwellMenu)
                    LabeledSlider(title: "Délai avant le clic", value: $model.dwellDelay, range: 0.6...2,
                                  low: "Court", high: "Long", format: { String(format: "%.1f s", $0) })
                }
            } footer: {
                Text("Idéal si les gestes rapides sont difficiles. Pour cliquer à nouveau au même endroit, éloigne un peu le curseur puis reviens.")
            }

            Section {
                Toggle(isOn: $model.stemScroll) {
                    Label { VStack(alignment: .leading, spacing: 2) {
                        Text("Défiler avec la tige des AirPods")
                        Text("Glisse le doigt vers le haut ou le bas sur la tige (AirPods Pro 2).").font(.caption).foregroundStyle(.secondary)
                    } } icon: { SettingsIcon(symbol: "arrow.up.arrow.down", color: .teal) }
                }
                if model.stemScroll {
                    Picker("Pas", selection: $model.scrollStep) {
                        Text("Petit").tag(0.125)
                        Text("Moyen").tag(0.25)
                        Text("Grand").tag(0.5)
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Défilement")
            } footer: {
                Text("Le glissement ne règle plus le volume pendant que c'est activé (le clavier et le menu Son, si). En pause, il règle à nouveau le volume. Plusieurs glissements rapprochés défilent plus loin.")
            }

            Section {
                Toggle(isOn: $model.shakeEscape) {
                    Label { VStack(alignment: .leading, spacing: 2) {
                        Text("Secouer la tête « non » = Échap")
                        Text("Pour fermer un menu ou annuler.").font(.caption).foregroundStyle(.secondary)
                    } } icon: { SettingsIcon(symbol: "escape", color: .red) }
                }
            }

            Section {
                Toggle(isOn: $model.tiltClick) {
                    Label { VStack(alignment: .leading, spacing: 2) {
                        Text("Clic droit")
                        Text("Penche vite la tête vers une épaule et reviens.").font(.caption).foregroundStyle(.secondary)
                    } } icon: { SettingsIcon(symbol: "contextualmenu.and.cursorarrow", color: .pink) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

typealias NodPresetTag = AirPodsMouseCore.NodPreset

// MARK: - À propos

struct AboutPane: View {
    @EnvironmentObject var model: AppModel
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "AirPodsMouse").font(.title2.weight(.semibold))
                        Text("Version \(version)").foregroundStyle(.secondary)
                        Text("Pilote ton Mac avec ta tête, grâce à tes AirPods.").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
            Section {
                Button("Revoir l'accueil") { WindowManager.shared.showOnboarding() }
                Button("Vue 3D des capteurs") { WindowManager.shared.showViewer() }
                Button("Ouvrir le journal") { NSWorkspace.shared.open(Log.url) }
            }
        }
        .formStyle(.grouped)
    }
}
