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

private struct ReplaySample {
    let t: Double
    let phase: String
    let w: V3
    let g: V3
}

private func parseSamples(_ csv: String, requirePhase: Bool) -> [ReplaySample] {
    var lines = csv.split(whereSeparator: \.isNewline).map(String.init)
    guard lines.count > 2 else { return [] }
    let header = lines.removeFirst().split(separator: ",").map(String.init)
    func col(_ n: String) -> Int? { header.firstIndex(of: n) }
    guard let cT = col("t"), let cwx = col("wx"), let cwy = col("wy"), let cwz = col("wz"),
          let cgx = col("gx"), let cgy = col("gy"), let cgz = col("gz") else { return [] }
    let cPhase = col("phase")
    if requirePhase && cPhase == nil { return [] }
    let cTs = col("ts")

    // Filtre d'abord les lignes complètes (évite un crash ou une période négative si la dernière ligne est tronquée)
    let rows = lines
        .map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        .filter { $0.count == header.count }
    guard let firstRow = rows.first, let lastRow = rows.last else { return [] }
    let wallFirst = Double(firstRow[cT]) ?? 0, wallLast = Double(lastRow[cT]) ?? 0
    let rawPeriod = (wallLast - wallFirst) / Double(max(rows.count - 1, 1))
    let period = rawPeriod > 0 ? rawPeriod : 0.02

    return rows.enumerated().map { i, f in
        let t = cTs.flatMap { Double(f[$0]) } ?? (wallFirst + Double(i) * period)
        let phase = cPhase.map { f[$0] } ?? ""
        let w = V3(Double(f[cwx]) ?? 0, Double(f[cwy]) ?? 0, Double(f[cwz]) ?? 0)
        let rawG = V3(Double(f[cgx]) ?? 0, Double(f[cgy]) ?? 0, Double(f[cgz]) ?? -1)
        let g = simd_length_squared(rawG) > 1e-12 ? simd_normalize(rawG) : V3(0, 0, -1)
        return ReplaySample(t: t, phase: phase, w: w, g: g)
    }
}

/// - Parameter screen: si fourni, simule un curseur bloqué aux bords de cet écran et le transmet au moteur.
public func replay(csv: String, engine startEngine: PointerEngine, screen: CGRect? = nil) -> ReplayResult {
    let parsed = parseSamples(csv, requirePhase: true)
    guard let first = parsed.first else { return ReplayResult() }
    var engine = startEngine
    var result = ReplayResult()
    let t0 = first.t
    var lastT: Double?
    var cursor = screen.map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero
    var samples = 0.0, atVerticalEdge = 0.0
    for s in parsed {
        let dt = lastT.map { s.t - $0 } ?? 0.02
        lastT = s.t
        let o = engine.step(w: s.w, g: s.g, dt: dt, t: s.t, screen: screen.map { ScreenContext(cursor: cursor, bounds: $0) })
        if let scr = screen {
            cursor = CGPoint(x: min(max(cursor.x + o.dx, scr.minX), scr.maxX - 1),
                             y: min(max(cursor.y + o.dy, scr.minY), scr.maxY - 1))
            samples += 1
            if cursor.y <= scr.minY + 0.5 || cursor.y >= scr.maxY - 1.5 { atVerticalEdge += 1 }
        }
        result.pathByPhase[s.phase, default: 0] += (o.dx * o.dx + o.dy * o.dy).squareRoot()
        if result.clicksByPhase[s.phase] == nil { result.clicksByPhase[s.phase] = [] }
        if o.click != nil { result.clicksByPhase[s.phase]!.append(s.t - t0) }
    }
    result.verticalEdgeFraction = samples > 0 ? atVerticalEdge / samples : 0
    return result
}

/// Compte les gestes « non » détectés dans un enregistrement (doit être 0 sur des mouvements normaux).
public func replayShakes(csv: String) -> Int {
    let parsed = parseSamples(csv, requirePhase: false)
    guard !parsed.isEmpty else { return 0 }
    let engine = PointerEngine()
    var detector = ShakeDetector()
    var n = 0, lastT: Double?
    for s in parsed {
        let dt = min(max(lastT.map { s.t - $0 } ?? 0.02, 0.001), 0.1)
        lastT = s.t
        let r = engine.rates(w: s.w, g: s.g)
        if detector.update(yawRate: r.yaw, pitchRate: r.pitch, t: s.t, dt: dt) { n += 1 }
    }
    return n
}
