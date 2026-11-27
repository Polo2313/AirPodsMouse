import SwiftUI

/// Accueil du premier lancement : mène jusqu'au premier clic réussi, sans aide extérieure.
struct OnboardingView: View {
    enum Step: Int, CaseIterable { case welcome, motion, airpods, accessibility, click, practice }

    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .welcome
    @State private var forward = true

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Group {
                    switch step {
                    case .welcome: WelcomeStep()
                    case .motion: MotionStep()
                    case .airpods: AirPodsStep()
                    case .accessibility: AccessibilityStep()
                    case .click: ClickChoiceStep()
                    case .practice: PracticeStep()
                    }
                }
                .id(step)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            .padding(.top, 36)

            footer
        }
        .frame(width: 620, height: 560)
        .background(
            LinearGradient(colors: [Color.brand.opacity(0.14), .clear], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
        // Avance tout seul quand une autorisation vient d'être accordée
        .onChange(of: model.motionAuth) { _, auth in if step == .motion && auth == .authorized { go(.airpods) } }
        .onChange(of: model.axTrusted) { _, ok in if step == .accessibility && ok { go(.click) } }
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Retour") { if let prev = Step(rawValue: step.rawValue - 1) { go(prev) } }
                    .buttonStyle(.borderless)
            }
            Spacer()
            HStack(spacing: 7) {
                ForEach(Step.allCases, id: \.self) { s in
                    Circle()
                        .fill(s == step ? Color.brand : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
            Spacer()
            nextButton
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(.bar)
    }

    @ViewBuilder private var nextButton: some View {
        switch step {
        case .welcome:
            Button("Commencer") { go(.motion) }.buttonStyle(.borderedProminent).controlSize(.large)
        case .practice:
            Button("Terminer") { finish() }.buttonStyle(.borderedProminent).controlSize(.large)
        case .motion:
            Button("Continuer") { go(.airpods) }.buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.motionAuth != .authorized)
        case .accessibility:
            Button("Continuer") { go(.click) }.buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!model.axTrusted)
        default:
            Button("Continuer") { if let next = Step(rawValue: step.rawValue + 1) { go(next) } }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private func go(_ s: Step) {
        guard s != step else { return }
        forward = s.rawValue > step.rawValue
        if reduceMotion { step = s } else { withAnimation(.spring(duration: 0.45)) { step = s } }
    }

    private func finish() {
        model.onboardingDone = true
        WindowManager.shared.closeOnboarding()
    }
}

// MARK: - Éléments communs

struct StepHeader: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 86, height: 86)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: color.opacity(0.35), radius: 14, y: 6)
            Text(title).font(.system(size: 26, weight: .bold)).multilineTextAlignment(.center)
            Text(text).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DoneBadge: View {
    let text: LocalizedStringKey
    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.headline)
            .foregroundStyle(.green)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.green.opacity(0.12), in: Capsule())
            .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Étapes

struct WelcomeStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = false
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "airpodspro")
                    .font(.system(size: 92, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .rotationEffect(.degrees(reduceMotion ? 0 : (tilt ? -8 : 8)))
                Image(systemName: "cursorarrow")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.primary)
                    .offset(x: 18, y: 8)
            }
            .frame(height: 130)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever()) { tilt = true }
            }
            Text("Pilote ton Mac avec ta tête").font(.system(size: 30, weight: .bold))
            Text("Tes AirPods deviennent une souris : tourne la tête pour déplacer le curseur, fais un petit « oui » pour cliquer.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Text("Il faut des AirPods Pro, AirPods 3, AirPods 4 ou AirPods Max.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct MotionStep: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 26) {
            StepHeader(symbol: "gyroscope", color: .purple,
                       title: "Accès aux mouvements",
                       text: "AirPodsMouse lit les capteurs de mouvement de tes AirPods. Rien ne quitte ton Mac.")
            switch model.motionAuth {
            case .authorized:
                DoneBadge(text: "Accès autorisé")
            case .denied, .restricted:
                VStack(spacing: 10) {
                    Text("L'accès a été refusé. Active « AirPodsMouse » dans Réglages › Confidentialité et sécurité › Mouvements et forme.")
                        .multilineTextAlignment(.center).foregroundStyle(.orange)
                    Button("Ouvrir le réglage") { Permissions.openMotionSettings() }.controlSize(.large)
                }
            default:
                VStack(spacing: 8) {
                    Button { model.requestMotion() } label: {
                        Label("Autoriser l'accès", systemImage: "hand.raised.fill").padding(.horizontal, 10)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    Text("Le Mac va afficher une demande : clique « Autoriser ».").font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

struct AirPodsStep: View {
    @EnvironmentObject var model: AppModel
    @State private var shownAt = Date()
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var moving: Bool { model.status == .active || model.status == .paused }

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(symbol: "airpodspro", color: .blue,
                       title: "Mets tes AirPods",
                       text: "Dans tes deux oreilles, puis bouge un peu la tête.")
            HeadIndicator(rates: model.headRates, active: moving)
                .frame(width: 150, height: 150)
            if moving {
                DoneBadge(text: "Tes AirPods bougent !")
            } else {
                VStack(spacing: 10) {
                    Text(model.noMotionHint).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button { model.wakeAirPods() } label: {
                        Label("Ramener les AirPods sur ce Mac", systemImage: "arrow.down.left.and.arrow.up.right.circle")
                    }
                    .controlSize(.large)
                    if now.timeIntervalSince(shownAt) > 10 {
                        Text("Toujours rien ? Vérifie que ce sont bien des AirPods Pro, 3, 4 ou Max, connectés à ce Mac.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
            }
            Spacer()
        }
        .onReceive(clock) { now = $0 }
        .animation(.spring, value: moving)
    }
}

/// Une cible qui suit les mouvements de la tête : on voit tout de suite que ça marche.
struct HeadIndicator: View {
    let rates: SIMD2<Double>   // lacet, tangage (rad/s)
    let active: Bool
    var body: some View {
        ZStack {
            Circle().fill(.quaternary)
            Circle().strokeBorder(.tertiary, lineWidth: 1).padding(30)
            Circle()
                .fill(active ? Color.brand.gradient : Color.secondary.gradient)
                .frame(width: 34, height: 34)
                .shadow(color: Color.brand.opacity(active ? 0.5 : 0), radius: 10)
                .offset(x: CGFloat(-max(min(rates.x, 1.5), -1.5)) * 40, y: CGFloat(-max(min(rates.y, 1.5), -1.5)) * 40)
                .animation(.spring(duration: 0.25), value: rates)
        }
    }
}

struct AccessibilityStep: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var toggleOn = false
    var body: some View {
        VStack(spacing: 22) {
            StepHeader(symbol: "accessibility", color: .indigo,
                       title: "Autorise le contrôle du curseur",
                       text: "macOS demande ton accord pour qu'une appli déplace le curseur et clique.")
            if model.axTrusted {
                DoneBadge(text: "C'est autorisé")
            } else {
                // Petite démonstration de ce qu'il faut faire dans Réglages
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 26, height: 26)
                    Text(verbatim: "AirPodsMouse").font(.body.weight(.medium))
                    Spacer()
                    Toggle("", isOn: .constant(toggleOn)).toggleStyle(.switch).labelsHidden().allowsHitTesting(false)
                }
                .padding(12)
                .frame(width: 320)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .trailing) {
                    Image(systemName: "hand.point.up.left.fill").font(.title2).foregroundStyle(.secondary)
                        .offset(x: 18, y: 18).opacity(toggleOn ? 0 : 1)
                }
                .accessibilityHidden(true)
                .onAppear {
                    if reduceMotion { toggleOn = true }
                    else { withAnimation(.easeInOut(duration: 1).delay(0.6).repeatForever()) { toggleOn = true } }
                }

                Button {
                    Permissions.promptAccessibility()
                    Permissions.openAccessibilitySettings()
                } label: {
                    Label("Ouvrir le réglage", systemImage: "arrow.up.forward.app").padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                Text("Active l'interrupteur à côté d'AirPodsMouse, puis reviens ici : la suite s'affiche toute seule.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
    }
}

struct ClickChoiceStep: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("Comment veux-tu cliquer ?").font(.system(size: 26, weight: .bold))
                Text("Tu pourras changer plus tard dans les réglages.").foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                ChoiceCard(selected: model.nodClick && !model.dwellEnabled,
                           symbol: "arrow.down.and.line.horizontal.and.arrow.up", color: .indigo,
                           title: "Hochement de tête",
                           text: "Un petit « oui » rapide : baisse la tête d'un coup et reviens.") {
                    model.nodClick = true; model.dwellEnabled = false
                }
                ChoiceCard(selected: model.dwellEnabled,
                           symbol: "timer", color: .orange,
                           title: "Clic automatique",
                           text: "Garde le curseur immobile une seconde sur la cible. Idéal si les gestes rapides sont difficiles.") {
                    model.dwellEnabled = true; model.nodClick = false
                }
            }
            Spacer()
        }
    }
}

struct ChoiceCard: View {
    let selected: Bool
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SettingsIcon(symbol: symbol, color: color, size: 40)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(selected ? Color.brand : .secondary)
                }
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(width: 240, height: 190, alignment: .topLeading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? Color.brand : .clear, lineWidth: 2.5))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.spring(duration: 0.3), value: selected)
    }
}

struct PracticeStep: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("À toi de jouer !").font(.system(size: 26, weight: .bold))
            Text("Vise chaque cible avec la tête et clique dessus.").foregroundStyle(.secondary)
            PracticeView(compact: true)
        }
    }
}
