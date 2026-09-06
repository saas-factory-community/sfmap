import AppKit

/// El sistema de diseño del Business OS, en AppKit.
///
/// ⚠️ EXISTE PORQUE LA PRIMERA VERSIÓN NO LO TENÍA. sfmap pintaba el lienzo con
/// el tema del sistema y lo rodeaba de cromo genérico de macOS: un
/// `NSPopUpButton` gris, la fuente del sistema, una barra de vidrio. Daniel:
/// *"olvidamos el sistema y el diseño tan hermoso, ¿qué pasó ahí?"*. Tenía
/// razón — el lienzo hablaba un idioma y la ventana otro.
///
/// LA GRAMÁTICA, leída del lienzo web:
///   · Nada es una barra pegada al borde. Todo son TARJETAS FLOTANTES con
///     esquina 14, borde de 1px y sombra suave, separadas del borde por aire.
///   · La tipografía es Montserrat, la misma del contenido. La del sistema
///     delata al instante que la ventana no es de la misma casa.
///   · El morado de marca solo marca lo ACTIVO. Un morado repartido por todo
///     deja de significar nada.
enum Estilo {
    static let radio: CGFloat = 14
    static let radioChico: CGFloat = 9
    static let aire: CGFloat = 14

    /*
     * EL ZOOM DEL SISTEMA (24 ago 2026). El lienzo tiene su zoom; el CROMO
     * (rail, panel, barra de estado, minimapa) tiene el suyo: pellizcar con el
     * puntero FUERA del lienzo lo escala. Los topes existen porque un cromo a
     * 0.3 es invisible y a 3 tapa el documento — y el ancho del panel tiene
     * suelo (deja de caber un nombre) y techo (deja de haber lienzo).
     */
    static func clampEscalaUI(_ s: CGFloat) -> CGFloat { min(1.6, max(0.7, s)) }
    static func clampAnchoLateral(_ w: CGFloat) -> CGFloat { min(480, max(220, w)) }

    /**
     * LA FUENTE QUE CABE. Un rótulo cortado es peor que no poner rótulo.
     *
     * El 23 ago 2026 el rail estrenó el nombre de la herramienta a 9 pt fijos
     * dentro de una caja de 48 px, y "Seleccionar" se leía "SELECCIO": un
     * instrumento que se corta a sí mismo se ve roto, no apretado. Aquí se MIDE
     * la palabra y se baja de medio en medio hasta que entra, con un suelo por
     * debajo del cual dejaría de leerse.
     */
    static func fuenteQueCabe(_ texto: String, ancho: CGFloat, desde: CGFloat,
                              hasta: CGFloat, peso: CGFloat = 600) -> NSFont {
        var tam = desde
        while tam > hasta {
            let f = fuente(tam, peso)
            if (texto as NSString).size(withAttributes: [.font: f]).width <= ancho { return f }
            tam -= 0.5
        }
        return fuente(hasta, peso)
    }

    static func fuente(_ tamano: CGFloat, _ peso: CGFloat = 600) -> NSFont {
        // La misma familia y el mismo archivo que el contenido. Si faltara, se
        // cae a la del sistema en vez de no pintar nada.
        let f = Fuentes.fuente(familia: "montserrat", peso: Double(peso), tamano: Double(tamano), cursiva: false)
        return (f as NSFont?) ?? .systemFont(ofSize: tamano, weight: peso >= 700 ? .bold : .semibold)
    }

    /**
     * LA MONO DEL CROMO. Un número no es una palabra.
     *
     * Regla de la casa (núcleo de marca §5): *"el monospace SOLO aparece en
     * chrome —counter, terminal, código, datos—, nunca en el body"*. El zoom, la
     * cuenta de elementos y los rótulos de sección son exactamente eso: lectura
     * de instrumento. En Montserrat el `100%` bailaba de ancho al pasar de 90 a
     * 100 y el ojo lo lee como que algo se movió; en una mono de ancho fijo, el
     * dígito cambia y la aguja no.
     *
     * Es el MISMO archivo que ya viaja dentro de la app y que mide el
     * compilador. Cero fuentes nuevas.
     */
    static func mono(_ tamano: CGFloat, _ peso: CGFloat = 600) -> NSFont {
        let f = Fuentes.fuente(familia: "jetbrains-mono", peso: Double(peso), tamano: Double(tamano), cursiva: false)
        return (f as NSFont?) ?? .monospacedDigitSystemFont(ofSize: tamano, weight: .semibold)
    }

    /**
     * EL BISEL Y LA PANTALLA — por qué el cromo se ve así y no como Miro.
     *
     * El sistema de Daniel (Titaniumorphism) tiene UNA primitiva: una pieza de
     * titanio mecanizado con la luz cayendo desde arriba, rodeando una pantalla.
     * Aquí eso se reparte solo: **el lienzo es la pantalla** —blanco, didáctico,
     * intocable porque va a salir en video— y **todo el cromo es el bisel**.
     *
     * Antes cada panel era un relleno plano con un borde de 1 px del mismo tono
     * en los cuatro lados. Eso no es una superficie: es un rectángulo. Un bisel
     * de verdad son tres cosas juntas, y hacen falta las tres:
     *
     *   1. GRADIENTE vertical (claro arriba → oscuro abajo). Es de dónde viene
     *      la luz. Sin él la pieza no tiene orientación.
     *   2. FILO SUPERIOR más claro que el borde lateral. Es el canto que la luz
     *      pega de frente. Es lo que separa "metal" de "papel gris".
     *   3. RIM: una hebra casi blanca justo dentro del filo. Es el brillo
     *      especular del canto vivo, y es el detalle que hace que se vea caro.
     *
     * ⚠️ Los seis colores NO se inventaron aquí. Están escritos en el panel del
     * estudio de Daniel (`entorno-fisico/panel.html`, 16 ago 2026), que ya
     * define el titanio en SUS DOS temas — oscuro (titanio) y claro (aluminio
     * pulido). Escribirlos de memoria habría sido inventar un séptimo par.
     */
    struct Bisel {
        var top: NSColor, mid: NSColor, bot: NSColor
        var borde: NSColor, filoAlto: NSColor, rim: NSColor
    }

    /**
     * Pinta una superficie de bisel dentro de `v.bounds`.
     *
     * `pozo: true` la invierte: oscuro arriba, claro abajo, y el filo vivo pasa
     * al canto INFERIOR. Es lo que hace la luz con un hueco en vez de un bulto,
     * y por eso un campo de búsqueda y un botón pulsado se leen como "entra"
     * sin que nadie tenga que explicarlo.
     *
     * ⚠️ Respeta `isFlipped`. El rail y el árbol están volteados y el resto no;
     * pintar el gradiente al derecho en una vista volteada deja la luz saliendo
     * del suelo, que es el tipo de error que se ve raro sin saber por qué.
     */
    static func pintarBisel(_ v: NSView, _ t: Tema, radio r: CGFloat = radio,
                            pozo: Bool = false, borde: Bool = true) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        let b = v.bounds
        guard b.width > 2, b.height > 2 else { return }
        let bz = t.bisel
        let camino = CGPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5),
                            cornerWidth: r, cornerHeight: r, transform: nil)
        let yArriba = v.isFlipped ? b.minY : b.maxY
        let yAbajo = v.isFlipped ? b.maxY : b.minY
        let haciaAbajo: CGFloat = v.isFlipped ? 1 : -1

        c.saveGState()
        c.addPath(camino); c.clip()

        /*
         * La banda de luz vive ARRIBA, no repartida por todo el alto.
         *
         * Con tres paradas equidistantes, una tarjeta de 44 px se ve preciosa y
         * un panel lateral de 1000 px se ve como un degradado de fondo de web de
         * 2010. En metal real la transición ocurre en el canto: unos milímetros.
         * Por eso la parada intermedia se ancla a ~90 px de la parte de arriba y
         * el resto del alto lo ocupa el asentado lento hacia el fondo.
         */
        let quiebre = min(0.55, 90 / max(1, b.height))
        let cols = pozo ? [bz.bot, bz.mid, bz.top] : [bz.top, bz.mid, bz.bot]
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: cols.map { $0.cgColor } as CFArray,
                              locations: [0, quiebre, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: b.midX, y: yArriba),
                                 end: CGPoint(x: b.midX, y: yAbajo), options: [])
        }

        // El canto que la luz pega de frente: arriba si sobresale, abajo si hunde.
        let yFilo = pozo ? yAbajo - haciaAbajo * 0.5 : yArriba + haciaAbajo * 0.5
        c.setLineWidth(1)
        c.setStrokeColor(bz.filoAlto.cgColor)
        c.move(to: CGPoint(x: b.minX, y: yFilo)); c.addLine(to: CGPoint(x: b.maxX, y: yFilo))
        c.strokePath()
        if !pozo {
            // El rim: la hebra especular, una hilera por dentro del filo.
            c.setStrokeColor(bz.rim.cgColor)
            let yRim = yArriba + haciaAbajo * 1.5
            c.move(to: CGPoint(x: b.minX, y: yRim)); c.addLine(to: CGPoint(x: b.maxX, y: yRim))
            c.strokePath()
        }
        c.restoreGState()

        if borde {
            c.addPath(camino)
            c.setStrokeColor(bz.borde.cgColor)
            c.setLineWidth(1)
            c.strokePath()
        }
    }

    /**
     * EL CANTO HUNDIDO — lo que remata la metáfora.
     *
     * Todo el cromo es bisel y el tablero es la pantalla. Pero una pantalla
     * pegada al ras del metal no existe: va METIDA, y lo que lo dice es la
     * sombra que el marco proyecta sobre ella —más fuerte arriba y a la
     * izquierda, que es de donde cae la luz en todo el sistema.
     *
     * Vive en los 11 px del borde del viewport, así que no toca el contenido, y
     * sobre todo NO TOCA LA EXPORTACIÓN: el PNG se pinta en su propio contexto a
     * partir de los elementos, nunca de esta vista. Lo que Daniel sube a un
     * video sigue saliendo limpio.
     *
     * ⚠️ El lienzo está VOLTEADO y las tarjetas no. Escrito con `bounds.maxY`
     * como "arriba" —que es lo natural— la sombra fuerte salía en el borde de
     * ABAJO justo en la superficie más grande de la ventana. Por eso vive aquí,
     * con el mismo cuidado que `pintarBisel`, y no copiada en cada vista.
     */
    static func cantoHundido(_ v: NSView, _ tema: Tema) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        let b = v.bounds
        guard b.width > 4, b.height > 4 else { return }
        let fuerza = tema.nombre == "oscuro" ? 0.42 : 0.075
        let hondo = 11.0
        let yArriba = v.isFlipped ? b.minY : b.maxY
        let yAbajo = v.isFlipped ? b.maxY : b.minY
        let haciaDentro: CGFloat = v.isFlipped ? 1 : -1

        func banda(_ recorte: CGRect, _ desde: CGPoint, _ hasta: CGPoint, _ f: Double) {
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [NSColor.black.withAlphaComponent(fuerza * f).cgColor,
                                              NSColor.black.withAlphaComponent(0).cgColor] as CFArray,
                                     locations: [0, 1]) else { return }
            c.saveGState(); c.clip(to: recorte)
            c.drawLinearGradient(g, start: desde, end: hasta, options: [])
            c.restoreGState()
        }
        // Arriba (la más marcada) y a la izquierda: de ahí viene la luz.
        banda(CGRect(x: b.minX, y: min(yArriba, yArriba + haciaDentro * hondo),
                     width: b.width, height: hondo),
              CGPoint(x: 0, y: yArriba), CGPoint(x: 0, y: yArriba + haciaDentro * hondo), 1.0)
        banda(CGRect(x: b.minX, y: b.minY, width: hondo, height: b.height),
              CGPoint(x: b.minX, y: 0), CGPoint(x: b.minX + hondo, y: 0), 0.85)
        // Y las dos de rebote, mucho más flojas: sin ellas el tablero parece
        // colgado de dos lados en vez de encajado en un marco.
        banda(CGRect(x: b.minX, y: min(yAbajo, yAbajo - haciaDentro * hondo),
                     width: b.width, height: hondo),
              CGPoint(x: 0, y: yAbajo), CGPoint(x: 0, y: yAbajo - haciaDentro * hondo), 0.26)
        banda(CGRect(x: b.maxX - hondo, y: b.minY, width: hondo, height: b.height),
              CGPoint(x: b.maxX, y: 0), CGPoint(x: b.maxX - hondo, y: 0), 0.26)
    }

    /**
     * UN VISOR HUNDIDO EN LA PLACA.
     *
     * Las dos piezas de abajo son la misma idea: una placa de titanio con algo
     * HUNDIDO dentro que se lee. En el minimapa lo hundido es el documento en
     * miniatura; en la barra, el número del zoom. Antes cada una lo resolvía a
     * su manera y se veían de dos familias, que es justo lo que Daniel señaló
     * — *"hazlos también el mismo diseño, así como el minimapa"*.
     *
     * Lo único que cambia entre las dos es el RELLENO, y ese delta es honesto:
     * uno enseña el lienzo y lleva el color del lienzo; el otro es un rótulo y
     * lleva el de la placa. Todo lo demás —radio, la sombra que el marco
     * proyecta sobre el fondo, el borde— sale de aquí una sola vez.
     */
    static func pintarVisor(_ v: NSView, _ tema: Tema, en r: CGRect,
                            relleno: NSColor, radio: CGFloat = 7) {
        guard let c = NSGraphicsContext.current?.cgContext, r.width > 2, r.height > 2 else { return }
        let camino = CGPath(roundedRect: r, cornerWidth: radio, cornerHeight: radio, transform: nil)
        c.addPath(camino); c.setFillColor(relleno.cgColor); c.fillPath()
        // La sombra del marco cayendo dentro. Sin ella, un color plano dentro
        // de metal se ve PEGADO encima en vez de hundido.
        c.saveGState()
        c.addPath(camino); c.clip()
        c.setStrokeColor(NSColor.black.withAlphaComponent(tema.nombre == "oscuro" ? 0.55 : 0.11).cgColor)
        c.setLineWidth(1)
        let yAlto = v.isFlipped ? r.minY + 0.5 : r.maxY - 0.5
        c.move(to: CGPoint(x: r.minX, y: yAlto)); c.addLine(to: CGPoint(x: r.maxX, y: yAlto))
        c.strokePath()
        c.restoreGState()
        c.addPath(camino); c.setStrokeColor(tema.bisel.borde.cgColor)
        c.setLineWidth(1); c.strokePath()
    }

    /// Una tarjeta flotante. La unidad de toda la interfaz.
    ///
    /// Deja el radio y la sombra en la capa —que es donde AppKit las sabe
    /// componer— y le pasa la PINTURA a `pintarBisel`, en `draw`. Un gradiente
    /// no cabe en `layer.backgroundColor`, y meterlo como sublayer obliga a
    /// perseguir el tamaño y la geometría volteada a mano en siete sitios.
    static func tarjeta(_ v: NSView, tema: Tema, radio r: CGFloat = radio) {
        v.wantsLayer = true
        guard let l = v.layer else { return }
        l.cornerRadius = r
        l.cornerCurve = .continuous
        l.backgroundColor = NSColor.clear.cgColor
        l.borderWidth = 0
        l.shadowColor = NSColor.black.cgColor
        // Sobre lienzo blanco, la sombra es la mitad de la separación: sin
        // ella una placa clara y un tablero blanco son la misma superficie.
        l.shadowOpacity = tema.nombre == "oscuro" ? 0.55 : 0.20
        l.shadowRadius = tema.nombre == "oscuro" ? 18 : 22
        l.shadowOffset = CGSize(width: 0, height: -7)
        l.masksToBounds = false
        v.needsDisplay = true
    }

    /// El acento a baja opacidad, para fondos de estado activo.
    static func acentoSuave(_ t: Tema) -> NSColor {
        t.nombre == "oscuro" ? NSColor(hex: "#a95cff33")! : NSColor(hex: "#8C27F11f")!
    }
    static func hover(_ t: Tema) -> NSColor {
        t.nombre == "oscuro" ? NSColor(white: 1, alpha: 0.07) : NSColor(white: 0, alpha: 0.05)
    }
}

/**
 * Una tarjeta que se pinta sola.
 *
 * Existe porque los paneles emergentes —zoom, exportar, variantes del rail,
 * fondo— se creaban como `NSView` pelados y `Estilo.tarjeta` les ponía un
 * relleno plano. Al pasar la pintura a `draw`, un `NSView` pelado deja de
 * pintar nada: se quedaban invisibles. Esta clase es el reemplazo directo, y de
 * paso hace que ningún panel futuro se olvide del bisel.
 */
final class Tarjeta: NSView {
    var tema: Tema
    var radio: CGFloat
    init(tema: Tema, radio: CGFloat = Estilo.radio) {
        self.tema = tema; self.radio = radio
        super.init(frame: .zero)
        Estilo.tarjeta(self, tema: tema, radio: radio)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) { Estilo.pintarBisel(self, tema, radio: radio) }
}

extension Estilo {
    /**
     * EL BISEL DE LOS ICONOS — un solo diseño para todos los glifos de la app.
     *
     * Elegido por Daniel el 24 ago 2026 sobre una matriz de 5 tratamientos: el
     * glifo deja de ser tinta plana y se vuelve una pieza de titanio con
     * gradiente, filo de luz arriba y sombra de corte abajo — el mismo lenguaje
     * que `pintarBisel` le da a las superficies, aplicado al dibujo.
     *
     * Se construye desde el ALPHA del icono plantilla en tres estampas
     * (transparency layers): sombra desplazada abajo, luz desplazada arriba, y
     * el cuerpo con el gradiente encima. Asi CUALQUIER icono existente o futuro
     * recibe el tratamiento sin redibujarse.
     *
     * `tinte` colorea el cuerpo (morado = activo, oro = donde estas, rojo =
     * riesgo, blanco = sobre acento solido); sin tinte, titanio neutro del tema.
     */
    private static var cacheIconoBisel: [String: NSImage] = [:]

    static func iconoBisel(_ base: NSImage, _ t: Tema, tinte: NSColor? = nil) -> NSImage {
        let llave = "\(ObjectIdentifier(base).hashValue)·\(t.nombre)·\(tinte?.descripcionLlave ?? "ti")·\(base.size.width)"
        if let hecha = cacheIconoBisel[llave] { return hecha }
        let oscuro = t.nombre == "oscuro"
        let tam = base.size
        let caja = NSRect(origin: .zero, size: tam)

        let arriba: NSColor
        let abajo: NSColor
        if let tinte {
            arriba = tinte.blended(withFraction: 0.32, of: .white) ?? tinte
            abajo = tinte.blended(withFraction: 0.24, of: .black) ?? tinte
        } else if oscuro {
            arriba = NSColor(hex: "#F7F7F9") ?? .white
            abajo = NSColor(hex: "#A2A3B0") ?? .lightGray
        } else {
            arriba = NSColor(hex: "#7A7B86") ?? .darkGray
            abajo = NSColor(hex: "#4A4B55") ?? .darkGray
        }
        let sombra = NSColor.black.withAlphaComponent(oscuro ? 0.60 : 0.26)
        let luz = NSColor.white.withAlphaComponent(oscuro ? 0.50 : 0.88)

        /*
         * ⚠️ SIN DILATACIÓN. La primera versión "engrosaba" estampando el glifo
         * en un anillo de 9 sub-offsets fraccionarios, y el antialiasing
         * apilado salía SUCIO — Daniel, 24 ago: *"lucen raros, como sucios,
         * borrosos"*. Tenía razón: nueve copias a medio píxel no son un trazo
         * grueso, son un halo. El grosor correcto vive en el GLIFO (los iconos
         * de herramienta son sólidos desde hoy), y aquí solo quedan tres
         * estampas limpias a offsets ENTEROS.
         */
        // Una estampa: el glifo desplazado, coloreado plano via sourceIn.
        func estampa(_ c: CGContext, dy: CGFloat, color: NSColor) {
            c.beginTransparencyLayer(auxiliaryInfo: nil)
            base.draw(in: caja.offsetBy(dx: 0, dy: dy), from: .zero, operation: .sourceOver, fraction: 1)
            c.setBlendMode(.sourceIn)
            c.setFillColor(color.cgColor)
            c.fill(caja.insetBy(dx: -2, dy: -2))
            c.endTransparencyLayer()
            c.setBlendMode(.normal)
        }

        let img = NSImage(size: tam, flipped: false) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            estampa(c, dy: -1.0, color: sombra)   // el corte, abajo
            estampa(c, dy: 1.0, color: luz)       // el filo que pega la luz, arriba
            /*
             * ⚠️ UN ICONO QUE TRAE SUS PROPIOS COLORES LOS CONSERVA.
             *
             * El cuerpo es un degradado de titanio recortado al glifo con
             * `.sourceIn` — que REEMPLAZA todos los colores del icono. Perfecto
             * para un glifo monocromo (que es lo que `Icono.dibujar` produce, y
             * por eso los marca como `isTemplate`), y destructivo para las
             * MUESTRAS de color: el cuadro del contorno, el del relleno y el
             * del rol salían los tres como el mismo cuadrado gris de titanio.
             *
             * Daniel, 25 ago: *"todos estos componentes muestran el color del
             * componente… de modo que son dinámicos en base al color del
             * componente"*.
             *
             * `isTemplate` es exactamente la pregunta que hay que hacer: un
             * template dice "píntame del color que quieras"; un no-template
             * dice "yo traigo mi color". Se respeta lo que el icono declara en
             * vez de asumir que todos son monocromos.
             */
            if base.isTemplate {
                c.beginTransparencyLayer(auxiliaryInfo: nil)
                base.draw(in: caja, from: .zero, operation: .sourceOver, fraction: 1)
                c.setBlendMode(.sourceIn)
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [arriba.cgColor, abajo.cgColor] as CFArray,
                                      locations: [0, 1]) {
                    c.drawLinearGradient(g, start: CGPoint(x: caja.midX, y: caja.maxY),
                                         end: CGPoint(x: caja.midX, y: caja.minY), options: [])
                }
                c.endTransparencyLayer()
                c.setBlendMode(.normal)
            } else {
                // Con sus colores, sobre el mismo relieve que el resto: la
                // muestra pertenece a la barra, solo que dice de qué color es
                // la cosa que representa.
                base.draw(in: caja, from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
        img.isTemplate = false
        cacheIconoBisel[llave] = img
        return img
    }
}

private extension NSColor {
    /// Llave estable para el cache de iconos biselados.
    var descripcionLlave: String {
        let c = usingColorSpace(.deviceRGB) ?? self
        return String(format: "%.2f%.2f%.2f%.2f", c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }
}

/// Un botón plano con hover, del tamaño y el radio de la casa.
final class BotonPlano: NSButton {
    var tema: Tema = .claro { didSet { repintar() } }
    var activo = false { didSet { repintar() } }
    /**
     * COMO se ve lo ACTIVO. Y son dos, no uno.
     *
     * En el rail, la herramienta activa va con el acento SOLIDO e icono blanco:
     * es un estado de modo, dura hasta que lo cambies, y tiene que verse desde
     * el otro lado de la pantalla. En la barra contextual va con el acento
     * SUAVE: ahí lo activo es un atributo del elemento —negrita, un panel
     * abierto— y ocho botones sólidos a la vez serían una alarma.
     *
     * El lienzo web hace exactamente esta distinción. Copiar uno solo para las
     * dos superficies era copiar la mitad de la decisión.
     */
    enum Enfasis { case suave, solido }
    var enfasis: Enfasis = .suave { didSet { repintar() } }
    /// Cierre alternativo al par target/action, para botones que se construyen
    /// dentro de un bucle y no tienen a quien apuntar.
    var alPulsar: (() -> Void)?
    /**
     * UN PUNTO, no un triángulo.
     *
     * Daniel: *"no me gusta que los iconos principales tengan como un triángulo
     * en la esquina inferior derecha, los hace lucir poco profesionales"*. Tenía
     * razón: la escuadra en la esquina es un gesto de barra de herramientas de
     * los 2000. El punto dice lo mismo —"aquí hay más"— y desaparece en el
     * conjunto en vez de ensuciar cada icono.
     */
    var tieneVariantes = false { didSet { needsDisplay = true } }
    /// Cuánto se mete el fondo del botón respecto a su caja, y con qué radio.
    /// Existe para el rótulo del zoom: ahí el fondo lo pinta la barra —es un
    /// visor hundido— y el hover del botón tiene que caber DENTRO de él. Con la
    /// forma por defecto se dibujaba un halo alrededor del visor.
    var insetFondo: CGFloat = 0
    var radioFondo: CGFloat = Estilo.radioChico
    /**
     * EL GLOBO ES PROPIO, y no es capricho.
     *
     * El `toolTip` de AppKit tarda ~1.5 s en salir, usa la tipografía del
     * sistema y no se puede colocar. En una barra de herramientas eso significa
     * que nadie lo ve nunca. Este sale al instante, del lado del lienzo, con la
     * tecla escrita — que es media razón de que exista.
     */
    var globo: String?
    var globoTecla: String?
    /**
     * EL GLOBO ES UNO SOLO EN TODA LA APP, y por eso es `static`.
     *
     * Era de cada boton, asi que dos podian estar vivos a la vez: se veian
     * "Deshacer ⌘Z" y "Rehacer ⇧⌘Z" pisandose, y de lejos parecia un globo con
     * el atajo repetido (Daniel: *"se quedo esto de deshacer repetido en el
     * lienzo"*). Un puntero no puede estar sobre dos botones: si hay dos
     * globos, uno de ellos es basura que nadie va a limpiar, porque el boton
     * que lo creo ya no se entera de nada.
     *
     * Compartido, enseñar uno borra el anterior por construccion — no hay
     * estado que sincronizar entre botones que no se conocen.
     */
    private static var vistaGlobo: NSView?
    private var dentro = false
    private var seguimiento: NSTrackingArea?

    /**
     * EL ICONO ENTRA PLANTILLA Y SE PINTA BISELADO.
     *
     * Los consumidores siguen asignando `b.image = Icono.x` (plantilla plana);
     * el botón guarda esa base y muestra su versión biselada del tema. Un solo
     * punto de paso = un solo diseño en toda la app (decisión 24 ago 2026).
     * `tinteIcono` fuerza el cuerpo (blanco sobre acento sólido, rojo riesgo).
     */
    private var iconoBase: NSImage?
    var tinteIcono: NSColor? { didSet { repintar() } }
    override var image: NSImage? {
        get { super.image }
        set {
            iconoBase = newValue
            super.image = newValue.map {
                Estilo.iconoBisel($0, tema, tinte: tinteIcono ?? (activo ? tema.acento : nil))
            }
        }
    }

    /// El título QUE SE PIDIÓ, que no es lo mismo que el que el botón tiene.
    ///
    /// ⚠️ `NSButton` nace con el título "Button" puesto. Un botón de solo icono
    /// no lo enseña porque `imagePosition = .imageOnly` lo esconde — pero el
    /// texto SIGUE AHÍ, y en cuanto algo vuelve a escribir `attributedTitle`
    /// reaparece encimado sobre el glifo, en las ocho celdas del rail a la vez.
    ///
    /// Pasó el 20 ago 2026: un cambio de color de título lo resucitó, y lo cazó
    /// el crítico ciego antes que yo. Guardar lo que SE PIDIÓ, en vez de leer lo
    /// que el control dice tener, cierra esa puerta.
    private let tituloPropio: String

    init(icono: NSImage?, titulo: String = "", ancho: CGFloat = 30, alto: CGFloat = 30) {
        tituloPropio = titulo
        super.init(frame: NSRect(x: 0, y: 0, width: ancho, height: alto))
        title = titulo
        isBordered = false
        bezelStyle = .regularSquare
        /*
         * ⚠️ EL CROMO NO SE QUEDA EL FOCO.
         *
         * `NSControl` toma el primer respondedor al pulsarlo. Consecuencia
         * medida: pulsas el botón de deshacer y a partir de ahí ⌘Z, Supr y las
         * flechas dejan de llegar al lienzo — el teclado se muere "solo" y no
         * hay forma de relacionarlo con el clic anterior.
         *
         * Un botón de barra no tiene nada que hacer con el foco de teclado: lo
         * rechaza y el lienzo lo conserva.
         */
        refusesFirstResponder = true
        wantsLayer = true
        layer?.cornerRadius = Estilo.radioChico
        layer?.cornerCurve = .continuous
        image = icono
        imagePosition = titulo.isEmpty ? .imageOnly : .imageLeading
        if !titulo.isEmpty {
            attributedTitle = NSAttributedString(string: titulo, attributes: [.font: Estilo.fuente(12)])
        }
        repintar()
    }
    required init?(coder: NSCoder) { fatalError() }

    /**
     * LO ACTIVO SE HUNDE, no se pinta de morado.
     *
     * Antes la herramienta activa era un cuadrado morado sólido con el icono en
     * blanco. Funciona, y es exactamente lo que hace cualquier barra de
     * herramientas web — que es el problema: no dice nada de quién la hizo. Y
     * además choca con la regla de marca (núcleo §6.4): *"el acento va en
     * outline y sello, no bañando la pieza"*.
     *
     * Un instrumento resuelve esto sin color: el control accionado **se hunde**.
     * Aquí es un pozo de bisel —gradiente invertido, filo vivo abajo— con el
     * glifo en morado. La tecla se ve pulsada, y el morado marca el modo en vez
     * de sustituir al metal.
     *
     * El rail añade una BARRA morada en el canto izquierdo. Ahí lo activo es un
     * MODO que dura hasta que lo cambies y tiene que leerse de lejos; en la
     * barra contextual es un atributo del elemento y ocho barras a la vez serían
     * una alarma. Misma pieza, dos grados.
     */
    override func draw(_ r: NSRect) {
        if let c = NSGraphicsContext.current?.cgContext {
            if activo {
                Estilo.pintarBisel(self, tema, radio: Estilo.radioChico, pozo: true, borde: false)
                if enfasis == .solido {
                    c.setFillColor(tema.acento.cgColor)
                    let alto = bounds.height - 12
                    c.addPath(CGPath(roundedRect: NSRect(x: 2.5, y: (bounds.height - alto) / 2,
                                                         width: 3, height: alto),
                                     cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
                    c.fillPath()
                }
            } else if dentro {
                c.setFillColor(Estilo.hover(tema).cgColor)
                c.addPath(CGPath(roundedRect: bounds.insetBy(dx: 0, dy: insetFondo),
                                 cornerWidth: radioFondo, cornerHeight: radioFondo, transform: nil))
                c.fillPath()
            }
        }
        super.draw(r)
        guard tieneVariantes, let c = NSGraphicsContext.current?.cgContext else { return }
        c.setFillColor((activo ? tema.acento.withAlphaComponent(0.85)
                        : tema.pieTexto.withAlphaComponent(0.55)).cgColor)
        /*
         * ⚠️ DENTRO, no sobre la esquina redondeada.
         *
         * A 7.5 px del borde el punto cae JUSTO encima del arco de la esquina, y
         * un crítico ciego lo leyó como "un glitch de renderizado en vez de un
         * badge intencional". Tenía razón: una señal que se confunde con un
         * fallo es peor que no tener señal.
         */
        /*
         * ⚠️ `NSButton` ESTÁ VOLTEADO: y=0 es ARRIBA.
         *
         * Con la coordenada cruda el punto salía en la esquina SUPERIOR derecha,
         * que no es donde ninguna barra de herramientas lo pone. Se descubrió
         * midiendo una conversión de coordenadas, no mirando: a 3 px de diámetro
         * el ojo no distingue "arriba" de "abajo" hasta que los ve en fila.
         */
        c.fillEllipse(in: NSRect(x: bounds.maxX - 10.5, y: bounds.maxY - 10.5, width: 3, height: 3))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        /*
         * ⚠️ EL GLOBO HUERFANO DEL ZOOM.
         *
         * `mouseExited` no llega cuando es la VISTA la que se mueve debajo de
         * un puntero quieto — y la barra de abajo se re-maqueta y se reancla
         * cada vez que cambia el zoom o el tamaño de la ventana. El boton se
         * iba de debajo del raton, nadie avisaba, y el globo se quedaba pegado
         * al lienzo hasta el siguiente hover.
         *
         * Aqui, que es justo donde AppKit avisa de que la geometria cambio, se
         * comprueba la posicion REAL del raton en vez de fiarse de los eventos.
         */
        if dentro, let w = window {
            let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
            if !bounds.contains(p) { dentro = false; repintar(); quitarGlobo() }
        }
        if let s = seguimiento { removeTrackingArea(s) }
        let s = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(s); seguimiento = s
    }
    override func mouseEntered(with e: NSEvent) { dentro = true; repintar(); mostrarGlobo() }
    override func mouseExited(with e: NSEvent) { dentro = false; repintar(); quitarGlobo() }
    /// Se pulsó sobre el PUNTO de variantes, no sobre el icono.
    ///
    /// ⚠️ Sin esto, las variantes solo abrían al SEGUNDO clic (el primero
    /// selecciona la herramienta). Daniel: *"el lápiz no tiene todavía sus tres
    /// variantes"* — las tenía, y no había forma de llegar a ellas sin saber
    /// que había que volver a pulsar. El área es de 18×18 aunque el punto mida
    /// 3: hacer clicable solo lo pintado es un blanco que la ley de Fitts
    /// vuelve incómodo con ratón e imposible con el dedo.
    var alPulsarVariantes: (() -> Void)?
    private func enElPunto(_ p: NSPoint) -> Bool {
        tieneVariantes && p.x >= bounds.maxX - 18 && p.y >= bounds.maxY - 18
    }

    override func mouseDown(with e: NSEvent) {
        quitarGlobo()
        if enElPunto(convert(e.locationInWindow, from: nil)), let f = alPulsarVariantes { f(); return }
        if let f = alPulsar { f() } else { super.mouseDown(with: e) }
    }

    private func mostrarGlobo() {
        guard let texto = globo, let raiz = window?.contentView else { return }
        quitarGlobo()
        let oscuro = tema.nombre == "oscuro"
        let fondo = oscuro ? NSColor(hex: "#e9eaf2")! : NSColor(hex: "#1a1b23")!
        let letra = oscuro ? NSColor(hex: "#15161d")! : NSColor(hex: "#f4f4f8")!
        let etq = NSTextField(labelWithString: texto)
        etq.font = Estilo.fuente(11.5, 600); etq.textColor = letra
        let w = etq.attributedStringValue.size().width
        var anchoTecla: CGFloat = 0
        var tecla: NSTextField?
        if let t = globoTecla, !t.isEmpty {
            let k = NSTextField(labelWithString: t)
            k.font = Estilo.fuente(10, 700); k.textColor = letra
            k.alignment = .center
            anchoTecla = max(16, k.attributedStringValue.size().width + 10)
            tecla = k
        }
        let v = NSView(frame: .zero)
        v.wantsLayer = true
        v.layer?.backgroundColor = fondo.cgColor
        v.layer?.cornerRadius = 7
        v.layer?.cornerCurve = .continuous
        v.layer?.shadowColor = NSColor.black.cgColor
        v.layer?.shadowOpacity = 0.28
        v.layer?.shadowRadius = 7
        v.layer?.shadowOffset = CGSize(width: 0, height: -2)
        etq.frame = NSRect(x: 9, y: 5, width: w + 2, height: 16)
        v.addSubview(etq)
        if let k = tecla {
            k.wantsLayer = true
            k.layer?.backgroundColor = (oscuro ? NSColor.black.withAlphaComponent(0.10)
                                        : NSColor.white.withAlphaComponent(0.16)).cgColor
            k.layer?.cornerRadius = 4
            k.frame = NSRect(x: 9 + w + 7, y: 5.5, width: anchoTecla, height: 15)
            v.addSubview(k)
        }
        let ancho = 9 + w + (anchoTecla > 0 ? anchoTecla + 7 : 0) + 9
        // Al LADO del lienzo, centrado con el botón: encima taparía el icono
        // justo cuando la mano lo está buscando.
        let origen = convert(NSPoint(x: bounds.maxX + 10, y: bounds.midY), to: raiz)
        v.frame = NSRect(x: origen.x, y: origen.y - 13, width: ancho, height: 26)
        raiz.addSubview(v)
        Self.vistaGlobo = v
    }

    private func quitarGlobo() { Self.quitarGlobo() }
    static func quitarGlobo() { vistaGlobo?.removeFromSuperview(); vistaGlobo = nil }

    private func repintar() {
        // El fondo lo pinta `draw` (un gradiente no cabe en `backgroundColor`).
        layer?.backgroundColor = NSColor.clear.cgColor
        contentTintColor = activo ? tema.acento : tema.cuerpoTexto
        // El glifo biselado se re-cuece cuando cambian tema/activo/tinte.
        if let base = iconoBase {
            super.image = Estilo.iconoBisel(base, tema, tinte: tinteIcono ?? (activo ? tema.acento : nil))
        }
        needsDisplay = true
        guard !tituloPropio.isEmpty else { return }
        let fuente = attributedTitle.length > 0
            ? (attributedTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? Estilo.fuente(12))
            : Estilo.fuente(12)
        attributedTitle = NSAttributedString(string: tituloPropio, attributes: [
            .font: fuente, .foregroundColor: contentTintColor ?? tema.cuerpoTexto,
        ])
    }
}

/// Iconos dibujados, no emojis ni SF Symbols mezclados.
///
/// SF Symbols tiene un peso y un remate propios que se ven al lado de los del
/// lienzo como de otra familia. Estos son los mismos trazos de 1.6 sobre
/// rejilla de 24 que usa la interfaz web.
enum Icono {
    static func dibujar(_ lado: CGFloat = 18, _ cuerpo: @escaping (CGContext, CGFloat) -> Void) -> NSImage {
        let img = NSImage(size: NSSize(width: lado, height: lado), flipped: true) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            c.setLineWidth(1.6 * lado / 24)
            c.setLineCap(.round); c.setLineJoin(.round)
            c.scaleBy(x: lado / 24, y: lado / 24)
            c.setLineWidth(1.6)
            cuerpo(c, 24)
            return true
        }
        img.isTemplate = true
        return img
    }

    /**
     * LA CARPETA, con pestaña de verdad.
     *
     * La anterior era un pentágono irregular: el lomo arrancaba a media altura y
     * subía en diagonal, así que a 18 px se leía como un rectángulo torcido.
     * Ésta tiene el gesto que el ojo espera —cuerpo recto, pestaña corta arriba
     * a la izquierda— y las esquinas redondeadas del resto del juego.
     */
    static let carpeta = dibujar { c, _ in
        c.move(to: CGPoint(x: 3.2, y: 18.8))
        c.addLine(to: CGPoint(x: 3.2, y: 7.4))
        c.addQuadCurve(to: CGPoint(x: 4.6, y: 6.0), control: CGPoint(x: 3.2, y: 6.0))
        c.addLine(to: CGPoint(x: 9.0, y: 6.0))
        c.addLine(to: CGPoint(x: 11.2, y: 8.6))
        c.addLine(to: CGPoint(x: 19.4, y: 8.6))
        c.addQuadCurve(to: CGPoint(x: 20.8, y: 10.0), control: CGPoint(x: 20.8, y: 8.6))
        c.addLine(to: CGPoint(x: 20.8, y: 18.8))
        c.closePath(); c.strokePath()
    }
    static let chevronDerecha = dibujar { c, _ in
        c.move(to: CGPoint(x: 9.5, y: 6)); c.addLine(to: CGPoint(x: 15.5, y: 12))
        c.addLine(to: CGPoint(x: 9.5, y: 18)); c.strokePath()
    }
    static let chevronAbajo = dibujar { c, _ in
        c.move(to: CGPoint(x: 6, y: 9.5)); c.addLine(to: CGPoint(x: 12, y: 15.5))
        c.addLine(to: CGPoint(x: 18, y: 9.5)); c.strokePath()
    }
    static let lupa = dibujar { c, _ in
        c.addEllipse(in: CGRect(x: 4.5, y: 4.5, width: 12, height: 12)); c.strokePath()
        c.move(to: CGPoint(x: 15.5, y: 15.5)); c.addLine(to: CGPoint(x: 20, y: 20)); c.strokePath()
    }
    static let mas = dibujar { c, _ in
        c.move(to: CGPoint(x: 12, y: 5)); c.addLine(to: CGPoint(x: 12, y: 19)); c.strokePath()
        c.move(to: CGPoint(x: 5, y: 12)); c.addLine(to: CGPoint(x: 19, y: 12)); c.strokePath()
    }
    static let menos = dibujar { c, _ in
        c.move(to: CGPoint(x: 5, y: 12)); c.addLine(to: CGPoint(x: 19, y: 12)); c.strokePath()
    }
    static let encuadrar = dibujar { c, _ in
        for (a, b, d) in [(4.0, 9.0, 1.0), (20.0, 9.0, -1.0)] {
            c.move(to: CGPoint(x: a, y: b)); c.addLine(to: CGPoint(x: a, y: 4.5))
            c.addLine(to: CGPoint(x: a + 4.5 * d, y: 4.5)); c.strokePath()
            c.move(to: CGPoint(x: a, y: 24 - b)); c.addLine(to: CGPoint(x: a, y: 19.5))
            c.addLine(to: CGPoint(x: a + 4.5 * d, y: 19.5)); c.strokePath()
        }
    }
    static let recargar = dibujar { c, _ in
        c.addArc(center: CGPoint(x: 12, y: 12), radius: 7.5,
                 startAngle: .pi * 0.35, endAngle: .pi * 1.75, clockwise: false)
        c.strokePath()
        c.move(to: CGPoint(x: 17.2, y: 3.4)); c.addLine(to: CGPoint(x: 17.6, y: 8.4))
        c.addLine(to: CGPoint(x: 12.6, y: 8.0)); c.strokePath()
    }
    static let puntos = dibujar { c, _ in
        for y in [7.0, 12.0, 17.0] { c.fillEllipse(in: CGRect(x: 10.8, y: y - 1.2, width: 2.4, height: 2.4)) }
    }
    static let luna = dibujar { c, _ in
        c.move(to: CGPoint(x: 19, y: 14.4))
        c.addCurve(to: CGPoint(x: 9.6, y: 5), control1: CGPoint(x: 13.6, y: 15.6), control2: CGPoint(x: 8.4, y: 10.4))
        c.addCurve(to: CGPoint(x: 12, y: 20), control1: CGPoint(x: 5.6, y: 7), control2: CGPoint(x: 4, y: 20))
        c.addCurve(to: CGPoint(x: 19, y: 14.4), control1: CGPoint(x: 15.5, y: 20), control2: CGPoint(x: 18.2, y: 17.8))
        c.strokePath()
    }
    /// ⚠️ Los rayos eran de 2 px sobre un núcleo de 8 y el conjunto pesaba el
    /// doble que la luna de al lado — dos botones hermanos con dos densidades
    /// distintas. Núcleo más chico, rayos más largos y CUATRO en diagonal más
    /// cortos: la silueta de sol de toda la vida, con la tinta de los demás.
    static let sol = dibujar { c, _ in
        c.addEllipse(in: CGRect(x: 8.6, y: 8.6, width: 6.8, height: 6.8)); c.strokePath()
        for i in 0..<8 {
            let a = Double(i) * .pi / 4
            let largo = i % 2 == 0 ? 3.4 : 2.4
            c.move(to: CGPoint(x: 12 + cos(a) * 8.6, y: 12 + sin(a) * 8.6))
            c.addLine(to: CGPoint(x: 12 + cos(a) * (8.6 + largo), y: 12 + sin(a) * (8.6 + largo)))
        }
        c.strokePath()
    }
}


/**
 * EL CROMO: la fila de titulo y el panel lateral son la MISMA superficie.
 *
 * Daniel: *"asegúrate que el sidebar sea del mismo color que el header; el
 * header de un ligero color diferente, de modo que se diferencie del board y se
 * unifique"*. Antes la fila de titulo era transparente y el lienzo llegaba hasta
 * el borde de arriba: el panel se leia como una isla de color pegada a un lado.
 *
 * Con una sola tinta para las dos, el cromo forma una L continua alrededor del
 * tablero, y el tablero se lee como lo que es: la superficie de trabajo, no el
 * fondo de la ventana. La diferencia con el lienzo es deliberadamente CHICA —lo
 * justo para separar dos zonas, no para partir la ventana en dos aplicaciones.
 */
extension Tema {
    /**
     * LOS SEIS COLORES DEL TITANIO, en los dos temas.
     *
     * ⚠️ NO son de esta app. Están copiados de `entorno-fisico/panel.html`
     * (16 ago 2026), donde Daniel ya había traducido Titaniumorphism a un tema
     * claro: en oscuro es TITANIO y en claro es ALUMINIO PULIDO. La estructura
     * es la misma —top/mid/bot + borde + filo + rim—, solo cambia de qué lado
     * del gris vive. Inventar aquí un par nuevo habría creado el séptimo morado
     * del sistema, que es exactamente lo que el núcleo de marca existe para
     * evitar.
     *
     * Y por eso el cromo funciona con el lienzo blanco: un bisel claro alrededor
     * de una pantalla blanca sigue siendo un bisel, igual que el marco de un
     * MacBook plateado alrededor de una página en blanco.
     */
    var bisel: Estilo.Bisel {
        nombre == "oscuro"
            ? Estilo.Bisel(top: c2("#24242b"), mid: c2("#16161c"), bot: c2("#0d0d12"),
                           borde: c2("#2c2c34"), filoAlto: c2("#42424c"),
                           rim: NSColor(white: 1, alpha: 0.10))
            /*
             * ⚠️ EL BORDE CLARO ES `#d2d2d9`, NO el `#d8d8dd` del panel del
             * estudio, y la diferencia se midió: allí las tarjetas viven sobre
             * un fondo `#f4f4f5` y aquí flotan sobre un lienzo BLANCO PURO. Una
             * pieza casi blanca con un borde casi blanco sobre blanco no es
             * sutil, es invisible — la barra de estado desaparecía contra el
             * tablero. Dos tonos más de borde y la sombra hacen el trabajo que
             * allá hacía el fondo.
             */
            : Estilo.Bisel(top: c2("#fbfbfd"), mid: c2("#f3f3f6"), bot: c2("#eaeaef"),
                           borde: c2("#d2d2d9"), filoAlto: c2("#ffffff"),
                           rim: NSColor(white: 1, alpha: 0.85))
    }

    /// El ORO de marca. Un tono por tema, porque el mismo naranja que canta
    /// sobre negro se pierde sobre blanco: núcleo §2.2 lista `#cc7301` como la
    /// variante oscura legítima del mismo oro, y es la que usa sfcal en claro.
    var oro: NSColor { nombre == "oscuro" ? c2("#ff9101") : c2("#cc7301") }

    /// El filo de un surco grabado. En oscuro va a media voz: sobre titanio, el
    /// `#42424c` a plena opacidad se lee como una línea blanca y el separador
    /// termina llamando más la atención que las herramientas que separa.
    var filoSurco: NSColor { bisel.filoAlto.withAlphaComponent(nombre == "oscuro" ? 0.45 : 0.9) }

    var cromo: NSColor { bisel.mid }
    var filoCromo: NSColor { bisel.borde }
}

private func c2(_ h: String) -> NSColor { NSColor(hex: h) ?? .gray }


extension NSCursor {
    /// EL CURSOR DE GIRO. macOS no publica ninguno, asi que se dibuja: sin una
    /// señal en el puntero, la zona de rotacion de las esquinas es invisible
    /// hasta que ya estas girando algo sin querer.
    static let giro: NSCursor = {
        let lado = 22.0
        let img = NSImage(size: NSSize(width: lado, height: lado), flipped: false) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return true }
            let centro = CGPoint(x: lado / 2, y: lado / 2)
            let r = 7.0
            for (color, ancho) in [(NSColor.white, 4.0), (NSColor.black, 2.0)] {
                c.setStrokeColor(color.cgColor); c.setLineWidth(ancho); c.setLineCap(.round)
                c.addArc(center: centro, radius: r, startAngle: 0.6, endAngle: 5.4, clockwise: false)
                c.strokePath()
                let fin = CGPoint(x: centro.x + cos(5.4) * r, y: centro.y + sin(5.4) * r)
                let a = 5.4 + .pi / 2
                c.move(to: CGPoint(x: fin.x + cos(a + 0.5) * 4.5, y: fin.y + sin(a + 0.5) * 4.5))
                c.addLine(to: fin)
                c.addLine(to: CGPoint(x: fin.x + cos(a - 2.2) * 4.5, y: fin.y + sin(a - 2.2) * 4.5))
                c.strokePath()
            }
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: lado / 2, y: lado / 2))
    }()

    /**
     * EL PUNTO FINO — el cursor de la goma.
     *
     * La goma ya dibuja su disco en el lienzo, y ése ES su cursor. Encima, una
     * cruz de sistema de 20 px es un segundo puntero discutiendo con el
     * primero, y con un disco de 80 px tapa justo lo que vas a borrar. Se
     * cambia por un punto de 4 px con halo, que dice dónde está el centro
     * exacto sin pelearse con el disco.
     *
     * No se ESCONDE el cursor (`NSCursor.hide`) a propósito: es un ajuste
     * global emparejado con `unhide`, y cualquier salida que no pase por su
     * pareja —una ventana modal, un fallo, la app perdiendo el foco a media
     * cosa— deja al Mac entero sin puntero. Un adorno no puede tener ese riesgo.
     */
    static let puntoFino: NSCursor = {
        let lado = 12.0
        let img = NSImage(size: NSSize(width: lado, height: lado), flipped: false) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return true }
            let centro = NSRect(x: lado / 2 - 2, y: lado / 2 - 2, width: 4, height: 4)
            c.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            c.fillEllipse(in: centro.insetBy(dx: -1.5, dy: -1.5))
            c.setFillColor(NSColor.white.cgColor)
            c.fillEllipse(in: centro)
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: lado / 2, y: lado / 2))
    }()

    // ── cursores por herramienta (pedido de Daniel, 24 ago 2026) ────────────
    //
    // El cursor ES la herramienta: el lápiz se ve lápiz y escribe por su punta.
    // Sólido blanco con halo negro, porque un cursor tiene que leerse sobre el
    // lienzo claro Y el oscuro; el bisel se queda en el rail, donde hay fondo.

    /// EL LÁPIZ. El hotspot va en la PUNTA (2, 22): la tinta nace exactamente
    /// donde el grafito toca el papel, no en el centro de un dibujo.
    static let lapizHerramienta: NSCursor = {
        let lado = 24.0
        let img = NSImage(size: NSSize(width: lado, height: lado), flipped: true) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return true }
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 16.6, y: 3.4))
            p.addCurve(to: CGPoint(x: 20.6, y: 7.4),
                       control1: CGPoint(x: 18.2, y: 1.9), control2: CGPoint(x: 20.9, y: 2.6))
            p.addLine(to: CGPoint(x: 7.5, y: 20.5))
            p.addLine(to: CGPoint(x: 2, y: 22))
            p.addLine(to: CGPoint(x: 3.5, y: 16.5))
            p.closeSubpath()
            c.addPath(p)
            c.setFillColor(NSColor.white.cgColor)
            c.setStrokeColor(NSColor.black.withAlphaComponent(0.92).cgColor)
            c.setLineWidth(1.4); c.setLineJoin(.round)
            c.drawPath(using: .fillStroke)
            // El corte de la madera: separa la punta del cuerpo.
            c.setLineWidth(1.1)
            c.move(to: CGPoint(x: 5.3, y: 14.7)); c.addLine(to: CGPoint(x: 9.3, y: 18.7))
            c.strokePath()
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 2, y: 22))
    }()

    /// EL MARCADOR: mismo contrato que el lápiz, punta plana, hotspot en ella.
    static let marcadorHerramienta: NSCursor = {
        let lado = 24.0
        let img = NSImage(size: NSSize(width: lado, height: lado), flipped: true) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return true }
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 15.5, y: 3))
            p.addLine(to: CGPoint(x: 21, y: 8.5))
            p.addLine(to: CGPoint(x: 9, y: 20.5))
            p.addLine(to: CGPoint(x: 3.5, y: 20.5))
            p.addLine(to: CGPoint(x: 3.5, y: 15))
            p.closeSubpath()
            c.addPath(p)
            c.setFillColor(NSColor.white.cgColor)
            c.setStrokeColor(NSColor.black.withAlphaComponent(0.92).cgColor)
            c.setLineWidth(1.4); c.setLineJoin(.round)
            c.drawPath(using: .fillStroke)
            c.setLineWidth(1.1)
            c.move(to: CGPoint(x: 5.9, y: 12.6)); c.addLine(to: CGPoint(x: 11.4, y: 18.1))
            c.strokePath()
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 3.5, y: 20.5))
    }()

    /// Una estampa del glifo con halo: negro alrededor, blanco encima.
    private static func estampaConHalo(_ c: CGContext, _ img: NSImage, en caja: NSRect) {
        for (dx, dy): (CGFloat, CGFloat) in [(0.8, 0), (-0.8, 0), (0, 0.8), (0, -0.8),
                                             (0.6, 0.6), (-0.6, 0.6), (0.6, -0.6), (-0.6, -0.6)] {
            c.beginTransparencyLayer(auxiliaryInfo: nil)
            img.draw(in: caja.offsetBy(dx: dx, dy: dy), from: .zero, operation: .sourceOver, fraction: 1)
            c.setBlendMode(.sourceIn)
            c.setFillColor(NSColor.black.withAlphaComponent(0.92).cgColor)
            c.fill(caja.insetBy(dx: -3, dy: -3))
            c.endTransparencyLayer()
            c.setBlendMode(.normal)
        }
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        img.draw(in: caja, from: .zero, operation: .sourceOver, fraction: 1)
        c.setBlendMode(.sourceIn)
        c.setFillColor(NSColor.white.cgColor)
        c.fill(caja.insetBy(dx: -3, dy: -3))
        c.endTransparencyLayer()
        c.setBlendMode(.normal)
    }

    /**
     * COLOCACIÓN: cruz fina + el glifo de la herramienta como insignia.
     *
     * La cruz es el punto de trabajo (hotspot en su centro); la insignia
     * abajo-derecha dice QUÉ vas a soltar sin taparlo — la convención de los
     * cursores de copia del sistema, con los glifos de la casa.
     */
    private static var cacheColocacion: [ObjectIdentifier: NSCursor] = [:]
    static func colocacion(_ icono: NSImage) -> NSCursor {
        if let hecho = cacheColocacion[ObjectIdentifier(icono)] { return hecho }
        let lado = 28.0
        let img = NSImage(size: NSSize(width: lado, height: lado), flipped: true) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return true }
            for (color, ancho) in [(NSColor.white, 3.4), (NSColor.black.withAlphaComponent(0.92), 1.6)] {
                c.setStrokeColor(color.cgColor); c.setLineWidth(ancho); c.setLineCap(.round)
                c.move(to: CGPoint(x: 8, y: 1.8)); c.addLine(to: CGPoint(x: 8, y: 14.2))
                c.move(to: CGPoint(x: 1.8, y: 8)); c.addLine(to: CGPoint(x: 14.2, y: 8))
                c.strokePath()
            }
            estampaConHalo(c, icono, en: NSRect(x: 14.5, y: 14.5, width: 13, height: 13))
            return true
        }
        let cursor = NSCursor(image: img, hotSpot: NSPoint(x: 8, y: 8))
        cacheColocacion[ObjectIdentifier(icono)] = cursor
        return cursor
    }
}
