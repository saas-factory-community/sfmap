import AppKit
import CoreText
import CoreGraphics

/// El pintor: documento → píxeles, en CoreGraphics.
///
/// POR QUÉ NO ES UN NAVEGADOR. El lienzo web pinta bien, pero cada gesto cruza
/// el bucle de eventos del navegador, React y el recolector de basura antes de
/// llegar al frame. Aquí un `NSEvent` toca la cámara y el frame siguiente ya
/// salió: no hay capa intermedia donde pueda meterse una pausa.
///
/// Y NO ES METAL a propósito. Se decidió creyendo que el cuello era la
/// composición de texto, que CoreText resuelve en la CPU de cualquier forma.
///
/// ⚠️ ESA CREENCIA ESTÁ MEDIDA Y ERA FALSA (26 ago 2026, `--medir` sobre el
/// lienzo 01, 129 elementos, fotograma de 21.5 ms con presupuesto de 8.3):
///
///     suelo de AppKit ....  1.8 ms
///     retícula de puntos .  9.5 ms   ← 45%
///     elementos .........   9.6 ms   ← 45%, y de esos:
///         · texto ........  0.27 ms
///         · sombras ......  0.32 ms
///
/// El texto es RUIDO. El fotograma se va en RELLENO DE PÍXELES —la retícula y
/// las áreas grandes de islas y tarjetas—, que es justo el eje donde Metal
/// gana. El coste tampoco escala con el número de elementos (27 elementos
/// cuestan lo mismo que 129: lo que manda es el área cubierta).
///
/// Así que la condición que este comentario dejaba escrita —*"si algún día el
/// cuello se MIDE en rasterizado, se cambia"*— ya se cumplió. Mientras el
/// cambio no se haga, el paliativo es no pintar lo que no aporta: el modo clase
/// (`F5`) apaga la retícula y baja el fotograma a 12 ms.
struct Pintor {
    let ctx: CGContext
    let tema: Tema
    let camara: Camara
    let tamano: CGSize
    /// EL DÍA, ya leído. Se entrega al pintor en vez de que el pintor pregunte:
    /// un fotograma no puede depender de lo que tarde un servidor. Por defecto
    /// va vacío, y un widget sin lectura lo DICE en pantalla.
    var dia = EstadoDia()

    /// Apaga las sombras. Sirve para MEDIR cuánto cuestan (`--medir`) y para
    /// que el arrastre pueda abaratarse si algún día hace falta. Estático
    /// porque el pintor se crea de nuevo en cada fotograma.
    static var sinSombras = false
    /// Igual que `sinSombras`, para medir cuánto del fotograma es COMPONER
    /// TEXTO (CoreText rehace la maqueta en cada pintado).
    static var sinTexto = false

    /*
     * ⚡ NIVEL DE DETALLE (5 sep 2026). De lejos, un renglón de 20 pt mide UN píxel:
     * componerlo con CoreText cuesta lo mismo que de cerca y nadie lo lee. Bajo
     * `lodTextoPx` (píxeles de PANTALLA por tamaño de letra) el renglón se pinta
     * como una barra tenue de su ancho —la silueta del párrafo sobrevive, el
     * coste no—. Medido en «El Ecosistema» (900 elementos, zoom 0.06): el
     * fotograma de vista general era el único que seguía lento tras el recorte
     * por viewport, porque a ese zoom TODO está a la vista.
     *
     * `sinLOD` lo apagan `--export` y `--foto`: un PNG se mira de cerca aunque
     * se pinte con la cámara lejos. `omitidosCuadro` es el sensor: la prueba
     * cuenta renglones omitidos, no supone.
     */
    static var lodTextoPx: Double = 2.6
    static var lodImagenPx: Double = 28
    static var sinLOD = false
    static var omitidosCuadro = 0

    /// ¿Se lee un renglón de este tamaño con esta cámara?
    func legible(_ tamano: Double) -> Bool {
        Pintor.sinLOD || tamano * camara.zoom >= Pintor.lodTextoPx
    }

    /// La silueta de un párrafo que no se lee: una barra por renglón, al ancho
    /// aproximado del texto, con el color del texto muy atenuado.
    private func silueta(_ lineas: [String], x izq: Double, y arriba: Double, ancho: Double,
                         lineH: Double, tamano: Double, color: NSColor, alinea: String) {
        Pintor.omitidosCuadro += lineas.count
        ctx.saveGState()
        ctx.setFillColor(color.withAlphaComponent(0.28).cgColor)
        for (i, linea) in lineas.enumerated() {
            let w = min(ancho, Double(linea.count) * tamano * 0.52)
            let x: Double = switch alinea {
                case "center": izq + (ancho - w) / 2
                case "right":  izq + ancho - w
                default:       izq
            }
            ctx.fill(CGRect(x: x, y: arriba + Double(i) * lineH + tamano * 0.25,
                            width: w, height: tamano * 0.5))
        }
        ctx.restoreGState()
    }

    /// Mundo → pantalla. Igual que `worldToScreen` del lienzo web.
    func aPantalla(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - camara.x) * camara.zoom + tamano.width / 2,
                y: (p.y - camara.y) * camara.zoom + tamano.height / 2)
    }

    func aplicarCamara() {
        // El lienzo trabaja en coordenadas de MUNDO y con la Y hacia abajo, como
        // el canvas del navegador. AppKit tiene la Y hacia arriba, así que la
        // vista se voltea una vez aquí en vez de invertir cada cálculo — mezclar
        // los dos convenios es una fuente inagotable de "está al revés".
        ctx.translateBy(x: tamano.width / 2, y: tamano.height / 2)
        ctx.scaleBy(x: camara.zoom, y: camara.zoom)
        ctx.translateBy(x: -camara.x, y: -camara.y)
    }

    // ── fondo ───────────────────────────────────────────────────────────────
    /** Paso base en unidades de mundo. */
    static let PASO_BASE = 20.0
    /** Por debajo de esto en pantalla, la retícula estorba en vez de orientar. */
    static let MIN_PX = 14.0

    /// El paso de mundo que toca a este zoom, saltando en potencias de 2.
    ///
    /// ⚠️ Portado del referente. La version anterior usaba un paso FIJO de 24 y
    /// se rendia por debajo de zoom 0.32: alejarte apagaba el fondo entero justo
    /// cuando mas falta hace saber donde estas. Con el paso adaptativo la
    /// retícula nunca desaparece, se hace mas grande.
    static func pasoParaZoom(_ zoom: Double) -> Double {
        var paso = PASO_BASE
        while paso * zoom < MIN_PX { paso *= 2 }
        while paso * zoom > MIN_PX * 4 && paso > 1 { paso /= 2 }
        return paso
    }

    func fondo(puntos: Bool, cuadricula: Bool = false) {
        ctx.setFillColor(tema.lienzo.cgColor)
        ctx.fill(CGRect(origin: .zero, size: tamano))
        guard puntos else { return }
        // La retícula se dibuja en PANTALLA, no en mundo: así el punto mide
        // siempre lo mismo y no se convierte en una mancha al alejar.
        let paso = Self.pasoParaZoom(camara.zoom) * camara.zoom
        let ox = tamano.width / 2 - camara.x * camara.zoom
        let oy = tamano.height / 2 - camara.y * camara.zoom
        let x0 = ox - (ox / paso).rounded(.up) * paso
        let y0 = oy - (oy / paso).rounded(.up) * paso
        if cuadricula {
            // La cuadrícula se pinta MÁS TENUE que los puntos: son muchas más
            // líneas cubriendo el mismo lienzo, y al mismo tono la superficie
            // deja de ser fondo y compite con el dibujo.
            ctx.setStrokeColor(tema.reticula.withAlphaComponent(0.75).cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [])
            var x = x0
            while x < tamano.width + paso {
                ctx.move(to: CGPoint(x: x.rounded() + 0.5, y: 0))
                ctx.addLine(to: CGPoint(x: x.rounded() + 0.5, y: tamano.height))
                x += paso
            }
            var y = y0
            while y < tamano.height + paso {
                ctx.move(to: CGPoint(x: 0, y: y.rounded() + 0.5))
                ctx.addLine(to: CGPoint(x: tamano.width, y: y.rounded() + 0.5))
                y += paso
            }
            ctx.strokePath()
            return
        }
        /*
         * ⚠️ 1.1 ES EL RADIO, NO EL DIAMETRO.
         *
         * El referente dibuja `arc(x, y, 1.1, …)` —un punto de 2.2 px de ancho—
         * y aqui se paso ese 1.1 (redondeado a 1.0) como el ANCHO del ovalo. El
         * punto salia a menos de la mitad de area, en un gris de #eeeef1 sobre
         * blanco: sobre papel es un punto, en pantalla es nada. Daniel: *"el
         * board de puntos no funciona, se ve blanco"*. No estaba apagado: estaba
         * pintado a la mitad de tamaño.
         */
        /*
         * ⚠️ ESTE BUCLE «INGENUO» ES EL MÁS RÁPIDO DE LOS CUATRO PROBADOS
         * (26 ago 2026, medido con `--medir` en el lienzo 01 / el lab):
         *
         *   · `fillEllipse` suelto, esto ............ 9.5 / 4.2 ms  ← se queda
         *   · un `CGMutablePath` con las ~5.000 .... 49.3 / 24.9 ms
         *   · mosaico `draw(_:byTiling:)` .......... 7.5 / 7.6 ms
         *   · `CGLayer` cacheado y desplazado ..... 10.7 / 6.5 ms
         *
         * Las dos últimas ganan en la página densa y PIERDEN en la de paso
         * grande, porque su coste es fijo (reescalado / copia de pantalla
         * entera) mientras que el del bucle baja con el número de puntos.
         * CoreGraphics tiene un camino rápido para `fillEllipse` que se pierde
         * en cuanto entra un path con miles de subtrazos. No volver a
         * «optimizar» esto sin medir las dos páginas.
         */
        ctx.setFillColor(tema.reticula.cgColor)
        let r = 1.1
        var y = y0
        while y < tamano.height + paso {
            var x = x0
            while x < tamano.width + paso {
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                x += paso
            }
            y += paso
        }
    }



    // ── geometría de figuras: UNA sola función, como en el lienzo web ───────
    func caminoFigura(_ kind: String, _ r: CGRect, radio: Double) -> CGPath {
        let p = CGMutablePath()
        let cx = r.midX, cy = r.midY
        switch kind {
        case "ellipse":
            p.addEllipse(in: r)
        case "diamond":
            p.move(to: CGPoint(x: cx, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: cy))
            p.addLine(to: CGPoint(x: cx, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: cy))
            p.closeSubpath()
        case "triangle":
            p.move(to: CGPoint(x: cx, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath()
        case "hexagon":
            let corte = min(r.width * 0.22, r.height * 0.5)
            p.move(to: CGPoint(x: r.minX + corte, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - corte, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: cy))
            p.addLine(to: CGPoint(x: r.maxX - corte, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + corte, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: cy)); p.closeSubpath()
        case "star":
            let rx = r.width / 2, ry = r.height / 2, interior = 0.42
            for i in 0..<10 {
                let ang = Double.pi * Double(i) / 5 - .pi / 2
                let f = i % 2 == 0 ? 1.0 : interior
                let pt = CGPoint(x: cx + cos(ang) * rx * f, y: cy + sin(ang) * ry * f)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
        case "arrow":
            let puntaW = min(r.width * 0.38, r.height * 0.9), cuerpo = r.height * 0.24
            p.move(to: CGPoint(x: r.minX, y: r.minY + cuerpo))
            p.addLine(to: CGPoint(x: r.maxX - puntaW, y: r.minY + cuerpo))
            p.addLine(to: CGPoint(x: r.maxX - puntaW, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: cy))
            p.addLine(to: CGPoint(x: r.maxX - puntaW, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX - puntaW, y: r.maxY - cuerpo))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - cuerpo)); p.closeSubpath()
        case "pill":
            let rr = min(r.width, r.height) / 2
            p.addRoundedRect(in: r, cornerWidth: rr, cornerHeight: rr)
        default:
            let rr = min(radio, r.width / 2, r.height / 2)
            p.addRoundedRect(in: r, cornerWidth: rr, cornerHeight: rr)
        }
        return p
    }

    /// ¿Dos colores son indistinguibles a ojo? (para detectar figura invisible)
    private func seParece(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return false }
        return abs(x.redComponent - y.redComponent) < 0.04
            && abs(x.greenComponent - y.greenComponent) < 0.04
            && abs(x.blueComponent - y.blueComponent) < 0.04
            && x.alphaComponent > 0.9 && y.alphaComponent > 0.9
    }

    private func aplicarTrazo(_ t: Trazo) {
        ctx.setStrokeColor(t.color.cgColor)
        ctx.setLineWidth(t.grosor)
        let u = t.grosor * 2
        switch t.estilo {
        case "dashed": ctx.setLineDash(phase: 0, lengths: [u * 2.2, u * 1.4])
        case "dotted": ctx.setLineDash(phase: 0, lengths: [0.1, u * 1.6]); ctx.setLineCap(.round)
        default:       ctx.setLineDash(phase: 0, lengths: [])
        }
    }

    // ── figura ──────────────────────────────────────────────────────────────
    func figura(_ e: Elemento) {
        // El DOCUMENTO se pinta entero por su cuenta (hoja + miniatura) y sale
        // ANTES de que aquí se rellene nada: si dejáramos correr el relleno del
        // rol, habría una caja debajo de la hoja pagando el doble.
        //
        // ⚠️ Y sale por `return` LIMPIO, sin tocar la pila de estados. La
        // primera versión hacía `documento(e); ctx.restoreGState(); return`
        // después del `restoreGState` de esta función: ese segundo pop se comía
        // un estado del LLAMADOR y el elemento siguiente se pintaba con la
        // cámara equivocada — se veía al doble de tamaño y en otro sitio. Un
        // save y un restore, siempre en el mismo nivel.
        if e.rol == "documento" { documento(e); return }
        /*
         * LA PIEL DIDÁCTICA. Cuatro formas que una caja no puede decir. Salen
         * por `return` LIMPIO —sin tocar la pila de estados— por la misma razón
         * que el documento: un `restoreGState` de más se come la cámara del
         * llamador y el siguiente elemento se pinta al doble en otro sitio.
         */
        switch e.rol {
        case "circulo":    circuloDidactico(e);    for p in e.textoLigado ?? [] { texto(e, p) }; if e.enlace != nil { marcaDestino(e) }; return
        case "momentum":   momentumDidactico(e);   if e.enlace != nil { marcaDestino(e) }; return
        case "termometro": termometroDidactico(e); if e.enlace != nil { marcaDestino(e) }; return
        case "parrilla":   parrillaDidactica(e);   if e.enlace != nil { marcaDestino(e) }; return
        default: break
        }
        // El WIDGET se pinta con la caja del rol debajo (a diferencia del
        // documento, que ES una hoja): fondo, borde y luego su contenido vivo.
        let esWidget = e.rol == "widget"
        let est = tema.rol(e.rol)
        let camino = caminoFigura(e.figura, e.caja, radio: tema.radio(e))
        ctx.saveGState()
        ctx.setAlpha(e.opacidad)
        if est.sombra && !Pintor.sinSombras {
            ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 14,
                          color: NSColor.black.withAlphaComponent(0.18).cgColor)
        }
        ctx.addPath(camino)
        ctx.setFillColor(tema.relleno(e).cgColor)
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        let t = tema.contorno(e)
        // Grosor 0 es una elección válida: figura sin contorno. Se decide aquí
        // y no se le deja al motor, que lo pinta distinto según la versión.
        if t.grosor > 0 {
            ctx.addPath(camino)
            aplicarTrazo(t)
            ctx.strokePath()
        /*
         * ⚠️ LA ÚNICA EXCEPCIÓN AL FANTASMA: el rol `tapa` (26 ago 2026).
         *
         * El fantasma existe porque una figura invisible «nunca es una
         * elección». En la tapa SÍ lo es: es una cortina que finge que ahí no
         * hay nada hasta que Daniel la arrastra fuera en cámara, y un contorno
         * de un pelo delata el rectángulo y mata el efecto.
         *
         * Y no se pierde, que es lo que el fantasma protege: es un `shape`, así
         * que `Geo.aceptaPuertos` lo acepta y el hover le pinta sus cuatro
         * puertos en cuanto el ratón pasa por encima; al pulsarla, la selección
         * la dibuja entera. Se encuentra con la mano sin verse con el ojo — que
         * es exactamente lo que hace falta para arrastrarla en cámara.
         */
        } else if e.rol != "tapa" && seParece(tema.relleno(e), tema.lienzo) {
            // Sin contorno Y relleno del color del lienzo = figura INVISIBLE.
            // Eso nunca es una elección: es un elemento perdido (medido 24 ago:
            // disparador blanco sobre lienzo blanco al quitar el trazo). Se
            // pinta un fantasma de un pelo para que siempre se pueda encontrar.
            ctx.addPath(camino)
            ctx.setStrokeColor(tema.reticula.cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.strokePath()
        }
        ctx.restoreGState()
        // El SENSOR pinta su propio contenido (cifra, delta, tendencia) y no
        // usa `text`: su maqueta la decide el instrumento, no el compilador.
        if e.rol == "sensor" { sensor(e) }
        if esWidget {
            // El conmutador necesita saber la caja del elemento que pinta.
            Pintor.elementoEnCurso = e
            widget(e)
            Pintor.elementoEnCurso = nil
        }
        // ⚠️ EL WIDGET NO PINTA SU `text`. Ese rótulo existe para la OTRA
        // superficie: el canvas web no tiene las fuentes del día, así que sin
        // él enseñaría una caja vacía —que se lee como un calendario sin
        // eventos, no como "esto se ve en sfmap"—. Aquí estorbaría encima del
        // contenido vivo.
        if !esWidget && !Pintor.sinTexto { for p in e.textoLigado ?? [] { texto(e, p) } }
        if e.enlace != nil { marcaDestino(e) }
    }

    /// El texto YA viene cortado en líneas por el compilador. Aquí se pinta;
    /// no se vuelve a decidir dónde parte una frase.
    private func texto(_ e: Elemento, _ p: Elemento.Parte) {
        let f = Fuentes.fuente(familia: p.estilo.familia, peso: p.estilo.peso,
                               tamano: p.estilo.tamano, cursiva: p.estilo.cursiva)
        let rolTexto = p.kind == "item" ? "body" : p.kind
        var col: NSColor = switch rolTexto {
            case "title": tema.tituloTexto
            case "caption": tema.pieTexto
            case "chip": tema.chipTexto
            default: tema.cuerpoTexto
        }
        if let h = e.colorTexto, let c = NSColor(hex: h) { col = c }

        let izq = e.x + p.x + (p.kind == "chip" ? 8 : 0)
        let ancho = p.ancho - (p.kind == "chip" ? 16 : 0)
        let lineH = p.lineas.isEmpty ? p.alto : p.alto / Double(p.lineas.count)

        if p.kind == "chip" {
            ctx.setFillColor(tema.rol("sticky").relleno.cgColor)
            let camino = CGMutablePath()
            camino.addRoundedRect(in: CGRect(x: e.x + p.x, y: e.y + p.y, width: p.ancho, height: p.alto),
                                  cornerWidth: 5, cornerHeight: 5)
            ctx.addPath(camino); ctx.fillPath()
        }

        if !legible(p.estilo.tamano) {
            silueta(p.lineas, x: izq, y: e.y + p.y, ancho: ancho, lineH: lineH,
                    tamano: p.estilo.tamano, color: col, alinea: e.alineacion)
            return
        }
        for (i, linea) in p.lineas.enumerated() {
            let attr = NSAttributedString(string: linea, attributes: [
                .font: f, .foregroundColor: col,
                .kern: p.estilo.espaciado ?? 0,
            ])
            let l = CTLineCreateWithAttributedString(attr)
            let w = CTLineGetTypographicBounds(l, nil, nil, nil)
            let x: Double = switch e.alineacion {
                case "center": izq + (ancho - w) / 2
                case "right":  izq + ancho - w
                default:       izq
            }
            let base = e.y + p.y + Double(i) * lineH + p.estilo.tamano * 0.82

            if let h = e.resaltado, let c = NSColor(hex: h) {
                ctx.setFillColor(c.cgColor)
                ctx.fill(CGRect(x: x - 3, y: base - p.estilo.tamano * 0.86,
                                width: w + 6, height: p.estilo.tamano * 1.16))
            }
            ctx.saveGState()
            // La Y del lienzo va hacia ABAJO; CoreText dibuja hacia arriba. Se
            // voltea SOLO el renglón, alrededor de su propia línea base.
            ctx.translateBy(x: x, y: base)
            ctx.scaleBy(x: 1, y: -1)
            ctx.textMatrix = .identity
        ctx.textPosition = .zero
            CTLineDraw(l, ctx)
            ctx.restoreGState()

            if p.estilo.subrayado || p.estilo.tachado {
                ctx.setFillColor(col.cgColor)
                let g = max(1, p.estilo.tamano * 0.055)
                if p.estilo.subrayado { ctx.fill(CGRect(x: x, y: base + p.estilo.tamano * 0.14, width: w, height: g)) }
                if p.estilo.tachado { ctx.fill(CGRect(x: x, y: base - p.estilo.tamano * 0.28, width: w, height: g)) }
            }
        }
    }

    // ── bloque de texto libre ──────────────────────────────────────────────
    func bloqueTexto(_ e: Elemento) {
        let est = e.estilo
        let f = Fuentes.fuente(familia: est.familia, peso: est.peso, tamano: est.tamano, cursiva: est.cursiva)
        var col = tema.tituloTexto
        if let h = e.colorTexto, let c = NSColor(hex: h) { col = c }
        let lineas = e.lineas.isEmpty ? [e.textoLibre ?? ""] : e.lineas
        let lineH = est.tamano * (est.interlineado ?? 1.25)
        ctx.setAlpha(e.opacidad)
        if !legible(est.tamano) {
            silueta(lineas, x: e.x, y: e.y, ancho: e.ancho, lineH: lineH,
                    tamano: est.tamano, color: col, alinea: e.alineacion)
            ctx.setAlpha(1)
            return
        }
        for (i, linea) in lineas.enumerated() {
            let attr = NSAttributedString(string: linea, attributes: [
                .font: f, .foregroundColor: col, .kern: est.espaciado ?? 0])
            let l = CTLineCreateWithAttributedString(attr)
            let w = CTLineGetTypographicBounds(l, nil, nil, nil)
            let x: Double = switch e.alineacion {
                case "center": e.x + (e.ancho - w) / 2
                case "right":  e.x + e.ancho - w
                default:       e.x
            }
            ctx.saveGState()
            ctx.translateBy(x: x, y: e.y + Double(i) * lineH + est.tamano * 0.82)
            ctx.scaleBy(x: 1, y: -1)
            ctx.textMatrix = .identity
        ctx.textPosition = .zero
            CTLineDraw(l, ctx)
            ctx.restoreGState()
        }
        ctx.setAlpha(1)
    }

    // ── conector ───────────────────────────────────────────────────────────
    func conector(_ e: Elemento, conEtiqueta: Bool = true) {
        let pts = TrazoConector.muestras(e)
        guard pts.count >= 2 else { return }
        let t = tema.aristas[e.claseArista] ?? tema.aristas["flujo"]!
        ctx.saveGState()
        ctx.setAlpha(e.opacidad)
        aplicarTrazo(t)
        let escala = max(0.5, min(4, e.crudo["strokeScale"]?.num ?? 1))
        ctx.setLineWidth(t.grosor * escala)
        ctx.setLineJoin(.round)
        ctx.addPath(TrazoConector.camino(e))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        if e.puntaFin != "ninguna" { punta(pts[pts.count - 2], pts[pts.count - 1], t.color, e.puntaFin, escala: escala) }
        if e.puntaInicio != "ninguna" { punta(pts[1], pts[0], t.color, e.puntaInicio, escala: escala) }
        ctx.restoreGState()
        if conEtiqueta { etiquetaArista(e) }
    }

    private func punta(_ de: CGPoint, _ a: CGPoint, _ col: NSColor, _ tipo: String, escala: Double = 1) {
        let ang = atan2(a.y - de.y, a.x - de.x)
        let l: CGFloat = 11 * CGFloat(escala), w: CGFloat = 6 * CGFloat(escala)
        ctx.setFillColor(col.cgColor)
        ctx.setStrokeColor(col.cgColor)
        switch tipo {
        case "circulo":
            ctx.fillEllipse(in: CGRect(x: a.x - w/2, y: a.y - w/2, width: w, height: w))
        case "barra":
            ctx.setLineWidth(2.5)
            ctx.move(to: CGPoint(x: a.x - sin(ang) * w, y: a.y + cos(ang) * w))
            ctx.addLine(to: CGPoint(x: a.x + sin(ang) * w, y: a.y - cos(ang) * w))
            ctx.strokePath()
        case "rombo":
            ctx.move(to: a)
            ctx.addLine(to: CGPoint(x: a.x - cos(ang) * l/1.6 - sin(ang) * w/1.6, y: a.y - sin(ang) * l/1.6 + cos(ang) * w/1.6))
            ctx.addLine(to: CGPoint(x: a.x - cos(ang) * l, y: a.y - sin(ang) * l))
            ctx.addLine(to: CGPoint(x: a.x - cos(ang) * l/1.6 + sin(ang) * w/1.6, y: a.y - sin(ang) * l/1.6 - cos(ang) * w/1.6))
            ctx.closePath(); ctx.fillPath()
        default:
            ctx.move(to: a)
            ctx.addLine(to: CGPoint(x: a.x - cos(ang) * l - sin(ang) * w, y: a.y - sin(ang) * l + cos(ang) * w))
            ctx.addLine(to: CGPoint(x: a.x - cos(ang) * l + sin(ang) * w, y: a.y - sin(ang) * l - cos(ang) * w))
            ctx.closePath(); ctx.fillPath()
        }
    }

    func etiquetaArista(_ e: Elemento, obstaculos: [CGRect] = []) {
        guard e.ruta.count >= 2, let texto=e.etiqueta, !texto.isEmpty else { return }
        let tam=max(9,min(48,e.crudo["labelStyle"]?["size"]?.num ?? 11))
        guard legible(tam) else { return }
        let f = Fuentes.fuente(familia: "montserrat", peso: 600, tamano: tam, cursiva: false)
        let attr = NSAttributedString(string: texto, attributes: [.font: f, .foregroundColor: tema.cuerpoTexto])
        let l = CTLineCreateWithAttributedString(attr)
        let w = CTLineGetTypographicBounds(l, nil, nil, nil)
        let r=TrazoConector.cajaEtiqueta(e,tamano:CGSize(width:w+12,height:tam*1.5),obstaculos:obstaculos)
        ctx.setFillColor(tema.lienzo.withAlphaComponent(0.92).cgColor)
        ctx.fill(r)
        ctx.saveGState()
        ctx.translateBy(x: r.minX+6, y: r.minY+tam*1.1)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        ctx.textPosition = .zero
        CTLineDraw(l, ctx)
        ctx.restoreGState()
    }

    // ── sección ────────────────────────────────────────────────────────────
    func seccion(_ e: Elemento) {
        let tin = tema.tintes[e.tinte] ?? tema.tintes["neutro"]!
        /*
         * EL PASO EN LA RAMPA — la profundidad, dicha con el MISMO color.
         *
         * Daniel, con los Miro de Mateo delante (25 ago): *"nota cómo Mateo
         * utiliza varios morados de la misma paleta para dar estructura"*. En
         * un embudo eso se puede MEDIR: la boca va tenue y el cuello va fuerte,
         * así que el tono dice a qué altura del embudo estás. Es información,
         * no degradado decorativo — y no entra ni un matiz nuevo, porque los
         * tres pasos salen del tinte que la banda ya tenía.
         */
        let relleno = e.crudo["paso"]?.num.map { tema.rampa(e.tinte, $0) } ?? tin.relleno
        ctx.saveGState()
        ctx.setAlpha(e.opacidad)
        let camino = CGMutablePath()
        let radio = e.radioEsquina ?? tema.rol("tray").radio
        camino.addRoundedRect(in: e.caja, cornerWidth: radio, cornerHeight: radio)
        ctx.addPath(camino); ctx.setFillColor(relleno.cgColor); ctx.fillPath()
        let g = e.grosorLinea ?? 1.5
        if g > 0 {
            ctx.addPath(camino)
            aplicarTrazo(Trazo(color: tin.trazo, grosor: g, estilo: e.estiloLinea ?? "solid"))
            ctx.strokePath()
        }
        if let t = e.titulo, !t.isEmpty {
            // El título va FUERA, encima del borde: dentro compite con el
            // contenido y en una sección llena no se lee.
            /*
             * EL RÓTULO CRECE CON LA SECCIÓN.
             *
             * Estaba clavado a 13. En un grupo de 400 de ancho eso es correcto;
             * en una BANDA de 5.400 —las del centro de mando— sale una pastilla
             * de 10 px sobre gris que un crítico ciego describió como "ilegible
             * sin hacer zoom". El rótulo es lo que dice de qué va la franja: si
             * no se lee, la franja no se presenta y el tablero parece tres
             * cosas pegadas en vez de un instrumento con capítulos.
             *
             * Escala suave y con tope: los grupos pequeños salen exactamente
             * igual que antes, y solo las bandas ganan cuerpo.
             */
            let tam = min(24.0, max(13.0, 13 + (e.ancho - 900) / 320))
            let f = Fuentes.fuente(familia: "montserrat", peso: 800, tamano: tam, cursiva: false)
            /*
             * ⚠️ EL RÓTULO NO ASUME EL COLOR DEL FONDO: LO CALCULA.
             *
             * Aquí ponía `tema.lienzo` — dando por hecho que la pastilla es un
             * color saturado y que el color del lienzo contrasta contra ella.
             * Es cierto para morado y ámbar, y FALSO para `neutro`, que es el
             * tinte de las tres bandas del centro de mando: su filo es un gris
             * medio, así que salía **negro sobre negro** en oscuro y **blanco
             * sobre blanco** en claro. Los tres rótulos del tablero, ilegibles,
             * en los dos temas (Daniel, 25 ago: *"que no vuelva a ocurrir negro
             * sobre negro y blanco sobre blanco en los títulos de secciones"*).
             *
             * La regla que entra al estándar: **un texto sobre un fondo de
             * color elige su tinta por LUMINANCIA del fondo, jamás por
             * convención.** Una convención se rompe en silencio el día que
             * alguien añade un tinte nuevo; una medición, no.
             */
            let attr = NSAttributedString(string: t.uppercased(),
                attributes: [.font: f, .foregroundColor: Tema.tintaSobre(tin.trazo), .kern: 0.6])
            let l = CTLineCreateWithAttributedString(attr)
            let w = CTLineGetTypographicBounds(l, nil, nil, nil)
            /*
             * EL RÓTULO OBEDECE A LA ALINEACIÓN.
             *
             * Estaba clavado a la izquierda: Daniel centró una sección y *"no se
             * movió el texto"*. Y no se movía — el modelo guardaba `textAlign` y
             * el pintor lo ignoraba. Una capacidad que la barra ofrece y el motor
             * no lee es exactamente lo que este lienzo persigue.
             */
            let anchoCart = w + tam * 1.3
            let xCart: Double = switch e.alineacion {
                case "center": e.x + (e.ancho - anchoCart) / 2
                case "right":  e.x + e.ancho - anchoCart - 10
                default:       e.x + 10
            }
            ctx.setFillColor(tin.trazo.cgColor)
            let cart = CGMutablePath()
            let altoCart = tam * 1.45
            cart.addRoundedRect(in: CGRect(x: xCart, y: e.y - altoCart - 4, width: anchoCart, height: altoCart),
                                cornerWidth: 5, cornerHeight: 5)
            ctx.addPath(cart); ctx.fillPath()
            ctx.saveGState()
            ctx.translateBy(x: xCart + tam * 0.65, y: e.y - 4 - altoCart * 0.28)
            ctx.scaleBy(x: 1, y: -1)
            ctx.textMatrix = .identity
        ctx.textPosition = .zero
            CTLineDraw(l, ctx)
            ctx.restoreGState()
        }
        // El conmutador de VENTANA, si la banda lo declara. Va después del
        // rótulo y en su misma fila: el rótulo dice QUÉ es la franja, el
        // conmutador dice CUÁNTO abarca.
        ventanasDeSeccion(e)
        ctx.restoreGState()
    }

    // ── tinta ──────────────────────────────────────────────────────────────
    /// El trazo GUARDADO. Un solo polígono relleno, calculado por `Tinta` y
    /// cacheado: sin caché, una página con tinta pagaría el spline de cada
    /// trazo 120 veces por segundo para dibujar exactamente lo mismo.
    ///
    /// El camino vive en coordenadas LOCALES y la posición la pone la matriz.
    /// Así arrastrar un trazo no invalida su geometría — que es el gesto más
    /// frecuente que se le hace a un trazo.
    func tinta(_ e: Elemento) {
        var col = tema.tinta
        if let h = e.colorTinta, let c = NSColor(hex: h) { col = c }
        let opc = Tinta.Opciones(grosor: e.grosorTinta, marcador: e.esMarcador)
        guard let cam = CacheTinta.compartida.camino(e.claveTinta, {
            Tinta.camino(e.trazoTinta, opc)
        }) else { return }
        ctx.saveGState()
        ctx.setAlpha(e.esMarcador ? 0.35 * e.opacidad : e.opacidad)
        ctx.setFillColor(col.cgColor)
        ctx.translateBy(x: e.x, y: e.y)
        ctx.addPath(cam)
        // NON-ZERO a propósito: un trazo que se cruza a sí mismo —una "e", un
        // lazo— se rellena UNA vez. Con par-impar el cruce saldría hueco, que
        // es lo contrario de lo que hace la tinta.
        ctx.fillPath(using: .winding)
        ctx.restoreGState()
    }

    // ── selección ──────────────────────────────────────────────────────────
    func seleccion(_ els: [Elemento]) {
        guard !els.isEmpty else { return }
        var r = els[0].cajaVisual
        for e in els.dropFirst() { r = r.union(e.cajaVisual) }
        ctx.setStrokeColor(tema.seleccion.cgColor)
        ctx.setLineWidth(1.5 / camara.zoom)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.stroke(r.insetBy(dx: -4 / camara.zoom, dy: -4 / camara.zoom))
        // Los tiradores se pintan exclusivamente en manijas(), con la misma
        // caja y condición que el hit-test. Un marco bloqueado no ofrece falsos agarres.
    }
}
