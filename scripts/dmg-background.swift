// Fond de la fenêtre du .dmg (640×400, @2x) : titre, flèche de l'appli vers Applications, aide en bas.
// Usage : swift scripts/dmg-background.swift sortie.png
import AppKit

let W: CGFloat = 640, H: CGFloat = 400, scale: CGFloat = 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)   // 144 dpi → Finder l'affiche net sur écran Retina
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Dégradé très doux
NSGradient(colors: [NSColor(srgbRed: 0.96, green: 0.97, blue: 1.0, alpha: 1),
                    NSColor(srgbRed: 0.90, green: 0.92, blue: 0.99, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                            .foregroundColor: color, .paragraphStyle: p]
    (s as NSString).draw(in: NSRect(x: 20, y: y, width: W - 40, height: size * 1.5), withAttributes: a)
}
let ink = NSColor(srgbRed: 0.13, green: 0.14, blue: 0.22, alpha: 1)
text("Installer AirPodsMouse", size: 24, weight: .bold, color: ink, y: H - 66)
text("Glisse l'icône dans le dossier Applications", size: 14, weight: .regular, color: ink.withAlphaComponent(0.65), y: H - 92)

// Flèche entre les deux icônes (icônes du Finder centrées en x=170 et x=470, y=175 depuis le haut)
let brand = NSColor(srgbRed: 0.32, green: 0.42, blue: 0.98, alpha: 1)
let y = H - 175
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 262, y: y)); arrow.line(to: NSPoint(x: 368, y: y))
arrow.lineWidth = 6; arrow.lineCapStyle = .round
brand.setStroke(); arrow.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 384, y: y)); head.line(to: NSPoint(x: 360, y: y + 15)); head.line(to: NSPoint(x: 360, y: y - 15)); head.close()
brand.setFill(); head.fill()


NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("OK → \(out)")
