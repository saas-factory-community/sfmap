import AppKit
import CoreText
import CoreGraphics

/// Imagenes del lienzo, cargadas una vez.
///
/// Sin cache, cada fotograma decodifica el PNG entero: con tres capturas en el
/// lienzo, mover el raton se vuelve una presentacion de diapositivas.
enum Imagenes {
    private static var cache: [String: NSImage] = [:]
    private static var fallidas: Set<String> = []

    /// La imagen, o nil si todavia no esta. `alLlegar` repinta cuando llegue.
    static func de(_ src: String, alLlegar: @escaping () -> Void) -> NSImage? {
        if let i = cache[src] { return i }
        if fallidas.contains(src) { return nil }
        if src.hasPrefix("data:") {
            guard let coma = src.firstIndex(of: ","),
                  let d = Data(base64Encoded: String(src[src.index(after: coma)...])),
                  let img = NSImage(data: d) else { fallidas.insert(src); return nil }
            cache[src] = img
            return img
        }
        /*
         * RUTA LOCAL. `URL(string: "/Users/…")` produce una URL sin esquema y
         * `URLSession` la rechaza en silencio: el marco de espera se quedaba
         * para siempre y parecia que "las imagenes no cargan". Una ruta de
         * disco se lee de disco, sincrona (es una vez: el cache la retiene).
         */
        if src.hasPrefix("/") || src.hasPrefix("~") || src.hasPrefix("file:") {
            let ruta = src.hasPrefix("file:")
                ? (URL(string: src)?.path ?? src)
                : NSString(string: src).expandingTildeInPath
            guard let img = NSImage(contentsOfFile: ruta) else { fallidas.insert(src); return nil }
            cache[src] = img
            return img
        }
        guard let url = URL(string: src) else { fallidas.insert(src); return nil }
        fallidas.insert(src)   // no se pide dos veces mientras viaja
        URLSession.shared.dataTask(with: url) { d, _, _ in
            guard let d, let img = NSImage(data: d) else { return }
            DispatchQueue.main.async {
                cache[src] = img
                fallidas.remove(src)
                alLlegar()
            }
        }.resume()
        return nil
    }
}

extension Pintor {

    // ── tabla ───────────────────────────────────────────────────────────────

    /// Tabla con los anchos de columna MEDIDOS que trae el modelo.
    ///
    /// El v3 los calculaba en tres sitios y el motor los IGNORABA, repartiendo
    /// el ancho en partes iguales: datos calculados con esfuerzo que nadie leia.
    func tabla(_ e: Elemento) {
        let filas = e.crudo["cells"]?.arr ?? []
        guard !filas.isEmpty else { return }
        var anchos = e.crudo["colWidths"]?.arr?.compactMap(\.num) ?? []
        let cols = filas.map { $0.arr?.count ?? 0 }.max() ?? 1
        if anchos.count < cols {
            // Sin anchos, reparto parejo. Es el peor caso, no el default.
            anchos = Array(repeating: e.ancho / Double(cols), count: cols)
        }
        let escala = e.ancho / max(1, anchos.reduce(0, +))
        let altoFila = e.crudo["rowHeight"]?.num ?? (e.alto / Double(filas.count))
        let encabezado = e.crudo["headerRow"]?.b ?? false
        let est = e.estilo

        ctx.saveGState()
        ctx.setAlpha(e.opacidad)
        let camino = CGMutablePath()
        camino.addRoundedRect(in: e.caja, cornerWidth: 8, cornerHeight: 8)
        ctx.addPath(camino)
        ctx.setFillColor(tema.rol("card").relleno.cgColor)
        ctx.fillPath()
        if encabezado {
            ctx.saveGState()
            ctx.addPath(camino); ctx.clip()
            ctx.setFillColor(tema.rol("sticky").relleno.cgColor)
            ctx.fill(CGRect(x: e.x, y: e.y, width: e.ancho, height: altoFila))
            ctx.restoreGState()
        }
        ctx.setStrokeColor(tema.rol("card").trazo.color.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [])
        for i in 1..<max(1, filas.count) {
            let y = e.y + Double(i) * altoFila
            ctx.move(to: CGPoint(x: e.x, y: y)); ctx.addLine(to: CGPoint(x: e.x + e.ancho, y: y))
        }
        var x = e.x
        for i in 0..<max(0, cols - 1) {
            x += anchos[i] * escala
            ctx.move(to: CGPoint(x: x, y: e.y)); ctx.addLine(to: CGPoint(x: x, y: e.y + e.alto))
        }
        ctx.strokePath()
        ctx.addPath(camino); ctx.strokePath()

        for (f, fila) in filas.enumerated() {
            var cx = e.x
            for (c, celda) in (fila.arr ?? []).enumerated() {
                let w = (c < anchos.count ? anchos[c] : 0) * escala
                var estilo = est
                if encabezado && f == 0 { estilo.peso = 800 }
                let color = (encabezado && f == 0) ? tema.tituloTexto : tema.cuerpoTexto
                renglon(celda.s ?? "", estilo, color,
                        x: cx + 12, y: e.y + Double(f) * altoFila + altoFila / 2 + estilo.tamano * 0.35,
                        ancho: w - 24, alinea: "left")
                cx += w
            }
        }
        ctx.restoreGState()
    }

    // ── codigo ──────────────────────────────────────────────────────────────

    /// Bloque de codigo. Sin resaltado de sintaxis, y se DICE por que: pintar
    /// medio resaltado (comillas si, tipos no) es peor que ninguno — dice que el
    /// lienzo entiende el lenguaje cuando no lo entiende.
    func codigo(_ e: Elemento) {
        ctx.saveGState()
        ctx.setAlpha(e.opacidad)
        let camino = CGMutablePath()
        camino.addRoundedRect(in: e.caja, cornerWidth: 8, cornerHeight: 8)
        ctx.addPath(camino)
        ctx.setFillColor(tema.rol("sticky").relleno.cgColor)
        ctx.fillPath()
        ctx.addPath(camino)
        ctx.setStrokeColor(tema.rol("card").trazo.color.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.strokePath()
        var est = e.estilo
        est.familia = "jetbrains-mono"
        let alto = est.tamano * 1.5
        ctx.saveGState()
        ctx.addPath(camino); ctx.clip()
        for (i, l) in (e.crudo["code"]?.s ?? "").components(separatedBy: "\n").enumerated() {
            renglon(l, est, tema.cuerpoTexto,
                    x: e.x + 14, y: e.y + 18 + Double(i) * alto + est.tamano * 0.8,
                    ancho: e.ancho - 28, alinea: "left")
        }
        ctx.restoreGState()
        if let lang = e.crudo["language"]?.s, !lang.isEmpty {
            var chico = EstiloTexto(); chico.peso = 700; chico.tamano = 10
            renglon(lang.uppercased(), chico, tema.pieTexto,
                    x: e.x + e.ancho - 60, y: e.y + 14, ancho: 48, alinea: "right")
        }
        ctx.restoreGState()
    }

    // ── imagen y embed ──────────────────────────────────────────────────────

    func imagen(_ e: Elemento, alLlegar: @escaping () -> Void) {
        ctx.saveGState()
        ctx.setAlpha(e.opacidad)
        let camino = CGMutablePath()
        camino.addRoundedRect(in: e.caja, cornerWidth: 6, cornerHeight: 6)
        // ⚡ De lejos (menos de `lodImagenPx` de ancho en pantalla) un bitmap se
        // reescala entero en cada cuadro para ocupar una mancha: se pinta la
        // mancha y ya. Al acercarse vuelve la imagen real.
        if !Pintor.sinLOD && e.ancho * camara.zoom < Pintor.lodImagenPx {
            Pintor.omitidosCuadro += 1
            ctx.addPath(camino)
            ctx.setFillColor(tema.rol("sticky").relleno.withAlphaComponent(0.6).cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            return
        }
        if let src = e.crudo["src"]?.s, let img = Imagenes.de(src, alLlegar: alLlegar),
           var cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            // EL RECORTE NO TOCA EL ARCHIVO: es una fracción guardada en el
            // elemento y se aplica aquí, al pintar. Ver `Recorte.swift`.
            let crop = Recorte.de(e)
            if crop != CGRect(x: 0, y: 0, width: 1, height: 1),
               let r = cg.cropping(to: Recorte.enPixeles(crop, ancho: cg.width, alto: cg.height)) {
                cg = r
            }
            ctx.saveGState()
            ctx.addPath(camino); ctx.clip()
            // La Y del lienzo va hacia abajo: la imagen se voltea sobre su
            // propia caja o sale del reves.
            ctx.translateBy(x: e.x, y: e.y + e.alto)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: e.ancho, height: e.alto))
            ctx.restoreGState()
        } else {
            // Marco de espera. Un hueco invisible se lee como que la imagen se
            // perdio; un marco dice "esta viniendo".
            ctx.addPath(camino)
            ctx.setFillColor(tema.rol("sticky").relleno.cgColor)
            ctx.fillPath()
            ctx.addPath(camino)
            ctx.setStrokeColor(tema.rol("card").trazo.color.cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.strokePath()
            var chico = EstiloTexto(); chico.peso = 600; chico.tamano = 12
            renglon(e.crudo["alt"]?.s ?? "imagen", chico, tema.pieTexto,
                    x: e.x, y: e.y + e.alto / 2, ancho: e.ancho, alinea: "center")
        }
        ctx.restoreGState()
        // Una miniatura de VIDEO se anuncia como tal. Sin el velo es idéntica a
        // una captura de pantalla, y nadie pulsa lo que no promete nada.
        veloVideo(e)
        if e.enlace != nil { marcaDestino(e) }
    }

    /// Un embed se pinta como TARJETA con su direccion, no como una web viva.
    ///
    /// Meter un WKWebView por elemento seria un proceso por tarjeta, y la
    /// primera vez que el lienzo tenga diez, la app deja de abrir en un
    /// segundo. La direccion se abre en el navegador de verdad con ⌘+clic, que
    /// es donde una pagina se lee bien.
    func embed(_ e: Elemento) {
        if let ruta = EmbedHTML.ruta(e) {
            ctx.saveGState()
            ctx.setAlpha(e.opacidad)
            ctx.setFillColor(tema.rol("card").relleno.cgColor)
            ctx.fill(e.caja)
            let cab = e.ancho * Double(EmbedHTML.cabecera / EmbedHTML.anchoLogico)
            if let imagen = PreviewHTML.imagen(ruta), let cg = imagen.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.saveGState()
                ctx.translateBy(x: e.x, y: e.y + e.alto)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: e.ancho, height: max(1, e.alto - cab)))
                ctx.restoreGState()
            } else {
                var ayuda = EstiloTexto(); ayuda.tamano = e.ancho * 0.017
                renglon("Cargando HTML…", ayuda, tema.pieTexto, x: e.x, y: e.y + e.alto / 2,
                        ancho: e.ancho, alinea: "center")
            }
            var est = EstiloTexto(); est.peso = 700; est.tamano = e.ancho * 0.0125
            renglon(e.crudo["name"]?.s ?? "HTML interactivo", est, tema.tituloTexto,
                    x: e.x + cab / 3, y: e.y + cab * 0.65, ancho: e.ancho - cab, alinea: "left")
            ctx.setStrokeColor(tema.reticula.cgColor); ctx.setLineWidth(2); ctx.stroke(e.caja)
            ctx.restoreGState()
            return
        }
        ctx.saveGState()
        ctx.setAlpha(e.opacidad)
        let camino = CGMutablePath()
        camino.addRoundedRect(in: e.caja, cornerWidth: 10, cornerHeight: 10)
        ctx.addPath(camino)
        ctx.setFillColor(tema.rol("card").relleno.cgColor)
        ctx.fillPath()
        ctx.addPath(camino)
        ctx.setStrokeColor(tema.rol("card").trazo.color.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.strokePath()
        ctx.setFillColor(tema.rol("sticky").relleno.cgColor)
        ctx.saveGState(); ctx.addPath(camino); ctx.clip()
        ctx.fill(CGRect(x: e.x, y: e.y, width: e.ancho, height: 30))
        ctx.restoreGState()
        for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            ctx.setFillColor(c.withAlphaComponent(0.85).cgColor)
            ctx.fillEllipse(in: CGRect(x: e.x + 12 + Double(i) * 14, y: e.y + 12, width: 7, height: 7))
        }
        var est = EstiloTexto(); est.peso = 600; est.tamano = 12
        renglon(e.crudo["url"]?.s ?? "", est, tema.pieTexto,
                x: e.x + 56, y: e.y + 20, ancho: e.ancho - 68, alinea: "left")
        var grande = EstiloTexto(); grande.peso = 600; grande.tamano = 13
        renglon("⌘ + clic para abrirlo", grande, tema.pieTexto,
                x: e.x, y: e.y + e.alto / 2 + 20, ancho: e.ancho, alinea: "center")
        ctx.restoreGState()
    }

    /// Un renglon suelto, con la misma cocina de CoreText que el texto ligado.
    func renglon(_ texto: String, _ est: EstiloTexto, _ color: NSColor,
                 x: Double, y: Double, ancho: Double, alinea: String) {
        guard !texto.isEmpty else { return }
        let f = Fuentes.fuente(familia: est.familia, peso: est.peso, tamano: est.tamano, cursiva: est.cursiva)
        var attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color]
        if let k = est.espaciado, k != 0 { attrs[.kern] = k }
        let linea = CTLineCreateWithAttributedString(NSAttributedString(string: texto, attributes: attrs))
        let w = Double(CTLineGetTypographicBounds(linea, nil, nil, nil))
        let px: Double = switch alinea {
            case "center": x + (ancho - w) / 2
            case "right": x + ancho - w
            default: x
        }
        ctx.saveGState()
        ctx.translateBy(x: px, y: y)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        ctx.textPosition = .zero
        CTLineDraw(linea, ctx)
        ctx.restoreGState()
    }

    // ── superposiciones ─────────────────────────────────────────────────────

    /// Las manijas de redimension y el tirador de giro.
    ///
    /// Su tamaño se mide en px de PANTALLA: una manija que encoge al alejarse se
    /// vuelve imposible de agarrar justo cuando mas falta hace.
    func manijas(_ r: CGRect, texto: Bool = false) {
        let z = camara.zoom
        let lado = (texto ? 6 : Geo.MANIJA_PX) / z
        ctx.setLineWidth((texto ? 1 : 1.5) / z)
        ctx.setLineDash(phase: 0, lengths: [])
        if !texto {
            // El tirador de giro: una linea corta y un circulo, arriba del centro.
            let g = Geo.centroGiro(r, zoom: z)
            ctx.setStrokeColor(tema.seleccion.cgColor)
            ctx.move(to: CGPoint(x: r.midX, y: r.minY))
            ctx.addLine(to: CGPoint(x: g.x, y: g.y + lado / 2))
            ctx.strokePath()
            ctx.setFillColor(tema.rol("card").relleno.cgColor)
            let cg = CGRect(x: g.x - lado / 2, y: g.y - lado / 2, width: lado, height: lado)
            ctx.fillEllipse(in: cg); ctx.strokeEllipse(in: cg)

        }

        for h in Geo.MANIJAS where !texto || !["n", "s"].contains(h) {
            let c = Geo.centroManija(r, h)
            let caja = CGRect(x: c.x - lado / 2, y: c.y - lado / 2, width: lado, height: lado)
            let camino = CGMutablePath()
            if texto { camino.addEllipse(in: caja) }
            else { camino.addRoundedRect(in: caja, cornerWidth: 2 / z, cornerHeight: 2 / z) }
            ctx.addPath(camino); ctx.setFillColor(tema.rol("card").relleno.cgColor); ctx.fillPath()
            ctx.addPath(camino); ctx.setStrokeColor((texto ? tema.cuerpoTexto.withAlphaComponent(0.45) : tema.seleccion).cgColor); ctx.strokePath()
        }
    }

    /**
     * LA FLECHITA DE GIRO, en la esquina que tiene el puntero encima.
     *
     * Se pinta UNA, la de la esquina apuntada, y no las cuatro: cuatro simbolos
     * permanentes alrededor de cada figura seleccionada es exactamente el ruido
     * que hace que una pizarra se sienta cargada. Aparece donde miras.
     */
    func flechaGiro(_ r: CGRect, _ esquina: String) {
        let z = camara.zoom
        let c = Geo.centroManija(r, esquina)
        let sx: Double = (esquina == "nw" || esquina == "sw") ? -1 : 1
        let sy: Double = (esquina == "nw" || esquina == "ne") ? -1 : 1
        let centro = CGPoint(x: c.x + sx * 13 / z, y: c.y + sy * 13 / z)
        let radio = 6.0 / z
        ctx.setLineWidth(1.8 / z)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setStrokeColor(tema.seleccion.cgColor)
        ctx.setLineCap(.round)
        ctx.addArc(center: centro, radius: radio, startAngle: 0.5, endAngle: 5.3, clockwise: false)
        ctx.strokePath()
        // La punta, al final del arco: sin ella es un circulo roto, no un giro.
        let fin = CGPoint(x: centro.x + cos(5.3) * radio, y: centro.y + sin(5.3) * radio)
        let a = 5.3 - .pi / 2   // tangente
        let l = 4.0 / z
        ctx.move(to: CGPoint(x: fin.x + cos(a + 0.5) * l, y: fin.y + sin(a + 0.5) * l))
        ctx.addLine(to: fin)
        ctx.addLine(to: CGPoint(x: fin.x + cos(a - 2.2) * l, y: fin.y + sin(a - 2.2) * l))
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    /// Los cuatro puertos de conexion, FUERA del borde.
    ///
    /// Encima competirian con las manijas y con el clic de seleccion; ese margen
    /// de aire es justo lo que hace que la mano entienda que el gesto SALE del
    /// elemento en vez de editarlo.
    func puertos(_ e: Elemento, activo: String?) {
        let z = camara.zoom
        let r = Geo.PUERTO_R_PX / z
        ctx.setLineWidth(1.6 / z)
        ctx.setLineDash(phase: 0, lengths: [])
        for (id, p) in Geo.puertosDe(e, zoom: z) {
            let caja = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            let encendido = id == activo
            ctx.setFillColor((encendido ? tema.acento : tema.rol("card").relleno).cgColor)
            ctx.fillEllipse(in: encendido ? caja.insetBy(dx: -r * 0.35, dy: -r * 0.35) : caja)
            ctx.setStrokeColor(tema.acento.cgColor)
            ctx.strokeEllipse(in: encendido ? caja.insetBy(dx: -r * 0.35, dy: -r * 0.35) : caja)
        }
    }

    /**
     * Los extremos de una flecha seleccionada, agarrables.
     *
     * Se pintan RELLENOS del color de acento —no huecos como los puertos— para
     * que se lean como "esto ya esta conectado y lo puedes mover", en vez de
     * "aqui podrias conectar algo".
     */
    func extremos(_ e: Elemento, agarrado: String? = nil) {
        let z = camara.zoom
        let r = Geo.EXTREMO_R_PX / z
        ctx.setLineWidth(2 / z)
        ctx.setLineDash(phase: 0, lengths: [])
        for (cual, p) in Geo.extremosDe(e) {
            let vivo = cual == agarrado
            let caja = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                .insetBy(dx: vivo ? -r * 0.3 : 0, dy: vivo ? -r * 0.3 : 0)
            ctx.setFillColor(tema.rol("card").relleno.cgColor)
            ctx.fillEllipse(in: caja)
            ctx.setStrokeColor(tema.acento.cgColor)
            ctx.strokeEllipse(in: caja)
            ctx.setFillColor(tema.acento.cgColor)
            ctx.fillEllipse(in: caja.insetBy(dx: r * 0.45, dy: r * 0.45))
        }
    }

    /// El rectangulo de seleccion por arrastre.
    /**
     * EL OBJETIVO de una conexión en curso, resaltado.
     *
     * Sin esto, apuntar es a ciegas: la única señal era que el fantasma
     * desaparecía, y eso se nota cuando ya soltaste. Un halo sobre la pieza a la
     * que vas a engancharte dice "aquí sí" ANTES de comprometerte, que es
     * cuando sirve.
     */
    func resaltarObjetivo(_ e: Elemento) {
        let r = e.cajaVisual.insetBy(dx: -6 / camara.zoom, dy: -6 / camara.zoom)
        let camino = CGMutablePath()
        let radio = 10 / camara.zoom
        camino.addRoundedRect(in: r, cornerWidth: radio, cornerHeight: radio)
        ctx.addPath(camino)
        ctx.setFillColor(tema.acento.withAlphaComponent(0.10).cgColor)
        ctx.fillPath()
        ctx.addPath(camino)
        ctx.setStrokeColor(tema.acento.cgColor)
        ctx.setLineWidth(2.5 / camara.zoom)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.strokePath()
    }

    /// Los codos que la mano puso en un conector.
    ///
    /// Se PINTAN, y no es decoración: un punto que se puede agarrar y no se ve
    /// es una capacidad que nadie descubre. El campo `waypoints` existía en el
    /// modelo del lienzo web, el router lo respetaba, y nada lo producía ni lo
    /// dibujaba nunca.
    func codos(_ pts: [CGPoint]) {
        guard !pts.isEmpty else { return }
        let r = 4.5 / camara.zoom
        ctx.setLineWidth(1.5 / camara.zoom)
        ctx.setLineDash(phase: 0, lengths: [])
        for p in pts {
            let caja = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            ctx.setFillColor(tema.rol("card").relleno.cgColor)
            ctx.fillEllipse(in: caja)
            ctx.setStrokeColor(tema.acento.cgColor)
            ctx.strokeEllipse(in: caja)
        }
    }

    func marco(_ r: CGRect) {
        ctx.setFillColor(tema.acento.withAlphaComponent(0.10).cgColor)
        ctx.fill(r)
        ctx.setStrokeColor(tema.acento.cgColor)
        ctx.setLineWidth(1 / camara.zoom)
        ctx.setLineDash(phase: 0, lengths: [4 / camara.zoom, 3 / camara.zoom])
        ctx.stroke(r)
        ctx.setLineDash(phase: 0, lengths: [])
    }

    /// La figura que se esta dibujando, mientras se arrastra.
    func fantasma(_ figura: String, _ r: CGRect, punteado: Bool = true) {
        let camino = caminoFigura(figura, r, radio: 12)
        ctx.setFillColor(tema.acento.withAlphaComponent(0.07).cgColor)
        ctx.addPath(camino); ctx.fillPath()
        ctx.setStrokeColor(tema.acento.cgColor)
        ctx.setLineWidth(1.5 / camara.zoom)
        if punteado { ctx.setLineDash(phase: 0, lengths: [6 / camara.zoom, 4 / camara.zoom]) }
        ctx.addPath(camino); ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
    }

    /// Las guias de alineacion. La guia y el iman van juntos: imantar sin
    /// mostrarla se siente embrujado, y mostrarla sin imantar es decorativo.
    func guias(_ gs: [Geo.Guia]) {
        ctx.setStrokeColor(NSColor(hex: "#ff2d95")!.cgColor)
        ctx.setLineWidth(1 / camara.zoom)
        ctx.setLineDash(phase: 0, lengths: [])
        for g in gs {
            if g.eje == "x" {
                ctx.move(to: CGPoint(x: g.valor, y: g.desde)); ctx.addLine(to: CGPoint(x: g.valor, y: g.hasta))
            } else {
                ctx.move(to: CGPoint(x: g.desde, y: g.valor)); ctx.addLine(to: CGPoint(x: g.hasta, y: g.valor))
            }
        }
        ctx.strokePath()
    }

    /// La flecha en curso mientras se arrastra desde un puerto.
    func conectando(_ desde: CGPoint, _ hasta: CGPoint, sobre: Bool) {
        ctx.setStrokeColor(tema.acento.cgColor)
        ctx.setLineWidth(2 / camara.zoom)
        ctx.setLineDash(phase: 0, lengths: sobre ? [] : [6 / camara.zoom, 4 / camara.zoom])
        ctx.move(to: desde); ctx.addLine(to: hasta)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        let ang = atan2(hasta.y - desde.y, hasta.x - desde.x)
        let l = 10 / camara.zoom, w = 5.5 / camara.zoom
        ctx.setFillColor(tema.acento.cgColor)
        ctx.move(to: hasta)
        ctx.addLine(to: CGPoint(x: hasta.x - cos(ang) * l - sin(ang) * w, y: hasta.y - sin(ang) * l + cos(ang) * w))
        ctx.addLine(to: CGPoint(x: hasta.x - cos(ang) * l + sin(ang) * w, y: hasta.y - sin(ang) * l - cos(ang) * w))
        ctx.closePath(); ctx.fillPath()
    }

    /// El trazo que se esta dibujando ahora mismo, antes de existir como
    /// elemento. Sin esto el lapiz no pinta hasta que sueltas, que se siente
    /// como que la app se congelo.
    ///
    /// ⚠️ LLAMA AL MISMO MOTOR QUE EL TRAZO GUARDADO, con las mismas opciones y
    /// SIN ningún modo "en vivo". El referente web tiene uno (`last: !live`) y
    /// con él el borrador y el resultado son dos dibujos distintos; aquí la
    /// divergencia no se vigila, no existe: el motor es una función pura de los
    /// puntos y estos son los mismos puntos que se van a guardar.
    func tintaEnVivo(_ pts: [PuntoTinta], color: NSColor, grosor: Double, marcador: Bool) {
        guard let cam = Tinta.camino(pts, Tinta.Opciones(grosor: grosor, marcador: marcador))
        else { return }
        ctx.saveGState()
        ctx.setAlpha(marcador ? 0.35 : 1)
        ctx.setFillColor(color.cgColor)
        ctx.addPath(cam)
        ctx.fillPath(using: .winding)
        ctx.restoreGState()
    }
}
