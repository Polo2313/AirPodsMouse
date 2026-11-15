// Rejoue un enregistrement de capteurs (CSV) dans un PointerEngine : sert aux vérifications de non-régression
// et à régler le moteur sur de vrais mouvements. Colonnes attendues : t, [ts], phase, wx, wy, wz, gx, gy, gz.
import CoreGraphics
import Foundation
import simd

public struct ReplayResult {
    /// Instants des clics (s depuis le début de l'enregistrement), rangés par phase de l'enregistrement.
    public var clicksByPhase: [String: [Double]] = [:]
    /// Déplacement total émis (px) par phase.
    public var pathByPhase: [String: Double] = [:]
    /// Part du temps où le curseur simulé est collé au bord haut ou bas (avec `screen` seulement).
    public var verticalEdgeFraction = 0.0
}

/// - Parameter screen: si fourni, simule un curseur bloqué aux bords de cet écran et le transmet au moteur.
public func replay(csv: String, engine startEngine: PointerEngine, screen: CGRect? = nil) -> ReplayResult {
    var engine = startEngine
    var result = ReplayResult()
    var lines = csv.split(whereSeparator: \.isNewline).map(String.init)
    guard lines.count > 2 else { return result }
    let header = lines.removeFirst().split(separator: ",").map(String.init)
    func col(_ n: String) -> Int? { header.firstIndex(of: n) }
    guard let cT = col("t"), let cPhase = col("phase"), let cwx = col("wx"), let cwy = col("wy"), let cwz = col("wz"),
          let cgx = col("gx"), let cgy = col("gy"), let cgz = col("gz") else { return result }
    let cTs = col("ts")

    // Sans horloge du capteur (colonne « ts »), les mesures arrivées par paquets Bluetooth ont des heures
    // d'arrivée faussées : on reconstitue un espacement régulier.
    let rows = lines.map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
    let wallFirst = Double(rows.first![cT]) ?? 0, wallLast = Double(rows.last![cT]) ?? 0
    let period = (wallLast - wallFirst) / Double(max(rows.count - 1, 1))

    var lastT: Double?
    var t0: Double?
    var cursor = screen.map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero
    var samples = 0.0, atVerticalEdge = 0.0
    for (i, f) in rows.enumerated() where f.count == header.count {
        let t = cTs.flatMap { Double(f[$0]) } ?? (wallFirst + Double(i) * period)
        if t0 == nil { t0 = t }
        let phase = f[cPhase]
        let w = V3(Double(f[cwx]) ?? 0, Double(f[cwy]) ?? 0, Double(f[cwz]) ?? 0)
        let g = simd_normalize(V3(Double(f[cgx]) ?? 0, Double(f[cgy]) ?? 0, Double(f[cgz]) ?? -1))
        let dt = lastT.map { t - $0 } ?? 0.02
        lastT = t
        let o = engine.step(w: w, g: g, dt: dt, t: t, screen: screen.map { ScreenContext(cursor: cursor, bounds: $0) })
        if let s = screen {
            cursor = CGPoint(x: min(max(cursor.x + o.dx, s.minX), s.maxX - 1), y: min(max(cursor.y + o.dy, s.minY), s.maxY - 1))
            samples += 1
            if cursor.y <= s.minY + 0.5 || cursor.y >= s.maxY - 1.5 { atVerticalEdge += 1 }
        }
        result.pathByPhase[phase, default: 0] += (o.dx * o.dx + o.dy * o.dy).squareRoot()
        if result.clicksByPhase[phase] == nil { result.clicksByPhase[phase] = [] }
        if o.click != nil { result.clicksByPhase[phase]!.append(t - t0!) }
    }
    result.verticalEdgeFraction = samples > 0 ? atVerticalEdge / samples : 0
    return result
}

/// Compte les gestes « non » détectés dans un enregistrement (doit être 0 sur des mouvements normaux).
public func replayShakes(csv: String) -> Int {
    let engine = PointerEngine()
    var detector = ShakeDetector()
    var lines = csv.split(whereSeparator: \.isNewline).map(String.init)
    guard lines.count > 2 else { return 0 }
    let header = lines.removeFirst().split(separator: ",").map(String.init)
    func col(_ n: String) -> Int? { header.firstIndex(of: n) }
    guard let cT = col("t"), let cwx = col("wx"), let cwy = col("wy"), let cwz = col("wz"),
          let cgx = col("gx"), let cgy = col("gy"), let cgz = col("gz") else { return 0 }
    let rows = lines.map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
    let first = Double(rows.first![cT]) ?? 0, last = Double(rows.last![cT]) ?? 0
    let period = (last - first) / Double(max(rows.count - 1, 1))
    var n = 0, lastT: Double?
    for (i, f) in rows.enumerated() where f.count == header.count {
        let t = col("ts").flatMap { Double(f[$0]) } ?? (first + Double(i) * period)
        let dt = min(max(lastT.map { t - $0 } ?? 0.02, 0.001), 0.1); lastT = t
        let w = V3(Double(f[cwx]) ?? 0, Double(f[cwy]) ?? 0, Double(f[cwz]) ?? 0)
        let g = simd_normalize(V3(Double(f[cgx]) ?? 0, Double(f[cgy]) ?? 0, Double(f[cgz]) ?? -1))
        let r = engine.rates(w: w, g: g)
        if detector.update(yawRate: r.yaw, pitchRate: r.pitch, t: t, dt: dt) { n += 1 }
    }
    return n
}
