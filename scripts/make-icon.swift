// Dessine l'icône d'AirPodsMouse et produit Resources/AppIcon.icns (via iconutil).
// Usage : swift scripts/make-icon.swift [sortie.png pour aperçu]
import AppKit

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024

    // Fond : « squircle » macOS (marge 100 px sur 1024), dégradé bleu → indigo, légère ombre
    let rect = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24 * s; shadow.shadowOffset = NSSize(width: 0, height: -10 * s); shadow.set()
    NSColor.black.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(srgbRed: 0.24, green: 0.56, blue: 1.0, alpha: 1),
                        NSColor(srgbRed: 0.36, green: 0.27, blue: 0.93, alpha: 1)])!
        .draw(in: shape, angle: -60)
    // Reflet doux en haut
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [.white.withAlphaComponent(0.22), .white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // AirPods (symbole système) en blanc
    func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, in r: NSRect, color: NSColor) {
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(.init(paletteColors: [color]))
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
        let ratio = min(r.width / img.size.width, r.height / img.size.height)
        let sz = NSSize(width: img.size.width * ratio, height: img.size.height * ratio)
        img.draw(in: NSRect(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2, width: sz.width, height: sz.height))
    }
    symbol("airpodspro", pointSize: 400, weight: .regular,
           in: NSRect(x: 150 * s, y: 350 * s, width: 540 * s, height: 450 * s), color: .white)

    // Flèche de curseur, en bas à droite, avec contour sombre pour la lisibilité
    let arrow = NSBezierPath()
    let a: [(CGFloat, CGFloat)] = [(0, 0), (0, -250), (62, -192), (110, -300), (160, -278), (112, -172), (195, -172)]
    let origin = NSPoint(x: 600 * s, y: 470 * s)
    for (i, p) in a.enumerated() {
        let pt = NSPoint(x: origin.x + p.0 * s, y: origin.y + p.1 * s)
        i == 0 ? arrow.move(to: pt) : arrow.line(to: pt)
    }
    arrow.close()
    arrow.lineJoinStyle = .round
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = .black.withAlphaComponent(0.35); sh.shadowBlurRadius = 14 * s
    sh.shadowOffset = NSSize(width: 0, height: -6 * s); sh.set()
    NSColor.white.setFill(); arrow.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(srgbRed: 0.12, green: 0.12, blue: 0.2, alpha: 1).setStroke()
    arrow.lineWidth = 16 * s; arrow.stroke()
    NSColor.white.setFill(); arrow.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(base * scale).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
if CommandLine.arguments.count > 1 {
    try! render(1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "OK → \(out.path)" : "iconutil a échoué")
