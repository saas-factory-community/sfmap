import AppKit

/**
 * HOJA DE CONTACTO DE ICONOS. `sfmap --iconos <salida.png>`.
 *
 * ⚠️ Un icono descentrado NO FALLA: se ve "raro" en una barra de veinte y nadie
 * sabe cuál. Daniel lo dijo así — *"nota como algunos se rompen"*— y tenía razón
 * sin poder señalarlos, porque a 18 px y de uno en uno no se distingue un trazo
 * torcido de un trazo distinto.
 *
 * Puestos en cuadrícula, cada uno dentro de su caja de 24 y con sus dos ejes
 * marcados, el que se sale se ve en un segundo. Es el sensor que faltaba: se
 * miran TODOS a la vez o no se mira ninguno.
 */
enum HojaIconos {
    static func ruta() -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--iconos") else { return nil }
        return i + 1 < a.count ? a[i + 1] : "/tmp/iconos.png"
    }

    static let items: [(String, NSImage)] = [
        ("alFondo", Icono.alFondo),
        ("alFrente", Icono.alFrente),
        ("basura", Icono.basura),
        ("candado", Icono.candado),
        ("candadoAbierto", Icono.candadoAbierto),
        ("carpeta", Icono.carpeta),
        ("carpetaAbierta", Icono.carpetaAbierta),
        ("carpetaMas", Icono.carpetaMas),
        ("lienzo", Icono.lienzo),
        ("lienzoMas", Icono.lienzoMas),
        ("equis", Icono.equis),
        ("chevronAbajo", Icono.chevronAbajo),
        ("chevronArriba", Icono.chevronArriba),
        ("chevronDerecha", Icono.chevronDerecha),
        ("chincheta", Icono.chincheta),
        ("circulo", Icono.circulo),
        ("codigo", Icono.codigo),
        ("colorTexto", Icono.colorTexto),
        ("compilar", Icono.compilar),
        ("conector", Icono.conector),
        ("contornoIcono", Icono.contornoIcono),
        ("cuadrado", Icono.cuadrado),
        ("cursiva", Icono.cursiva),
        ("cursor", Icono.cursor),
        ("descargar", Icono.descargar),
        ("documentos", Icono.documentos),
        ("deshacer", Icono.deshacer),
        ("destello", Icono.destello),
        ("duplicar", Icono.duplicar),
        ("embed", Icono.embed),
        ("encuadrar", Icono.encuadrar),
        ("enlace", Icono.enlace),
        ("engrane", Icono.engrane),
        ("panel", Icono.panel),
        ("esquina", Icono.esquina),
        ("estrella", Icono.estrella),
        ("figuras", Icono.figuras),
        ("flechaFigura", Icono.flechaFigura),
        ("fondoCuadricula", Icono.fondoCuadricula),
        ("fondoLiso", Icono.fondoLiso),
        ("fondoPuntos", Icono.fondoPuntos),
        ("goma", Icono.goma),
        ("hexagono", Icono.hexagono),
        ("imagen", Icono.imagen),
        ("interrogacion", Icono.interrogacion),
        ("lapiz", Icono.lapiz),
        ("luna", Icono.luna),
        ("lupa", Icono.lupa),
        ("mano", Icono.mano),
        ("marcador", Icono.marcador),
        ("mas", Icono.mas),
        ("menos", Icono.menos),
        ("negrita", Icono.negrita),
        ("nota", Icono.nota),
        ("pildora", Icono.pildora),
        ("puntos", Icono.puntos),
        ("recargar", Icono.recargar),
        ("recortar", Icono.recortar),
        ("rehacer", Icono.rehacer),
        ("rellenoIcono", Icono.rellenoIcono),
        ("resaltar", Icono.resaltar),
        ("rombo", Icono.rombo),
        ("seccion", Icono.seccion),
        ("sol", Icono.sol),
        ("subrayado", Icono.subrayado),
        ("tabla", Icono.tabla),
        ("textoT", Icono.textoT),
        ("tresPuntos", Icono.tresPuntos),
        ("triangulo", Icono.triangulo),
        ("alinear:left", Icono.alinear("left")),
        ("alinear:center", Icono.alinear("center")),
        ("alinear:right", Icono.alinear("right")),
        ("grosor:2", Icono.grosor(2)),
        ("grosor:7", Icono.grosor(7)),
        ("grosor:20", Icono.grosor(20)),
        ("linea:solid", Icono.linea("solid")),
        ("linea:dashed", Icono.linea("dashed")),
        ("linea:dotted", Icono.linea("dotted")),
        ("ruta:ortogonal", Icono.ruta("ortogonal")),
        ("ruta:recta", Icono.ruta("recta")),
        ("ruta:curva", Icono.ruta("curva")),
        ("punta:ninguna", Icono.punta("ninguna")),
        ("punta:flecha", Icono.punta("flecha")),
        ("punta:triangulo", Icono.punta("triangulo")),
        ("punta:rombo", Icono.punta("rombo")),
        ("punta:circulo", Icono.punta("circulo")),
        ("punta:barra", Icono.punta("barra")),
        ("clase:flujo", Icono.clase("flujo")),
        ("clase:agente", Icono.clase("agente")),
        ("clase:fragil", Icono.clase("fragil")),
        ("clase:hueco", Icono.clase("hueco")),
    ]

    static func generar(_ salida: String) {
        let lado: CGFloat = 76, cols = 8
        let filas = (items.count + cols - 1) / cols
        let w = Int(CGFloat(cols) * lado), h = Int(CGFloat(filas) * (lado + 16))
        guard let ctx = CGContext(data: nil, width: w * 2, height: h * 2, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.scaleBy(x: 2, y: 2)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for (i, item) in items.enumerated() {
            let cx = CGFloat(i % cols) * lado
            let cy = CGFloat(h) - CGFloat(i / cols + 1) * (lado + 16)
            let caja = CGRect(x: cx + (lado - 44) / 2, y: cy + 24, width: 44, height: 44)
            ctx.setStrokeColor(NSColor(srgbRed: 0.55, green: 0.15, blue: 0.95, alpha: 0.20).cgColor)
            ctx.setLineWidth(1); ctx.stroke(caja)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: caja.midX, y: caja.minY)); ctx.addLine(to: CGPoint(x: caja.midX, y: caja.maxY))
            ctx.move(to: CGPoint(x: caja.minX, y: caja.midY)); ctx.addLine(to: CGPoint(x: caja.maxX, y: caja.midY))
            ctx.strokePath()
            item.1.draw(in: caja)
            let t = NSAttributedString(string: item.0, attributes: [
                .font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor.darkGray])
            t.draw(at: NSPoint(x: cx + (lado - t.size().width) / 2, y: cy + 10))
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let img = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: salida))
        FileHandle.standardError.write("hoja: \(items.count) iconos → \(salida)\n".data(using: .utf8)!)
    }
}
