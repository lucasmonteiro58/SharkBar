// Gera o ícone do app (1024×1024) em vetor. Uso: swift make_icon.swift saida.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let neon = NSColor(red: 0.27, green: 1.0, blue: 0.45, alpha: 1)
let neonDeep = NSColor(red: 0.0, green: 0.72, blue: 0.32, alpha: 1)

// Fundo: squircle do macOS (824 pt dentro de 1024, com sombra).
let inset: CGFloat = 100
let bgRect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor.black.withAlphaComponent(0.45).cgColor)
NSColor.black.setFill(); bg.fill()
ctx.restoreGState()
ctx.saveGState()
bg.addClip()
NSGradient(colors: [NSColor(red: 0.13, green: 0.15, blue: 0.17, alpha: 1),
                    NSColor(red: 0.04, green: 0.05, blue: 0.06, alpha: 1)])!.draw(in: bgRect, angle: -90)
// brilho verde difuso atrás
NSGradient(colors: [neon.withAlphaComponent(0.28), neon.withAlphaComponent(0)])!
    .draw(fromCenter: CGPoint(x: 512, y: 470), radius: 0, toCenter: CGPoint(x: 512, y: 470), radius: 420, options: [])
ctx.restoreGState()

// Fone: arco + conchas.
let band = NSBezierPath()
band.appendArc(withCenter: CGPoint(x: 470, y: 470), radius: 235, startAngle: 200, endAngle: -20, clockwise: true)
band.lineWidth = 46; band.lineCapStyle = .round
NSColor(white: 0.93, alpha: 1).setStroke(); band.stroke()

func cup(_ x: CGFloat) {
    let outer = NSBezierPath(roundedRect: CGRect(x: x, y: 290, width: 130, height: 230), xRadius: 58, yRadius: 58)
    NSGradient(colors: [NSColor(white: 0.98, alpha: 1), NSColor(white: 0.78, alpha: 1)])!.draw(in: outer, angle: -90)
    let pad = NSBezierPath(roundedRect: CGRect(x: x + 30, y: 322, width: 70, height: 166), xRadius: 32, yRadius: 32)
    NSColor(white: 0.12, alpha: 1).setFill(); pad.fill()
}
cup(210); cup(600)

// Mouse na frente, à direita, com contorno do fundo para destacar.
let mouseRect = CGRect(x: 560, y: 175, width: 230, height: 330)
let mouse = NSBezierPath(roundedRect: mouseRect, xRadius: 115, yRadius: 115)
ctx.saveGState()
let ring = NSBezierPath(roundedRect: mouseRect.insetBy(dx: -22, dy: -22), xRadius: 137, yRadius: 137)
NSColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1).setFill(); ring.fill()
ctx.setShadow(offset: .zero, blur: 40, color: neon.withAlphaComponent(0.8).cgColor)
NSGradient(colors: [neon, neonDeep])!.draw(in: mouse, angle: -90)
ctx.restoreGState()
// divisória dos botões + roda
let split = NSBezierPath()
split.move(to: CGPoint(x: mouseRect.midX, y: mouseRect.maxY - 8))
split.line(to: CGPoint(x: mouseRect.midX, y: mouseRect.maxY - 120))
split.move(to: CGPoint(x: mouseRect.minX + 12, y: mouseRect.maxY - 130))
split.curve(to: CGPoint(x: mouseRect.maxX - 12, y: mouseRect.maxY - 130),
            controlPoint1: CGPoint(x: mouseRect.midX - 40, y: mouseRect.maxY - 150),
            controlPoint2: CGPoint(x: mouseRect.midX + 40, y: mouseRect.maxY - 150))
split.lineWidth = 10; split.lineCapStyle = .round
NSColor(red: 0.02, green: 0.25, blue: 0.1, alpha: 0.9).setStroke(); split.stroke()
let wheel = NSBezierPath(roundedRect: CGRect(x: mouseRect.midX - 15, y: mouseRect.maxY - 100, width: 30, height: 62), xRadius: 15, yRadius: 15)
NSColor(red: 0.02, green: 0.2, blue: 0.08, alpha: 1).setFill(); wheel.fill()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
