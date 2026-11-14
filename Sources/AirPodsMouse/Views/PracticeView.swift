import SwiftUI

/// Jeu d'entraînement : 3 cibles à viser et cliquer, l'une après l'autre.
struct PracticeView: View {
    var compact = false
    private let total = 3
    @State private var hits = 0
    @State private var target = CGPoint(x: 0.5, y: 0.5)   // position relative (0…1)
    @State private var hovering = false
    @State private var pop = false

    var body: some View {
        VStack(spacing: 12) {
            if !compact {
                Text("Vise chaque cible avec la tête, puis clique (hochement ou clic automatique).")
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.background.secondary)
                    if hits < total {
                        Button(action: hit) {
                            ZStack {
                                Circle().fill(Color.brand.opacity(hovering ? 0.35 : 0.18))
                                Circle().fill(Color.brand.opacity(hovering ? 0.7 : 0.45)).padding(18)
                                Circle().fill(Color.brand).padding(34)
                            }
                            .frame(width: 96, height: 96)
                            .scaleEffect(hovering ? 1.12 : 1)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering = $0 }
                        .position(x: 60 + target.x * (geo.size.width - 120), y: 60 + target.y * (geo.size.height - 120))
                        .transition(.scale.combined(with: .opacity))
                        .id(hits)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "party.popper.fill").font(.system(size: 48)).foregroundStyle(.orange)
                                .scaleEffect(pop ? 1 : 0.4)
                            Text("Bravo, tu sais cliquer avec ta tête !").font(.title2.weight(.semibold))
                            Button("Recommencer") { restart() }
                        }
                        .onAppear { withAnimation(.spring(duration: 0.5, bounce: 0.5)) { pop = true } }
                    }
                }
            }
            .frame(minHeight: compact ? 270 : 320)
            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { i in
                    Image(systemName: i < hits ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(i < hits ? .green : .secondary)
                }
            }
            .font(.title3)
        }
        .padding(compact ? 0 : 24)
        .animation(.spring(duration: 0.35), value: hits)
    }

    private func hit() {
        NSSound(named: "Pop")?.play()
        hovering = false
        hits += 1
        target = CGPoint(x: .random(in: 0...1), y: .random(in: 0...1))
    }

    private func restart() { pop = false; hits = 0; target = CGPoint(x: 0.5, y: 0.5) }
}
