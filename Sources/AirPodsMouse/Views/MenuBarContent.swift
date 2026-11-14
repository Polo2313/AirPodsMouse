import SwiftUI

/// Menu de l'icône dans la barre des menus : l'essentiel, à portée d'un clic.
struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Text(model.status.title)
        if model.status == .noMotion {
            Button("Ramener les AirPods sur ce Mac") { model.wakeAirPods() }
        }
        if !model.axTrusted {
            Button("⚠️ Autoriser l'Accessibilité…") { Permissions.openAccessibilitySettings() }
        }
        Divider()
        Button(model.isPaused ? LocalizedStringKey("Reprendre") : LocalizedStringKey("Pause")) { model.togglePause() }
            .keyboardShortcut("p", modifiers: [.control, .option])
        Toggle("Clic automatique", isOn: $model.dwellEnabled)
        Toggle("Clic par hochement de tête", isOn: $model.nodClick)
        Divider()
        Button("Réglages…") { WindowManager.shared.showSettings() }
            .keyboardShortcut(",")
        Button("Quitter AirPodsMouse") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
