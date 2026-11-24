import Foundation
import os

/// Journal lisible par l'utilisateur : ~/Library/Logs/AirPodsMouse.log (Réglages › À propos › Journal).
/// Conserve l'historique récent (plafonné à 256 Ko) et protège les écritures concurrentes.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AirPodsMouse.log")
    private static let maxBytes = 256 * 1024
    private static let lock = OSAllocatedUnfairLock()
    private static let handle: FileHandle? = {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        } else if let data = try? Data(contentsOf: url), data.count > maxBytes {
            let trimmed = data.suffix(maxBytes / 2)
            try? trimmed.write(to: url, options: .atomic)
        }
        let h = try? FileHandle(forWritingTo: url)
        _ = try? h?.seekToEnd()
        return h
    }()

    static func line(_ s: String) {
        lock.withLock {
            let now = Date()
            var cal = Calendar.current
            cal.timeZone = .current
            let c = cal.dateComponents([.hour, .minute, .second], from: now)
            let ts = String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
            if let data = "[\(ts)] \(s)\n".data(using: .utf8) {
                handle?.write(data)
                FileHandle.standardOutput.write(data)
            }
        }
    }
}
