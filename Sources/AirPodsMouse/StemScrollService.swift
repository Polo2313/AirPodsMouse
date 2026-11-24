import AppKit
import AirPodsMouseCore
import CoreAudio

/// Écoute le volume des AirPods pour détecter les glissements sur la tige (voir StemSwipeDetector),
/// remet le volume à sa valeur, et signale le glissement.
@MainActor
final class StemScrollService {
    var onSwipe: ((StemSwipe) -> Void)?
    private var device: AudioDeviceID?
    private var detector: StemSwipeDetector?
    private var listeners: [(UInt32, AudioObjectPropertyListenerBlock)] = []
    private var lastVolumeKeyAt = Date.distantPast
    private var keyMonitor: Any?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var isRestoring = false
    private(set) var enabled = false

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on {
            // Touches volume du clavier : ce ne sont pas des glissements
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] e in
                guard e.subtype.rawValue == 8 else { return }
                let key = (e.data1 & 0xFFFF0000) >> 16
                if key == 0 || key == 1 || key == 7 { MainActor.assumeIsolated { self?.lastVolumeKeyAt = Date() } }
            }
            watchDefaultOutput()
            attach()
        } else {
            if let m = keyMonitor { NSEvent.removeMonitor(m) }
            keyMonitor = nil
            unwatchDefaultOutput()
            detach()
        }
    }

    /// Le son passe sur un autre appareil : on se rebranche sur les AirPods s'ils sont la sortie.
    private func watchDefaultOutput() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.detach(); self?.attach() } }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
        outputListener = block
    }

    private func unwatchDefaultOutput() {
        guard let block = outputListener else { return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
        outputListener = nil
    }

    private func attach() {
        guard enabled, device == nil, let ap = AudioOutput.airPods(), ap == AudioOutput.defaultOutput else { return }
        let elements = [UInt32(0), 1, 2].filter { var a = Self.volumeAddress($0); return AudioObjectHasProperty(ap, &a) }
        guard let first = elements.first, let v = Self.volume(ap, first) else { return }
        device = ap
        detector = StemSwipeDetector(reference: v)
        for el in elements {
            var a = Self.volumeAddress(el)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.volumeChanged(element: el) } }
            }
            AudioObjectAddPropertyListenerBlock(ap, &a, .main, block)
            listeners.append((el, block))
        }
        Log.line("Défilement par la tige : à l'écoute des AirPods")
    }

    private func detach() {
        if let d = device {
            for (el, block) in listeners { var a = Self.volumeAddress(el); AudioObjectRemovePropertyListenerBlock(d, &a, .main, block) }
        }
        listeners = []; device = nil; detector = nil
    }

    private func volumeChanged(element: UInt32) {
        guard !isRestoring, let d = device, var det = detector, let v = Self.volume(d, element) else { return }
        let key = Date().timeIntervalSince(lastVolumeKeyAt) < 0.4
        let swipe = det.volumeChanged(to: v, at: ProcessInfo.processInfo.systemUptime, keyPressedRecently: key)
        detector = det
        guard let swipe else { return }
        // Remet le volume où il était (le glissement ne doit pas changer le son)
        isRestoring = true
        for (el, _) in listeners { Self.setVolume(d, el, det.reference) }
        isRestoring = false
        onSwipe?(swipe)
    }

    // MARK: - CoreAudio

    private static func volumeAddress(_ el: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: el)
    }

    private static func volume(_ d: AudioDeviceID, _ el: UInt32) -> Double? {
        var a = volumeAddress(el); var v = Float32(0); var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(d, &a, 0, nil, &size, &v) == noErr ? Double(v) : nil
    }

    private static func setVolume(_ d: AudioDeviceID, _ el: UInt32, _ v: Double) {
        var a = volumeAddress(el); var f = Float32(v)
        AudioObjectSetPropertyData(d, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &f)
    }
}
