// Moteur de pointage : transforme les rotations des AirPods en déplacements du curseur et en clics.
// Indépendant de l'interface (testable en rejouant un enregistrement : voir tools/replay.swift).
import Foundation
import simd

public typealias V3 = SIMD3<Double>

/// Filtre « 1 € » (Casiez et al.) : très lisse quand on bouge lentement (supprime le tremblement
/// naturel de la tête), réactif quand on bouge vite (pas de retard).
public struct OneEuroFilter {
    public var minCutoff: Double
    public var beta: Double
    public var dCutoff: Double = 1.0
    private(set) var value: Double?
    private var dx = 0.0

    public init(minCutoff: Double, beta: Double) { self.minCutoff = minCutoff; self.beta = beta }

    private func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    public mutating func filter(_ x: Double, dt: Double) -> Double {
        guard let prev = value else { value = x; return x }
        dx += alpha(dCutoff, dt) * ((x - prev) / dt - dx)
        let v = prev + alpha(minCutoff + beta * abs(dx), dt) * (x - prev)
        value = v
        return v
    }

    public mutating func reset(to x: Double) { value = x; dx = 0 }
}

public func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

public enum ClickKind: Sendable { case left, right }

/// Geste « aller-retour » rapide autour d'un axe (hochement de tête, inclinaison vers l'épaule).
/// Pendant un geste candidat, le curseur est retenu ; si ce n'était pas un clic, le mouvement retenu est rendu.
/// Un clic = un aller-retour rapide et court qui revient au point de départ, dans un sens ou dans l'autre.
/// Seuils mesurés sur de vrais enregistrements :
///   hochement de clic : 9-13°, aller-retour ≈ 0,55 s · regard haut/bas : 16-24°, 0,7-1 s · visée : 5-9° sans retour.
public struct FlickDetector {
    public var threshold: Double          // rad/s : vitesse à partir de laquelle un geste est candidat
    public var dominance: Double          // la rotation du geste doit dominer les autres axes
    public var minAngle = 0.05            // rad (~3°) : en dessous, c'est un tressaillement
    public var maxAngle = 0.3             // rad (~17°) : au-delà, c'est un vrai regard, pas un clic
    public var maxOutbound = 0.45         // s : l'aller doit se retourner dans ce délai
    public var maxTotal = 0.5            // s : aller-retour complet (clics mesurés 0,22-0,38 s ; regards 0,7-1 s)
    public var returnFraction = 0.4       // le retour doit ramener à moins de 40 % de l'aller
    private(set) var start: Double?
    private var sign = 0.0
    private var returning = false
    private var excursion = 0.0
    private var angle = 0.0        // angle depuis le début du mouvement (avant même le seuil)
    private var onsetAngle = 0.0   // angle accumulé avant le franchissement du seuil
    private var peak = 0.0, otherPeak = 0.0
    private var stillSince: Double?
    private var waitStill = false
    private var cooldownUntil = -1.0
    #if DEBUG_GESTURES
    private var onsetStart = 0.0
    #endif

    public init(threshold: Double, dominance: Double) { self.threshold = threshold; self.dominance = dominance }

    public enum Result { case none, candidate, timeout, fired, cooldown }

    /// `r` = vitesse sur l'axe du geste, `other` = plus grande vitesse sur les autres axes.
    public mutating func update(_ r: Double, other: Double, t: Double, dt: Double) -> Result {
        if t < cooldownUntil { return .cooldown }        // on laisse la tête revenir sans bouger le curseur
        guard let s = start else {
            // Après un rejet (grand regard, visée), on attend que la tête se pose : sinon le rebond
            // d'un grand mouvement ressemble à un hochement.
            if waitStill {
                if abs(r) < 0.15 {
                    if stillSince == nil { stillSince = t }
                    if t - stillSince! > 0.12 { waitStill = false; stillSince = nil }
                } else { stillSince = nil }
                onsetAngle = 0
                return .none
            }
            // Mesure le début du mouvement, avant le seuil, pour avoir l'amplitude réelle
            if abs(r) < 0.15 { onsetAngle = 0 } else { onsetAngle += r * dt }
            if abs(r) > threshold && abs(r) > abs(other) * dominance {
                start = t; sign = r < 0 ? -1 : 1; returning = false; stillSince = nil
                angle = onsetAngle; excursion = abs(angle); peak = abs(r); otherPeak = abs(other)
                #if DEBUG_GESTURES
                onsetStart = onsetAngle
                #endif
                return .candidate
            }
            return .none
        }
        angle += r * dt
        let rel = angle * sign                            // > 0 dans le sens de l'aller
        excursion = max(excursion, rel)
        peak = max(peak, abs(r)); otherPeak = max(otherPeak, abs(other))
        let reject: Bool = {
            if excursion > maxAngle { return true }                         // trop grand : vrai regard
            if t - s > maxTotal { return true }                             // trop lent
            if !returning {
                if r * sign < -threshold * 0.6 { returning = true; return false }
                if t - s > maxOutbound { return true }
                // Arrêté sans revenir = visée. (Au point de retournement d'un hochement la vitesse passe
                // aussi par zéro, mais seulement un instant.)
                if abs(r) < 0.12 {
                    if stillSince == nil { stillSince = t }
                    if t - stillSince! > 0.15 { return true }
                } else { stillSince = nil }
            } else if rel < -excursion * 0.8 { return true }                // repart loin de l'autre côté
            return false
        }()
        if reject {
            #if DEBUG_GESTURES
            print(String(format: "  rejet t=%.2f exc=%.1f° rel=%.1f° durée=%.2f retour=%@ r=%.2f", t, excursion * 57.3, rel * 57.3, t - s, returning ? "oui" : "non", r))
            #endif
            start = nil; onsetAngle = 0; waitStill = true; stillSince = nil; return .timeout
        }
        if returning && rel < excursion * returnFraction {
            start = nil; onsetAngle = 0
            guard excursion >= minAngle, peak > otherPeak * dominance else { return .timeout }
            #if DEBUG_GESTURES
            print(String(format: "  CLIC  t=%.2f exc=%.1f° rel=%.1f° durée=%.2f pic=%.2f autres=%.2f début=%.1f°", t, excursion * 57.3, rel * 57.3, t - s, peak, otherPeak, onsetStart * 57.3))
            #endif
            cooldownUntil = t + 0.2
            return .fired
        }
        return .candidate
    }
}

public struct PointerOutput {
    public var dx = 0.0, dy = 0.0          // pixels
    public var click: ClickKind?
    public init() {}
}

public struct PointerEngine {
    public init() {}
    // Réglages
    public var sensitivity = 1.0
    public var verticalRatio = 2.4          // on bouge moins la tête en vertical qu'en horizontal (mesuré : ~7° contre ~11°)
    public var gainSlow = 1400.0            // px par radian quand on vise finement (1° ≈ 24 px)
    public var gainFast = 4200.0            // px par radian pour les grands déplacements (1° ≈ 73 px)
    public var speedSlow = 0.15, speedFast = 1.0   // rad/s : transition entre précision et vitesse
    public var noiseFloor = 0.015, noiseFull = 0.05 // rad/s : en dessous, c'est du bruit
    public var invertX = false, invertY = false
    public var nodClick = true
    public var nodPreset: NodPreset = .normal {
        didSet { nod.threshold = nodPreset.threshold; nod.maxTotal = nodPreset.maxTotal }
    }
    public var tiltClick = false
    public var axis: V3?                    // axe haut/bas calibré (repère écouteur), sinon axe par défaut

    // État
    private var yawAngle = 0.0, pitchAngle = 0.0
    private var fYaw = OneEuroFilter(minCutoff: 0.8, beta: 6)
    private var fPitch = OneEuroFilter(minCutoff: 0.8, beta: 6)
    private var lastYaw: Double?, lastPitch: Double?
    private var nod = FlickDetector(threshold: 0.65, dominance: 1.3)
    private var tilt = FlickDetector(threshold: 1.0, dominance: 1.5)
    private var heldX = 0.0, heldY = 0.0
    private var recent: [(t: Double, dx: Double, dy: Double)] = []   // derniers déplacements émis
    private var gestureStart: Double?

    public static func defaultAxis(_ g: V3) -> V3 { abs(g.x) < 0.7 ? V3(1, 0, 0) : V3(0, 1, 0) }

    /// Axes horizontaux dans le repère écouteur : `side` (axe du hochement), `forward` (direction du regard).
    public func axes(g: V3) -> (side: V3, forward: V3)? {
        var a = axis ?? Self.defaultAxis(g)
        a -= simd_dot(a, g) * g
        if simd_length(a) < 0.2 {
            a = Self.defaultAxis(g); a -= simd_dot(a, g) * g
            if simd_length(a) < 0.2 { return nil }
        }
        let side = simd_normalize(a)
        return (side, simd_normalize(simd_cross(side, g)))
    }

    /// Décompose une rotation : lacet (+ = vers la gauche), tangage (+ = vers le haut), roulis.
    public func rates(w: V3, g: V3) -> (yaw: Double, pitch: Double, roll: Double) {
        let yaw = -simd_dot(w, g)
        guard let (side, fwd) = axes(g: g) else { return (yaw, 0, 0) }
        return (yaw, simd_dot(w, side), simd_dot(w, fwd))
    }

    public mutating func reset() {
        lastYaw = nil; lastPitch = nil; heldX = 0; heldY = 0
    }

    public mutating func step(w: V3, g: V3, dt rawDt: Double, t: Double) -> PointerOutput {
        var out = PointerOutput()
        let gap = rawDt > 0.15
        let dt = min(max(rawDt, 0.001), 0.1)
        let r = rates(w: w, g: g)

        yawAngle += r.yaw * dt
        pitchAngle += r.pitch * dt
        if gap { fYaw.reset(to: yawAngle); fPitch.reset(to: pitchAngle); lastYaw = nil }
        let fy = fYaw.filter(yawAngle, dt: dt)
        let fp = fPitch.filter(pitchAngle, dt: dt)
        defer { lastYaw = fy; lastPitch = fp }
        guard let ly = lastYaw, let lp = lastPitch else { return out }

        let dYaw = fy - ly, dPitch = fp - lp
        let speed = (dYaw * dYaw + dPitch * dPitch).squareRoot() / dt
        let gain = (gainSlow + (gainFast - gainSlow) * smoothstep(speedSlow, speedFast, speed))
            * smoothstep(noiseFloor, noiseFull, speed) * sensitivity
        var dx = -dYaw * gain * (invertX ? -1 : 1)
        var dy = -dPitch * gain * verticalRatio * (invertY ? -1 : 1)

        // Gestes : pendant un geste candidat, on retient le mouvement
        var holding = false, discard = false
        func apply(_ res: FlickDetector.Result, _ kind: ClickKind) {
            switch res {
            case .fired: out.click = kind; discard = true
            case .cooldown: discard = true
            case .candidate: holding = true
            case .timeout: dx += heldX; dy += heldY; heldX = 0; heldY = 0
            case .none: break
            }
        }
        if nodClick { apply(nod.update(r.pitch, other: max(abs(r.yaw), abs(r.roll)), t: t, dt: dt), .left) }
        if tiltClick && out.click == nil && nod.start == nil {
            apply(tilt.update(r.roll, other: max(abs(r.yaw), abs(r.pitch)), t: t, dt: dt), .right)
        }
        recent.removeAll { t - $0.t > 1.0 }
        if holding { if gestureStart == nil { gestureStart = t } } else if out.click == nil { gestureStart = nil }
        if out.click != nil {
            // Annule le petit glissement au tout début du geste : le clic tombe là où on visait
            let since = (gestureStart ?? t) - 0.2
            for d in recent where d.t >= since { out.dx -= d.dx; out.dy -= d.dy }
            recent.removeAll()
            gestureStart = nil
        }
        if discard { heldX = 0; heldY = 0; return out }
        if holding { heldX += dx; heldY += dy; return out }
        out.dx = dx; out.dy = dy
        recent.append((t, dx, dy))
        return out
    }
}
