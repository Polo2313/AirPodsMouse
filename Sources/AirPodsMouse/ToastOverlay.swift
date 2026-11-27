import AppKit
import SwiftUI

/// Petite bulle près du curseur pour les événements importants (l'icône de la barre des menus est souvent
/// cachée par l'encoche) : AirPods perdus ou retrouvés, pause, recentrage, glisser, défilement…
@MainActor
final class ToastOverlay {
    static let shared = ToastOverlay()
    private let panel: NSPanel
    private let host: NSHostingView<ToastView>
    private var hideWork: DispatchWorkItem?
    private var generation: UInt64 = 0

    private init() {
        host = NSHostingView(rootView: ToastView(symbol: "", text: ""))
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = host
    }

    func show(_ text: String, symbol: String) {
        generation &+= 1
        let gen = generation
        hideWork?.cancel()
        host.rootView = ToastView(symbol: symbol, text: text)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let m = NSEvent.mouseLocation
        // En bas à droite du curseur, sans sortir de l'écran (y compris sur le bord maxX/maxY)
        let targetScreen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(m) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        var origin = NSPoint(x: m.x + 22, y: m.y - 22 - size.height)
        if let screen = targetScreen?.visibleFrame {
            let maxX = max(screen.minX + 8, screen.maxX - size.width - 8)
            let maxY = max(screen.minY + 8, screen.maxY - size.height - 8)
            origin.x = min(max(origin.x, screen.minX + 8), maxX)
            origin.y = min(max(origin.y, screen.minY + 8), maxY)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == gen else { return }
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; self.panel.animator().alphaValue = 0 },
                                                     completionHandler: {
                    MainActor.assumeIsolated {
                        guard self.generation == gen else { return }
                        self.panel.orderOut(nil)
                    }
                })
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }
}

struct ToastView: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.brand)
            Text(text).font(.system(size: 13, weight: .medium)).fixedSize()
        }
        .accessibilityElement(children: .combine)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .padding(6)
    }
}
