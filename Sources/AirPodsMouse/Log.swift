import Darwin
import Foundation
import os

/// Journal lisible par l'utilisateur : ~/Library/Logs/AirPodsMouse.log (Réglages › À propos › Journal).
/// Conserve l'historique récent (plafonné à 256 Ko) et protège les écritures concurrentes inter-threads et inter-processus.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AirPodsMouse.log")
    private static let maxBytes = 256 * 1024
    private struct State {
        var fd: Int32 = -1
        var bytesWritten: Int = 0
    }
    private static let state = OSAllocatedUnfairLock(initialState: State())

    private static func ensureOpen(_ st: inout State) -> Int32 {
        if st.fd >= 0 && st.bytesWritten < maxBytes { return st.fd }
        if st.fd >= 0 {
            Darwin.close(st.fd)
            st.fd = -1
        }
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: url), data.count > maxBytes {
            let suffix = data.suffix(maxBytes / 2)
            // Coupe proprement au début d'une ligne
            if let nl = suffix.firstIndex(of: 0x0A), nl + 1 < suffix.endIndex {
                try? suffix[(nl + 1)...].write(to: url, options: .atomic)
            } else {
                try? suffix.write(to: url, options: .atomic)
            }
        }
        let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        st.fd = fd
        st.bytesWritten = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return fd
    }

    static func line(_ s: String) {
        let now = Date()
        var cal = Calendar.current
        cal.timeZone = .current
        let c = cal.dateComponents([.hour, .minute, .second], from: now)
        let ts = String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        guard let data = "[\(ts)] \(s)\n".data(using: .utf8) else { return }
        state.withLock { st in
            let fd = ensureOpen(&st)
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress, raw.count > 0 else { return }
                if fd >= 0 {
                    let n = Darwin.write(fd, base, raw.count)
                    if n > 0 { st.bytesWritten += n }
                }
                _ = Darwin.write(STDOUT_FILENO, base, raw.count)
            }
        }
    }
}
