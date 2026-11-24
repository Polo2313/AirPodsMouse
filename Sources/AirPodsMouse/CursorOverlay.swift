import AppKit
import SwiftUI

/// Anneau discret qui suit le curseur : se remplit avant un clic automatique, pulse au moment d'un clic.
/// Fenêtre transparente qui laisse passer les clics, visible sur tous les bureaux et en plein écran.
@MainActor
final class CursorOverlay {
    static let shared = CursorOverlay()
    private let size: CGFloat = 64
    private let panel: NSPanel
    private var shown = false
    private var lastOrigin = NSPoint(x: -9999, y: -9999)

    private init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: CursorRing().environmentObject(AppModel.shared))
    }

    /// À appeler à chaque image (120 Hz).
    func update(visible: Bool) {
        if visible {
            let m = NSEvent.mouseLocation
            let origin = NSPoint(x: (m.x - size / 2).rounded(), y: (m.y - size / 2).rounded())
            if hypot(origin.x - lastOrigin.x, origin.y - lastOrigin.y) >= 0.5 {
                panel.setFrameOrigin(origin)
                lastOrigin = origin
            }
            if !shown { panel.orderFrontRegardless(); shown = true }
        } else if shown {
            panel.orderOut(nil); shown = false
        }
    }
}

struct CursorRing: View {
    @EnvironmentObject var model: AppModel
    @State private var pulse = true

    var body: some View {
        ZStack {
            if model.dwellProgress > 0 {
                Circle().stroke(.white.opacity(0.35), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: model.dwellProgress)
                    .stroke(Color.brand, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .black.opacity(0.35), radius: 2)
            }
            if model.isDragging || model.scrollMode {
                Image(systemName: model.isDragging ? "hand.draw.fill" : "arrow.up.and.down.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white, Color.brand)
                    .padding(5)
                    .background(Color.brand, in: Circle())
                    .offset(x: 18, y: 18)
            }
            Circle()
                .stroke(Color.brand, lineWidth: 3)
                .scaleEffect(pulse ? 1.25 : 0.4)
                .opacity(pulse ? 0 : 0.9)
        }
        .padding(10)
        .frame(width: 64, height: 64)
        .onChange(of: model.lastClickAt) { _, _ in
            pulse = false
            withAnimation(.easeOut(duration: 0.35)) { pulse = true }
        }
    }
}
