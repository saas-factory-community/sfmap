import AppKit

/**
 * RENOMBRAR EN LA PROPIA FILA.
 *
 * Daniel: *"al hacer doble clic en la carpeta, poder cambiarle el nombre desde
 * ahí, no que se abra un panel de macOS"*. Antes era un `NSAlert` modal: un
 * dialogo que bloquea la app entera para editar seis letras, y que ademas
 * esconde la lista justo cuando quieres ver como quedan los nombres juntos.
 *
 * El riesgo que motivo aquel dialogo —perder el nombre por un clic fuera— se
 * resuelve al reves: salir del campo CONFIRMA, y Escape es quien cancela. Es lo
 * que hacen el Finder, Notion y cualquier lista de documentos.
 */
final class EditorEnLinea: NSTextField, NSTextFieldDelegate {
    private var alTerminar: ((String?) -> Void)?
    private var listo = false

    init(texto: String, marco: NSRect, tema: Tema, alTerminar: @escaping (String?) -> Void) {
        self.alTerminar = alTerminar
        super.init(frame: marco)
        stringValue = texto
        font = Estilo.fuente(12.5, 600)
        textColor = tema.tituloTexto
        backgroundColor = tema.lienzo
        isBordered = false
        drawsBackground = true
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = tema.acento.cgColor
        delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Enter confirma, Escape cancela. Sin esto Escape cierra la ventana.
    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) { terminar(stringValue); return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) { terminar(nil); return true }
        return false
    }
    /// Perder el foco GUARDA. Y `listo` evita la doble llamada: Enter dispara
    /// tambien el fin de edicion, y sin la bandera el nombre se manda dos veces.
    func controlTextDidEndEditing(_ n: Notification) { terminar(stringValue) }

    private func terminar(_ t: String?) {
        guard !listo else { return }
        listo = true
        let f = alTerminar; alTerminar = nil
        removeFromSuperview()
        f?(t?.trimmingCharacters(in: .whitespaces))
    }
}

/**
 * EL BUSCADOR, hundido.
 *
 * Era un `NSSearchField` del sistema, y de todo lo que había en pantalla era lo
 * que más gritaba "app genérica de macOS": su propio bisel redondeado, su lupa,
 * su tipografía y su anillo de foco azul, ninguno de esta casa.
 *
 * Aquí es un POZO: el mismo bisel del resto, invertido. Y no es un capricho de
 * pintura, es la gramática de profundidad completa — **lo que sobresale se
 * pulsa, lo que se hunde se llena**. Un campo de texto y un botón no pueden
 * verse igual y esperar que la mano sepa cuál es cuál.
 */
final class PozoBusqueda: NSView, NSTextFieldDelegate {
    var tema: Tema { didSet { repintar() } }
    var alTeclear: ((String) -> Void)?
    var texto: String { campo.stringValue }

    private let campo = NSTextField()
    private let lupa = NSImageView(image: Icono.lupa)
    private let limpiar = BotonPlano(icono: Icono.equis, ancho: 20, alto: 20)
    private var editando = false { didSet { needsDisplay = true } }

    init(tema: Tema) {
        self.tema = tema
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        campo.isBordered = false
        campo.isBezeled = false
        campo.drawsBackground = false
        campo.focusRingType = .none
        campo.font = Estilo.fuente(12, 500)
        campo.placeholderString = "Buscar…"
        campo.delegate = self
        campo.cell?.usesSingleLineMode = true
        addSubview(lupa); addSubview(campo); addSubview(limpiar)
        limpiar.isHidden = true
        limpiar.alPulsar = { [weak self] in
            self?.campo.stringValue = ""
            self?.limpiar.isHidden = true
            self?.alTeclear?("")
        }
        repintar()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        lupa.frame = NSRect(x: 7, y: (bounds.height - 15) / 2, width: 15, height: 15)
        limpiar.frame = NSRect(x: bounds.width - 24, y: (bounds.height - 20) / 2, width: 20, height: 20)
        campo.frame = NSRect(x: 26, y: (bounds.height - 17) / 2 - 1,
                             width: bounds.width - 26 - 26, height: 17)
    }

    override func draw(_ r: NSRect) {
        Estilo.pintarBisel(self, tema, radio: 8, pozo: true, borde: false)
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        // Al escribir, el canto se enciende en morado. Es el anillo de foco de
        // macOS dicho en el idioma de la casa: misma información, cero azul.
        c.addPath(CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                         cornerWidth: 8, cornerHeight: 8, transform: nil))
        c.setStrokeColor((editando ? tema.acento : tema.bisel.borde).cgColor)
        c.setLineWidth(editando ? 1.5 : 1)
        c.strokePath()
    }

    /// El clic en cualquier parte del pozo entra a escribir, no solo el clic
    /// exacto sobre el renglón de texto.
    override func mouseDown(with e: NSEvent) { window?.makeFirstResponder(campo) }

    func controlTextDidChange(_ n: Notification) {
        limpiar.isHidden = campo.stringValue.isEmpty
        alTeclear?(campo.stringValue)
    }
    func controlTextDidBeginEditing(_ n: Notification) { editando = true }
    func controlTextDidEndEditing(_ n: Notification) { editando = false }

    private func repintar() {
        campo.textColor = tema.tituloTexto
        lupa.image = Estilo.iconoBisel(Icono.lupa, tema)
        limpiar.tema = tema
        needsDisplay = true
    }
}

/// La pila del arbol, VOLTEADA: primera fila arriba, hueco abajo.
final class PilaArriba: NSStackView { override var isFlipped: Bool { true } }

/// La barra de lienzos. Se abre pulsando el HEADER.
///
/// Daniel: *"asegúrate de que si le clico al header se pueda expandir"*. En la
/// primera versión el header era una etiqueta muerta y la navegación vivía en
/// un `NSPopUpButton` gris que desplegaba **129 lienzos en una lista plana** —
/// sin carpetas, sin búsqueda y sin poder ver dónde estaba uno. La misma lista
/// que en la web es un árbol con carpetas, contador y buscador.
///
/// Aquí es el mismo árbol: carpetas plegables con su cuenta, sección "SIN
/// CARPETA" con nombre (un sitio sin nombre es un agujero: así se perdió una
/// página el 20 ago), y buscador que filtra al teclear.
final class Lateral: NSView {

    /// A donde puede caer una pagina arrastrada.
    enum Destino: Equatable { case carpeta(String), raiz }

    var tema: Tema = .claro { didSet { repintar() } }
    var paginas: [ResumenPagina] = [] { didSet { reconstruir() } }
    var carpetas: [Carpeta] = [] { didSet { reconstruir() } }
    var activa: String? { didSet { reconstruir() } }
    /// La carpeta donde esta el CURSOR del teclado. Se marca igual que la fila
    /// activa porque es la misma pregunta —"¿donde estoy?"— y dos marcas
    /// distintas para lo mismo obligan a aprender un vocabulario de colores.
    ///
    /// ⚠️ Existe porque ← y → cambian de carpeta SIN abrir nada: sin una marca
    /// visible, esas dos teclas no harian nada observable y se sentirian rotas.
    var foco: String? { didSet { if oldValue != foco { reconstruir() } } }
    /**
     * EL ESPACIO (11 sep 2026). Daniel: *"si estoy trabajando en el negocio,
     * ¿pa' qué quiero ver personal, lab, plantillas?"*.
     *
     * Un espacio ES una carpeta raíz. No hay tabla ni campo nuevo: el
     * `parent_id` que ya existía da la jerarquía y el lienzo web sigue viendo
     * las mismas carpetas. Lo que cambia es la VISTA. Con `espacio == nil` el
     * panel es la PORTADA —una fila por espacio, con su cuenta— y con un
     * espacio elegido se enseña solo su subárbol. Todo lo que parte del panel
     * (flechas, ⌘N, buscador, arrastre) queda acotado a él: el ruido de los
     * demás proyectos no existe mientras trabajas en uno.
     *
     * Cambiar de espacio limpia lo que era de la vista anterior: carpetas
     * abiertas, cursor y lote. Un cursor apuntando a una carpeta que ya no se
     * ve es exactamente la fila invisible que `aPlegar` se cuida de no dejar.
     */
    var espacio: String? {
        didSet {
            guard oldValue != espacio else { return }
            expandidas = []; ordenAbiertas = []; marcadas = []; ancla = nil
            foco = nil
            reconstruir()
        }
    }
    /// Entrar a un espacio (`id`) o volver a la portada (`nil`).
    var alElegirEspacio: ((String?) -> Void)?
    /// Las carpetas que el panel enseña AHORA: el subárbol del espacio activo.
    var carpetasVisibles: [Carpeta] { Self.carpetasDe(carpetas, espacio: espacio) }
    /// Los lienzos que el panel enseña AHORA.
    var paginasVisibles: [ResumenPagina] { Self.paginasDe(paginas, carpetas, espacio: espacio) }
    var alElegir: ((String) -> Void)?
    var alCrearPagina: ((String?) -> Void)?
    var alCrearCarpeta: ((String?) -> Void)?
    var alAnidarCarpeta: ((String, String?) -> Void)?
    var alRenombrarPagina: ((String, String) -> Void)?
    var alBorrarPagina: ((String) -> Void)?
    /// Borrar VARIOS a la vez. Quien lo recibe pregunta antes: es irreversible
    /// y de alcance masivo, y esas dos cosas juntas no salen de un clic.
    var alBorrarPaginas: (([String]) -> Void)?
    var alMoverPagina: ((String, String?) -> Void)?
    var alRenombrarCarpeta: ((String, String) -> Void)?
    var alBorrarCarpeta: ((String) -> Void)?
    /// El canto derecho se ARRASTRA (24 ago 2026). Reporta la x del puntero en
    /// coordenadas de ventana; quien coloca el panel decide el ancho y el tope.
    var alCambiarAncho: ((CGFloat) -> Void)?

    private let titulo = NSTextField(labelWithString: "LIENZOS")
    private let filo = NSView()
    private let masPagina = BotonPlano(icono: Icono.lienzoMas, ancho: 26, alto: 26)
    private let masCarpeta = BotonPlano(icono: Icono.carpetaMas, ancho: 26, alto: 26)
    private let buscador = PozoBusqueda(tema: .claro)
    private let scroll = NSScrollView()
    private let pila = PilaArriba()
    private var expandidas: Set<String> = []
    /// Las carpetas abiertas EN ORDEN de apertura (la última al final): la de
    /// hasta arriba del orden es DONDE ESTÁS, igual que en VSCode. El botón + y
    /// ⌘N crean ahí, no en la raíz — un lienzo nuevo que nace en "SIN CARPETA"
    /// cuando tienes la carpeta de agosto abierta es el sistema decidiendo por
    /// ti (23 ago 2026).
    private var ordenAbiertas: [String] = []
    private var filtro = ""
    private var anchoConstruido: CGFloat = -1
    private let agarre = AgarreLateral()

    /// La carpeta "de pie": la última abierta que SIGUE abierta. Plegarla cae a
    /// la anterior que siga abierta, y si no queda ninguna, a la raíz.
    var carpetaContexto: String? { ordenAbiertas.last }

    /// Plegar o abrir una carpeta y actualizar el contexto. Una sola pieza para
    /// el clic de la fila y para las pruebas.
    // ── multiselección ──────────────────────────────────────────────────────
    /// Los lienzos marcados para una acción en lote.
    private(set) var marcadas: Set<String> = []
    /// Desde dónde mide ⇧ su tramo.
    private var ancla: String?

    /// Repinta el lote sin reconstruir la lista entera: reconstruir en cada
    /// clic tira el scroll al principio, y marcar cinco cosas seguidas con la
    /// lista saltando es imposible.
    private func repintarLote() {
        for f in pila.arrangedSubviews.compactMap({ $0 as? FilaPulsable }) {
            if let id = f.arrastrable { f.enLote = marcadas.contains(id) }
        }
    }

    /// ⇧: marca todo lo que hay ENTRE el ancla y esta fila, en el orden en que
    /// se ven — no en el del array, que no es el mismo.
    private func marcarTramo(hasta id: String) {
        let visibles = pila.arrangedSubviews.compactMap { ($0 as? FilaPulsable)?.arrastrable }
        guard let b = visibles.firstIndex(of: id) else { return }
        let a = ancla.flatMap { visibles.firstIndex(of: $0) } ?? b
        for i in min(a, b)...max(a, b) { marcadas.insert(visibles[i]) }
        repintarLote()
    }

    func limpiarLote() { guard !marcadas.isEmpty else { return }; marcadas = []; repintarLote() }

    func alternarExpansion(_ id: String) {
        if expandidas.contains(id) {
            expandidas.remove(id)
            ordenAbiertas.removeAll { $0 == id }
        } else {
            expandidas.insert(id)
            ordenAbiertas.removeAll { $0 == id }
            ordenAbiertas.append(id)
        }
        reconstruir()
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        /*
         * EL RÓTULO EN MONO, y la regla es de la casa: el monospace se reserva
         * al cromo —counters, rótulos, datos— y no toca el contenido. Una
         * eyebrow espaciada en mono es de instrumento; en la misma tipografía
         * que los nombres de abajo, es un nombre más que hay que descartar.
         */
        titulo.font = Estilo.mono(9.5, 700)
        addSubview(titulo)
        addSubview(filo)

        // El ALTA vive junto al titulo del panel, no escondida en un menu: si
        // crear un lienzo exige buscar donde, se crean menos lienzos. Y nace
        // en la carpeta ABIERTA, no en la raíz (ver `carpetaContexto`).
        masPagina.globo = "Lienzo nuevo  ⌘N"
        // Sin carpeta abierta, el lienzo nace en la RAÍZ DEL ESPACIO, no
        // huérfano: en la portada el botón no se enseña (no hay dónde nacer).
        masPagina.alPulsar = { [weak self] in
            guard let self else { return }
            self.alCrearPagina?(self.carpetaContexto ?? self.espacio)
        }
        masCarpeta.globo = "Carpeta nueva  ⌘⇧N"
        masCarpeta.alPulsar = { [weak self] in
            guard let self else { return }
            // En la portada crea un ESPACIO (carpeta raíz); dentro de uno, una
            // subcarpeta suya. Nunca una carpeta dentro de una subcarpeta: una
            // subcarpeta dentro de otra sería el tercer nivel, y son dos.
            self.alCrearCarpeta?(self.espacio)
        }
        addSubview(masPagina); addSubview(masCarpeta)
        // El rótulo es el camino de VUELTA: dentro de un espacio dice
        // "‹ ESPACIOS" y pulsarlo regresa a la portada.
        titulo.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(pulsarTitulo)))

        buscador.alTeclear = { [weak self] t in
            self?.filtro = t.lowercased()
            self?.reconstruir()
        }
        addSubview(buscador)

        pila.orientation = .vertical
        pila.alignment = .leading
        pila.spacing = 1
        pila.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 10, right: 0)
        /*
         * ⚠️ EL ÁRBOL SE PINTABA ABAJO.
         *
         * AppKit apila desde el ORIGEN, y el origen de una vista no volteada
         * está abajo a la izquierda. Con el árbol más corto que el scroll, todo
         * caía al fondo del panel y arriba quedaba un hueco enorme: parecía que
         * no había cargado.
         *
         * `distribution = .fill` + un espaciador al final empujan el contenido
         * hacia arriba, que es donde una lista empieza a leerse.
         */
        pila.distribution = .fill
        // Y VOLTEADA: en una vista de documento no volteada el origen esta
        // ABAJO, asi que un arbol mas corto que el panel se hunde y aparece un
        // hueco enorme bajo el buscador. Volteada, el origen es la esquina de
        // arriba y una lista corta empieza donde empiezan todas las listas.
        scroll.documentView = pila
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        /*
         * OVERLAY SIEMPRE (Daniel, 24 ago: "quita esa barra gris sombreada").
         * Con un ratón conectado, macOS elige el scroller LEGACY: un riel
         * permanente pintado sobre el panel. Forzado a overlay, el knob solo
         * asoma mientras se scrollea — y se re-asserta en layout() porque el
         * sistema lo revierte cuando cambia el aparato apuntador.
         */
        scroll.scrollerStyle = .overlay
        addSubview(scroll)

        agarre.alArrastrar = { [weak self] xVentana in self?.alCambiarAncho?(xVentana) }
        addSubview(agarre)
    }
    required init?(coder: NSCoder) { fatalError() }

    /**
     * ARRASTRAR UNA PAGINA A SU CARPETA.
     *
     * Daniel: *"no necesito ver tantos «mover a»; lo contrario, tan simple como
     * arrastrando y soltando a la carpeta correspondiente"*. Y tenia razon en lo
     * aritmetico: el menu crecia con el numero de carpetas, asi que la accion
     * mas comun era la que mas costaba leer.
     *
     * Es un bucle MODAL de eventos, no el arrastre del sistema. El sistema esta
     * pensado para llevar datos ENTRE aplicaciones —pasteboard, promesas de
     * archivo, tipos declarados— y aqui el viaje empieza y acaba en la misma
     * lista. Cien lineas de ceremonia para mover una fila tres pixeles.
     *
     * ⚠️ Soltar en el VACIO no hace nada, a proposito. En el rail web todo el
     * panel era zona de soltado y una pagina se salia sola de su carpeta al
     * arrastrarla un poco; asi se perdio una de vista. Sacar tiene su propia
     * diana: el rotulo SIN CARPETA.
     */
    private func arrastrarPagina(_ id: String) {
        guard let w = window else { return }
        let origen = paginas.first { $0.id == id }?.folderId
        var destino: Destino?
        var marcada: FilaPulsable?
        NSCursor.closedHand.push()
        defer { NSCursor.pop(); marcada?.marcarSoltado(false) }

        while let ev = w.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if ev.type == .leftMouseUp { break }
            let p = convert(ev.locationInWindow, from: nil)
            let fila = filaEn(p)
            // Sobre su propia carpeta no se marca nada: soltar ahi no mueve.
            let d = fila?.destino
            let util: Bool = switch d {
                case .carpeta(let c): c != origen
                case .raiz: origen != nil
                case nil: false
            }
            let nueva = util ? fila : nil
            if nueva !== marcada {
                marcada?.marcarSoltado(false)
                nueva?.marcarSoltado(true)
                marcada = nueva
            }
            destino = util ? d : nil
        }
        switch destino {
        case .carpeta(let c): alMoverPagina?(id, c)
        case .raiz: alMoverPagina?(id, nil)
        case nil: break
        }
    }

    /// Arrastra una CARPETA a otra para anidarla, o al rótulo para sacarla.
    private func arrastrarCarpeta(_ id: String) {
        guard let w = window else { return }
        let yaEsHija = carpetas.first { $0.id == id }?.madre != nil
        var destino: Destino?
        var marcada: FilaPulsable?
        NSCursor.closedHand.push()
        defer { NSCursor.pop(); marcada?.marcarSoltado(false) }

        while let ev = w.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if ev.type == .leftMouseUp { break }
            let fila = filaEn(convert(ev.locationInWindow, from: nil))
            let d = fila?.destino
            let util: Bool = switch d {
                // Ni sobre si misma, ni sobre una que ya es hija (2º nivel).
                case .carpeta(let c): c != id && carpetas.first { $0.id == c }?.madre == nil
                case .raiz: yaEsHija
                case nil: false
            }
            let nueva = util ? fila : nil
            if nueva !== marcada {
                marcada?.marcarSoltado(false); nueva?.marcarSoltado(true); marcada = nueva
            }
            destino = util ? d : nil
        }
        switch destino {
        case .carpeta(let c): alAnidarCarpeta?(id, c)
        case .raiz: alAnidarCarpeta?(id, nil)
        case nil: break
        }
    }

    /// Monta el editor sobre el titulo de una fila y devuelve el nombre nuevo.
    private func editarNombre(en fila: FilaPulsable, x: CGFloat, actual: String,
                              _ hecho: @escaping (String) -> Void) {
        // Se oculta la etiqueta, no se borra: si cancelas, vuelve tal cual.
        let etiqueta = fila.subviews.compactMap { $0 as? NSTextField }
            .first { $0.frame.minX == x }
        etiqueta?.isHidden = true
        let marco = NSRect(x: x - 4, y: (fila.bounds.height - 22) / 2,
                           width: fila.bounds.width - x - 8, height: 22)
        let campo = EditorEnLinea(texto: actual, marco: marco, tema: tema) { nuevo in
            etiqueta?.isHidden = false
            guard let n = nuevo, !n.isEmpty, n != actual else { return }
            hecho(n)
        }
        fila.addSubview(campo)
        window?.makeFirstResponder(campo)
        campo.currentEditor()?.selectAll(nil)
    }

    private func filaEn(_ p: NSPoint) -> FilaPulsable? {
        let enPila = convert(p, to: pila)
        return pila.arrangedSubviews.compactMap { $0 as? FilaPulsable }
            .first { $0.frame.contains(enPila) }
    }

    /// El clic derecho en el HUECO del panel no hace nada — pero se lo queda.
    /// Dejarlo pasar significaba abrir el menu del tablero sobre el panel.
    override func rightMouseDown(with e: NSEvent) {}

    /**
     * LA PLACA.
     *
     * El panel es la pieza de metal más grande de la ventana, así que es donde
     * más se nota la diferencia entre un relleno plano y un bisel: la banda de
     * luz arriba le da un canto por donde empezar a leer, y el resto se asienta.
     * Sin radio y sin borde a los cuatro lados, porque va a ras: el único canto
     * que necesita es el filo derecho contra el tablero, que ya pone `filo`.
     */
    override func draw(_ r: NSRect) { Estilo.pintarBisel(self, tema, radio: 0, borde: false) }

    override func layout() {
        super.layout()
        let m: CGFloat = 14
        filo.frame = NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height)
        titulo.frame = NSRect(x: m + 1, y: bounds.height - 30, width: bounds.width - m * 2 - 60, height: 16)
        masCarpeta.frame = NSRect(x: bounds.width - m - 58, y: bounds.height - 36, width: 26, height: 26)
        masPagina.frame = NSRect(x: bounds.width - m - 28, y: bounds.height - 36, width: 26, height: 26)
        buscador.frame = NSRect(x: m, y: bounds.height - 70, width: bounds.width - m * 2, height: 28)
        scroll.frame = NSRect(x: 6, y: 8, width: bounds.width - 14, height: bounds.height - 84)
        scroll.scrollerStyle = .overlay   // el sistema lo revierte a legacy; aquí se re-impone
        pila.frame.size.width = scroll.frame.width - 4
        // Las filas se construyen con el ancho del scroll: si se construyeron
        // antes de tener frame, salieron de 1 px y hay que rehacerlas.
        if abs(anchoConstruido - scroll.frame.width) > 0.5 { reconstruir() }
        /*
         * ⚠️ EL ALTO DEL ARBOL SE FIJABA UNA VEZ Y NO VOLVIA A CRECER.
         *
         * Se calculaba solo al reconstruir, asi que el arbol se quedaba con el
         * alto de la PRIMERA maquetacion —la de la ventana chica de arranque, 684
         * px— y al abrirse la ventana a pantalla completa (986) sobraban 302 px.
         * En una vista de documento sin voltear ese sobrante va ARRIBA: el hueco
         * enorme entre el buscador y la primera carpeta. Medido, no deducido.
         */
        pila.frame.size.height = max(scroll.contentSize.height, pila.fittingSize.height)
        pila.frame.origin.y = 0
        // El agarre vive ENCIMA del filo: 16 px de diana (Daniel, 24 ago:
        // "es difícil agarrarlo" con 9 — la ley de Fitts no negocia).
        agarre.frame = NSRect(x: bounds.width - 16, y: 0, width: 16, height: bounds.height)
    }

    /// Abre todas las carpetas. Lo usa la escena de verificación: un árbol
    /// cerrado no demuestra que el árbol funcione.
    /// Abre una carpeta concreta (tras crear algo dentro, para que se vea).
    /// Plegar una carpeta concreta, sin alternar.
    func plegar(_ id: String) {
        expandidas.remove(id)
        ordenAbiertas.removeAll { $0 == id }
        reconstruir()
    }

    func abrir(_ id: String) {
        expandidas.insert(id)
        ordenAbiertas.removeAll { $0 == id }
        ordenAbiertas.append(id)
        reconstruir()
    }

    func abrirTodas() { expandidas = Set(carpetas.map(\.id)); reconstruir() }

    private func repintar() {
        /*
         * A RAS, no flotando.
         *
         * Era una tarjeta con sombra encima del lienzo. En sfcal —y en toda app
         * de macOS con barra lateral— el panel es PARTE de la ventana: fondo
         * propio, un filo a la derecha, y nada más. Flotando se leía como un
         * objeto puesto encima; a ras se lee como una zona de la app.
         */
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.borderWidth = 0
        layer?.shadowOpacity = 0
        // El fondo lo pinta `draw`: es una placa de bisel, no un color plano.
        layer?.backgroundColor = NSColor.clear.cgColor
        filo.wantsLayer = true
        filo.layer?.backgroundColor = tema.filoCromo.cgColor
        pintarTitulo()
        buscador.tema = tema
        masPagina.tema = tema; masCarpeta.tema = tema
        agarre.tema = tema
        needsDisplay = true
        reconstruir()
    }

    private func coinciden(_ p: ResumenPagina) -> Bool {
        filtro.isEmpty || p.nombre.lowercased().contains(filtro)
    }

    /**
     * EL ORDEN DE LA LISTA ES EL ORDEN EN QUE SE LEE.
     *
     * Las paginas NO se ordenaban: caian en el orden en que llegaban del
     * servidor (por fecha), asi que un curso numerado 00→08 se enseñaba al
     * reves —08 arriba, 00 abajo— y para empezar por el principio habia que
     * leer la lista de abajo hacia arriba. Daniel, 26 ago: *"el orden pudiera
     * ser inverso? en base a la numerologia"*.
     *
     * `localizedStandardCompare` es el mismo criterio del Finder: cuenta los
     * numeros como NUMEROS (el 2 va antes que el 10, no despues como haria
     * `<` sobre texto) e ignora mayusculas y acentos. Un `<` a secas pondria
     * "Estructura General" antes que "control · cajas" solo porque la E
     * mayuscula pesa menos en ASCII que la c minuscula, y eso no es un orden:
     * es un accidente de la codificacion.
     */
    /**
     * LOS LIENZOS QUE COMPARTEN CARPETA CON EL QUE ESTAS VIENDO, EN ORDEN.
     *
     * Vive aqui, junto a `porNombre`, porque el orden tiene que ser EL MISMO
     * que el panel enseña. Si los atajos ordenaran por su cuenta serian dos
     * listas distintas, y pulsar el `3` llevaria a algo que en pantalla no es
     * el cuarto: un atajo que no coincide con lo que se ve es peor que no
     * tener atajo.
     *
     * Un lienzo suelto (sin carpeta) tiene de vecinos a los demas sueltos: el
     * grupo "SIN CARPETA" del panel es un vecindario como cualquier otro.
     */
    static func vecindario(_ todas: [ResumenPagina], de actual: String?) -> [ResumenPagina] {
        let carpeta = todas.first { $0.id == actual }?.folderId
        return todas.filter { $0.folderId == carpeta }.sorted { porNombre($0.nombre, $1.nombre) }
    }

    /// El lienzo en la POSICION `n` del vecindario, o nil si ahi no hay nada.
    ///
    /// Sin adivinar: pulsar el 7 en una carpeta de tres NO lleva al ultimo. Si
    /// lo hiciera, el 7 y el 3 acabarian en el mismo sitio y el atajo dejaria
    /// de significar una posicion.
    static func enPosicion(_ todas: [ResumenPagina], de actual: String?, _ n: Int) -> String? {
        let v = vecindario(todas, de: actual)
        return v.indices.contains(n) ? v[n].id : nil
    }

    /**
     * LAS CARPETAS EN EL ORDEN EN QUE SE VEN, aplanadas.
     *
     * El panel enseña cada carpeta raiz seguida de sus hijas, asi que la
     * flecha tiene que recorrerlas en ese mismo orden: si navegara solo por
     * las raices, las subcarpetas serian invisibles al teclado aunque estén
     * ahi delante.
     */
    static func carpetasEnOrden(_ carpetas: [Carpeta], raiz: String? = nil) -> [Carpeta] {
        var fila: [Carpeta] = []
        // `raiz` es el espacio: dentro de uno, las "madres" son sus hijas directas.
        for madre in carpetas.filter({ $0.madre == raiz }).sorted(by: { porNombre($0.nombre, $1.nombre) }) {
            fila.append(madre)
            fila += carpetas.filter { $0.madre == madre.id }.sorted { porNombre($0.nombre, $1.nombre) }
        }
        return fila
    }

    /**
     * QUE SE PLIEGA AL SALIR DE UNA CARPETA. *"Al saltar entre carpetas cierra
     * la anterior, para no dejar un desorden"*.
     *
     * ⚠️ SALVO SI LA ANTERIOR CONTIENE A LA NUEVA. Bajar de "Contenido" a su
     * hija "Curso Claude Code" es MOVERSE DENTRO, no salir: plegar la madre
     * esconderia la hija a la que acabas de llegar, y el cursor se quedaria
     * marcando una fila invisible. La regla no es "cierra la anterior" a
     * secas: es "cierra lo que dejas atras", y a una madre no la dejas atras
     * mientras estas dentro de ella.
     *
     * Y al reves: al salir de una hija hacia otra rama, se pliega tambien la
     * madre. Si no, "Contenido" se queda abierta enseñando lienzos de un sitio
     * donde ya no estas — que es exactamente el desorden que se queria evitar.
     */
    static func aPlegar(_ carpetas: [Carpeta], saliendoDe vieja: String?, entrandoA nueva: String) -> [String] {
        guard let vieja, vieja != nueva else { return [] }
        let madreDe = Dictionary(uniqueKeysWithValues: carpetas.map { ($0.id, $0.madre) })
        // La cadena de la nueva: ella y sus ancestros. Nada de aqui se pliega.
        var dentro: Set<String> = [nueva]
        var c = madreDe[nueva] ?? nil
        while let id = c { dentro.insert(id); c = madreDe[id] ?? nil }
        guard !dentro.contains(vieja) else { return [] }
        var cerrar = [vieja]
        if let madre = madreDe[vieja] ?? nil, !dentro.contains(madre) { cerrar.append(madre) }
        return cerrar
    }

    /// La carpeta anterior (-1) o siguiente (+1). Se queda en los extremos: sin
    /// vuelta, igual que los lienzos.
    static func carpetaVecina(_ carpetas: [Carpeta], raiz: String? = nil, de actual: String?, paso: Int) -> String? {
        let f = carpetasEnOrden(carpetas, raiz: raiz)
        guard !f.isEmpty else { return nil }
        // Sin foco todavia, la primera flecha aterriza en la primera carpeta
        // en vez de no hacer nada: pulsar y que no pase nada se lee como que
        // el atajo no existe.
        guard let i = f.firstIndex(where: { $0.id == actual }) else { return f.first?.id }
        let j = i + paso
        return f.indices.contains(j) ? f[j].id : nil
    }

    /// Los lienzos de UNA carpeta concreta, en el orden del panel.
    ///
    /// Distinto de `vecindario`, que parte del lienzo abierto: aqui se parte de
    /// la carpeta donde esta el CURSOR, que puede no ser la misma — es
    /// justamente lo que permite moverse de carpeta sin abrir nada.
    static func lienzosDe(_ todas: [ResumenPagina], carpeta: String?) -> [ResumenPagina] {
        todas.filter { $0.folderId == carpeta }.sorted { porNombre($0.nombre, $1.nombre) }
    }

    /// El lienzo anterior (-1) o siguiente (+1) DENTRO de la misma carpeta.
    ///
    /// ⚠️ Nunca se sale del vecindario y nunca da la vuelta. Las dos cosas por
    /// el mismo motivo: al final de la lista, se acabo. Envolver haria que
    /// "siguiente" te devuelva al primero, y saltar a la carpeta de al lado te
    /// dejaria en otro sitio del arbol — las dos sin que nada te avise de que
    /// cambiaste de contexto (Daniel, 26 ago: *"con flecha no me muevo entre
    /// carpetas, asegurate que sea asi"*).
    static func vecino(_ todas: [ResumenPagina], de actual: String?, paso: Int) -> String? {
        let v = vecindario(todas, de: actual)
        guard let i = v.firstIndex(where: { $0.id == actual }) else { return nil }
        let j = i + paso
        return v.indices.contains(j) ? v[j].id : nil
    }

    // ── espacios (lógica pura, con pruebas en EspaciosTests) ────────────────

    /// La carpeta RAÍZ de la que cuelga una carpeta (ella misma si ya es raíz).
    /// `nil` si no hay carpeta o no se conoce: eso es un lienzo huérfano.
    static func raizDe(_ carpetas: [Carpeta], carpeta: String?) -> String? {
        guard var id = carpeta else { return nil }
        let madreDe = Dictionary(uniqueKeysWithValues: carpetas.map { ($0.id, $0.madre) })
        guard madreDe[id] != nil else { return nil }
        // Acotado: un ciclo en `parent_id` (la BD no lo impide) no puede colgar la app.
        var pasos = 0
        while let m = madreDe[id] ?? nil, pasos < 16 { id = m; pasos += 1 }
        return id
    }

    /// El subárbol de carpetas de un espacio, sin la raíz. En la portada, ninguna.
    static func carpetasDe(_ carpetas: [Carpeta], espacio: String?) -> [Carpeta] {
        guard let espacio else { return [] }
        return carpetas.filter { $0.id != espacio && raizDe(carpetas, carpeta: $0.id) == espacio }
    }

    /// Los lienzos de un espacio (raíz y subcarpetas). En la portada, los
    /// HUÉRFANOS: los que no cuelgan de ninguna carpeta conocida. Se enseñan
    /// ahí para que no se pierdan (así se perdió una página el 20 ago), no
    /// para estorbar dentro de un espacio.
    static func paginasDe(_ paginas: [ResumenPagina], _ carpetas: [Carpeta], espacio: String?) -> [ResumenPagina] {
        paginas.filter { raizDe(carpetas, carpeta: $0.folderId) == espacio }
    }

    /// Los espacios en el orden de la portada, cada uno con cuántos lienzos tiene.
    static func espacios(_ carpetas: [Carpeta], _ paginas: [ResumenPagina]) -> [(carpeta: Carpeta, cuenta: Int)] {
        carpetas.filter { $0.madre == nil }.sorted { porNombre($0.nombre, $1.nombre) }
            .map { ($0, paginasDe(paginas, carpetas, espacio: $0.id).count) }
    }

    static func porNombre(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }

    private func reconstruir() {
        pila.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // Un espacio que ya no existe (se borró la carpeta) devuelve a la portada.
        if let e = espacio, !carpetas.contains(where: { $0.id == e }) { espacio = nil; return }
        pintarTitulo()
        masPagina.isHidden = espacio == nil
        if let e = espacio { arbol(de: e) } else { portada() }
        // El espaciador se come el sobrante y deja el árbol pegado arriba.
        let cola = NSView()
        cola.translatesAutoresizingMaskIntoConstraints = false
        cola.setContentHuggingPriority(.init(1), for: .vertical)
        pila.addArrangedSubview(cola)
        anchoConstruido = scroll.frame.width
        pila.layoutSubtreeIfNeeded()
        pila.frame.size.height = max(scroll.contentSize.height, pila.fittingSize.height)
        pila.frame.origin.y = 0
        /*
         * ⚠️ ABRE POR ARRIBA. Un `NSScrollView` conserva su desplazamiento al
         * cambiar el contenido, así que tras reconstruir el árbol la lista
         * aparecía a media altura: las primeras filas visibles eran páginas
         * sueltas sin el rótulo de su carpeta, que había quedado más arriba. Se
         * lee como una lista mal agrupada, no como una lista desplazada.
         */
        scroll.documentView?.scroll(NSPoint(x: 0, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// LA PORTADA: una fila por espacio. Y con algo escrito en el buscador,
    /// busca en TODO: es la única vista desde la que se ve el conjunto.
    private func portada() {
        if !filtro.isEmpty {
            let hallados = paginas.filter(coinciden).sorted { Self.porNombre($0.nombre, $1.nombre) }
            for p in hallados { pila.addArrangedSubview(filaPagina(p, sangria: 6)) }
            if hallados.isEmpty { pila.addArrangedSubview(etiqueta("Nada con ese nombre.", sangria: 10)) }
            return
        }
        let lista = Self.espacios(carpetas, paginas)
        for (c, n) in lista { pila.addArrangedSubview(filaEspacio(c, cuenta: n)) }
        if lista.isEmpty { pila.addArrangedSubview(etiqueta("Todavía no hay espacios.", sangria: 10)) }
        let sueltas = Self.paginasDe(paginas, carpetas, espacio: nil).sorted { Self.porNombre($0.nombre, $1.nombre) }
        if !sueltas.isEmpty {
            pila.addArrangedSubview(rotulo("SIN ESPACIO", cuenta: sueltas.count))
            for p in sueltas { pila.addArrangedSubview(filaPagina(p, sangria: 6)) }
        }
    }

    /// EL ÁRBOL DE UN ESPACIO: su nombre arriba (que es también la diana para
    /// SACAR un lienzo de una subcarpeta), sus subcarpetas y sus lienzos sueltos.
    private func arbol(de e: String) {
        let visibles = paginasVisibles.filter(coinciden)
        let nombre = carpetas.first { $0.id == e }?.nombre ?? "?"
        pila.addArrangedSubview(rotulo(nombre.uppercased(), cuenta: visibles.count, destino: .carpeta(e)))
        let subs = carpetas.filter { $0.madre == e }.sorted { Self.porNombre($0.nombre, $1.nombre) }
        // Las SUBCARPETAS van primero: son contenedores, y un contenedor
        // enterrado bajo veinte páginas no se encuentra.
        for c in subs { ramaDe(c, sangria: 0, visibles: visibles) }
        let sueltas = visibles.filter { $0.folderId == e }.sorted { Self.porNombre($0.nombre, $1.nombre) }
        for p in sueltas { pila.addArrangedSubview(filaPagina(p, sangria: 6)) }
        if visibles.isEmpty {
            pila.addArrangedSubview(etiqueta(filtro.isEmpty ? "Todavía no hay lienzos aquí." : "Nada con ese nombre.", sangria: 10))
        }
    }

    /*
     * DOS NIVELES, NI UNO MAS.
     *
     * Daniel: *"quiero poder guardar carpetas dentro de carpetas, solo un
     * nivel de profundidad, no necesito más"*. El limite es una decision de
     * diseño, no una carencia: con tres niveles ya hay que RECORDAR donde
     * guardaste algo, y una lista que exige memoria deja de ser un indice.
     * Con los espacios, el nivel 1 es el espacio y el 2 sus subcarpetas.
     *
     * Lo impone la app (la columna `parent_id` aceptaria cadenas): una
     * carpeta que YA es hija no ofrece "carpeta dentro". Si la BD trae un
     * tercer nivel (se creo por REST), se pinta igual — esconderlo seria
     * perder lienzos — pero no se puede crear desde aqui.
     */
    private func ramaDe(_ c: Carpeta, sangria: CGFloat, visibles: [ResumenPagina]) {
        let hijas = visibles.filter { $0.folderId == c.id }.sorted { Self.porNombre($0.nombre, $1.nombre) }
        let subs = carpetas.filter { $0.madre == c.id }.sorted { Self.porNombre($0.nombre, $1.nombre) }
        // Con un filtro activo, una carpeta sin resultados no se enseña:
        // buscar y ver diez carpetas vacías es peor que no buscar.
        if !filtro.isEmpty && hijas.isEmpty && subs.isEmpty { return }
        let abierta = expandidas.contains(c.id) || !filtro.isEmpty
        pila.addArrangedSubview(filaCarpeta(c, abierta: abierta, sangria: sangria))
        guard abierta else { return }
        for sub in subs { ramaDe(sub, sangria: sangria + 16, visibles: visibles) }
        for p in hijas { pila.addArrangedSubview(filaPagina(p, sangria: sangria + 18)) }
        if hijas.isEmpty && subs.isEmpty {
            pila.addArrangedSubview(etiqueta("vacía", sangria: sangria + 22))
        }
    }

    /// Una fila de la portada: el espacio, con su cuenta en mono a la derecha.
    /// Pulsar ENTRA. Es diana de soltado para meterle un lienzo huérfano.
    private func filaEspacio(_ c: Carpeta, cuenta: Int) -> NSView {
        let v = FilaPulsable(alto: 36, tema: tema, activa: foco == c.id)
        v.destino = .carpeta(c.id)
        v.alPulsar = { [weak self] in self?.alElegirEspacio?(c.id) }
        let ic = NSImageView(image: Estilo.iconoBisel(Icono.carpeta, tema))
        ic.frame = NSRect(x: 12, y: 9, width: 18, height: 18)
        v.addSubview(ic)
        let t = NSTextField(labelWithString: c.nombre)
        t.font = Estilo.fuente(13.5, 600); t.textColor = tema.tituloTexto
        t.lineBreakMode = .byTruncatingMiddle
        t.frame = NSRect(x: 38, y: 9, width: v.frame.width - 38 - 52, height: 18)
        v.addSubview(t)
        // La cuenta en mono: es cromo (un dato), no contenido.
        let n = NSTextField(labelWithString: "\(cuenta)")
        n.attributedStringValue = NSAttributedString(string: "\(cuenta)", attributes: [
            .font: Estilo.mono(10, 600), .foregroundColor: tema.pieTexto, .kern: 0.6])
        n.alignment = .right
        n.frame = NSRect(x: v.frame.width - 46, y: 11, width: 34, height: 14)
        v.addSubview(n)
        v.alRenombrar = { [weak self] in
            self?.editarNombre(en: v, x: 38, actual: c.nombre) { nuevo in
                self?.alRenombrarCarpeta?(c.id, nuevo)
            }
        }
        v.alMenu = { [weak self] in
            guard let self else { return }
            self.menu([
                ("Entrar", false, { self.alElegirEspacio?(c.id) }),
                ("Lienzo nuevo aquí", false, { self.alCrearPagina?(c.id) }),
                ("Carpeta dentro", false, { self.alCrearCarpeta?(c.id) }),
                ("Renombrar  ·  doble clic", false, { v.alRenombrar?() }),
                ("Borrar espacio…", true, { self.alBorrarCarpeta?(c.id) }),
            ])
        }
        return v
    }

    @objc private func pulsarTitulo() {
        guard espacio != nil else { return }
        alElegirEspacio?(nil)
    }

    private func pintarTitulo() {
        let texto = espacio == nil ? "ESPACIOS" : "‹ ESPACIOS"
        titulo.attributedStringValue = NSAttributedString(string: texto, attributes: [
            .font: Estilo.mono(9.5, 700),
            .foregroundColor: espacio == nil ? tema.pieTexto : tema.acento, .kern: 1.6])
    }

    // ── filas ───────────────────────────────────────────────────────────────
    private func caja(_ alto: CGFloat) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: max(1, scroll.frame.width - 4), height: alto))
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: alto).isActive = true
        v.widthAnchor.constraint(equalToConstant: max(1, scroll.frame.width - 4)).isActive = true
        return v
    }

    private func filaCarpeta(_ c: Carpeta, abierta: Bool, sangria: CGFloat = 0) -> NSView {
        let v = FilaPulsable(alto: 30, tema: tema, activa: foco == c.id)
        // Dentro de un espacio, sus subcarpetas SÍ reciben lienzos: son el
        // último nivel, y el arrastre es como se mueve un lienzo aquí.
        if c.madre == nil || c.madre == espacio { v.destino = .carpeta(c.id) }
        // Una carpeta se arrastra a otra solo en la portada (anidar raíces) y
        // solo si NO tiene hijas: lo contrario abriría un tercer nivel.
        if espacio == nil, !carpetas.contains(where: { $0.madre == c.id }) {
            v.arrastrableCarpeta = c.id
            v.alArrastrar = { [weak self] id in self?.arrastrarCarpeta(id) }
        }
        v.alPulsar = { [weak self] in self?.alternarExpansion(c.id) }
        let ch = NSImageView(image: Estilo.iconoBisel(abierta ? Icono.chevronAbajo : Icono.chevronDerecha, tema))
        ch.frame = NSRect(x: 6 + sangria, y: 7, width: 16, height: 16)
        v.addSubview(ch)
        let ic = NSImageView(image: Estilo.iconoBisel(abierta ? Icono.carpetaAbierta : Icono.carpeta, tema))
        ic.frame = NSRect(x: 24 + sangria, y: 6, width: 18, height: 18)
        v.addSubview(ic)
        let t = NSTextField(labelWithString: c.nombre)
        t.font = Estilo.fuente(12.5, 600); t.textColor = tema.cuerpoTexto
        t.lineBreakMode = .byTruncatingMiddle
        t.toolTip = c.nombre
        t.frame = NSRect(x: 46 + sangria, y: 6, width: v.frame.width - 46 - sangria - 12, height: 17)
        v.addSubview(t)
        v.alRenombrar = { [weak self] in
            self?.editarNombre(en: v, x: 46 + sangria, actual: c.nombre) { n in
                self?.alRenombrarCarpeta?(c.id, n)
            }
        }
        let menuCarpeta: () -> Void = { [weak self] in
            guard let self else { return }
            var filas: [(String, Bool, () -> Void)] = [
                ("Lienzo nuevo aquí", false, { self.alCrearPagina?(c.id) }),
            ]
            // Solo en las carpetas de primer nivel: una subcarpeta dentro de una
            // subcarpeta seria el tercer nivel, y son dos.
            if c.madre == nil {
                filas.append(("Carpeta dentro", false, { self.alCrearCarpeta?(c.id) }))
            } else if self.espacio == nil {
                // Sacar una subcarpeta a la raíz la vuelve un ESPACIO; dentro de
                // un espacio eso no tiene sentido y no se ofrece.
                filas.append(("Sacar de la carpeta", false, { self.alAnidarCarpeta?(c.id, nil) }))
            }
            filas.append(("Renombrar  ·  doble clic", false, { v.alRenombrar?() }))
            filas.append(("Borrar carpeta…", true, { self.alBorrarCarpeta?(c.id) }))
            self.menu(filas)
        }
        v.alMenu = menuCarpeta
        return v
    }

    /*
     * ⚠️ EL BORRADO ERA INVISIBLE.
     *
     * En la primera version del rail web, borrar una pagina solo existia por
     * clic derecho: funcionaba, y no habia forma de descubrirlo. Daniel:
     * *"estoy intentando eliminar algunos manualmente pero no estoy siendo
     * capaz"*. Un boton de tres puntos en cada fila cuesta 30 px y convierte una
     * capacidad escondida en una que se ve.
     */

    private func menu(_ filas: [(String, Bool, () -> Void)]) {
        let m = NSMenu()
        for (t, peligro, f) in filas {
            let i = NSMenuItem(title: t, action: #selector(disparar(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = Delegado.Bloque(f)
            if peligro { i.attributedTitle = NSAttributedString(string: t, attributes: [
                .foregroundColor: tema.rol("risk").trazo.color, .font: NSFont.menuFont(ofSize: 13)]) }
            m.addItem(i)
        }
        m.popUp(positioning: nil, at: NSEvent.mouseLocation.equalTo(.zero) ? .zero
                : convert(window?.convertPoint(fromScreen: NSEvent.mouseLocation) ?? .zero, from: nil), in: self)
    }

    @objc private func disparar(_ i: NSMenuItem) { (i.representedObject as? Delegado.Bloque)?.f() }


    private func filaPagina(_ p: ResumenPagina, sangria: CGFloat) -> NSView {
        let esActiva = p.id == activa
        let v = FilaPulsable(alto: 28, tema: tema, activa: esActiva)
        /*
         * EL ORO ES "AQUÍ ESTÁS", y es el único sitio del panel donde aparece.
         *
         * La marca tiene dos colores con oficios distintos (núcleo §1): el
         * morado es el concepto y el chasis —por eso marca la HERRAMIENTA activa
         * y la promesa de soltado—, y el oro es la luz, lo protagonista. En una
         * lista de lienzos, el protagonista es el que estás mirando. Con los dos
         * en morado, "modo activo" y "documento abierto" se dirían con la misma
         * palabra, y son dos preguntas distintas.
         *
         * Va en barra + tipografía, no en fondo: un renglón bañado de oro sería
         * exactamente lo que el estándar prohíbe.
         */
        v.marca = esActiva ? tema.oro : nil
        v.arrastrable = p.id
        v.alArrastrar = { [weak self] id in self?.arrastrarPagina(id) }
        // Soltar sobre una pagina la mete en la carpeta de ESA pagina: es lo que
        // hacen Finder y Miro, y ahorra apuntar exactamente al renglon del titulo.
        if let f = p.folderId { v.destino = .carpeta(f) }
        v.enLote = marcadas.contains(p.id)
        /*
         * ⭐ MULTISELECCIÓN (26 ago 2026). Daniel: *"permíteme con control o
         * shift eliminar más de un componente a la vez seleccionándolo"*.
         *
         * ⌘ suma o quita uno; ⇧ marca el TRAMO desde el último; un clic seco
         * limpia el lote y abre el lienzo. Es la gramática de Finder, y no hace
         * falta enseñarla porque ya se sabe.
         */
        v.alPulsarConTeclas = { [weak self] mods in
            guard let self else { return }
            if mods.contains(.command) {
                if self.marcadas.contains(p.id) { self.marcadas.remove(p.id) }
                else { self.marcadas.insert(p.id); self.ancla = p.id }
                self.repintarLote()
            } else if mods.contains(.shift) {
                self.marcarTramo(hasta: p.id)
            } else {
                if !self.marcadas.isEmpty { self.marcadas = []; self.repintarLote() }
                self.ancla = p.id
                self.alElegir?(p.id)
            }
        }
        // Oro = dónde estás (la gramática del cromo): el lienzo abierto lo lleva.
        let ic = NSImageView(image: Estilo.iconoBisel(Icono.lienzo, tema, tinte: esActiva ? tema.oro : nil))
        ic.frame = NSRect(x: sangria + 10, y: 5, width: 17, height: 17)
        v.addSubview(ic)
        let t = NSTextField(labelWithString: p.nombre)
        t.font = Estilo.fuente(12.5, esActiva ? 700 : 500)
        t.textColor = esActiva ? tema.oro : tema.cuerpoTexto
        /*
         * ⚠️ EL NOMBRE SE TRUNCA POR EL FINAL, Y AHÍ ES DONDE SE DIFERENCIAN.
         *
         * Un crítico ciego lo cazó el 20 ago 2026: dos páginas distintas se
         * cortaban las dos a "Business OS · EL CAMI…" y quedaban indistinguibles
         * en la lista. La lista deja de servir para lo único que hace.
         *
         * Tres arreglos, y hacen falta los tres: se trunca por EL MEDIO (el
         * final es lo que las separa), el ancho se reserva SOLO cuando hay
         * contador que enseñar, y el nombre completo va en el globo — porque
         * ningún ancho alcanza para todos los nombres.
         */
        t.lineBreakMode = .byTruncatingMiddle
        t.toolTip = p.nombre
        t.frame = NSRect(x: sangria + 31, y: 5,
                         width: v.frame.width - sangria - 31 - 12, height: 17)
        v.addSubview(t)
        v.alRenombrar = { [weak self] in
            self?.editarNombre(en: v, x: sangria + 31, actual: p.nombre) { n in
                self?.alRenombrarPagina?(p.id, n)
            }
        }
        let menuPagina: () -> Void = { [weak self] in
            guard let self else { return }
            var filas: [(String, Bool, () -> Void)] = [
                ("Renombrar  ·  doble clic", false, { v.alRenombrar?() }),
            ]
            /*
             * MOVER se hace ARRASTRANDO (20 ago): el menu traia un "Mover a X"
             * por carpeta, asi que la accion mas comun era la mas larga de leer
             * y crecia con el arbol. Queda "Sacar", que es el gesto raro.
             *
             * ⚠️ Y sigue SIN ser "soltar en el vacio": en el rail web todo el
             * panel era zona de soltado y una pagina se salia de su carpeta sola
             * al arrastrarla un poco — asi se perdio una de vista. La diana es
             * el rotulo SIN CARPETA.
             */
            if p.folderId != nil {
                filas.append(("Sacar de la carpeta", false, { self.alMoverPagina?(p.id, nil) }))
            }
            // Con un LOTE marcado, el menú habla del lote: borrar uno cuando
            // tienes cinco marcados es lo contrario de lo que acabas de pedir.
            if self.marcadas.count > 1 && self.marcadas.contains(p.id) {
                filas.append(("Borrar \(self.marcadas.count) lienzos…", true, {
                    self.alBorrarPaginas?(Array(self.marcadas))
                }))
            } else {
                filas.append(("Borrar…", true, { self.alBorrarPagina?(p.id) }))
            }
            self.menu(filas)
        }
        v.alMenu = menuPagina
        return v
    }

    private func rotulo(_ s: String, cuenta: Int, destino: Destino = .raiz) -> NSView {
        let v = FilaPulsable(alto: 30, tema: tema)
        // SACAR de una carpeta tiene su propia diana, no "soltar en el vacio".
        // Dentro de un espacio la diana es su raíz, no "sin carpeta".
        v.destino = destino
        let t = NSTextField(labelWithString: s)
        t.attributedStringValue = NSAttributedString(string: s, attributes: [
            .font: Estilo.mono(9, 700), .foregroundColor: tema.pieTexto, .kern: 1.4])
        t.frame = NSRect(x: 11, y: 8, width: 160, height: 14)
        v.addSubview(t)
        _ = cuenta
        for (dy, col) in [(27.0, tema.bisel.borde), (26.0, tema.filoSurco)] {
            let linea = NSView(frame: NSRect(x: 8, y: dy, width: Double(v.frame.width) - 16, height: 1))
            linea.wantsLayer = true
            linea.layer?.backgroundColor = col.cgColor
            v.addSubview(linea)
        }
        return v
    }

    private func etiqueta(_ s: String, sangria: CGFloat) -> NSView {
        let v = caja(24)
        let t = NSTextField(labelWithString: s)
        t.font = Estilo.fuente(11.5, 500); t.textColor = tema.pieTexto
        t.frame = NSRect(x: sangria, y: 4, width: v.frame.width - sangria - 8, height: 16)
        v.addSubview(t)
        return v
    }
}

/// Una fila que responde al puntero. Sin hover, una lista larga no dice dónde
/// está el dedo y hay que apuntar a ciegas.
final class FilaPulsable: NSView {
    var alPulsar: (() -> Void)?
    /**
     * El menu de ESTA fila, el mismo del boton ⋯, tambien por clic derecho.
     *
     * ⚠️ Sin esto el evento subia por la cadena de respuesta hasta el lienzo,
     * que abria el menu del TABLERO —"Poner Nota aqui", "Pegar", "Encuadrar
     * todo"— encima del panel. Daniel: *"quise dar clic derecho para eliminar
     * alguno y no funcionó tan sólido como me gustaría"*. No es que no
     * funcionara: es que contestaba otra cosa, que es peor.
     */
    var alMenu: (() -> Void)?
    override func rightMouseDown(with e: NSEvent) { alMenu?() }

    /// Donde cae una pagina soltada sobre esta fila. `nil` = no acepta nada.
    var destino: Lateral.Destino?
    /// Que pagina ARRASTRA esta fila. `nil` = no se arrastra (rotulos).
    var arrastrable: String?
    /// Que CARPETA arrastra esta fila, si es una carpeta anidable.
    var arrastrableCarpeta: String?
    var alArrastrar: ((String) -> Void)?
    /// Resaltado de "sueltalo aqui". Se pinta distinto del hover para que no se
    /// confunda con "estas encima": uno informa, el otro promete una accion.
    func marcarSoltado(_ on: Bool) {
        layer?.borderWidth = on ? 2 : 0
        layer?.borderColor = on ? tema.acento.cgColor : nil
        layer?.backgroundColor = on ? Estilo.acentoSuave(tema).cgColor
                                    : (activa ? fondoActiva : .clear).cgColor
    }

    override func mouseDragged(with e: NSEvent) {
        guard let id = arrastrable ?? arrastrableCarpeta else { return }
        alArrastrar?(id)
    }
    let tema: Tema
    private let activa: Bool
    private var seguimiento: NSTrackingArea?

    /// El color del canto izquierdo. Oro = el lienzo abierto; nada = una fila más.
    var marca: NSColor? { didSet { needsDisplay = true } }

    /// El fondo de una fila seleccionada: neutro y muy tenue, porque quien dice
    /// "esta es" es la barra de color, no el relleno.
    private var fondoActiva: NSColor {
        tema.nombre == "oscuro" ? NSColor(white: 1, alpha: 0.055) : NSColor(white: 0, alpha: 0.045)
    }

    init(alto: CGFloat, tema: Tema, activa: Bool = false) {
        self.tema = tema; self.activa = activa
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: alto))
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: alto).isActive = true
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        if activa { layer?.backgroundColor = fondoActiva.cgColor }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ r: NSRect) {
        guard let m = marca, let c = NSGraphicsContext.current?.cgContext else { return }
        c.setFillColor(m.cgColor)
        let alto = bounds.height - 9
        c.addPath(CGPath(roundedRect: NSRect(x: 1, y: (bounds.height - alto) / 2, width: 3, height: alto),
                         cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
        c.fillPath()
    }

    /*
     * ⚠️ LAS ETIQUETAS SE TRAGAN EL CLIC.
     *
     * `NSTextField(labelWithString:)` parece texto muerto pero sigue siendo un
     * NSControl: recibe el `mouseDown` y NO lo pasa al padre. Medido el 20 ago
     * 2026: pulsar el header no abría nada porque el clic caía sobre el nombre
     * del lienzo, y el gesto se perdía ahí dentro sin que nada fallara.
     *
     * Devolviendo `self` desde `hitTest`, toda la tarjeta es una sola
     * superficie pulsable — que es lo que el ojo ya creía que era.
     */
    override func hitTest(_ punto: NSPoint) -> NSView? {
        bounds.contains(convert(punto, from: superview)) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let s = seguimiento { removeTrackingArea(s) }
        let s = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(s); seguimiento = s
    }
    override func mouseEntered(with e: NSEvent) {
        if !activa { layer?.backgroundColor = Estilo.hover(tema).cgColor }
    }
    override func mouseExited(with e: NSEvent) {
        layer?.backgroundColor = (activa ? fondoActiva : .clear).cgColor
    }
    /// Doble clic RENOMBRA; uno solo abre o pliega. Es la convencion de toda
    /// lista de documentos de macOS.
    var alRenombrar: (() -> Void)?
    /// El clic CON teclas. Existe aparte de `alPulsar` para que las filas que no
    /// saben de multiselección (carpetas, rótulos) sigan igual de simples.
    var alPulsarConTeclas: ((NSEvent.ModifierFlags) -> Void)?
    override func mouseDown(with e: NSEvent) {
        if e.clickCount >= 2, alRenombrar != nil { alRenombrar?(); return }
        if let f = alPulsarConTeclas { f(e.modifierFlags); return }
        alPulsar?()
    }
    /// Marcada dentro de una selección múltiple. Se pinta con el acento suave,
    /// no con el fondo de "activa": una es "estás aquí" y la otra "esta va en el
    /// lote", y confundirlas al borrar cinco cosas sale caro.
    var enLote = false {
        didSet {
            layer?.backgroundColor = enLote ? Estilo.acentoSuave(tema).cgColor
                                            : (activa ? fondoActiva : .clear).cgColor
        }
    }
}

/**
 * EL AGARRE del canto derecho del panel (24 ago 2026, pedido de Daniel).
 *
 * Un bucle modal de arrastre, igual que arrastrarPagina: el viaje empieza y
 * acaba aquí, no hay datos que cruzar entre apps. Reporta la x del puntero en
 * COORDENADAS DE VENTANA: el panel vive pegado a x=0, así que esa x ES el
 * ancho pedido — y no depende de la escala del cromo ni de conversiones.
 */
final class AgarreLateral: NSView {
    var alArrastrar: ((CGFloat) -> Void)?
    var tema: Tema = .claro { didSet { needsDisplay = true } }
    private var dentro = false { didSet { needsDisplay = true } }
    private var arrastrando = false { didSet { needsDisplay = true } }
    private var seguimiento: NSTrackingArea?

    /// El asa se enseña SOLO bajo la mano (Daniel, 24 ago: la barrita fija
    /// "no muy elegante" — fuera). En reposo el canto queda limpio; al entrar
    /// el cursor aparece la barrita morada + el cursor de resize, que juntos
    /// son toda la señal que hace falta.
    override func draw(_ r: NSRect) {
        guard dentro || arrastrando,
              let c = NSGraphicsContext.current?.cgContext else { return }
        let alto: CGFloat = 44
        let asa = NSRect(x: bounds.midX - 1.5, y: (bounds.height - alto) / 2, width: 3, height: alto)
        c.addPath(CGPath(roundedRect: asa, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
        c.setFillColor(tema.acento.cgColor)
        c.fillPath()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let s = seguimiento { removeTrackingArea(s) }
        let s = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self)
        addTrackingArea(s); seguimiento = s
    }
    override func mouseEntered(with e: NSEvent) { dentro = true; NSCursor.resizeLeftRight.set() }
    override func mouseExited(with e: NSEvent) { dentro = false; NSCursor.arrow.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

    override func mouseDown(with e: NSEvent) {
        guard let w = window else { return }
        arrastrando = true
        NSCursor.resizeLeftRight.push()
        defer { NSCursor.pop(); arrastrando = false }
        while let ev = w.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if ev.type == .leftMouseUp { break }
            alArrastrar?(ev.locationInWindow.x)
        }
    }
}
