import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let out = root.appendingPathComponent("outputs/play_store")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}

let ink = NSColor(hex: 0x17120f)
let stage = NSColor(hex: 0x100d0a)
let panel = NSColor(hex: 0x211e1a)
let cream = NSColor(hex: 0xf4efe7)
let muted = NSColor(hex: 0xb9aa95)
let amber = NSColor(hex: 0xf4a124)
let teal = NSColor(hex: 0x0fb5a4)
let red = NSColor(hex: 0xff5a4d)
let violet = NSColor(hex: 0x7b61ff)
let blue = NSColor(hex: 0x3b82f6)
let pink = NSColor(hex: 0xe84393)

func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

func renderPNG(width: Int, height: Int, file: String, draw: (CGFloat, CGFloat) -> Void) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "FilmswipePlayAssets", code: 1)
    }

    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.setShouldAntialias(true)
    context.cgContext.translateBy(x: 0, y: CGFloat(height))
    context.cgContext.scaleBy(x: 1, y: -1)
    draw(CGFloat(width), CGFloat(height))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "FilmswipePlayAssets", code: 2)
    }
    try data.write(to: out.appendingPathComponent(file))
}

func fill(_ color: NSColor, _ rect: CGRect, radius: CGFloat = 0) {
    color.setFill()
    let path = radius > 0
        ? NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        : NSBezierPath(rect: rect)
    path.fill()
}

func stroke(_ color: NSColor, _ rect: CGRect, radius: CGFloat = 0, width: CGFloat = 1) {
    color.setStroke()
    let path = radius > 0
        ? NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        : NSBezierPath(rect: rect)
    path.lineWidth = width
    path.stroke()
}

func line(_ color: NSColor, from: CGPoint, to: CGPoint, width: CGFloat = 1) {
    color.setStroke()
    let path = NSBezierPath()
    path.move(to: from)
    path.line(to: to)
    path.lineWidth = width
    path.lineCapStyle = .round
    path.stroke()
}

func text(
    _ value: String,
    x: CGFloat,
    y: CGFloat,
    w: CGFloat,
    h: CGFloat,
    size: CGFloat,
    color: NSColor,
    weight: NSFont.Weight = .regular,
    align: NSTextAlignment = .left
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = align
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineSpacing = size * 0.08
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font(size, weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    NSGraphicsContext.current?.cgContext.saveGState()
    NSGraphicsContext.current?.cgContext.scaleBy(x: 1, y: -1)
    let rect = CGRect(x: x, y: -y - h, width: w, height: h)
    (value as NSString).draw(in: rect, withAttributes: attrs)
    NSGraphicsContext.current?.cgContext.restoreGState()
}

func centerText(_ value: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
    text(value, x: x, y: y, w: w, h: h, size: size, color: color, weight: weight, align: .center)
}

func shadow(_ alpha: CGFloat, blur: CGFloat, y: CGFloat = 8) {
    let sh = NSShadow()
    sh.shadowColor = NSColor.black.withAlphaComponent(alpha)
    sh.shadowBlurRadius = blur
    sh.shadowOffset = NSSize(width: 0, height: -y)
    sh.set()
}

func clearShadow() {
    NSShadow().set()
}

func rotated(_ angle: CGFloat, around center: CGPoint, draw: () -> Void) {
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle * .pi / 180)
    ctx.translateBy(x: -center.x, y: -center.y)
    draw()
    ctx.restoreGState()
}

func chevron(x: CGFloat, y: CGFloat, scale: CGFloat, color: NSColor) {
    let lw = 7 * scale
    line(color, from: CGPoint(x: x - 16 * scale, y: y - 20 * scale), to: CGPoint(x: x, y: y), width: lw)
    line(color, from: CGPoint(x: x, y: y), to: CGPoint(x: x - 16 * scale, y: y + 20 * scale), width: lw)
    line(color, from: CGPoint(x: x + 18 * scale, y: y - 20 * scale), to: CGPoint(x: x + 34 * scale, y: y), width: lw)
    line(color, from: CGPoint(x: x + 34 * scale, y: y), to: CGPoint(x: x + 18 * scale, y: y + 20 * scale), width: lw)
}

func arrowRight(x: CGFloat, y: CGFloat, scale: CGFloat, color: NSColor) {
    let lw = 4.8 * scale
    line(color, from: CGPoint(x: x - 18 * scale, y: y), to: CGPoint(x: x + 18 * scale, y: y), width: lw)
    line(color, from: CGPoint(x: x + 3 * scale, y: y - 14 * scale), to: CGPoint(x: x + 18 * scale, y: y), width: lw)
    line(color, from: CGPoint(x: x + 18 * scale, y: y), to: CGPoint(x: x + 3 * scale, y: y + 14 * scale), width: lw)
}

func drawSymbol(x: CGFloat, y: CGFloat, size: CGFloat, rounded: CGFloat? = nil) {
    let r = rounded ?? size * 0.22
    fill(amber, CGRect(x: x, y: y, width: size, height: size), radius: r)
    let cardW = size * 0.36
    let cardH = size * 0.55
    let cy = y + size * 0.225
    let back = CGRect(x: x + size * 0.28, y: cy, width: cardW, height: cardH)
    let front = CGRect(x: x + size * 0.42, y: cy, width: cardW, height: cardH)
    rotated(-11, around: CGPoint(x: back.midX, y: back.midY)) {
        shadow(0.25, blur: size * 0.06, y: size * 0.02)
        fill(cream, back, radius: size * 0.08)
        clearShadow()
    }
    rotated(10, around: CGPoint(x: front.midX, y: front.midY)) {
        shadow(0.35, blur: size * 0.07, y: size * 0.02)
        fill(panel, front, radius: size * 0.08)
        clearShadow()
        chevron(x: front.midX - size * 0.02, y: front.midY, scale: size / 210, color: amber)
    }
}

func drawHeader(_ title: String? = nil) {
    text("Film", x: 56, y: 64, w: 112, h: 52, size: 38, color: cream, weight: .heavy)
    text("Swipe", x: 129, y: 64, w: 150, h: 52, size: 38, color: amber, weight: .heavy)
    if let title {
        text(title, x: 56, y: 123, w: 660, h: 36, size: 24, color: muted, weight: .semibold)
    }
    drawCircleIcon(x: 842, y: 69, icon: "search")
    drawPill(x: 912, y: 69, w: 118, label: "Filtros", color: panel, textColor: cream)
}

func drawCircleIcon(x: CGFloat, y: CGFloat, icon: String) {
    fill(panel, CGRect(x: x, y: y, width: 54, height: 54), radius: 27)
    if icon == "search" {
        stroke(cream.withAlphaComponent(0.9), CGRect(x: x + 15, y: y + 14, width: 20, height: 20), radius: 10, width: 3)
        line(cream.withAlphaComponent(0.9), from: CGPoint(x: x + 32, y: y + 32), to: CGPoint(x: x + 40, y: y + 40), width: 3)
    }
}

func drawPill(x: CGFloat, y: CGFloat, w: CGFloat, label: String, color: NSColor, textColor: NSColor) {
    fill(color, CGRect(x: x, y: y, width: w, height: 54), radius: 27)
    centerText(label, x: x + 12, y: y + 14, w: w - 24, h: 30, size: 20, color: textColor, weight: .bold)
}

func drawBottomNav(active: Int) {
    fill(NSColor(hex: 0x15110e), CGRect(x: 0, y: 1780, width: 1080, height: 140))
    let labels = ["Swipe", "Catalogo", "Pendientes", "Juntos", "Perfil"]
    let xs: [CGFloat] = [68, 268, 484, 690, 890]
    for (i, label) in labels.enumerated() {
        let isActive = i == active
        let col = isActive ? amber : NSColor(hex: 0x786d5f)
        fill(isActive ? NSColor(hex: 0x2b251d) : NSColor.clear, CGRect(x: xs[i] - 22, y: 1798, width: 130, height: 80), radius: 40)
        if i == 0 {
            chevron(x: xs[i] + 36, y: 1828, scale: 0.42, color: col)
        } else {
            stroke(col, CGRect(x: xs[i] + 23, y: 1813, width: 34, height: 34), radius: 8, width: 3)
        }
        centerText(label, x: xs[i] - 30, y: 1852, w: 150, h: 32, size: 16, color: col, weight: .bold)
    }
}

func drawPosterArt(_ rect: CGRect, colors: [NSColor], title: String, kicker: String) {
    fill(colors[0], rect, radius: 34)
    for i in 0..<6 {
        let inset = CGFloat(i) * 34
        fill(colors[(i + 1) % colors.count].withAlphaComponent(0.22), CGRect(x: rect.minX + inset, y: rect.minY + CGFloat(i) * 74, width: rect.width - inset * 0.7, height: 190), radius: 36)
    }
    fill(NSColor.black.withAlphaComponent(0.36), CGRect(x: rect.minX, y: rect.maxY - 230, width: rect.width, height: 230), radius: 0)
    text(kicker.uppercased(), x: rect.minX + 34, y: rect.maxY - 190, w: rect.width - 68, h: 28, size: 18, color: cream.withAlphaComponent(0.86), weight: .bold)
    text(title, x: rect.minX + 34, y: rect.maxY - 158, w: rect.width - 68, h: 92, size: 44, color: cream, weight: .heavy)
}

func drawTicket(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, title: String, subtitle: String, colors: [NSColor]) {
    shadow(0.45, blur: 30, y: 16)
    fill(cream, CGRect(x: x, y: y, width: w, height: h), radius: 36)
    clearShadow()
    let art = CGRect(x: x, y: y, width: w, height: h * 0.64)
    drawPosterArt(art, colors: colors, title: title, kicker: subtitle)
    line(NSColor(hex: 0xd8cbb9), from: CGPoint(x: x + 22, y: y + h * 0.64), to: CGPoint(x: x + w - 22, y: y + h * 0.64), width: 2)
    text(title, x: x + 36, y: y + h * 0.68, w: w - 72, h: 70, size: 42, color: ink, weight: .heavy)
    text("Drama visual  |  2026  |  118 min", x: x + 36, y: y + h * 0.77, w: w - 72, h: 36, size: 22, color: NSColor(hex: 0x796d5f), weight: .semibold)
    drawPill(x: x + 36, y: y + h - 88, w: 132, label: "Vista", color: teal, textColor: NSColor.white)
    drawPill(x: x + 184, y: y + h - 88, w: 174, label: "Pendiente", color: amber, textColor: ink)
}

func drawPhoneBase() {
    fill(stage, CGRect(x: 0, y: 0, width: 1080, height: 1920))
    fill(NSColor(hex: 0x17120e), CGRect(x: 0, y: 0, width: 1080, height: 1920))
    for i in 0..<8 {
        let color = [amber, teal, red, violet, blue][i % 5]
        fill(color.withAlphaComponent(0.08), CGRect(x: CGFloat(i) * 148 - 40, y: CGFloat(i) * 210 + 30, width: 420, height: 180), radius: 90)
    }
}

func drawMiniMovieRow(x: CGFloat, y: CGFloat, title: String, meta: String, color: NSColor, tag: String) {
    fill(panel, CGRect(x: x, y: y, width: 968, height: 164), radius: 24)
    drawPosterArt(CGRect(x: x + 18, y: y + 18, width: 94, height: 128), colors: [color, amber, teal], title: "", kicker: "")
    text(title, x: x + 140, y: y + 30, w: 520, h: 46, size: 28, color: cream, weight: .heavy)
    text(meta, x: x + 140, y: y + 78, w: 560, h: 34, size: 20, color: muted, weight: .semibold)
    drawPill(x: x + 742, y: y + 54, w: 164, label: tag, color: color, textColor: color == amber ? ink : NSColor.white)
}

func screenshot1() throws {
    try renderPNG(width: 1080, height: 1920, file: "01_swipe.png") { _, _ in
        drawPhoneBase()
        drawHeader("Descubre peliculas a golpe de swipe")
        text("Cartelera personal", x: 56, y: 178, w: 560, h: 44, size: 28, color: amber, weight: .bold)
        drawTicket(x: 140, y: 250, w: 800, h: 1180, title: "Luz de Medianoche", subtitle: "Recomendacion", colors: [NSColor(hex: 0x41224f), violet, pink, amber])
        centerText("Desliza derecha: vista  |  izquierda: descartar  |  arriba: pendiente", x: 70, y: 1495, w: 940, h: 70, size: 24, color: muted, weight: .semibold)
        drawPill(x: 160, y: 1602, w: 218, label: "Vista", color: teal, textColor: NSColor.white)
        drawPill(x: 430, y: 1602, w: 218, label: "Saltar", color: red, textColor: NSColor.white)
        drawPill(x: 700, y: 1602, w: 238, label: "Pendiente", color: amber, textColor: ink)
        drawBottomNav(active: 0)
    }
}

func screenshot2() throws {
    try renderPNG(width: 1080, height: 1920, file: "02_search.png") { _, _ in
        drawPhoneBase()
        drawHeader("Encuentra cualquier titulo")
        fill(panel, CGRect(x: 56, y: 190, width: 968, height: 82), radius: 41)
        text("Buscar pelicula...", x: 130, y: 214, w: 500, h: 42, size: 28, color: muted, weight: .semibold)
        stroke(muted, CGRect(x: 86, y: 214, width: 32, height: 32), radius: 16, width: 4)
        line(muted, from: CGPoint(x: 112, y: 240), to: CGPoint(x: 126, y: 254), width: 4)
        text("Resultados", x: 56, y: 326, w: 400, h: 46, size: 34, color: cream, weight: .heavy)
        drawMiniMovieRow(x: 56, y: 402, title: "La Ultima Entrada", meta: "Thriller | 2025 | 106 min", color: red, tag: "Pendiente")
        drawMiniMovieRow(x: 56, y: 596, title: "Verano en Marte", meta: "Sci-Fi | 2024 | 122 min", color: violet, tag: "Anadir")
        drawMiniMovieRow(x: 56, y: 790, title: "Cafe de Ruta", meta: "Comedia | 2023 | 98 min", color: amber, tag: "Vista")
        fill(NSColor(hex: 0x2b251d), CGRect(x: 56, y: 1064, width: 968, height: 380), radius: 32)
        text("Busca, revisa y guarda", x: 96, y: 1110, w: 720, h: 54, size: 40, color: cream, weight: .heavy)
        text("Film Swipe convierte cada busqueda en una decision rapida: vista, pendiente o descartada.", x: 96, y: 1184, w: 790, h: 126, size: 28, color: muted, weight: .semibold)
        drawBottomNav(active: 0)
    }
}

func screenshot3() throws {
    try renderPNG(width: 1080, height: 1920, file: "03_filters.png") { _, _ in
        drawPhoneBase()
        drawHeader("Filtra por decada, genero y pais")
        fill(NSColor(hex: 0xf4efe7), CGRect(x: 0, y: 360, width: 1080, height: 1420), radius: 42)
        fill(NSColor(hex: 0xd6c9b8), CGRect(x: 480, y: 390, width: 120, height: 10), radius: 5)
        text("Filtrar cartelera", x: 56, y: 430, w: 620, h: 56, size: 44, color: ink, weight: .heavy)
        text("Decada", x: 56, y: 532, w: 240, h: 36, size: 26, color: NSColor(hex: 0x4b4036), weight: .bold)
        let decades = ["1980s", "1990s", "2000s", "2010s", "2020s"]
        for (i, d) in decades.enumerated() {
            drawPill(x: 56 + CGFloat(i) * 190, y: 586, w: 154, label: d, color: i == 4 ? amber : NSColor(hex: 0xeee4d5), textColor: ink)
        }
        text("Genero", x: 56, y: 720, w: 240, h: 36, size: 26, color: NSColor(hex: 0x4b4036), weight: .bold)
        let genres = [("Drama", teal), ("Terror", red), ("Comedia", amber), ("Sci-Fi", violet), ("Romance", pink), ("Crimen", blue)]
        for (i, item) in genres.enumerated() {
            let col = i < 3 ? item.1 : NSColor(hex: 0xeee4d5)
            let textCol = i < 3 && item.1 != amber ? NSColor.white : ink
            drawPill(x: 56 + CGFloat(i % 3) * 318, y: 774 + CGFloat(i / 3) * 88, w: 280, label: item.0, color: col, textColor: textCol)
        }
        text("Origen", x: 56, y: 998, w: 240, h: 36, size: 26, color: NSColor(hex: 0x4b4036), weight: .bold)
        drawPill(x: 56, y: 1052, w: 260, label: "Europa", color: violet, textColor: NSColor.white)
        drawPill(x: 344, y: 1052, w: 260, label: "Asia", color: teal, textColor: NSColor.white)
        drawPill(x: 632, y: 1052, w: 300, label: "America", color: NSColor(hex: 0xeee4d5), textColor: ink)
        fill(panel, CGRect(x: 56, y: 1264, width: 968, height: 112), radius: 56)
        centerText("Aplicar filtros", x: 56, y: 1298, w: 900, h: 46, size: 32, color: amber, weight: .heavy)
        arrowRight(x: 690, y: 1321, scale: 1.05, color: amber)
        drawBottomNav(active: 0)
    }
}

func screenshot4() throws {
    try renderPNG(width: 1080, height: 1920, file: "04_watchlist.png") { _, _ in
        drawPhoneBase()
        drawHeader("Tu lista para ver despues")
        text("Pendientes", x: 56, y: 186, w: 420, h: 58, size: 46, color: cream, weight: .heavy)
        text("Guarda las peliculas que no quieres perder.", x: 56, y: 252, w: 680, h: 40, size: 24, color: muted, weight: .semibold)
        drawMiniMovieRow(x: 56, y: 350, title: "Hotel Aurora", meta: "Misterio | 2026 | 101 min", color: violet, tag: "Pendiente")
        drawMiniMovieRow(x: 56, y: 544, title: "Noche de Estreno", meta: "Drama | 2025 | 116 min", color: amber, tag: "Pendiente")
        drawMiniMovieRow(x: 56, y: 738, title: "Ruta 27", meta: "Aventura | 2024 | 109 min", color: teal, tag: "Pendiente")
        fill(NSColor(hex: 0x2b251d), CGRect(x: 56, y: 1016, width: 968, height: 436), radius: 34)
        text("Reserva sin olvidar", x: 96, y: 1070, w: 720, h: 54, size: 42, color: cream, weight: .heavy)
        text("Marca una pelicula como pendiente con un swipe hacia arriba y vuelve cuando toque elegir plan.", x: 96, y: 1150, w: 790, h: 120, size: 28, color: muted, weight: .semibold)
        drawPill(x: 96, y: 1320, w: 250, label: "Orden reciente", color: amber, textColor: ink)
        drawBottomNav(active: 2)
    }
}

func screenshot5() throws {
    try renderPNG(width: 1080, height: 1920, file: "05_detail.png") { _, _ in
        drawPhoneBase()
        drawHeader("Ficha de pelicula")
        drawTicket(x: 96, y: 210, w: 888, h: 1320, title: "Noche de Estreno", subtitle: "Detalle", colors: [NSColor(hex: 0x183b3a), teal, amber, blue])
        text("Sinopsis, reparto, direccion, duracion y valoracion en una ficha clara antes de decidir.", x: 126, y: 1340, w: 820, h: 110, size: 28, color: NSColor(hex: 0x4a4035), weight: .semibold)
        drawBottomNav(active: 1)
    }
}

func screenshot6() throws {
    try renderPNG(width: 1080, height: 1920, file: "06_profile.png") { _, _ in
        drawPhoneBase()
        drawHeader("Tu historial de cine")
        text("Perfil", x: 56, y: 186, w: 420, h: 58, size: 46, color: cream, weight: .heavy)
        fill(panel, CGRect(x: 56, y: 286, width: 968, height: 420), radius: 34)
        text("Perfil de cine", x: 104, y: 342, w: 480, h: 32, size: 22, color: amber, weight: .bold)
        text("Cinefila en marcha", x: 104, y: 390, w: 650, h: 66, size: 48, color: cream, weight: .heavy)
        fill(NSColor(hex: 0x3a3128), CGRect(x: 104, y: 506, width: 820, height: 26), radius: 13)
        fill(amber, CGRect(x: 104, y: 506, width: 560, height: 26), radius: 13)
        text("18 vistas | 7 pendientes | 34 h en la butaca", x: 104, y: 560, w: 740, h: 40, size: 26, color: muted, weight: .semibold)
        let stats = [("18", "vistas", teal), ("7", "pendientes", amber), ("34", "horas", violet)]
        for (i, s) in stats.enumerated() {
            let x = 56 + CGFloat(i) * 332
            fill(NSColor(hex: 0x2b251d), CGRect(x: x, y: 770, width: 300, height: 210), radius: 30)
            centerText(s.0, x: x, y: 808, w: 300, h: 72, size: 58, color: s.2, weight: .heavy)
            centerText(s.1, x: x, y: 894, w: 300, h: 42, size: 24, color: muted, weight: .bold)
        }
        text("Generos favoritos", x: 56, y: 1060, w: 420, h: 44, size: 34, color: cream, weight: .heavy)
        drawPill(x: 56, y: 1132, w: 260, label: "Drama", color: teal, textColor: NSColor.white)
        drawPill(x: 344, y: 1132, w: 260, label: "Sci-Fi", color: violet, textColor: NSColor.white)
        drawPill(x: 632, y: 1132, w: 260, label: "Terror", color: red, textColor: NSColor.white)
        fill(NSColor(hex: 0x3a3128), CGRect(x: 56, y: 1300, width: 968, height: 36), radius: 18)
        fill(teal, CGRect(x: 56, y: 1300, width: 720, height: 36), radius: 18)
        text("2020s", x: 56, y: 1360, w: 200, h: 34, size: 24, color: muted, weight: .semibold)
        fill(NSColor(hex: 0x3a3128), CGRect(x: 56, y: 1428, width: 968, height: 36), radius: 18)
        fill(amber, CGRect(x: 56, y: 1428, width: 440, height: 36), radius: 18)
        text("2010s", x: 56, y: 1488, w: 200, h: 34, size: 24, color: muted, weight: .semibold)
        drawBottomNav(active: 4)
    }
}

func featureGraphic() throws {
    try renderPNG(width: 1024, height: 500, file: "feature_graphic.png") { w, h in
        fill(stage, CGRect(x: 0, y: 0, width: w, height: h))
        fill(amber.withAlphaComponent(0.16), CGRect(x: 676, y: -80, width: 420, height: 420), radius: 210)
        fill(teal.withAlphaComponent(0.13), CGRect(x: -110, y: 270, width: 380, height: 220), radius: 110)
        drawSymbol(x: 66, y: 134, size: 180, rounded: 40)
        text("Film", x: 296, y: 102, w: 150, h: 76, size: 56, color: cream, weight: .heavy)
        text("Swipe", x: 406, y: 102, w: 204, h: 76, size: 56, color: amber, weight: .heavy)
        text("Descubre peliculas, desliza y guarda tu proxima noche de cine.", x: 298, y: 194, w: 430, h: 106, size: 29, color: muted, weight: .semibold)
        drawPill(x: 298, y: 332, w: 210, label: "Vista", color: teal, textColor: NSColor.white)
        drawPill(x: 528, y: 332, w: 226, label: "Pendiente", color: amber, textColor: ink)
        rotated(-8, around: CGPoint(x: 912, y: 232)) {
            drawPosterArt(CGRect(x: 852, y: 82, width: 132, height: 230), colors: [violet, pink, amber], title: "", kicker: "")
        }
        rotated(7, around: CGPoint(x: 842, y: 304)) {
            drawPosterArt(CGRect(x: 768, y: 166, width: 146, height: 238), colors: [teal, blue, amber], title: "", kicker: "")
        }
    }
}

func playIcon() throws {
    try renderPNG(width: 512, height: 512, file: "app_icon_512.png") { _, _ in
        fill(NSColor.clear, CGRect(x: 0, y: 0, width: 512, height: 512))
        drawSymbol(x: 18, y: 18, size: 476, rounded: 108)
    }
}

try screenshot1()
try screenshot2()
try screenshot3()
try screenshot4()
try screenshot5()
try screenshot6()
try featureGraphic()
try playIcon()

print("Generated Play Store assets in \(out.path)")
