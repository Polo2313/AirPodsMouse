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
            if AppModel.shared.onboardingDone { WindowManager.shared.showSettings() }
            else { WindowManager.shared.showOnboarding() }
        }
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
