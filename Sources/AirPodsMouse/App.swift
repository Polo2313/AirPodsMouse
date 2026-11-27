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
            guard Self.claimSingleInstance() else { return }
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

    /// Une seule AirPodsMouse à la fois : deux copies déplacent le curseur chacune de leur côté et se prennent
    /// mutuellement pour le trackpad (pointage saccadé, clics doublés). La copie de /Applications est prioritaire :
    /// la copie du dossier du projet (ou une ancienne inscription « ouvrir au démarrage ») lui passe la main.
    /// Lancer avec `--ici` pour tester la copie du projet malgré tout.
    /// - Returns: false si cette copie doit se fermer.
    @MainActor
    private static func claimSingleInstance() -> Bool {
        let installed = URL(fileURLWithPath: "/Applications/AirPodsMouse.app")
        let me = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        if me.path != installed.path, FileManager.default.fileExists(atPath: installed.path),
           !CommandLine.arguments.contains("--ici") {
            Log.line("Lancée depuis \(me.path) : ouverture de la version installée à la place")
            NSWorkspace.shared.openApplication(at: installed, configuration: NSWorkspace.OpenConfiguration())
            NSApp.terminate(nil)
            return false
        }
        let id = Bundle.main.bundleIdentifier ?? "local.airpodsmouse"
        let pid = ProcessInfo.processInfo.processIdentifier
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: id) where other.processIdentifier != pid {
            Log.line("Une autre AirPodsMouse tournait (\(other.bundleURL?.path ?? "?")) : fermeture")
            other.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if !other.isTerminated { other.forceTerminate() } }
        }
        return true
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
