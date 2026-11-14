import CoreMotion
import Foundation

/// Lit les capteurs des AirPods.
/// Mesuré : ~50 mesures/s arrivant par paquets ; un flux qui démarre peut mettre plusieurs secondes,
/// et chaque relance (stop/start) provoque une déconnexion/reconnexion qui peut le couper.
/// On ne relance donc qu'après 45 s de silence, et jamais sur l'événement « connecté » (boucle).
@MainActor
final class MotionService: NSObject, CMHeadphoneMotionManagerDelegate {
    private let manager = CMHeadphoneMotionManager()
    var onSample: ((CMDeviceMotion) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    private(set) var startedAt = Date.distantPast
    private(set) var lastSampleAt: Date?
    private(set) var connected = false
    private var lastAuth: CMAuthorizationStatus?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    /// Reçoit des mesures récentes (< 2 s).
    var isStreaming: Bool { lastSampleAt.map { Date().timeIntervalSince($0) < 2 } ?? false }

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        let auth = Permissions.motion
        lastAuth = auth
        guard auth != .denied && auth != .restricted else { return }
        manager.delegate = self
        manager.stopDeviceMotionUpdates()
        startedAt = Date()
        manager.startDeviceMotionUpdates(to: .main) { [weak self] m, err in
            if let err { Log.line("Erreur capteurs : \(err.localizedDescription)"); return }
            guard let m else { return }
            MainActor.assumeIsolated {
                self?.lastSampleAt = Date()
                self?.onSample?(m)
            }
        }
    }

    /// À appeler chaque seconde.
    func healthCheck() {
        let auth = Permissions.motion
        if auth != lastAuth {
            Log.line("Autorisation Mouvements : \(auth.rawValue)")
            lastAuth = auth
            if auth == .authorized { start() }   // des mises à jour lancées avant l'accord restent muettes
        }
        let silentFor = Date().timeIntervalSince(lastSampleAt ?? startedAt)
        if silentFor > 45, Date().timeIntervalSince(startedAt) > 45, auth == .authorized { start() }
    }

    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            if !self.connected { Log.line("AirPods connectés") }
            self.connected = true; self.onConnectionChange?(true)
        }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in self.connected = false; self.onConnectionChange?(false) }
    }
}
