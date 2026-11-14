import Foundation

/// Journal lisible par l'utilisateur : ~/Library/Logs/AirPodsMouse.log (Réglages › À propos › Journal).
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AirPodsMouse.log")
    private static let handle: FileHandle? = {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try? FileHandle(forWritingTo: url)
    }()
    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()

    static func line(_ s: String) {
        let data = "[\(time.string(from: Date()))] \(s)\n".data(using: .utf8)!
        handle?.write(data)
        FileHandle.standardOutput.write(data)
    }
}
