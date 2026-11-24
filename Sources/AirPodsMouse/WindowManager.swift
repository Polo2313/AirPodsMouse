import AppKit
import SwiftUI

/// Ouvre les fenêtres de l'appli. Tant qu'une fenêtre est ouverte, l'appli apparaît dans le Dock et ⌘-Tab
/// (on la retrouve facilement) ; sinon elle reste discrète dans la barre des menus.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()
    private var windows: [String: NSWindow] = [:]
    private lazy var viewer = Viewer3D()

    func showSettings() {
        show("settings", title: String(localized: "Réglages d'AirPodsMouse"), size: NSSize(width: 720, height: 520)) {
            SettingsView().environmentObject(AppModel.shared)
        }
    }

    func showOnboarding() {
        show("onboarding", title: "", size: NSSize(width: 620, height: 560), titlebarHidden: true) {
            OnboardingView().environmentObject(AppModel.shared)
        }
    }

    func closeOnboarding() {
        windows["onboarding"]?.close()
        windows.removeValue(forKey: "onboarding")
    }

    func showViewer() {
        viewer.window.delegate = self
        AppModel.shared.onSample = { [weak self] m in self?.viewer.update(motion: m, engine: AppModel.shared.engine) }
        viewer.show()
        NSApp.setActivationPolicy(.regular)
    }

    private func show<V: View>(_ id: String, title: String, size: NSSize, titlebarHidden: Bool = false,
                               @ViewBuilder content: () -> V) {
        let window: NSWindow
        if let w = windows[id] {
            window = w
        } else {
            window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
            window.title = title
            window.isReleasedWhenClosed = false
            if titlebarHidden {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.isMovableByWindowBackground = true
            }
            window.contentView = FirstMouseHostingView(rootView: content())
            window.setContentSize(size)
            window.center()
            window.delegate = self
            windows[id] = window
        }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if !self.viewer.isVisible { AppModel.shared.onSample = nil }
                if let w = notification.object as? NSWindow, w === self.windows["onboarding"] {
                    self.windows.removeValue(forKey: "onboarding")
                }
                let open = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
                if !open { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }
}

/// Un clic dans une fenêtre inactive agit tout de suite (par défaut, macOS l'utilise seulement pour activer
/// la fenêtre : un clic de tête serait « mangé »).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
