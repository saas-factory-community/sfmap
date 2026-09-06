import AppKit
import UniformTypeIdentifiers

/**
 * LA VISTA DEL LIENZO. Aquí vive la latencia.
 *
 * Tres decisiones que la explican, y ninguna es un truco:
 *
 * 1. `wantsLayer` + `layerContentsRedrawPolicy = .onSetNeedsDisplay`. El frame
 *    se pinta cuando algo cambia, no en un bucle. Un lienzo quieto no gasta.
 * 2. El evento toca la cámara y llama a `needsDisplay` en la MISMA vuelta. No
 *    hay estado intermedio, ni React, ni un `requestAnimationFrame` que espere
 *    a la siguiente vuelta del bucle del navegador.
 * 3. `CATransaction` sin animación implícita. Sin esto, Core Animation
 *    interpola cada cambio de capa y añade fotogramas de retraso a un gesto que
 *    ya sabía su destino.
 *
 * Y aquí vive también la MÁQUINA DE PUNTEROS, que en el lienzo web se llamaba
 * "la pieza frágil" con razón: es donde se cruzan los sistemas de entrada que
 * nadie coordina. En macOS son menos que en un iPad —no hay palma, ni lápiz, ni
 * gestos de WebKit en paralelo— así que el puerto se queda con las reglas que
 * SÍ aplican y no arrastra las que no.
 */
final class Lienzo: NSView {

    let doc = Documento()
    /// EL MODO CLASE (`F5`). Vive en memoria: un revelado a medias jamás se
    /// guarda en el documento. Ver `Enactar.swift`.
    let enact = Enactar.Estado()
    /// Los diales de los MECANISMOS. También en memoria: mover la mano en
    /// cámara no puede escribir en `draw`. Ver `Mecanismo.swift`.
    let meca = Mecanismo.Estado()
    var tema = Tema.claro { didSet { needsDisplay = true } }
    var fondo: Fondo = .puntos { didSet { needsDisplay = true } }
    var camara = Camara() { didSet { needsDisplay = true; alMoverCamara?(camara.zoom) } }
    var herramienta: Herramienta = .seleccionar {
        didSet {
            guard herramienta != oldValue else { return }
            cursorParaHerramienta()
            if herramienta != .seleccionar { doc.seleccion = []; avisarSeleccion() }
            /*
             * AL COGER LA GOMA SE DICE QUÉ GOMA ES.
             *
             * Su alcance por defecto es `tinta`, y esa decisión —la buena, la
             * que deja anotar sobre un diagrama sin arriesgarlo— tiene un
             * precio: pasarla sobre una caja no hace NADA, y "no hace nada" es
             * indistinguible de "está rota". El aviso lo cuenta en el momento
             * exacto en que importa, sin abrir ningún panel.
             */
            if herramienta == .goma {
                mostrarAviso("Goma · \(Int(goma.grosor)) · \(goma.alcance.nombre.lowercased())",
                             muestra: goma.grosor)
            }
            alCambiarHerramienta?()
            needsDisplay = true
        }
    }
    var tinta: (color: String?, grosor: Double) = (nil, 4)
    /**
     * LA GOMA TIENE SU PROPIO TAMAÑO, y no es un capricho de simetría.
     *
     * Compartía el grosor con el lápiz —"cambiar de herramienta no cambia de
     * pronto la escala de la mano"— y esa frase es verdad entre lápiz y
     * marcador, que escriben. Una goma no escribe: se usa gorda para limpiar
     * una zona y el lápiz fino para corregirla, y con el valor compartido
     * ajustar una arruinaba la otra en cada ida y vuelta.
     *
     * Se recuerda entre sesiones porque es un ajuste de mano, no de documento.
     */
    var goma = Goma() {
        didSet {
            UserDefaults.standard.set(goma.grosor, forKey: "sfmap.goma.grosor")
            UserDefaults.standard.set(goma.alcance.rawValue, forKey: "sfmap.goma.alcance")
            needsDisplay = true
        }
    }

    var alMoverCamara: ((Double) -> Void)?
    var alCambiar: ((_ persistente: Bool) -> Void)?
    var alSeleccionar: (() -> Void)?
    /// Escape: el llamador cierra sus paneles flotantes.
    var alEscapar: (() -> Void)?
    /// Cambiar de tema con la T pelada. Lo resuelve el dueño de la ventana:
    /// el tema no es del lienzo, es de la app entera.
    var alTema: (() -> Void)?
    /// Ir al lienzo en la POSICION n (0-9) de la carpeta abierta.
    var alIrAPagina: ((Int) -> Void)?
    /// Ir al lienzo vecino de la carpeta abierta: -1 anterior, +1 siguiente.
    var alPaginaVecina: ((Int) -> Void)?
    /// Plegar o desplegar en el panel la carpeta donde esta el cursor.
    var alAlternarCarpeta: (() -> Void)?
    /// Mover el cursor a la carpeta anterior (-1) o siguiente (+1). NO abre
    /// ningun lienzo: solo cambia donde apunta el teclado.
    var alCarpetaVecina: ((Int) -> Void)?
    /// Enseñar en el rail el panel de la herramienta que se acaba de elegir.
    var alEnseñarGrupo: ((Herramienta) -> Void)?
    /// Se toco el lienzo: lo que flote sobre el y no le pertenezca, se cierra.
    var alTocarLienzo: (() -> Void)?
    var alPedirMenu: ((NSPoint, Elemento?) -> Void)?
    var alAbrirEnlace: ((String) -> Void)?
    /// Cerrar una tarea de Todoist desde su casilla. Lo cablea `main.swift`.
    var alCerrarTarea: ((String) -> Void)?
    /**
     * LA HERRAMIENTA SE QUEDA PUESTA tras crear.
     *
     * Daniel: *"si inserto un rectángulo, en lugar de volver a dar otro clic a
     * la herramienta, se conserva, de modo que puedo insertar múltiples
     * rectángulos rápidamente"*. Es lo correcto: dibujar un diagrama es poner
     * ocho cajas seguidas, y volver a `seleccionar` después de cada una cobra un
     * viaje al rail por caja.
     *
     * La salida es ESCAPE, que ya devuelve a seleccionar, y la tecla V. El
     * cierre sigue existiendo para que la app pueda sincronizar el rail cuando
     * la herramienta cambie por teclado.
     */
    var alCambiarHerramienta: (() -> Void)?
    /// Aviso de un cambio de grosor hecho con la rueda o un atajo.
    var alCambiarGrosor: ((Double) -> Void)?
    /// El rail tiene que enterarse: si su panel está abierto, la muestra
    /// marcada debe seguir al dial. Un panel que enseña otro valor que el que
    /// está puesto es peor que no enseñar ninguno.
    var alCambiarGoma: ((Goma) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Al cambiar de tamaño se repinta TODO, no solo lo que creció.
    override func setFrameSize(_ nuevo: NSSize) {
        let cambio = nuevo != frame.size
        super.setFrameSize(nuevo)
        if cambio { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        /*
         * ⚠️ CAMBIAR DE TAMAÑO INVALIDA EL LIENZO ENTERO.
         *
         * Con `.onSetNeedsDisplay` el layer solo se repinta cuando se pide, y al
         * crecer la vista AppKit marca sucia ÚNICAMENTE la franja nueva. Todo lo
         * demás conserva los píxeles del tamaño anterior.
         *
         * En un lienzo eso no es un detalle: la cámara se centra en
         * `bounds.width/2`, así que un cambio de tamaño mueve TODO el contenido.
         * El resultado medido el 20 ago 2026 era un rectángulo de 655×148 arriba
         * a la izquierda con el encuadre viejo congelado —sin retícula, con otro
         * color— que sobrevivía indefinidamente. Se ve exactamente como "la vista
         * en puntitos falla", que es como Daniel lo reportó.
         *
         * No falla nada y no hay error: hay una zona de la ventana que enseña un
         * fotograma de hace rato.
         */
        layer?.needsDisplayOnBoundsChange = true
        doc.alCambiar = { [weak self] persistente in
            self?.needsDisplay = true
            self?.alCambiar?(persistente)
        }
        doc.alSeleccionar = { [weak self] in self?.avisarSeleccion() }
    }
    required init?(coder: NSCoder) { fatalError() }

    var elementos: [Elemento] { doc.elementos }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: estado de interacción
    // ════════════════════════════════════════════════════════════════════════

    private enum Gesto {
        case ninguno
        case pan(NSPoint)
        case arrastre(inicio: CGPoint, ultimo: CGPoint, movio: Bool, activaAlSoltar: Bool)
        case marco(CGPoint, CGPoint)
        case elastico(Herramienta, CGPoint, CGPoint)
        case redimensionar(String, CGPoint, CGRect, [String: CGRect])
        case girar(CGPoint)
        case conectando(desde: String, puerto: String?, inicio: CGPoint, actual: CGPoint, movio: Bool)
        case doblar(id: String, indice: Int)
        /// Reenganchar un extremo de una flecha a otra cosa.
        case extremo(id: String, cual: String, actual: CGPoint)
        case dibujar([PuntoTinta])
        /// La goma no borra mientras pasa: MARCA. Lo marcado se pinta
        /// fantasma y se confirma entero al soltar — ver `marcarGoma`.
        case borrar(Set<String>)
        /// El dial de un MECANISMO. No mueve el elemento: mueve su VALOR, y el
        /// dibujo responde. Ver `Mecanismo.swift`.
        case dial(String)
    }
    private var gesto: Gesto = .ninguno {
        didSet {
            /*
             * LA FUSIÓN DE EVENTOS SE RESTAURA AQUÍ, y no en `mouseUp`.
             *
             * Se apaga al empezar un trazo para que la Kamvas entregue sus 260
             * muestras por segundo en vez de las ~60 a las que macOS las
             * agrupa. Restaurarla en `mouseUp` parecía suficiente y no lo era:
             * **Escape abandona un gesto a media línea** sin pasar por ahí, y
             * por esa puerta la fusión se quedaba apagada para el resto de la
             * vida del proceso — cobrándole eventos de más a cada arrastre de
             * toda la app, en silencio.
             *
             * Puesto en el `didSet` del gesto, la restauración no se puede
             * olvidar: no hay forma de dejar de dibujar sin pasar por aquí.
             */
            if case .dibujar = gesto { return }
            if case .dibujar = oldValue { NSEvent.isMouseCoalescingEnabled = true }
        }
    }
    /// Marca de tiempo del `mouseDown` que abrió el trazo. Los tiempos se
    /// guardan RELATIVOS a él: absolutos serían segundos desde el arranque de
    /// la máquina, un número enorme que no dice nada y ocupa en cada punto.
    private var inicioTrazo: TimeInterval = 0

    /**
     * Un punto de la pluma con todo lo que el evento sabe.
     *
     * Hasta hoy sfmap leía `pressure` y tiraba el resto. La PW600L manda
     * además INCLINACIÓN (±60° por eje) y el evento trae su propio reloj; con
     * eso el motor puede hacer dos cosas que sin ellas son imposibles:
     * plumilla que responde al ángulo, y ancho que responde a la velocidad de
     * verdad en vez de a la distancia entre muestras —que no es lo mismo en
     * cuanto cambia la cadencia del dispositivo.
     *
     * `subtype` decide: un ratón no tiene ángulo, y escribir (0,0) como si lo
     * tuviera sería un dato inventado. Sin tableta, los campos no se ponen.
     */
    private func puntoDePluma(_ e: NSEvent, _ w: CGPoint) -> PuntoTinta {
        /*
         * SE CUANTIZA AQUÍ, no al guardar.
         *
         * Un `Double` de la pluma imprime 17 cifras y el documento viaja por la
         * red: con la fusión de eventos apagada un trazo son 600 puntos, y a
         * 88 bytes por punto una página de escritura pesa megas. Centésimas de
         * unidad de mundo son una centésima de píxel al zoom 1 — nadie las ve.
         *
         * Y se recorta en la CAPTURA, no en el guardado, para que el borrador
         * en vivo y el elemento guardado tengan exactamente los mismos números.
         * Recortar al guardar dejaría dos geometrías que difieren en el último
         * decimal, y "casi el mismo píxel" no es lo que promete el motor.
         */
        var q = PuntoTinta(x: redondear(w.x, 2), y: redondear(w.y, 2),
                           p: redondear(Double(e.pressure), 4))
        q.t = redondear(max(0, (e.timestamp - inicioTrazo) * 1000), 1)
        if e.subtype == .tabletPoint {
            let t = e.tilt
            // La Y del lienzo va hacia ABAJO (convenio del canvas web) y la del
            // evento hacia arriba. Sin este giro, la plumilla saldría espejada
            // en el eje que decide el ángulo de la caligrafía.
            q.ix = redondear(Double(t.x), 4)
            q.iy = redondear(-Double(t.y), 4)
        }
        return q
    }

    /// Recorta decimales antes de guardar. Un `Double` de la pluma imprime 17
    /// cifras y el documento se comparte por la red: los dígitos que nadie
    /// puede ver cuestan bytes en cada punto de cada trazo.
    private func redondear(_ v: Double, _ d: Int) -> Double {
        let f = pow(10.0, Double(d))
        return (v * f).rounded() / f
    }
    private var guias: [Geo.Guia] = []
    private var hover: (id: String, puerto: String?)?
    private var espacio = false
    /// ¿El puntero está DENTRO de la ventana? Sin este dato, `hover` sobrevive a
    /// que la mano se vaya al teclado y los puertos se quedan pintados.
    private var punteroDentro = false
    /// Donde esta el puntero, en el mundo. Lo usa la flechita de giro.
    private var punteroMundo: CGPoint?
    /// Posición de pantalla del puntero, para dibujar la goma encima del lienzo.
    private var punteroVista: CGPoint?
    private var ultimoClic: (id: String, cuando: TimeInterval)?
    private var editor: EditorTexto?
    private var seguimiento: NSTrackingArea?

    /// El elemento que se está editando NO se pinta: si no, se ve el texto dos
    /// veces, ligeramente desalineado. Es un fallo que el v3 tenía listado.
    private var editandoId: String? { editor?.editando }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: pintar
    // ════════════════════════════════════════════════════════════════════════

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // AppKit puede entregar el contexto después de haber pintado una
        // etiqueta hermana. El estado de texto no forma parte de todos los
        // estados gráficos que AppKit restaura; dejarlo explícito evita que un
        // lienzo dependa del último texto pintado fuera de él.
        ctx.textMatrix = .identity
        ctx.textPosition = .zero
        let p = Pintor(ctx: ctx, tema: tema, camara: camara, tamano: bounds.size,
                       dia: Cronista.compartido.estado)
        /*
         * EN MODO CLASE EL FONDO SE APAGA — y no es sólo estética.
         *
         * MEDIDO el 26 ago con `--medir`: la retícula cuesta 9.1 ms de un
         * fotograma de 20.9 en el lienzo 01, con el presupuesto en 8.3 ms. Es
         * la mitad del fotograma pintando puntos que, mientras se dicta, no
         * orientan a nadie: el alumno mira el dibujo, no la cuadrícula del
         * cuaderno. Apagarla en clase es la única forma barata de devolverle
         * fluidez al arrastre de un dial o de una tapa delante de la cámara.
         *
         * Fuera del modo, el fondo es el que Daniel eligió en la barra.
         */
        p.fondo(puntos: !enact.activo && fondo != .liso,
                cuadricula: !enact.activo && fondo == .cuadricula)
        ctx.saveGState()
        p.aplicarCamara()

        // z ascendente, y los conectores por DEBAJO: una flecha por encima de
        // una tarjeta se lee como error aunque la geometría sea correcta.
        let visibles = doc.elementos.sorted { $0.z < $1.z }
        for e in visibles where e.tipo == "frame" { conCondena(ctx, e) { conGiro(ctx, e) { p.seccion(e) } } }
        for e in visibles where e.tipo == "connector" { conCondena(ctx, e) { p.conector(e) } }
        for e in visibles {
            /*
             * ⚠️ MIENTRAS SE EDITA SE OCULTA EL TEXTO, NO LA FIGURA.
             *
             * La regla es que el texto no se pinte dos veces (el editor encima
             * del pintado, ligeramente desalineados). La primera versión saltaba
             * el ELEMENTO ENTERO, así que una nota recién creada perdía su
             * cuerpo amarillo mientras escribías: parecía que el color no
             * funcionaba, cuando lo que no se pintaba era la nota.
             */
            let editando = e.id == editandoId
            if editando && e.tipo == "text" { continue }
            let e = editando ? e.sinTexto : e
            // EL MODO CLASE decide si este elemento ya existe (y con qué gesto
            // entra). Fuera del modo, `conEscena` pinta y devuelve true.
            _ = Enactar.conEscena(ctx, e, enact) {
            conCondena(ctx, e) { conGiro(ctx, e) {
                switch e.tipo {
                // Un MECANISMO se pinta con su valor vivo, no con su caja.
                case _ where Mecanismo.esMecanismo(e):
                    Mecanismo.pintar(e, ctx, tema, valor: meca.valor(e),
                                     senalado: meca.senalado(de: e),
                                     lazo: Mecanismo.tipo(e) == "lazo" ? meca.lazo(e) : nil)
                case "shape": p.figura(e)
                case "text":  p.bloqueTexto(e)
                case "ink":   p.tinta(e)
                case "table": p.tabla(e)
                case "code":  p.codigo(e)
                case "image": p.imagen(e) { [weak self] in self?.needsDisplay = true }
                case "embed": p.embed(e)
                default: break
                }
            } }
            }
        }

        // ── superposiciones ─────────────────────────────────────────────────
        // EL VELO DEL RECORTE va ANTES que la selección: mientras se recorta,
        // lo que importa es qué se queda y qué se va, no qué está marcado.
        if let r = recorte { pintarVeloRecorte(ctx, r) }
        let sel = doc.seleccionados
        if !sel.isEmpty {
            p.seleccion(sel)
            // Las manijas solo con UN elemento o con la caja común: redimensionar
            // varios a la vez usa la caja de la unión, que es lo que Figma hace.
            if herramienta == .seleccionar, let r = cajaDeManijas() {
                p.manijas(r)
                // Y la flechita de giro, si el puntero esta en una esquina.
                // La condicion es TENER punto, no `punteroDentro`: esa bandera
                // solo se enciende con `mouseEntered`, y el hover de los puertos
                // —que se pinta al lado— nunca dependio de ella.
                if let w = punteroMundo,
                   let esq = Geo.giroEnEsquina(r, w, zoom: camara.zoom) { p.flechaGiro(r, esq) }
            }
        }
        if !guias.isEmpty { p.guias(guias) }
        // Los codos de un conector seleccionado se ven: un punto que se puede
        // agarrar y no se pinta es una capacidad que nadie descubre.
        for e in sel where e.tipo == "connector" {
            p.codos(e.crudo["waypoints"]?.arr?.map {
                CGPoint(x: $0["x"]?.num ?? 0, y: $0["y"]?.num ?? 0)
            } ?? [])
            // Y sus DOS extremos, que son lo unico agarrable de una flecha.
            if case .extremo(let id, let cual, _) = gesto, id == e.id { p.extremos(e, agarrado: cual) }
            else { p.extremos(e) }
        }

        switch gesto {
        case .marco(let a, let b): p.marco(normalizar(a, b))
        case .elastico(let h, let a, let b):
            let caja = normalizar(a, b)
            p.fantasma(h == .seccion ? "rect" : h.rawValue, caja)
        case .conectando(let desde, let puerto, _, let actual, _):
            if let origen = doc.porId(desde) {
                let obs = Conectores.obstaculoDe(origen)
                let salida = Ruteo.anclaje(obs, hacia: actual, holgura: 0, lado: puerto)
                // El MISMO cálculo que decide al soltar. Dos cálculos distintos
                // harían que la pantalla prometa una cosa y el gesto haga otra.
                let objetivo = Geo.candidatoConexion(doc.elementos, actual, zoom: camara.zoom, excluir: desde)
                if let o = objetivo { p.resaltarObjetivo(o) }
                p.conectando(salida, actual, sobre: objetivo != nil)
                // El FANTASMA de lo que va a nacer si sueltas en el VACÍO. Sale
                // del mismo cálculo que la figura real: escribirlo dos veces
                // haría que el fantasma prometa un sitio y la figura aparezca en
                // otro, que es peor que no tener fantasma.
                if objetivo == nil { p.fantasma("rect", Crear.cajaFantasma(origen.caja, actual)) }
            }
        case .extremo(let id, let cual, let actual):
            // La MISMA cuenta que decide al soltar: si la pantalla promete un
            // objetivo y el gesto engancha otro, la mano deja de creerle.
            if let conn = doc.porId(id) {
                let fijo = cual == "desde" ? conn.hastaId : conn.desdeId
                let objetivo = Geo.candidatoConexion(doc.elementos, actual, zoom: camara.zoom,
                                                     excluir: fijo ?? "")
                if let o = objetivo { p.resaltarObjetivo(o) }
                let otro = cual == "desde" ? conn.ruta.last : conn.ruta.first
                if let otro { p.conectando(otro, actual, sobre: objetivo != nil) }
            }

        case .dibujar(let pts):
            p.tintaEnVivo(pts, color: tinta.color.flatMap { NSColor(hex: $0) } ?? tema.tinta,
                          grosor: tinta.grosor, marcador: herramienta == .marcador)
        default: break
        }

        /*
         * LOS PUERTOS SOLO CON EL PUNTERO ENCIMA.
         *
         * Daniel: *"a menos que tenga el mouse en el hover, evita mostrar los
         * puntitos; si solo estoy escribiendo en el teclado no necesito ver los
         * puntos a los lados, solo el componente"*. Exacto: mientras escribes,
         * cuatro círculos flotando alrededor de la caja son ruido sobre lo único
         * que estás mirando.
         *
         * Y `hover` no se limpiaba nunca: se quedaba pegado desde el último
         * movimiento del ratón, así que los puertos seguían pintados minutos
         * después de que la mano se fuera al teclado.
         */
        if editandoId == nil, let h = hover, punteroDentro,
           let e = doc.porId(h.id), Geo.aceptaPuertos(e),
           herramienta == .seleccionar || Herramienta.flechas.contains(herramienta) {
            p.puertos(e, activo: h.puerto)
        }
        ctx.restoreGState()
        if herramienta == .goma, let p = punteroVista { discoDeGoma(ctx, p) }
        if let h = hud { pintarHud(ctx, h) }
        // Al final del todo, en coordenadas de VISTA: el canto del marco sobre
        // la pantalla va encima del contenido, como una sombra de verdad.
        Estilo.cantoHundido(self, tema)
    }

    /// Aplica el giro del elemento alrededor de su centro.
    ///
    /// Vive junto al pintado y NO dentro de cada figura porque el hit-test hace
    /// la operación inversa en un solo sitio: si el giro se aplicara pieza por
    /// pieza, la primera que se olvidara se vería en un lado y se agarraría en
    /// otro — exactamente el fallo del v3.
    private func conGiro(_ ctx: CGContext, _ e: Elemento, _ cuerpo: () -> Void) {
        guard Geo.estaGirado(e) else { cuerpo(); return }
        ctx.saveGState()
        ctx.translateBy(x: e.caja.midX, y: e.caja.midY)
        ctx.rotate(by: e.giro)
        ctx.translateBy(x: -e.caja.midX, y: -e.caja.midY)
        cuerpo()
        ctx.restoreGState()
    }

    /// Lo condenado por la goma se pinta APAGADO, en su sitio y con su forma.
    /// Sale del MISMO conjunto que se borra al soltar: una lista aparte para
    /// pintar acabaría prometiendo una cosa y llevándose otra.
    private func conCondena(_ ctx: CGContext, _ e: Elemento, _ cuerpo: () -> Void) {
        // Yendose: se apaga y se encoge desde su PROPIO centro. Escalar desde
        // el origen del mundo lo mandaria de viaje hacia la esquina, que se
        // leeria como "se movio" y no como "se fue".
        if let vida = vidaDesvanecida(e.id) {
            let caja = e.caja
            ctx.saveGState()
            ctx.setAlpha(vida)
            ctx.translateBy(x: caja.midX, y: caja.midY)
            // Hasta 0.82 y no hasta 0: encogerlo del todo lo convierte en un
            // punto que se va, y lo que paso no es que se alejara.
            ctx.scaleBy(x: 0.82 + 0.18 * vida, y: 0.82 + 0.18 * vida)
            ctx.translateBy(x: -caja.midX, y: -caja.midY)
            cuerpo()
            ctx.restoreGState()
            return
        }
        guard marcadoPorLaGoma(e.id) else { cuerpo(); return }
        ctx.saveGState()
        ctx.setAlpha(0.18)
        cuerpo()
        ctx.restoreGState()
    }

    /**
     * EL DISCO DE LA GOMA — y es EXACTAMENTE lo que borra.
     *
     * Se pinta en coordenadas de VISTA, con el radio que sale de `Goma`, que es
     * el mismo que pregunta el gesto. Antes se dibujaba un disco de un tamaño y
     * se borraba por un PUNTO: la mano aprendía a apuntar en vez de a pasar.
     *
     * Tres capas y ninguna es adorno: un halo oscuro por fuera y un filo claro
     * por dentro hacen que el anillo se lea sobre el lienzo blanco Y sobre el
     * negro —un solo trazo desaparece contra uno de los dos— y el punto del
     * centro dice dónde está el ratón cuando el disco es enorme.
     */
    private func discoDeGoma(_ ctx: CGContext, _ p: CGPoint) {
        let r = goma.radioPantalla(zoom: camara.zoom)
        let caja = NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        var borrando = false
        if case .borrar = gesto { borrando = true }
        // Morado = el modo de la máquina; el rojo del rol `risk` solo aparece
        // cuando de verdad hay algo condenado. Un instrumento que se pinta de
        // peligro en reposo enseña a ignorar el peligro.
        let vivo = borrando ? tema.rol("risk").trazo.color : tema.acento

        ctx.saveGState()
        ctx.setFillColor(vivo.withAlphaComponent(borrando ? 0.16 : 0.07).cgColor)
        ctx.fillEllipse(in: caja)

        ctx.setLineWidth(3.5)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.28).cgColor)
        ctx.strokeEllipse(in: caja)

        ctx.setLineWidth(1.6)
        ctx.setStrokeColor(vivo.cgColor)
        ctx.strokeEllipse(in: caja)

        ctx.setLineWidth(0.75)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        ctx.strokeEllipse(in: caja.insetBy(dx: 1.4, dy: 1.4))

        if r > 9 {
            ctx.setFillColor(vivo.withAlphaComponent(0.9).cgColor)
            ctx.fillEllipse(in: NSRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3))
        }
        ctx.restoreGState()
    }

    // ── el aviso de tamaño ──────────────────────────────────────────────────

    /**
     * EL AVISO DEL DIAL.
     *
     * El dial de la tableta cambia el grosor sin que la mano suelte la pluma ni
     * mire el rail — ése es todo el punto de tenerlo. Pero un control que
     * responde sin decir que respondió es, para la mano, un control roto: hasta
     * que no dibujas no sabes en qué número te dejó. El aviso enseña el número Y
     * el disco a tamaño real, abajo y en medio, donde no tapa lo que estás
     * trazando, y se va solo.
     */
    struct Aviso {
        var texto: String
        var muestra: Double        // diámetro en px de PANTALLA — el DESTINO
        var alfa: Double = 1
        /// El diámetro que se está PINTANDO ahora mismo, camino del destino.
        ///
        /// ⚠️ La mancha saltaba de un tamaño a otro y con eso el HUD decía el
        /// número pero no el CAMBIO: girando la rueda rápido, lo único que se
        /// veía era una bola parpadeando. Daniel: *"me gustaría ver cómo cambia
        /// el grosor con una ligera animación"*. Interpolar entre el tamaño
        /// anterior y el nuevo convierte un dato en un gesto — y de paso dice
        /// hacia dónde vas, que es lo que la mano quiere saber mientras gira.
        var pintada: Double = 0
    }
    private(set) var hud: Aviso?
    private var relojHud: Timer?

    func mostrarAviso(_ texto: String, muestra: Double) {
        // Se arranca desde donde estaba la mancha anterior, no desde cero: si
        // el HUD sigue vivo (rueda girando), el crecimiento es continuo en vez
        // de reiniciarse en cada paso.
        let desde = hud?.pintada ?? muestra
        hud = Aviso(texto: texto, muestra: muestra, pintada: desde)
        needsDisplay = true
        relojHud?.invalidate()
        var vividos = 0.0
        // Un temporizador y no una animación de Core Animation: esto se pinta
        // dentro del `draw` del lienzo, que no es una capa con propiedades
        // animables. 30 pasos por segundo bastan para un desvanecido de 0.3 s.
        relojHud = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] t in
            guard let s = self else { t.invalidate(); return }
            vividos += 1.0 / 30
            // La mancha persigue su destino con un acercamiento exponencial:
            // rápido al principio, suave al llegar. Sin pasos que contar y sin
            // saltos cuando la rueda cambia el destino a media animación.
            if let h = s.hud, abs(h.pintada - h.muestra) > 0.05 {
                s.hud?.pintada = h.pintada + (h.muestra - h.pintada) * 0.34
                s.needsDisplay = true
            }
            if vividos < 0.9 { return }
            let a = 1 - (vividos - 0.9) / 0.3
            if a <= 0 { s.hud = nil; t.invalidate() } else { s.hud?.alfa = a }
            s.needsDisplay = true
        }
    }

    private func pintarHud(_ ctx: CGContext, _ a: Aviso) {
        let f = Estilo.mono(12, 600)
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: tema.tituloTexto]
        let medida = (a.texto as NSString).size(withAttributes: attrs)
        // El HUECO se reserva con el destino y la MANCHA se pinta con lo
        // animado: si la píldora midiera lo que crece, la caja entera latiría
        // y el ojo perdería el número, que es lo que se está leyendo.
        let hueco = min(a.muestra, 26.0)
        let d = min(max(a.pintada, 1), 26.0)
        let alto: CGFloat = 34
        let ancho = medida.width + hueco + 34
        let caja = NSRect(x: (bounds.width - ancho) / 2, y: bounds.height - alto - 26,
                          width: ancho, height: alto)
        ctx.saveGState()
        ctx.setAlpha(a.alfa)
        let camino = CGMutablePath()
        camino.addRoundedRect(in: caja, cornerWidth: alto / 2, cornerHeight: alto / 2)
        ctx.addPath(camino)
        ctx.setFillColor(tema.rol("card").relleno.withAlphaComponent(0.96).cgColor)
        ctx.fillPath()
        ctx.addPath(camino)
        ctx.setStrokeColor(tema.rol("card").trazo.color.cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
        // La muestra va a TAMAÑO REAL hasta donde cabe en la píldora: el número
        // dice cuánto, la mancha dice cuánto se siente.
        ctx.setFillColor(tema.acento.cgColor)
        ctx.fillEllipse(in: NSRect(x: caja.minX + 14 + (hueco - d) / 2, y: caja.midY - d / 2,
                                   width: d, height: d))
        (a.texto as NSString).draw(at: NSPoint(x: caja.minX + 14 + hueco + 10, y: caja.midY - medida.height / 2),
                                   withAttributes: attrs)
        ctx.restoreGState()
    }

    private func normalizar(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: cámara
    // ════════════════════════════════════════════════════════════════════════

    /**
     * DONDE CAE LO QUE SE PEGA: bajo el raton.
     *
     * Caia en el centro de la vista, y eso obliga a un segundo gesto SIEMPRE:
     * pegas, y lo primero que haces es arrastrarlo a donde lo querias. Daniel,
     * 26 ago: *"cuando pegue un objeto, que se posicione justo donde tengo el
     * mouse"*. El raton ya dice donde: es la unica informacion de intencion
     * que hay en el momento de pegar, y estaba tirandose.
     *
     * ⚠️ Con el fallback, que no es un detalle: `⌘V` desde el MENU se puede
     * pulsar con el puntero fuera del lienzo (sobre el panel, sobre la barra,
     * fuera de la ventana). Ahi el raton no dice nada util, y pegar en unas
     * coordenadas de fuera de pantalla se lee como "no pego nada". Sin punto
     * fiable, el centro de la vista — que al menos siempre se ve.
     */
    func puntoDePegado() -> CGPoint {
        guard let v = window?.mouseLocationOutsideOfEventStream else {
            return aMundo(NSPoint(x: bounds.midX, y: bounds.midY))
        }
        let local = convert(v, from: nil)
        guard bounds.contains(local) else {
            return aMundo(NSPoint(x: bounds.midX, y: bounds.midY))
        }
        return aMundo(local)
    }

    func aMundo(_ p: NSPoint) -> CGPoint {
        CGPoint(x: (p.x - bounds.width / 2) / camara.zoom + camara.x,
                y: (p.y - bounds.height / 2) / camara.zoom + camara.y)
    }

    /*
     * QUIÉN manda cada scroll — medido con una sonda el 23 ago 2026 sobre los
     * aparatos de este escritorio (100 eventos):
     *
     *   rueda vertical del ratón → pid 0 (HID real), SIN precisión, |Δ| 0.1–6.9
     *   rueda horizontal (Logi)  → pid del agente de OpenLogi, SIN precisión, |Δ| 7–100
     *   trackpad                 → deltas PRECISOS
     *
     * Por eso `!hasPreciseScrollingDeltas` NO reconoce al dial de la tableta:
     * mete al ratón entero en la misma bolsa. Con esa condición —la de ayer— la
     * rueda vertical hacía ZOOM en vez de mover, y la horizontal no hacía NADA,
     * porque la rama de zoom solo lee `scrollingDeltaY` y en un giro horizontal
     * vale 0. El contrato de la hoja de atajos manda: la rueda PANEA; el zoom
     * pide ⌘/⌃, pellizco, ⌘+/⌘− — o el dial, que sí se distingue por su origen.
     */
    override func scrollWheel(with e: NSEvent) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        /*
         * LA SEGUNDA RUEDA DE LA TABLETA — la de abajo — AL GROSOR.
         *
         * ⚠️ Las dos ruedas de la Kamvas son INDISTINGUIBLES por procedencia:
         * `esDialDeTableta` mira que PROCESO manda el evento (el driver de
         * Huion), y las dos salen del mismo. Lo unico que puede separarlas es
         * el EJE: si el driver tiene la de abajo mapeada a desplazamiento
         * horizontal, llega como deltaX y aqui se puede leer.
         *
         * Es una hipotesis, no un hecho: si tu driver manda las dos en
         * vertical, esta rama no salta nunca y no rompe nada — la rueda se
         * mapea entonces a `[` y `]` en la app de Huion, que ya estan
         * cableadas al grosor. Por eso va la sonda de debajo: en vez de
         * adivinar dos veces, que el aparato lo diga.
         */
        if vieneDelDialDeLaTableta(e) {
            if ProcessInfo.processInfo.environment["SFMAP_SONDA_DIAL"] != nil {
                FileHandle.standardError.write(Data(
                    "DIAL dx=\(e.scrollingDeltaX) dy=\(e.scrollingDeltaY) precis=\(e.hasPreciseScrollingDeltas) fase=\(e.phase.rawValue)\n".utf8))
            }
            if abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) * 1.5, abs(e.scrollingDeltaX) > 0.5 {
                ajustarGrosor(e.scrollingDeltaX > 0 ? 1 : -1)
                return
            }
        }
        if e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control)
            || vieneDelDialDeLaTableta(e) {
            /*
             * ⚠️ ARRIBA ACERCA, ABAJO ALEJA. Petición de Daniel, y es la
             * convención de todo lo demás: la rueda hacia adelante te mete en el
             * contenido. Estaba al revés — se heredó el signo de la web sin
             * comprobar de qué lado cae `scrollingDeltaY` en macOS.
             *
             * El delta se ACOTA antes de exponenciarlo: sin acotar, una muesca
             * de ratón (±100) lleva el zoom de 100% a 272%, porque la misma
             * expresión calibrada para un trackpad da un salto absurdo con el
             * otro aparato.
             */
            let d = max(-50, min(50, e.scrollingDeltaY))
            zoomEn(punto: convert(e.locationInWindow, from: nil), factor: exp(d * 0.005))
        } else {
            // Sin ganancia inventada: el lienzo recorre los MISMOS píxeles que
            // el sistema pide desplazar, así la rueda se siente igual aquí que
            // en cualquier otra ventana. Dividir entre el zoom es lo que hace
            // que el recorrido EN PANTALLA no dependa de la escala.
            camara.x -= e.scrollingDeltaX / camara.zoom
            camara.y -= e.scrollingDeltaY / camara.zoom
        }
    }

    /// El dial de la Kamvas —cuando el driver lo mapea a "rueda de ratón"—
    /// llega como un evento SINTÉTICO posteado por el proceso de Huion. Ese es
    /// el único rasgo fiable que lo separa del ratón de verdad, que entra por el
    /// HID del sistema con pid 0. Se cachea por pid porque resolver el proceso
    /// en cada evento sería consultar el sistema 100 veces por giro.
    private static var procesoDeTableta: [pid_t: Bool] = [:]
    /// Estático y visible: el monitor del cromo (main.swift) también necesita
    /// reconocer el dial — es el camino de zoom que más usa la mano de Daniel,
    /// y fue exactamente el que se coló al canvas con el puntero fuera de él.
    static func esDialDeTableta(_ e: NSEvent) -> Bool {
        guard let crudo = e.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID),
              crudo > 0 else { return false }          // pid 0 = aparato real
        let pid = pid_t(crudo)
        if let ya = procesoDeTableta[pid] { return ya }
        var quien = ""
        if let app = NSRunningApplication(processIdentifier: pid) {
            quien = ((app.bundleIdentifier ?? "") + " " + (app.localizedName ?? "")).lowercased()
        }
        if quien.isEmpty {   // procesos sin cara: el driver puede no ser una app
            var buf = [CChar](repeating: 0, count: 256)
            if proc_name(pid, &buf, UInt32(buf.count)) > 0 {
                quien = String(cString: buf).lowercased()
            }
        }
        let esTableta = quien.contains("huion") || quien.contains("tablet")
        procesoDeTableta[pid] = esTableta
        return esTableta
    }
    private func vieneDelDialDeLaTableta(_ e: NSEvent) -> Bool { Lienzo.esDialDeTableta(e) }

    /// El gancho del zoom de cromo para el TECLADO (⌘+/⌘−). Lo instala el
    /// Delegado; devuelve true si el puntero estaba sobre cromo y la UI escaló.
    static var zoomUIFueraDelLienzo: ((CGFloat) -> Bool)?

    override func magnify(with e: NSEvent) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        zoomEn(punto: convert(e.locationInWindow, from: nil), factor: 1 + e.magnification)
        CATransaction.commit()
    }

    func zoomEn(punto: NSPoint, factor: Double) {
        let antes = aMundo(punto)
        camara.zoom = max(0.02, min(20, camara.zoom * factor))
        let despues = aMundo(punto)
        camara.x += antes.x - despues.x
        camara.y += antes.y - despues.y
    }

    /// Los atajos de teclado del dial no traen coordenadas de puntero utiles.
    /// Se consulta la posicion del cursor en la ventana al momento del evento,
    /// en vez de usar el centro o la ubicacion (casi siempre cero) del evento.
    private func puntoRealDelCursor() -> NSPoint {
        guard let ventana = window else { return NSPoint(x: bounds.midX, y: bounds.midY) }
        let p = convert(ventana.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.contains(p) ? p : NSPoint(x: bounds.midX, y: bounds.midY)
    }

    /**
     * EL DIAL DE LA TABLETA MUEVE EL INSTRUMENTO QUE ESTÁ EN LA MANO.
     *
     * La rueda inferior de la Huion manda `[` y `]` (o `,` y `.`), y esto es lo
     * que hacen. Cuál grosor mueven depende de la herramienta activa: el de la
     * TINTA con el lápiz y el marcador, el de la GOMA con la goma. Lo que la
     * mano espera del dial es "más gordo esto que estoy usando", no "más gordo
     * un ajuste que a lo mejor es de otra herramienta".
     *
     * Y avisa. Un control que responde sin decir que respondió es, para la
     * mano, un control roto: sin el aviso hay que trazar para descubrir en qué
     * número te dejó, y para entonces ya has ensuciado el lienzo.
     */
    func ajustarGrosor(_ pasos: Int) {
        /*
         * LA RUEDA DE ABAJO ELIGE EL LAPIZ SI NO HABIA NINGUNO.
         *
         * Daniel, 26 ago: *"si estoy seleccionando y giro el dial no funciona;
         * entonces si giro el dial inferior automaticamente se pasa al lapiz"*.
         *
         * Y es lo correcto: esa rueda solo tiene sentido sobre algo que pinta.
         * Girarla con el puntero de seleccion en la mano no era "no hacer
         * nada", era un gesto sin destinatario — cambiabas un grosor invisible
         * que solo se veria al elegir el lapiz mas tarde. Girar la rueda ES
         * decir "voy a dibujar", asi que la herramienta viene detras.
         *
         * Solo cuando NO hay ninguna de tinta activa: si estabas en el
         * marcador o en la goma, la rueda ajusta LO TUYO y no te lo cambia.
         */
        if herramienta != .lapiz, herramienta != .marcador, herramienta != .goma {
            herramienta = .lapiz
            alCambiarHerramienta?()
        }
        if herramienta == .goma {
            let nuevo = Goma.grosorAjustado(goma.grosor, pasos: pasos)
            guard nuevo != goma.grosor else { return }
            goma.grosor = nuevo
            alCambiarGoma?(goma)
            mostrarAviso("Goma · \(Int(nuevo))", muestra: nuevo)
            alCambiarGrosor?(nuevo)
            alEnseñarGrupo?(herramienta)
            return
        }
        let nuevo = Tinta.grosorAjustado(tinta.grosor, pasos: pasos)
        guard nuevo != tinta.grosor else { return }
        tinta.grosor = nuevo
        alCambiarGrosor?(nuevo)
        mostrarAviso("\(herramienta == .marcador ? "Marcador" : "Lápiz") · \(Int(nuevo))",
                     muestra: nuevo)
        // El panel se abre mientras se gira: ahi esta la FILA de grosores, y
        // ver moverse la seleccion dice en que escalon estas y cuantos quedan
        // — cosa que un numero suelto no dice.
        alEnseñarGrupo?(herramienta)
        needsDisplay = true
    }

    func zoomA(_ z: Double) {
        let centro = NSPoint(x: bounds.midX, y: bounds.midY)
        zoomEn(punto: centro, factor: z / camara.zoom)
    }

    func alCien() { zoomA(1) }

    /// Encuadra la selección, o todo. Descuenta lo que ocupa la interfaz:
    /// encuadrar contra la ventana entera mete el contenido debajo del rail y de
    /// la barra de estado.
    func encuadrar() {
        let objetivo = doc.seleccion.isEmpty ? doc.elementos : doc.seleccionados
        guard var r = objetivo.first?.cajaVisual else { return }
        for e in objetivo.dropFirst() { r = r.union(e.cajaVisual) }
        let izq = 74.0, arriba = 60.0, abajo = 62.0, pad = 40.0
        let dispW = max(1, bounds.width - pad * 2 - izq)
        let dispH = max(1, bounds.height - pad * 2 - arriba - abajo)
        camara.zoom = max(0.02, min(1.6, min(dispW / max(1, r.width), dispH / max(1, r.height))))
        camara.x = r.midX - (izq / 2) / camara.zoom
        camara.y = r.midY - ((arriba - abajo) / 2) / camara.zoom
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: puntero
    // ════════════════════════════════════════════════════════════════════════

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let s = seguimiento { removeTrackingArea(s) }
        let s = NSTrackingArea(rect: bounds,
                               options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self)
        addTrackingArea(s); seguimiento = s
    }

    override func mouseMoved(with e: NSEvent) {
        punteroDentro = true
        let vista = convert(e.locationInWindow, from: nil)
        punteroVista = vista
        let w = aMundo(vista)
        actualizarHover(w)
        cursorParaPunto(w)
    }

    override func mouseEntered(with e: NSEvent) {
        punteroDentro = true
        punteroVista = convert(e.locationInWindow, from: nil)
        needsDisplay = true
    }

    /// Salir del lienzo APAGA los puertos. Es la mitad que faltaba: encenderlos
    /// al entrar sin apagarlos al salir los deja encendidos para siempre.
    override func mouseExited(with e: NSEvent) {
        punteroDentro = false
        if hover != nil { hover = nil }
        punteroMundo = nil
        punteroVista = nil
        needsDisplay = true
    }

    /// Al empezar a escribir, la mano deja el ratón: los puertos se apagan.
    private func apagarHover() {
        punteroDentro = false
        hover = nil
        punteroMundo = nil
        punteroVista = nil
        needsDisplay = true
    }

    /// Qué elemento ofrece sus puertos ahora mismo.
    ///
    /// Solo con el puntero cerca: pintarlos siempre llenaría el lienzo de puntos
    /// flotantes; pintarlos solo con el cursor EXACTAMENTE encima los haría
    /// parpadear al cruzar el borde. La zona viva es el elemento más el aire
    /// donde viven los puertos.
    /// EL HOVER DE UNA GRÁFICA. Va con el hover normal porque es lo mismo —
    /// «qué hay debajo del ratón»— sólo que aquí la respuesta es un PUNTO de
    /// datos, no un elemento. Repinta sólo cuando el punto cambia: mover el
    /// ratón por el lienzo no puede costar un fotograma por píxel.
    private func actualizarPuntoGrafica(_ w: CGPoint) {
        let g = doc.elementos.reversed().first {
            Mecanismo.esMecanismo($0) && Mecanismo.tipo($0) == "grafica" && $0.caja.contains(w)
        }
        let i = g.flatMap { Mecanismo.puntoEn($0, w) }
        if meca.senalar(i == nil ? nil : g?.id, i) { needsDisplay = true }
    }

    private func actualizarHover(_ w: CGPoint) {
        actualizarPuntoGrafica(w)
        if punteroMundo != w { punteroMundo = w; needsDisplay = true }
        var nuevo: (id: String, puerto: String?)?
        for e in doc.elementos.sorted(by: { $0.z > $1.z }) where Geo.aceptaPuertos(e) {
            guard Geo.cercaDe(e, w, zoom: camara.zoom) else { continue }
            nuevo = (e.id, Geo.puertoEn(e, w, zoom: camara.zoom))
            break
        }
        if nuevo?.id != hover?.id || nuevo?.puerto != hover?.puerto {
            hover = nuevo
            needsDisplay = true
        }
    }

    private func cursorParaHerramienta() {
        switch herramienta {
        case .seleccionar: NSCursor.arrow.set()
        case .mano: NSCursor.openHand.set()
        case .texto: NSCursor.iBeam.set()
        // El cursor ES la herramienta (24 ago 2026): el lápiz y el marcador se
        // ven como lo que son, y su hotspot vive en la PUNTA — la tinta nace
        // exactamente donde el instrumento toca el papel.
        case .lapiz: NSCursor.lapizHerramienta.set()
        case .marcador: NSCursor.marcadorHerramienta.set()
        // La goma NO lleva cruz: su cursor es el disco, y una cruz encima de un
        // disco de 80 px es un segundo puntero discutiendo con el primero. Un
        // punto diminuto marca el centro exacto sin pelearse con él.
        case .goma: NSCursor.puntoFino.set()
        // Todo lo que COLOCA (figuras, nota, sección, conectores, tabla…):
        // cruz fina con el glifo de insignia, hotspot en el centro de la cruz.
        default: NSCursor.colocacion(herramienta.icono).set()
        }
    }

    private func cursorParaPunto(_ w: CGPoint) {
        guard herramienta == .seleccionar else { return }
        if let caja = cajaDeManijas() {
            if let h = Geo.manijaEn(caja, w, zoom: camara.zoom) {
                if h == Geo.GIRO { NSCursor.giro.set(); return }
                switch Geo.cursorDeManija(h) {
                case .vertical: NSCursor.resizeUpDown.set()
                case .horizontal: NSCursor.resizeLeftRight.set()
                default: NSCursor.crosshair.set()
                }
                return
            }
        }
        if hover?.puerto != nil { NSCursor.crosshair.set(); return }
        NSCursor.arrow.set()
    }

    // ══════════════════════════════════════════════════════════════════════
    // MARK: recortar
    // ══════════════════════════════════════════════════════════════════════

    /// El gesto de recortar una imagen, si está en curso. La aritmética vive
    /// en `Recorte`; aquí solo el ratón, el velo y las dos teclas.
    var recorte: Recorte.Sesion?

    /// Entrar al modo. Solo con UNA imagen seleccionada: recortar "lo que haya"
    /// no significa nada, y ofrecerlo sobre una caja de texto sería una
    /// promesa que la tijera no puede cumplir.
    @discardableResult
    func iniciarRecorte() -> Bool {
        guard doc.seleccion.count == 1, let id = doc.seleccion.first,
              let e = doc.porId(id), e.tipo == "image", !e.bloqueado else { return false }
        recorte = Recorte.Sesion(id: id, caja: e.caja)
        NSCursor.crosshair.set()
        needsDisplay = true
        return true
    }

    func confirmarRecorte() {
        guard let r = recorte, let e = doc.porId(r.id) else { recorte = nil; return }
        recorte = nil
        NSCursor.arrow.set()
        // Sin arrastre no hay recorte. Salir sin tocar nada es la respuesta
        // correcta a "entré al modo y me arrepentí": no se gasta un paso de
        // deshacer ni se marca el documento como sucio.
        guard r.recorta, let ap = Recorte.aplicar(e, seleccion: r.seleccion) else {
            needsDisplay = true; return
        }
        doc.editar("recortar") { els in
            for k in els.indices where els[k].id == r.id {
                els[k].tocar(Recorte.parche(crop: ap.crop, caja: ap.caja))
            }
        }
        avisarSeleccion()
    }

    func cancelarRecorte() {
        recorte = nil
        NSCursor.arrow.set()
        needsDisplay = true
    }

    /// ¿Se puede quitar el recorte de lo seleccionado? Lo pregunta el menú.
    var puedeQuitarRecorte: Bool {
        doc.seleccionados.contains { $0.tipo == "image" && Recorte.tieneRecorte($0) }
    }

    func quitarRecorte() {
        let ids = doc.seleccion
        doc.editar("quitar recorte") { els in
            for k in els.indices where ids.contains(els[k].id) && els[k].tipo == "image" {
                els[k].tocar(Recorte.quitar(els[k]))
            }
        }
        avisarSeleccion()
    }

    /// El velo: lo que se VA queda apagado, lo que se queda sigue vivo. Es la
    /// forma de que el gesto se entienda sin leer nada — Daniel lo pidió con
    /// esas palabras: *"ver sombreado lo que voy a cortar"*.
    private func pintarVeloRecorte(_ ctx: CGContext, _ r: Recorte.Sesion) {
        ctx.saveGState()
        // El velo cubre TODO el lienzo visible menos lo que se conserva: así
        // también se apaga lo que hay alrededor de la imagen y la atención cae
        // donde tiene que caer.
        let mundo = CGRect(x: camara.x - bounds.width / camara.zoom,
                           y: camara.y - bounds.height / camara.zoom,
                           width: bounds.width * 2 / camara.zoom,
                           height: bounds.height * 2 / camara.zoom)
        let velo = CGMutablePath()
        velo.addRect(mundo)
        velo.addRect(r.seleccion)
        ctx.addPath(velo)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fillPath(using: .evenOdd)

        let g = 1.5 / camara.zoom
        ctx.setStrokeColor(tema.acento.cgColor)
        ctx.setLineWidth(g)
        ctx.stroke(r.seleccion)
        // Los tercios: la guía de encuadre de cualquier cámara. Cuesta cuatro
        // líneas y es la diferencia entre cortar a ojo y cortar bien.
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(g * 0.7)
        for i in 1...2 {
            let f = Double(i) / 3
            ctx.move(to: CGPoint(x: r.seleccion.minX + r.seleccion.width * f, y: r.seleccion.minY))
            ctx.addLine(to: CGPoint(x: r.seleccion.minX + r.seleccion.width * f, y: r.seleccion.maxY))
            ctx.move(to: CGPoint(x: r.seleccion.minX, y: r.seleccion.minY + r.seleccion.height * f))
            ctx.addLine(to: CGPoint(x: r.seleccion.maxX, y: r.seleccion.minY + r.seleccion.height * f))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    override func mouseDown(with e: NSEvent) {
        /*
         * TOCAR EL LIENZO CIERRA LO QUE FLOTA ENCIMA.
         *
         * El desplegable del lapiz se quedaba abierto hasta que volvieras a
         * pulsar su boton: se abria pegado al rail, y al abrir el panel lateral
         * el rail se movia y el desplegable NO — quedaba una tarjeta de colores
         * suelta en mitad del lienzo, sin dueño visible y sin forma obvia de
         * cerrarla. Daniel: *"es molesto que no desaparece"*.
         */
        alTocarLienzo?()
        cerrarEditor(guardando: true)
        let p = convert(e.locationInWindow, from: nil)
        punteroVista = p
        let w = aMundo(p)
        let m = e.modifierFlags

        // RECORTANDO, el ratón solo dibuja el rectángulo. Nada de seleccionar
        // ni arrastrar por debajo: el modo es un modo.
        if recorte != nil { recorte?.empezar(w); needsDisplay = true; return }

        // EL PANEO GANA A TODO. La barra espaciadora y el botón del medio son la
        // vía de escape universal de cualquier lienzo serio: da igual qué
        // herramienta esté activa, mueven la cámara. Sin esto, con el lápiz en la
        // mano no hay forma de desplazarse sin cambiar de herramienta — y cambiar
        // para moverte y volver es justo la fricción que hace que una pizarra se
        // sienta barata.
        if espacio || herramienta == .mano || m.contains(.option) && herramienta == .mano {
            gesto = .pan(p); NSCursor.closedHand.set(); return
        }

        // ⌘ + clic ABRE el enlace del elemento. La barra lo promete en su
        // propio texto de ayuda; prometerlo sin implementarlo es el pecado que
        // este lienzo persigue.
        if m.contains(.command), let el = Geo.elegir(doc.elementos, w, zoom: camara.zoom),
           let liga = el.enlace ?? (el.tipo == "embed" ? el.crudo["url"]?.s : nil) {
            alAbrirEnlace?(liga); return
        }

        /*
         * Y UN CLIC SIMPLE SOBRE LA MARCA TAMBIEN ABRE.
         *
         * ⌘+clic es un atajo que hay que SABER, y este mapa se opera a diario
         * sobre cientos de nodos: un destino que solo se alcanza con un secreto
         * es un destino que no existe. La marca se pinta redonda, del tamaño de
         * un botón, y ahora se comporta como uno. El radio y el centro salen de
         * `Pintor`, los MISMOS que se pintaron: dos piezas calculando dónde
         * está el botón es la receta de un botón que no se deja pulsar.
         */
        if !m.contains(.shift), herramienta == .seleccionar,
           let el = doc.elementos.reversed().first(where: {
               guard $0.enlace != nil, !$0.bloqueado else { return false }
               let c = Pintor.centroMarca($0, zoom: camara.zoom)
               let r = Pintor.radioMarca(camara.zoom)
               return hypot(w.x - c.x, w.y - c.y) <= r + 2 / camara.zoom
           }), let liga = el.enlace {
            alAbrirEnlace?(liga); return
        }

        /*
         * EL DIAL DE UN MECANISMO — agarrar la perilla NO mueve el elemento.
         *
         * Va antes de la selección por la misma razón que el conmutador de
         * abajo: un dial que en vez de girar el mecanismo selecciona su caja es
         * un dial que no existe. Y la zona sensible sale de `Mecanismo`, la
         * MISMA que lo pinta — dos piezas calculando dónde está un control es
         * la receta del control que no se deja agarrar.
         *
         * Sólo con la herramienta de selección: con el lápiz en la mano, sobre
         * un mecanismo se dibuja, que es lo que se espera de un lápiz.
         */
        /*
         * LOS BOTONES DE UN LAZO — CORRER · flecha de regreso · reiniciar.
         * Mismo contrato que el dial: van antes de la selección, la zona la
         * calcula `Lazo` (la misma pieza que los pinta) y nada escribe en el
         * documento. El reloj repinta el lienzo mientras el pulso corre y se
         * muere solo al llegar a ENTREGAR.
         */
        if !m.contains(.shift), herramienta == .seleccionar,
           let el = doc.elementos.reversed().first(where: {
               Mecanismo.esMecanismo($0) && !$0.bloqueado && Mecanismo.tipo($0) == "lazo" &&
               (Lazo.zonaCorrer($0).contains(w) || Lazo.zonaRegreso($0).contains(w) || Lazo.zonaReiniciar($0).contains(w))
           }) {
            meca.alRepintar = { [weak self] in self?.needsDisplay = true }
            if Lazo.zonaCorrer(el).contains(w) { meca.correr(el) }
            else if Lazo.zonaRegreso(el).contains(w) { meca.alternarRegreso(el) }
            else { meca.reiniciar(el) }
            needsDisplay = true
            return
        }

        if !m.contains(.shift), herramienta == .seleccionar,
           let el = doc.elementos.reversed().first(where: {
               Mecanismo.esMecanismo($0) && !$0.bloqueado && Mecanismo.zonaDial($0).contains(w)
           }) {
            meca.poner(el.id, Mecanismo.valorEn(el, w))
            gesto = .dial(el.id)
            needsDisplay = true
            return
        }

        /*
         * EL CONMUTADOR DE VISTA DEL CALENDARIO — la ÚNICA interacción de un
         * widget, y a propósito.
         *
         * La regla del panel es que es ESPEJO, no cabina: nada de lo que se
         * pulse aquí escribe en Google, en Todoist ni en el documento. Cambiar
         * de vista se salva porque es MIRAR de otra manera, no operar.
         *
         * Va ANTES de la selección: un chip que selecciona el widget en vez de
         * conmutar es un botón que no existe. Y la caja sale de
         * `Pintor.chipsDeVista`, la MISMA que los dibuja — la lección de la
         * marca de destino: dos piezas calculando dónde está un botón es la
         * receta del botón que no se deja pulsar.
         */
        if !m.contains(.shift), herramienta == .seleccionar,
           let el = doc.elementos.reversed().first(where: { $0.rol == "widget" && $0.caja.contains(w) }),
           let v = Pintor.vistaEn(el, w) {
            VistaCalendario.elegida = v
            needsDisplay = true
            return
        }

        // EL CONMUTADOR DE VENTANA de la banda de sensores (7D/30D/90D). Como
        // el del calendario: cambiar de ventana es MIRAR, no consultar — las
        // tres series ya están escritas en el documento.
        if !m.contains(.shift), herramienta == .seleccionar,
           let banda = doc.elementos.first(where: {
               $0.tipo == "frame" && !Pintor.chipsDeVentana($0).isEmpty
           }), let v = Pintor.ventanaEn(banda, w) {
            VentanaSensor.elegida = v
            needsDisplay = true
            return
        }

        /*
         * LA CASILLA DE UNA TAREA — la ÚNICA cosa del panel que escribe.
         *
         * Orden de Daniel (25 ago): *"permíteme añadir los checks a la parte de
         * tareas… que pueda marcar los checks desde acá justo como lo haría un
         * widget"*. Enmienda al read-only que él mismo firmó; lo que se conserva
         * está escrito en `LecturaTodoist.cerrar`.
         *
         * Se dispara en el `mouseDown` y no en el soltar, al revés que el doble
         * clic que abre la app: aquí el blanco es de 19 px y no existe el gesto
         * de "arrastrar una casilla", así que esperar al soltar solo añadiría
         * latencia a un acuse que tiene que sentirse inmediato.
         */
        if !m.contains(.shift), herramienta == .seleccionar,
           doc.elementos.contains(where: { $0.rol == "widget" && $0.caja.contains(w) }),
           let id = Pintor.tareaEn(w), !Pintor.cerradas.contains(id) {
            Pintor.cerradas.insert(id)          // acuse inmediato: se tacha ya
            needsDisplay = true
            alCerrarTarea?(id)
            return
        }

        // El CONECTOR nace de un elemento, no del vacío: una flecha que empieza
        // en la nada no conecta nada.
        if Herramienta.flechas.contains(herramienta) {
            if let el = Geo.elegir(doc.elementos, w, zoom: camara.zoom) {
                gesto = .conectando(desde: el.id, puerto: nil, inicio: w, actual: w, movio: false)
            }
            return
        }
        if Herramienta.deToque.contains(herramienta) { crearDeToque(w); return }
        if Herramienta.deArrastre.contains(herramienta) { gesto = .elastico(herramienta, w, w); return }
        // LA GOMA es un gesto propio. Sin este caso caía al final y armaba un
        // pan: pasar la goma MOVÍA el lienzo en vez de borrar — lo más
        // desconcertante que puede hacer una herramienta, porque no falla, hace
        // otra cosa.
        if herramienta == .goma {
            gesto = .borrar([])
            marcarGoma(w, quitando: e.modifierFlags.contains(.option))
            return
        }
        if herramienta == .lapiz || herramienta == .marcador {
            doc.abrirGesto()
            /*
             * ⚠️ SE APAGA LA FUSIÓN DE EVENTOS DE PUNTERO.
             *
             * macOS agrupa los eventos de puntero a la cadencia de PANTALLA
             * salvo que se le pida lo contrario. Con eso, la Kamvas —que
             * entrega más de 260 muestras por segundo— llegaba aquí a ~60, y
             * se midió en la tinta real de Daniel: 5.3 unidades de mundo entre
             * muestras de mediana, 41 en el peor caso. Ningún suavizado
             * recupera una curva de la que nunca llegaron los puntos: lo que
             * se tiró en la captura no se inventa en el pintor.
             *
             * Se apaga solo mientras dura el trazo, porque es un ajuste GLOBAL
             * del proceso y el resto de la app no gana nada con más eventos.
             */
            NSEvent.isMouseCoalescingEnabled = false
            inicioTrazo = e.timestamp
            gesto = .dibujar([puntoDePluma(e, w)])
            return
        }

        // Con la herramienta de selección el orden importa:
        //   1. manija (está ENCIMA de todo: si perdiera contra el elemento de
        //      abajo, redimensionar algo pegado a otra cosa sería imposible)
        //   2. puerto (vive fuera del borde, así que rara vez compite)
        //   3. elemento → arrastrar
        //   4. vacío → marquesina
        if let caja = cajaDeManijas(), let h = Geo.manijaEn(caja, w, zoom: camara.zoom) {
            doc.abrirGesto()
            if h == Geo.GIRO { gesto = .girar(w) }
            else {
                let previas = Dictionary(uniqueKeysWithValues:
                    doc.seleccionados.filter { $0.tipo != "connector" }.map { ($0.id, $0.caja) })
                gesto = .redimensionar(h, w, caja, previas)
            }
            return
        }
        /*
         * REENGANCHAR un extremo. Va ANTES que el PUERTO, que el codo y que el
         * arrastre del cuerpo.
         *
         * ⚠️ El orden aqui no es cosmetico. El extremo de una flecha muere
         * pegado al borde de su caja, y el puerto de esa caja flota 13 px por
         * fuera del mismo borde: los dos agarres se solapan. Con el puerto
         * primero, tirar del extremo de la flecha nacia una flecha NUEVA desde
         * la caja — el gesto hacia lo contrario de lo que parecia. Un extremo
         * seleccionado es un blanco DELIBERADO; un puerto es ambiente, y lo
         * deliberado gana.
         */
        for conn in doc.seleccionados where conn.tipo == "connector" && !conn.bloqueado {
            if let cual = Geo.extremoEn(conn, w, zoom: camara.zoom) {
                doc.abrirGesto()
                gesto = .extremo(id: conn.id, cual: cual, actual: w)
                return
            }
        }

        if let h = hover, let puerto = h.puerto, doc.porId(h.id) != nil {
            gesto = .conectando(desde: h.id, puerto: puerto, inicio: w, actual: w, movio: false)
            return
        }

        /*
         * DOBLAR UN CONECTOR: arrastrar su cuerpo INSERTA un codo.
         *
         * ⚠️ El campo `waypoints` existía en el modelo, el router lo respetaba y
         * la barra lo borraba al cambiar de ruta — y NADA lo producía nunca. Es
         * el patrón exacto que este lienzo existe para no repetir: una capacidad
         * declarada sin productor, que parece autoritativa y sobre la que el
         * siguiente construye.
         *
         * Solo sobre un conector YA seleccionado: si no, arrastrar sobre una
         * línea al pasar por encima doblaría flechas por accidente.
         */
        if let el = Geo.elegir(doc.elementos, w, zoom: camara.zoom),
           el.tipo == "connector", doc.seleccion.contains(el.id) {
            doc.abrirGesto()
            gesto = .doblar(id: el.id, indice: insertarCodo(el, en: w))
            return
        }

        if let el = Geo.elegir(doc.elementos, w, zoom: camara.zoom) {
            /* DOBLE CLIC: se resuelve AL SOLTAR, jamás al presionar.
             *
             * Resolverlo en el `down` hacía que "clic para seleccionar y
             * enseguida arrastrar" —el gesto más común que existe en un lienzo—
             * abriera el editor de texto y dejara el arrastre MUERTO. Cualquier
             * mano que dude menos de 350 ms choca con eso. */
            let ahora = Date().timeIntervalSince1970
            let segundo = ultimoClic.map { $0.id == el.id && ahora - $0.cuando < 0.35 } ?? false
            ultimoClic = (el.id, ahora)

            if m.contains(.shift) {
                doc.seleccion.formSymmetricDifference(doc.expandirSeleccion([el.id]))
            } else if !doc.seleccion.contains(el.id) {
                doc.seleccion = doc.expandirSeleccion([el.id])
            }
            avisarSeleccion()
            // ALT arrastra una COPIA y deja el original donde estaba. El canvas
            // viejo documentaba este atajo y hacía PAN con Alt: un atajo
            // documentado que hace otra cosa es peor que uno ausente.
            if m.contains(.option) {
                doc.duplicar(doc.seleccion, desplazamiento: .zero)
                avisarSeleccion()
            }
            doc.abrirGesto()
            gesto = .arrastre(inicio: w, ultimo: w, movio: false,
                              activaAlSoltar: segundo && !m.contains(.option))
            return
        }
        if !m.contains(.shift) { doc.seleccion = []; avisarSeleccion() }
        gesto = .marco(w, w)
    }

    override func rightMouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let w = aMundo(p)
        let el = Geo.elegir(doc.elementos, w, zoom: camara.zoom)
        if let el, !doc.seleccion.contains(el.id) {
            doc.seleccion = doc.expandirSeleccion([el.id])
            avisarSeleccion()
        }
        alPedirMenu?(e.locationInWindow, el)
    }

    override func otherMouseDown(with e: NSEvent) { gesto = .pan(convert(e.locationInWindow, from: nil)) }
    override func otherMouseDragged(with e: NSEvent) { mouseDragged(with: e) }
    override func otherMouseUp(with e: NSEvent) { mouseUp(with: e) }

    override func mouseDragged(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        punteroVista = p
        let w = aMundo(p)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if recorte != nil { recorte?.mover(w); needsDisplay = true; return }

        switch gesto {
        case .pan(let ultimo):
            camara.x -= (p.x - ultimo.x) / camara.zoom
            camara.y -= (p.y - ultimo.y) / camara.zoom
            gesto = .pan(p)

        // EL DIAL: la mano manda sobre el valor, y el mecanismo responde en el
        // mismo fotograma. Nada de esto toca el documento.
        case .dial(let id):
            if let el = doc.porId(id) {
                meca.poner(id, Mecanismo.valorEn(el, w))
                needsDisplay = true
            }

        case .arrastre(let inicio, let ultimo, _, let activa):
            var dx = w.x - ultimo.x, dy = w.y - ultimo.y
            guard dx != 0 || dy != 0 else { return }
            // IMANTADO: la mano suelta donde quiere y el lienzo hace el último
            // tramo. Se calcula contra la caja YA desplazada, para que el imán
            // corrija sobre el destino y no sobre el origen.
            let sel = doc.seleccionados
            if var caja = sel.first?.caja, herramienta == .seleccionar {
                for x in sel.dropFirst() { caja = caja.union(x.caja) }
                let destino = caja.offsetBy(dx: dx, dy: dy)
                let iman = Geo.imantar(destino, doc.elementos, zoom: camara.zoom, ignorar: doc.seleccion)
                dx += iman.dx; dy += iman.dy
                guias = iman.guias
            }
            doc.mover(doc.seleccion, dx: dx, dy: dy, rapido: true)
            gesto = .arrastre(inicio: inicio, ultimo: CGPoint(x: ultimo.x + dx, y: ultimo.y + dy),
                              movio: true, activaAlSoltar: activa)

        case .marco(let a, _): gesto = .marco(a, w); needsDisplay = true
        case .elastico(let h, let a, _): gesto = .elastico(h, a, w); needsDisplay = true

        case .redimensionar(let h, let inicio, let caja, let previas):
            let d = CGPoint(x: w.x - inicio.x, y: w.y - inicio.y)
            /*
             * LA ESQUINA ESCALA · EL LADO DEFORMA.
             *
             * Estaba al reves de lo que la mano espera: TODO deformaba libre y
             * la proporcion habia que pedirla con Shift. Daniel, 26 ago: *"al
             * tirar de las esquinas que solo conserve la proporcion, que no se
             * deforme; solo si jalo de los lados o de arriba, ahi si con
             * intencion quiero deformarlo, de otra forma no"*.
             *
             * Y tiene sentido mas alla del gusto: los ocho tiradores no
             * significan lo mismo. Un lado se agarra en UN eje, asi que pedirle
             * que mantenga la proporcion seria ignorar la mitad del gesto. Una
             * esquina se agarra en los DOS a la vez: es el tirador de "hazlo
             * mas grande", no el de "hazlo mas ancho". Que deformara por
             * defecto convertia el gesto de escalar en el de estropear, y en
             * una imagen eso no se nota hasta que ya esta guardado.
             *
             * Shift sigue estando, INVERTIDO: ahora es la llave para romper la
             * proporcion a proposito desde una esquina. La capacidad no se
             * pierde, cambia de sitio — pasa de ser el default a ser la
             * excepcion, que es donde vive lo que se hace a proposito.
             */
            let esquina = ["nw", "ne", "se", "sw"].contains(h)
            let nueva = Geo.redimensionar(caja, h, d,
                                          proporcional: esquina != e.modifierFlags.contains(.shift))
            doc.volatil { els in
                for k in els.indices where previas[els[k].id] != nil {
                    guard !els[k].bloqueado, let antes = previas[els[k].id] else { continue }
                    // Cada elemento recibe su parte PROPORCIONAL de la caja
                    // nueva: sin esto, redimensionar tres cosas juntas las
                    // apila todas en la misma esquina.
                    let sx = caja.width > 0 ? nueva.width / caja.width : 1
                    let sy = caja.height > 0 ? nueva.height / caja.height : 1
                    els[k].ponerCaja(CGRect(x: nueva.minX + (antes.minX - caja.minX) * sx,
                                            y: nueva.minY + (antes.minY - caja.minY) * sy,
                                            width: max(8, antes.width * sx),
                                            height: max(8, antes.height * sy)))
                    els[k].remaquetar()
                }
                els = Conectores.rerutear(els, movidos: doc.seleccion)
            }

        case .girar(let inicio):
            let sel = doc.seleccionados
            guard var caja = sel.first?.caja else { return }
            for x in sel.dropFirst() { caja = caja.union(x.caja) }
            let centro = CGPoint(x: caja.midX, y: caja.midY)
            let ang = Geo.ajustarAngulo(Geo.anguloHacia(centro, w), shift: e.modifierFlags.contains(.shift))
            doc.volatil { els in
                for k in els.indices where doc.seleccion.contains(els[k].id) && !els[k].bloqueado {
                    els[k].ponerGiro(ang)
                }
            }
            _ = inicio

        case .conectando(let desde, let puerto, let inicio, _, let movio):
            let semovio = movio || hypot(w.x - inicio.x, w.y - inicio.y) > 6 / camara.zoom
            gesto = .conectando(desde: desde, puerto: puerto, inicio: inicio, actual: w, movio: semovio)
            needsDisplay = true

        case .dibujar(var pts):
            /*
             * MUESTRAS PEGADAS NO SE GUARDAN.
             *
             * Con la fusión apagada la Kamvas entrega más de 260 por segundo, y
             * cuando la mano frena llegan a caer varias en la MISMA décima de
             * unidad. Ésas no describen la letra: engordan el documento y le
             * dan trabajo al spline para no mover un píxel. Se filtran por
             * DISTANCIA, con una salida: si la presión cambió de verdad, la
             * muestra entra aunque la pluma no se haya movido —una pluma
             * apoyada que aprieta sí está diciendo algo.
             *
             * Al descartar, el TIEMPO no se pierde: la siguiente muestra que
             * entra trae su propio `t`, así que la velocidad se calcula sobre
             * el intervalo real y no sale falseada.
             */
            let q = puntoDePluma(e, w)
            if let u = pts.last,
               hypot(q.x - u.x, q.y - u.y) < 0.3, abs(q.p - u.p) < 0.02 {
                return
            }
            pts.append(q)
            gesto = .dibujar(pts)
            needsDisplay = true

        case .doblar(let id, let i):
            doc.volatil { els in
                guard let k = els.firstIndex(where: { $0.id == id }) else { return }
                var codos = els[k].crudo["waypoints"]?.arr ?? []
                guard i < codos.count else { return }
                codos[i] = .objeto(["x": .numero(w.x), "y": .numero(w.y)])
                els[k].tocar(["waypoints": .lista(codos)])
                els[k] = Conectores.rutear(els[k], els)
            }

        case .extremo(let id, let cual, _):
            gesto = .extremo(id: id, cual: cual, actual: w)
            needsDisplay = true

        case .borrar: marcarGoma(w, quitando: e.modifierFlags.contains(.option))
        case .ninguno: break
        }
    }

    override func mouseUp(with e: NSEvent) {
        let w = aMundo(convert(e.locationInWindow, from: nil))
        guias = []
        if recorte != nil {
            recorte?.soltar(); needsDisplay = true
            NSCursor.crosshair.set()
            return
        }
        defer { cursorParaHerramienta() }

        switch gesto {
        // El dial se suelta y ya: el valor quedó puesto en cada fotograma del
        // arrastre, y no hay nada que confirmar porque nada se guarda.
        case .dial:
            gesto = .ninguno

        case .arrastre(_, _, let movio, let activa):
            gesto = .ninguno
            if movio {
                // Al SOLTAR se re-rutea TODO: una tarjeta movida puede estorbar
                // a una flecha ajena. Hacerlo en cada fotograma haría que las
                // flechas lejanas salten sin motivo aparente.
                doc.volatil { $0 = Conectores.reruteaTodo($0) }
                doc.cerrarGesto("mover")
            } else {
                doc.cerrarGesto("mover")
                /*
                 * UN WIDGET PULSADO ABRE SU APP (enmienda del 25 ago).
                 *
                 * Daniel: *"asegúrate que al presionar el widget se abra la
                 * página de sfcal o redirija para allá"*. El panel sigue sin
                 * escribir nada — lo que hace es LLEVAR a la cabina donde la
                 * mano sí edita, que es exactamente lo que él hacía a mano
                 * buscando la app en el Dock.
                 *
                 * ⚠️ DOBLE clic, no simple, y lo pidió él así. Un clic simple
                 * es el gesto de SELECCIONAR: si además abriera una app, tocar
                 * el widget para moverlo o para mirarlo de cerca traería sfcal
                 * al frente sin querer, varias veces al día.
                 *
                 * Y va en el SOLTAR, solo si NO se arrastró (`movio` falso):
                 * el gesto de agarrar y el de pulsar comparten el primer
                 * evento, y solo el final los distingue. Misma razón por la que
                 * un botón de verdad se dispara al soltar.
                 */
                if activa, let el = doc.elementos.first(where: { $0.id == doc.seleccion.first }),
                   el.rol == "widget", let liga = el.enlace {
                    alAbrirEnlace?(liga)
                    return
                }
                // Doble toque = dos clics QUIETOS. Si el segundo arrastró, era
                // un arrastre, y activar ahora abriría un editor sobre algo
                // recién movido.
                if activa, let id = doc.seleccion.first { editarTexto(id) }
            }

        case .marco(let a, let b):
            gesto = .ninguno
            let caja = normalizar(a, b)
            guard caja.width > 4 || caja.height > 4 else { break }
            // Por el CENTRO, no por contención total: exigir que quepa entera
            // hace que rodear un grupo a ojo no seleccione la mitad.
            let dentro = doc.elementos.filter {
                caja.contains(CGPoint(x: $0.caja.midX, y: $0.caja.midY))
            }.map(\.id)
            if e.modifierFlags.contains(.shift) { doc.seleccion.formUnion(dentro) }
            else { doc.seleccion = Set(dentro) }
            doc.seleccion = doc.expandirSeleccion(doc.seleccion)
            avisarSeleccion()

        case .elastico(let h, let a, let b):
            gesto = .ninguno
            crearArrastrando(h, normalizar(a, b), inicio: a)

        case .redimensionar:
            gesto = .ninguno
            doc.volatil { $0 = Conectores.reruteaTodo($0) }
            doc.cerrarGesto("redimensionar")

        case .girar:
            gesto = .ninguno
            doc.cerrarGesto("girar")

        case .conectando(let desde, let puerto, let inicio, _, let movio):
            gesto = .ninguno
            conectar(desde: desde, puerto: puerto, desdePunto: inicio, en: w, arrastre: movio)

        case .doblar:
            gesto = .ninguno
            doc.cerrarGesto("doblar")

        case .extremo(let id, let cual, _):
            gesto = .ninguno
            reengancharExtremo(id, cual, en: w)

        case .dibujar(let pts):
            gesto = .ninguno          // el `didSet` restaura la fusión
            terminarTrazo(pts)

        case .borrar(let marcados):
            gesto = .ninguno
            confirmarGoma(marcados)

        case .pan, .ninguno:
            gesto = .ninguno
        }
        needsDisplay = true
    }

    /**
     * Prepara el codo que se va a arrastrar y devuelve su índice.
     *
     * Si el punto cae SOBRE un codo que ya existe, se mueve ESE. Si cae en un
     * tramo, se inserta uno nuevo EN SU SITIO dentro de la lista — no al final:
     * meterlo al final haría que la línea se cruzara consigo misma en cuanto
     * hubiera dos, y la mano leería eso como que el codo "saltó".
     */
    private func insertarCodo(_ conn: Elemento, en w: CGPoint) -> Int {
        var codos = conn.crudo["waypoints"]?.arr ?? []
        let agarre = 8 / camara.zoom
        for (i, c) in codos.enumerated() {
            let p = CGPoint(x: c["x"]?.num ?? 0, y: c["y"]?.num ?? 0)
            if hypot(p.x - w.x, p.y - w.y) <= agarre { return i }
        }
        // ¿En qué tramo de la ruta cayó? Los codos ocupan las posiciones
        // intermedias de `points`, así que el tramo dice entre cuáles va.
        let pts = conn.ruta
        var mejor = (dist: Double.infinity, tramo: 0)
        for i in 0..<max(0, pts.count - 1) {
            let d = distanciaASegmento(w, pts[i], pts[i + 1])
            if d < mejor.dist { mejor = (d, i) }
        }
        let indice = codos.isEmpty ? 0 : min(codos.count, max(0, mejor.tramo))
        codos.insert(.objeto(["x": .numero(w.x), "y": .numero(w.y)]), at: indice)
        doc.editar("doblar") { els in
            guard let k = els.firstIndex(where: { $0.id == conn.id }) else { return }
            els[k].tocar(["waypoints": .lista(codos)])
            els[k] = Conectores.rutear(els[k], els)
        }
        return indice
    }

    private func distanciaASegmento(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let l2 = dx * dx + dy * dy
        if l2 == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /**
     * La caja de las MANIJAS, o nil si no hay nada que redimensionar.
     *
     * ⚠️ UN CONECTOR NO SE REDIMENSIONA. Su geometría se deriva de sus dos
     * extremos: estirar su caja no significa nada y el router la reescribe en el
     * frame siguiente. Peor: la manija NORTE de la caja de una flecha cae JUSTO
     * en el medio de su tramo horizontal, así que agarrar la línea para doblarla
     * arrancaba un redimensionado. Lo cazó la prueba de gestos, no el ojo.
     *
     * Tampoco con algo BLOQUEADO en la selección: unas manijas que no mueven
     * nada son una promesa.
     */
    private func cajaDeManijas() -> CGRect? {
        let sel = doc.seleccionados.filter { $0.tipo != "connector" }
        guard !sel.isEmpty, !sel.contains(where: { $0.bloqueado }) else { return nil }
        var caja = sel[0].cajaVisual
        for e in sel.dropFirst() { caja = caja.union(e.cajaVisual) }
        return caja
    }

    private func avisarSeleccion() { alSeleccionar?(); needsDisplay = true }

    /**
     * SONDA DE ESTADO. Lo que la app cree que está pasando, en una línea.
     *
     * Es el sensor que la verificación de una app nativa necesita: una captura
     * enseña PÍXELES, y cuando lo que se busca no aparece no distingue "el
     * gesto no ocurrió" de "el gesto ocurrió y no se pinta". Sin esto se
     * adivina, y adivinar es lo que este proyecto lleva todo el día demostrando
     * que no funciona.
     */
    var estadoParaSonda: String {
        let g: String = switch gesto {
            case .ninguno: "ninguno"
            case .pan: "pan"
            case .arrastre(_, _, let m, _): "arrastre(movio: \(m))"
            case .dial(let id): "dial(\(id))"
            case .marco: "marco"
            case .elastico(let h, _, _): "elastico(\(h.rawValue))"
            case .redimensionar(let h, _, _, _): "redimensionar(\(h))"
            case .girar: "girar"
            case .conectando(let d, let p, _, _, let m): "conectando(de: \(d), puerto: \(p ?? "—"), movio: \(m))"
            case .doblar(let id, let i): "doblar(\(id) codo \(i))"
            case .extremo(let id, let c, _): "extremo(\(id) \(c))"
            case .dibujar(let pts): "dibujar(\(pts.count) pts)"
            case .borrar(let m): "borrar(marcados: \(m.count))"
        }
        return "gesto=\(g) herramienta=\(herramienta.rawValue) sel=\(doc.seleccion.count) "
             + "hover=\(hover.map { "\($0.id):\($0.puerto ?? "—")" } ?? "—") "
             + "elementos=\(doc.elementos.count) editor=\(editandoId ?? "—")"
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: crear
    // ════════════════════════════════════════════════════════════════════════

    private func crearDeToque(_ w: CGPoint) {
        let z = doc.zSiguiente
        let nuevo: Elemento
        switch herramienta {
        case .nota: nuevo = Crear.nota(w, z: z)
        case .tabla: nuevo = Crear.tabla(w, celdas: [["Columna", "Columna"], ["", ""], ["", ""]], z: z)
        case .codigo: nuevo = Crear.codigo(w, codigo: "// código", z: z)
        case .embed: nuevo = Crear.embed(w, url: "https://", z: z)
        default: return
        }
        doc.agregar([nuevo], etiqueta: "crear")
        volverAlSelector()
        // Crear ABRE EL CURSOR. Sin esto hay que crear, apuntar y hacer doble
        // clic para escribir la primera palabra — tres gestos para lo que el
        // dedo ya venía a hacer.
        if nuevo.tipo == "shape" { editarTexto(nuevo.id) }
    }

    /**
     * TRAS INSERTAR, VUELVE LA FLECHA.
     *
     * Daniel lo pidio al reves hace dos tandas —*"mantén la herramienta"*— y lo
     * corrigio al usarlo de verdad: *"ando insertando un chingo de estas
     * madres"*. Con la herramienta pegada, el clic siguiente —que casi siempre
     * es para AGARRAR lo que acabas de poner— inserta otra encima, y en vez de
     * ahorrarte un viaje al rail te cuesta un deshacer.
     *
     * El lapiz, el marcador, la goma y la mano NO entran: son gestos continuos,
     * y ahi sí quieres seguir. Es la misma linea que trazan Figma y Miro.
     */
    private func volverAlSelector() { herramienta = .seleccionar }

    private func crearArrastrando(_ h: Herramienta, _ caja: CGRect, inicio: CGPoint) {
        // Un área minúscula significa que fue un CLIC, no un arrastre: se crea
        // con un tamaño útil en vez de una figura de 2px que nadie puede agarrar.
        let chico = caja.width < 12 || caja.height < 12
        // Un clic con la herramienta de TEXTO no puede caer en 180px: eso parte
        // cualquier frase en una columna de dos palabras.
        let porDefecto = h == .texto
            ? CGRect(x: inicio.x, y: inicio.y, width: 420, height: 60)
            : CGRect(x: inicio.x - 90, y: inicio.y - 60, width: 180, height: 120)
        let r = chico ? porDefecto : caja
        let z = doc.zSiguiente
        let nuevo: Elemento
        switch h {
        case .seccion: nuevo = Crear.seccion(r)
        case .texto: nuevo = Crear.texto(CGPoint(x: r.minX, y: r.minY), z: z, maxAncho: r.width)
        default: nuevo = Crear.figura(h.rawValue, r, z: z)
        }
        doc.agregar([nuevo], etiqueta: "crear")
        volverAlSelector()
        editarTexto(nuevo.id)
    }

    /**
     * SOLTAR EL CONECTOR.
     *
     * Caer en el VACÍO no significa "no pasa nada": ahí es donde nace una figura
     * nueva YA CONECTADA. Un ARRASTRE la crea donde la soltaste; un CLIC (sin
     * mover) la pone a un salto estándar en la dirección del puerto. Son dos
     * gestos distintos con la misma intención.
     */
    private func conectar(desde: String, puerto: String?, desdePunto: CGPoint,
                          en w: CGPoint, arrastre: Bool) {
        guard let origen = doc.porId(desde) else { return }
        /*
         * EL LADO DE SALIDA ES DONDE PUSISTE EL DEDO.
         *
         * Con la herramienta de flecha no se arranca en un puerto, se arranca
         * en el CUERPO de la caja — y hasta ahora el lado se elegia solo, mirando
         * hacia donde estaba el destino. Daniel: *"quise poner una flecha del
         * extremo derecho del bloque A al superior del bloque B"* y salio por
         * otro lado. Empezar el trazo pegado al borde derecho ES decir "sale por
         * la derecha"; ignorarlo convierte un gesto preciso en una sugerencia.
         *
         * Y arrancar en MITAD de la caja no dice nada: ahi `lado` queda en nil y
         * decide el ruteo, como siempre.
         */
        let lado = puerto ?? Ruteo.ladoIntencional(Conectores.obstaculoDe(origen), desdePunto)
        // Conectar algo consigo mismo no significa nada: se descarta en silencio
        // (por eso `excluir`, y no un `if` después).
        if let destino = Geo.candidatoConexion(doc.elementos, w, zoom: camara.zoom, excluir: desde) {
            let ladoDestino = Ruteo.ladoMasCercano(Conectores.obstaculoDe(destino), w)
            var c = Crear.conector(desde, destino.id, z: (doc.elementos.map(\.z).min() ?? 0) - 1,
                                   puertoDesde: lado, puertoHasta: ladoDestino)
            // La flecha nace con la forma de la herramienta que la trazó.
            if Herramienta.flechas.contains(herramienta) {
                c.crudo = c.crudo.con("routing", .texto(herramienta.ruteo))
            }
            doc.editar("conectar") { els in
                els.append(c)
                els = Conectores.reruteaTodo(els)
            }
            doc.seleccion = [c.id]
            volverAlSelector()
            avisarSeleccion()
            return
        }
        let caja = arrastre ? Crear.cajaFantasma(origen.caja, w) : Crear.cajaEnDireccion(origen.caja, lado)
        // La figura nueva HEREDA la forma y el rol del origen: encadenar cinco
        // pasos de un proceso no debería obligar a repintar cada uno.
        let nueva = Crear.figura(origen.tipo == "shape" ? origen.figura : "rect", caja,
                                 z: doc.zSiguiente, rol: origen.tipo == "shape" ? origen.rol : "drawn")
        let opuesto: String? = switch lado {
            case "e": "w"; case "w": "e"; case "n": "s"; case "s": "n"; default: nil
        }
        let c = Crear.conector(desde, nueva.id, z: (doc.elementos.map(\.z).min() ?? 0) - 1,
                               puertoDesde: lado, puertoHasta: opuesto)
        doc.editar("encadenar") { els in
            els.append(nueva); els.append(c)
            els = Conectores.reruteaTodo(els)
        }
        doc.seleccion = [nueva.id]
        volverAlSelector()
        avisarSeleccion()
        editarTexto(nueva.id)
    }

    /**
     * SUELTA UN EXTREMO en donde caiga.
     *
     * En el VACIO no pasa nada: el extremo vuelve a donde estaba. Es lo unico
     * honesto — una flecha que apunta a la nada no es una relacion, y borrarla
     * por soltar mal seria castigar un resbalon.
     *
     * El lado se toma del punto donde soltaste, asi que el destino se elige y el
     * COSTADO tambien, en el mismo gesto: soltar por la izquierda de una tarjeta
     * engancha por la izquierda. Y como el lado queda FIJADO, mover la caja ya
     * no lo mueve — que es lo que Daniel pidio la primera vez que se hablo de
     * puertos.
     */
    private func reengancharExtremo(_ id: String, _ cual: String, en w: CGPoint) {
        defer { doc.cerrarGesto("reenganchar") }
        guard let conn = doc.porId(id) else { return }
        // El OTRO extremo se excluye: una flecha de algo a si mismo no es nada.
        let fijo = (cual == "desde" ? conn.hastaId : conn.desdeId) ?? ""
        guard let destino = Geo.candidatoConexion(doc.elementos, w, zoom: camara.zoom, excluir: fijo),
              destino.id != fijo
        else { return }
        let lado = Ruteo.ladoMasCercano(Conectores.obstaculoDe(destino), w)
        doc.editar("reenganchar") { els in
            guard let k = els.firstIndex(where: { $0.id == id }) else { return }
            els[k].tocar(cual == "desde"
                ? ["fromId": .texto(destino.id), "fromPort": .texto(lado), "waypoints": nil]
                : ["toId": .texto(destino.id), "toPort": .texto(lado), "waypoints": nil])
            els = Conectores.reruteaTodo(els)
        }
    }

    private func terminarTrazo(_ pts: [PuntoTinta]) {
        defer { doc.cerrarGesto("dibujar") }
        guard pts.count >= 2 else { return }
        let minX = pts.map(\.x).min()!, minY = pts.map(\.y).min()!
        var o: [String: Json] = [
            "id": .texto(Crear.nuevoId("ink")), "type": .texto("ink"),
            "x": .numero(minX), "y": .numero(minY),
            "width": .numero(pts.map(\.x).max()! - minX), "height": .numero(pts.map(\.y).max()! - minY),
            "rotation": .numero(0), "zIndex": .numero(doc.zSiguiente), "opacity": .numero(1),
            "locked": .bool(false), "version": .numero(1),
            "createdAt": .numero(Date().timeIntervalSince1970 * 1000),
            "updatedAt": .numero(Date().timeIntervalSince1970 * 1000),
            // Los puntos van RELATIVOS al origen: el v3 aceptaba absolutos y
            // relativos y dejaba cajas gigantes que no se podían seleccionar.
            /*
             * Los puntos van RELATIVOS al origen, y ADEMÁS traen lo que la
             * pluma sabe y el formato viejo tiraba: `tiltX`/`tiltY` (la
             * inclinación de la PW600L, ±60°) y `t` (milisegundos desde el
             * inicio, que es lo que convierte una distancia en una VELOCIDAD).
             *
             * Los tres son ADITIVOS y CONDICIONALES: el lienzo web lee x, y,
             * pressure, ignora el resto y lo conserva al guardar; y un trazo
             * sin ellos —todos los que ya existen— no queda con ceros que
             * mientan, queda SIN el campo, que es lo que el motor distingue.
             */
            "points": .lista(pts.map { q in
                var o: [String: Json] = ["x": .numero(redondear(q.x - minX, 2)),
                                         "y": .numero(redondear(q.y - minY, 2)),
                                         "pressure": .numero(q.p)]
                if q.ix != 0 || q.iy != 0 {
                    o["tiltX"] = .numero(q.ix)
                    o["tiltY"] = .numero(q.iy)
                }
                if q.t >= 0 { o["t"] = .numero(q.t) }
                return .objeto(o)
            }),
            "size": .numero(tinta.grosor),
            "highlighter": .bool(herramienta == .marcador),
        ]
        // El color se guarda SOLO si la mano eligió uno. Guardar el del tema
        // activo produjo trazos que desaparecían al cambiar a oscuro.
        if let c = tinta.color { o["color"] = .texto(c) }
        doc.editar("dibujar") { $0.append(Elemento(.objeto(o))) }
        doc.seleccion = []
    }

    /**
     * LA GOMA MARCA MIENTRAS PASA, Y BORRA AL SOLTAR.
     *
     * Es un gesto continuo —se pasa por encima, como una goma de verdad; una de
     * un solo clic obliga a apuntar a cada trazo por separado— pero lo que toca
     * no desaparece todavía: se queda FANTASMA. Dos razones, y la segunda es la
     * que importa:
     *
     * 1. Ver antes de perder. Con el alcance en `todo` un barrido cruza una
     *    sección entera, y "ya se fue, deshaz" es peor experiencia que "mira lo
     *    que se va a ir, y si no era, sal del disco".
     * 2. **Se puede DESMARCAR con ⌥.** Un roce accidental a mitad de barrido se
     *    arregla pasando otra vez con Opción apretada, en vez de deshacer el
     *    barrido entero —incluido lo que sí querías borrar— y volver a empezar.
     *    No se desmarca por volver a pasar sin más: al barrer se cruza dos veces
     *    por el mismo sitio constantemente, y eso haría parpadear la condena.
     *
     * Y todo el barrido entra al historial como UN paso, que es como la mano lo
     * recuerda: "borré esto", no "borré catorce cosas".
     */
    private func marcarGoma(_ w: CGPoint, quitando: Bool = false) {
        guard case .borrar(var marcados) = gesto else { return }
        let r = goma.radioMundo(zoom: camara.zoom)
        let tocados = Goma.alcanzados(doc.elementos, centro: w, radio: r, alcance: goma.alcance)
        guard !tocados.isEmpty else { return }
        let antes = marcados
        if quitando { marcados.subtract(tocados) } else { marcados.formUnion(tocados) }
        guard marcados != antes else { return }
        gesto = .borrar(marcados)
        needsDisplay = true
    }

    /// El barrido se hace efectivo. Un solo `editar` = un solo paso de deshacer.
    private func confirmarGoma(_ marcados: Set<String>) {
        guard !marcados.isEmpty else { return }
        // Si habia otro desvanecido a medias, se cierra antes: dos animaciones
        // sobre el mismo lienzo compiten por el mismo reloj y una de las dos
        // se quedaria a medio camino con sus elementos sin borrar.
        cerrarDesvanecido()

        // Los TRAZOS no se desvanecen: la goma sobre tinta es un gesto continuo
        // —pasas, y va desapareciendo bajo la mano— y meterle una salida de dos
        // decimas convertiria un barrido fluido en una sucesion de parpadeos.
        // La animacion es para lo que se va ENTERO, que es donde se pierde de
        // vista qué había ahí.
        let enteros = marcados.filter { id in
            doc.elementos.first { $0.id == id }.map { $0.tipo != "drawn" } ?? false
        }
        let trazos = marcados.subtracting(enteros)
        if !trazos.isEmpty { borrarDeVerdad(trazos) }
        guard !enteros.isEmpty else { return }

        for id in enteros { desvaneciendo[id] = 0 }
        needsDisplay = true
        var t = 0.0
        let DURA = 0.20
        relojGoma = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] reloj in
            guard let s = self else { reloj.invalidate(); return }
            t += 1.0 / 60
            if t >= DURA { s.cerrarDesvanecido(); return }
            // Empieza rapido y frena: al reves, la forma se queda un rato casi
            // entera y la espera se nota como lentitud.
            let p = 1 - pow(1 - t / DURA, 2)
            for k in s.desvaneciendo.keys { s.desvaneciendo[k] = p }
            s.needsDisplay = true
        }
    }

    /// ¿Este elemento está condenado por el barrido en curso? Lo pregunta el
    /// pintado para apagarlo, y es la ÚNICA fuente de esa verdad.
    private func marcadoPorLaGoma(_ id: String) -> Bool {
        if case .borrar(let m) = gesto { return m.contains(id) }
        return false
    }

    /**
     * EL DESVANECIDO DE LA GOMA — de 0 (entero) a 1 (ido).
     *
     * ⚠️ Lo que se borra desaparecia de GOLPE al levantar la mano, y borrar un
     * componente entero de un parpadeo deja la duda de QUE se fue: el ojo no
     * llega a registrar la forma que ya no esta, y hay que mirar el lienzo a
     * ver que falta. Una salida de dos decimas no es decoracion — es el acuse
     * de recibo de una accion destructiva.
     *
     * Se encoge ADEMAS de apagarse. Solo con alfa parece que se esconde; con
     * el encogimiento se lee "se lo llevaron", que es lo que de verdad paso.
     */
    private var desvaneciendo: [String: Double] = [:]
    private var relojGoma: Timer?

    /// Lo que el pintado necesita: 1 = entero, 0 = invisible. Nil si no aplica.
    private func vidaDesvanecida(_ id: String) -> Double? {
        desvaneciendo[id].map { 1 - $0 }
    }

    /**
     * Termina YA cualquier desvanecido pendiente.
     *
     * Hace falta porque el borrado de verdad ocurre al FINAL de la animacion:
     * si empiezas otro barrido antes de que acabe, o cierras el lienzo, lo
     * condenado tiene que irse igual. Una animacion nunca puede ser la que
     * decide si un cambio se aplica o no.
     */
    func cerrarDesvanecido() {
        relojGoma?.invalidate(); relojGoma = nil
        let ids = Set(desvaneciendo.keys)
        desvaneciendo.removeAll()
        guard !ids.isEmpty else { return }
        borrarDeVerdad(ids)
    }

    private func borrarDeVerdad(_ ids: Set<String>) {
        doc.editar("borrar") { els in
            els.removeAll { ids.contains($0.id) }
            // Una flecha cuyo origen o destino acaba de irse ya no relaciona
            // nada: se va con ellos, igual que al borrar por selección.
            let h = Conectores.huerfanos(els)
            els.removeAll { h.contains($0.id) }
        }
        avisarSeleccion()
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: editar texto
    // ════════════════════════════════════════════════════════════════════════

    func editarTexto(_ id: String) {
        guard let e = doc.porId(id), ["shape", "text", "frame", "code"].contains(e.tipo),
              !e.bloqueado else { return }
        cerrarEditor(guardando: true)
        let ed = EditorTexto(elemento: e, tema: tema, camara: camara, viewport: bounds.size,
                             guardar: { [weak self] t in self?.guardarTexto(id, t) },
                             cancelar: { [weak self] in self?.editor = nil; self?.needsDisplay = true })
        // El editor vive en la VENTANA, no dentro del lienzo: dentro heredaría
        // el volteo de la vista y el texto saldría del revés.
        superview?.addSubview(ed)
        editor = ed
        apagarHover()
        ed.enfocar()
        needsDisplay = true
    }

    private func guardarTexto(_ id: String, _ texto: String) {
        editor = nil
        doc.editar("escribir") { els in
            guard let i = els.firstIndex(where: { $0.id == id }) else { return }
            els[i].escribir(texto)
        }
        avisarSeleccion()
    }

    func cerrarEditor(guardando: Bool) {
        guard let ed = editor else { return }
        editor = nil
        guardando ? ed.cerrarPorFoco() : ed.removeFromSuperview()
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: teclado
    // ════════════════════════════════════════════════════════════════════════

    override func flagsChanged(with e: NSEvent) { super.flagsChanged(with: e) }

    override func keyDown(with e: NSEvent) {
        if punteroDentro { apagarHover() }
        let cmd = e.modifierFlags.contains(.command)
        let shift = e.modifierFlags.contains(.shift)
        let k = e.charactersIgnoringModifiers?.lowercased() ?? ""

        /*
         * ── EL MODO CLASE (F5) ─────────────────────────────────────────────
         * Se pone DELANTE de todo lo demás a propósito: mientras se da la
         * clase, el teclado no puede mover elementos ni abrir paletas. Un
         * empujón accidental durante la grabación se paga en la edición.
         */
        if e.keyCode == 96 {                                   // F5
            if enact.activo { enact.salir() } else {
                enact.alRepintar = { [weak self] in self?.needsDisplay = true }
                enact.entrar(tope: Enactar.tope(doc.elementos))
            }
            return
        }
        if enact.activo {
            switch e.keyCode {
            case 124, 49: enact.avanzar()        // → o barra espaciadora
            case 123: enact.retroceder()         // ←
            case 53: enact.salir()               // esc
            default: if k == "r" { enact.revelarTodo() }
            }
            return
        }

        /*
         * ── RECORTANDO ─────────────────────────────────────────────────────
         * Dos teclas y ninguna más, delante del resto por la misma razón que
         * el modo clase: en un modo, el teclado pertenece al modo. Enter
         * confirma, Esc se va. Daniel lo pidió así: *"arrastrar, ver sombreado
         * lo que voy a cortar, y darle enter"*.
         */
        if recorte != nil {
            switch e.keyCode {
            case 36, 76: confirmarRecorte()      // Intro y el Intro del bloque numérico
            case 53: cancelarRecorte()           // esc
            default: break
            }
            return
        }

        if e.keyCode == 49 { espacio = true; NSCursor.openHand.set(); return }   // barra espaciadora

        if cmd {
            switch k {
            /*
             * ⌘+/⌘− TAMBIÉN se rutean por DÓNDE está el puntero (24 ago 2026).
             * El lienzo es el primer respondedor siempre, así que sin este
             * desvío el teclado zoomeaba el canvas aunque la mano estuviera
             * sobre el sidebar — tercera vez que el zoom se colaba por un
             * camino distinto (pellizco, dial, teclado). El gancho lo pone el
             * Delegado: devuelve true si el puntero está sobre cromo y él ya
             * escaló la UI.
             */
            case "=", "+":
                if Lienzo.zoomUIFueraDelLienzo?(1.1) == true { return }
                zoomEn(punto: puntoRealDelCursor(), factor: 1.1); return
            case "-", "_":
                if Lienzo.zoomUIFueraDelLienzo?(1 / 1.1) == true { return }
                zoomEn(punto: puntoRealDelCursor(), factor: 1 / 1.1); return
            case "z": shift ? doc.rehacer() : doc.deshacer(); avisarSeleccion(); return
            case "a":
                doc.seleccion = shift
                    // ⌘⇧A selecciona el DIAGRAMA entero desde una de sus piezas:
                    // una región compilada se mueve como una unidad o no se
                    // mueve.
                    ? (doc.seleccion.first.map { doc.regionDe($0) } ?? Set(doc.elementos.map(\.id)))
                    : Set(doc.elementos.map(\.id))
                avisarSeleccion(); return
            case "d": doc.duplicar(doc.seleccion); avisarSeleccion(); return
            case "k": iniciarRecorte(); return
            case "g": shift ? doc.desagrupar() : doc.agrupar(); avisarSeleccion(); return
            case "c": copiar(); return
            case "x": copiar(); doc.borrarSeleccion(); avisarSeleccion(); return
            case "v": pegar(); return
            case "l" where shift: doc.alternarCandado(); avisarSeleccion(); return
            /*
             * ⌘] UNA CAPA ADELANTE · ⌘⇧] HASTA EL FRENTE (y al reves con [).
             *
             * Es lo que hacen Figma, Illustrator y Sketch, y la razon de que
             * coincidan es buena: el gesto CORTO hace el movimiento pequeño y
             * añadir Shift lo lleva al extremo. Antes ⌘] saltaba directo al
             * frente y no habia forma de mover una sola capa — que es
             * justamente lo que hace falta cuando dos cosas se tapan y solo
             * quieres cambiar cual de las DOS gana.
             */
            case "]": shift ? doc.alFrente() : doc.unaAdelante(); return
            case "[": shift ? doc.alFondo() : doc.unaAtras(); return
            default: break
            }
        }

        switch e.keyCode {
        case 51, 117:   // retroceso, suprimir
            doc.borrarSeleccion(); avisarSeleccion(); return
        case 53:
            /*
             * ESCAPE = VOLVER AL SELECTOR. La via de salida universal.
             *
             * Suelta la seleccion, cierra lo que este abierto y devuelve la
             * herramienta de seleccion. Desde que las herramientas se QUEDAN
             * puestas —para poder insertar cinco cajas seguidas sin cinco
             * viajes al rail— hace falta una tecla que diga "ya"; sin ella, la
             * unica forma de volver era apuntar al rail.
             */
            // Un gesto a medias se ABANDONA, no se confirma: Escape en mitad
            // de un arrastre significa "no era esto".
            if case .ninguno = gesto {} else {
                gesto = .ninguno
                doc.cerrarGesto("cancelar")
            }
            doc.seleccion = []
            herramienta = .seleccionar
            alEscapar?()
            avisarSeleccion()
            return
        case 36:        // intro
            /*
             * CON ALGO SELECCIONADO, EDITA. SIN NADA, PLIEGA LA CARPETA.
             *
             * Es el mismo reparto que las flechas: la tecla conserva su trabajo
             * de siempre mientras hay seleccion, y solo ocupa el hueco que
             * quedaba libre cuando no la hay — con el lienzo sin seleccionar,
             * intro no hacia nada.
             *
             * La carpeta es la del lienzo que estas viendo, igual que en los
             * atajos de numero: un solo criterio de "donde estoy" para todos
             * los atajos de navegacion, o cada tecla contaria una historia
             * distinta de en que parte del arbol te encuentras.
             */
            if let id = doc.seleccion.first { editarTexto(id); return }
            alAlternarCarpeta?()
            return
        case 123, 124, 125, 126:
            /*
             * SIN NADA SELECCIONADO, LAS FLECHAS CAMBIAN DE LIENZO.
             *
             * No se le quita nada al empujon fino: mientras haya algo
             * seleccionado las flechas siguen MOVIENDO, que es su trabajo y la
             * unica forma de colocar al pixel. La navegacion solo ocupa el
             * hueco que quedaba libre — con el lienzo vacio de seleccion, las
             * flechas no hacian absolutamente nada.
             *
             * Izquierda y arriba van hacia atras; derecha y abajo, hacia
             * delante. Los dos pares hacen lo mismo a proposito: la lista se
             * lee en vertical (arriba/abajo) y el curso avanza en horizontal
             * (atras/adelante), y no hay forma de saber cual de los dos modelos
             * mentales trae la mano en cada momento.
             */
            /*
             * ⚠️ EL GUARDIA VA DENTRO, NO EN UN `where` DEL `case`.
             *
             * `case 123, 124, 125, 126 where cond:` NO aplica la condicion a
             * los cuatro: en Swift el `where` se pega SOLO al ultimo patron de
             * la lista. Escrito asi, izquierda/derecha/abajo entraban SIEMPRE a
             * navegar y solo arriba miraba la seleccion — o sea que el empujon
             * fino se perdia en tres de las cuatro flechas. Comprobado con un
             * caso minimo antes de darlo por bueno, porque el codigo compila
             * igual y no dice nada.
             */
            if doc.seleccion.isEmpty && !cmd {
                /*
                 * HORIZONTAL = CARPETAS · VERTICAL = LIENZOS.
                 *
                 * Daniel, 26 ago: *"flecha a la derecha me mueve entre
                 * carpetas, por lo tanto no cambia de panel hasta que muevo
                 * hacia abajo"*. Los dos ejes hacen cosas de NATURALEZA
                 * distinta, y esa es toda la idea:
                 *
                 *   ← →   cambian de carpeta y NO abren nada. Solo mueven el
                 *         cursor, que se ve marcado en el panel.
                 *   ↑ ↓   entran en los lienzos de esa carpeta, y AHI si
                 *         cambia lo que estas viendo.
                 *
                 * Asi se puede recorrer el arbol entero sin cargar un solo
                 * lienzo, y elegir cuando bajar. La version anterior movia con
                 * las cuatro flechas y abria con todas: no habia forma de
                 * mirar sin abrir.
                 */
                switch e.keyCode {
                case 123: alCarpetaVecina?(-1)
                case 124: alCarpetaVecina?(1)
                case 126: alPaginaVecina?(-1)
                default:  alPaginaVecina?(1)
                }
                return
            }
            // Las flechas MUEVEN, con Shift a paso largo. Es la única forma de
            // ajustar un píxel sin pelear con el imán.
            let paso = shift ? 10.0 : 1.0
            let d: CGPoint = switch e.keyCode {
                case 123: CGPoint(x: -paso, y: 0)
                case 124: CGPoint(x: paso, y: 0)
                case 125: CGPoint(x: 0, y: paso)
                default:  CGPoint(x: 0, y: -paso)
            }
            guard !doc.seleccion.isEmpty else { return }
            doc.editar("mover") { els in
                for i in els.indices where doc.seleccion.contains(els[i].id) && !els[i].bloqueado {
                    els[i].mover(dx: d.x, dy: d.y)
                }
                els = Conectores.reruteaTodo(els)
            }
            return
        default: break
        }

        if k == "1" && shift { encuadrar(); return }
        /*
         * 0-9 SALTAN AL LIENZO N DE LA CARPETA ABIERTA.
         *
         * Es POSICION en la lista, no el numero del nombre: 0 es el primero,
         * 9 el decimo. En una carpeta numerada 00→08 las dos lecturas coinciden
         * —que es el caso que lo pidio— pero la posicion tambien funciona en
         * una carpeta que no numera nada, y el nombre no.
         *
         * ⚠️ POR QUE SE PUEDEN TOMAR LAS TECLAS SUELTAS SIN QUITAR NADA.
         * El `0` ya hacia zoom al 100% y el `⇧1` encuadrar — pero las dos
         * cosas viven TAMBIEN en el menu Ver como ⌘0 y ⌘1. Eran duplicados,
         * asi que el `0` suelto se cede sin perder la capacidad: ⌘0 sigue
         * llevando al tamaño real. El `⇧1` se comprueba ANTES, arriba, para
         * que encuadrar tampoco se pierda.
         */
        if let n = Int(k), k.count == 1, !cmd, !shift, alIrAPagina != nil {
            alIrAPagina?(n)
            return
        }
        if k == "0" { alCien(); return }
        // La rueda inferior de Huion puede emitir [ y ] (o , y .). Son atajos
        // sueltos a propósito: no entran al menú y no pueden abrir la hoja de
        // atajos. En la app REAL los coge antes un monitor local (main.swift),
        // para que el dial siga funcionando con el foco en el panel lateral;
        // esta puerta es la que conducen las escenas de verificación, y sirve
        // de red si el monitor no llegara a instalarse.
        if k == "]" { ajustarGrosor(1); return }
        if k == "[" { ajustarGrosor(-1); return }
        if k == "." { ajustarGrosor(1); return }
        if k == "," { ajustarGrosor(-1); return }
        /*
         * T = TEMA, y vive AQUÍ y no en el menú a propósito.
         *
         * Un `NSMenuItem` con `keyEquivalent` sin ⌘ se queda la letra en toda la
         * ventana: escribir "tema" en el buscador de lienzos apagaría la luz a
         * la primera letra. En el `keyDown` del lienzo la tecla solo llega
         * cuando el foco es el tablero, que es cuando la mano la quiere.
         * El ⌘T del menú sigue existiendo, para quien la busque donde se buscan.
         */
        /*
         * ⌃P LAPIZ · ⌃M MARCADOR · ⌃E GOMA — para los botones del lapiz fisico.
         *
         * Daniel, 26 ago: *"asi configurare los botones en el lapiz fisico de
         * la tableta"*. Van con CONTROL y no sueltas por dos motivos: las
         * letras sueltas ya reparten herramientas (V, H, N, L...) y una tableta
         * manda su combinacion sin que haya un dedo cerca del teclado — un
         * atajo para hardware tiene que ser imposible de pulsar por accidente
         * mientras se escribe.
         *
         * Y cada uno ABRE SU PANEL: elegir sin enseñar nada deja la mano sin
         * saber si el boton del lapiz hizo algo, porque no hay puntero sobre el
         * rail que lo resalte y lapiz y marcador comparten casilla.
         */
        if e.modifierFlags.contains(.control), !cmd,
           let h: Herramienta = switch k { case "p": .lapiz; case "m": .marcador; case "e": .goma
                                          default: nil } {
            herramienta = h
            alEnseñarGrupo?(h)
            return
        }
        if k == "t" && !cmd { alTema?(); return }
        if let h = Herramienta.porTecla[k], !cmd { herramienta = h; return }
        super.keyDown(with: e)
    }

    override func keyUp(with e: NSEvent) {
        if e.keyCode == 49 { espacio = false; cursorParaHerramienta(); return }
        super.keyUp(with: e)
    }

    // ── portapapeles ────────────────────────────────────────────────────────

    /// Copiar escribe JSON en el portapapeles del SISTEMA: así el pegado
    /// funciona entre ventanas y sobrevive a cerrar la app, en vez de vivir en
    /// una variable que se pierde con el proceso.
    /**
     * COPIAR. Y una excepción que vale por todo el gesto.
     *
     * Copiar elementos pone su JSON en el portapapeles: es lo que hace que
     * pegar en otro lienzo devuelva las figuras. Pero cuando lo seleccionado es
     * UN bloque de CÓDIGO o UN texto, lo que se quiere copiar casi siempre es
     * el TEXTO, no la figura — y en este curso literalmente: el bloque del
     * prompt existe para pegarse en tres arneses distintos delante de la
     * cámara. Daniel, 26 ago: *"no puedo ni seleccionarlo ni copiarlo"*.
     *
     * Se ponen LOS DOS en el portapapeles, con el JSON PRIMERO: el pegado de
     * sfmap busca su tipo y lo encuentra; cualquier otra app se queda con el
     * texto plano. Nadie pierde nada y el gesto obvio funciona.
     */
    private func copiar() {
        let sel = doc.seleccionados
        guard !sel.isEmpty else { return }
        let doc2 = Json.objeto(["sfmap": .numero(1), "elements": .lista(sel.map(\.crudo))])
        guard let d = try? JSONEncoder().encode(doc2), let s = String(data: d, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        if sel.count == 1, ["code", "text"].contains(sel[0].tipo) {
            let plano = sel[0].tipo == "code" ? (sel[0].crudo["code"]?.s ?? "")
                                              : sel[0].textoEditable
            if !plano.isEmpty {
                NSPasteboard.general.setString(plano, forType: .string)
                // El JSON viaja aparte, en el tipo propio de sfmap: así el
                // pegado interno sigue reconstruyendo la figura.
                NSPasteboard.general.setString(s, forType: Lienzo.tipoSFMap)
                return
            }
        }
        NSPasteboard.general.setString(s, forType: .string)
    }

    /// El tipo propio del portapapeles. Existe para poder llevar a la vez el
    /// texto plano (para el mundo) y el JSON (para sfmap).
    static let tipoSFMap = NSPasteboard.PasteboardType("so.saasfactory.sfmap.elementos")

    /// Crear en un punto CONCRETO, para el menú contextual del vacío. La
    /// herramienta de toque nace bajo el cursor y no en el centro de la vista.
    func crearAqui(_ h: Herramienta, en w: CGPoint) {
        let antes = herramienta
        herramienta = h
        crearDeToque(w)
        herramienta = antes
    }

    func pegarDesdeMenu() { pegar() }

    /**
     * DONDE VIVE UNA IMAGEN PEGADA.
     *
     * El lienzo viaja (esta en Supabase, se abre desde cualquier Mac) pero la
     * imagen NO viaja con el: el elemento guarda una RUTA. Asi que la ruta
     * tiene que ser una que exista igual en las tres maquinas, y la unica que
     * cumple eso es una dentro del repo, que va por git.
     *
     * Es la misma convencion que ya usan las evidencias de The Machinery: el
     * generador expande sus `src` relativos a `~/Developer/business-os/...`.
     * Aqui no se inventa nada, se sigue.
     *
     * ⚠️ Y el precio, dicho: hasta que el PNG este commiteado, en las OTRAS
     * Macs el lienzo enseña un marco de espera donde va la imagen. Una imagen
     * pegada es un archivo nuevo sin versionar, como cualquier otro.
     */
    private static var carpetaPegadas: URL? {
        let f = FileManager.default
        var d = URL(fileURLWithPath: NSString(string: "~/Developer/business-os/.claude/sfmap/imagenes")
            .expandingTildeInPath)
        // Por mes: una sola carpeta con trescientas capturas deja de ser
        // navegable, y encontrarlas a mano es justo lo que se hace cuando algo
        // sale mal.
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM"
        d.appendPathComponent(fmt.string(from: Date()))
        guard (try? f.createDirectory(at: d, withIntermediateDirectories: true)) != nil else { return nil }
        return d
    }

    /// Guarda el bitmap como PNG y devuelve (ruta absoluta, pixeles reales).
    ///
    /// Se normaliza SIEMPRE a PNG aunque llegue TIFF (que es lo que pone en el
    /// portapapeles una captura de macOS): un TIFF de pantalla completa pesa
    /// 20-30 MB donde el PNG pesa uno, y ese peso acabaria en el repo.
    static func guardarPegada(_ img: NSImage) -> (String, CGSize)? {
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]),
              let dir = Self.carpetaPegadas else { return nil }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = dir.appendingPathComponent("pegada-\(fmt.string(from: Date())).png")
        guard (try? png.write(to: url)) != nil else { return nil }
        // Los PIXELES, no los puntos: en una pantalla retina `img.size` da la
        // mitad, y la caja naceria al doble de resolucion de la que dice.
        return (url.path, CGSize(width: rep.pixelsWide, height: rep.pixelsHigh))
    }

    /// ¿Trae el portapapeles una imagen? Devuelve true si ya la coloco.
    ///
    /// Dos formas de llegar, y las dos hacen falta: un archivo copiado en el
    /// Finder viaja como URL (y ese NO se copia al repo — ya vive en disco y
    /// duplicarlo seria mentir sobre de donde salio), y una captura o un
    /// "copiar imagen" del navegador viaja como bitmap crudo, que si hay que
    /// escribir a algun sitio porque no tiene ninguno.
    private func pegarImagen() -> Bool {
        let pb = NSPasteboard.general
        let centro = puntoDePegado()

        let soloImagenes = [NSPasteboard.ReadingOptionKey.urlReadingContentsConformToTypes:
                                [UTType.image.identifier]]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: soloImagenes) as? [URL],
           let u = urls.first, let img = NSImage(contentsOf: u) {
            /*
             * LOS PIXELES SI SE PUEDEN, LOS PUNTOS SI NO.
             *
             * `NSBitmapImageRep` da la resolucion REAL, que es lo que hay que
             * declarar. Pero no parsea todo lo que `NSImage` sabe abrir —un
             * HEIC del iPhone, por ejemplo— y exigirlo tiraba el archivo
             * entero: se quedaba sin pegar sin decir por que. Cuando no lo
             * entiende se usa `img.size`, que da puntos en vez de pixeles; la
             * caja sale igual porque lo unico que importa es la PROPORCION, y
             * esa es la misma en las dos unidades.
             */
            let px = NSBitmapImageRep(data: (try? Data(contentsOf: u)) ?? Data())
                .map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? img.size
            doc.agregar([Crear.imagen(centro, src: u.path, natural: px,
                                      z: doc.zSiguiente, alt: u.lastPathComponent)], etiqueta: "pegar imagen")
            avisarSeleccion()
            return true
        }

        guard let img = NSImage(pasteboard: pb), let (ruta, px) = Self.guardarPegada(img) else { return false }
        doc.agregar([Crear.imagen(centro, src: ruta, natural: px,
                                  z: doc.zSiguiente, alt: "imagen pegada")], etiqueta: "pegar imagen")
        avisarSeleccion()
        return true
    }

    private func pegar() {
        // La imagen se mira ANTES que el texto: el portapapeles de una captura
        // suele traer TAMBIEN una cadena (la ruta, o el nombre), y comprobar
        // primero el texto convertiria cada captura en un bloque de letras.
        if pegarImagen() { return }
        // El tipo propio va PRIMERO: al copiar un bloque de código, el texto
        // plano del portapapeles es el prompt (para pegarlo en otra app) y las
        // figuras viajan aquí. Sin esto, copiar y pegar dentro de sfmap
        // convertiría una tarjeta en un párrafo.
        guard let s = NSPasteboard.general.string(forType: Lienzo.tipoSFMap)
                   ?? NSPasteboard.general.string(forType: .string) else { return }
        guard let d = s.data(using: .utf8), let j = try? JSONDecoder().decode(Json.self, from: d),
              j["sfmap"] != nil, let els = j["elements"]?.arr else {
            // Texto plano: nace como bloque de texto en el centro de la vista.
            // Es lo que la mano espera al pegar una frase en un lienzo.
            doc.agregar([Crear.texto(puntoDePegado(), texto: s, z: doc.zSiguiente, maxAncho: 420)],
                        etiqueta: "pegar")
            return
        }
        var mapa: [String: String] = [:]
        var copias: [Elemento] = []
        let z = doc.zSiguiente
        for (i, raw) in els.enumerated() {
            let viejo = Elemento(raw)
            let nuevoId = Crear.nuevoId(viejo.tipo)
            mapa[viejo.id] = nuevoId
            var c = viejo
            c.crudo = c.crudo.con(["id": .texto(nuevoId), "zIndex": .numero(z + Double(i))])
            copias.append(c)
        }
        /*
         * EL GRUPO ENTERO SE MUEVE, no cada pieza.
         *
         * Antes cada copia se desplazaba +28,+28 desde su original: bastaba
         * para no taparlo, y dejaba lo pegado donde estaba lo copiado — que
         * puede ser a tres pantallas de donde estas mirando. Ahora el CENTRO
         * del grupo aterriza bajo el raton, y se mueve todo con el mismo
         * vector para que las piezas conserven sus posiciones RELATIVAS: si se
         * recolocara cada una por su cuenta, pegar un diagrama de seis cajas
         * lo devolveria hecho un monton.
         */
        let cajas = copias.filter { $0.tipo != "connector" }.map(\.caja)
        if let primera = cajas.first {
            let grupo = cajas.dropFirst().reduce(primera) { $0.union($1) }
            let destino = puntoDePegado()
            let dx = destino.x - grupo.midX, dy = destino.y - grupo.midY
            for i in copias.indices where copias[i].tipo != "connector" {
                copias[i].mover(dx: dx, dy: dy)
            }
        }
        for i in copias.indices where copias[i].tipo == "connector" {
            guard let a = copias[i].desdeId, let b = copias[i].hastaId,
                  let na = mapa[a], let nb = mapa[b] else { copias[i].crudo = .nulo; continue }
            copias[i].crudo = copias[i].crudo.con(["fromId": .texto(na), "toId": .texto(nb)])
        }
        copias.removeAll { $0.id.isEmpty }
        doc.agregar(copias, etiqueta: "pegar")
        doc.volatil { $0 = Conectores.reruteaTodo($0) }
        avisarSeleccion()
    }
}
