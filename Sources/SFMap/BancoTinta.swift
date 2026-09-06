import AppKit
import CoreGraphics
import Foundation

/**
 * EL BANCO DE TRAZOS. `sfmap --banco <carpeta>`.
 *
 * Un motor de tinta no se juzga con adjetivos. Esto coge el fixture
 * `banco/trazos.json` —la tinta REAL de Daniel de "La Máquina en Frío" más los
 * casos sintéticos que aprietan donde duele— y lo rasteriza a PNG.
 *
 * ⚠️ LO IMPORTANTE ES QUE EL RASTERIZADOR ES UNO SOLO.
 *
 * Cada motor entrega GEOMETRÍA y esta clase la pinta con el mismo contexto, el
 * mismo fondo, el mismo antialiasing y la misma escala. Si cada motor pintara
 * en su propia pila —CoreGraphics contra el canvas de un navegador— el A/B
 * mediría la pila de dibujo tanto como el motor, y la comparación no diría
 * nada. Así lo único que puede diferir es la forma.
 *
 * Motores:
 *   · `sfmap`   — el motor nuevo (`Tinta`)
 *   · `viejo`   — el de antes, copiado aquí VERBATIM para poder medir el antes
 *                 y el después con el mismo instrumento
 *   · `web-pf`  — perfect-freehand, el referente del spec, con sus parámetros
 *                 canónicos (`scripts/banco-web.mjs` produce los polígonos)
 *   · `web-v4`  — el ribbon del lienzo web v4, que es lo que HOY pinta este
 *                 mismo documento en el navegador
 *
 * `--ab sfmap,web-pf` compone los pares en una sola lámina con las etiquetas A
 * y B y guarda la clave APARTE: el crítico ciego mira la lámina y la clave no
 * viaja con ella.
 */
enum BancoTinta {

    static func ruta() -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--banco") else { return nil }
        return i + 1 < a.count ? a[i + 1] : "/tmp/banco-tinta"
    }

    private static func arg(_ nombre: String) -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: nombre), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    /// Píxeles por unidad de mundo. 3 no es capricho: el poligonado y el
    /// banding se ven a partir de ahí, y a 1x un juicio de suavidad es un
    /// juicio sobre el antialiasing.
    static var ESCALA = 3.0
    static let MARGEN = 14.0

    // ════════════════════════════════════════════════════════════════════════
    // MARK: el fixture
    // ════════════════════════════════════════════════════════════════════════

    struct Trazo {
        var x: Double, y: Double
        var grosor: Double
        var marcador: Bool
        var puntos: [PuntoTinta]
    }
    struct Caso {
        var nombre: String, grupo: String, nota: String
        var trazos: [Trazo]
    }

    static func leerFixture(_ ruta: String) -> [Caso] {
        guard let d = FileManager.default.contents(atPath: ruta),
              let j = try? JSONDecoder().decode(Json.self, from: d),
              let cs = j["casos"]?.arr else { return [] }
        return cs.map { c in
            Caso(nombre: c["nombre"]?.s ?? "?", grupo: c["grupo"]?.s ?? "?",
                 nota: c["nota"]?.s ?? "",
                 trazos: (c["trazos"]?.arr ?? []).map { t in
                     Trazo(x: t["x"]?.num ?? 0, y: t["y"]?.num ?? 0,
                           grosor: t["size"]?.num ?? 4,
                           marcador: t["highlighter"]?.b ?? false,
                           puntos: (t["puntos"]?.arr ?? []).map { p in
                               PuntoTinta(x: p["x"]?.num ?? 0, y: p["y"]?.num ?? 0,
                                          p: p["pressure"]?.num ?? 0.5,
                                          ix: p["tiltX"]?.num ?? 0, iy: p["tiltY"]?.num ?? 0,
                                          t: p["t"]?.num ?? -1)
                           })
                 })
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: el motor viejo, tal cual era
    // ════════════════════════════════════════════════════════════════════════

    /**
     * El de antes, palabra por palabra: `addLine` entre muestras y
     * `setLineWidth` por segmento. Vive aquí y no en el pintor porque su único
     * trabajo es ser el ANTES de una medición — un motor retirado que se queda
     * en el camino caliente es deuda; uno que se queda en el banco es un
     * testigo.
     */
    private static func pintarViejo(_ ctx: CGContext, _ t: Trazo, _ color: CGColor) {
        let pts = t.puntos
        guard pts.count >= 2 else { return }
        ctx.saveGState()
        ctx.setAlpha(t.marcador ? 0.35 : 1)
        ctx.setStrokeColor(color)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        var mn = 1.0, mx = 0.0
        for q in pts { mn = min(mn, q.p); mx = max(mx, q.p) }
        let varia = (mx - mn) > 0.03
        for i in 0..<(pts.count - 1) {
            ctx.setLineWidth(t.grosor * (varia ? (0.4 + pts[i].p * 1.2) : 1))
            ctx.move(to: CGPoint(x: t.x + pts[i].x, y: t.y + pts[i].y))
            ctx.addLine(to: CGPoint(x: t.x + pts[i + 1].x, y: t.y + pts[i + 1].y))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: rasterizar
    // ════════════════════════════════════════════════════════════════════════

    struct Marco { var minX = 0.0, minY = 0.0, ancho = 0.0, alto = 0.0 }

    /// La caja del caso, con margen para el ancho máximo posible del trazo. Se
    /// calcula UNA vez para todos los motores: encuadrar cada uno a su propia
    /// tinta cambiaría la escala entre paneles y el A/B compararía zooms.
    static func marco(_ c: Caso) -> Marco {
        var mnx = Double.infinity, mny = Double.infinity
        var mxx = -Double.infinity, mxy = -Double.infinity
        var pad = MARGEN
        for t in c.trazos {
            pad = max(pad, MARGEN + Tinta.diametro(Tinta.Opciones(grosor: t.grosor, marcador: t.marcador)))
            for q in t.puntos {
                mnx = min(mnx, t.x + q.x); mxx = max(mxx, t.x + q.x)
                mny = min(mny, t.y + q.y); mxy = max(mxy, t.y + q.y)
            }
        }
        guard mnx.isFinite else { return Marco(minX: 0, minY: 0, ancho: 40, alto: 40) }
        return Marco(minX: mnx - pad, minY: mny - pad,
                     ancho: max(20, mxx - mnx + pad * 2), alto: max(20, mxy - mny + pad * 2))
    }

    static func contexto(_ m: Marco) -> CGContext? {
        let w = Int((m.ancho * ESCALA).rounded()), h = Int((m.alto * ESCALA).rounded())
        guard w > 0, h > 0, w < 12000, h < 12000,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        // El mundo tiene la Y hacia ABAJO, como el canvas del navegador; el
        // mapa de bits la tiene hacia arriba. Se voltea una vez aquí.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: ESCALA, y: -ESCALA)
        ctx.translateBy(x: -m.minX, y: -m.minY)
        return ctx
    }

    static let TINTA = CGColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
    static let MARCADOR = CGColor(red: 1, green: 0.72, blue: 0.14, alpha: 1)

    /**
     * EL PESO DE LA TINTA, en unidades de mundo al cuadrado.
     *
     * Existe porque "se ve más grueso" no es un juicio de calidad, es un
     * juicio de PESO — y comparar dos motores que pintan con grosores
     * distintos no mide la calidad de ninguno. Se suma la cobertura de cada
     * píxel (1 = tinta llena) y se divide por la escala al cuadrado.
     *
     * Con la longitud del trazo, que es la misma para todos los motores
     * porque los puntos son los mismos, sale el ANCHO MEDIO: el número que
     * dice si el A/B es justo.
     */
    static func peso(_ ctx: CGContext) -> Double {
        guard let base = ctx.data else { return 0 }
        let w = ctx.width, h = ctx.height, fila = ctx.bytesPerRow
        let p = base.bindMemory(to: UInt8.self, capacity: fila * h)
        var suma = 0.0
        for y in 0..<h {
            let f = y * fila
            for x in 0..<w {
                let i = f + x * 4
                // Fondo blanco: la tinta es lo que FALTA de blanco. Se mide en
                // el verde, que es donde el ojo pone casi toda la luminancia.
                suma += (255.0 - Double(p[i + 1])) / 255.0
            }
        }
        return suma / (ESCALA * ESCALA)
    }

    /// Longitud del trazo por sus muestras crudas. Igual para todos los
    /// motores: es el denominador honesto del ancho medio.
    static func largo(_ c: Caso) -> Double {
        var l = 0.0
        for t in c.trazos where t.puntos.count >= 2 {
            for i in 1..<t.puntos.count {
                l += hypot(t.puntos[i].x - t.puntos[i - 1].x, t.puntos[i].y - t.puntos[i - 1].y)
            }
        }
        return max(1e-6, l)
    }

    static func png(_ ctx: CGContext, _ ruta: String) -> Bool {
        guard let img = ctx.makeImage() else { return false }
        let rep = NSBitmapImageRep(cgImage: img)
        guard let d = rep.representation(using: .png, properties: [:]) else { return false }
        try? d.write(to: URL(fileURLWithPath: ruta))
        return true
    }

    /// Pinta un caso con el motor nuevo y devuelve cuánto tardó la GEOMETRÍA
    /// (sin el rasterizado), que es lo único que este cambio puede empeorar.
    @discardableResult
    static func pintarSfmap(_ ctx: CGContext, _ c: Caso) -> Double {
        var geo = 0.0
        for t in c.trazos {
            let opc = Tinta.Opciones(grosor: t.grosor, marcador: t.marcador)
            let t0 = CFAbsoluteTimeGetCurrent()
            let cam = Tinta.camino(t.puntos, opc)
            geo += CFAbsoluteTimeGetCurrent() - t0
            guard let cam else { continue }
            ctx.saveGState()
            ctx.setAlpha(t.marcador ? 0.35 : 1)
            ctx.setFillColor(t.marcador ? MARCADOR : TINTA)
            ctx.translateBy(x: t.x, y: t.y)
            ctx.addPath(cam)
            ctx.fillPath(using: .winding)
            ctx.restoreGState()
        }
        return geo
    }

    /// Polígonos que llegan de fuera (perfect-freehand, ribbon v4). Se rellenan
    /// EXACTAMENTE como el navegador los rellena: el referente cierra el
    /// contorno con cuadráticas de punto medio, así que aquí también.
    static func pintarPoligonos(_ ctx: CGContext, _ c: Caso, _ polis: [Json], suave: Bool) {
        for (i, t) in c.trazos.enumerated() {
            guard i < polis.count, let pts = polis[i].arr, pts.count >= 3 else { continue }
            let p: [CGPoint] = pts.map { CGPoint(x: $0["x"]?.num ?? 0, y: $0["y"]?.num ?? 0) }
            let cam = CGMutablePath()
            if suave {
                cam.move(to: p[0])
                for k in 1..<p.count {
                    let a = p[k], b = p[(k + 1) % p.count]
                    cam.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
                }
            } else {
                cam.move(to: p[0])
                for k in 1..<p.count { cam.addLine(to: p[k]) }
            }
            cam.closeSubpath()
            ctx.saveGState()
            ctx.setAlpha(t.marcador ? 0.35 : 1)
            ctx.setFillColor(t.marcador ? MARCADOR : TINTA)
            ctx.translateBy(x: t.x, y: t.y)
            ctx.addPath(cam)
            ctx.fillPath(using: .winding)
            ctx.restoreGState()
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: correr
    // ════════════════════════════════════════════════════════════════════════

    static func generar(_ carpeta: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: carpeta, withIntermediateDirectories: true)
        if let e = arg("--escala").flatMap(Double.init) { ESCALA = e }
        let solo = arg("--solo")
        let raiz = arg("--fixture") ?? "banco/trazos.json"
        let casos = leerFixture(raiz)
        guard !casos.isEmpty else { print("BANCO_ERROR sin casos en \(raiz)"); return }

        // Polígonos externos, si el script de node ya corrió.
        var web: [String: [String: [Json]]] = [:]
        for motor in ["web-pf", "web-v4"] {
            let r = "\(carpeta)/contornos-\(motor).json"
            guard let d = fm.contents(atPath: r),
                  let j = try? JSONDecoder().decode(Json.self, from: d),
                  let o = j.obj else { continue }
            var m: [String: [Json]] = [:]
            for (k, v) in o { m[k] = v.arr ?? [] }
            web[motor] = m
        }

        var resumen: [String] = ["caso\tlargo\tmotor\tancho_medio\tgeo_ms"]
        for c in casos where solo == nil || c.nombre == solo {
            let mk = marco(c)
            let l = largo(c)
            var linea = String(format: "%-18s %5.0f u", (c.nombre as NSString).utf8String!, l)

            if let ctx = contexto(mk) {
                let ms = pintarSfmap(ctx, c) * 1000
                _ = png(ctx, "\(carpeta)/\(c.nombre).sfmap.png")
                let a = peso(ctx) / l
                linea += String(format: "  sfmap=%.2f (%.2fms)", a, ms)
                resumen.append(String(format: "%@\t%.1f\tsfmap\t%.3f\t%.3f", c.nombre, l, a, ms))
            }
            /*
             * EL BORRADOR Y EL GUARDADO, pintados por los DOS caminos reales.
             *
             * `vivo` = como pinta `PintorExtra.tintaEnVivo`: puntos en
             * coordenadas de MUNDO, sin trasladar la matriz.
             * `guardado` = como pinta `Pintor.tinta`: puntos RELATIVOS al
             * origen del elemento y la posición puesta por la matriz.
             *
             * Son dos rutas de código distintas sobre el mismo motor, y la
             * promesa es que dan el mismo píxel. Dos imágenes lo enseñan; una
             * afirmación, no.
             */
            if let ctx = contexto(mk) {
                for t in c.trazos {
                    let opc = Tinta.Opciones(grosor: t.grosor, marcador: t.marcador)
                    let mundo = t.puntos.map { q -> PuntoTinta in
                        var r = q; r.x += t.x; r.y += t.y; return r
                    }
                    guard let cam = Tinta.camino(mundo, opc) else { continue }
                    ctx.saveGState()
                    ctx.setAlpha(t.marcador ? 0.35 : 1)
                    ctx.setFillColor(t.marcador ? MARCADOR : TINTA)
                    ctx.addPath(cam)
                    ctx.fillPath(using: .winding)
                    ctx.restoreGState()
                }
                _ = png(ctx, "\(carpeta)/\(c.nombre).vivo.png")
            }
            if let ctx = contexto(mk) {
                pintarSfmap(ctx, c)
                _ = png(ctx, "\(carpeta)/\(c.nombre).guardado.png")
            }
            if let ctx = contexto(mk) {
                for t in c.trazos { pintarViejo(ctx, t, t.marcador ? MARCADOR : TINTA) }
                _ = png(ctx, "\(carpeta)/\(c.nombre).viejo.png")
                let a = peso(ctx) / l
                linea += String(format: "  viejo=%.2f", a)
                resumen.append(String(format: "%@\t%.1f\tviejo\t%.3f\t", c.nombre, l, a))
            }
            for motor in ["web-pf", "web-v4"] {
                guard let polis = web[motor]?[c.nombre], let ctx = contexto(mk) else { continue }
                // perfect-freehand se pinta con la cuadrática de punto medio
                // (es lo que hace `freehandOutlinePath`); el ribbon del v4 con
                // `lineTo`, que es lo que hace `drawInk`.
                pintarPoligonos(ctx, c, polis, suave: motor == "web-pf")
                _ = png(ctx, "\(carpeta)/\(c.nombre).\(motor).png")
                let a = peso(ctx) / l
                linea += String(format: "  %@=%.2f", motor, a)
                resumen.append(String(format: "%@\t%.1f\t%@\t%.3f\t", c.nombre, l, motor, a))
            }
            print("BANCO \(linea)")
        }

        let vistos = casos.filter { solo == nil || $0.nombre == solo }
        if let motores = arg("--hoja") {
            hojaDeContacto(carpeta, vistos, motores.split(separator: ",").map(String.init))
        }
        if let par = arg("--ab") {
            componerAB(carpeta, vistos, par, semilla: UInt64(arg("--semilla").flatMap { UInt64($0) } ?? 7))
        }
        print("BANCO_OK \(carpeta) · \(casos.count) casos")
        try? resumen.joined(separator: "\n").write(toFile: "\(carpeta)/resumen.tsv",
                                                   atomically: true, encoding: .utf8)
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: la hoja de contacto (ésta SÍ va rotulada)
    // ════════════════════════════════════════════════════════════════════════

    /// Todos los casos contra todos los motores en una lámina, con nombres.
    /// No es la del crítico —esa va ciega— es la del que construye: mirar 64
    /// PNG de uno en uno es como juzgar una tipografía por una letra.
    static func hojaDeContacto(_ carpeta: String, _ casos: [Caso], _ motores: [String]) {
        let alturaFila = 200.0, etiqueta = 150.0, sep = 8.0, cabeza = 26.0
        struct Fila { var nombre: String; var imgs: [(NSImage, String)] }
        var filas: [Fila] = []
        for c in casos {
            var im: [(NSImage, String)] = []
            for m in motores {
                if let i = NSImage(contentsOfFile: "\(carpeta)/\(c.nombre).\(m).png") { im.append((i, m)) }
            }
            if !im.isEmpty { filas.append(Fila(nombre: c.nombre, imgs: im)) }
        }
        guard !filas.isEmpty else { return }

        // Columna de ANCHO FIJO. Empaquetar cada miniatura a su medida deja las
        // columnas desalineadas y entonces la hoja se lee por filas, que es
        // justo lo contrario de para lo que existe: comparar motores.
        let columna = 340.0
        func ancho(_ i: NSImage) -> Double {
            min(columna, i.size.width * (alturaFila / max(1, i.size.height)))
        }
        let w = etiqueta + Double(motores.count) * (columna + sep)
        let h = cabeza + Double(filas.count) * (alturaFila + sep)

        guard let ctx = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(red: 0.90, green: 0.90, blue: 0.91, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        func texto(_ s: String, _ x: Double, _ y: Double, _ tam: Double, _ peso: NSFont.Weight) {
            let at: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: tam, weight: peso),
                                                     .foregroundColor: NSColor.black]
            let l = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: at))
            ctx.textMatrix = .identity
            ctx.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(l, ctx)
        }

        var y = h - cabeza
        for (k, m) in motores.enumerated() {
            texto(m, etiqueta + Double(k) * (columna + sep) + 4, h - 18, 14, .bold)
        }

        for f in filas {
            y -= alturaFila + sep
            texto(f.nombre, 6, y + alturaFila / 2, 13, .semibold)
            for (k, par) in f.imgs.enumerated() {
                let x = etiqueta + Double(k) * (columna + sep)
                let a = ancho(par.0)
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: columna, height: alturaFila))
                if let cg = par.0.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    ctx.draw(cg, in: CGRect(x: x + (columna - a) / 2, y: y, width: a, height: alturaFila))
                }
            }
        }
        _ = png(ctx, "\(carpeta)/hoja.png")
        print("BANCO_HOJA \(carpeta)/hoja.png · \(filas.count) filas × \(motores.count) motores")
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: el A/B ciego
    // ════════════════════════════════════════════════════════════════════════

    /**
     * Dos motores, misma lámina, etiquetas A y B — y el lado lo decide una
     * moneda con semilla. La clave se guarda en un archivo APARTE.
     *
     * Que la clave no esté en la imagen no es ceremonia: un crítico que puede
     * deducir cuál es el nuestro deja de ser un crítico y pasa a ser un
     * espejo, y un espejo siempre dice que vamos bien.
     */
    static func componerAB(_ carpeta: String, _ casos: [Caso], _ par: String, semilla: UInt64) {
        let ms = par.split(separator: ",").map(String.init)
        guard ms.count == 2 else { print("BANCO_ERROR --ab pide dos motores"); return }
        var estado = semilla &* 6364136223846793005 &+ 1442695040888963407
        func moneda() -> Bool {
            estado = estado &* 6364136223846793005 &+ 1442695040888963407
            return (estado >> 33) & 1 == 1
        }
        var clave: [String] = []
        for c in casos {
            let a = "\(carpeta)/\(c.nombre).\(ms[0]).png"
            let b = "\(carpeta)/\(c.nombre).\(ms[1]).png"
            guard let ia = NSImage(contentsOfFile: a), let ib = NSImage(contentsOfFile: b) else { continue }
            let volteado = moneda()
            let izq = volteado ? ib : ia, der = volteado ? ia : ib
            let mIzq = volteado ? ms[1] : ms[0], mDer = volteado ? ms[0] : ms[1]

            let sep = 26.0, banda = 34.0
            let w = izq.size.width + der.size.width + sep
            let h = max(izq.size.height, der.size.height) + banda
            guard let ctx = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { continue }
            ctx.setFillColor(CGColor(red: 0.93, green: 0.93, blue: 0.94, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            func poner(_ img: NSImage, _ x: Double) {
                guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                ctx.draw(cg, in: CGRect(x: x, y: 0, width: img.size.width, height: img.size.height))
            }
            poner(izq, 0)
            poner(der, izq.size.width + sep)
            // Las etiquetas, arriba, en el mismo sitio siempre.
            let fuente = NSFont.systemFont(ofSize: 20, weight: .semibold)
            for (txt, x) in [("A", izq.size.width / 2), ("B", izq.size.width + sep + der.size.width / 2)] {
                let at: [NSAttributedString.Key: Any] = [.font: fuente, .foregroundColor: NSColor.black]
                let s = NSAttributedString(string: txt, attributes: at)
                let l = CTLineCreateWithAttributedString(s)
                ctx.textMatrix = .identity
                ctx.textPosition = CGPoint(x: x - 6, y: h - 25)
                CTLineDraw(l, ctx)
            }
            _ = png(ctx, "\(carpeta)/\(c.nombre).ab.png")
            clave.append("\(c.nombre)\tA=\(mIzq)\tB=\(mDer)")
        }
        try? clave.joined(separator: "\n").write(toFile: "\(carpeta)/ab-clave.tsv",
                                                 atomically: true, encoding: .utf8)
        print("BANCO_AB \(clave.count) laminas · clave en \(carpeta)/ab-clave.tsv")
    }
}
