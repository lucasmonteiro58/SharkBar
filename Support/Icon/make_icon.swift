// Gera o ícone do SharkBar (1024×1024) em vetor. Uso: swift make_icon.swift saida.png
// Barbatana de tubarão saindo de uma onda, sob uma "barra de menu" — tudo desenhado à mão.
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
let neon = rgb(70, 245, 140)
let teal = rgb(40, 200, 220)

// Fundo: squircle do macOS com sombra.
let bgRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor.black.withAlphaComponent(0.45).cgColor)
NSColor.black.setFill(); bg.fill()
ctx.restoreGState()

ctx.saveGState()
bg.addClip()
NSGradient(colors: [rgb(16, 32, 52), rgb(6, 12, 22)])!.draw(in: bgRect, angle: -90)
// brilho atrás da barbatana
NSGradient(colors: [teal.withAlphaComponent(0.35), teal.withAlphaComponent(0)])!
    .draw(fromCenter: CGPoint(x: 540, y: 430), radius: 0, toCenter: CGPoint(x: 540, y: 430), radius: 430, options: [])

// "Barra de menu" no topo, com três itens.
let bar = CGRect(x: 100, y: 772, width: 824, height: 152)
NSColor.white.withAlphaComponent(0.07).setFill(); NSBezierPath(rect: bar).fill()
NSColor.white.withAlphaComponent(0.12).setFill(); NSBezierPath(rect: CGRect(x: 100, y: 770, width: 824, height: 4)).fill()
for (i, w) in [70.0, 46.0, 110.0].enumerated() {
    let x = 560 + [0.0, 96.0, 168.0][i]
    let pill = NSBezierPath(roundedRect: CGRect(x: x, y: 832, width: w, height: 30), xRadius: 15, yRadius: 15)
    (i == 2 ? neon : NSColor.white.withAlphaComponent(0.55)).setFill()
    pill.fill()
}
let dot = NSBezierPath(ovalIn: CGRect(x: 180, y: 830, width: 34, height: 34))
NSColor.white.withAlphaComponent(0.55).setFill(); dot.fill()

// Barbatana.
let fin = NSBezierPath()
fin.move(to: CGPoint(x: 300, y: 330))
fin.curve(to: CGPoint(x: 600, y: 700), controlPoint1: CGPoint(x: 400, y: 420), controlPoint2: CGPoint(x: 470, y: 640))
fin.curve(to: CGPoint(x: 700, y: 330), controlPoint1: CGPoint(x: 640, y: 560), controlPoint2: CGPoint(x: 640, y: 420))
fin.close()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 26, color: NSColor.black.withAlphaComponent(0.5).cgColor)
NSGradient(colors: [rgb(250, 252, 255), rgb(170, 190, 210)])!.draw(in: fin, angle: -70)
ctx.restoreGState()
// reflexo na borda de ataque
let edge = NSBezierPath()
edge.move(to: CGPoint(x: 600, y: 700))
edge.curve(to: CGPoint(x: 660, y: 360), controlPoint1: CGPoint(x: 630, y: 580), controlPoint2: CGPoint(x: 640, y: 450))
edge.lineWidth = 10; edge.lineCapStyle = .round
NSColor.white.withAlphaComponent(0.6).setStroke(); edge.stroke()

// Onda (água) cobrindo a base da barbatana.
func wave(y: CGFloat, amp: CGFloat, phase: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: CGPoint(x: 100, y: 100))
    p.line(to: CGPoint(x: 100, y: y))
    var x: CGFloat = 100
    while x <= 924 {
        p.line(to: CGPoint(x: x, y: y + amp * sin((x + phase) / 70)))
        x += 4
    }
    p.line(to: CGPoint(x: 924, y: 100))
    p.close()
    return p
}
NSGradient(colors: [teal.withAlphaComponent(0.85), rgb(10, 60, 90)])!.draw(in: wave(y: 345, amp: 16, phase: 0), angle: -90)
NSGradient(colors: [rgb(20, 90, 120), rgb(8, 30, 50)])!.draw(in: wave(y: 290, amp: 14, phase: 60), angle: -90)
// crista neon
let crest = NSBezierPath()
var x: CGFloat = 100
crest.move(to: CGPoint(x: x, y: 345 + 16 * sin(x / 70)))
while x <= 924 { x += 4; crest.line(to: CGPoint(x: x, y: 345 + 16 * sin(x / 70))) }
crest.lineWidth = 9
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 22, color: neon.withAlphaComponent(0.9).cgColor)
neon.setStroke(); crest.stroke()
ctx.restoreGState()
ctx.restoreGState()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
