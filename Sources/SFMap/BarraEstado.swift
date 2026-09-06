import AppKit

/// Como se ve el fondo del lienzo.
enum Fondo: String, CaseIterable {
    case liso, puntos, cuadricula
    var nombre: String { self == .liso ? "Liso" : self == .puntos ? "Puntos" : "Cuadrícula" }
    var icono: NSImage {
        switch self {
        case .liso: return Icono.fondoLiso
        case .puntos: return Icono.fondoPuntos
        case .cuadricula: return Icono.fondoCuadricula
        }
    }
}

/**
 * LA BARRA DE ESTADO, abajo a la derecha.
 *
 * Ahi porque es donde no estorba: arriba compite con el contenido y a la
 * izquierda choca con el rail de herramientas.
 *
 * El estado del GUARDADO vive aqui y no flotando sobre el lienzo. Daniel ya
 * habia pedido eso mismo antes ("estorbaba en tablet"): es un requisito ganado
 * con feedback, no una preferencia.
 */
final class BarraEstado: NSView {
    var tema: Tema = .claro { didSet { repintar() } }
    /**
     * EL ZOOM SE PONE EN ORO CUANDO NO ESTÁS AL 100%.
     *
     * No es decoración: es la regla del semáforo del sistema —color solo para
     * estado real y medible— aplicada al único número de la ventana. "El mapa se
     * ve raro" casi siempre es "estás al 40% y no lo sabías", y hasta ahora esa
     * respuesta estaba escrita en gris al lado de otras nueve cosas grises.
     *
     * En oro porque el oro es lo protagonista, y porque un rojo o un ámbar de
     * alarma dirían que algo está MAL, y no lo está.
     */
    var zoom: Double = 1 {
        didSet {
            txtZoom.stringValue = "\(Int((zoom * 100).rounded()))%"
            let nominal = abs(zoom - 1) < 0.005
            txtZoom.textColor = nominal ? tema.cuerpoTexto : tema.oro
        }
    }
    var estado: String = "" {
        didSet { txtEstado.stringValue = estado; repintarEstado(); needsLayout = true }
    }
    var esError = false { didSet { repintarEstado() } }

    /**
     * ⭐ EL SELLO DE GUARDADO (26 ago 2026). *"Dame un signo de guardado hasta
     * abajo, y asegúrate de que funcione smooth."*
     *
     * Un texto que cambia de palabra se lee cuando ya lo estás mirando; un
     * PUNTO de color se ve de reojo, que es como se mira una barra de estado
     * mientras trabajas. Tres estados y ninguno más:
     *
     *   · violeta  = guardado (la marca de la casa: está a salvo)
     *   · ámbar    = hay algo sin guardar, o está saliendo
     *   · rojo     = no pudo
     *
     * El color se cruza con una transición de 0.25 s: sin ella, un guardado
     * rápido es un parpadeo, y un parpadeo se lee como error aunque diga que
     * todo va bien.
     */
    enum Sello { case guardado, pendiente, error }
    var sello: Sello = .guardado { didSet { if sello != oldValue { repintarSello() } } }
    var fondo: Fondo = .puntos { didSet { btnFondo.image = fondo.icono } }
    var puedeDeshacer = false { didSet { btnDeshacer.isEnabled = puedeDeshacer; btnDeshacer.alphaValue = puedeDeshacer ? 1 : 0.35 } }
    var puedeRehacer = false { didSet { btnRehacer.isEnabled = puedeRehacer; btnRehacer.alphaValue = puedeRehacer ? 1 : 0.35 } }
    var haySeleccion = false

    var alZoom: ((Double) -> Void)?
    var alZoomA: ((Double) -> Void)?
    var alEncuadrar: (() -> Void)?
    var alFondo: ((Fondo) -> Void)?
    var alTema: (() -> Void)?
    var alDeshacer: (() -> Void)?
    var alRehacer: (() -> Void)?
    var alExportar: ((Bool) -> Void)?
    /// Solo se pone cuando la página TIENE una región compilada. Un botón de
    /// recompilar sobre un lienzo dibujado a mano no tendría qué compilar.
    var alRecompilar: (() -> Void)? { didSet { btnCompilar.isHidden = alRecompilar == nil; needsLayout = true } }

    private let puntoSello = NSView(frame: NSRect(x: 14, y: 24, width: 9, height: 9))
    private let txtEstado = NSTextField(labelWithString: "")
    private let txtZoom = NSTextField(labelWithString: "100%")
    private let btnFondo = BotonPlano(icono: Icono.fondoPuntos)
    private let btnDeshacer = BotonPlano(icono: Icono.deshacer)
    private let btnRehacer = BotonPlano(icono: Icono.rehacer)
    private let btnTema = BotonPlano(icono: Icono.luna)
    private let btnCompilar = BotonPlano(icono: Icono.compilar)
    private var botones: [BotonPlano] = []
    private var panel: NSView?
    /// El ancho con el que se coloco por ultima vez, para avisar solo cuando
    /// cambia de verdad (y no entrar en un bucle de maquetacion).
    private var ultimoAnchoIdeal: CGFloat = 0
    /// La barra cambio de ancho (aparecio o se fue un boton): quien la coloca
    /// tiene que volver a hacerlo. Ella no se recoloca sola — ver `layout()`.
    var alRedimensionar: (() -> Void)?

    private static let niveles: [Double] = [0.1, 0.25, 0.5, 1, 2, 4]

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 560, height: 54))
        txtEstado.font = Estilo.fuente(13, 600)
        // El zoom es una LECTURA, no una palabra: en Montserrat el `100%` medía
        // distinto que el `90%` y al acercarte la cifra se movía de sitio. En
        // mono el dígito cambia y la aguja se queda quieta (núcleo §5: el
        // monospace vive en el cromo, y un contador es cromo).
        txtZoom.font = Estilo.mono(13, 700)
        txtZoom.alignment = .center
        addSubview(puntoSello); addSubview(txtEstado); addSubview(txtZoom)
        repintarSello()

        btnDeshacer.globo = "Deshacer  ⌘Z"; btnDeshacer.alPulsar = { [weak self] in self?.alDeshacer?() }
        btnRehacer.globo = "Rehacer  ⇧⌘Z"; btnRehacer.alPulsar = { [weak self] in self?.alRehacer?() }
        btnFondo.globo = "Vista del lienzo"; btnFondo.alPulsar = { [weak self] in self?.abrirFondo() }
        let menos = BotonPlano(icono: Icono.menos); menos.globo = "Alejar"
        menos.alPulsar = { [weak self] in self?.alZoom?(1 / 1.2) }
        let mas = BotonPlano(icono: Icono.mas); mas.globo = "Acercar"
        mas.alPulsar = { [weak self] in self?.alZoom?(1.2) }
        let encuadrar = BotonPlano(icono: Icono.encuadrar); encuadrar.globo = "Encuadrar  ⇧1"
        encuadrar.alPulsar = { [weak self] in self?.alEncuadrar?() }
        let exportar = BotonPlano(icono: Icono.descargar); exportar.globo = "Exportar PNG"
        exportar.alPulsar = { [weak self] in self?.abrirExportar() }
        /*
         * La puerta a los atajos se MUDÓ al engrane de arriba a la derecha, por
         * petición de Daniel. Aquí queda un hueco a propósito: dos puertas al
         * mismo sitio es una de más, y la de arriba es donde macOS pone los
         * ajustes de una ventana.
         */
        btnCompilar.globo = "Recompilar la región gobernada"
        btnCompilar.isHidden = true
        btnCompilar.alPulsar = { [weak self] in self?.alRecompilar?() }
        btnTema.globo = "Tema claro / oscuro"
        btnTema.alPulsar = { [weak self] in self?.alTema?() }

        botones = [btnDeshacer, btnRehacer, btnFondo, menos, mas, encuadrar, exportar, btnCompilar, btnTema]
        botones.forEach { $0.setFrameSize(NSSize(width: 36, height: 36)) }
        botones.forEach { addSubview($0) }
        addSubview(txtZoom)
        // El % de zoom tambien es un boton: abre los niveles.
        let bZoom = BotonPlano(icono: nil, ancho: 62, alto: 36)
        bZoom.insetFondo = 3; bZoom.radioFondo = 6
        bZoom.globo = "Nivel de zoom"
        bZoom.alPulsar = { [weak self] in self?.abrirZoom() }
        botones.insert(bZoom, at: 4)
        addSubview(bZoom)
        txtZoom.isEditable = false
        repintar()
    }
    required init?(coder: NSCoder) { fatalError() }

    /**
     * Cuánto mide con los botones que tiene AHORA.
     *
     * ⚠️ Existe porque colocarla salía mal por ORDEN: quien la posiciona lo hace
     * contra `frame.width`, y el ancho real se calculaba dentro de `layout()`,
     * que corre DESPUÉS. Con el botón del compilador visible la barra crecía y
     * se salía por el borde derecho: el último control quedaba cortado por la
     * mitad. Es el mismo fallo de orden que el panel que se maquetaba antes de
     * tener tamaño — dos veces el mismo día.
     */
    /**
     * Cuánto ocupa el texto de estado, medido — no 170 px a ojo.
     *
     * El reserve fijo dejaba un vacío de dos dedos entre "45 elementos" y el
     * primer botón, y la barra parecía descuadrada. Con la medida real, la barra
     * se encoge con lo que dice y crece cuando avisa de algo.
     */
    private var anchoEstado: CGFloat {
        guard !estado.isEmpty else { return 0 }
        return max(58, min(230, ceil(txtEstado.attributedStringValue.size().width) + 6))
    }
    /// Cuánto ocupa el bloque de estado con su separador. Sin mensaje, CERO: una
    /// barra que reserva sitio para un texto que no existe deja un hueco a la
    /// izquierda y se lee como descuadrada.
    /// +17 por el sello: el punto ocupa sitio SIEMPRE, también cuando no hay
    /// mensaje — es el único que informa cuando la barra calla.
    private var bloqueEstado: CGFloat { anchoEstado == 0 ? 31 : anchoEstado + 39 }

    var anchoIdeal: CGFloat {
        var x: CGFloat = bloqueEstado
        for (i, b) in botones.enumerated() where !b.isHidden {
            if i == 2 || i == 3 || b === btnTema { x += 7 }
            x += b.frame.width + 2
        }
        return x + 8
    }

    override func layout() {
        super.layout()
        // El estado se recortaba en cuanto el mensaje pasaba de dos palabras.
        // Es la única línea que dice si algo se guardó: no puede terminar en "…".
        // El SELLO va antes del texto: se ve de reojo sin leer nada.
        puntoSello.frame = NSRect(x: 14, y: 22, width: 9, height: 9)
        txtEstado.frame = NSRect(x: 31, y: 17, width: anchoEstado, height: 20)
        var x: CGFloat = bloqueEstado
        for (i, b) in botones.enumerated() {
            if b.isHidden { continue }
            // Separadores logicos: tras deshacer/rehacer, tras el fondo, y
            // antes del tema. Se pintan en draw().
            //
            // ⚠️ El ultimo era `i == 8` y apuntaba al COMPILADOR, no al tema:
            // los indices se eligieron con el array de 9 y luego `bZoom` se
            // inserta en la posicion 4, corriendo todo lo que va detras. Un
            // indice literal sobre un array que se modifica despues es una
            // bomba de relojeria silenciosa — por eso ahora se pregunta por el
            // BOTON, no por su numero.
            if i == 2 || i == 3 || b === btnTema { x += 7 }
            b.frame = NSRect(x: x, y: 9, width: b.frame.width, height: 36)
            x += b.frame.width + 2
        }
        txtZoom.frame = NSRect(x: botones[4].frame.minX, y: 17, width: 62, height: 20)
        /*
         * ⚠️ AQUI NO SE TOCA NI EL FRAME NI EL BOUNDS. Se hizo, y se medio.
         *
         * `layout()` hacia esto:
         *
         *     let esc = frame.height / bounds.height
         *     bounds.size.width = anchoIdeal
         *     frame.size.width  = anchoIdeal * esc
         *
         * y se REALIMENTA: `anchoIdeal` se calcula sumando `frame.width` de
         * los hijos, que estan en coordenadas de `bounds`; cambiar `bounds`
         * cambia la escala en X, la siguiente pasada lee unos hijos medidos
         * contra otra escala, y las dos escalas se separan. Medido, con la
         * barra colocada a escala 1.0:
         *
         *     bounds.w=282.9  frame.w=398.0  escX=1.407  escY=1.000
         *     el hijo mas a la derecha acababa en 388, con bounds de 282.9
         *
         * Ahi estan los dos sintomas de golpe: la capsula ESTIRADA un 40% a lo
         * ancho (Daniel: *"siento como que se estiran, no mantiene la
         * proporcion"*) y los ultimos botones —la luna— por fuera del bisel,
         * porque se pintaban 105 px mas alla del borde.
         *
         * El tamaño es de quien COLOCA la vista, que ya lo pone proporcional
         * en las dos dimensiones. `layout()` solo reparte a los hijos. Y para
         * el caso que motivo aquel apaño —la barra crece cuando llega el boton
         * del compilador, segundos despues y por red— hay un aviso explicito:
         * `alRedimensionar`. Recalcular tu propio tamaño mientras te maquetas
         * no es independencia, es una ecuacion que se resuelve a si misma.
         */
        if ultimoAnchoIdeal != anchoIdeal {
            ultimoAnchoIdeal = anchoIdeal
            alRedimensionar?()
        }
    }

    override func draw(_ r: NSRect) {
        // Radio 12: el del minimapa. Son las dos piezas de la fila de abajo y
        // tenían dos esquinas distintas.
        Estilo.pintarBisel(self, tema, radio: 12)
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        // El mismo surco grabado del rail, de pie: sombra del corte + filo.
        func surco(_ x: CGFloat) {
            c.setFillColor(tema.bisel.borde.cgColor)
            c.fill(NSRect(x: x, y: 12, width: 1, height: 20))
            c.setFillColor(tema.filoSurco.cgColor)
            c.fill(NSRect(x: x + 1, y: 12, width: 1, height: 20))
        }
        for i in [2, 3, 8] where i < botones.count && !botones[i].isHidden {
            surco(botones[i].frame.minX - 5.5)
        }
        if anchoEstado > 0 { surco(anchoEstado + 17) }
        // EL ROTULO DEL ZOOM VA HUNDIDO, con la misma pieza que el visor del
        // minimapa: las dos son placas de titanio con una lectura dentro.
        if botones.count > 4 {
            Estilo.pintarVisor(self, tema, en: botones[4].frame.insetBy(dx: 0, dy: 3),
                               relleno: tema.bisel.bot, radio: 6)
        }
    }

    private func repintar() {
        Estilo.tarjeta(self, tema: tema, radio: 12)
        txtZoom.textColor = abs(zoom - 1) < 0.005 ? tema.cuerpoTexto : tema.oro
        botones.forEach { $0.tema = tema }
        btnTema.image = tema.nombre == "claro" ? Icono.luna : Icono.sol
        repintarEstado()
        needsDisplay = true
    }

    private func repintarEstado() {
        // Solo se pone rojo cuando algo falla DE VERDAD. Un indicador que grita
        // en cada guardado se deja de leer.
        txtEstado.textColor = esError ? tema.rol("risk").trazo.color : tema.pieTexto
        repintarSello()
    }

    private func repintarSello() {
        let color: NSColor
        switch sello {
        case .guardado:  color = tema.acento
        case .pendiente: color = tema.oro
        case .error:     color = tema.rol("risk").trazo.color
        }
        puntoSello.wantsLayer = true
        puntoSello.layer?.cornerRadius = 4.5
        puntoSello.layer?.cornerCurve = .continuous
        // La transición es lo que lo hace "smooth": el color se cruza, no salta.
        let a = CABasicAnimation(keyPath: "backgroundColor")
        a.duration = 0.25
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        puntoSello.layer?.add(a, forKey: "color")
        puntoSello.layer?.backgroundColor = color.cgColor
        puntoSello.toolTip = sello == .guardado ? "Guardado"
                           : (sello == .pendiente ? "Guardando…" : "No se pudo guardar")
    }

    func cerrarPanel() { panel?.removeFromSuperview(); panel = nil }

    private func abrirPanel(_ ancho: CGFloat, _ alto: CGFloat, _ x: CGFloat, _ cuerpo: (NSView) -> Void) {
        cerrarPanel()
        let v = Tarjeta(tema: tema, radio: 11)
        cuerpo(v)
        v.frame = NSRect(x: frame.minX + x, y: frame.maxY + 6, width: ancho, height: alto)
        superview?.addSubview(v)
        panel = v
    }

    private func abrirFondo() {
        abrirPanel(150, CGFloat(Fondo.allCases.count) * 32 + 10, btnFondo.frame.minX - 40) { v in
            for (i, f) in Fondo.allCases.enumerated() {
                let b = BotonPlano(icono: f.icono, titulo: f.nombre, ancho: 134, alto: 30)
                b.tema = tema; b.activo = f == fondo; b.alignment = .left
                b.alPulsar = { [weak self] in self?.alFondo?(f); self?.cerrarPanel() }
                b.frame = NSRect(x: 8, y: 5 + CGFloat(Fondo.allCases.count - 1 - i) * 32, width: 134, height: 30)
                v.addSubview(b)
            }
        }
    }

    private func abrirZoom() {
        abrirPanel(110, CGFloat(Self.niveles.count) * 30 + 10, botones[4].frame.minX - 28) { v in
            for (i, z) in Self.niveles.enumerated() {
                let b = BotonPlano(icono: nil, titulo: "\(Int(z * 100))%", ancho: 94, alto: 28)
                b.tema = tema; b.activo = abs(zoom - z) < 0.005
                b.alPulsar = { [weak self] in self?.alZoomA?(z); self?.cerrarPanel() }
                b.frame = NSRect(x: 8, y: 5 + CGFloat(Self.niveles.count - 1 - i) * 30, width: 94, height: 28)
                v.addSubview(b)
            }
        }
    }

    /*
     * EXPORTAR, con menu y en PALABRAS.
     *
     * Daniel sobre la version anterior: *"hay un boton que dice sel, intuyo que
     * descarga pero no me gusta como funciona"*. Y con razon: "sel" era una
     * abreviatura que solo entiende quien escribio el codigo, aparecia y
     * desaparecia segun hubiera seleccion, y descargaba de golpe sin decir que.
     * Ahora la opcion de seleccion se DESHABILITA en vez de esconderse: una
     * opcion que aparece y desaparece nunca se aprende.
     */
    private func abrirExportar() {
        abrirPanel(214, 76, frame.width - 240) { v in
            let filas: [(String, Bool)] = [("Exportar el lienzo", false), ("Exportar la selección", true)]
            for (i, f) in filas.enumerated() {
                let apagado = f.1 && !haySeleccion
                let b = BotonPlano(icono: f.1 ? Icono.encuadrar : Icono.imagen, titulo: f.0, ancho: 198, alto: 32)
                b.tema = tema; b.alignment = .left
                b.isEnabled = !apagado
                b.alphaValue = apagado ? 0.45 : 1
                b.alPulsar = { [weak self] in
                    guard !apagado else { return }
                    self?.alExportar?(f.1); self?.cerrarPanel()
                }
                b.frame = NSRect(x: 8, y: 6 + CGFloat(1 - i) * 34, width: 198, height: 32)
                v.addSubview(b)
            }
        }
    }
}
