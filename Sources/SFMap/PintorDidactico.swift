import AppKit
import CoreGraphics

/**
 * LA PIEL DIDÁCTICA — lo que una caja no puede decir.
 *
 * Daniel, 25 ago por la noche, con el tablero de Mateo delante: *"todos son
 * cajas, cabrón… la meta se baja al comparador"*. Y el diagnóstico es exacto:
 * un estándar de DIAGRAMAS hace pensar que todo es un diagrama de cajas. Una
 * página que ENSEÑA no es eso — las cajas son uno de sus vocablos, no el
 * vocabulario.
 *
 * ════════════════════════════════════════════════════════════════════════════
 * LA REGLA QUE DECIDE QUÉ ENTRA AQUÍ
 * ════════════════════════════════════════════════════════════════════════════
 *
 * **Una primitiva nueva solo se gana el sitio si dice algo que una caja NO
 * puede decir.** No "algo que se vería mejor": algo que la caja no puede
 * expresar. Por eso son cuatro y no doce:
 *
 * · `circulo`    — «aquí EMPIEZA un tema». La forma redonda dice encabezado;
 *                  una caja diría paso, y entonces habría que rotularlo.
 * · `momentum`   — «esto CRECE». El tamaño ES el dato. Cinco cajas iguales con
 *                  un rótulo "crece" es contarlo, no enseñarlo.
 * · `termometro` — «esto se LLENA hasta aquí». Un porcentaje escrito se lee;
 *                  un tubo lleno hasta el 20% se entiende sin leer.
 * · `parrilla`   — «esto es UN inventario de N cosas». Doce cajas sueltas son
 *                  doce cosas; una rejilla es una sola idea con doce entradas.
 *
 * ⚠️ Y lo que NO entró, a propósito: la "placa de fase" (una tarjeta con borde
 * grueso ya lo hace) y la "prosa resaltada" (es texto con un resaltado, no una
 * forma nueva). La válvula del estándar manda: primero etiqueta, luego forma.
 *
 * ⚠️ **La expresividad es de Mateo; los colores son NUESTROS.** Todo lo de aquí
 * pinta con los tintes del tema y su rampa. Copiar su rojo sería fallar dos
 * veces: perder nuestra marca y no ganar la suya.
 */
extension Pintor {

    // ════════════════════════════════════════════════════════════════════════
    // MARK: - Utilidades comunes
    // ════════════════════════════════════════════════════════════════════════

    /// Los tres tonos del territorio de un elemento. Todo lo didáctico se pinta
    /// con ellos, nunca con un literal: es la RAMPA del estándar, usada de
    /// verdad y no al 10%.
    func tonos(_ e: Elemento) -> (tenue: NSColor, medio: NSColor, fuerte: NSColor) {
        let t = e.crudo["tint"]?.s ?? "neutro"
        return (tema.rampa(t, 0.12), tema.rampa(t, 0.55), tema.tintes[t]?.trazo ?? tema.acento)
    }

    /// Texto centrado en una caja, cortado a lo ancho y con la tinta que de
    /// verdad se lee sobre ese fondo (`Tema.tintaSobre`, regla de contraste).
    func dTextoCentrado(_ s: String, en r: CGRect, tam tamPedido: Double, peso: Double,
                        sobre fondo: NSColor?, color: NSColor? = nil, mono: Bool = false) {
        /*
         * ⚠️ ANTES DE TRUNCAR, ENCOGER.
         *
         * Una palabra sola que no cabe no se puede partir, así que el envoltorio
         * la truncaba: "Onboardi…". Un rótulo truncado no nombra nada — y en una
         * parrilla, donde la celda es fija, pasa constantemente.
         *
         * Se baja el tamaño hasta que la palabra más larga quepa (con suelo:
         * por debajo de 10pt ya no se lee y entonces sí toca truncar, que es
         * información honesta de que ahí no cabe).
         */
        var tam = tamPedido
        let ancho = r.width - 16
        let masLarga = s.split(separator: " ").map(String.init).max { wAncho($0, tam: tam, peso: peso, mono: mono) < wAncho($1, tam: tam, peso: peso, mono: mono) } ?? s
        while tam > 10, wAncho(masLarga, tam: tam, peso: peso, mono: mono) > ancho { tam -= 1 }
        let lineas = wEnvolver(s, ancho: ancho, tam: tam, peso: peso,
                              lineas: max(1, Int(r.height / (tam * 1.25))))
        let alto = Double(lineas.count) * tam * 1.25
        var y = r.midY - alto / 2
        let tinta = color ?? (fondo.map { Tema.tintaSobre($0) } ?? tema.tituloTexto)
        for l in lineas {
            let w = wAncho(l, tam: tam, peso: peso, mono: mono)
            wTexto(l, CGPoint(x: r.midX - w / 2, y: y), tam: tam, peso: peso, color: tinta, mono: mono)
            y += tam * 1.25
        }
    }

    /// Una flecha CURVA entre dos puntos, con su punta. Las del estándar son
    /// ortogonales porque conectan procesos; estas acompañan una metáfora y por
    /// eso van curvas — el arco es parte de lo que se cuenta (el impulso).
    func dFlechaCurva(_ a: CGPoint, _ b: CGPoint, alto: Double, color: NSColor, grosor: Double = 3) {
        let ctrl = CGPoint(x: (a.x + b.x) / 2, y: min(a.y, b.y) - alto)
        let p = CGMutablePath()
        p.move(to: a)
        p.addQuadCurve(to: b, control: ctrl)
        ctx.saveGState()
        ctx.addPath(p)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(grosor)
        ctx.setLineCap(.round)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.strokePath()
        // La punta, orientada por la tangente en el final de la curva.
        let dx = b.x - ctrl.x, dy = b.y - ctrl.y
        let ang = atan2(dy, dx)
        let l = grosor * 3.2
        let t = CGMutablePath()
        t.move(to: b)
        t.addLine(to: CGPoint(x: b.x - cos(ang - 0.42) * l, y: b.y - sin(ang - 0.42) * l))
        t.addLine(to: CGPoint(x: b.x - cos(ang + 0.42) * l, y: b.y - sin(ang + 0.42) * l))
        t.closeSubpath()
        ctx.addPath(t); ctx.setFillColor(color.cgColor); ctx.fillPath()
        ctx.restoreGState()
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: - 1. CÍRCULO — «aquí empieza un tema»
    // ════════════════════════════════════════════════════════════════════════

    /**
     * La entrada de una sección. Redondo a propósito: en el vocabulario, una
     * caja es un PASO y un rombo una DECISIÓN — un encabezado no es ninguna de
     * las dos, y sin forma propia había que rotularlo ("SECCIÓN: …"), que es
     * exactamente contar en vez de enseñar.
     *
     * Es el device con el que Mateo abre cada isla de su tablero ("FORMAS DE
     * VENDER", "THE OLD WAY", "OBJETIVO"), y funciona porque el ojo lo separa
     * del contenido antes de leerlo.
     */
    func circuloDidactico(_ e: Elemento) {
        let r = e.caja
        let c = tonos(e)
        ctx.saveGState()
        ctx.setAlpha(e.opacidad)
        let p = CGMutablePath()
        p.addEllipse(in: r)
        ctx.addPath(p); ctx.setFillColor(c.tenue.cgColor); ctx.fillPath()
        ctx.addPath(p)
        ctx.setStrokeColor(c.fuerte.cgColor)
        ctx.setLineWidth(e.grosorLinea ?? 3)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.strokePath()
        if let t = e.crudo["rotulo"]?.s {
            dTextoCentrado(t.uppercased(), en: r.insetBy(dx: 14, dy: 10),
                           tam: e.crudo["tam"]?.num ?? 19, peso: 800, sobre: c.tenue)
        }
        ctx.restoreGState()
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: - 2. MOMENTUM — «esto crece»
    // ════════════════════════════════════════════════════════════════════════

    /**
     * La bola de nieve: N círculos que CRECEN de izquierda a derecha, unidos por
     * arcos. El tamaño ES el dato.
     *
     * ⚠️ Por qué esto no es "cinco cajas con una etiqueta que dice crece": una
     * caja igual a la anterior con la palabra "más" al lado obliga a creerte el
     * texto. Un círculo que mide el doble no hay que creérselo. Es la diferencia
     * entre contar y enseñar, que es de lo que va toda esta piel.
     *
     * `momentum: {items: ["mes 1", "mes 2", …], pie?: "…"}`
     */
    func momentumDidactico(_ e: Elemento) {
        guard let items = e.crudo["momentum"]?["items"]?.arr?.compactMap({ $0.s }), items.count >= 2 else { return }
        let r = e.caja
        let c = tonos(e)
        ctx.saveGState()
        ctx.setAlpha(e.opacidad)

        let n = items.count
        let pie = e.crudo["momentum"]?["pie"]?.s
        // Aire abajo para los rótulos que no caben dentro de su bola.
        let altoPie = (pie != nil ? 26.0 : 0) + 44   // dos filas de rótulos
        let zona = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height - altoPie)
        // El diámetro crece linealmente del 34% al 100% del alto disponible: el
        // primero tiene que verse pequeño DE VERDAD o la metáfora no arranca.
        let dMax = min(zona.height, zona.width / (Double(n) * 0.78))
        func diam(_ i: Int) -> Double { dMax * (0.34 + 0.66 * Double(i) / Double(n - 1)) }
        let total = (0..<n).reduce(0.0) { $0 + diam($1) }
        let hueco = max(10, (zona.width - total) / Double(n - 1))
        var x = zona.minX
        var centros: [(CGPoint, Double)] = []
        // Los que no caben dentro de su bola: se colocan al final, escalonados.
        var fuera: [(Int, CGPoint, Double)] = []
        for i in 0..<n {
            let d = diam(i)
            let cen = CGPoint(x: x + d / 2, y: zona.maxY - d / 2)
            centros.append((cen, d))
            x += d + hueco
        }
        // Los arcos van PRIMERO: por debajo de las bolas, como en el referente.
        for i in 0..<(n - 1) {
            let (a, da) = centros[i], (b, db) = centros[i + 1]
            dFlechaCurva(CGPoint(x: a.x + da / 2 * 0.72, y: a.y - da / 2 * 0.72),
                         CGPoint(x: b.x - db / 2 * 0.80, y: b.y - db / 2 * 0.62),
                         alto: dMax * 0.30, color: c.fuerte, grosor: 2.5)
        }
        for (i, (cen, d)) in centros.enumerated() {
            let caja = CGRect(x: cen.x - d / 2, y: cen.y - d / 2, width: d, height: d)
            let p = CGMutablePath(); p.addEllipse(in: caja)
            // El tono también sube con el tamaño: dos canales diciendo lo mismo.
            let t = Double(i) / Double(n - 1)
            let relleno = c.tenue.blended(withFraction: t * 0.85, of: c.fuerte) ?? c.tenue
            ctx.addPath(p); ctx.setFillColor(relleno.cgColor); ctx.fillPath()
            ctx.addPath(p); ctx.setStrokeColor(c.fuerte.cgColor); ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: []); ctx.strokePath()
            /*
             * ⚠️ EL RÓTULO SALE FUERA CUANDO NO CABE DENTRO.
             *
             * La primera versión lo metía siempre dentro del círculo, y en las
             * bolas pequeñas —que son justo las que empiezan la metáfora— salía
             * "1 vi…", "cade…", "audien…". Un rótulo truncado no nombra nada, y
             * encima rompe lo que la forma acababa de decir bien.
             *
             * Se mide si cabe. Si no, va DEBAJO: la bola sigue diciendo el
             * tamaño y la palabra sigue siendo legible. Las dos cosas que se
             * querían, en vez de media de cada una.
             */
            let tam = max(12.0, min(21.0, d * 0.17))
            let cabe = wAncho(items[i], tam: tam, peso: 800, mono: false) <= d * 0.78
            if cabe {
                dTextoCentrado(items[i], en: caja, tam: tam, peso: 800, sobre: relleno)
            } else {
                fuera.append((i, cen, caja.maxY))
            }
        }
        /*
         * ⚠️ LOS RÓTULOS DE FUERA SE ESCALONAN CUANDO SE PISARÍAN.
         *
         * Las bolas pequeñas van juntas —es lo que hace que la serie arranque
         * apretada y se abra— así que sus rótulos, que son más anchos que
         * ellas, se solapaban: "entra al LT" y "compra el anual" salían uno
         * encima del otro y no se leía ninguno de los dos. Dos palabras
         * ilegibles son peor que una: la primera al menos se entendía.
         *
         * Se mide el solape real contra el anterior COLOCADO, no contra el
         * vecino de índice: con tres seguidos que chocan, alternar a ciegas
         * volvería a juntar el primero y el tercero.
         */
        let tRot = 15.0
        var ocupadoHasta: [Double] = [-1e9, -1e9]   // borde derecho por fila
        for (i, cen, base) in fuera {
            let w = wAncho(items[i], tam: tRot, peso: 800, mono: false)
            let x = cen.x - w / 2
            let fila = x > ocupadoHasta[0] + 8 ? 0 : 1
            ocupadoHasta[fila] = x + w
            wTexto(items[i], CGPoint(x: x, y: base + 6 + Double(fila) * 21),
                   tam: tRot, peso: 800, color: tema.cuerpoTexto)
        }
        if let pie {
            wTexto(pie, CGPoint(x: r.minX, y: r.maxY - 18), tam: 16, peso: 600, color: tema.pieTexto)
        }
        ctx.restoreGState()
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: - 3. TERMÓMETRO — «esto se llena hasta aquí»
    // ════════════════════════════════════════════════════════════════════════

    /**
     * Un tubo con bulbo que se llena hasta un porcentaje. El device con el que
     * Mateo enseña el calentamiento de un lead (20% → 60% → 90%).
     *
     * ⚠️ Un porcentaje ESCRITO se lee y se compara con esfuerzo; un tubo lleno
     * hasta un tercio se entiende antes de leer nada. Por eso el número también
     * está —no se esconde el dato— pero el que hace el trabajo es el relleno.
     *
     * `termometro: {pct: 20, rotulo: "Día 1", pie?: "…"}`
     * **`pct` ausente ⇒ tubo VACÍO con «sin dato»**, jamás un 0 pintado como
     * medición (`dato-ausente-no-es-cero`).
     */
    func termometroDidactico(_ e: Elemento) {
        guard let j = e.crudo["termometro"] else { return }
        let r = e.caja
        let c = tonos(e)
        ctx.saveGState()
        ctx.setAlpha(e.opacidad)

        let pct = j["pct"]?.num
        let rotulo = j["rotulo"]?.s
        let altoRot = rotulo != nil ? 24.0 : 0
        let cuerpo = CGRect(x: r.minX, y: r.minY + 22, width: r.width, height: r.height - 22 - altoRot)
        let dBulbo = min(cuerpo.width * 0.86, cuerpo.height * 0.36)
        let anchoTubo = dBulbo * 0.42
        let tubo = CGRect(x: cuerpo.midX - anchoTubo / 2, y: cuerpo.minY,
                          width: anchoTubo, height: cuerpo.height - dBulbo * 0.72)
        let bulbo = CGRect(x: cuerpo.midX - dBulbo / 2, y: cuerpo.maxY - dBulbo,
                           width: dBulbo, height: dBulbo)

        // El vidrio.
        let vidrio = CGMutablePath()
        vidrio.addRoundedRectSeguro(in: tubo, cornerWidth: anchoTubo / 2, cornerHeight: anchoTubo / 2)
        vidrio.addEllipse(in: bulbo)
        ctx.addPath(vidrio); ctx.setFillColor(c.tenue.cgColor); ctx.fillPath()
        ctx.addPath(vidrio); ctx.setStrokeColor(c.fuerte.cgColor); ctx.setLineWidth(2.5)
        ctx.setLineDash(phase: 0, lengths: []); ctx.strokePath()

        // El bulbo SIEMPRE lleno: es el depósito, no la medida. Vacío parecería
        // un termómetro roto.
        let dentro = bulbo.insetBy(dx: 4, dy: 4)
        let pb = CGMutablePath(); pb.addEllipse(in: dentro)
        ctx.addPath(pb); ctx.setFillColor(c.fuerte.cgColor); ctx.fillPath()

        if let pct {
            let f = max(0, min(1, pct / 100))
            let hCol = tubo.height * f
            let col = CGRect(x: tubo.minX + 4, y: tubo.maxY - hCol, width: tubo.width - 8, height: hCol)
            if hCol > 2 {
                let pc = CGMutablePath()
                pc.addRoundedRectSeguro(in: col, cornerWidth: col.width / 2, cornerHeight: col.width / 2)
                ctx.addPath(pc); ctx.setFillColor(c.fuerte.cgColor); ctx.fillPath()
            }
            let et = "\(Int(pct.rounded()))%"
            let w = wAncho(et, tam: 18, peso: 800, mono: true)
            wTexto(et, CGPoint(x: cuerpo.midX - w / 2, y: r.minY), tam: 18, peso: 800,
                   color: c.fuerte, mono: true)
        } else {
            let et = "sin dato"
            let w = wAncho(et, tam: 13, peso: 600, mono: true)
            wTexto(et, CGPoint(x: cuerpo.midX - w / 2, y: r.minY + 3), tam: 13, peso: 600,
                   color: tema.pieTexto, mono: true)
        }
        // Las marcas del vidrio: cuatro rayitas, lo justo para que se lea como
        // un instrumento y no como un tubo de color.
        ctx.setStrokeColor(c.fuerte.withAlphaComponent(0.5).cgColor); ctx.setLineWidth(1.5)
        for k in 1...4 {
            let y = tubo.minY + tubo.height * Double(k) / 5
            ctx.move(to: CGPoint(x: tubo.minX + 3, y: y))
            ctx.addLine(to: CGPoint(x: tubo.minX + tubo.width * 0.45, y: y))
        }
        ctx.strokePath()

        if let rotulo {
            let w = wAncho(rotulo, tam: 15, peso: 700, mono: false)
            wTexto(rotulo, CGPoint(x: cuerpo.midX - w / 2, y: r.maxY - 18), tam: 15, peso: 700,
                   color: tema.cuerpoTexto)
        }
        ctx.restoreGState()
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: - 4. PARRILLA — «esto es UN inventario de N cosas»
    // ════════════════════════════════════════════════════════════════════════

    /**
     * Una rejilla de celdas rotuladas dentro de un marco grueso.
     *
     * ⚠️ Doce cajas sueltas son doce cosas que el ojo cuenta una por una. Una
     * rejilla es UNA idea con doce entradas: se percibe como bloque y se lee al
     * detalle solo si hace falta. Es exactamente lo que hace Mateo con sus 12
     * formas de vender, y la diferencia entre un inventario y una sopa.
     *
     * `parrilla: {celdas: [...], columnas: 3}`
     */
    func parrillaDidactica(_ e: Elemento) {
        guard let celdas = e.crudo["parrilla"]?["celdas"]?.arr?.compactMap({ $0.s }), !celdas.isEmpty else { return }
        let cols = max(1, Int(e.crudo["parrilla"]?["columnas"]?.num ?? 3))
        let filas = Int(ceil(Double(celdas.count) / Double(cols)))
        let r = e.caja
        let c = tonos(e)
        ctx.saveGState()
        ctx.setAlpha(e.opacidad)

        // El MARCO grueso es lo que convierte doce celdas en un inventario.
        let marco = CGMutablePath()
        marco.addRoundedRectSeguro(in: r, cornerWidth: 8, cornerHeight: 8)
        ctx.addPath(marco); ctx.setFillColor(c.fuerte.cgColor); ctx.fillPath()

        let pad = 9.0
        let interior = r.insetBy(dx: pad, dy: pad)
        let wCel = (interior.width - Double(cols - 1) * pad) / Double(cols)
        let hCel = (interior.height - Double(filas - 1) * pad) / Double(filas)
        for (i, texto) in celdas.enumerated() {
            let cx = interior.minX + Double(i % cols) * (wCel + pad)
            let cy = interior.minY + Double(i / cols) * (hCel + pad)
            let caja = CGRect(x: cx, y: cy, width: wCel, height: hCel)
            let p = CGMutablePath()
            p.addRoundedRectSeguro(in: caja, cornerWidth: 4, cornerHeight: 4)
            ctx.addPath(p); ctx.setFillColor(tema.rol("card").relleno.cgColor); ctx.fillPath()
            dTextoCentrado(texto, en: caja.insetBy(dx: 6, dy: 4),
                           tam: e.crudo["parrilla"]?["tam"]?.num ?? 15, peso: 700,
                           sobre: tema.rol("card").relleno)
        }
        ctx.restoreGState()
    }
}
