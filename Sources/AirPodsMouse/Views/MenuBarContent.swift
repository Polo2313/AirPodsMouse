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
        Button(model.isDragging ? LocalizedStringKey("Lâcher") : LocalizedStringKey("Glisser-déposer")) { model.toggleDrag() }
        Button(model.scrollMode ? LocalizedStringKey("Arrêter de défiler") : LocalizedStringKey("Défiler avec la tête")) { model.toggleScrollMode() }
        Toggle("Parler au clic dans une recherche", isOn: $model.autoVoiceOnTextClick)
        Button("Parler maintenant") { model.startVoiceInput() }
        Button("Clavier visuel") { HandsFree.showKeyboard() }
        Button("Dictée") { HandsFree.startDictation() }
        Divider()
        Button("Réglages…") { WindowManager.shared.showSettings() }
            .keyboardShortcut(",")
        Button("Quitter AirPodsMouse") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
