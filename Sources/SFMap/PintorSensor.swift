import AppKit
import CoreGraphics

/**
 * EL SENSOR y LAS MARCAS DE DESTINO — lo que convierte un mapa en un tablero.
 *
 * Un mapa que no lee el mundo es un póster: se dibuja una vez, envejece en
 * silencio y a las dos semanas nadie lo abre. Este proyecto ya enterró cuatro
 * por eso. La diferencia entre museo e instrumento es UNA cosa: que le entre
 * DATO, y que el dato diga CUÁNDO se midió.
 *
 * ⚠️ Y LA REGLA QUE MANDA AQUÍ: un cero no es un dato. Un sensor sin lectura
 * pinta «sin dato», nunca `0` — porque un `0` bien tipografiado se lee como una
 * medición y ese error ya costó caro (`dato-ausente-no-es-cero`, 17 ago 2026).
 * Por eso el sensor guarda `valor` como TEXTO ya formateado: quien lo escribe
 * es quien sabe si midió, y la ausencia viaja como ausencia.
 *
 * Nativo y no imagen: una gráfica horneada a PNG obliga a un archivo por
 * sensor, y el pintor cachea las imágenes POR RUTA — reemplazar el contenido de
 * un PNG ya visto deja la cifra vieja en pantalla hasta relanzar. Un sensor que
 * miente al refrescarse es peor que no tenerlo. Así, un PATCH y ya está.
 */
extension Pintor {

    struct Lectura {
        var etiqueta: String
        var valor: String?          // nil ⇒ sin dato
        var delta: String?
        var signo: Double           // +1 subió · −1 bajó · 0 plano
        var tendencia: [Double]
        var pie: String?
        var meta: String?
        /// Las FECHAS de la serie (ISO). Sin ellas el eje X no tiene rótulos y
        /// la chispa dice una forma sin decir de cuándo es.
        var fechas: [String]
        /// −1 para las métricas donde SUBIR es malo (churn, costes). Sin esto,
        /// la chispa pinta de rojo un churn que mejora: el color diciendo lo
        /// contrario del dato.
        var polaridad: Double

        /// Puente al de `Ejes`: UNA definición de cómo se escribe un día. Dos
        /// formatos de fecha en el mismo tablero es el principio de dos
        /// verdades sobre cuándo pasó algo.
        static func diaCorto(_ iso: String) -> String? { Ejes.diaCorto(iso) }

        init?(_ e: Elemento) {
            guard let raw = e.crudo["sensor"] else { return nil }
            /*
             * LA VENTANA ELEGIDA manda si el sensor la trae. `sensores.py`
             * escribe las tres (7/30/90) y los campos planos siguen siendo la
             * de 7 días: un lienzo viejo, o el canvas web —que no conoce
             * `ventanas`—, siguen enseñando algo correcto en vez de quedarse
             * mudos.
             */
            let ventana = VentanaSensor.elegida
            let j = raw["ventanas"]?[String(ventana.dias)] ?? raw
            /*
             * ⚠️ LA VENTANA NO TRAE TODO, Y LO QUE NO TRAE SE HEREDA.
             *
             * El cron escribe por ventana lo que CAMBIA con ella (valor, delta,
             * tendencia, fechas, pie). La ETIQUETA y la META son del generador
             * —son diseño, no medición— y viven en el objeto de fuera. Al leer
             * solo la sub-lectura, las seis tarjetas se quedaron SIN TÍTULO:
             * seis números sin decir de qué. Daniel: *"pon títulos a cada
             * tarjeta, no entiendo a qué se debe cada una"*.
             *
             * Regla: la ventana MANDA en lo suyo y HEREDA lo demás.
             */
            func campo(_ k: String) -> Json? { j[k] ?? raw[k] }
            etiqueta = campo("etiqueta")?.s ?? ""
            let v = j["valor"]?.s ?? j["valor"]?.num.map { NumberFormatter.localizedString(from: NSNumber(value: $0), number: .decimal) }
            valor = (v?.isEmpty ?? true) ? nil : v
            delta = j["delta"]?.s
            signo = j["signo"]?.num ?? 0
            tendencia = j["tendencia"]?.arr?.compactMap { $0.num } ?? []
            pie = campo("pie")?.s
            meta = campo("meta")?.s
            fechas = j["fechas"]?.arr?.compactMap { $0.s } ?? []
            polaridad = campo("polaridad")?.num ?? 1
        }
    }

    /// El contenido del sensor, dentro de su caja ya pintada por `figura`.
    func sensor(_ e: Elemento) {
        guard let l = Lectura(e) else { return }
        let r = e.caja
        ctx.saveGState()
        ctx.setAlpha(e.opacidad)
        let pad = 13.0

        // ETIQUETA — versalitas mono. Es el nombre del instrumento, no un
        // título de tarjeta: por eso pesa poco y va arriba, fuera del camino.
        pintarTexto(l.etiqueta.uppercased(), en: CGPoint(x: r.minX + pad, y: r.minY + pad),
                    tamano: 9.5, peso: 700, color: tema.pieTexto, mono: true, espaciado: 1.1)

        // VALOR — la cifra manda. Mono para que los dígitos no bailen al
        // refrescarse: con tipografía proporcional, pasar de 8,191 a 8,298
        // mueve todo el renglón y el ojo lee "cambió el diseño", no "cambió el
        // número".
        let hayDato = l.valor != nil
        let cifra = l.valor ?? "sin dato"
        let tamCifra = tamanoQueCabe(cifra, ancho: Double(r.width) - pad * 2 - (l.delta != nil ? 54 : 0),
                                     desde: 27, hasta: 15, peso: 700, mono: true)
        let yCifra = r.minY + pad + 16
        pintarTexto(cifra, en: CGPoint(x: r.minX + pad, y: yCifra),
                    tamano: tamCifra, peso: hayDato ? 700 : 500,
                    color: hayDato ? tema.tituloTexto : tema.pieTexto, mono: true)

        // DELTA — el chip del cambio. Verde/rojo salen de los TINTES que el
        // estándar ya tiene: no es un color nuevo, es el mismo vocabulario.
        if hayDato, let d = l.delta, !d.isEmpty {
            // ⚠️ SIN VERDE. El estándar reserva el color para lo que GRITA, y
            // "todo bien" no grita: subir es lo esperado. Un chip verde en cada
            // sensor que sube es decoración, y decoración a la que el ojo se
            // acostumbra le roba fuerza al rojo, que es el que sí avisa.
            // Bueno = neutro · malo = rojo. (Paleta reducida, 25 ago 2026.)
            let clave = l.signo < 0 ? "rojo" : "neutro"
            let t = tema.tintes[clave] ?? tema.tintes["neutro"]!
            let anchoChip = Medidor.medir(d, chip(10)) + 16
            let caja = CGRect(x: r.maxX - pad - anchoChip, y: yCifra + 3, width: anchoChip, height: 19)
            let p = CGMutablePath()
            p.addRoundedRectSeguro(in: caja, cornerWidth: 5, cornerHeight: 5)
            ctx.addPath(p); ctx.setFillColor(t.relleno.cgColor); ctx.fillPath()
            pintarTexto(d, en: CGPoint(x: caja.minX + 8, y: caja.minY + 4),
                        tamano: 10, peso: 700, color: t.etiqueta, mono: true)
        }

        // TENDENCIA — la forma del último tramo. Sin ejes ni rótulos a
        // propósito: aquí no se lee un valor, se lee una DIRECCIÓN.
        // La gráfica ahora tiene EJES, y los ejes ocupan: 46 px a la izquierda y
        // 15 abajo. Se le da su sitio en vez de encogerla, porque una gráfica
        // con ejes que no caben es peor que una sin ellos.
        let yBase = r.maxY - pad - (l.pie != nil || l.meta != nil ? 17 : 0)
        if l.tendencia.count >= 2 {
            chispa(l.tendencia, polaridad: l.polaridad, fechas: l.fechas,
                   moneda: (l.valor ?? "").hasPrefix("$"),
                   en: CGRect(x: r.minX + pad, y: yCifra + tamCifra + 16,
                                           width: r.width - pad * 2,
                                           height: max(12, yBase - (yCifra + tamCifra + 22))),
                   signo: l.signo)
        }

        if let pie = l.pie {
            pintarTexto(pie, en: CGPoint(x: r.minX + pad, y: r.maxY - pad - 11),
                        tamano: 9, peso: 500, color: tema.pieTexto, mono: true)
        }
        if let meta = l.meta {
            let w = Medidor.medir(meta, chip(9))
            pintarTexto(meta, en: CGPoint(x: r.maxX - pad - w, y: r.maxY - pad - 11),
                        tamano: 9, peso: 700, color: tema.acento, mono: true)
        }
        ctx.restoreGState()
    }

    /// La chispa: área suave + línea + punto en el último dato.
    ///
    /// ⚠️ SU COLOR SALE DE LA LINEA QUE DIBUJA, no del delta del día. Con el
    /// `signo` del sensor, el MRR salía VERDE (subió +1.3% ayer) sobre una
    /// curva que llevaba dos semanas cayendo: el color decía una cosa y la
    /// forma la contraria. Dos hechos distintos, dos codificaciones: el CHIP
    /// habla del último día, la CHISPA del tramo entero.
    /**
     * LA GRÁFICA DE UN SENSOR — con sus dos ejes rotulados.
     *
     * Daniel, 25 ago: *"los filtros que tenemos de métricas diarias, quarters y
     * mensuales, asegúrate que cada una tenga values en el eje X y Y para tener
     * bien medidas las métricas"*.
     *
     * Y tiene razón de fondo: hasta ahora esto era una CHISPA —una forma sin
     * escala— y una forma sin escala se puede leer como se quiera. La misma
     * curva parece un desplome o un temblor según cuánto zoom le pongas al eje
     * Y. Con el mínimo y el máximo escritos, la pendiente deja de ser una
     * impresión y pasa a ser una medida.
     *
     * ⚠️ El eje Y **no arranca en cero a propósito**: estas series son rangos
     * estrechos (8.200–9.400 de MRR) y forzar el cero aplastaría contra el borde
     * inferior justo lo que se quiere ver. Por eso los dos extremos van
     * ESCRITOS: un eje recortado sin rótulos sí es un engaño; con ellos es un
     * zoom declarado.
     */
    private func chispa(_ vs: [Double], polaridad: Double = 1, fechas: [String] = [],
                        moneda: Bool = false, en r0: CGRect, signo _: Double) {
        guard r0.height > 6, vs.count >= 2 else { return }
        // Sitio para los rótulos: el eje Y a la izquierda, el X debajo.
        // Sitio para los rótulos: el eje Y a la izquierda, el X debajo.
        let anchoY = 46.0, altoX = 15.0
        let r = CGRect(x: r0.minX + anchoY, y: r0.minY,
                       width: max(20, r0.width - anchoY), height: max(10, r0.height - altoX))
        let deriva = (vs.last! - vs.first!) * polaridad
        let signo: Double = abs(deriva) < 1e-9 ? 0 : (deriva > 0 ? 1 : -1)
        let esc = Ejes.escalaY(vs, marcasDeseadas: r.height > 70 ? 4 : 3)
        func punto(_ i: Int) -> CGPoint {
            let x = r.minX + r.width * Double(i) / Double(vs.count - 1)
            return CGPoint(x: x, y: r.maxY - esc.fraccion(vs[i]) * (r.height - 3) - 1.5)
        }
        // Misma regla en la chispa: la caída se pinta roja porque hay que verla;
        // la subida va en el acento de marca, que informa sin gritar.
        let col = signo < 0 ? (tema.tintes["rojo"]?.etiqueta ?? tema.acento) : tema.acento

        let area = CGMutablePath()
        area.move(to: CGPoint(x: r.minX, y: r.maxY))
        for i in vs.indices { area.addLine(to: punto(i)) }
        area.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        area.closeSubpath()
        ctx.addPath(area)
        ctx.setFillColor(col.withAlphaComponent(0.13).cgColor)
        ctx.fillPath()

        // ── LOS EJES, antes de la línea para que queden por debajo.
        //
        // Marcas en números REDONDOS (1·10ⁿ, 2·10ⁿ, 5·10ⁿ) y no en el mínimo y
        // el máximo que salgan: "8.200 → 9.400" no dice nada, "8.500 · 9.000 ·
        // 9.500" se compara de un vistazo con cualquier otra lectura. La
        // aritmética vive en `Ejes` y está probada con números.
        let tenue = tema.pieTexto.withAlphaComponent(0.6)
        for m in esc.marcas {
            let y = r.maxY - esc.fraccion(m) * (r.height - 3) - 1.5
            guard y >= r.minY - 1, y <= r.maxY + 1 else { continue }
            ctx.setStrokeColor(tema.reticula.withAlphaComponent(0.75).cgColor)
            ctx.setLineWidth(1); ctx.setLineDash(phase: 0, lengths: [2, 4])
            ctx.move(to: CGPoint(x: r.minX, y: y)); ctx.addLine(to: CGPoint(x: r.maxX, y: y))
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
            let et = Ejes.rotuloY(m, paso: esc.paso, moneda: moneda)
            let w = Medidor.medir(et, chip(8.5))
            pintarTexto(et, en: CGPoint(x: r.minX - 6 - w, y: y - 5),
                        tamano: 8.5, peso: 700, color: tenue, mono: true)
        }
        // El eje X: una marca por unidad natural del periodo (7 días → 7).
        for mx in Ejes.marcasX(fechas: fechas, dias: VentanaSensor.elegida.dias,
                               anchoDisponible: r.width) {
            let x = punto(mx.indice).x
            ctx.setStrokeColor(tema.reticula.cgColor); ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: x, y: r.maxY)); ctx.addLine(to: CGPoint(x: x, y: r.maxY + 3))
            ctx.strokePath()
            let w = Medidor.medir(mx.rotulo, chip(8.5))
            // Los extremos se pegan al borde en vez de centrarse: un rótulo
            // centrado en el último punto se sale de la caja.
            let cx = mx.indice == 0 ? x
                   : (mx.indice == fechas.count - 1 ? x - w : x - w / 2)
            pintarTexto(mx.rotulo, en: CGPoint(x: cx, y: r.maxY + 4),
                        tamano: 8.5, peso: 600, color: tenue, mono: true)
        }

        let linea = CGMutablePath()
        linea.move(to: punto(0))
        for i in vs.indices.dropFirst() { linea.addLine(to: punto(i)) }
        ctx.addPath(linea)
        ctx.setStrokeColor(col.cgColor)
        ctx.setLineWidth(1.6)
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.strokePath()

        let u = punto(vs.count - 1)
        ctx.setFillColor(col.cgColor)
        ctx.fillEllipse(in: CGRect(x: u.x - 2.6, y: u.y - 2.6, width: 5.2, height: 5.2))
    }

    // ── utilidades de texto del sensor ─────────────────────────────────────

    private func chip(_ t: Double) -> EstiloTexto {
        var e = EstiloTexto(); e.familia = "jetbrains-mono"; e.peso = 700; e.tamano = t; return e
    }

    private func tamanoQueCabe(_ s: String, ancho: Double, desde: Double, hasta: Double,
                               peso: Double, mono: Bool) -> Double {
        var t = desde
        var e = EstiloTexto()
        e.familia = mono ? "jetbrains-mono" : "montserrat"; e.peso = peso
        while t > hasta {
            e.tamano = t
            if Medidor.medir(s, e) <= ancho { return t }
            t -= 1
        }
        return hasta
    }

    func pintarTexto(_ s: String, en p: CGPoint, tamano: Double, peso: Double,
                     color: NSColor, mono: Bool = false, espaciado: Double = 0) {
        guard !s.isEmpty else { return }
        let f = Fuentes.fuente(familia: mono ? "jetbrains-mono" : "montserrat",
                               peso: peso, tamano: tamano, cursiva: false)
        var attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color]
        if espaciado != 0 { attrs[.kern] = espaciado }
        let l = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        // ⚠️ `textMatrix` NO entra en saveGState (guía de Quartz 2D): cualquier
        // NSTextField de AppKit lo deja con una escala puesta y el siguiente
        // CTLineDraw la hereda. Ya salió una hoja de contacto con el texto
        // girado 180° por esto.
        ctx.textMatrix = .identity
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y + tamano * 0.82)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(l, ctx)
        ctx.restoreGState()
    }

    // ── la marca de destino ────────────────────────────────────────────────

    /// El radio de la marca EN MUNDO. Vive aquí y no en el pintor porque el
    /// hit-test del lienzo necesita el mismo número: dos sitios calculando
    /// dónde está el botón es la receta de un botón que no se deja pulsar.
    ///
    /// ⚠️ LA MARCA SUSURRA (25 ago 2026). Nació a 10 y con el disco morado a
    /// plena saturación: en un tablero de treinta nodos eran treinta puntos de
    /// color compitiendo con el contenido, y Daniel lo nombró — *"las marcas de
    /// vínculo hoy compiten con la tarjeta"*. Baja a 7 y el disco se pinta
    /// TENUE; el color pleno se reserva para el hover y la selección, que es
    /// cuando la marca sí tiene algo que decir.
    static func radioMarca(_ zoom: Double) -> Double { 7 / zoom }

    static func centroMarca(_ e: Elemento, zoom: Double) -> CGPoint {
        let r = radioMarca(zoom)
        return CGPoint(x: e.x + e.ancho - r - 6 / zoom, y: e.y + r + 6 / zoom)
    }

    /// La marca dice A DÓNDE va, no solo QUE va a algún sitio.
    ///
    /// Con una marca única para cuatro destinos, pulsar es una apuesta: puede
    /// abrir un SOP, saltar de lienzo, lanzar un vídeo o sacarte al navegador.
    /// Un mapa que se opera a diario no puede pedirle al ojo que adivine.
    func marcaDestino(_ e: Elemento) {
        guard let m = Enlace.marca(e.enlace) else { return }
        // En panorama, la imagen ya es el destino. Un sello de tamaño fijo
        // tapa la evidencia diminuta. Al acercarse vuelve la pista visual.
        if e.abreAlClic, min(e.ancho, e.alto) * camara.zoom < 90 { return }
        let r = Pintor.radioMarca(camara.zoom)
        let c = Pintor.centroMarca(e, zoom: camara.zoom)
        let s = r * 0.44

        ctx.saveGState()
        // Tenue: el disco es un susurro, no un sello. Sobre claro y sobre oscuro
        // el mismo acento a ~22% deja leer la tarjeta y sigue diciendo "aquí hay
        // algo que abrir" cuando el ojo lo busca.
        ctx.setAlpha(e.opacidad * 0.9)
        ctx.setFillColor(tema.acento.withAlphaComponent(0.22).cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.setStrokeColor(tema.acento.cgColor)
        ctx.setFillColor(tema.acento.cgColor)
        ctx.setLineWidth(1.3 / camara.zoom)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setLineJoin(.round); ctx.setLineCap(.round)

        switch m {
        case .documento:
            // Hoja con la esquina doblada.
            let w = s * 1.35, h = s * 1.75, dob = s * 0.62
            let p = CGMutablePath()
            p.move(to: CGPoint(x: c.x - w/2, y: c.y - h/2))
            p.addLine(to: CGPoint(x: c.x + w/2 - dob, y: c.y - h/2))
            p.addLine(to: CGPoint(x: c.x + w/2, y: c.y - h/2 + dob))
            p.addLine(to: CGPoint(x: c.x + w/2, y: c.y + h/2))
            p.addLine(to: CGPoint(x: c.x - w/2, y: c.y + h/2))
            p.closeSubpath()
            ctx.addPath(p); ctx.strokePath()
            for k in 0..<2 {
                let y = c.y + s * (0.1 + Double(k) * 0.55)
                ctx.move(to: CGPoint(x: c.x - w/2 + s * 0.3, y: y))
                ctx.addLine(to: CGPoint(x: c.x + w/2 - s * 0.3, y: y))
            }
            ctx.strokePath()
        case .pagina:
            // Tres nodos y dos aristas: el grafo que lleva a otro grafo.
            let n = s * 0.34
            let ps = [CGPoint(x: c.x - s * 0.85, y: c.y - s * 0.75),
                      CGPoint(x: c.x + s * 0.85, y: c.y - s * 0.15),
                      CGPoint(x: c.x - s * 0.15, y: c.y + s * 0.95)]
            ctx.move(to: ps[0]); ctx.addLine(to: ps[1])
            ctx.move(to: ps[1]); ctx.addLine(to: ps[2])
            ctx.strokePath()
            for p in ps { ctx.fillEllipse(in: CGRect(x: p.x - n, y: p.y - n, width: n * 2, height: n * 2)) }
        case .video:
            let t = CGMutablePath()
            t.move(to: CGPoint(x: c.x - s * 0.62, y: c.y - s * 0.95))
            t.addLine(to: CGPoint(x: c.x + s * 1.0, y: c.y))
            t.addLine(to: CGPoint(x: c.x - s * 0.62, y: c.y + s * 0.95))
            t.closeSubpath()
            ctx.addPath(t); ctx.fillPath()
        case .web:
            ctx.addArc(center: CGPoint(x: c.x - s * 0.55, y: c.y + s * 0.55), radius: s,
                       startAngle: -.pi * 0.25, endAngle: .pi * 0.85, clockwise: false)
            ctx.strokePath()
            ctx.addArc(center: CGPoint(x: c.x + s * 0.55, y: c.y - s * 0.55), radius: s,
                       startAngle: .pi * 0.75, endAngle: .pi * 1.85, clockwise: false)
            ctx.strokePath()
        case .app:
            // La flecha que SALE de la caja: el gesto universal de "esto se
            // abre en otro sitio". Se distingue del eslabón (que va a la web)
            // porque aquí el destino es una APP de escritorio.
            let m = CGMutablePath()
            m.addRoundedRectSeguro(in: CGRect(x: c.x - s, y: c.y - s * 0.55, width: s * 1.55, height: s * 1.55),
                             cornerWidth: s * 0.28, cornerHeight: s * 0.28)
            ctx.addPath(m); ctx.strokePath()
            ctx.move(to: CGPoint(x: c.x + s * 0.05, y: c.y - s * 0.05))
            ctx.addLine(to: CGPoint(x: c.x + s * 1.0, y: c.y - s * 1.0))
            ctx.strokePath()
            let f = CGMutablePath()
            f.move(to: CGPoint(x: c.x + s * 0.32, y: c.y - s * 1.0))
            f.addLine(to: CGPoint(x: c.x + s * 1.0, y: c.y - s * 1.0))
            f.addLine(to: CGPoint(x: c.x + s * 1.0, y: c.y - s * 0.32))
            ctx.addPath(f); ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// El velo de reproducción sobre una imagen que es un VÍDEO. Una miniatura
    /// sin él es indistinguible de una captura de pantalla: el gesto de pulsar
    /// hay que ofrecerlo, no esperarlo.
    func veloVideo(_ e: Elemento) {
        guard case .video = Enlace.leer(e.enlace) else { return }
        let r = e.caja
        let rad = min(min(r.width, r.height) * 0.16, 26 / camara.zoom)
        let c = CGPoint(x: r.midX, y: r.midY)
        ctx.saveGState()
        ctx.setAlpha(e.opacidad * 0.92)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2))
        let s = rad * 0.46
        let t = CGMutablePath()
        t.move(to: CGPoint(x: c.x - s * 0.6, y: c.y - s))
        t.addLine(to: CGPoint(x: c.x + s, y: c.y))
        t.addLine(to: CGPoint(x: c.x - s * 0.6, y: c.y + s))
        t.closeSubpath()
        ctx.addPath(t)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }
}
