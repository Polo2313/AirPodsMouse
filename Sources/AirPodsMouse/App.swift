import AppKit
import SwiftUI

@main
struct AirPodsMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent().environmentObject(model)
        } label: {
            Image(systemName: model.menuBarSymbol)
                .accessibilityLabel("AirPodsMouse")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
                Viewer3D().renderSnapshot(to: CommandLine.arguments[i + 1]); exit(0)
            }
            NSApp.setActivationPolicy(.accessory)
            HotKeys.register()
            AppModel.shared.start()
            if CommandLine.arguments.contains("--test-toast") {   // vérification visuelle de la bulle
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    MainActor.assumeIsolated { ToastOverlay.shared.show(String(localized: "Recentré"), symbol: "scope") }
                }
            }
            if AppModel.shared.onboardingDone { WindowManager.shared.showSettings() }
            else { WindowManager.shared.showOnboarding() }
        }
    }

    /// Ne jamais quitter avec le bouton de la souris enfoncé (glisser en cours).
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { if AppModel.shared.cursor.dragging { AppModel.shared.cursor.endDrag() } }
    }

    /// Double-clic sur l'appli déjà ouverte (utile si l'icône est cachée par l'encoche) → Réglages.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { WindowManager.shared.showSettings() }
        return false
    }
}

extension AppModel {
    var menuBarSymbol: String {
        switch status {
        case .active, .searching: "airpodspro"
        case .paused: "pause.circle"
        case .calibrating: "arrow.up.and.down.circle"
        case .noMotion, .motionDenied, .unavailable: "exclamationmark.triangle"
        }
    }
}
