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

            Section("Démarrage") {
                Toggle("Ouvrir AirPodsMouse au démarrage du Mac", isOn: Binding(get: { model.launchAtLogin },
                                                                              set: { model.launchAtLogin = $0 }))
            }

            Section("Raccourcis clavier") {
                LabeledContent("Pause / reprendre") { Text(verbatim: "⌃ ⌥ P").monospaced() }
                LabeledContent("Calibrer") { Text(verbatim: "⌃ ⌥ C").monospaced() }
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
                    LabeledSlider(title: "Délai avant le clic", value: $model.dwellDelay, range: 0.6...2,
                                  low: "Court", high: "Long", format: { String(format: "%.1f s", $0) })
                }
            } footer: {
                Text("Idéal si les gestes rapides sont difficiles. Pour cliquer à nouveau au même endroit, éloigne un peu le curseur puis reviens.")
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
