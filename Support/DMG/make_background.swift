// Fundo da janela do instalador (.dmg). Uso: swift make_background.swift saida.png escala
import AppKit

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "background.png"
let scale: CGFloat = args.count > 2 ? CGFloat(Double(args[2]) ?? 1) : 1
let W: CGFloat = 640, H: CGFloat = 400

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
let neon = rgb(70, 245, 140), teal = rgb(40, 200, 220)

NSGradient(colors: [rgb(16, 32, 52), rgb(6, 12, 22)])!.draw(in: CGRect(x: 0, y: 0, width: W, height: H), angle: -90)
NSGradient(colors: [teal.withAlphaComponent(0.22), teal.withAlphaComponent(0)])!
    .draw(fromCenter: CGPoint(x: W / 2, y: 210), radius: 0, toCenter: CGPoint(x: W / 2, y: 210), radius: 300, options: [])

// Onda neon no rodapé (mesma linguagem do ícone).
let crest = NSBezierPath()
var x: CGFloat = 0
crest.move(to: CGPoint(x: 0, y: 46))
while x <= W { x += 3; crest.line(to: CGPoint(x: x, y: 46 + 7 * sin(x / 38))) }
crest.lineWidth = 3
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 12, color: neon.withAlphaComponent(0.8).cgColor)
neon.withAlphaComponent(0.85).setStroke(); crest.stroke()
ctx.restoreGState()

// Seta do app para Aplicativos (ícones ficam em x=170 e x=470, y=200 contando de cima).
let arrowY = H - 200
let arrow = NSBezierPath()
arrow.move(to: CGPoint(x: 262, y: arrowY))
arrow.line(to: CGPoint(x: 370, y: arrowY))
arrow.lineWidth = 6; arrow.lineCapStyle = .round
let head = NSBezierPath()
head.move(to: CGPoint(x: 356, y: arrowY + 16))
head.line(to: CGPoint(x: 378, y: arrowY))
head.line(to: CGPoint(x: 356, y: arrowY - 16))
head.lineWidth = 6; head.lineCapStyle = .round; head.lineJoinStyle = .round
NSColor.white.withAlphaComponent(0.75).setStroke()
arrow.stroke(); head.stroke()

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                            .foregroundColor: color, .paragraphStyle: p]
    NSAttributedString(string: s, attributes: a).draw(in: CGRect(x: 0, y: y, width: W, height: size * 1.5))
}
text("Instalar o SharkBar", size: 24, weight: .bold, color: .white, y: H - 70)
text("Arraste o ícone para a pasta Aplicativos", size: 14, weight: .regular, color: NSColor.white.withAlphaComponent(0.7), y: H - 98)
text("Primeira abertura: Ajustes › Privacidade e Segurança › Abrir Mesmo Assim", size: 11, weight: .regular,
     color: NSColor.white.withAlphaComponent(0.5), y: 66)

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
