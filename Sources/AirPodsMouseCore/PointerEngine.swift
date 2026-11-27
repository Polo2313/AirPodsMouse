// Moteur de pointage : transforme les rotations des AirPods en déplacements du curseur et en clics.
// Indépendant de l'interface (testable en rejouant un enregistrement : voir tools/replay.swift).
import CoreGraphics
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

/// Où se trouve le curseur, et l'écran qui le contient (coordonnées écran, origine en haut à gauche).
public struct ScreenContext {
    public var cursor: CGPoint
    public var bounds: CGRect
    public init(cursor: CGPoint, bounds: CGRect) { self.cursor = cursor; self.bounds = bounds }
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
    /// Mémoire des 4 bords : quand le curseur touche un bord et que la tête continue de tourner au-delà,
    /// il attend que la tête revienne réellement au bord avant de repartir dans l'autre sens.
    public var edgeMemory = true
    public var maxEdgeOvershoot = 460.0     // px (~16° hors écran max : évite de bloquer si on se tourne complètement)
    /// Garde « en face de l'écran = curseur au centre » (réalignement, rattrapage vitesse rapide/lente, zéro dérive).
    public var alignment = true
    /// Alignement vertical désactivé : on ne bouge la tête que de ±6° pour couvrir l'écran en hauteur, mais bien plus
    /// pour regarder le clavier, et l'angle vertical dérive (+4° mesurés rien qu'en hochant la tête). Aligné, le curseur
    /// restait collé en haut ou en bas (28 % du temps au rejeu contre 14 %). L'horizontal suffit au besoin exprimé.
    public var alignVertical = false
    public var alignGain = 2600.0           // px par radian de la correspondance tête ↔ écran (× sensibilité)
    public var alignStrength = 0.08         // part de l'écart corrigée à chaque mesure, mouvements rapides seulement
    public var alignSpeedLow = 0.3, alignSpeedHigh = 1.0   // rad/s : pas de correction en visée fine
    public var referenceTimeConstant = 120.0 // s : le « en face » suit lentement la position habituelle de la tête
    public var catchUpFrom = 60.0, catchUpFull = 200.0   // px d'écart : rattrapage dans le sens du mouvement
    public var catchUpRate = 0.06           // part de l'écart rattrapée par mesure (≈ 50/s)
    public var catchUpMaxFactor = 2.0       // le rattrapage n'ajoute jamais plus de 2× le mouvement de la tête

    // État
    private var yawAngle = 0.0, pitchAngle = 0.0
    private var yawBias = 0.0, pitchBias = 0.0      // dérive à vide du gyroscope apprise quand la tête est immobile
    private var fYaw = OneEuroFilter(minCutoff: 0.8, beta: 6)
    private var fPitch = OneEuroFilter(minCutoff: 0.8, beta: 6)
    private var lastYaw: Double?, lastPitch: Double?
    private var nod = FlickDetector(threshold: 0.65, dominance: 1.3)
    private var tilt = FlickDetector(threshold: 1.0, dominance: 1.5)
    private var heldX = 0.0, heldY = 0.0
    private var recent: [(t: Double, dx: Double, dy: Double)] = []   // derniers déplacements émis
    private var gestureStart: Double?
    private var refYaw: Double?, refPitch: Double?   // direction « en face » (correspond au centre de l'écran)
    private var overshootX = 0.0, overshootY = 0.0   // dépassement virtuel (px) au-delà des bords de l'écran

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
        overshootX = 0; overshootY = 0
    }

    /// Appelé après un déplacement au vrai trackpad : adopte la nouvelle position du curseur sans tirer en arrière.
    public mutating func reanchorAfterExternalMove() {
        reset()
        refYaw = nil; refPitch = nil
    }

    /// Remet la référence « en face » sur la direction actuelle de la tête ; l'appelant place le curseur au centre.
    public mutating func recenter() {
        refYaw = lastYaw; refPitch = lastPitch
        overshootX = 0; overshootY = 0
    }

    /// Direction filtrée de la tête (rad) : lacet (+ = gauche), tangage (+ = haut). Nil avant la première mesure.
    public var headAngles: (yaw: Double, pitch: Double)? {
        guard let y = lastYaw, let p = lastPitch else { return nil }
        return (y, p)
    }

    /// Position où le curseur devrait être d'après la direction de la tête (en face = centre de `bounds`).
    public func idealPosition(in bounds: CGRect) -> CGPoint? {
        guard let y = lastYaw, let p = lastPitch else { return nil }
        return ideal(yaw: y, pitch: p, bounds: bounds)
    }

    private func ideal(yaw: Double, pitch: Double, bounds: CGRect) -> CGPoint? {
        guard let ry = refYaw, let rp = refPitch else { return nil }
        let k = alignGain * sensitivity
        return CGPoint(x: bounds.midX - (yaw - ry) * k * (invertX ? -1 : 1),
                       y: bounds.midY - (pitch - rp) * k * verticalRatio * (invertY ? -1 : 1))
    }

    /// Mémoire des bords, réalignement pendant les mouvements rapides, et « en face » recalibré en continu.
    private mutating func align(dx: inout Double, dy: inout Double, yaw fy: Double, pitch fp: Double,
                                speed: Double, dt: Double, screen sc: ScreenContext) {
        let b = sc.bounds, c = sc.cursor
        let k = alignGain * sensitivity
        if refYaw == nil || refPitch == nil {
            // Première mesure : la référence est choisie pour que la position idéale soit le curseur actuel (pas de saut)
            refYaw = fy + (c.x - b.midX) / k * (invertX ? -1 : 1)
            refPitch = fp + (c.y - b.midY) / (k * verticalRatio) * (invertY ? -1 : 1)
        }
        guard let target = ideal(yaw: fy, pitch: fp, bounds: b) else { return }
        let atLeft = c.x <= b.minX + 0.5, atRight = c.x >= b.maxX - 1.5
        let atTop = c.y <= b.minY + 0.5, atBottom = c.y >= b.maxY - 1.5

        // Mémoire des bords : la tête a dépassé le bord → le curseur n'en repart que quand elle y est revenue
        if atLeft && target.x < b.minX && dx > 0 { dx = 0 }
        if atRight && target.x > b.maxX - 1 && dx < 0 { dx = 0 }
        if alignVertical && atTop && target.y < b.minY && dy > 0 { dy = 0 }
        if alignVertical && atBottom && target.y > b.maxY - 1 && dy < 0 { dy = 0 }

        // Réalignement, seulement pendant les mouvements rapides (invisible), jamais en visée fine
        let w = smoothstep(alignSpeedLow, alignSpeedHigh, speed) * alignStrength
        if w > 0 {
            let tx = min(max(target.x, b.minX), b.maxX - 1), ty = min(max(target.y, b.minY), b.maxY - 1)
            dx += (tx - (c.x + dx)) * w
            if alignVertical { dy += (ty - (c.y + dy)) * w }
        }

        // Rattrapage : quand le curseur est loin de sa position idéale et qu'on bouge vers elle, il avance un peu
        // plus vite (jamais à contre-sens, jamais à l'arrêt, rien quand l'écart est petit = visée fine).
        func catchUp(_ d: Double, _ err: Double) -> Double {
            guard d != 0, (d > 0) == (err > 0) else { return d }
            let extra = err * catchUpRate * smoothstep(catchUpFrom, catchUpFull, abs(err))
            return d + (extra > 0 ? min(extra, abs(d) * catchUpMaxFactor) : max(extra, -abs(d) * catchUpMaxFactor))
        }
        dx = catchUp(dx, target.x - (c.x + dx))
        if alignVertical { dy = catchUp(dy, target.y - (c.y + dy)) }

        // « En face » recalibré : la référence suit lentement la direction habituelle de la tête
        if !(atLeft || atRight || (alignVertical && (atTop || atBottom))), let ry = refYaw, let rp = refPitch {
            let a = min(dt / referenceTimeConstant, 1)
            refYaw = ry + (fy - ry) * a
            refPitch = rp + (fp - rp) * a
        }
    }

    /// Absorbe le dépassement de la tête au-delà des 4 bords de l'écran (fonctionne même sans `alignment`).
    private mutating func applyEdgeMemory(dx: inout Double, dy: inout Double, dt: Double, screen sc: ScreenContext) {
        let b = sc.bounds, c = sc.cursor
        let cap = maxEdgeOvershoot * sensitivity

        // Axe horizontal (bords gauche et droit)
        let nextX = c.x + dx
        if overshootX < 0 {
            overshootX = max(-cap, overshootX + dx)
            if overshootX > 0 { dx = overshootX; overshootX = 0 } else { dx = 0 }
        } else if overshootX > 0 {
            overshootX = min(cap, overshootX + dx)
            if overshootX < 0 { dx = overshootX; overshootX = 0 } else { dx = 0 }
        } else if nextX < b.minX {
            overshootX = max(-cap, nextX - b.minX)
            dx = b.minX - c.x
        } else if nextX > b.maxX - 1 {
            overshootX = min(cap, nextX - (b.maxX - 1))
            dx = (b.maxX - 1) - c.x
        }

        // Axe vertical (bords haut et bas)
        let nextY = c.y + dy
        if overshootY < 0 {
            overshootY = max(-cap, overshootY + dy)
            if overshootY > 0 { dy = overshootY; overshootY = 0 } else { dy = 0 }
        } else if overshootY > 0 {
            overshootY = min(cap, overshootY + dy)
            if overshootY < 0 { dy = overshootY; overshootY = 0 } else { dy = 0 }
        } else if nextY < b.minY {
            overshootY = max(-cap, nextY - b.minY)
            dy = b.minY - c.y
        } else if nextY > b.maxY - 1 {
            overshootY = min(cap, nextY - (b.maxY - 1))
            dy = (b.maxY - 1) - c.y
        }

        // Si la tête reste immobile longtemps hors de l'écran, résorbe doucement le dépassement (τ ≈ 8 s)
        if abs(dx) < 0.05 && abs(dy) < 0.05 {
            let decay = max(0, 1 - dt / 8.0)
            overshootX *= decay
            overshootY *= decay
        }
    }

    public mutating func step(w: V3, g: V3, dt rawDt: Double, t: Double, screen: ScreenContext? = nil) -> PointerOutput {
        var out = PointerOutput()
        // En mode micro Bluetooth (HFP 24 kHz, ex. pendant que Librewispr écoute), les paquets arrivent
        // par salves espacées de ~0,16–0,24 s : on tolère jusqu'à 0,35 s sans jeter le mouvement.
        let gap = rawDt > 0.35
        let dt = min(max(rawDt, 0.001), 0.1)
        let rawR = rates(w: w, g: g)

        // Apprend et soustrait la dérive à vide du gyroscope quand la tête est au repos (< ~2°/s) :
        // élimine la dérive de ~1 400 px/min qui faussait l'alignement tête ↔ écran.
        let rawSpeed = hypot(rawR.yaw, rawR.pitch)
        if rawSpeed < 0.032 {
            let a = min(dt / 2.0, 0.15)
            yawBias = min(max(yawBias + (rawR.yaw - yawBias) * a, -0.025), 0.025)
            pitchBias = min(max(pitchBias + (rawR.pitch - pitchBias) * a, -0.025), 0.025)
        }
        let r = (yaw: rawR.yaw - yawBias, pitch: rawR.pitch - pitchBias, roll: rawR.roll)

        // N'intègre pas le bruit sous le seuil d'immobilité : l'angle de référence ne dérive plus jamais à l'arrêt !
        let quietGate = smoothstep(noiseFloor * 0.5, noiseFloor * 1.4, hypot(r.yaw, r.pitch))
        yawAngle += r.yaw * quietGate * dt
        pitchAngle += r.pitch * quietGate * dt
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
        if nodClick { apply(nod.update(rawR.pitch, other: max(abs(rawR.yaw), abs(rawR.roll)), t: t, dt: dt), .left) }
        if tiltClick && out.click == nil && nod.start == nil {
            apply(tilt.update(rawR.roll, other: max(abs(rawR.yaw), abs(rawR.pitch)), t: t, dt: dt), .right)
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
        if alignment, let sc = screen {
            align(dx: &dx, dy: &dy, yaw: fy, pitch: fp, speed: speed, dt: dt, screen: sc)
        }
        if edgeMemory, let sc = screen {
            // Si `alignment` gère déjà l'horizontal, `applyEdgeMemory` complète le vertical ; sinon il gère les 4 bords.
            if alignment {
                var zeroX = 0.0
                applyEdgeMemory(dx: &zeroX, dy: &dy, dt: dt, screen: sc)
                overshootX = 0
            } else {
                applyEdgeMemory(dx: &dx, dy: &dy, dt: dt, screen: sc)
            }
        } else {
            overshootX = 0; overshootY = 0
        }
        out.dx = dx; out.dy = dy
        recent.append((t, dx, dy))
        return out
    }
}
