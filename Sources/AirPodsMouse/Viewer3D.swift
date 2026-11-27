// Fenêtre 3D : affiche en temps réel l'orientation du boîtier.
import AppKit
import SceneKit
import simd
import Metal
import CoreMotion
import AirPodsMouseCore

final class Viewer3D: NSObject {
    let window: NSWindow
    let scnView = SCNView()
    let pivot = SCNNode()            // tourne avec le boîtier
    let caseMaterial = SCNMaterial()
    let info = NSTextField(labelWithString: "")
    var q0: simd_quatd?              // orientation au moment du recentrage
    var basis = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)   // repère « boîtier » -> repère écouteur
    var needsRecenter = true
    var lastInfo = Date.distantPast

    var isVisible: Bool { window.isVisible }

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = String(localized: "AirPodsMouse — Vue 3D")
        window.isReleasedWhenClosed = false
        window.center()

        let content = NSView(frame: window.contentLayoutRect)
        scnView.frame = content.bounds
        scnView.autoresizingMask = [.width, .height]
        scnView.scene = buildScene()
        scnView.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1)
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = true     // glisser = tourner la caméra, molette = zoom
        content.addSubview(scnView)

        let legend = NSTextField(labelWithString: String(localized: "🔴 droite   🟢 haut   🔵 direction pointée   (axes fins = repère fixe)"))
        legend.textColor = .white
        legend.frame = NSRect(x: 12, y: content.bounds.height - 30, width: 600, height: 20)
        legend.autoresizingMask = [.minYMargin]
        content.addSubview(legend)

        info.textColor = NSColor(calibratedWhite: 0.85, alpha: 1)
        info.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        info.frame = NSRect(x: 12, y: 12, width: 480, height: 20)
        info.autoresizingMask = [.maxYMargin]
        content.addSubview(info)

        let button = NSButton(title: String(localized: "Recentrer"), target: self, action: #selector(recenter))
        button.bezelStyle = .rounded
        button.frame = NSRect(x: content.bounds.width - 120, y: 8, width: 110, height: 30)
        button.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(button)

        window.contentView = content
    }

    func show() {
        needsRecenter = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func recenter() { needsRecenter = true }

    // MARK: - Scène

    func buildScene() -> SCNScene {
        let scene = SCNScene()

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position = SCNVector3(3.0, 1.7, 1.2)
        camera.look(at: SCNVector3(0, 0.1, -0.4))
        scene.rootNode.addChildNode(camera)

        // Sol en grille
        let grid = SCNNode()
        for i in -5...5 {
            let t = CGFloat(i) * 0.4
            grid.addChildNode(line(from: SCNVector3(-2, 0, t), to: SCNVector3(2, 0, t)))
            grid.addChildNode(line(from: SCNVector3(t, 0, -2), to: SCNVector3(t, 0, 2)))
        }
        grid.position = SCNVector3(0, -0.9, 0)
        scene.rootNode.addChildNode(grid)

        // Repère fixe (fin, transparent)
        for (dir, color) in [(SIMD3<Float>(1, 0, 0), NSColor.systemRed),
                             (SIMD3<Float>(0, 1, 0), NSColor.systemGreen),
                             (SIMD3<Float>(0, 0, -1), NSColor.systemBlue)] {
            let a = arrow(dir, color: color.withAlphaComponent(0.3), length: 1.6, radius: 0.008)
            scene.rootNode.addChildNode(a)
        }

        // Boîtier
        caseMaterial.diffuse.contents = NSColor(calibratedWhite: 0.95, alpha: 1)
        caseMaterial.specular.contents = NSColor.white
        let box = SCNBox(width: 0.55, height: 0.24, length: 0.75, chamferRadius: 0.11)
        box.materials = [caseMaterial]
        pivot.addChildNode(SCNNode(geometry: box))
        // Petit repère à l'avant (direction pointée)
        let nose = SCNNode(geometry: SCNSphere(radius: 0.045))
        nose.geometry?.firstMaterial?.diffuse.contents = NSColor.systemBlue
        nose.position = SCNVector3(0, 0, -0.39)
        pivot.addChildNode(nose)
        // Axes du boîtier (épais)
        pivot.addChildNode(arrow([1, 0, 0], color: .systemRed, length: 0.9, radius: 0.022))
        pivot.addChildNode(arrow([0, 1, 0], color: .systemGreen, length: 0.9, radius: 0.022))
        pivot.addChildNode(arrow([0, 0, -1], color: .systemBlue, length: 1.2, radius: 0.022))
        scene.rootNode.addChildNode(pivot)
        return scene
    }

    func arrow(_ dir: SIMD3<Float>, color: NSColor, length: CGFloat, radius: CGFloat) -> SCNNode {
        let m = SCNMaterial(); m.diffuse.contents = color; m.lightingModel = .constant
        let shaft = SCNNode(geometry: SCNCylinder(radius: radius, height: length))
        shaft.geometry?.materials = [m]
        shaft.position = SCNVector3(0, length / 2, 0)
        let head = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: radius * 3, height: radius * 8))
        head.geometry?.materials = [m]
        head.position = SCNVector3(0, length + radius * 4, 0)
        let node = SCNNode()
        node.addChildNode(shaft); node.addChildNode(head)
        node.simdOrientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(dir))
        return node
    }

    func line(from a: SCNVector3, to b: SCNVector3) -> SCNNode {
        let src = SCNGeometrySource(vertices: [a, b])
        let el = SCNGeometryElement(indices: [Int32(0), 1], primitiveType: .line)
        let g = SCNGeometry(sources: [src], elements: [el])
        g.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.35, alpha: 1)
        g.firstMaterial?.lightingModel = .constant
        return SCNNode(geometry: g)
    }

    // MARK: - Mise à jour

    /// q : orientation des écouteurs · g : gravité (repère écouteur) · forward : direction pointée (repère écouteur)
    func update(q: simd_quatd, g: SIMD3<Double>, forward: SIMD3<Double>, yawRate: Double, pitchRate: Double) {
        guard window.isVisible, simd_length_squared(g) > 1e-9, q.length > 1e-9 else { return }
        let unitQ = q.normalized
        if needsRecenter || q0 == nil {
            needsRecenter = false
            q0 = unitQ
            // Repère « boîtier » : x = droite, y = haut, z = arrière, exprimé dans le repère écouteur
            let up = -simd_normalize(g)
            var fwd = forward - simd_dot(forward, up) * up
            if !(simd_length_squared(fwd) > 1e-6) {
                fwd = abs(up.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
                fwd -= simd_dot(fwd, up) * up
            }
            fwd = simd_normalize(fwd)
            let right = simd_cross(fwd, up)
            basis = simd_quatd(simd_double3x3(columns: (right, up, -fwd)))
        }
        guard let refQ = q0 else { return }
        // Rotation depuis le recentrage, exprimée dans le repère du boîtier
        let d = basis.inverse * (refQ.inverse * unitQ) * basis
        pivot.simdOrientation = simd_quatf(ix: Float(d.imag.x), iy: Float(d.imag.y), iz: Float(d.imag.z), r: Float(d.real))

        if Date().timeIntervalSince(lastInfo) > 0.1 {
            lastInfo = Date()
            info.stringValue = String(format: String(localized: "gauche/droite %+5.2f rad/s    haut/bas %+5.2f rad/s"), yawRate, pitchRate)
        }
    }

    /// Rend la scène dans un PNG (pour la doc), avec une pose de démonstration.
    func renderSnapshot(to path: String) {
        pivot.simdOrientation = simd_quatf(angle: 0.45, axis: [0, 1, 0]) * simd_quatf(angle: 0.3, axis: [1, 0, 0])
            * simd_quatf(angle: -0.2, axis: [0, 0, 1])
        let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        r.scene = scnView.scene
        r.autoenablesDefaultLighting = true
        r.scene?.background.contents = NSColor(calibratedWhite: 0.11, alpha: 1)
        let img = r.snapshot(atTime: 0, with: CGSize(width: 1280, height: 900), antialiasingMode: .multisampling4X)
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { print("snapshot failed"); return }
        try? png.write(to: URL(fileURLWithPath: path))
        print("snapshot -> \(path)")
    }

    func flash(_ color: NSColor) {
        caseMaterial.diffuse.contents = color
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.caseMaterial.diffuse.contents = NSColor(calibratedWhite: 0.95, alpha: 1)
        }
    }
}

extension Viewer3D {
    /// Met à jour la vue depuis une mesure brute des capteurs.
    func update(motion m: CMDeviceMotion, engine: PointerEngine) {
        let rawG = V3(m.gravity.x, m.gravity.y, m.gravity.z)
        guard simd_length_squared(rawG) > 1e-9 else { return }
        let w = V3(m.rotationRate.x, m.rotationRate.y, m.rotationRate.z)
        let g = simd_normalize(rawG)
        guard let ax = engine.axes(g: g) else { return }
        let r = engine.rates(w: w, g: g)
        let q = m.attitude.quaternion
        update(q: simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w), g: g, forward: ax.forward, yawRate: r.yaw, pitchRate: r.pitch)
    }
}
