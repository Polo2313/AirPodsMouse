// Rejoue un enregistrement de capteurs (CSV) dans un PointerEngine : sert aux vérifications de non-régression
// et à régler le moteur sur de vrais mouvements. Colonnes attendues : t, [ts], phase, wx, wy, wz, gx, gy, gz.
import Foundation
import simd

public struct ReplayResult {
    /// Instants des clics (s depuis le début de l'enregistrement), rangés par phase de l'enregistrement.
    public var clicksByPhase: [String: [Double]] = [:]
    /// Déplacement total émis (px) par phase.
    public var pathByPhase: [String: Double] = [:]
}

public func replay(csv: String, engine startEngine: PointerEngine) -> ReplayResult {
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
    for (i, f) in rows.enumerated() where f.count == header.count {
        let t = cTs.flatMap { Double(f[$0]) } ?? (wallFirst + Double(i) * period)
        if t0 == nil { t0 = t }
        let phase = f[cPhase]
        let w = V3(Double(f[cwx]) ?? 0, Double(f[cwy]) ?? 0, Double(f[cwz]) ?? 0)
        let g = simd_normalize(V3(Double(f[cgx]) ?? 0, Double(f[cgy]) ?? 0, Double(f[cgz]) ?? -1))
        let dt = lastT.map { t - $0 } ?? 0.02
        lastT = t
        let o = engine.step(w: w, g: g, dt: dt, t: t)
        result.pathByPhase[phase, default: 0] += (o.dx * o.dx + o.dy * o.dy).squareRoot()
        if result.clicksByPhase[phase] == nil { result.clicksByPhase[phase] = [] }
        if o.click != nil { result.clicksByPhase[phase]!.append(t - t0!) }
    }
    return result
}
