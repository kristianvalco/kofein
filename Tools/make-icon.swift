// Vygeneruje AppIcon.iconset (+ náhľad) pre Kofein.
// Použitie: make-icon <výstupný priečinok> [štýl]      štýly: amber | cream | dark | sunset
//           make-icon <výstupný priečinok> preview     → jeden obrázok so všetkými štýlmi
import AppKit

enum Style: String, CaseIterable {
    case amber, cream, dark, sunset
}

let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "."
let styleArg = args.count > 2 ? args[2] : "amber"
let size: CGFloat = 1024

func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

func drawMaster(_ style: Style) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    defer { img.unlockFocus() }

    // macOS ikony majú okolo seba ~10 % priehľadný okraj
    let inset = size * 0.1
    let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.2237, yRadius: rect.width * 0.2237)

    // farby podľa štýlu: (pozadie, glyf, para)
    let bg: NSColor, glyph: NSColor, steam: NSColor
    switch style {
    case .amber:  (bg, glyph, steam) = (rgb(245, 158, 43), .white, .white)
    case .cream:  (bg, glyph, steam) = (rgb(247, 240, 230), rgb(43, 27, 18), rgb(232, 120, 38))
    case .dark:   (bg, glyph, steam) = (rgb(30, 30, 32), .white, rgb(255, 159, 67))
    case .sunset: (bg, glyph, steam) = (rgb(255, 122, 48), .white, .white)
    }

    // mäkký tieň pod celou ikonou
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(style == .cream ? 0.18 : 0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    bg.setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    if style == .sunset {
        // jediný štýl s gradientom: sýty, plynulý, zhora nadol (ako Apple ikony)
        NSGradient(starting: rgb(255, 176, 84), ending: rgb(255, 96, 40))!
            .draw(in: rect, angle: -90)
    }
    // jemné radiálne svetlo v hornej časti – dodá hĺbku bez viditeľného gradientu
    let glow = NSGradient(colors: [
        NSColor.white.withAlphaComponent(style == .cream ? 0.6 : 0.16),
        NSColor.white.withAlphaComponent(0),
    ])!
    glow.draw(fromCenter: NSPoint(x: rect.midX, y: rect.maxY - rect.height * 0.05), radius: 0,
              toCenter: NSPoint(x: rect.midX, y: rect.maxY - rect.height * 0.05), radius: rect.width * 0.85,
              options: [])
    NSGraphicsContext.restoreGraphicsState()

    // šálka (SF Symbol) – jednofarebná, s jemným tieňom
    let cupName = "cup.and.saucer.fill"
    let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [glyph]))
    guard let cup = NSImage(systemSymbolName: cupName, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { fatalError("SF Symbol sa nenašiel") }
    cup.isTemplate = false
    let scale = rect.width * 0.56 / cup.size.width
    let cupSize = NSSize(width: cup.size.width * scale, height: cup.size.height * scale)
    let cupRect = NSRect(x: rect.midX - cupSize.width / 2,
                         y: rect.midY - cupSize.height / 2 - rect.height * 0.06,
                         width: cupSize.width, height: cupSize.height)

    NSGraphicsContext.saveGraphicsState()
    let cupShadow = NSShadow()
    cupShadow.shadowColor = NSColor.black.withAlphaComponent(style == .cream ? 0.12 : 0.22)
    cupShadow.shadowBlurRadius = 14
    cupShadow.shadowOffset = NSSize(width: 0, height: -8)
    cupShadow.set()
    cup.draw(in: cupRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    // para: tri vlnky nad šálkou (SF Symbol šálka paru nemá)
    steam.withAlphaComponent(0.9).setStroke()
    let lineW = rect.width * 0.034
    let baseY = cupRect.maxY + rect.height * 0.03
    let steamH = rect.height * 0.15
    // stred šálky bez uška je trochu vľavo od stredu symbolu
    let cupCenterX = cupRect.midX - cupRect.width * 0.09
    for (i, dx) in [-0.13, 0.0, 0.13].enumerated() {
        let x = cupCenterX + rect.width * CGFloat(dx)
        let h = steamH * (i == 1 ? 1.0 : 0.8)
        let path = NSBezierPath()
        path.lineWidth = lineW
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: x, y: baseY))
        path.curve(to: NSPoint(x: x, y: baseY + h),
                   controlPoint1: NSPoint(x: x - rect.width * 0.07, y: baseY + h * 0.35),
                   controlPoint2: NSPoint(x: x + rect.width * 0.07, y: baseY + h * 0.65))
        path.stroke()
    }
    return img
}

func png(_ master: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    master.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

if styleArg == "preview" {
    // všetky štýly vedľa seba na svetlom aj tmavom pozadí
    let cell = 300, pad = 30
    let w = Style.allCases.count * (cell + pad) + pad, h = 2 * (cell + pad) + pad
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    for (row, bgColor) in [rgb(236, 236, 240), rgb(28, 28, 30)].enumerated() {
        bgColor.setFill()
        NSRect(x: 0, y: row * (cell + pad), width: w, height: cell + pad + (row == 1 ? pad : 0)).fill()
        for (col, style) in Style.allCases.enumerated() {
            let x = pad + col * (cell + pad), y = pad + row * (cell + pad)
            drawMaster(style).draw(in: NSRect(x: x, y: y, width: cell, height: cell),
                                   from: .zero, operation: .sourceOver, fraction: 1)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: row == 0 ? NSColor.black : NSColor.white,
            ]
            let label = "\(col + 1). \(style.rawValue)" as NSString
            label.draw(at: NSPoint(x: x + 18, y: y + 4), withAttributes: attrs)
        }
    }
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(outDir)/icon-variants.png"))
    print("\(outDir)/icon-variants.png")
    exit(0)
}

guard let style = Style(rawValue: styleArg) else {
    print("Neznámy štýl: \(styleArg). Možnosti: \(Style.allCases.map(\.rawValue).joined(separator: ", "))")
    exit(1)
}
let master = drawMaster(style)
let iconset = "\(outDir)/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(master, pixels: base).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base).png"))
    try! png(master, pixels: base * 2).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)@2x.png"))
}
try! png(master, pixels: 1024).write(to: URL(fileURLWithPath: "\(outDir)/AppIcon-preview.png"))
print("iconset: \(iconset) (\(style.rawValue))")
