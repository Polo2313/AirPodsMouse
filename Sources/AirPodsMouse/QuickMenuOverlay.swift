import AppKit
import AirPodsMouseCore
import SwiftUI

/// Affiche le menu de clic rapide autour du point visé (fenêtre transparente qui laisse passer la souris).
@MainActor
final class QuickMenuOverlay {
    static let shared = QuickMenuOverlay()
    static let size: CGFloat = 300
    private let panel: NSPanel

    private init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: QuickMenuView().environmentObject(AppModel.shared))
    }

    /// - Parameter origin: centre du menu en coordonnées écran (origine en haut à gauche).
    func show(at origin: CGPoint) {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        panel.setFrameOrigin(NSPoint(x: origin.x - Self.size / 2, y: mainHeight - origin.y - Self.size / 2))
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}

extension DwellMenu.Action {
    var symbol: String {
        switch self {
        case .click: "cursorarrow.click"
        case .doubleClick: "cursorarrow.click.2"
        case .rightClick: "contextualmenu.and.cursorarrow"
        case .drag: "hand.draw"
        case .scroll: "arrow.up.and.down"
        }
    }
    var title: LocalizedStringKey {
        switch self {
        case .click: "Clic"
        case .doubleClick: "Double-clic"
        case .rightClick: "Clic droit"
        case .drag: "Glisser"
        case .scroll: "Défiler"
        }
    }
}

struct QuickMenuView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            if let menu = model.quickMenu {
                Circle().fill(.ultraThinMaterial).frame(width: 2 * menu.radius + 90)
                    .overlay(Circle().strokeBorder(.white.opacity(0.15)))
                Circle().fill(Color.brand.opacity(0.6)).frame(width: 10)
                ForEach(DwellMenu.Action.allCases, id: \.self) { a in
                    let c = menu.itemCenter(a)
                    let hovered = model.quickMenuHovered == a
                    VStack(spacing: 2) {
                        ZStack {
                            Circle().fill(hovered ? Color.brand : Color.black.opacity(0.55))
                            if hovered {
                                Circle().trim(from: 0, to: model.quickMenuProgress)
                                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90)).padding(3)
                            }
                            Image(systemName: a.symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                        }
                        .frame(width: 2 * menu.itemRadius - 14, height: 2 * menu.itemRadius - 14)
                        Text(a.title).font(.caption2.weight(.semibold)).foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.8), radius: 2)
                    }
                    .scaleEffect(hovered ? 1.12 : 1)
                    .position(x: QuickMenuOverlay.size / 2 + (c.x - menu.origin.x), y: QuickMenuOverlay.size / 2 + (c.y - menu.origin.y))
                    .animation(.spring(duration: 0.2), value: hovered)
                }
            }
        }
        .frame(width: QuickMenuOverlay.size, height: QuickMenuOverlay.size)
    }
}
