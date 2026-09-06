import AppKit

/**
 * sfmap — el lienzo de sistemas, NATIVO.
 *
 * El reparto: la SUPERFICIE es Swift (aquí vive el frame) y el COMPILADOR se
 * queda en Node, a un localhost de distancia. Reescribir el layout de grafos y
 * la medición de fuentes en Swift serían meses para ganar en el único eje que
 * no aprieta: compilar un diagrama cuesta 110 ms y pasa una vez por diagrama;
 * mover el ratón pasa 120 veces por segundo.
 *
 * ⚠️ NO HAY MODO ENVOLTORIO. Lo hubo —un WKWebView que cargaba el lienzo web— y
 * se borró al alcanzar paridad, que es lo que se pactó. Un WKWebView no gana
 * latencia ni arraiga el hábito, y son las dos razones por las que esto es una
 * app aparte y no una pestaña.
 */
final class Delegado: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var ventana: NSWindow!
    let lienzo = Lienzo(frame: NSRect(x: 0, y: 0, width: 1280, height: 820))
    /// La franja de cromo de arriba: el MISMO color que el panel, para que las
    /// dos lean como una sola superficie que rodea al tablero.
    let banda = FranjaTitulo()
    let filoBanda = NSView()
    let header = HeaderPulsable()
    let lateral = Lateral(frame: .zero)
    /// Arriba a la derecha, como los ajustes de cualquier ventana de macOS.
    let engrane = BotonPlano(icono: Icono.engrane, ancho: 30, alto: 30)
    let rail = RailHerramientas(frame: .zero)
    let barra = BarraContextual(frame: .zero)
    let estado = BarraEstado(frame: .zero)
    let mapa = Minimapa()
    var lateralAbierta = false
    /*
     * EL PANEL DEL DOCUMENTO vive a la DERECHA y flota como el de lienzos, con
     * el mismo convenio: el tablero sigue entero debajo. Se abre desde un nodo
     * con `doc:` y es lo que convierte al mapa en índice de la operación.
     */
    let panelDoc = PanelDoc(frame: .zero)
    var docAbierto = false
    var anchoDoc: CGFloat = {
        let g = UserDefaults.standard.double(forKey: "sfmap.anchoDoc")
        return g > 0 ? min(760, max(320, CGFloat(g))) : 470
    }()
    var hoja: NSView?
    var regiones: [Compilador.Region] = []

    /*
     * EL ZOOM DEL SISTEMA (24 ago 2026, pedido de Daniel). El lienzo tiene su
     * zoom; el CROMO tiene el suyo: pellizcar con el puntero FUERA del lienzo
     * escala rail, panel, barra de estado y minimapa. Se implementa con el
     * truco de AppKit de frame≠bounds: cada pieza se maqueta a su tamaño
     * NATURAL (bounds) y se muestra al escalado (frame) — el hit-testing viaja
     * por la transformación de bounds, así que los clics siguen cayendo bien.
     */
    var escalaUI: CGFloat = {
        let g = UserDefaults.standard.double(forKey: "escalaUI")
        return g > 0 ? Estilo.clampEscalaUI(CGFloat(g)) : 1
    }()
    /// El ancho LÓGICO del panel (el visual es ancho × escala). Arrastrable.
    var anchoLateral: CGFloat = {
        let g = UserDefaults.standard.double(forKey: "anchoLateral")
        return g > 0 ? Estilo.clampAnchoLateral(CGFloat(g)) : 300
    }()
    /// Tamaños naturales, capturados ANTES del primer escalado. Lazy a
    /// propósito: el primer acceso ocurre en el primer `colocar`, cuando los
    /// frames todavía son los de fábrica.
    lazy var railNatural = rail.frame.size
    lazy var mapaNatural = mapa.frame.size
    lazy var estadoAltoNatural = estado.frame.height

    var paginas: [ResumenPagina] = []
    var carpetas: [Carpeta] = []
    var actual: Nube.Pagina?
    var guardando = false
    var sucio = false
    /// Sube con CADA edición. Es el sensor de "¿lo que salió sigue siendo lo
    /// que hay?" — ver `guardar()`.
    var sello: UInt64 = 0
    /// Hubo cambios mientras un guardado volaba: repetir al aterrizar.
    var repetirGuardado = false
    /// La puerta agéntica (Puente.swift): elemento a centrar tras abrir,
    /// última selección escrita y firma del panel para no repintar en vano.
    var centrarPendiente: String?
    var seleccionEscrita: Set<String>? = nil
    var firmaPanel = ""

    ///
    /// `--tema claro|oscuro` lo fija SIN escribirlo en las preferencias: una
    /// verificación que deja el tema cambiado para la próxima vez no es una
    /// verificación, es un efecto secundario.
    var temaManual: String? = {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--tema"), i + 1 < a.count { return a[i + 1] }
        return UserDefaults.standard.string(forKey: "sfmap.tema")
    }()

    func applicationDidFinishLaunching(_ n: Notification) {
        traza("arranque · \(ProcessInfo.processInfo.processName) pid \(ProcessInfo.processInfo.processIdentifier)")
        Fuentes.registrar()
        if !Fuentes.faltantes.isEmpty { traza("⚠︎ fuentes que no cargaron: \(Fuentes.faltantes)") }
        Nube.cargarConfig()
        Compilador.cargarToken()

        ventana = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        ventana.title = "sfmap"
        ventana.titlebarAppearsTransparent = true
        ventana.titleVisibility = .hidden
        ventana.delegate = self
        /*
         * ARRANCA SIEMPRE A PANTALLA COMPLETA.
         *
         * Daniel: *"si le doy doble clic se expande y se adapta a la pantalla;
         * asegúrate que siempre que lo abramos esté a tamaño completo"*. Un
         * lienzo infinito en una ventana de 1280 es un lienzo mirado por una
         * mirilla, y llegar cada mañana a estirarla con el ratón es una cuota
         * que se paga todos los días por una decisión que nunca cambia.
         *
         * El autoguardado SE QUEDA, pero solo por el MONITOR: restaura el marco,
         * de ahí se lee en qué pantalla quedó, y encima se pone su `visibleFrame`
         * —el área útil, sin barra de menú ni Dock, que es exactamente lo que
         * hace el doble clic en la barra de título—. Recordar la pantalla sí
         * sirve; recordar un tamaño que él siempre corrige, no.
         */
        ventana.setFrameAutosaveName("sfmap.ventana")
        if let pantalla = ventana.screen ?? NSScreen.main ?? NSScreen.screens.first {
            ventana.setFrame(pantalla.visibleFrame, display: true)
        } else {
            ventana.center()
        }

        let raiz = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 820))
        raiz.autoresizingMask = [.width, .height]
        lienzo.frame = raiz.bounds
        lienzo.autoresizingMask = [.width, .height]
        raiz.addSubview(lienzo)
        montarCromo(en: raiz)
        ventana.contentView = raiz
        /*
         * ⚠️ MAQUETAR CON EL MARCO REAL, ANTES DE MOSTRAR.
         *
         * `montarCromo` acaba llamando `colocar`, pero con el BORRADOR de
         * 1280×820: la ventana ya adoptó su marco de pantalla completa tres
         * líneas arriba, y al asignar el contentView AppKit estira `raiz` SIN
         * disparar `windowDidResize` — el marco de la ventana no cambió. Los
         * hijos no tienen máscara de autoajuste, así que el header, el rail y
         * el minimapa se quedaban con las medidas de la ventana chica y el
         * primer segundo se veía el cromo esparcido a mitad de pantalla, hasta
         * que `abrir()` terminaba de cargar por red y llamaba `colocar` de
         * nuevo. El arreglo no es animar el salto: es que no haya salto.
         */
        colocar(raiz)
        // El sensor de lo de arriba: si el header no nace pegado al techo de la
        // ventana REAL, el cromo volvió a maquetarse con el borrador.
        traza("cromo maquetado · raiz \(Int(raiz.bounds.width))×\(Int(raiz.bounds.height))"
              + " · header y=\(Int(header.frame.minY)) de \(Int(raiz.bounds.height - HeaderPulsable.ALTO))"
              + " · rail x=\(Int(rail.frame.minX)) y=\(Int(rail.frame.minY))"
              + " · estado x=\(Int(estado.frame.minX))")
        // La flecha, SIEMPRE, en cada arranque: la herramienta no se recuerda
        // entre sesiones a proposito. Abrir la app y encontrarte el lápiz
        // puesto de anoche es el peor primer clic posible.
        lienzo.herramienta = .seleccionar
        rail.activa = .seleccionar
        ventana.makeFirstResponder(lienzo)
        ventana.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        aplicarTema()
        centrarSemaforos()
        // AppKit los devuelve a su sitio en cada uno de estos: la fila se
        // descuadraba sola al redimensionar o al volver de pantalla completa.
        for n in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification,
                  NSWindow.didEndLiveResizeNotification, NSWindow.didExitFullScreenNotification] {
            NotificationCenter.default.addObserver(
                forName: n, object: ventana, queue: .main) { [weak self] _ in self?.centrarSemaforos() }
        }
        DistributedNotificationCenter.default.addObserver(
            self, selector: #selector(temaCambio),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
        montarMenu()

        /*
         * EL ZOOM FUERA DEL LIENZO ESCALA EL CROMO (24 ago 2026).
         * Sobre el lienzo, el gesto sigue siendo el zoom del documento; sobre
         * el cromo (banda, header, panel, rail, barra, minimapa, estado)
         * escala la interfaz — pellizco Y ⌘/⌃+rueda, los dos caminos del zoom.
         *
         * ⚠️ Por FRAMES, no por hitTest. La primera versión preguntaba
         * `hitTest` y el lienzo cubre la ventana ENTERA por debajo del cromo:
         * cualquier vista de cromo que deje pasar el evento (la banda lo hace,
         * para arrastrar la ventana) caía al lienzo y el canvas zoomeaba con
         * el puntero sobre el header. El criterio correcto es geométrico:
         * ¿el puntero está sobre el rectángulo de alguna pieza de cromo?
         */
        NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel]) { [weak self] ev in
            guard let self, ev.window === self.ventana else { return ev }
            /*
             * ⚠️ EL DIAL DE LA TABLETA TAMBIÉN ES ZOOM — y fue el agujero.
             * La primera versión solo cazaba pellizco y ⌘/⌃+rueda; el dial de
             * la Kamvas entra como rueda sintética SIN modificadores, así que
             * con el puntero sobre el header seguía zoomeando el canvas (la
             * banda deja pasar eventos para arrastrar la ventana, y debajo de
             * TODO está el lienzo). Mismos tres caminos que reconoce el
             * lienzo: pellizco · ⌘/⌃+rueda · dial.
             */
            let esZoomDeRueda = ev.type == .scrollWheel
                && (ev.modifierFlags.contains(.command) || ev.modifierFlags.contains(.control)
                    || Lienzo.esDialDeTableta(ev))
            guard ev.type == .magnify || esZoomDeRueda else { return ev }
            guard self.punteroSobreCromo(ev.locationInWindow) else { return ev }
            let factor: CGFloat = ev.type == .magnify
                ? 1 + ev.magnification
                : exp(max(-50, min(50, ev.scrollingDeltaY)) * 0.005)
            self.fijarEscalaUI(self.escalaUI * factor)
            return nil
        }

        // El mismo criterio para el TECLADO: ⌘+/⌘− con el puntero sobre cromo
        // escala la UI. El lienzo pregunta por este gancho antes de zoomear.
        Lienzo.zoomUIFueraDelLienzo = { [weak self] factor in
            guard let self, let ventana = self.ventana else { return false }
            let loc = ventana.mouseLocationOutsideOfEventStream
            guard self.punteroSobreCromo(loc) else { return false }
            self.fijarEscalaUI(self.escalaUI * factor)
            return true
        }

        traza("ventana lista · tema \(lienzo.tema.nombre)\(Nube.soloLectura ? " · SOLO LECTURA" : "")")
        if Nube.soloLectura { decir("") }
        if CommandLine.arguments.contains("--lateral") { alternarLateral() }
        if let p = Nube.problema {
            decir("⚠︎ \(p)", error: true)
        } else {
            Task { await self.cargarLista() }
        }
        // El sondeo de sincronía. Ver `Nube.version` sobre por qué es un sondeo.
        Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.mirarSiCambio(); self?.mirarLista()
        }
        // La puerta agéntica late a 1s: órdenes de Levy y selección de Daniel.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.latidoPuente() }
        /*
         * EL CRONISTA — el ciclo que mantiene vivos los widgets del día.
         *
         * Solo repinta cuando el CONTENIDO cambió, no en cada vuelta: el lienzo
         * se repinta entero, y forzar un frame cada minuto para confirmar que
         * todo sigue igual es trabajo por nada mientras Daniel arrastra.
         */
        Cronista.compartido.alCambiar = { [weak self] in self?.lienzo.needsDisplay = true }
        Cronista.compartido.encender()

        // Escena de verificación, si se pidió. Va DESPUÉS de la carga para que
        // parta de un estado real, no de una ventana a medio montar.
        if let esc = Escenas.nombrePedido() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { Escenas.correr(esc, self) }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: cromo
    // ════════════════════════════════════════════════════════════════════════

    private func montarCromo(en raiz: NSView) {
        header.alPulsar = { [weak self] in self?.alternarLateral() }
        // La banda ya no necesita capa: se pinta en `draw` como el resto del cromo.
        filoBanda.wantsLayer = true
        raiz.addSubview(banda)
        raiz.addSubview(filoBanda)
        raiz.addSubview(header)

        panelDoc.isHidden = true
        panelDoc.alCerrar = { [weak self] in self?.cerrarDoc() }
        panelDoc.alAbrirLiga = { [weak self] liga in self?.irA(liga) }
        raiz.addSubview(panelDoc)

        /*
         * ELEGIR UN LIENZO NO CIERRA EL PANEL.
         *
         * Lo cerraba en cada clic, y con eso convertia el indice en un menu de
         * un solo uso: para pasar del lienzo 03 al 04 habia que volver a
         * abrirlo. Daniel, 26 ago: *"luego de seleccionar una page no escondas
         * el sidebar, dejalo abierto a menos que yo lo haga"*.
         *
         * El panel se abre y se cierra con SU gesto (el atajo del menu o el
         * boton de la cabecera) y con ninguno mas. Una superficie que se
         * esconde sola decide por ti; una que espera a que la cierres, no.
         */
        lateral.alElegir = { [weak self] id in
            guard let self else { return }
            // El cursor sigue al raton: si eliges un lienzo con el clic, las
            // flechas tienen que seguir desde AHI. Sin esto, cursor y lienzo
            // abierto se separan en silencio y la siguiente flecha te lleva a
            // un sitio que no tiene que ver con lo que estas mirando.
            self.lateral.foco = self.paginas.first { $0.id == id }?.folderId
            Task { await self.abrir(id) }
        }
        /*
         * LA CARPETA ABIERTA ES LA DEL LIENZO QUE ESTAS MIRANDO.
         *
         * Se podria haber tomado la carpeta DESPLEGADA en el panel, pero puede
         * haber varias desplegadas a la vez y ninguna es mas "la abierta" que
         * otra: el atajo tendria que adivinar. El lienzo que tienes delante, en
         * cambio, es uno solo y siempre — y es el que da el contexto que la
         * mano cree tener cuando pulsa un numero.
         *
         * El ORDEN es el mismo que enseña el panel (`Lateral.porNombre`), y se
         * pide prestado en vez de repetirlo aqui: dos criterios de orden serian
         * dos listas distintas, y el `3` llevaria a un sitio que en la lista no
         * es el cuarto. Un atajo que no coincide con lo que se ve es peor que
         * no tener atajo.
         */
        /*
         * EL CURSOR MANDA, NO EL LIENZO ABIERTO.
         *
         * Todos los atajos de navegacion parten de la carpeta donde esta el
         * CURSOR (`lateral.foco`), no de la del lienzo que se ve. Tienen que
         * ser cosas distintas: si mandara el lienzo abierto, mover el cursor
         * con → a otra carpeta y pulsar ↓ te devolveria a la carpeta de la que
         * saliste — o sea, la flecha derecha no serviria para nada.
         *
         * Sin cursor todavia (recien abierta la app), se usa la carpeta del
         * lienzo abierto: es de donde la mano cree que parte.
         */
        func carpetaCursor() -> String? {
            self.lateral.foco ?? self.paginas.first { $0.id == self.actual?.id }?.folderId
        }

        lienzo.alCarpetaVecina = { [weak self] paso in
            guard let self,
                  let id = Lateral.carpetaVecina(self.carpetas, de: carpetaCursor(), paso: paso)
            else { return }
            // El panel se enseña y la carpeta se despliega: mover el cursor a
            // una carpeta plegada dejaria la tecla sin nada observable, que es
            // el mismo fallo mudo de siempre.
            if !self.lateralAbierta { self.alternarLateralMenu() }
            for vieja in Lateral.aPlegar(self.carpetas, saliendoDe: carpetaCursor(), entrandoA: id) {
                self.lateral.plegar(vieja)
            }
            self.lateral.foco = id
            self.lateral.abrir(id)
        }

        lienzo.alIrAPagina = { [weak self] n in
            guard let self else { return }
            let v = Lateral.lienzosDe(self.paginas, carpeta: carpetaCursor())
            guard v.indices.contains(n), v[n].id != self.actual?.id else { return }
            Task { await self.abrir(v[n].id) }
        }

        lienzo.alAlternarCarpeta = { [weak self] in
            guard let self, let carpeta = carpetaCursor() else { return }
            // Si el panel esta escondido se enseña ANTES de plegar nada: una
            // tecla que cambia algo invisible se siente rota, y a la segunda
            // pulsacion ya no sabes en que estado lo dejaste.
            if !self.lateralAbierta { self.alternarLateralMenu() }
            self.lateral.alternarExpansion(carpeta)
        }

        lienzo.alPaginaVecina = { [weak self] paso in
            guard let self else { return }
            let v = Lateral.lienzosDe(self.paginas, carpeta: carpetaCursor())
            guard !v.isEmpty else { return }
            /*
             * LA PRIMERA BAJADA ENTRA; las siguientes recorren.
             *
             * Si el lienzo abierto NO es de la carpeta del cursor, es que
             * acabas de llegar aqui con → y todavia no has entrado: ↓ abre el
             * PRIMERO. Es literalmente "no cambia de panel hasta que muevo
             * hacia abajo". Solo cuando ya estas dentro, ↓ y ↑ pasan al vecino.
             */
            guard let i = v.firstIndex(where: { $0.id == self.actual?.id }) else {
                Task { await self.abrir(paso > 0 ? v[0].id : v[v.count - 1].id) }
                return
            }
            let j = i + paso
            guard v.indices.contains(j) else { return }
            Task { await self.abrir(v[j].id) }
        }

        lateral.alCrearPagina = { [weak self] carpeta in self?.crearPagina(en: carpeta) }
        lateral.alCrearCarpeta = { [weak self] madre in self?.crearCarpeta(en: madre) }
        lateral.alAnidarCarpeta = { [weak self] id, madre in self?.anidarCarpeta(id, madre) }
        lateral.alRenombrarPagina = { [weak self] id, n in self?.renombrarPagina(id, n) }
        lateral.alBorrarPagina = { [weak self] id in self?.borrarPagina(id) }
        lateral.alBorrarPaginas = { [weak self] ids in self?.borrarPaginas(ids) }
        lateral.alMoverPagina = { [weak self] id, c in self?.moverPagina(id, c) }
        lateral.alRenombrarCarpeta = { [weak self] id, n in self?.renombrarCarpeta(id, n) }
        lateral.alBorrarCarpeta = { [weak self] id in self?.borrarCarpeta(id) }
        lateral.isHidden = true
        lateral.alCambiarAncho = { [weak self] xVentana in
            guard let self else { return }
            // El panel vive en x=0: la x del puntero ES el ancho visual pedido.
            self.anchoLateral = Estilo.clampAnchoLateral(xVentana / self.escalaUI)
            UserDefaults.standard.set(Double(self.anchoLateral), forKey: "anchoLateral")
            if let raiz = self.ventana?.contentView { self.colocar(raiz) }
        }
        raiz.addSubview(lateral)

        engrane.globo = "Atajos y comandos"
        engrane.alPulsar = { [weak self] in self?.mostrarAtajos() }
        raiz.addSubview(engrane)

        rail.alElegir = { [weak self] h in self?.lienzo.herramienta = h; self?.ventana.makeFirstResponder(self?.lienzo) }
        rail.alCambiarTinta = { [weak self] t in self?.lienzo.tinta = t }
        rail.alCambiarGoma = { [weak self] g in self?.lienzo.goma = g }
        raiz.addSubview(rail)

        // La barra crece cuando llega el boton del compilador (por red, segundos
        // despues de abrir). Ya no se recoloca sola —eso era lo que la estiraba—
        // asi que avisa, y la recoloca quien coloca a todos.
        estado.alRedimensionar = { [weak self] in
            guard let self, let raiz = self.ventana.contentView else { return }
            self.colocar(raiz)
        }
        barra.isHidden = true
        barra.alCambiar = { [weak self] patch, solo in self?.aplicarPatch(patch, solo) }
        barra.alColor = { [weak self] campos in
            self?.editarSeleccion("color") { $0.ponerColor(campos) }
        }
        barra.alTrazo = { [weak self] estilo, grosor, radio in
            self?.editarSeleccion("trazo") { $0.ponerTrazo(estilo: estilo, grosor: grosor, radio: radio) }
        }
        barra.alTipografia = { [weak self] t in
            self?.editarSeleccion("tipografía") { $0.aplicarTipografia(t) }
        }
        barra.alAbrirGesto = { [weak self] in self?.lienzo.doc.abrirGesto() }
        barra.alCerrarGesto = { [weak self] e in self?.lienzo.doc.cerrarGesto(e) }
        barra.alBorrar = { [weak self] in self?.lienzo.doc.borrarSeleccion(); self?.refrescarBarra() }
        barra.alDuplicar = { [weak self] in
            guard let s = self else { return }
            s.lienzo.doc.duplicar(s.lienzo.doc.seleccion); s.refrescarBarra()
        }
        barra.alFrente = { [weak self] in self?.lienzo.doc.alFrente() }
        barra.alFondo = { [weak self] in self?.lienzo.doc.alFondo() }
        barra.alAdelante = { [weak self] in self?.lienzo.doc.unaAdelante() }
        barra.alAtras = { [weak self] in self?.lienzo.doc.unaAtras() }
        barra.alRecortar = { [weak self] in self?.lienzo.iniciarRecorte() }
        barra.alAgrupar = { [weak self] in self?.lienzo.doc.agrupar(); self?.refrescarBarra() }
        barra.alDesagrupar = { [weak self] in self?.lienzo.doc.desagrupar(); self?.refrescarBarra() }
        barra.alAnclaje = { [weak self] fijar in self?.fijarAnclaje(fijar) }
        raiz.addSubview(barra)

        estado.alZoom = { [weak self] f in
            guard let l = self?.lienzo else { return }
            l.zoomEn(punto: NSPoint(x: l.bounds.midX, y: l.bounds.midY), factor: f)
        }
        estado.alZoomA = { [weak self] z in self?.lienzo.zoomA(z) }
        estado.alEncuadrar = { [weak self] in self?.lienzo.encuadrar() }
        estado.alFondo = { [weak self] f in self?.lienzo.fondo = f; self?.estado.fondo = f }
        estado.alTema = { [weak self] in self?.alternarTema() }
        lienzo.alEnseñarGrupo = { [weak self] h in self?.rail.abrirGrupoDe(h) }
        lienzo.alTema = { [weak self] in self?.alternarTema() }
        estado.alDeshacer = { [weak self] in self?.lienzo.doc.deshacer(); self?.refrescarBarra() }
        estado.alRehacer = { [weak self] in self?.lienzo.doc.rehacer(); self?.refrescarBarra() }
        estado.alExportar = { [weak self] sel in self?.exportar(soloSeleccion: sel) }
        raiz.addSubview(estado)

        mapa.alIrA = { [weak self] p in
            guard let l = self?.lienzo else { return }
            l.camara = Camara(x: p.x, y: p.y, zoom: l.camara.zoom)
        }
        raiz.addSubview(mapa)

        lienzo.alCambiar = { [weak self] persistente in
            guard let s = self else { return }
            if persistente { s.marcarSucio() }
            s.mapa.elementos = s.lienzo.doc.elementos
            s.mapa.seleccion = s.lienzo.doc.seleccion
            s.refrescarBotones()
        }
        lienzo.alSeleccionar = { [weak self] in self?.refrescarBarra() }
        lienzo.alMoverCamara = { [weak self] z in
            guard let s = self else { return }
            s.estado.zoom = z
            s.mapa.camara = s.lienzo.camara
            s.mapa.vista = s.lienzo.bounds.size
            s.refrescarBarra(soloPosicion: true)
            s.recordarCamara()
        }
        // El rail sigue a la herramienta, venga de donde venga (rail, tecla, o
        // Escape). Antes la app EMPUJABA el rail y la tecla lo dejaba desfasado.
        lienzo.alCambiarHerramienta = { [weak self] in
            guard let s = self else { return }
            s.rail.activa = s.lienzo.herramienta
        }
        lienzo.alCambiarGrosor = { [weak self] g in
            // ⚠️ EL RAIL TIENE QUE ENTERARSE, igual que la goma dos lineas mas
            // abajo. Sin esto el panel enseña el grosor de ANTES: la escalera
            // estaba bien y el dial la recorria, pero nadie se lo contaba a la
            // fila de peldaños — por eso seguia sin verse mover.
            self?.rail.tinta.grosor = g
            self?.decir("grosor · \(String(format: "%.1f", g))")
        }
        // El dial mueve el grosor de la goma; el panel del rail tiene que
        // seguirlo. Sin esto, abrir el panel después de girar enseña el tamaño
        // de antes y la mano deja de creerle al panel.
        lienzo.alCambiarGoma = { [weak self] g in self?.rail.goma = g }

        /*
         * EL DIAL DE LA TABLETA LLEGA AUNQUE EL FOCO NO ESTÉ EN EL LIENZO.
         *
         * La rueda inferior de la Huion manda `[`/`]` (o `,`/`.`), y el lienzo
         * ya las entiende — pero solo cuando ES el primer respondedor. Basta
         * haber clicado un lienzo en el panel lateral para que el dial deje de
         * hacer nada, y eso es indistinguible de "el dial no funciona": la mano
         * gira, no pasa nada, y se deja de usar el dial.
         *
         * Un monitor LOCAL las coge antes de que se repartan. Dos guardas y las
         * dos hacen falta: con ⌘ son atajos de menú de verdad, y mientras se
         * ESCRIBE una coma es una coma —tragarse la tecla dentro del buscador
         * de lienzos sería peor que no tener dial.
         */
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let s = self, !e.modifierFlags.contains(.command) else { return e }
            let k = e.charactersIgnoringModifiers ?? ""
            // Con la sonda puesta se escribe TODA tecla que no lleve ⌘. Si la
            // rueda de la tableta esta mandando algo distinto de lo que
            // creemos, se ve aqui en una linea en vez de discutirlo a ciegas.
            if ProcessInfo.processInfo.environment["SFMAP_SONDA_DIAL"] != nil {
                FileHandle.standardError.write(Data(
                    "TECLA '\(k)' code=\(e.keyCode) mods=\(e.modifierFlags.rawValue)\n".utf8))
            }
            guard ["[", "]", ",", "."].contains(k) else { return e }
            let foco = s.ventana.firstResponder
            if foco is NSTextView || foco is NSTextField { return e }
            s.lienzo.ajustarGrosor(k == "]" || k == "." ? 1 : -1)
            return nil
        }

        /*
         * LA GOMA SE RECUERDA entre sesiones. Es un ajuste de MANO, no de
         * documento: quien la dejó gorda para limpiar una pizarra la quiere
         * gorda al volver, igual que un lápiz físico no se afila solo.
         */
        var g = Goma()
        let guardado = UserDefaults.standard.double(forKey: "sfmap.goma.grosor")
        if guardado > 0 { g.grosor = guardado }
        if let a = UserDefaults.standard.string(forKey: "sfmap.goma.alcance"),
           let alcance = Goma.Alcance(rawValue: a) { g.alcance = alcance }
        lienzo.goma = g
        rail.goma = g
        lienzo.alTocarLienzo = { [weak self] in
            self?.rail.cerrarDesplegable(); self?.estado.cerrarPanel()
        }
        lienzo.alEscapar = { [weak self] in
            self?.barra.cerrarPanel(); self?.estado.cerrarPanel(); self?.rail.cerrarDesplegable()
        }
        lienzo.alPedirMenu = { [weak self] p, el in self?.menuContextual(p, el) }
        lienzo.alAbrirEnlace = { [weak self] liga in self?.irA(liga) }
        lienzo.alCerrarTarea = { [weak self] id in
            Task { @MainActor in
                if let err = await LecturaTodoist.cerrar(id) {
                    // Si no se pudo, se DESHACE la palomita: dejarla puesta
                    // sería el panel afirmando algo que no pasó.
                    Pintor.cerradas.remove(id)
                    self?.lienzo.needsDisplay = true
                    self?.decir("⚠︎ no se pudo cerrar la tarea · \(err)", error: true)
                } else {
                    self?.decir("tarea cerrada ✓")
                    Cronista.compartido.refrescarTodo()
                }
            }
        }
        colocar(raiz)
    }

    /**
     * Coloca el cromo. A mano y no con autolayout: son seis rectángulos que
     * dependen del tamaño de la ventana y de si la barra está abierta.
     * Autolayout aquí serían veinte restricciones para expresar cuatro sumas.
     */
    private func colocar(_ raiz: NSView) {
        let a = Estilo.aire
        let esc = escalaUI
        // El ancho VISUAL del panel: el lógico (arrastrable) por la escala UI.
        let anchoPanel = anchoLateral * esc
        /*
         * ⚠️ LOS SEMÁFOROS SON EL ANCLA, no un obstáculo.
         *
         * La ventana es `fullSizeContentView` para que el lienzo llegue al borde,
         * y los tres botones de macOS siguen flotando sobre el contenido. La
         * primera versión los RODEABA: bajaba el header 14 px y lo corría 78 a la
         * derecha, dejando dos piezas de cromo en dos líneas distintas.
         *
         * Daniel, con sfcal delante: *"nota cómo el header está alineado con los
         * iconos de semáforo, nota cómo todo luce simétrico"*. Ahora la fila de
         * título es UNA, con su centro en el de los botones del sistema, y lo que
         * cambia con el panel es dónde EMPIEZA — no a qué altura vive.
         */
        let semaforos: CGFloat = 78
        // La fila del título TAMBIÉN escala (pedido de Daniel, 24 ago: "adaptar
        // TODOS estos componentes fuera del canvas": el título, las carpetas,
        // los botones — todo el cromo, no solo el rail).
        let filaAlto = HeaderPulsable.ALTO * esc
        let filaY = raiz.bounds.height - filaAlto

        /*
         * LA FRANJA cubre TODO el ancho; su filo empieza donde acaba el panel.
         *
         * Si el filo cruzara tambien por encima del panel, partiria en dos la
         * unica pieza que el color esta juntando. Asi la linea aparece solo
         * donde de verdad separa algo: entre el cromo y el tablero.
         */
        banda.frame = NSRect(x: 0, y: filaY, width: raiz.bounds.width, height: filaAlto)
        let xFilo = lateralAbierta ? anchoPanel : 0
        filoBanda.frame = NSRect(x: xFilo, y: filaY - 1, width: raiz.bounds.width - xFilo, height: 1)

        // El panel va a ras: de arriba abajo y pegado al borde, como en sfcal.
        // Flotando dejaba de leerse como parte de la ventana. Se maqueta a su
        // ancho LÓGICO (bounds) y se muestra al escalado (frame).
        let altoPanel = raiz.bounds.height - filaAlto
        lateral.frame = NSRect(x: 0, y: 0, width: anchoPanel, height: altoPanel)
        lateral.bounds = NSRect(x: 0, y: 0, width: anchoLateral, height: altoPanel / esc)
        /*
         * EL HEADER NO SE MUEVE. Abierto o cerrado, vive junto a los semáforos.
         *
         * Antes se corría 300 px a la derecha al abrir el panel, y el boton que
         * lo abre viajaba con el: para cerrarlo habia que ir a buscarlo donde
         * NO estaba la mano. Daniel: *"que el nombre y el botón queden en la
         * posición de sfmap, en el mismo lugar del ratón donde se esconde"*. Un
         * interruptor que cambia de sitio segun su propio estado obliga a mirar
         * antes de cada clic.
         *
         * Y por eso muere la identidad de la app: ese hueco es ahora del
         * documento. El nombre de la app ya esta en el Dock, en el menu y en la
         * manzana; repetirlo dentro costaba la mejor posicion de la ventana.
         */
        let x = semaforos
        let anchoHeader = min(header.anchoIdeal * esc, raiz.bounds.width - x - 20)
        header.frame = NSRect(x: x, y: filaY, width: anchoHeader, height: filaAlto)
        header.bounds = NSRect(x: 0, y: 0, width: anchoHeader / esc, height: HeaderPulsable.ALTO)

        engrane.frame = NSRect(x: raiz.bounds.width - 30 * esc - Estilo.aire,
                               y: filaY + (filaAlto - 30 * esc) / 2,
                               width: 30 * esc, height: 30 * esc)
        engrane.bounds = NSRect(x: 0, y: 0, width: 30, height: 30)
        // El desplegable se ancla al rail al abrirse; si el rail se mueve, el
        // panel se queda donde estaba y aparece huerfano en mitad del lienzo.
        // Pero CERRARLO era peor que el mal que curaba: recolocar el cromo pasa
        // cada vez que la barra de estado cambia de ancho —y cambia al escribir
        // el grosor—, asi que girar el dial cerraba el panel del lapiz. Se
        // recoloca al final, cuando el rail ya esta en su sitio.
        let panelAbierto = rail.grupoAbierto != nil
        rail.frame.size = NSSize(width: railNatural.width * esc, height: railNatural.height * esc)
        rail.bounds = NSRect(origin: .zero, size: railNatural)
        rail.frame.origin = NSPoint(x: (lateralAbierta ? anchoPanel : 0) + a,
                                    y: (raiz.bounds.height - rail.frame.height) / 2)
        // Ya con el rail en su sitio: el panel vuelve a anclarse a el.
        if panelAbierto { rail.recolocarDesplegable() }
        mapa.frame.size = NSSize(width: mapaNatural.width * esc, height: mapaNatural.height * esc)
        mapa.bounds = NSRect(origin: .zero, size: mapaNatural)
        mapa.frame.origin = NSPoint(x: (lateralAbierta ? anchoPanel : 0) + a, y: a)
        mapa.isHidden = lateralAbierta && raiz.bounds.width < 1100
        mapa.vista = lienzo.bounds.size
        /*
         * ⚠️ LA BARRA DE ESTADO NO SE RECOLOCABA NUNCA, y por eso se salía.
         *
         * Se anclaba sola dentro de su `layout()`, y `layout()` solo corre
         * cuando algo la marca sucia. Su máscara de autoajuste es la de por
         * defecto, así que al crecer la ventana —o al abrirse a pantalla
         * completa— AppKit ni la mueve ni le pide maquetarse: se quedaba con la
         * `x` calculada para la ventana de arranque y los dos últimos botones
         * colgaban fuera del borde derecho. Y su `y` era 0, la de su `init`, así
         * que se pegaba al canto sin el aire que sí tenía el minimapa.
         *
         * Ahora la coloca quien coloca a todos, con el MISMO aire que el
         * minimapa: las dos piezas de abajo son hermanas y tienen que verse
         * igual de esquinadas.
         */
        /*
         * ⚠️ EL FRAME PRIMERO, EL BOUNDS DESPUES. No es estilo: es el orden.
         *
         * En AppKit, una vez que frame y bounds difieren, escribir `frame.size`
         * CONSERVA la escala vigente y REESCALA el bounds para mantenerla. Asi
         * que poner el bounds y luego el frame es escribir dos veces la misma
         * cosa: la segunda deshace la primera. Medido, pidiendo 405 en ambos:
         *
         *     bounds = 405   →  bounds.w = 405.0
         *     frame  = 405   →  bounds.w = 292.9   (405 / 1.383, la escala vieja)
         *
         * Resultado: escala 1.383 en X contra 1.0 en Y. La capsula salia
         * ESTIRADA a lo ancho y sus ultimos botones —la luna— caian 105 px por
         * fuera del bisel. Al reves, el bounds define el sistema de
         * coordenadas y no toca el frame, asi que las dos escalas cuadran.
         */
        estado.frame.size = NSSize(width: estado.anchoIdeal * esc, height: estadoAltoNatural * esc)
        estado.bounds = NSRect(x: 0, y: 0, width: estado.anchoIdeal, height: estadoAltoNatural)
        let apartar = docAbierto ? anchoDoc : 0
        estado.frame.origin = NSPoint(x: max(a, raiz.bounds.width - estado.frame.width - a - apartar), y: a)

        // El panel del documento: de la banda para abajo, pegado al canto
        // derecho. Mismo convenio que el de lienzos —a ras, no flotando— porque
        // una tarjeta suspendida deja de leerse como parte de la ventana.
        panelDoc.isHidden = !docAbierto
        panelDoc.frame = NSRect(x: raiz.bounds.width - anchoDoc, y: 0,
                                width: anchoDoc, height: altoPanel)
    }

    /// A DÓNDE lleva una liga. Un solo sitio decide, para que ⌘+clic, el clic
    /// en la marca y una liga dentro de un documento no puedan discrepar.
    func irA(_ liga: String) {
        switch Enlace.leer(liga) {
        case .documento(let ruta):
            abrirDoc(ruta)
        case .pagina(let id):
            guard id != actual?.id else { decir("ya estás en ese lienzo"); return }
            Task { await self.abrir(id) }
        case .video(let u), .web(let u):
            NSWorkspace.shared.open(u)
        case .app(let nombre, let vista):
            /*
             * ABRIR LA CABINA. El panel sigue sin escribir nada: lo que hace
             * es LLEVAR a la app donde la mano sí edita, que es exactamente lo
             * que Daniel hacía a mano buscándola en el Dock.
             *
             * `activates: true` para que venga al frente: abrir una app detrás
             * de la ventana actual se siente como que el clic no hizo nada.
             */
            // Se deja pedida la VISTA antes de abrir: la app la lee al arrancar
            // o al volver al frente. Escribirlo después sería una carrera con
            // su propio arranque.
            if let v = vista { PeticionVista.pedir(v) }
            if let u = Enlace.rutaApp(nombre) {
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = true
                NSWorkspace.shared.openApplication(at: u, configuration: cfg) { [weak self] _, err in
                    if let err { DispatchQueue.main.async { self?.decir("⚠︎ \(nombre): \(err.localizedDescription)", error: true) } }
                }
                decir("abriendo \(nombre)…")
            } else if let w = Enlace.webDeApp(nombre) {
                NSWorkspace.shared.open(w)
                decir("\(nombre) no está instalada · abriendo su web")
            } else {
                decir("⚠︎ no encuentro la app «\(nombre)» — ¿está instalada?", error: true)
            }
        case nil:
            decir("⚠︎ no entendí la liga: \(liga)", error: true)
        }
    }

    func abrirDoc(_ ruta: String) {
        let ok = panelDoc.mostrar(ruta)
        docAbierto = true
        if let raiz = ventana?.contentView { colocar(raiz) }
        decir(ok ? "doc · \(ruta)" : "⚠︎ no encontré \(ruta)", error: !ok)
    }

    func cerrarDoc() {
        docAbierto = false
        if let raiz = ventana?.contentView { colocar(raiz) }
    }

    /// ¿El puntero está sobre alguna pieza de cromo VISIBLE? Geometría pura:
    /// los frames viven en coords de `raiz`, y `locationInWindow` también
    /// (contentView a pantalla completa, mismo origen).
    func punteroSobreCromo(_ locVentana: NSPoint) -> Bool {
        guard let raiz = ventana?.contentView else { return false }
        let p = raiz.convert(locVentana, from: nil)
        let piezas: [NSView] = [banda, header, engrane, rail, estado, mapa, barra, lateral]
        return piezas.contains { !$0.isHidden && $0.frame.contains(p) }
    }

    /*
     * LA CÁMARA SE RECUERDA POR LIENZO, LOCALMENTE (Daniel, 24 ago: "que la
     * app recuerde el último zoom; al recargar lo conserva"). La nube guarda
     * la cámara solo cuando el DOCUMENTO se guarda — correcto: mirar no debe
     * subir agent_version — así que el zoom de solo-mirar se perdía en cada
     * ⌘R. El viewport es un asunto DEL APARATO, no del documento: vive en
     * UserDefaults, por página, con debounce (la cámara cambia a 120 Hz al
     * panear; escribir defaults en cada fotograma sería castigar el arrastre).
     */
    private var guardaCamara: DispatchWorkItem?
    func recordarCamara() {
        guard let id = actual?.id else { return }
        guardaCamara?.cancel()
        let c = lienzo.camara
        let item = DispatchWorkItem {
            UserDefaults.standard.set([c.x, c.y, c.zoom], forKey: "sfmap.camara.\(id)")
        }
        guardaCamara = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }
    static func camaraRecordada(_ id: String) -> Camara? {
        guard let a = UserDefaults.standard.array(forKey: "sfmap.camara.\(id)") as? [Double],
              a.count == 3, a[2] > 0 else { return nil }
        return Camara(x: a[0], y: a[1], zoom: a[2])
    }

    /// Fija la escala del cromo, la persiste y remaqueta. Una sola puerta.
    func fijarEscalaUI(_ s: CGFloat) {
        escalaUI = Estilo.clampEscalaUI(s)
        UserDefaults.standard.set(Double(escalaUI), forKey: "escalaUI")
        if let raiz = ventana?.contentView { colocar(raiz) }
        // La fila del título cambió de alto: los semáforos se re-centran o
        // quedan flotando a la altura vieja.
        centrarSemaforos()
    }

    /**
     * BAJA LOS TRES BOTONES DE macOS al eje de la fila del header.
     *
     * Daniel: *"baja el icono de los semáforos, céntralo a los componentes del
     * header"*. AppKit los pinta en la barra de título estándar —28 pt de alto—
     * y esta fila mide 52: quedaban 12 pt más arriba que el icono de la app y
     * que el título, tres piezas de la misma fila en dos renglones distintos.
     *
     * Portado de sfcal, que ya lo resolvió el 16 ago para su TopBar de 46. La
     * aritmética es la suya: se mide el centro actual DESDE ARRIBA y se corrige
     * la diferencia, en vez de fijar una `y` absoluta que depende de si la vista
     * del sistema está volteada.
     */
    func centrarSemaforos() {
        let centroDeseado = HeaderPulsable.ALTO * escalaUI / 2
        for tipo in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let b = ventana.standardWindowButton(tipo), let sup = b.superview else { continue }
            let enVentana = sup.convert(b.frame, to: nil)
            let centroActual = ventana.frame.height - enVentana.midY
            let delta = centroDeseado - centroActual
            guard abs(delta) > 0.5 else { continue }
            var f = b.frame
            f.origin.y += sup.isFlipped ? delta : -delta
            b.frame = f
        }
    }

    @objc func zAlFrente() { lienzo.doc.alFrente() }
    @objc func zAdelante() { lienzo.doc.unaAdelante() }
    @objc func zAtras() { lienzo.doc.unaAtras() }
    @objc func zAlFondo() { lienzo.doc.alFondo() }

    @objc func alternarLateralMenu() { alternarLateral() }

    private func alternarLateral() {
        lateralAbierta.toggle()
        lateral.isHidden = !lateralAbierta
        header.abierto = lateralAbierta
        /*
         * EL PANEL ABIERTO MANDA EN SU ZONA (Daniel, 24 ago: "ningún
         * componente se clickee detrás del sidebar"). El z-order de AppKit es
         * orden de montaje, y la barra contextual (y cualquier pieza montada
         * después del panel) quedaba ENCIMA aunque visualmente estuviera
         * detrás: un clic en el panel caía en un botón invisible debajo.
         * Re-colgarlo al abrirse lo pone hasta arriba de la pila.
         */
        if lateralAbierta, let raiz = ventana.contentView {
            lateral.removeFromSuperview()
            raiz.addSubview(lateral)
        }
        if let raiz = ventana.contentView { colocar(raiz) }
        ventana.makeFirstResponder(lienzo)
    }

    func windowDidResize(_ n: Notification) {
        if let r = ventana.contentView { colocar(r) }
        refrescarBarra()
    }

    func windowDidResignKey(_ n: Notification) {
        // Los paneles flotantes se cierran al perder el foco: uno abierto
        // detrás de otra ventana es un objeto huérfano sobre el lienzo.
        barra.cerrarPanel(); estado.cerrarPanel(); rail.cerrarDesplegable()
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: barra contextual
    // ════════════════════════════════════════════════════════════════════════

    /// Fuerza el mismo refresco que dispara un cambio del documento. Lo usan
    /// las escenas para reproducir la secuencia exacta que cerraba el panel.
    func forzarRefrescoBarra() { refrescarBarra() }

    private func refrescarBarra(soloPosicion: Bool = false) {
        let sel = lienzo.doc.seleccionados
        guard !sel.isEmpty else { barra.isHidden = true; barra.cerrarPanel(); refrescarBotones(); return }
        barra.tema = lienzo.tema
        barra.seleccion = sel
        // ACOMODAR solo aparece cuando hay algo que acomodar. Un botón en gris
        // que no explica por qué está en gris es peor que la ausencia.
        let nodos = sel.filter { ["shape", "image", "table", "code", "embed", "text"].contains($0.tipo) }
        barra.alAcomodar = nodos.count >= 2 ? { [weak self] in self?.acomodar() } : nil
        barra.acomodarBloqueados = nodos.filter(\.bloqueado).count
        var caja = sel[0].cajaVisual
        for e in sel.dropFirst() { caja = caja.union(e.cajaVisual) }
        barra.reconstruir(caja: caja, camara: lienzo.camara, viewport: lienzo.bounds.size)
        refrescarBotones()
        _ = soloPosicion
    }

    private func refrescarBotones() {
        mapa.seleccion = lienzo.doc.seleccion
        estado.puedeDeshacer = lienzo.doc.historial.puedeDeshacer
        estado.puedeRehacer = lienzo.doc.historial.puedeRehacer
        estado.haySeleccion = !lienzo.doc.seleccion.isEmpty
    }

    private func editarSeleccion(_ etiqueta: String, _ cuerpo: (inout Elemento) -> Void) {
        let ids = lienzo.doc.seleccion
        lienzo.doc.editar(etiqueta) { els in
            for i in els.indices where ids.contains(els[i].id) { cuerpo(&els[i]) }
        }
        refrescarBarra()
    }

    /// Aplica un parche crudo, opcionalmente acotado a QUÉ elementos.
    ///
    /// Sin ese filtro, pintar de rojo tres figuras y sus dos flechas le metía un
    /// campo `color` a los conectores, que no lo leen: datos muertos escritos en
    /// silencio, el patrón exacto que este lienzo existe para no repetir.
    private func aplicarPatch(_ patch: [String: Json?], _ solo: ((Elemento) -> Bool)?) {
        let ids = lienzo.doc.seleccion
        lienzo.doc.editar("cambiar") { els in
            for i in els.indices where ids.contains(els[i].id) {
                if let f = solo, !f(els[i]) { continue }
                els[i].tocar(patch)
                if patch["shape"] != nil || patch["role"] != nil { els[i].remaquetar() }
            }
            if patch["routing"] != nil || patch["waypoints"] != nil {
                els = Conectores.reruteaTodo(els)
            }
        }
        refrescarBarra()
    }

    /// Fija o suelta el ANCLAJE de un conector.
    ///
    /// Existe porque un anclaje que no se puede soltar es una trampa: conectas
    /// por el lado equivocado, mueves la caja esperando que la flecha se
    /// acomode, y no se acomoda nunca. La decisión de la mano tiene que poder
    /// deshacerse por la misma mano.
    private func fijarAnclaje(_ fijar: Bool) {
        let ids = lienzo.doc.seleccion
        lienzo.doc.editar(fijar ? "fijar anclaje" : "soltar anclaje") { els in
            for i in els.indices where ids.contains(els[i].id) && els[i].tipo == "connector" {
                guard fijar else { els[i].tocar(["fromPort": nil, "toPort": nil]); continue }
                // Al FIJAR se guardan los lados por los que la flecha pasa AHORA:
                // fijar sin mirar dejaría el anclaje en un lado arbitrario.
                guard let a = els[i].desdeId.flatMap({ id in els.first { $0.id == id } }),
                      let b = els[i].hastaId.flatMap({ id in els.first { $0.id == id } }),
                      let p0 = els[i].ruta.first, let pN = els[i].ruta.last else { continue }
                els[i].tocar(["fromPort": .texto(Ruteo.ladoMasCercano(Conectores.obstaculoDe(a), p0)),
                              "toPort": .texto(Ruteo.ladoMasCercano(Conectores.obstaculoDe(b), pN))])
            }
            els = Conectores.reruteaTodo(els)
        }
        refrescarBarra()
    }

    private func acomodar() {
        let r = lienzo.doc.acomodar()
        decir(r.bloqueados > 0
              ? "acomodadas \(r.movidos) · \(r.bloqueados) bloqueada\(r.bloqueados > 1 ? "s" : "")"
              : "acomodadas \(r.movidos)")
        refrescarBarra()
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: menú contextual
    // ════════════════════════════════════════════════════════════════════════

    /// Dos menús en uno: sobre un elemento ofrece lo que se le puede hacer A
    /// ESO; sobre el vacío, lo que se puede TRAER. Un menú único con la mitad de
    /// las entradas grises es más largo de leer y no dice más.
    private func menuContextual(_ punto: NSPoint, _ el: Elemento?) {
        let m = NSMenu()
        func item(_ t: String, _ tecla: String = "", _ f: @escaping () -> Void) {
            let i = NSMenuItem(title: t, action: #selector(disparar(_:)), keyEquivalent: tecla)
            i.target = self
            i.representedObject = Bloque(f)
            m.addItem(i)
        }
        if el != nil {
            item("Editar texto", "") { [weak self] in
                if let id = self?.lienzo.doc.seleccion.first { self?.lienzo.editarTexto(id) }
            }
            item("Duplicar", "d") { [weak self] in
                guard let s = self else { return }
                s.lienzo.doc.duplicar(s.lienzo.doc.seleccion); s.refrescarBarra()
            }
            /*
             * RECORTAR: solo aparece sobre una IMAGEN, y "quitar recorte" solo
             * si hay algo que quitar. Una tijera gris sobre una caja de texto
             * enseña que el menú no sabe sobre qué se pulsó.
             */
            if el?.tipo == "image" {
                m.addItem(.separator())
                item("Recortar imagen", "k") { [weak self] in self?.lienzo.iniciarRecorte() }
                if lienzo.puedeQuitarRecorte {
                    item("Quitar recorte") { [weak self] in self?.lienzo.quitarRecorte() }
                }
            }
            m.addItem(.separator())
            item("Traer al frente") { [weak self] in self?.lienzo.doc.alFrente() }
            item("Enviar al fondo") { [weak self] in self?.lienzo.doc.alFondo() }
            m.addItem(.separator())
            item("Agrupar", "g") { [weak self] in self?.lienzo.doc.agrupar(); self?.refrescarBarra() }
            item("Desagrupar") { [weak self] in self?.lienzo.doc.desagrupar(); self?.refrescarBarra() }
            m.addItem(.separator())
            for (t, eje) in [("Alinear a la izquierda", "izquierda"), ("Centrar horizontal", "centro-h"),
                             ("Alinear a la derecha", "derecha"), ("Alinear arriba", "arriba"),
                             ("Centrar vertical", "centro-v"), ("Alinear abajo", "abajo")] {
                item(t) { [weak self] in self?.lienzo.doc.alinear(eje) }
            }
            item("Distribuir en horizontal") { [weak self] in self?.lienzo.doc.distribuir(horizontal: true) }
            item("Distribuir en vertical") { [weak self] in self?.lienzo.doc.distribuir(horizontal: false) }
            m.addItem(.separator())
            item("Eliminar") { [weak self] in self?.lienzo.doc.borrarSeleccion(); self?.refrescarBarra() }
        } else {
            let w = lienzo.aMundo(lienzo.convert(punto, from: nil))
            for (t, h) in [("Nota", Herramienta.nota), ("Tabla", .tabla), ("Código", .codigo), ("Embed", .embed)] {
                item("Poner \(t) aquí") { [weak self] in
                    guard let s = self else { return }
                    s.lienzo.crearAqui(h, en: w)
                    s.rail.activa = .seleccionar
                }
            }
            m.addItem(.separator())
            item("Pegar", "v") { [weak self] in self?.lienzo.pegarDesdeMenu() }
            item("Seleccionar todo", "a") { [weak self] in
                guard let s = self else { return }
                s.lienzo.doc.seleccion = Set(s.lienzo.doc.elementos.map(\.id))
                s.refrescarBarra()
            }
            m.addItem(.separator())
            item("Encuadrar todo") { [weak self] in
                self?.lienzo.doc.seleccion = []
                self?.lienzo.encuadrar()
                self?.refrescarBarra()
            }
        }
        m.popUp(positioning: nil, at: lienzo.convert(punto, from: nil), in: lienzo)
    }

    final class Bloque: NSObject { let f: () -> Void; init(_ f: @escaping () -> Void) { self.f = f } }
    @objc private func disparar(_ i: NSMenuItem) { (i.representedObject as? Bloque)?.f() }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: menú de la app
    // ════════════════════════════════════════════════════════════════════════

    private func montarMenu() {
        let principal = NSMenu()
        let app = NSMenuItem(); principal.addItem(app)
        let mApp = NSMenu()
        mApp.addItem(withTitle: "Acerca de sfmap", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        mApp.addItem(.separator())
        mApp.addItem(withTitle: "Ocultar sfmap", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        mApp.addItem(withTitle: "Salir de sfmap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = mApp

        let archivo = NSMenuItem(); principal.addItem(archivo)
        let mArchivo = NSMenu(title: "Archivo")
        mArchivo.addItem(withTitle: "Lienzo nuevo", action: #selector(nuevoLienzo), keyEquivalent: "n").target = self
        mArchivo.addItem(withTitle: "Carpeta nueva", action: #selector(nuevaCarpeta), keyEquivalent: "N").target = self
        mArchivo.addItem(.separator())
        mArchivo.addItem(withTitle: "Guardar ahora", action: #selector(guardar), keyEquivalent: "s").target = self
        mArchivo.addItem(withTitle: "Recargar", action: #selector(recargar), keyEquivalent: "r").target = self
        mArchivo.addItem(.separator())
        mArchivo.addItem(withTitle: "Exportar PNG…", action: #selector(exportarTodo), keyEquivalent: "e").target = self
        archivo.submenu = mArchivo

        let edicion = NSMenuItem(); principal.addItem(edicion)
        let mEdicion = NSMenu(title: "Edición")
        // Estos van al PRIMER RESPONDEDOR, no a mí: así el editor de texto se
        // queda con ⌘C y ⌘V mientras escribes, y el lienzo cuando no.
        mEdicion.addItem(withTitle: "Deshacer", action: #selector(deshacerMenu), keyEquivalent: "z").target = self
        /*
         * ⚠️ EL EQUIVALENTE CON SHIFT VA EN MAYÚSCULA.
         *
         * `charactersIgnoringModifiers` ignora TODOS los modificadores menos
         * shift: un ⌘⇧Z real entrega "Z", no "z". Con la minúscula el ítem no
         * matchea nunca y rehacer no responde — mientras ⌘Z sí, que es la clase
         * de fallo que se lee como "a veces funciona".
         */
        let rehacer = mEdicion.addItem(withTitle: "Rehacer", action: #selector(rehacerMenu), keyEquivalent: "Z")
        rehacer.keyEquivalentModifierMask = [.command, .shift]; rehacer.target = self
        mEdicion.addItem(.separator())
        mEdicion.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        mEdicion.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        mEdicion.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        /*
         * ORGANIZAR, en el menu y no solo en el teclado.
         *
         * Un atajo que no esta escrito en ningun sitio solo lo usa quien ya lo
         * sabia. Aqui se ven los cuatro con su combinacion al lado, que es como
         * se aprenden — y de paso queda claro que hay DOS pasos distintos: uno
         * corto y uno hasta el final.
         */
        mEdicion.addItem(.separator())
        for (titulo, tecla, mayus, accion) in [
            ("Traer al frente", "]", true, #selector(zAlFrente)),
            ("Una capa adelante", "]", false, #selector(zAdelante)),
            ("Una capa atrás", "[", false, #selector(zAtras)),
            ("Enviar al fondo", "[", true, #selector(zAlFondo)),
        ] as [(String, String, Bool, Selector)] {
            let it = mEdicion.addItem(withTitle: titulo, action: accion, keyEquivalent: tecla)
            if mayus { it.keyEquivalentModifierMask = [.command, .shift] }
            it.target = self
        }
        edicion.submenu = mEdicion

        let ver = NSMenuItem(); principal.addItem(ver)
        let mVer = NSMenu(title: "Vista")
        mVer.addItem(withTitle: "Tamaño real", action: #selector(cien), keyEquivalent: "0").target = self
        let enc = mVer.addItem(withTitle: "Encuadrar", action: #selector(encuadrar), keyEquivalent: "1")
        enc.keyEquivalentModifierMask = [.shift]; enc.target = self
        mVer.addItem(.separator())
        mVer.addItem(withTitle: "Tema claro / oscuro", action: #selector(alternarTemaMenu), keyEquivalent: "t").target = self
        // ⌘⇧B abre y cierra el panel de lienzos (Daniel, 26 ago). Estaba en
        // ⌘\, que no se parece a nada: la B de "barra lateral" es la tecla que
        // usan las apps donde ese panel existe, y una tecla que ya sabes es
        // media tecla que no hay que aprender.
        //
        // En AppKit una `keyEquivalent` en MAYUSCULA significa ⌘⇧ — no hay que
        // tocar `keyEquivalentModifierMask`, y ponerle ademas `.shift` a mano
        // pediria ⌘⇧⇧, que no existe.
        mVer.addItem(withTitle: "Lienzos", action: #selector(alternarLateralMenu), keyEquivalent: "B").target = self
        mVer.addItem(.separator())
        mVer.addItem(withTitle: "Atajos", action: #selector(mostrarAtajosMenu), keyEquivalent: "/").target = self
        ver.submenu = mVer
        NSApp.mainMenu = principal
    }

    @objc private func deshacerMenu() { lienzo.doc.deshacer(); refrescarBarra() }
    @objc private func rehacerMenu() { lienzo.doc.rehacer(); refrescarBarra() }
    @objc private func cien() {
        // ⌘0 sobre cromo = la UI vuelve a 1. Sobre el lienzo, el 100% de siempre.
        if let v = ventana, punteroSobreCromo(v.mouseLocationOutsideOfEventStream) {
            fijarEscalaUI(1); return
        }
        lienzo.alCien()
    }
    @objc private func encuadrar() { lienzo.encuadrar() }
    /// ⌘R RECARGA del servidor, siempre (Daniel, 24 ago). Antes, en páginas
    /// con región gobernada, disparaba RECOMPILAR — que reescribe la geometría
    /// del diagrama, la operación que operar.md §8 dice que la firma Daniel.
    /// Un atajo llamado "recargar" que a veces recompila es una trampa;
    /// recompilar conserva su botón propio, explícito.
    @objc private func recargar() {
        // ⌘R adopta la versión recién instalada. Sin esto, cada vez que se
        // reinstala la app el proceso vivo sigue con el binario anterior: no
        // falla nada, simplemente no tiene lo nuevo, y hay que descubrir por
        // cuenta propia que había que cerrar y abrir.
        if Relanzar.siHayVersionNueva() { return }
        Task { @MainActor in Cronista.compartido.refrescarTodo() }
        guard let id = actual?.id else { return }
        Task { await abrir(id) }
    }
    /// ⌘N: el lienzo nuevo cae donde está parada la mano — la carpeta abierta
    /// del panel, como en VSCode — y solo en la raíz si no hay ninguna abierta.
    @objc private func nuevoLienzo() { crearPagina(en: lateral.carpetaContexto) }
    @objc private func nuevaCarpeta() { crearCarpeta() }
    @objc private func exportarTodo() { exportar(soloSeleccion: false) }
    @objc private func alternarTemaMenu() { alternarTema() }
    @objc private func mostrarAtajosMenu() { mostrarAtajos() }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: tema
    // ════════════════════════════════════════════════════════════════════════

    @objc private func temaCambio() { DispatchQueue.main.async { self.aplicarTema() } }

    private func alternarTema() {
        let ahora = lienzo.tema.nombre
        temaManual = ahora == "claro" ? "oscuro" : "claro"
        UserDefaults.standard.set(temaManual, forKey: "sfmap.tema")
        aplicarTema()
    }

    func aplicarTemaPublico() { aplicarTema() }

    private func aplicarTema() {
        /*
         * ⚠️ ANTES ESTO SE PINTABA AQUÍ ARRIBA, con `lienzo.tema` — que todavía
         * era el tema VIEJO, porque se asigna doce líneas más abajo. La franja
         * del título iba siempre un cambio por detrás: en oscuro se quedaba
         * blanca. No falla nada y no hay error; simplemente la fila de arriba
         * pertenece al tema anterior.
         *
         * La regla que lo cierra: NADIE pinta con el tema antes de haberlo
         * elegido. Todo el reparto vive junto, al final.
         */
        // El sistema manda MIENTRAS nadie elija. En cuanto la mano elige, su
        // elección gana y sobrevive a reabrir: seguir al sistema después de que
        // alguien pidió lo contrario es ignorarlo.
        let delSistema = ventana.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let t: Tema = (temaManual ?? (delSistema ? "oscuro" : "claro")) == "oscuro" ? .oscuro : .claro
        lienzo.tema = t
        banda.tema = t
        filoBanda.layer?.backgroundColor = t.filoCromo.cgColor
        header.tema = t
        lateral.tema = t
        rail.tema = t
        estado.tema = t
        barra.tema = t
        mapa.tema = t
        engrane.tema = t
        panelDoc.tema = t
        // El documento abierto se RE-PINTA con el tema nuevo: sus colores viven
        // en el texto atribuido, que ya está compuesto y no se entera solo.
        if docAbierto, let d = panelDoc.docActual { panelDoc.mostrar(d) }
        ventana.backgroundColor = t.lienzo
        ventana.appearance = NSAppearance(named: t.nombre == "oscuro" ? .darkAqua : .aqua)
        refrescarBarra()
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: datos
    // ════════════════════════════════════════════════════════════════════════

    private func decir(_ s: String, error: Bool = false) {
        // El candado se antepone SIEMPRE —un aviso que el siguiente mensaje borra
        // no está cuando hace falta— pero en PALABRAS, sin emoji: un ojo junto al
        // contador de elementos se lee como decoración, no como estado.
        let texto = Nube.soloLectura ? "solo lectura · " + s : s
        DispatchQueue.main.async { self.estado.esError = error; self.estado.estado = texto }
    }

    private func cargarLista() async {
        do {
            let (ps, cs) = try await Nube.paginas()
            await MainActor.run {
                self.paginas = ps; self.carpetas = cs
                self.lateral.paginas = ps
                self.lateral.carpetas = cs
                self.decir("")
                /*
                 * ABRE DONDE LO DEJASTE. La lista viene por fecha, así que "la
                 * primera" es la última que tocó cualquiera —incluido un cron—
                 * no la que estabas mirando.
                 */
                let recordada = UserDefaults.standard.string(forKey: "sfmap.ultima")
                let a = CommandLine.arguments
                if let i = a.firstIndex(of: "--centrar"), i + 1 < a.count {
                    self.centrarPendiente = a[i + 1]
                }
                let pedida = a.dropFirst().first { $0.count > 20 && !$0.hasPrefix("-") }
                let destino = ps.first { $0.id == pedida } ?? ps.first { $0.id == recordada } ?? ps.first
                if let d = destino { Task { await self.abrir(d.id) } }
            }
        } catch {
            decir("⚠︎ \(error.localizedDescription)", error: true)
        }
    }

    private func abrir(_ id: String) async {
        // ⚠️ La goma borra al TERMINAR su desvanecido. Si se cambia de lienzo
        // con uno a medias, ese borrado se aplicaria sobre el documento que
        // acaba de cargarse — o se perderia. Se cierra aqui, contra el
        // documento al que pertenece, antes de tocar nada.
        //
        // En el hilo principal a proposito: `abrir` es `async` y toca la vista,
        // asi que el aviso del compilador no era ruido — sin esto se estaria
        // escribiendo en el modelo desde fuera del actor.
        await MainActor.run { self.lienzo.cerrarDesvanecido() }
        decir("abriendo…")
        do {
            let p = try await Nube.abrir(id)
            await MainActor.run {
                // ¿Es la MISMA página releída, o un lienzo distinto? De eso
                // depende que el deshacer sobreviva: ver `Documento.cargar`.
                let recarga = self.actual?.id == id
                self.actual = p
                UserDefaults.standard.set(id, forKey: "sfmap.ultima")
                self.lienzo.doc.cargar(p.elementos, recarga: recarga)
                self.lienzo.cerrarEditor(guardando: false)
                /*
                 * ABRIR UN LIENZO DEVUELVE LA FLECHA.
                 *
                 * Las herramientas se QUEDAN puestas para poder insertar cinco
                 * cajas seguidas sin cinco viajes al rail, pero eso vale dentro
                 * de un lienzo, no entre dos: llegar a un mapa nuevo con el
                 * lápiz o la flecha en la mano significa que el primer clic
                 * —que casi siempre es para mirar o seleccionar algo— dibuja.
                 * Daniel: *"la flecha de selección está de default siempre, al
                 * abrir incluso"*.
                 */
                self.lienzo.herramienta = .seleccionar
                self.rail.cerrarDesplegable()
                let carpeta = ps_carpeta(self.paginas, self.carpetas, p.id)
                self.header.poner(nombre: p.nombre, carpeta: carpeta)
                self.lateral.activa = p.id
                if let i = self.paginas.firstIndex(where: { $0.id == p.id }) {
                    self.paginas[i].elementos = p.elementos.count
                    self.lateral.paginas = self.paginas
                }
                if let raiz = self.ventana.contentView { self.colocar(raiz) }
                /*
                 * EL TECLADO VUELVE AL LIENZO AL ABRIR.
                 *
                 * Antes lo arreglaba un efecto colateral: el panel se cerraba
                 * al elegir, y al cerrarse el buscador dejaba de ser primer
                 * respondedor. Ahora el panel SE QUEDA ABIERTO (que es lo que
                 * se pidio), asi que sin esto el foco se quedaria en el campo
                 * de busqueda: escribes esperando actuar sobre el lienzo y en
                 * realidad estas filtrando la lista. Es el mismo fallo mudo
                 * que ya documenta el monitor del dial, unas lineas arriba.
                 */
                self.ventana.makeFirstResponder(self.lienzo)
                self.sucio = false
                // Primero la memoria LOCAL del aparato (el último zoom que la
                // mano dejó aquí), luego la cámara del documento, luego encuadrar.
                if let local = Delegado.camaraRecordada(p.id) { self.lienzo.camara = local }
                else if let c = p.camara { self.lienzo.camara = c }
                else { self.lienzo.encuadrar() }
                self.refrescarBarra()
                self.mapa.elementos = p.elementos
                self.mapa.camara = self.lienzo.camara
                self.mapa.vista = self.lienzo.bounds.size
                if let c = self.centrarPendiente { self.centrarPendiente = nil; self.centrarSeleccionar(c) }
                /*
                 * SIN CONTADOR. Daniel: *"quita lo de 45 elementos, están de
                 * más"*. Y tiene razón: cuántos elementos hay se ve mirando el
                 * lienzo, así que ese número ocupaba la única línea que sí dice
                 * algo que NO se puede ver — si tu trabajo está guardado.
                 */
                self.decir(Fuentes.faltantes.isEmpty ? ""
                           : "⚠︎ sin \(Fuentes.faltantes.joined(separator: ", "))",
                           error: !Fuentes.faltantes.isEmpty)
            }
            // La puerta del compilador solo se ofrece si hay algo que compilar.
            let rs = await Compilador.regiones(p.id)
            await MainActor.run {
                self.regiones = rs
                self.estado.alRecompilar = rs.isEmpty ? nil : { [weak self] in self?.recompilar() }
                if !rs.isEmpty { traza("regiones gobernadas: \(rs.map(\.id))") }
            }
        } catch { decir("⚠︎ \(error.localizedDescription)", error: true) }
    }

    private func marcarSucio() {
        sucio = true
        // ⚠️ CADA EDICIÓN SUBE EL SELLO. Es lo que distingue "lo que salió en
        // este guardado" de "lo que Daniel cambió mientras volaba". Sin él,
        // `sucio = false` al terminar borraba cambios que nunca se enviaron.
        sello &+= 1
        estado.sello = .pendiente
        decir("sin guardar")
        // Se guarda al SOLTAR, no en cada fotograma del arrastre: escribir por
        // fotograma es lo que hacía que el lienzo web se pisara a sí mismo.
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(guardar), object: nil)
        perform(#selector(guardar), with: nil, afterDelay: 0.6)
    }

    /**
     * EL GUARDADO, con las dos costuras que lo hacían "molesto" (26 ago 2026).
     *
     * 1. UN CAMBIO HECHO MIENTRAS EL GUARDADO VOLABA SE PERDÍA. La llamada
     *    salía con una copia de los elementos, y al volver ponía `sucio =
     *    false` sin preguntar: todo lo editado en ese medio segundo quedaba
     *    marcado como guardado sin haber salido nunca de la máquina. Se veía
     *    "guardado" en la barra y no lo estaba — la peor forma del fallo.
     *    Ahora cada edición sube un SELLO; al volver solo se limpia si el
     *    sello no se movió, y si se movió, se vuelve a guardar en seguida.
     *
     * 2. LA BARRA PARPADEABA. "sin guardar" → "guardando…" → "guardado v20"
     *    en menos de un segundo, en cada arrastre. Daniel: *"que sea smooth,
     *    solo el guardado es suficiente"*. El número de versión no dice nada
     *    que él pueda usar, y "guardando…" solo importa si TARDA: ahora
     *    aparece a los 400 ms y no antes, así que un guardado normal es un
     *    único cambio de texto, no tres.
     */
    @objc private func guardar() {
        // El candado se comprueba ANTES de marcar nada: dejar que el guardado
        // arranque y falle al final dejaría el estado diciendo "guardando…"
        // para siempre.
        if Nube.soloLectura { sucio = false; decir("sin guardar (solo lectura)"); return }
        guard var p = actual, sucio else { return }
        // Un guardado en vuelo NO se pisa: se apunta que hay que repetir en
        // cuanto aterrice. Antes esto era un `return` seco y el cambio se
        // quedaba esperando a que otra edición lo arrastrara.
        if guardando { repetirGuardado = true; return }
        guardando = true
        let selloEnVuelo = sello
        p.elementos = lienzo.doc.elementos
        p.camara = lienzo.camara
        // "guardando…" solo si TARDA. Un guardado rápido no debe pintar nada.
        let lento = DispatchWorkItem { [weak self] in
            guard let s = self, s.guardando else { return }
            s.decir("guardando…")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: lento)
        // Se congela una COPIA antes de cruzar al Task: `p` es var, y una var
        // capturada por una tarea concurrente es exactamente el hueco por donde
        // se cuela un guardado con el estado de otro momento.
        let aGuardar = p
        Task {
            do {
                let v = try await Nube.guardar(aGuardar)
                await MainActor.run {
                    lento.cancel()
                    self.actual?.version = v
                    self.actual?.elementos = self.lienzo.doc.elementos
                    self.guardando = false
                    // Solo está guardado lo que salió. Si el sello se movió,
                    // Daniel siguió editando y hay que volver a salir.
                    let alDia = self.sello == selloEnVuelo && !self.repetirGuardado
                    self.repetirGuardado = false
                    self.sucio = !alDia
                    self.header.poner(nombre: aGuardar.nombre,
                                          carpeta: ps_carpeta(self.paginas, self.carpetas, aGuardar.id))
                    if alDia { self.estado.sello = .guardado; self.decir("guardado") }
                    else { self.guardar() }
                }
            } catch {
                await MainActor.run {
                    lento.cancel()
                    self.guardando = false
                    self.repetirGuardado = false
                    self.estado.sello = .error
                    self.decir("⚠︎ no guardó: \(error.localizedDescription)", error: true)
                }
            }
        }
    }

    /// El sondeo de sincronía: si la versión del servidor subió y no fuimos
    /// nosotros, alguien la editó en la web o en otro dispositivo.
    private func mirarSiCambio() {
        // Sin `isKeyWindow`: Daniel mira sfmap mientras teclea en OTRA app
        // (SFTerm) — el espejo debe enterarse aunque no tenga el foco.
        guard let p = actual else { return }
        let botones = NSEvent.pressedMouseButtons
        Task {
            let v = await Nube.version(p.id)
            guard Puente.debeRecargar(remota: v, local: p.version, sucio: self.sucio,
                                      guardando: self.guardando, botonesRaton: botones) else { return }
            await MainActor.run { self.decir("cambió en otro sitio · recargando…") }
            await self.abrir(p.id)
        }
    }

    /// El panel también es un espejo: páginas nuevas/renombradas/movidas por
    /// Levy (o por la web) aparecen solas, sin relanzar. Incidente 24 ago 2026:
    /// el panel listaba UNA vez al arrancar y una página recién creada por REST
    /// era invisible hasta matar la app.
    private func mirarLista() {
        Task {
            guard let (ps, cs) = try? await Nube.paginas() else { return }
            let firma = Puente.firmaListas(ps, cs)
            await MainActor.run {
                guard firma != self.firmaPanel else { return }
                self.firmaPanel = firma
                self.paginas = ps; self.carpetas = cs
                self.lateral.paginas = ps; self.lateral.carpetas = cs
            }
        }
    }

    /// El latido de la puerta agéntica: consume `orden.json` (Levy → app) y
    /// publica `seleccion.json` (app → Levy) cuando la selección cambió.
    private func latidoPuente() {
        if let o = Puente.leerOrden() {
            Task {
                if let pg = o.abrir, pg != self.actual?.id {
                    await MainActor.run { self.centrarPendiente = o.centrar }
                    await self.abrir(pg)
                } else if let c = o.centrar {
                    await MainActor.run { self.centrarSeleccionar(c) }
                }
                if let d = o.doc { await MainActor.run { self.abrirDoc(d) } }
            }
        }
        guard let p = actual else { return }
        let sel = lienzo.doc.seleccion
        if seleccionEscrita != sel {
            seleccionEscrita = sel
            Puente.escribirSeleccion(pagina: p.id, nombre: p.nombre,
                                     elementos: lienzo.doc.seleccionados)
        }
    }

    /// Centra la cámara en un elemento y lo deja SELECCIONADO (el anillo de
    /// selección ya es el highlight). Es el "te lo marqué en el lienzo".
    func centrarSeleccionar(_ id: String) {
        guard let e = lienzo.doc.elementos.first(where: { $0.id == id }) else {
            decir("⚠︎ no encontré el elemento \(id)", error: true); return
        }
        lienzo.doc.seleccion = [id]
        lienzo.camara = .centradaEn(e.cajaVisual, zoom: max(0.5, lienzo.camara.zoom))
        mapa.camara = lienzo.camara
        lienzo.needsDisplay = true
        refrescarBarra()
        decir("Levy señala: \(e.textoEditable.isEmpty ? id : String(e.textoEditable.prefix(40)))")
    }

    // ── páginas ─────────────────────────────────────────────────────────────

    private func crearPagina(en carpeta: String?) {
        Task {
            do {
                let p = try await Nube.crearPagina(carpeta: carpeta)
                await MainActor.run {
                    self.paginas.insert(p, at: 0)
                    // Que se VEA donde nació: si la carpeta destino estaba
                    // plegada, la página nueva aparecía solo al abrirla a mano.
                    if let c = carpeta { self.lateral.abrir(c) }
                    self.lateral.paginas = self.paginas
                }
                await self.abrir(p.id)
            } catch { decir("⚠︎ \(error.localizedDescription)", error: true) }
        }
    }

    private func crearCarpeta(en madre: String? = nil) {
        Task {
            do {
                let c = try await Nube.crearCarpeta(madre: madre)
                await MainActor.run {
                    self.carpetas.append(c)
                    self.lateral.carpetas = self.carpetas
                    if let m = madre { self.lateral.abrir(m) }
                    self.decir("carpeta creada")
                }
            } catch { decir("⚠︎ \(error.localizedDescription)", error: true) }
        }
    }

    /// Mete o saca una carpeta de otra. Un solo nivel; el panel ya no ofrece
    /// diana para lo que lo rompería.
    private func anidarCarpeta(_ id: String, _ madre: String?) {
        Task {
            do {
                try await Nube.anidarCarpeta(id, en: madre)
                await MainActor.run {
                    if let i = self.carpetas.firstIndex(where: { $0.id == id }) {
                        self.carpetas[i].madre = madre
                        self.lateral.carpetas = self.carpetas
                    }
                    if let m = madre { self.lateral.abrir(m) }
                    self.decir(madre == nil ? "carpeta sacada" : "carpeta anidada")
                }
            } catch { decir("⚠︎ \(error.localizedDescription)", error: true) }
        }
    }

    private func renombrarPagina(_ id: String, _ nombre: String) {
        Task {
            do {
                try await Nube.renombrarPagina(id, nombre)
                await MainActor.run {
                    if let i = self.paginas.firstIndex(where: { $0.id == id }) { self.paginas[i].nombre = nombre }
                    self.lateral.paginas = self.paginas
                    if self.actual?.id == id {
                        self.actual?.nombre = nombre
                        self.header.poner(nombre: nombre,
                                          carpeta: ps_carpeta(self.paginas, self.carpetas, id))
                        if let r = self.ventana.contentView { self.colocar(r) }
                    }
                }
            } catch { decir("⚠︎ \(error.localizedDescription)", error: true) }
        }
    }

    /// Borrar un lienzo NO PREGUNTA (orden de Daniel, 23 ago 2026: "que no me
    /// pregunte y simplemente se borre"). El diálogo cobraba un clic a la acción
    /// más común del panel, y el borrado es LOGICO: la fila queda en la base con
    /// `is_deleted`, así que un clic no puede llevarse meses de trabajo.
    private func borrarPagina(_ id: String) {
        Task {
            do {
                try await Nube.borrarPagina(id)
                await MainActor.run {
                    self.paginas.removeAll { $0.id == id }
                    self.lateral.paginas = self.paginas
                    self.decir("borrado")
                }
                if self.actual?.id == id, let otra = self.paginas.first { await self.abrir(otra.id) }
            } catch { decir("⚠︎ \(error.localizedDescription)", error: true) }
        }
    }

    private func moverPagina(_ id: String, _ carpeta: String?) {
        Task {
            do {
                try await Nube.moverPagina(id, aCarpeta: carpeta)
                await MainActor.run {
                    if let i = self.paginas.firstIndex(where: { $0.id == id }) { self.paginas[i].folderId = carpeta }
                    self.lateral.paginas = self.paginas
                    if self.actual?.id == id {
                        self.header.poner(nombre: self.actual?.nombre ?? "",
                                          carpeta: ps_carpeta(self.paginas, self.carpetas, id))
                    }
                }
            } catch { decir("⚠︎ \(error.localizedDescription)", error: true) }
        }
    }

    private func renombrarCarpeta(_ id: String, _ nombre: String) {
        Task {
            do {
                try await Nube.renombrarCarpeta(id, nombre)
                await MainActor.run {
                    if let i = self.carpetas.firstIndex(where: { $0.id == id }) { self.carpetas[i].nombre = nombre }
                    self.lateral.carpetas = self.carpetas
                }
            } catch { decir("⚠︎ \(error.localizedDescription)", error: true) }
        }
    }

    /// Borrar una carpeta tampoco pregunta, por lo mismo: suelta sus lienzos a
    /// "SIN CARPETA" (jamás los borra con ella) y el contenedor desaparece.
    /**
     * ⚠️ BORRAR EN LOTE PREGUNTA. SIEMPRE.
     *
     * Es la regla de la casa, ganada con un incidente propio: una acción
     * irreversible de alcance masivo no sale de un clic. Aquí el diálogo no
     * estorba —se abre una vez por lote, no por elemento— y dice EL NÚMERO,
     * que es el dato que decide: borrar "unos lienzos" y borrar CATORCE no son
     * la misma decisión.
     */
    private func confirmar(_ titulo: String, _ cuerpo: String, _ botonRojo: String) -> Bool {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = titulo
        a.informativeText = cuerpo
        let ok = a.addButton(withTitle: botonRojo)
        ok.hasDestructiveAction = true
        a.addButton(withTitle: "Cancelar")
        return a.runModal() == .alertFirstButtonReturn
    }

    private func borrarPaginas(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let nombres = ids.compactMap { id in paginas.first { $0.id == id }?.nombre }
        let lista = nombres.prefix(8).map { "· \($0)" }.joined(separator: "\n")
            + (nombres.count > 8 ? "\n· …y \(nombres.count - 8) más" : "")
        guard confirmar("Se borrarán \(ids.count) lienzos",
                        "\(lista)\n\nEsto no se puede deshacer desde la app.",
                        "Borrar \(ids.count)") else { return }
        Task {
            var idos: [String] = []
            for id in ids {
                if (try? await Nube.borrarPagina(id)) != nil { idos.append(id) }
            }
            let hechos = idos
            await MainActor.run {
                self.paginas.removeAll { hechos.contains($0.id) }
                self.lateral.paginas = self.paginas
                self.lateral.limpiarLote()
                let fallos = ids.count - hechos.count
                self.decir(fallos == 0 ? "borrados \(hechos.count)"
                                       : "⚠︎ \(fallos) no se pudieron borrar", error: fallos > 0)
            }
            if let a = self.actual?.id, ids.contains(a), let otra = self.paginas.first {
                await self.abrir(otra.id)
            }
        }
    }

    private func borrarCarpeta(_ id: String) {
        // Lo que hay DENTRO decide la pregunta: una carpeta vacía se va sin
        // ceremonia; una con trabajo dentro avisa de cuánto se lleva por
        // delante y ofrece la salida intermedia (conservar los lienzos).
        let dentro = paginas.filter { $0.folderId == id }
        let nombre = carpetas.first { $0.id == id }?.nombre ?? "la carpeta"
        var tambienLosLienzos = false
        if !dentro.isEmpty {
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = "«\(nombre)» tiene \(dentro.count) lienzo\(dentro.count == 1 ? "" : "s")"
            a.informativeText = dentro.prefix(8).map { "· \($0.nombre)" }.joined(separator: "\n")
                + (dentro.count > 8 ? "\n· …y \(dentro.count - 8) más" : "")
            let borrar = a.addButton(withTitle: "Borrar carpeta y \(dentro.count) lienzos")
            borrar.hasDestructiveAction = true
            a.addButton(withTitle: "Solo la carpeta")
            a.addButton(withTitle: "Cancelar")
            switch a.runModal() {
            case .alertFirstButtonReturn:  tambienLosLienzos = true
            case .alertSecondButtonReturn: tambienLosLienzos = false
            default: return
            }
        }
        Task {
            if tambienLosLienzos {
                for p in dentro { try? await Nube.borrarPagina(p.id) }
                await MainActor.run {
                    let ids = Set(dentro.map(\.id))
                    self.paginas.removeAll { ids.contains($0.id) }
                }
            }
            do {
                try await Nube.borrarCarpeta(id)
                await MainActor.run {
                    self.carpetas.removeAll { $0.id == id }
                    for i in self.paginas.indices where self.paginas[i].folderId == id { self.paginas[i].folderId = nil }
                    self.lateral.carpetas = self.carpetas
                    self.lateral.paginas = self.paginas
                    self.decir("carpeta borrada")
                }
            } catch { decir("⚠︎ \(error.localizedDescription)", error: true) }
        }
    }

    /// RECOMPILAR: la capa semántica hecha gesto.
    ///
    /// No se toca en modo solo lectura: recompilar ESCRIBE en el documento, y un
    /// candado que solo cubre el guardado propio deja abierta la puerta de al
    /// lado.
    private func recompilar() {
        guard let p = actual, let r = regiones.first else { return }
        if Nube.soloLectura { decir("solo lectura · no se recompiló"); return }
        decir("recompilando \(r.id)…")
        Task {
            do {
                let res = try await Compilador.recompilar(p.id, r, tema: lienzo.tema.nombre)
                await MainActor.run {
                    self.decir("recompilado · +\(res.agregados) ~\(res.actualizados) −\(res.quitados)"
                               + (res.fijados > 0 ? " · \(res.fijados) fijados intactos" : ""))
                }
                await self.abrir(p.id)
            } catch {
                await MainActor.run { self.decir("⚠︎ \(error.localizedDescription)", error: true) }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: exportar
    // ════════════════════════════════════════════════════════════════════════

    /// Exporta a PNG usando la caja VISUAL, no la del objeto: el pie de una
    /// tarjeta cuelga por fuera y con `caja` se corta a media frase. La imagen
    /// exportada es la que se comparte — cortar texto ahí es el peor sitio.
    private func exportar(soloSeleccion: Bool) {
        let objetivo = soloSeleccion ? lienzo.doc.seleccionados : lienzo.doc.elementos
        guard var r = objetivo.first?.cajaVisual else { decir("nada que exportar"); return }
        for e in objetivo.dropFirst() { r = r.union(e.cajaVisual) }
        r = r.insetBy(dx: -48, dy: -48)
        let escala = 2.0   // retina: un PNG a 1x se ve borroso en cualquier pantalla de hoy
        let w = Int(r.width * escala), h = Int(r.height * escala)
        guard w > 0, h > 0, w * h < 80_000_000 else { decir("⚠︎ el lienzo es demasiado grande para exportar", error: true); return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(actual?.nombre ?? "lienzo").png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(lienzo.tema.lienzo.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: escala, y: escala)
        // La Y del documento va hacia abajo: se voltea el lienzo entero una vez.
        ctx.translateBy(x: 0, y: r.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -r.minX, y: -r.minY)

        let p = Pintor(ctx: ctx, tema: lienzo.tema, camara: Camara(x: 0, y: 0, zoom: 1),
                       tamano: CGSize(width: r.width, height: r.height))
        let visibles = objetivo.sorted { $0.z < $1.z }
        for e in visibles where e.tipo == "frame" { p.seccion(e) }
        for e in visibles where e.tipo == "connector" { p.conector(e) }
        for e in visibles {
            ctx.saveGState()
            if Geo.estaGirado(e) {
                ctx.translateBy(x: e.caja.midX, y: e.caja.midY)
                ctx.rotate(by: e.giro)
                ctx.translateBy(x: -e.caja.midX, y: -e.caja.midY)
            }
            switch e.tipo {
            case "shape": p.figura(e)
            case "text":  p.bloqueTexto(e)
            case "ink":   p.tinta(e)
            case "table": p.tabla(e)
            case "code":  p.codigo(e)
            case "image": p.imagen(e) {}
            case "embed": p.embed(e)
            default: break
            }
            ctx.restoreGState()
        }
        guard let img = ctx.makeImage() else { decir("⚠︎ no se pudo componer el PNG", error: true); return }
        let rep = NSBitmapImageRep(cgImage: img)
        guard let datos = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try datos.write(to: url)
            decir("exportado · \(w)×\(h)")
        } catch { decir("⚠︎ \(error.localizedDescription)", error: true) }
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: atajos
    // ════════════════════════════════════════════════════════════════════════

    /**
     * LA HOJA DE ATAJOS.
     *
     * Existe porque el v3 la prometía y no la tenía: declaraba `?` como
     * "mostrar atajos" y NADA lo abría jamás. Treinta atajos documentados en un
     * archivo que ningún humano podía ver.
     *
     * ⚠️ REGLA: esta lista se deriva de lo que el teclado HACE. Un catálogo
     * escrito aparte se desincroniza del manejador en la primera semana — es
     * literalmente lo que le pasó al v3, donde ⌘A estaba documentado y no
     * existía, y `T` aparecía dos veces para dos herramientas.
     */
    private func mostrarAtajos() {
        if let h = hoja { h.removeFromSuperview(); hoja = nil; return }
        guard let raiz = ventana.contentView else { return }
        let grupos: [(String, [(String, String)])] = [
            ("Herramientas", Herramienta.allCases.filter { !$0.tecla.isEmpty }.map { ($0.tecla, $0.nombre) }),
            ("Moverse", [("Espacio + arrastrar", "Mover el lienzo"), ("Botón del medio", "Mover el lienzo"),
                         ("Rueda / dos dedos", "Mover el lienzo"), ("⌘ + rueda", "Acercar y alejar"),
                         ("⇧1", "Encuadrar"), ("0", "Volver al 100%")]),
            ("Seleccionar", [("Clic", "Elegir"), ("⇧ + clic", "Sumar a la selección"),
                             ("Arrastrar en vacío", "Marquesina"), ("⌘A", "Todo"),
                             ("⌘⇧A", "El diagrama entero, desde una de sus piezas"),
                             ("⌘ + clic", "Abrir el enlace del elemento")]),
            ("Goma", [("E", "Coger la goma"), ("Rueda inferior de la tableta", "Tamaño"),
                      ("[ y ]", "Tamaño, sin tableta"), ("⌥ + barrer", "Quitar de lo marcado"),
                      ("Alcance", "Tinta o Todo, en su panel del rail")]),
            ("Editar", [("Doble clic / Intro", "Escribir dentro"), ("Supr", "Eliminar"),
                        ("⌘Z / ⌘⇧Z", "Deshacer / rehacer"), ("⌘D", "Duplicar"),
                        ("⌥ + arrastrar", "Duplicar arrastrando"), ("⌘G / ⌘⇧G", "Agrupar / desagrupar"),
                        ("⌘K", "Recortar imagen · arrastra e Intro"),
                        ("⌘⇧L", "Bloquear"), ("⌘[ / ⌘]", "Al fondo / al frente"),
                        ("Flechas", "Mover 1 px"), ("⇧ + flechas", "Mover 10 px"),
                        ("⇧ al redimensionar", "Conservar proporción"), ("⇧ al girar", "Escalones de 15°")]),
            ("Lienzo", [("⌘N", "Lienzo nuevo"), ("⌘⇧N", "Carpeta nueva"), ("⌘S", "Guardar ahora"),
                        ("⌘R", "Recargar"), ("⌘E", "Exportar PNG"), ("T", "Tema claro / oscuro"),
                        ("⌘\\", "Abrir la lista de lienzos"), ("⌘/", "Esta hoja")]),
        ]
        let fondo = NSView(frame: raiz.bounds)
        fondo.autoresizingMask = [.width, .height]
        fondo.wantsLayer = true
        fondo.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor

        let cols = 2
        let anchoCol: CGFloat = 380
        let tarjeta = Tarjeta(tema: lienzo.tema, radio: 18)
        var alturas = [CGFloat](repeating: 0, count: cols)
        var vistas: [(NSView, Int)] = []
        for (i, g) in grupos.enumerated() {
            let col = i % cols
            let bloque = NSView(frame: NSRect(x: 0, y: 0, width: anchoCol, height: CGFloat(g.1.count) * 24 + 30))
            let t = NSTextField(labelWithString: g.0.uppercased())
            t.font = Estilo.fuente(10.5, 800); t.textColor = lienzo.tema.pieTexto
            t.frame = NSRect(x: 0, y: bloque.frame.height - 20, width: anchoCol, height: 16)
            bloque.addSubview(t)
            for (j, fila) in g.1.enumerated() {
                let k = NSTextField(labelWithString: fila.0)
                k.font = Estilo.fuente(11.5, 700); k.textColor = lienzo.tema.tituloTexto
                k.alignment = .right
                k.frame = NSRect(x: 0, y: bloque.frame.height - 46 - CGFloat(j) * 24, width: 150, height: 18)
                let d = NSTextField(labelWithString: fila.1)
                d.font = Estilo.fuente(11.5, 500); d.textColor = lienzo.tema.cuerpoTexto
                d.frame = NSRect(x: 162, y: bloque.frame.height - 46 - CGFloat(j) * 24, width: anchoCol - 162, height: 18)
                bloque.addSubview(k); bloque.addSubview(d)
            }
            alturas[col] += bloque.frame.height + 18
            vistas.append((bloque, col))
        }
        let alto = (alturas.max() ?? 300) + 60
        let ancho = CGFloat(cols) * anchoCol + 30 * CGFloat(cols + 1) - 30
        tarjeta.frame = NSRect(x: (raiz.bounds.width - ancho) / 2, y: (raiz.bounds.height - alto) / 2,
                               width: ancho, height: alto)
        let titulo = NSTextField(labelWithString: "Atajos")
        titulo.font = Estilo.fuente(17, 800); titulo.textColor = lienzo.tema.tituloTexto
        titulo.frame = NSRect(x: 30, y: alto - 42, width: 300, height: 24)
        tarjeta.addSubview(titulo)
        var y = [CGFloat](repeating: alto - 60, count: cols)
        for (v, col) in vistas {
            y[col] -= v.frame.height
            v.frame.origin = NSPoint(x: 30 + CGFloat(col) * (anchoCol + 30), y: y[col])
            y[col] -= 18
            tarjeta.addSubview(v)
        }
        let cerrar = BotonPlano(icono: nil, titulo: "Cerrar", ancho: 90, alto: 30)
        cerrar.tema = lienzo.tema
        cerrar.alPulsar = { [weak self] in self?.hoja?.removeFromSuperview(); self?.hoja = nil }
        cerrar.frame = NSRect(x: ancho - 120, y: alto - 46, width: 90, height: 30)
        tarjeta.addSubview(cerrar)
        fondo.addSubview(tarjeta)
        raiz.addSubview(fondo)
        hoja = fondo
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    /// Guardar antes de cerrar. Un cambio de hace medio segundo todavía no ha
    /// viajado, y perderlo por cerrar la ventana es el peor momento posible.
    func applicationShouldTerminate(_ s: NSApplication) -> NSApplication.TerminateReply {
        guard sucio, actual != nil else { return .terminateNow }
        guardar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

// El cronómetro del arrastre: carga una página real y sale.
if let id = Cronometro.ruta() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let sem = DispatchSemaphore(value: 0)
    Task { await Cronometro.correr(id); sem.signal() }
    // La medición vive en el hilo principal, así que hay que bombear el bucle
    // en vez de bloquearlo: con `sem.wait()` a secas nada se dibujaría nunca.
    while sem.wait(timeout: .now() + 0.02) == .timedOut {
        while let e = app.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
            app.sendEvent(e)
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    exit(0)
}

// `--vista mes|semana|cuatro|dia` fija la vista del widget de calendario SOLO
// para esta corrida (igual que `--tema`): una verificación que deja cambiada la
// preferencia de Daniel no es una verificación, es un efecto secundario.
if let i = CommandLine.arguments.firstIndex(of: "--vista"), i + 1 < CommandLine.arguments.count,
   let v = VistaCalendario(rawValue: CommandLine.arguments[i + 1]) {
    VistaCalendario.forzada = v
}

// `--ventana semana|mes|trimestre` fija la ventana de los sensores SOLO para
// esta corrida, igual que `--tema` y `--vista`: una verificación que deja
// cambiada la preferencia de Daniel no es una verificación.
if let i = CommandLine.arguments.firstIndex(of: "--ventana"), i + 1 < CommandLine.arguments.count,
   let v = VentanaSensor(rawValue: CommandLine.arguments[i + 1]) {
    VentanaSensor.forzada = v
}

// La hoja de MUESTRA de la piel didáctica, fuera de pantalla.
if let i = CommandLine.arguments.firstIndex(of: "--piel"), i + 1 < CommandLine.arguments.count {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let nombre = CommandLine.arguments[i + 1]
    Escenas.pielFueraDePantalla(nombre + "-oscuro.png", tema: .oscuro)
    Escenas.pielFueraDePantalla(nombre + "-claro.png", tema: .claro)
    exit(0)
}

// La escena de la BARRA. Fuera de pantalla y SIN Delegado: montar el delegado
// abriría la ventana a pantalla completa, que es justo lo que la regla del deep
// work prohíbe (`nada-emerge-en-deep-work`).
if CommandLine.arguments.contains("--barra-panel") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    Escenas.barraPanelFueraDePantalla()
    exit(0)
}

// La escena del CENTRO DE MANDO, fuera de pantalla (no roba el foco).
if CommandLine.arguments.contains("--centro-de-mando") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    Nube.cargarConfig()
    let sem = DispatchSemaphore(value: 0)
    Task { @MainActor in
        await Cronista.compartido.cargarUnaVez()
        Escenas.centroDeMandoFueraDePantalla()
        if let pg = try? await Nube.abrir("a91ada07-5a25-4307-a79a-4f0bb2ed3fab") {
            Escenas.costeDelPanelReal(pg.elementos)
        }
        sem.signal()
    }
    while sem.wait(timeout: .now() + 0.02) == .timedOut {
        while let e = app.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
            app.sendEvent(e)
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    exit(0)
}

// La SONDA del día: enseña lo que leen las tres fuentes del centro de mando.
if CommandLine.arguments.contains("--sonda-dia") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let sem = DispatchSemaphore(value: 0)
    Task { await SondaDia.correr(); sem.signal() }
    while sem.wait(timeout: .now() + 0.02) == .timedOut {
        while let e = app.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
            app.sendEvent(e)
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    exit(0)
}

// El EXPORT de una página como asset publicable: recorte al contenido, 2x.
if let (id, salida, escala) = Foto.argumentosExport() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let sem = DispatchSemaphore(value: 0)
    Task { await Foto.exportar(id, salida, escala); sem.signal() }
    while sem.wait(timeout: .now() + 0.02) == .timedOut {
        while let e = app.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
            app.sendEvent(e)
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    exit(0)
}

// La FOTO de una página real: carga por la nube, pinta offscreen y sale.
if let (id, salida) = Foto.argumentos() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let sem = DispatchSemaphore(value: 0)
    Task { await Foto.correr(id, salida); sem.signal() }
    while sem.wait(timeout: .now() + 0.02) == .timedOut {
        while let e = app.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
            app.sendEvent(e)
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    exit(0)
}

// La hoja del CROMO corre y SALE. Va antes que nada porque no toca la nube.
if let (doc, salida) = HojaDoc.args() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    HojaDoc.generar(doc, salida)
    exit(0)
}

if let salida = HojaCromo.ruta() {
    Fuentes.registrar()
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    HojaCromo.generar(salida)
    exit(0)
}

// El BANCO DE TRAZOS corre y SALE. No monta ventana ni toca la nube: su
// fixture está en el repo a propósito, para que la comparación se pueda repetir
// dentro de un año sin depender de que una fila de la base siga existiendo.
if let salida = BancoTinta.ruta() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    BancoTinta.generar(salida)
    exit(0)
}

// La hoja de iconos corre y SALE: no monta ventana ni toca la nube.
if let salida = HojaIconos.ruta() {
    Fuentes.registrar()
    HojaIconos.generar(salida)
    exit(0)
}

let app = NSApplication.shared
let delegado = Delegado()
app.delegate = delegado
app.setActivationPolicy(.regular)
app.run()

/// El nombre de la carpeta de una página, o nil.
func ps_carpeta(_ ps: [ResumenPagina], _ cs: [Carpeta], _ id: String) -> String? {
    guard let f = ps.first(where: { $0.id == id })?.folderId else { return nil }
    return cs.first { $0.id == f }?.nombre
}
