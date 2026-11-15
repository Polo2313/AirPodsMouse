import AppKit
import Carbon

/// Raccourcis globaux : ⌃⌥P pause · ⌃⌥C recentrer · ⌃⌥V réglages · ⌃⌥Q quitter · ⌃⌥D glisser · ⌃⌥S défiler.
/// Toujours un moyen de reprendre la main, même si la tête envoie le curseur n'importe où.
enum HotKeys {
    static func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch id {
                    case 1: NSApp.terminate(nil)
                    case 2: AppModel.shared.togglePause()
                    case 3: AppModel.shared.recenter()
                    case 4: WindowManager.shared.showSettings()
                    case 5: AppModel.shared.toggleDrag()
                    case 6: AppModel.shared.toggleScrollMode()
                    default: break
                    }
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
        let mods = UInt32(controlKey | optionKey)
        for (id, key) in [(UInt32(1), kVK_ANSI_Q), (UInt32(2), kVK_ANSI_P), (UInt32(3), kVK_ANSI_C), (UInt32(4), kVK_ANSI_V),
                         (UInt32(5), kVK_ANSI_D), (UInt32(6), kVK_ANSI_S)] {
            var ref: EventHotKeyRef?
            let err = RegisterEventHotKey(UInt32(key), mods, EventHotKeyID(signature: OSType(0x41504D53), id: id),
                                          GetApplicationEventTarget(), 0, &ref)
            if err != noErr { Log.line("Raccourci \(id) indisponible (déjà utilisé par une autre appli ?)") }
        }
    }
}
