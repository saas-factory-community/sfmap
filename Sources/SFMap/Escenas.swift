import AppKit

/**
 * EL CONDUCTOR DE ESCENAS. Solo tras `--escena <nombre>`.
 *
 * ⚠️ POR QUE EXISTE, y por que NO es un atajo.
 *
 * Una app nativa no se puede verificar desde fuera con clics: `CGEvent.post`
 * exige permiso de Accesibilidad para el proceso que los manda, y un agente no
 * lo tiene. Sin una via, la unica "prueba" posible seria abrir la ventana,
 * mirarla, y afirmar que lo demas tambien funciona — que es exactamente la
 * clase de verde que este proyecto persigue: un actuador reportando su
 * intencion en vez de su resultado.
 *
 * La tentacion era llamar directo al modelo (`doc.agregar(...)`) y capturar. Eso
 * NO prueba nada de lo que hay que probar: se saltaria la maquina de punteros
 * entera, que es justo la pieza fragil. Aqui se construyen NSEvent REALES y se
 * entregan a los MISMOS manejadores que recibe el raton — `mouseDown`,
 * `mouseDragged`, `mouseUp`, `keyDown`. Si el gesto esta roto, la escena sale
 * rota.
 *
 * Solo prepara el estado; capturar es cosa de quien mira.
 */
enum Escenas {

    static func nombrePedido() -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--escena"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    /// Un evento de raton en coordenadas de la VISTA, convertidas a la ventana.
    private static func evento(_ tipo: NSEvent.EventType, _ v: NSView, _ p: NSPoint,
                               _ mods: NSEvent.ModifierFlags = [], clics: Int = 1) -> NSEvent? {
        guard let w = v.window else { return nil }
        return NSEvent.mouseEvent(with: tipo, location: v.convert(p, to: nil),
                                  modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: w.windowNumber, context: nil,
                                  eventNumber: 0, clickCount: clics, pressure: 1)
    }

    private static func arrastrar(_ l: Lienzo, de a: NSPoint, a b: NSPoint, mods: NSEvent.ModifierFlags = []) {
        guard let d = evento(.leftMouseDown, l, a, mods) else { return }
        l.mouseDown(with: d)
        // Varios pasos, no uno: un arrastre de un solo salto no ejercita el
        // imantado ni el fantasma, que es la mitad de lo que hay que ver.
        for t in stride(from: 0.2, through: 1.0, by: 0.2) {
            let p = NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            if let m = evento(.leftMouseDragged, l, p, mods) { l.mouseDragged(with: m) }
        }
        if let u = evento(.leftMouseUp, l, b, mods) { l.mouseUp(with: u) }
    }

    private static func mover(_ l: Lienzo, a p: NSPoint) {
        if let m = evento(.mouseMoved, l, p) { l.mouseMoved(with: m) }
    }

    /*
     * ⚠️ EL CLIC VA AL BOTON, NO AL CONTENEDOR.
     *
     * La primera version mandaba `mouseDown` a la tarjeta que contiene el botón.
     * `NSView.mouseDown` no hace hit-testing: reparte el evento por la CADENA DE
     * RESPONDEDORES hacia arriba, y ahí acaba en manos de quien no lo pidió. En
     * la corrida del 20 ago eso creó un rectángulo en el lienzo desde un clic
     * dirigido al rail.
     *
     * Un evento entregado a mano tiene que entregarse a la vista EXACTA que lo
     * habría recibido; si no, se está probando otra cosa.
     */
    private static func clic(_ v: NSView, _ p: NSPoint, clics: Int = 1) {
        let destino = v.hitTest(v.superview.map { v.convert(p, to: $0) } ?? p) ?? v
        guard let d = evento(.leftMouseDown, destino, destino.convert(p, from: v), [], clics: clics) else { return }
        destino.mouseDown(with: d)
        if let u = evento(.leftMouseUp, destino, destino.convert(p, from: v), [], clics: clics) {
            destino.mouseUp(with: u)
        }
    }

    /// Teclea de verdad: los caracteres entran por el primer respondedor, que es
    /// el editor de texto si esta abierto.
    private static func teclear(_ w: NSWindow, _ texto: String) {
        for c in texto {
            guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: w.windowNumber, context: nil,
                                           characters: String(c), charactersIgnoringModifiers: String(c),
                                           isARepeat: false, keyCode: 0) else { continue }
            w.sendEvent(e)
        }
    }

    private static func luego(_ s: Double, _ f: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f)
    }

    /// Un lienzo VACIO para las escenas que crean cosas: montar sobre un
    /// diagrama de 38 elementos taparia lo que hay que ver.
    private static func limpiar(_ l: Lienzo) {
        l.doc.cargar([])
        l.camara = Camara(x: 0, y: 0, zoom: 1)
    }

    static func correr(_ nombre: String, _ d: Delegado) {
        let l = d.lienzo
        guard let w = d.ventana else { return }
        traza("escena: \(nombre)")
        // La sonda late DESPUES de que la escena termine: lo que se captura y lo
        // que dice el log son el mismo instante.
        for t in [4.0, 6.0, 8.0] {
            luego(t) { traza("sonda +\(Int(t))s · \(l.estadoParaSonda)") }
        }

        switch nombre {
        case "rail":
            // El rail con el desplegable de FORMAS abierto: dos clics, porque el
            // segundo sobre la herramienta ya activa es lo que abre variantes.
            d.rail.activa = .rect
            l.herramienta = .rect
            luego(0.3) {
                let b = d.rail.subviews.compactMap { $0 as? BotonPlano }
                    .first { $0.identifier?.rawValue == "formas" }
                if let b { clic(d.rail, NSPoint(x: b.frame.midX, y: b.frame.midY)) }
            }

        case "ajustes":
            /*
             * EL ZOOM DEL CROMO Y EL RESIZER, medidos desde dentro (24 ago).
             * Sin ratón sintético a propósito: el arrastre del asa vive en un
             * bucle modal de `nextEvent` y un evento entregado a mano lo deja
             * esperando (la misma trampa documentada arriba). Se verifica la
             * GEOMETRÍA y el CABLEADO, que es donde vivían los dos bugs.
             */
            if !d.lateralAbierta { d.header.alPulsar?() }
            luego(0.5) {
                guard let raiz = w.contentView else { return }
                let arriba = NSPoint(x: raiz.bounds.midX, y: raiz.bounds.height - 20)
                let panel = NSPoint(x: 40, y: raiz.bounds.midY)
                let centro = NSPoint(x: raiz.bounds.midX + 200, y: raiz.bounds.midY)
                traza("AJUSTES cromo(header)=\(d.punteroSobreCromo(arriba))"
                      + " cromo(panel)=\(d.punteroSobreCromo(panel))"
                      + " cromo(lienzo)=\(d.punteroSobreCromo(centro))")
                let antes = d.rail.frame.width
                let bandaAntes = d.banda.frame.height
                d.fijarEscalaUI(1.3)
                traza("AJUSTES rail \(Int(antes))→\(Int(d.rail.frame.width)) px"
                      + " · banda \(Int(bandaAntes))→\(Int(d.banda.frame.height)) px con escala 1.3")
                d.fijarEscalaUI(1.0)
                d.lateral.alCambiarAncho?(390)
                traza("AJUSTES panel ancho→\(Int(d.lateral.frame.width)) tras arrastre a x=390")
                d.lateral.alCambiarAncho?(300)
                let asa = d.lateral.subviews.contains { $0 is AgarreLateral }
                traza("AJUSTES asa presente=\(asa)")
            }

        case "tinta":
            d.rail.activa = .lapiz
            l.herramienta = .lapiz
            luego(0.3) {
                let b = d.rail.subviews.compactMap { $0 as? BotonPlano }
                    .first { $0.identifier?.rawValue == "tinta" }
                if let b { clic(d.rail, NSPoint(x: b.frame.midX, y: b.frame.midY)) }
            }

        case "figura":
            limpiar(l)
            l.herramienta = .rect
            d.rail.activa = .rect
            luego(0.4) {
                arrastrar(l, de: NSPoint(x: 520, y: 300), a: NSPoint(x: 860, y: 480))
                // Crear abre el cursor: se teclea de verdad y se cierra con Enter.
                luego(0.4) {
                    teclear(w, "Videos YT")
                    luego(0.3) { l.cerrarEditor(guardando: true) }
                }
            }

        case "barra":
            limpiar(l)
            l.herramienta = .rect
            luego(0.3) {
                arrastrar(l, de: NSPoint(x: 480, y: 330), a: NSPoint(x: 820, y: 500))
                luego(0.3) {
                    teclear(w, "Contorno")
                    l.cerrarEditor(guardando: true)
                    // Y se abre el popover de CONTORNO desde la barra real.
                    luego(0.5) {
                        let btn = d.barra.subviews.compactMap { $0 as? BotonPlano }
                            .first { $0.globo == "Contorno" }
                        if let btn { clic(d.barra, NSPoint(x: btn.frame.midX, y: btn.frame.midY)) }
                    }
                }
            }

        case "puerto":
            limpiar(l)
            l.herramienta = .rect
            luego(0.3) {
                arrastrar(l, de: NSPoint(x: 300, y: 340), a: NSPoint(x: 560, y: 480))
                luego(0.3) {
                    teclear(w, "Origen")
                    l.cerrarEditor(guardando: true)
                    l.herramienta = .seleccionar
                    d.rail.activa = .seleccionar
                    // El puntero se acerca para que el elemento OFREZCA sus
                    // puertos, y se arrastra desde el de la derecha al vacio.
                    luego(0.4) {
                        mover(l, a: NSPoint(x: 573, y: 410))
                        luego(0.3) {
                            arrastrar(l, de: NSPoint(x: 573, y: 410), a: NSPoint(x: 900, y: 412))
                            luego(0.4) {
                                teclear(w, "Siguiente")
                                luego(0.3) { l.cerrarEditor(guardando: true) }
                            }
                        }
                    }
                }
            }

        case "puerto-medio":
            // El MISMO gesto, congelado a media flecha: es donde se ve el
            // fantasma y la linea en curso, que al soltar ya no existen.
            limpiar(l)
            l.herramienta = .rect
            luego(0.3) {
                arrastrar(l, de: NSPoint(x: 300, y: 340), a: NSPoint(x: 560, y: 480))
                luego(0.3) {
                    teclear(w, "Origen")
                    l.cerrarEditor(guardando: true)
                    l.herramienta = .seleccionar
                    luego(0.4) {
                        mover(l, a: NSPoint(x: 573, y: 410))
                        luego(0.3) {
                            guard let ev = evento(.leftMouseDown, l, NSPoint(x: 573, y: 410)) else { return }
                            l.mouseDown(with: ev)
                            for t in stride(from: 0.2, through: 1.0, by: 0.2) {
                                let p = NSPoint(x: 573 + (880 - 573) * t, y: 410 + 6 * t)
                                if let m = evento(.leftMouseDragged, l, p) { l.mouseDragged(with: m) }
                            }
                        }
                    }
                }
            }

        case "surtido":
            // Una de cada tipo, para mirar el pintor entero de un vistazo.
            limpiar(l)
            let z = l.doc.zSiguiente
            var els: [Elemento] = []
            let formas = ["rect", "ellipse", "diamond", "triangle", "hexagon", "pill", "star", "arrow"]
            for (i, f) in formas.enumerated() {
                var e = Crear.figura(f, CGRect(x: Double(i % 4) * 210 - 400, y: Double(i / 4) * 150 - 320,
                                               width: 180, height: 120), z: z + Double(i))
                e.escribir(f)
                els.append(e)
            }
            els.append(Crear.nota(CGPoint(x: -300, y: 30), texto: "una nota adhesiva", z: z + 20))
            els.append(Crear.texto(CGPoint(x: -60, y: -30), texto: "Un bloque de texto libre que envuelve solo.",
                                   z: z + 21, maxAncho: 300))
            els.append(Crear.tabla(CGPoint(x: 330, y: 70),
                                   celdas: [["Pieza", "Estado"], ["motor", "vivo"], ["sensor", "falta"]], z: z + 22))
            els.append(Crear.codigo(CGPoint(x: -290, y: 250), codigo: "func medir() -> Double {\n  return ancho\n}", z: z + 23))
            var seccion = Crear.seccion(CGRect(x: -460, y: -400, width: 900, height: 330), titulo: "Las figuras")
            seccion.tocarSinFijar(["tint": .texto("morado")])
            els.append(seccion)
            l.doc.cargar(els + [])
            luego(0.2) { l.encuadrar() }

        case "paginas":
            // El arbol de lienzos, con las carpetas abiertas.
            luego(0.2) {
                if !d.lateralAbierta { d.alternarLateralMenu() }
                d.lateral.abrirTodas()
            }

        case "oscuro", "claro":
            UserDefaults.standard.set(nombre, forKey: "sfmap.tema")
            luego(0.2) { d.aplicarTemaPublico() }

        case "nota":
            // La nota recién puesta: amarilla, sin marco interno, con el cursor.
            limpiar(l)
            l.herramienta = .nota
            d.rail.activa = .nota
            luego(0.4) { clic(l, NSPoint(x: 620, y: 400)) }

        case "conectar-medio":
            // El gesto de conectar, CONGELADO encima del destino: es donde se ve
            // el resaltado, que al soltar ya no existe.
            limpiar(l)
            luego(0.3) {
                var a = Crear.figura("rect", CGRect(x: -430, y: -70, width: 190, height: 130), z: 1)
                a.escribir("Origen")
                var b = Crear.figura("rect", CGRect(x: 190, y: -70, width: 190, height: 130), z: 2)
                b.escribir("Destino")
                l.doc.cargar([a, b])
                l.camara = Camara(x: 0, y: 0, zoom: 1)
                l.herramienta = .seleccionar
                luego(0.4) {
                    let z = l.camara.zoom
                    func aVista(_ p: CGPoint) -> NSPoint {
                        NSPoint(x: (p.x - l.camara.x) * z + l.bounds.width / 2,
                                y: (p.y - l.camara.y) * z + l.bounds.height / 2)
                    }
                    let puerto = aVista(Geo.puertosDe(l.doc.elementos[0], zoom: z).first { $0.id == "e" }!.p)
                    let centro = aVista(CGPoint(x: l.doc.elementos[1].caja.midX, y: l.doc.elementos[1].caja.midY))
                    mover(l, a: puerto)
                    luego(0.3) {
                        guard let ev = evento(.leftMouseDown, l, puerto) else { return }
                        l.mouseDown(with: ev)
                        for t in stride(from: 0.2, through: 1.0, by: 0.2) {
                            let p = NSPoint(x: puerto.x + (centro.x - puerto.x) * t,
                                            y: puerto.y + (centro.y - puerto.y) * t)
                            if let m = evento(.leftMouseDragged, l, p) { l.mouseDragged(with: m) }
                        }
                    }
                }
            }

        case "diagonal":
            // El caso de la captura de Daniel, para MIRARLO: dos cajas en
            // diagonal, la flecha trazada entre ellas, y sus extremos a la vista.
            limpiar(d.lienzo)
            var da = Crear.figura("rect", CGRect(x: -420, y: -330, width: 300, height: 340), z: 1)
            da.escribir("A")
            var db = Crear.figura("rect", CGRect(x: 40, y: 120, width: 300, height: 360), z: 2)
            db.escribir("B")
            d.lienzo.doc.cargar([da, db])
            d.lienzo.camara = Camara(x: -60, y: -60, zoom: 0.9)
            d.lienzo.herramienta = .conector
            luego(0.6) {
                let l = d.lienzo, z = l.camara.zoom
                func aVista(_ p: CGPoint) -> NSPoint {
                    NSPoint(x: (p.x - l.camara.x) * z + l.bounds.width / 2,
                            y: (p.y - l.camara.y) * z + l.bounds.height / 2)
                }
                arrastrar(l, de: aVista(CGPoint(x: da.caja.midX, y: da.caja.midY)),
                          a: aVista(CGPoint(x: db.caja.midX, y: db.caja.midY)))
                l.herramienta = .seleccionar
                if let c = l.doc.elementos.first(where: { $0.tipo == "connector" }) {
                    traza("diagonal · ruta \(c.ruta.map { "(\(Int($0.x)),\(Int($0.y)))" }.joined(separator: " → "))")
                }
                // Y A seleccionada con el puntero en su esquina: es donde tiene
                // que aparecer la flechita de giro.
                l.doc.seleccion = [da.id]
                mover(l, a: aVista(CGPoint(x: da.caja.maxX + 14, y: da.caja.maxY + 14)))
                l.needsDisplay = true
            }

        case "flechas":
            // El grupo de flechas con sus tres formas abiertas.
            d.rail.activa = .conector
            l.herramienta = .conector
            luego(0.4) {
                let b = d.rail.subviews.compactMap { $0 as? BotonPlano }
                    .first { $0.identifier?.rawValue == "conector" }
                if let b { clic(d.rail, NSPoint(x: b.frame.maxX - 8, y: b.frame.maxY - 8)) }
            }

        case "prueba":
            gauntlet(l, w, d)

        case "sonda-tinta":
            sondaDeTinta(l, d)

        case "goma":
            pruebaGoma(l)

        case "opsroom":
            pruebaOpsroom(l, d)

        case "centro-de-mando":
            pruebaCentroDeMando(l)

        case "barra-panel":
            barraPanelFueraDePantalla()

        default:
            traza("escena desconocida: \(nombre)")
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: la sonda de tinta — latencia real, dentro de la app
    // ════════════════════════════════════════════════════════════════════════

    /**
     * CUÁNTO TARDA EL LIENZO EN PINTARSE MIENTRAS SE ESCRIBE. `--escena tinta`.
     *
     * El número que importa no es cuánto cuesta la geometría en un banco: es
     * cuánto tarda la VENTANA en repintarse entre una muestra de la pluma y la
     * siguiente, con el documento que Daniel tiene delante. A 120 Hz hay 8.3 ms
     * y ahí dentro cabe el fondo, los 71 elementos de la página, el cromo y el
     * trazo en curso.
     *
     * Se mide con `display()`, que fuerza el repintado SÍNCRONO en el mismo
     * hilo: así el reloj mide el dibujo de verdad y no cuánto tardó AppKit en
     * decidir cuándo dibujar. Es el peor caso honesto — un fotograma por
     * muestra, sin que el sistema agrupe ninguno.
     *
     * ⚠️ Lo que esto NO mide: el viaje del USB al proceso. Eso lo pone el
     * driver de Huion y nadie desde aquí lo puede cronometrar; decir lo
     * contrario sería inventar un número.
     */
    /**
     * LA GOMA, CONDUCIDA CON LA MANO.
     *
     * `GomaTests` mide la REGLA —qué alcanza el disco— y eso no dice nada del
     * cable: que un `mouseDown` con la goma marque en vez de borrar, que soltar
     * confirme, que Escape abandone. Esa parte solo se prueba conduciéndola.
     */
    private static func pruebaGoma(_ l: Lienzo) {
        pasos = 0; fallos = 0
        let z = { (w: CGPoint) -> NSPoint in
            NSPoint(x: (w.x - l.camara.x) * l.camara.zoom + l.bounds.width / 2,
                    y: (w.y - l.camara.y) * l.camara.zoom + l.bounds.height / 2)
        }
        func montar() {
            limpiar(l)
            l.doc.cargar([
                Elemento(.objeto([
                    "id": .texto("caja"), "type": .texto("shape"), "shape": .texto("rect"),
                    "x": .numero(-260), "y": .numero(-60),
                    "width": .numero(160), "height": .numero(120), "zIndex": .numero(1),
                ])),
                Elemento(.objeto([
                    "id": .texto("trazo"), "type": .texto("ink"),
                    "x": .numero(60), "y": .numero(0),
                    "width": .numero(200), "height": .numero(2),
                    "size": .numero(6), "zIndex": .numero(2),
                    "points": .lista((0...20).map { i in
                        .objeto(["x": .numero(Double(i) * 10), "y": .numero(0),
                                 "pressure": .numero(0.5)])
                    }),
                ])),
            ])
            l.herramienta = .goma
            l.goma = Goma(grosor: 28, alcance: .tinta)
        }

        // 1 · MARCA, no borra. Lo que se ve fantasma todavía está en el documento.
        montar()
        if let d = evento(.leftMouseDown, l, z(CGPoint(x: 160, y: 0))) { l.mouseDown(with: d) }
        exigir("con el botón abajo NADA se ha borrado todavía", l.doc.elementos.count == 2)
        exigir("y el trazo ya está marcado", l.estadoParaSonda.contains("borrar(marcados: 1)"))

        // 2 · Soltar confirma, y en UN solo paso de deshacer.
        if let u = evento(.leftMouseUp, l, z(CGPoint(x: 160, y: 0))) { l.mouseUp(with: u) }
        exigir("al soltar, el trazo se fue", !l.doc.elementos.contains { $0.tipo == "ink" })
        exigir("y la caja sigue ahí (alcance = tinta)", l.doc.elementos.contains { $0.id == "caja" })
        l.doc.deshacer()
        exigir("un solo deshacer devuelve el trazo entero", l.doc.elementos.count == 2)

        // 3 · ⌥ DESMARCA lo que se marcó por error, sin deshacer el barrido.
        montar()
        if let d = evento(.leftMouseDown, l, z(CGPoint(x: 160, y: 0))) { l.mouseDown(with: d) }
        exigir("marcado antes de ⌥", l.estadoParaSonda.contains("marcados: 1"))
        if let m = evento(.leftMouseDragged, l, z(CGPoint(x: 170, y: 0)), .option) {
            l.mouseDragged(with: m)
        }
        exigir("⌥ lo devuelve a la vida", l.estadoParaSonda.contains("marcados: 0"))
        if let u = evento(.leftMouseUp, l, z(CGPoint(x: 170, y: 0)), .option) { l.mouseUp(with: u) }
        exigir("y al soltar no se borró nada", l.doc.elementos.count == 2)

        // 4 · Con alcance `todo` sí se lleva el componente.
        montar()
        l.goma.alcance = .todo
        arrastrar(l, de: z(CGPoint(x: -200, y: 0)), a: z(CGPoint(x: -160, y: 0)))
        exigir("con alcance todo, la caja se va", !l.doc.elementos.contains { $0.id == "caja" })

        // 5 · El dial mueve la GOMA cuando la goma está en la mano, y no la tinta.
        montar()
        let tintaAntes = l.tinta.grosor
        l.ajustarGrosor(1)
        exigir("el dial subió el grosor de la goma", l.goma.grosor > 28)
        exigir("y no tocó el del lápiz", l.tinta.grosor == tintaAntes)
        l.herramienta = .lapiz
        let gomaAntes = l.goma.grosor
        l.ajustarGrosor(1)
        exigir("con el lápiz en la mano mueve la tinta", l.tinta.grosor > tintaAntes)
        exigir("y deja la goma como estaba", l.goma.grosor == gomaAntes)

        limpiar(l)
        traza("═══ PRUEBA DE LA GOMA: \(pasos - fallos)/\(pasos) ═══")
    }

    private static func sondaDeTinta(_ l: Lienzo, _ d: Delegado) {
        // Un documento REAL debajo. Medir sobre un lienzo en blanco daría el
        // coste del trazo y nada más, y el fotograma se paga entero.
        let fixture = "\(NSHomeDirectory())/Developer/software/sfmap/banco/trazos.json"
        let casos = BancoTinta.leerFixture(fixture)
        if let completo = casos.first(where: { $0.nombre == "real-completo" }) {
            var els: [Elemento] = []
            for (i, t) in completo.trazos.enumerated() {
                els.append(Elemento(.objeto([
                    "id": .texto("ink-sonda-\(i)"), "type": .texto("ink"),
                    "x": .numero(t.x), "y": .numero(t.y),
                    "size": .numero(t.grosor), "highlighter": .bool(t.marcador),
                    "updatedAt": .numero(Double(i)),
                    "points": .lista(t.puntos.map { q in
                        .objeto(["x": .numero(q.x), "y": .numero(q.y), "pressure": .numero(q.p)])
                    }),
                ])))
            }
            l.doc.cargar(els)
            l.camara = Camara(x: 320, y: 300, zoom: 1)
        }
        l.herramienta = .lapiz

        // Un fotograma en frío antes de medir: el primero paga la caché de
        // contornos de los 32 trazos guardados, y meterlo en la muestra diría
        // que escribir cuesta lo que cuesta abrir la página.
        l.display()

        var msPagina: [Double] = []
        for _ in 0..<20 {
            let t0 = CFAbsoluteTimeGetCurrent()
            l.setNeedsDisplay(l.bounds); l.display()
            msPagina.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        }

        // Y ahora el trazo: 600 muestras, que es lo que entrega la Kamvas en
        // cinco segundos con la fusión de eventos apagada.
        let n = 600
        var msTrazo: [Double] = []
        func punto(_ i: Int) -> NSPoint {
            let t = Double(i) / Double(n - 1)
            return NSPoint(x: 120 + 900 * t, y: 420 + 200 * sin(t * 9))
        }
        func evPluma(_ tipo: NSEvent.EventType, _ p: NSPoint, _ i: Int) -> NSEvent? {
            guard let w = l.window else { return nil }
            return NSEvent.mouseEvent(with: tipo, location: l.convert(p, to: nil), modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime + Double(i) * 0.004,
                                      windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                                      clickCount: 1,
                                      pressure: Float(0.15 + 0.4 * abs(sin(Double(i) / 60))))
        }
        if let e = evPluma(.leftMouseDown, punto(0), 0) { l.mouseDown(with: e) }
        for i in 1..<n {
            guard let e = evPluma(.leftMouseDragged, punto(i), i) else { continue }
            let t0 = CFAbsoluteTimeGetCurrent()
            l.mouseDragged(with: e)
            l.display()
            msTrazo.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        }
        if let e = evPluma(.leftMouseUp, punto(n - 1), n) { l.mouseUp(with: e) }
        l.display()

        /*
         * Y SE VUELCA EL ELEMENTO QUE ACABA DE NACER, crudo.
         *
         * Es la prueba del formato: lo que sfmap escribe tiene que abrirlo el
         * lienzo web. Volcar el JSON de verdad —el que sale de `terminarTrazo`,
         * no uno escrito a mano para la ocasión— es la única forma de que la
         * comprobación valga; un fixture inventado prueba el fixture.
         */
        if let nuevo = l.doc.elementos.last(where: { $0.tipo == "ink" && $0.id.hasPrefix("ink-") }),
           !nuevo.id.hasPrefix("ink-sonda"),
           let d = try? JSONEncoder().encode(nuevo.crudo) {
            try? d.write(to: URL(fileURLWithPath: "/tmp/trazo-sfmap.json"))
            traza("SONDA_TINTA volcado /tmp/trazo-sfmap.json · \(d.count) bytes · \(nuevo.trazoTinta.count) puntos")
        }

        func cuenta(_ v: [Double]) -> String {
            let s = v.sorted()
            func q(_ f: Double) -> Double { s[min(s.count - 1, Int(f * Double(s.count)))] }
            let media = v.reduce(0, +) / Double(v.count)
            return String(format: "n=%d media=%.2f p50=%.2f p95=%.2f max=%.2f ms · peor caso %.0f fps",
                          v.count, media, q(0.5), q(0.95), s[s.count - 1], 1000 / max(0.001, q(0.95)))
        }
        traza("SONDA_TINTA pagina-quieta (32 trazos guardados) · \(cuenta(msPagina))")
        traza("SONDA_TINTA trazo-en-vivo (hasta 600 muestras) · \(cuenta(msTrazo))")
        // El coste al final del trazo es el que decide: es cuando el recálculo
        // es más caro y es donde la mano notaría el frenazo.
        let cola = Array(msTrazo.suffix(100))
        traza("SONDA_TINTA ultimas-100-muestras · \(cuenta(cola))")
        traza("SONDA_TINTA elementos=\(l.doc.elementos.count) zoom=\(l.camara.zoom)")

        // Y una foto del lienzo DE VERDAD, con la tinta de Daniel dentro de la
        // app. El banco pinta en un mapa de bits aparte; esto es la ventana.
        if let rep = l.bitmapImageRepForCachingDisplay(in: l.bounds) {
            l.cacheDisplay(in: l.bounds, to: rep)
            if let d = rep.representation(using: .png, properties: [:]) {
                try? d.write(to: URL(fileURLWithPath: "/tmp/sfmap-tinta-app.png"))
                traza("SONDA_TINTA foto /tmp/sfmap-tinta-app.png \(rep.pixelsWide)x\(rep.pixelsHigh)")
            }
        }
        luego(1.0) { exit(0) }
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: la prueba de los gestos
    // ════════════════════════════════════════════════════════════════════════

    private static var pasos = 0
    private static var fallos = 0

    private static func exigir(_ que: String, _ cierto: Bool) {
        pasos += 1
        if !cierto { fallos += 1 }
        traza("\(cierto ? "✔" : "✘") \(que)")
    }

    /**
     * LA PRUEBA DE LA MAQUINA DE PUNTEROS.
     *
     * Las 51 pruebas unitarias cubren el MODELO: mover fija, el corte de texto,
     * el ruteo, el historial. Lo que ninguna cubre es el CABLE — que un
     * `mouseDown` en tal sitio con tal herramienta acabe llamando a lo que debe.
     * Esa es justo la pieza que el lienzo web llamaba "la frágil", y la que una
     * captura no puede demostrar: una imagen enseña un resultado, no si el
     * camino que llevó a él es el que la mano recorre.
     *
     * Aquí se conduce con eventos REALES y se comprueba el estado después de
     * cada gesto. Sale en el log con ✔ o ✘, y al final el conteo.
     */
    private static func gauntlet(_ l: Lienzo, _ w: NSWindow, _ d: Delegado) {
        pasos = 0; fallos = 0
        /*
         * ⚠️ TAMAÑO DE VENTANA FIJO. La prueba mide gestos, no monitores.
         *
         * Desde que la app abre a pantalla completa, el alto de la ventana
         * cambia entre corridas segun el monitor que restaure el autoguardado.
         * El rail va centrado en vertical, asi que se mueve con ella, y el panel
         * del lapiz se abre ARRIBA o ABAJO segun quepa: el mismo punto de la
         * paleta caia en el selector de grosor o en los colores. Sintoma: la
         * misma prueba daba 44, 42 y 38 en tres corridas seguidas.
         *
         * Una prueba que depende de en que pantalla arrancaste no esta midiendo
         * lo que dice medir.
         */
        w.setFrame(NSRect(x: 80, y: 80, width: 1440, height: 900), display: true)
        limpiar(l)
        var t = 0.0
        func paso(_ s: Double = 0.35, _ f: @escaping () -> Void) { t += s; luego(t, f) }

        // 1 · CREAR ARRASTRANDO, tres veces.
        paso { l.herramienta = .rect }
        paso { arrastrar(l, de: NSPoint(x: 200, y: 200), a: NSPoint(x: 380, y: 320)); l.cerrarEditor(guardando: false) }
        paso { l.herramienta = .rect }
        paso { arrastrar(l, de: NSPoint(x: 500, y: 420), a: NSPoint(x: 680, y: 540)); l.cerrarEditor(guardando: false) }
        paso { l.herramienta = .rect }
        paso { arrastrar(l, de: NSPoint(x: 800, y: 200), a: NSPoint(x: 980, y: 320)); l.cerrarEditor(guardando: false) }
        paso { exigir("arrastrar crea tres figuras", l.doc.elementos.count == 3) }

        // 2 · MARQUESINA sobre las tres.
        paso {
            l.herramienta = .seleccionar
            arrastrar(l, de: NSPoint(x: 120, y: 120), a: NSPoint(x: 1060, y: 620))
        }
        paso { exigir("la marquesina selecciona las tres", l.doc.seleccion.count == 3) }

        // 3 · CONECTAR dos y ACOMODAR.
        paso {
            l.doc.editar("conectar") { els in
                let ids = els.map(\.id)
                els.append(Crear.conector(ids[0], ids[1]))
                els.append(Crear.conector(ids[1], ids[2]))
                els = Conectores.reruteaTodo(els)
            }
            l.doc.seleccion = Set(l.doc.elementos.filter { $0.tipo == "shape" }.map(\.id))
        }
        paso {
            let antes = l.doc.elementos.filter { $0.tipo == "shape" }.map(\.x)
            let r = l.doc.acomodar()
            let despues = l.doc.elementos.filter { $0.tipo == "shape" }.map(\.x)
            exigir("acomodar mueve las tres (\(r.movidos))", r.movidos == 3 && antes != despues)
        }

        // 4 · DESHACER y REHACER.
        paso {
            let despuesDeAcomodar = l.doc.elementos.filter { $0.tipo == "shape" }.map(\.x)
            l.doc.deshacer()
            let deshecho = l.doc.elementos.filter { $0.tipo == "shape" }.map(\.x)
            exigir("deshacer revierte el acomodo entero", deshecho != despuesDeAcomodar)
            l.doc.rehacer()
            exigir("rehacer lo vuelve a poner",
                   l.doc.elementos.filter { $0.tipo == "shape" }.map(\.x) == despuesDeAcomodar)
        }

        // 5 · REDIMENSIONAR por la manija sureste.
        paso {
            l.doc.seleccion = [l.doc.elementos.first { $0.tipo == "shape" }!.id]
            let e = l.doc.seleccionados[0]
            let anchoAntes = e.ancho
            // La manija vive en coordenadas de MUNDO; se convierte a la vista.
            let z = l.camara.zoom
            let se = NSPoint(x: (e.caja.maxX - l.camara.x) * z + l.bounds.width / 2,
                             y: (e.caja.maxY - l.camara.y) * z + l.bounds.height / 2)
            arrastrar(l, de: se, a: NSPoint(x: se.x + 120, y: se.y + 60))
            let anchoDespues = l.doc.seleccionados[0].ancho
            exigir("la manija SE ensancha (\(Int(anchoAntes))→\(Int(anchoDespues)))", anchoDespues > anchoAntes + 60)
        }

        // 6 · GIRAR por el tirador.
        paso {
            let e = l.doc.seleccionados[0]
            let z = l.camara.zoom
            let g = Geo.centroGiro(e.cajaVisual, zoom: z)
            let p = NSPoint(x: (g.x - l.camara.x) * z + l.bounds.width / 2,
                            y: (g.y - l.camara.y) * z + l.bounds.height / 2)
            arrastrar(l, de: p, a: NSPoint(x: p.x + 150, y: p.y + 150))
            exigir("el tirador gira", abs(l.doc.seleccionados[0].giro) > 0.05)
        }

        // 7 · DIBUJAR con el lápiz.
        paso {
            l.herramienta = .lapiz
            arrastrar(l, de: NSPoint(x: 300, y: 620), a: NSPoint(x: 640, y: 700))
            exigir("el lápiz deja un trazo", l.doc.elementos.contains { $0.tipo == "ink" })
        }

        // 8 · BORRAR con la goma.
        paso {
            l.herramienta = .goma
            guard let tinta = l.doc.elementos.first(where: { $0.tipo == "ink" }) else { return }
            let z = l.camara.zoom
            let m = CGPoint(x: tinta.caja.midX, y: tinta.caja.midY)
            let p = NSPoint(x: (m.x - l.camara.x) * z + l.bounds.width / 2,
                            y: (m.y - l.camara.y) * z + l.bounds.height / 2)
            arrastrar(l, de: NSPoint(x: p.x - 30, y: p.y), a: NSPoint(x: p.x + 30, y: p.y))
            exigir("la goma se come el trazo", !l.doc.elementos.contains { $0.tipo == "ink" })
        }

        // 9 · COPIAR y PEGAR por el portapapeles del sistema.
        paso {
            l.herramienta = .seleccionar
            l.doc.seleccion = [l.doc.elementos.first { $0.tipo == "shape" }!.id]
            let antes = l.doc.elementos.count
            teclaCon(w, "c", .command); teclaCon(w, "v", .command)
            exigir("copiar y pegar añade uno", l.doc.elementos.count == antes + 1)
        }

        // 10 · DUPLICAR y ELIMINAR por teclado.
        paso {
            let antes = l.doc.elementos.count
            teclaCon(w, "d", .command)
            exigir("⌘D duplica", l.doc.elementos.count == antes + 1)
            teclaCon(w, String(UnicodeScalar(127)), [], codigo: 51)
            exigir("Supr elimina", l.doc.elementos.count == antes)
        }

        // 11 · La TECLA de herramienta.
        paso {
            teclaCon(w, "p", [])
            exigir("la tecla P cambia al lápiz", l.herramienta == .lapiz)
            teclaCon(w, "v", [])
            exigir("la tecla V vuelve a seleccionar", l.herramienta == .seleccionar)
        }

        // 12 · DOBLAR un conector: el gesto que le da productor a `waypoints`.
        //
        // Monta su PROPIO escenario limpio. Heredar el del paso anterior dejaba
        // la flecha tapada por las figuras duplicadas y la prueba medía dónde
        // habían caído, no si el gesto funciona.
        paso(0.5) {
            limpiar(l)
            var a = Crear.figura("rect", CGRect(x: -520, y: -60, width: 160, height: 110), z: 1)
            a.escribir("A")
            var b = Crear.figura("rect", CGRect(x: 360, y: -60, width: 160, height: 110), z: 2)
            b.escribir("B")
            let c = Crear.conector(a.id, b.id, z: -1, puertoDesde: "e", puertoHasta: "w")
            l.doc.cargar([a, b, Conectores.rutear(c, [a, b, c])])
            l.doc.seleccion = [c.id]
            l.camara = Camara(x: 0, y: 0, zoom: 1)
        }
        paso(0.5) {
            guard let c = l.doc.elementos.first(where: { $0.tipo == "connector" }) else {
                exigir("hay un conector que doblar", false); return
            }
            let pts = c.ruta
            var mejor = (largo: -1.0, m: CGPoint.zero)
            for i in 0..<max(0, pts.count - 1) {
                let m = CGPoint(x: (pts[i].x + pts[i+1].x)/2, y: (pts[i].y + pts[i+1].y)/2)
                guard Geo.elegir(l.doc.elementos, m, zoom: l.camara.zoom)?.id == c.id else { continue }
                let d = hypot(pts[i+1].x - pts[i].x, pts[i+1].y - pts[i].y)
                if d > mejor.largo { mejor = (d, m) }
            }
            guard mejor.largo > 0 else { exigir("hay un tramo despejado que agarrar", false); return }
            let z = l.camara.zoom
            let p = NSPoint(x: (mejor.m.x - l.camara.x) * z + l.bounds.width / 2,
                            y: (mejor.m.y - l.camara.y) * z + l.bounds.height / 2)
            arrastrar(l, de: p, a: NSPoint(x: p.x, y: p.y + 110))
            let codos = l.doc.porId(c.id)?.crudo["waypoints"]?.arr ?? []
            exigir("arrastrar el cuerpo del conector inserta un codo", codos.count == 1)
            let ruta = l.doc.porId(c.id)?.ruta ?? []
            // PASA POR el codo, no necesariamente como VÉRTICE: al colapsar los
            // colineales puede quedar en medio de un tramo recto. Exigir vértice
            // sería exigir un detalle de implementación en vez del
            // comportamiento — y la primera versión lo hacía, y salía en rojo
            // con la ruta perfectamente correcta.
            let cx = codos.first?["x"]?.num ?? 0, cy = codos.first?["y"]?.num ?? 0
            var pasa = false
            for i in 0..<max(0, ruta.count - 1) {
                let a = ruta[i], b = ruta[i+1]
                let dx = b.x - a.x, dy = b.y - a.y, l2 = dx*dx + dy*dy
                if l2 == 0 { continue }
                let t = max(0, min(1, ((cx - a.x)*dx + (cy - a.y)*dy) / l2))
                if hypot(cx - (a.x + t*dx), cy - (a.y + t*dy)) < 1 { pasa = true; break }
            }
            exigir("y la ruta pasa por él", pasa)
            // Y NO se dobla sobre sí misma: dos verticales en la misma X.
            var xs: [Double] = []
            for i in 0..<max(0, ruta.count - 1) where abs(ruta[i].x - ruta[i+1].x) < 0.5 { xs.append(ruta[i].x) }
            exigir("y no se dobla sobre sí misma", Set(xs).count == xs.count)
        }

        // 13 · CONECTAR DOS CAJAS: arrastrar del puerto de A al CUERPO de B.
        //      Es el gesto que Daniel dice que no funciona. Se reproduce antes
        //      de tocar nada: un fallo que no se puede repetir se "arregla"
        //      adivinando.
        paso(0.5) {
            limpiar(l)
            var a = Crear.figura("rect", CGRect(x: -420, y: -60, width: 180, height: 120), z: 1)
            a.escribir("A")
            var b = Crear.figura("rect", CGRect(x: 220, y: -60, width: 180, height: 120), z: 2)
            b.escribir("B")
            l.doc.cargar([a, b])
            l.camara = Camara(x: 0, y: 0, zoom: 1)
            l.herramienta = .seleccionar
        }
        paso(0.5) {
            let a = l.doc.elementos[0], b = l.doc.elementos[1]
            let z = l.camara.zoom
            func aVista(_ p: CGPoint) -> NSPoint {
                NSPoint(x: (p.x - l.camara.x) * z + l.bounds.width / 2,
                        y: (p.y - l.camara.y) * z + l.bounds.height / 2)
            }
            // El puerto ESTE de A, y el CENTRO de B.
            let puerto = aVista(Geo.puertosDe(a, zoom: z).first { $0.id == "e" }!.p)
            let centroB = aVista(CGPoint(x: b.caja.midX, y: b.caja.midY))
            mover(l, a: puerto)
            let antes = l.doc.elementos.count
            arrastrar(l, de: puerto, a: centroB)
            let conectores = l.doc.elementos.filter { $0.tipo == "connector" }
            exigir("del puerto de A al cuerpo de B: NACE un conector", conectores.count == 1)
            exigir("y NO nace una figura nueva (\(antes)→\(l.doc.elementos.count))",
                   l.doc.elementos.count == antes + 1)
            if let c = conectores.first {
                exigir("y une A con B", c.desdeId == a.id && c.hastaId == b.id)
            }
        }

        // 14 · LOS BOTONES de deshacer/rehacer de la barra, pulsados de verdad.
        //      Un `isEnabled = false` los saca del hit-testing de AppKit: si el
        //      contador del historial no se refresca, el botón se ve normal y
        //      está MUERTO. No lo puede ver una captura.
        paso(0.5) {
            limpiar(l)
            l.herramienta = .rect
            arrastrar(l, de: NSPoint(x: 400, y: 300), a: NSPoint(x: 620, y: 440))
            l.cerrarEditor(guardando: false)
            l.herramienta = .seleccionar
        }
        paso(0.5) {
            let n = l.doc.elementos.count
            let botones = d.estado.subviews.compactMap { $0 as? BotonPlano }
            guard let undo = botones.first(where: { ($0.globo ?? "").hasPrefix("Deshacer") }),
                  let redo = botones.first(where: { ($0.globo ?? "").hasPrefix("Rehacer") }) else {
                exigir("la barra tiene botones de deshacer y rehacer", false); return
            }
            exigir("el botón de deshacer está VIVO tras crear algo", undo.isEnabled)
            clic(d.estado, NSPoint(x: undo.frame.midX, y: undo.frame.midY))
            exigir("y al pulsarlo se deshace (\(n)→\(l.doc.elementos.count))", l.doc.elementos.count == n - 1)
            exigir("el de rehacer se enciende", redo.isEnabled)
            clic(d.estado, NSPoint(x: redo.frame.midX, y: redo.frame.midY))
            exigir("y al pulsarlo se rehace", l.doc.elementos.count == n)
        }

        // 15 · ⌘Z y ⌘⇧Z por el MENÚ, que es quien se queda con la tecla.
        paso(0.5) {
            let n = l.doc.elementos.count
            teclaPorLaVentana(w, "z", [.command])
            exigir("⌘Z deshace", l.doc.elementos.count == n - 1)
            teclaPorLaVentana(w, "Z", [.command, .shift])
            exigir("⌘⇧Z rehace", l.doc.elementos.count == n)
        }

        // 16 · La NOTA nace amarilla, y el zoom va al derecho.
        paso(0.5) {
            limpiar(l)
            l.herramienta = .nota
            clic(l, NSPoint(x: 600, y: 400))
            l.cerrarEditor(guardando: false)
            exigir("la nota nace con el rol amarillo", l.doc.elementos.first?.rol == "nota")
            let z0 = l.camara.zoom
            rueda(l, dy: 10, mods: .command)
            exigir("scroll ARRIBA acerca (\(String(format: "%.2f", z0))→\(String(format: "%.2f", l.camara.zoom)))",
                   l.camara.zoom > z0)
            rueda(l, dy: -10, mods: .command)
            exigir("scroll ABAJO aleja", l.camara.zoom < z0 + 0.001)

            // Y SIN modificador la rueda MUEVE, en los dos ejes. El 23 ago se
            // rompió justo aquí: reconocer al dial de la tableta por "no tiene
            // deltas precisos" metía al ratón entero en la rama del zoom, así
            // que la rueda vertical acercaba y la horizontal no hacía nada.
            l.camara.zoom = 1; l.camara.x = 0; l.camara.y = 0
            rueda(l, dy: -20, mods: [])
            exigir("la rueda sin ⌘ MUEVE en vertical (y=\(l.camara.y))", l.camara.y != 0)
            exigir("y no toca el zoom", abs(l.camara.zoom - 1) < 0.0001)
            let yTrasVertical = l.camara.y
            rueda(l, dy: 0, dx: -20, mods: [])
            exigir("el giro HORIZONTAL mueve en horizontal (x=\(l.camara.x))", l.camara.x != 0)
            exigir("y no arrastra el eje vertical con él", l.camara.y == yTrasVertical)
            // La cámara vuelve a su sitio: los pasos que siguen apuntan a
            // coordenadas concretas y una prueba que deja el lienzo corrido
            // hace fallar a las otras cinco, no a la suya.
            l.camara.x = 0; l.camara.y = 0; l.camara.zoom = 1
        }

        // 17 · EL PUNTO de variantes abre el desplegable AL PRIMER CLIC.
        //      Daniel: *"el lápiz no tiene todavía sus tres variantes"*. Las
        //      tenía, y solo abrían al SEGUNDO clic — no había forma de llegar a
        //      ellas sin saber que había que volver a pulsar.
        paso(0.5) {
            let b = d.rail.subviews.compactMap { $0 as? BotonPlano }
                .first { $0.identifier?.rawValue == "tinta" }
            guard let b else { exigir("el rail tiene grupo de tinta", false); return }
            let antes = d.rail.superview?.subviews.count ?? 0
            // La esquina INFERIOR derecha del botón, que en el rail volteado es
            // `maxY`. La primera versión apuntó a la de arriba y la prueba salió
            // en rojo midiendo mi puntería otra vez.
            let pLocal = NSPoint(x: b.frame.maxX - 8, y: b.frame.maxY - 8)
            clic(d.rail, pLocal)
            let despues = d.rail.superview?.subviews.count ?? 0
            exigir("el punto abre las variantes al primer clic", despues == antes + 1)
        }

        // 18 · LO QUE DANIEL DICE QUE NO RESPONDE. Se reproduce antes de tocarlo.
        paso(0.5) {
            limpiar(l)
            l.herramienta = .seleccionar
            var t = Crear.texto(CGPoint(x: -200, y: -30), texto: "alinéame", z: 1, maxAncho: 400)
            t.crudo = t.crudo.con("id", .texto("T"))
            l.doc.cargar([t])
            l.doc.seleccion = ["T"]
            l.camara = Camara(x: 0, y: 0, zoom: 1)
        }
        paso(0.5) {
            exigir("el texto nuevo nace CENTRADO", l.doc.porId("T")?.alineacion == "center")
            // Y una SECCIÓN también obedece: su rótulo estaba clavado a la izquierda.
            var sec = Crear.seccion(CGRect(x: -300, y: -300, width: 600, height: 200), titulo: "hi")
            sec.aplicarTipografia(Tipografia(alineacion: "center"))
            exigir("la sección acepta alineación", sec.alineacion == "center")
            // Alinear a la izquierda por el mismo camino que la barra.
            l.doc.editar("alinear") { els in els[0].aplicarTipografia(Tipografia(alineacion: "left")) }
            exigir("alinear a la izquierda cambia la alineación", l.doc.porId("T")?.alineacion == "left")
            // Y que el PINTOR lo respete: el ancho del renglón contra su caja.
            let e = l.doc.porId("T")!
            exigir("y el bloque conserva su ancho de columna", e.ancho >= 380)
        }
        paso(0.5) {
            // EL GROSOR, por el camino REAL: abrir el desplegable del rail y
            // pulsar la barra. Medirlo sobre una paleta suelta fuera de la
            // ventana probaba otra cosa — de hecho salía en rojo por eso.
            l.herramienta = .lapiz
            // El paso anterior dejó ESTE desplegable abierto: sin cerrarlo, el
            // clic lo cierra y la prueba mide un panel que no existe.
            d.rail.cerrarDesplegable()
            let b = d.rail.subviews.compactMap { $0 as? BotonPlano }
                .first { $0.identifier?.rawValue == "tinta" }
            if let b { clic(d.rail, NSPoint(x: b.frame.maxX - 8, y: b.frame.maxY - 8)) }
        }
        paso(0.6) {
            // ⚠️ LA PALETA VISIBLE, no la primera que aparezca. Un panel cerrado
            // sigue en la jerarquia un rato, y coger ese daba una paleta real
            // sobre la que los clics no caen en ningun sitio: los dos ✘ salian
            // con el panel bueno abierto delante.
            guard let paleta = d.rail.superview?.subviews
                .compactMap({ v -> PaletaTinta? in
                    guard !v.isHiddenOrHasHiddenAncestor else { return nil }
                    return v.subviews.compactMap { $0 as? PaletaTinta }.first
                }).first(where: { $0.bounds.width > 40 }) else {
                exigir("el desplegable del lápiz trae su paleta", false); return
            }
            paleta.window?.makeKeyAndOrderFront(nil)
            paleta.layoutSubtreeIfNeeded()
            let antes = l.tinta.grosor
            let n = CGFloat(RailHerramientas.grosores.count)
            let anchoB = (paleta.bounds.width - (n - 1) * 3) / n
            let x = 2 * (anchoB + 3) + anchoB / 2
            clic(paleta, NSPoint(x: x, y: 67))
            exigir("pulsar un grosor lo elige (\(antes)→\(l.tinta.grosor))",
                   l.tinta.grosor == RailHerramientas.grosores[2])
            // Y un color, por el mismo camino.
            clic(paleta, NSPoint(x: 32, y: 10))
            exigir("y pulsar un color lo elige (\(l.tinta.color ?? "tema"))", l.tinta.color != nil)
            // Y que la PALETA se entere: es lo que la mano ve.
            exigir("la paleta refleja lo elegido", paleta.actual.grosor == l.tinta.grosor
                                                && paleta.actual.color == l.tinta.color)
        }
        paso(0.5) {
            // LA HERRAMIENTA DE FLECHA: clic en A, arrastre al cuerpo de B.
            limpiar(l)
            var a = Crear.figura("rect", CGRect(x: -420, y: -60, width: 180, height: 120), z: 1)
            a.escribir("A")
            var b = Crear.figura("rect", CGRect(x: 220, y: -60, width: 180, height: 120), z: 2)
            b.escribir("B")
            l.doc.cargar([a, b])
            l.camara = Camara(x: 0, y: 0, zoom: 1)
            l.herramienta = .conector
        }
        paso(0.5) {
            let a = l.doc.elementos[0], b = l.doc.elementos[1]
            let z = l.camara.zoom
            func aVista(_ p: CGPoint) -> NSPoint {
                NSPoint(x: (p.x - l.camara.x) * z + l.bounds.width / 2,
                        y: (p.y - l.camara.y) * z + l.bounds.height / 2)
            }
            let antes = l.doc.elementos.count
            arrastrar(l, de: aVista(CGPoint(x: a.caja.midX, y: a.caja.midY)),
                      a: aVista(CGPoint(x: b.caja.midX, y: b.caja.midY)))
            let cs = l.doc.elementos.filter { $0.tipo == "connector" }
            exigir("la HERRAMIENTA de flecha conecta A con B", cs.count == 1)
            exigir("y no crea figuras (\(antes)→\(l.doc.elementos.count))", l.doc.elementos.count == antes + 1)
            exigir("tras trazar VUELVE la flecha de seleccion", l.herramienta == .seleccionar)
        }

        paso(0.6) {
            /*
             * EL CASO DE LA CAPTURA: dos cajas en DIAGONAL.
             *
             * Daniel: *"flechas nunca adentro de componentes"*. Aqui se mide en
             * la app viva —no solo en la prueba de unidad— porque lo que el vio
             * fue el DIBUJO, y el dibujo sale de `ruta`, que es lo que se
             * inspecciona.
             */
            limpiar(l)
            var a = Crear.figura("rect", CGRect(x: -420, y: -330, width: 300, height: 340), z: 1)
            a.escribir("A")
            var b = Crear.figura("rect", CGRect(x: 40, y: 120, width: 300, height: 360), z: 2)
            b.escribir("B")
            l.doc.cargar([a, b])
            l.camara = Camara(x: 0, y: 0, zoom: 0.8)
            l.herramienta = .conector
        }
        paso(0.5) {
            let a = l.doc.elementos[0], b = l.doc.elementos[1]
            let z = l.camara.zoom
            func aVista(_ p: CGPoint) -> NSPoint {
                NSPoint(x: (p.x - l.camara.x) * z + l.bounds.width / 2,
                        y: (p.y - l.camara.y) * z + l.bounds.height / 2)
            }
            arrastrar(l, de: aVista(CGPoint(x: a.caja.midX, y: a.caja.midY)),
                      a: aVista(CGPoint(x: b.caja.midX, y: b.caja.midY)))
            guard let c = l.doc.elementos.first(where: { $0.tipo == "connector" }) else {
                exigir("en diagonal nace el conector", false); return
            }
            let r = c.ruta
            var dentro = 0
            for i in 0..<max(0, r.count - 1) {
                let tramo = CGRect(x: min(r[i].x, r[i+1].x), y: min(r[i].y, r[i+1].y),
                                   width: abs(r[i+1].x - r[i].x), height: abs(r[i+1].y - r[i].y))
                    .insetBy(dx: 1, dy: 1)
                for e in [a, b] where tramo.intersects(e.caja.insetBy(dx: 1, dy: 1)) { dentro += 1 }
            }
            exigir("en diagonal, NINGUN tramo entra en una caja (\(dentro) invasiones)", dentro == 0)
        }
        paso(0.6) {
            // REENGANCHAR: se agarra el extremo de la flecha y se suelta en C.
            var c = Crear.figura("rect", CGRect(x: -420, y: 180, width: 260, height: 200), z: 3)
            c.escribir("C")
            l.doc.agregar([c], etiqueta: "tercera")
            if let conn = l.doc.elementos.first(where: { $0.tipo == "connector" }) {
                l.doc.seleccion = [conn.id]
            }
            l.needsDisplay = true
        }
        paso(0.5) {
            let z = l.camara.zoom
            func aVista(_ p: CGPoint) -> NSPoint {
                NSPoint(x: (p.x - l.camara.x) * z + l.bounds.width / 2,
                        y: (p.y - l.camara.y) * z + l.bounds.height / 2)
            }
            guard let conn = l.doc.elementos.first(where: { $0.tipo == "connector" }),
                  let ce = l.doc.elementos.last(where: { $0.tipo == "shape" }),
                  let fin = conn.ruta.last else {
                exigir("hay flecha y hay C", false); return
            }
            let destinoAntes = conn.hastaId
            arrastrar(l, de: aVista(fin), a: aVista(CGPoint(x: ce.caja.minX + 12, y: ce.caja.midY)))
            let ahora = l.doc.porId(conn.id)
            exigir("arrastrar el extremo lo reengancha a C",
                   ahora?.hastaId == ce.id && ahora?.hastaId != destinoAntes)
            exigir("y se queda por el lado donde lo soltaste", ahora?.crudo["toPort"]?.s == "w")
            exigir("y no nacio ninguna figura suelta (3)", l.doc.elementos.count == 4)
        }

        // 19 · Y que NADA de esto se guardó.
        paso(1.2) {
            traza("═══ PRUEBA DE GESTOS: \(pasos - fallos)/\(pasos) ═══")
            traza("sonda final · \(l.estadoParaSonda)")
        }
    }

    /// Por la VENTANA: así pasa por el menú principal, que es quien se queda con
    /// los equivalentes de teclado. Mandarlo al lienzo probaría el otro camino.
    private static func teclaPorLaVentana(_ w: NSWindow, _ c: String, _ mods: NSEvent.ModifierFlags) {
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods,
                                       timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: w.windowNumber, context: nil,
                                       characters: c, charactersIgnoringModifiers: c,
                                       isARepeat: false, keyCode: 6) else { return }
        if NSApp.mainMenu?.performKeyEquivalent(with: e) != true { w.sendEvent(e) }
    }

    /// Una muesca de rueda, con sus modificadores. Los DOS ejes: el giro
    /// horizontal existe (rueda de pulgar) y durante un día no hizo nada.
    private static func rueda(_ v: NSView, dy: Double, dx: Double = 0, mods: NSEvent.ModifierFlags) {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                               wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else { return }
        cg.flags = mods.contains(.command) ? .maskCommand : []
        guard let e = NSEvent(cgEvent: cg) else { return }
        v.scrollWheel(with: e)
    }

    private static func teclaCon(_ w: NSWindow, _ c: String, _ mods: NSEvent.ModifierFlags, codigo: UInt16 = 0) {
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods,
                                       timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: w.windowNumber, context: nil,
                                       characters: c, charactersIgnoringModifiers: c,
                                       isARepeat: false, keyCode: codigo) else { return }
        // Directo al lienzo: por la ventana lo interceptaría el menú principal,
        // que es otro camino y no el que se quiere probar aquí.
        (w.contentView?.subviews.compactMap { $0 as? Lienzo }.first)?.keyDown(with: e)
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: el opsroom — que un nodo LLEVE a donde promete
    // ════════════════════════════════════════════════════════════════════════

    /**
     * ⚠️ POR QUE ESTA ESCENA EXISTE, y no basta con `EnlaceTests`.
     *
     * Las pruebas de unidad demuestran que `doc:` y `page:` se LEEN bien. Lo que
     * no pueden demostrar es EL CABLE: que un clic sobre la marca de un nodo
     * acabe llamando al despacho, y no en otra parte de la cadena de
     * respondedores. Ese es el eslabón frágil —el mismo que el 20 ago creó un
     * rectángulo desde un clic dirigido al rail— y una foto tampoco lo prueba:
     * una imagen enseña un resultado, no si el camino que llevó a él es el que
     * recorre la mano.
     *
     * Y no se puede verificar desde fuera: `CGEvent.post` exige permiso de
     * Accesibilidad que el agente no tiene. Por eso se conduce desde dentro.
     */
    private static func pruebaOpsroom(_ l: Lienzo, _ d: Delegado) {
        pasos = 0; fallos = 0

        // Un lienzo de mentira con los cuatro destinos, para no depender de que
        // una página real de Daniel siga teniendo tal nodo en tal sitio.
        func nodo(_ id: String, _ x: Double, _ liga: String?, rol: String = "card") -> Elemento {
            var o: [String: Json] = [
                "id": .texto(id), "type": .texto("shape"), "shape": .texto("rect"),
                "role": .texto(rol),
                "x": .numero(x), "y": .numero(0), "width": .numero(220), "height": .numero(110),
                "rotation": .numero(0), "zIndex": .numero(1), "opacity": .numero(1),
                "locked": .bool(false), "version": .numero(1),
                "createdAt": .numero(0), "updatedAt": .numero(0),
            ]
            if let liga { o["link"] = .texto(liga) }
            return Elemento(.objeto(o))
        }
        l.doc.cargar([
            nodo("n:doc", 0, "doc:CLAUDE.md"),
            nodo("n:page", 300, "page:6b9dce83-d426-4025-8d81-e852a670b418"),
            nodo("n:web", 600, "https://saasfactory.so"),
            nodo("n:mudo", 900, nil),
        ])
        l.camara = Camara(x: 560, y: 55, zoom: 1)
        l.herramienta = .seleccionar
        l.needsDisplay = true
        l.layoutSubtreeIfNeeded()

        // El destino que el despacho recibe, capturado sin abrir nada: la escena
        // NO debe navegar de verdad (arrastraría la red y la ventana de Daniel).
        var recibido: [String] = []
        let antes = l.alAbrirEnlace
        l.alAbrirEnlace = { recibido.append($0) }
        defer { l.alAbrirEnlace = antes }

        /// El punto de PANTALLA donde se pintó la marca de un nodo. Se calcula
        /// con los MISMOS números del pintor: si el hit-test y el pintado
        /// discreparan, esta escena sería el sensor que lo dice.
        func puntoMarca(_ id: String) -> NSPoint? {
            guard let e = l.doc.elementos.first(where: { $0.id == id }) else { return nil }
            let c = Pintor.centroMarca(e, zoom: l.camara.zoom)
            let p = CGPoint(x: (c.x - l.camara.x) * l.camara.zoom + l.bounds.width / 2,
                            y: (c.y - l.camara.y) * l.camara.zoom + l.bounds.height / 2)
            return NSPoint(x: p.x, y: p.y)
        }

        func clicEn(_ id: String) {
            guard let p = puntoMarca(id), let ev = evento(.leftMouseDown, l, p) else { return }
            l.mouseDown(with: ev)
            if let u = evento(.leftMouseUp, l, p) { l.mouseUp(with: u) }
        }

        clicEn("n:doc")
        exigir("clic en la marca de un nodo `doc:` despacha su ruta",
               recibido.last == "doc:CLAUDE.md")

        clicEn("n:page")
        exigir("clic en la marca de un nodo `page:` despacha su lienzo",
               recibido.last?.hasPrefix("page:") == true)

        clicEn("n:web")
        exigir("clic en la marca de un nodo web despacha su URL",
               recibido.last == "https://saasfactory.so")

        // Un nodo SIN liga no dispara nada: si lo hiciera, seleccionar una caja
        // cualquiera abriría cosas, que es peor que no abrir ninguna.
        let cuantas = recibido.count
        clicEn("n:mudo")
        exigir("un nodo sin liga no despacha nada", recibido.count == cuantas)

        // Y el CENTRO de la caja tampoco: la marca es un botón, el cuerpo no.
        if let e = l.doc.elementos.first(where: { $0.id == "n:doc" }) {
            let c = CGPoint(x: e.caja.midX, y: e.caja.midY)
            let p = NSPoint(x: (c.x - l.camara.x) * l.camara.zoom + l.bounds.width / 2,
                            y: (c.y - l.camara.y) * l.camara.zoom + l.bounds.height / 2)
            if let ev = evento(.leftMouseDown, l, p) { l.mouseDown(with: ev) }
            if let u = evento(.leftMouseUp, l, p) { l.mouseUp(with: u) }
            exigir("el CUERPO de la caja selecciona, no abre",
                   recibido.count == cuantas && l.doc.seleccion.contains("n:doc"))
        }

        // El panel de documento, con un markdown REAL del repo.
        let panel = d.panelDoc
        panel.frame = NSRect(x: 0, y: 0, width: 470, height: 700)
        panel.layoutSubtreeIfNeeded()
        exigir("el panel abre un markdown real del repo",
               panel.mostrar("docs/business-os/MAPA-FUENTES-DE-VERDAD.md"))
        exigir("y DICE que no encontró lo que no existe",
               !panel.mostrar("docs/no-existe-jamas.md"))

        traza("OPSROOM \(pasos - fallos)/\(pasos) pasos" + (fallos == 0 ? " · TODO VERDE" : " · \(fallos) FALLOS"))
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: el centro de mando — el conmutador conducido y el coste del arrastre
    // ════════════════════════════════════════════════════════════════════════

    /**
     * `--escena centro-de-mando`. Dos cosas que solo se pueden comprobar
     * CONDUCIENDO la app, no con una prueba de unidad:
     *
     * 1. Que el conmutador de vista **se deja pulsar de verdad**. Las pruebas
     *    miden dónde CREE el pintor que están los chips; esto manda un
     *    `NSEvent` a la ventana y mira si la vista cambió. Entre las dos hay un
     *    cable —el `mouseDown` del lienzo— y ese cable es justo donde el botón
     *    se puede perder.
     *
     * 2. Cuánto CUESTA el widget en un fotograma. El panel vive abierto y se
     *    arrastra a diario; un calendario de siete columnas con cuarenta
     *    bloques y texto real se paga en cada `display()`. Se mide con y sin
     *    los widgets sobre el MISMO documento: la diferencia es el precio.
     */
    /**
     * EL PANEL DE ESTILO SOBREVIVE A SUS PROPIOS CAMBIOS. `--escena barra-panel`.
     *
     * Daniel, 25 ago: *"el componente que me permite modificar el grosor de
     * este rombo, al intentar adaptarlo, como que desaparece"*. Era literal:
     * mover el slider cambiaba el documento, el documento avisaba, la barra se
     * reconstruía y lo PRIMERO que hacía era cerrar el panel. El control se
     * suicidaba en cuanto lo tocabas.
     *
     * El fallo era invisible desde fuera —el panel se cerraba y se podía volver
     * a abrir, así que "funcionaba"—, y por eso se prueba preguntando por el
     * estado ANTES y DESPUÉS del cambio.
     */
    /**
     * LA HOJA DE MUESTRA de la piel didáctica. `sfmap --piel <salida.png>`.
     *
     * Se pintan las cuatro primitivas nuevas fuera de pantalla, en los dos
     * temas, ANTES de rediseñar ningún lienzo real. Mirar una forma nueva
     * dentro de un tablero de cien elementos es no verla: si el termómetro sale
     * torcido, se confunde con "el tablero está cargado".
     */
    static func pielFueraDePantalla(_ salida: String, tema: Tema) {
        Fuentes.registrar()
        let marco = NSRect(x: 0, y: 0, width: 1500, height: 760)
        let win = NSWindow(contentRect: marco, styleMask: [.borderless],
                           backing: .buffered, defer: false)
        let l = Lienzo(frame: marco)
        l.tema = tema
        win.contentView = l

        func el(_ id: String, _ rol: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                _ tinte: String, _ extra: [String: Json] = [:]) -> Elemento {
            var o: [String: Json] = [
                "id": .texto(id), "type": .texto("shape"), "shape": .texto("rect"),
                "role": .texto(rol), "tint": .texto(tinte),
                "x": .numero(x), "y": .numero(y), "width": .numero(w), "height": .numero(h),
                "rotation": .numero(0), "zIndex": .numero(1), "opacity": .numero(1),
                "locked": .bool(false), "version": .numero(1),
                "createdAt": .numero(0), "updatedAt": .numero(0),
            ]
            for (k, v) in extra { o[k] = v }
            return Elemento(.objeto(o))
        }

        l.doc.cargar([
            el("c1", "circulo", 40, 40, 230, 130, "morado", ["rotulo": .texto("El canal único")]),
            el("c2", "circulo", 40, 200, 230, 130, "ambar", ["rotulo": .texto("La venta")]),
            el("m1", "momentum", 320, 40, 700, 250, "morado", ["momentum": .objeto([
                "items": .lista([.texto("1 video"), .texto("3/sem"), .texto("cadencia"),
                                 .texto("audiencia"), .texto("demanda")]),
                "pie": .texto("La cadencia compone: el mismo esfuerzo, cada vez más superficie."),
            ])]),
            el("t1", "termometro", 320, 330, 130, 330, "ambar",
               ["termometro": .objeto(["pct": .numero(20), "rotulo": .texto("Día 1")])]),
            el("t2", "termometro", 470, 330, 130, 330, "ambar",
               ["termometro": .objeto(["pct": .numero(60), "rotulo": .texto("Día 5")])]),
            el("t3", "termometro", 620, 330, 130, 330, "ambar",
               ["termometro": .objeto(["pct": .numero(90), "rotulo": .texto("Día 7")])]),
            el("t4", "termometro", 770, 330, 130, 330, "neutro",
               ["termometro": .objeto(["rotulo": .texto("sin medir")])]),
            el("p1", "parrilla", 1060, 40, 400, 250, "morado", ["parrilla": .objeto([
                "celdas": .lista(["YouTube", "Landing", "About", "Correo", "Anuncios", "Checkout",
                                  "Onboarding", "Feed", "Clases"].map { .texto($0) }),
                "columnas": .numero(3), "tam": .numero(15),
            ])]),
            el("p2", "parrilla", 960, 330, 500, 330, "ambar", ["parrilla": .objeto([
                "celdas": .lista(["Diagnóstico", "VSL", "Llamada", "Oferta",
                                  "90 días", "Installer", "Sales Kit", "Testimonio"].map { .texto($0) }),
                "columnas": .numero(2), "tam": .numero(17),
            ])]),
        ])
        l.camara = Camara(x: 750, y: 350, zoom: 1)
        l.layoutSubtreeIfNeeded()
        l.display()
        if let rep = l.bitmapImageRepForCachingDisplay(in: l.bounds) {
            l.cacheDisplay(in: l.bounds, to: rep)
            if let d = rep.representation(using: .png, properties: [:]) {
                try? d.write(to: URL(fileURLWithPath: salida))
                traza("PIEL → \(salida) · tema \(tema.nombre)")
            }
        }
    }

    static func barraPanelFueraDePantalla() {
        Fuentes.registrar()
        let marco = NSRect(x: 0, y: 0, width: 1400, height: 900)
        let win = NSWindow(contentRect: marco, styleMask: [.borderless],
                           backing: .buffered, defer: false)
        let raiz = NSView(frame: marco)
        let l = Lienzo(frame: marco)
        raiz.addSubview(l)
        let barra = BarraContextual(frame: .zero)
        barra.tema = l.tema
        raiz.addSubview(barra)
        win.contentView = raiz
        raiz.layoutSubtreeIfNeeded()
        pruebaBarraPanel(l, barra)
    }

    private static func pruebaBarraPanel(_ l: Lienzo, _ barra: BarraContextual) {
        pasos = 0; fallos = 0
        func nodo(_ id: String, _ x: Double) -> Elemento {
            Elemento(.objeto([
                "id": .texto(id), "type": .texto("shape"), "shape": .texto("diamond"),
                "role": .texto("card"),
                "x": .numero(x), "y": .numero(0), "width": .numero(300), "height": .numero(160),
                "rotation": .numero(0), "zIndex": .numero(1), "opacity": .numero(1),
                "locked": .bool(false), "version": .numero(1),
                "createdAt": .numero(0), "updatedAt": .numero(0),
            ]))
        }
        l.doc.cargar([nodo("n:rombo", 0), nodo("n:otro", 500)])
        l.camara = Camara(x: 400, y: 80, zoom: 1)
        l.herramienta = .seleccionar
        l.layoutSubtreeIfNeeded()
        // El MISMO refresco que dispara un cambio del documento en la app.
        func refrescar() {
            barra.seleccion = l.doc.seleccionados
            guard let primero = barra.seleccion.first else { return }
            var caja = primero.cajaVisual
            for e in barra.seleccion.dropFirst() { caja = caja.union(e.cajaVisual) }
            barra.reconstruir(caja: caja, camara: l.camara, viewport: l.bounds.size)
        }
        l.doc.seleccion = ["n:rombo"]
        refrescar()

        barra.abrirPanelDePrueba("trazo")
        exigir("el panel de trazo abre", barra.hayPanelAbierto)

        // Mover el GROSOR: el gesto exacto que lo cerraba.
        for g in [3.0, 4.0, 5.0, 6.0] {
            barra.alTrazo?(nil, g, nil)
            refrescar()
        }
        exigir("y SIGUE abierto tras mover el grosor cuatro veces", barra.hayPanelAbierto)
        exigir("y sigue siendo el mismo panel", barra.panelAbierto == "contorno")

        // Cambiar de elemento SÍ lo cierra: el panel enseña los valores del que
        // estaba seleccionado, y dejarlo abierto sobre otro sería mentir.
        l.doc.seleccion = ["n:otro"]
        refrescar()
        exigir("cambiar de selección SÍ cierra el panel", !barra.hayPanelAbierto)

        /*
         * ⭐ LOS CUADROS DE LA BARRA ENSEÑAN EL COLOR DEL ELEMENTO.
         *
         * Daniel: *"todos estos componentes muestran el color del componente…
         * son dinámicos en base al color del componente"*. No lo eran: el
         * bisel pintaba un degradado de titanio con `.sourceIn` sobre CUALQUIER
         * icono, así que las tres muestras salían como el mismo cuadrado gris.
         *
         * Se comprueba MIDIENDO píxeles, que es lo único que no se puede
         * engañar: se retrata la barra con el contorno por defecto y con uno
         * dorado explícito, y las dos fotos tienen que salir DISTINTAS.
         */
        func fotoBarra() -> NSBitmapImageRep? {
            guard barra.frame.width > 10,
                  let rep = barra.bitmapImageRepForCachingDisplay(in: barra.bounds) else { return nil }
            barra.cacheDisplay(in: barra.bounds, to: rep)
            return rep
        }
        l.doc.seleccion = ["n:rombo"]
        refrescar()
        let sinColor = fotoBarra()?.representation(using: .png, properties: [:])

        var oro = l.doc.elementos.first { $0.id == "n:rombo" }!
        oro.ponerColor(["stroke": "#d99a1f"])
        l.doc.cargar(l.doc.elementos.map { $0.id == "n:rombo" ? oro : $0 })
        l.doc.seleccion = ["n:rombo"]
        refrescar()
        let conColor = fotoBarra()?.representation(using: .png, properties: [:])
        exigir("el cuadro del contorno CAMBIA con el color del elemento",
               sinColor != nil && conColor != nil && sinColor != conColor)
        if let d = conColor { try? d.write(to: URL(fileURLWithPath: "/tmp/barra-oro.png")) }

        // Y una FOTO de la barra, para poder MIRAR los cuadros de color: el
        // estado se puede probar, pero "¿el cuadro enseña el color del
        // elemento?" hay que verlo.
        l.doc.seleccion = ["n:rombo"]
        refrescar()
        if barra.frame.width > 10, let rep = barra.bitmapImageRepForCachingDisplay(in: barra.bounds) {
            barra.cacheDisplay(in: barra.bounds, to: rep)
            if let d = rep.representation(using: .png, properties: [:]) {
                try? d.write(to: URL(fileURLWithPath: "/tmp/barra.png"))
                traza("BARRA_PANEL foto → /tmp/barra.png (\(Int(barra.frame.width))x\(Int(barra.frame.height)))")
            }
        }

        traza("BARRA_PANEL \(pasos - fallos)/\(pasos) pasos" + (fallos == 0 ? " · TODO VERDE" : " · \(fallos) FALLOS"))
    }

    /// Corre la escena FUERA DE PANTALLA. `sfmap --centro-de-mando`.
    ///
    /// ⚠️ Y no es un detalle de comodidad: la regla dice que ninguna prueba de
    /// Levy roba el foco ni abre ventanas mientras Daniel trabaja
    /// (`nada-emerge-en-deep-work`, 24 ago). Una escena que se verifica
    /// abriéndole la app en la cara durante su bloque de marketing es una
    /// verificación que cuesta más de lo que informa.
    static func centroDeMandoFueraDePantalla() {
        Fuentes.registrar()
        let marco = NSRect(x: 0, y: 0, width: 1800, height: 1000)
        let win = NSWindow(contentRect: marco, styleMask: [.borderless],
                           backing: .buffered, defer: false)
        let l = Lienzo(frame: marco)
        win.contentView = l
        l.layoutSubtreeIfNeeded()
        pruebaCentroDeMando(l)
    }

    static func pruebaCentroDeMando(_ l: Lienzo) {
        pasos = 0; fallos = 0

        func widget(_ tipo: String, _ x: Double, _ w: Double, _ liga: String? = nil) -> Elemento {
            var o: [String: Json] = [
                "id": .texto("w:\(tipo)"), "type": .texto("shape"), "shape": .texto("rect"),
                "role": .texto("widget"),
                "x": .numero(x), "y": .numero(0), "width": .numero(w), "height": .numero(1124),
                "rotation": .numero(0), "zIndex": .numero(1), "opacity": .numero(1),
                "locked": .bool(false), "version": .numero(1),
                "createdAt": .numero(0), "updatedAt": .numero(0),
                "widget": .objeto(["tipo": .texto(tipo)]),
            ]
            if let liga { o["link"] = .texto(liga) }
            return Elemento(.objeto(o))
        }
        // Con su CABINA, igual que en el lienzo real.
        // Con su CABINA y su VISTA, igual que en el lienzo real.
        let widgets = [widget("calendario", 0, 2280, "app:sfcal?vista=week"),
                       widget("monk", 2350, 1180, "app:sfcal?vista=monkMode"),
                       widget("tareas", 3600, 880, "app:sfcal?vista=tasks"),
                       widget("trofeo", 4560, 790)]
        l.doc.cargar(widgets)
        l.camara = Camara(x: 2670, y: 562, zoom: 0.34)
        l.herramienta = .seleccionar
        l.layoutSubtreeIfNeeded()

        // ── 1. EL CONMUTADOR, PULSADO DE VERDAD ─────────────────────────────
        let previa = VistaCalendario.elegida
        defer { VistaCalendario.elegida = previa }   // la escena no cambia sus preferencias

        func pulsar(_ v: VistaCalendario) -> Bool {
            guard let e = l.doc.elementos.first(where: { $0.id == "w:calendario" }),
                  let caja = Pintor.chipsDeVista(e).first(where: { $0.0 == v })?.1 else { return false }
            let c = CGPoint(x: caja.midX, y: caja.midY)
            let p = NSPoint(x: (c.x - l.camara.x) * l.camara.zoom + l.bounds.width / 2,
                            y: (c.y - l.camara.y) * l.camara.zoom + l.bounds.height / 2)
            guard let ev = evento(.leftMouseDown, l, p) else { return false }
            l.mouseDown(with: ev)
            if let u = evento(.leftMouseUp, l, p) { l.mouseUp(with: u) }
            return true
        }

        // El recorrido que Daniel haría: la semana por defecto → el mes → un día.
        VistaCalendario.elegida = .semana
        _ = pulsar(.mes)
        exigir("pulsar MES conmuta la vista", VistaCalendario.elegida == .mes)
        _ = pulsar(.dia)
        exigir("pulsar 1D conmuta la vista", VistaCalendario.elegida == .dia)
        _ = pulsar(.semana)
        exigir("y se vuelve a 7D", VistaCalendario.elegida == .semana)

        // El conmutador NO selecciona: si además seleccionara, cada cambio de
        // vista dejaría la barra contextual abierta encima del panel.
        exigir("conmutar no selecciona el widget", l.doc.seleccion.isEmpty)

        // Y el CUERPO del calendario sí selecciona: el widget sigue siendo un
        // elemento del lienzo, no una zona muerta.
        if let e = l.doc.elementos.first(where: { $0.id == "w:calendario" }) {
            let c = CGPoint(x: e.caja.midX, y: e.caja.midY)
            let p = NSPoint(x: (c.x - l.camara.x) * l.camara.zoom + l.bounds.width / 2,
                            y: (c.y - l.camara.y) * l.camara.zoom + l.bounds.height / 2)
            if let ev = evento(.leftMouseDown, l, p) { l.mouseDown(with: ev) }
            if let u = evento(.leftMouseUp, l, p) { l.mouseUp(with: u) }
            exigir("el cuerpo del widget sigue seleccionando",
                   l.doc.seleccion.contains("w:calendario"))
        }
        l.doc.seleccion = []

        // ── 1b. DOBLE CLIC = ABRE LA CABINA ─────────────────────────────────
        //
        // Daniel: *"asegúrate que al darle doble clic me mande a la app sfcal
        // correspondiente si clickee en tareas, monk mode o el propio
        // calendario"*. Se despacha la LIGA, no se abre nada: una escena que
        // le lanza sfcal a la cara es justo lo que la regla del deep work
        // prohíbe.
        var abiertas: [String] = []
        let antes = l.alAbrirEnlace
        l.alAbrirEnlace = { abiertas.append($0) }
        defer { l.alAbrirEnlace = antes }

        func dobleClic(_ id: String) {
            guard let e = l.doc.elementos.first(where: { $0.id == id }) else { return }
            let c = CGPoint(x: e.caja.midX, y: e.caja.midY)
            let p = NSPoint(x: (c.x - l.camara.x) * l.camara.zoom + l.bounds.width / 2,
                            y: (c.y - l.camara.y) * l.camara.zoom + l.bounds.height / 2)
            for n in 1...2 {
                if let d = evento(.leftMouseDown, l, p, [], clics: n) { l.mouseDown(with: d) }
                if let u = evento(.leftMouseUp, l, p, [], clics: n) { l.mouseUp(with: u) }
            }
        }

        // ⚠️ Cada widget lleva a SU VISTA, no solo a la app. Daniel: *"si le doy
        // doble clic a la vista de Monk Mode, que me mande para allá"*.
        dobleClic("w:calendario")
        exigir("el CALENDARIO lleva a la vista de semana", abiertas.last == "app:sfcal?vista=week")
        dobleClic("w:monk")
        exigir("MONK MODE lleva a SU vista", abiertas.last == "app:sfcal?vista=monkMode")
        // TAREAS lleva a SFCAL, no a la app de Todoist: Todoist es la FUENTE del
        // dato, pero la cabina donde Daniel mira sus tareas es su propia app.
        dobleClic("w:tareas")
        exigir("TAREAS lleva a la vista de tareas de sfcal (no a la app ajena)",
               abiertas.last == "app:sfcal?vista=tasks")

        // Y un clic SIMPLE no abre nada: es el gesto de seleccionar. Si además
        // lanzara una app, tocar el widget para moverlo traería sfcal al frente
        // varias veces al día.
        let cuantas = abiertas.count
        if let e = l.doc.elementos.first(where: { $0.id == "w:monk" }) {
            let c = CGPoint(x: e.caja.midX, y: e.caja.midY)
            let p = NSPoint(x: (c.x - l.camara.x) * l.camara.zoom + l.bounds.width / 2,
                            y: (c.y - l.camara.y) * l.camara.zoom + l.bounds.height / 2)
            if let d = evento(.leftMouseDown, l, p) { l.mouseDown(with: d) }
            if let u = evento(.leftMouseUp, l, p) { l.mouseUp(with: u) }
        }
        exigir("un clic SIMPLE no abre ninguna app", abiertas.count == cuantas)

        // Y la app que abre tiene que EXISTIR en esta máquina.
        exigir("sfcal está donde el esquema la busca", Enlace.rutaApp("sfcal") != nil)
        exigir("Todoist está donde el esquema la busca", Enlace.rutaApp("todoist") != nil)

        // ── 1c. LA CASILLA DE UNA TAREA ─────────────────────────────────────
        //
        // Se comprueba el CABLE, no la red: la escena captura el id que el
        // lienzo despacha y NO cierra nada. Cerrar una tarea real de Daniel
        // para probar que el botón funciona sería pagar la prueba con su
        // trabajo.
        var cerradas: [String] = []
        let antesCerrar = l.alCerrarTarea
        l.alCerrarTarea = { cerradas.append($0) }
        defer { l.alCerrarTarea = antesCerrar; Pintor.cerradas = []; Pintor.casillasTarea = [] }

        Pintor.casillasTarea = [("tarea-A", CGRect(x: 3620, y: 120, width: 19, height: 19)),
                                ("tarea-B", CGRect(x: 3620, y: 182, width: 19, height: 19))]
        func tocar(_ p: CGPoint) {
            let v = NSPoint(x: (p.x - l.camara.x) * l.camara.zoom + l.bounds.width / 2,
                            y: (p.y - l.camara.y) * l.camara.zoom + l.bounds.height / 2)
            if let d = evento(.leftMouseDown, l, v) { l.mouseDown(with: d) }
            if let u = evento(.leftMouseUp, l, v) { l.mouseUp(with: u) }
        }
        tocar(CGPoint(x: 3629, y: 129))
        exigir("pulsar la casilla despacha SU tarea", cerradas.last == "tarea-A")
        tocar(CGPoint(x: 3629, y: 191))
        exigir("y la de al lado despacha la suya", cerradas.last == "tarea-B")

        // Pulsar el TÍTULO no cierra: desde aquí no hay deshacer, así que el
        // blanco es la casilla y solo la casilla.
        let antesN = cerradas.count
        tocar(CGPoint(x: 3800, y: 129))
        exigir("pulsar el título de la tarea NO la cierra", cerradas.count == antesN)

        // Y una ya cerrada no se re-despacha.
        tocar(CGPoint(x: 3629, y: 129))
        exigir("una tarea ya palomeada no se manda dos veces", cerradas.count == antesN)
        Pintor.cerradas = []; Pintor.casillasTarea = []

        // ── 2. EL PRECIO DEL FOTOGRAMA ──────────────────────────────────────
        //
        // Se mide con `display()`, repintado SÍNCRONO, igual que la sonda de
        // tinta: así el reloj mide el dibujo y no cuándo decidió AppKit
        // dibujar. Y se compara contra el MISMO documento con los widgets
        // fuera, que es la única forma de saber qué cuestan ELLOS.
        func cronometrar(_ n: Int) -> [Double] {
            var ms: [Double] = []
            for i in 0..<n {
                l.camara.x += (i % 2 == 0 ? 12 : -12)    // como un arrastre
                let t = DispatchTime.now().uptimeNanoseconds
                l.display()
                ms.append(Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6)
            }
            return ms
        }
        func resumen(_ v: [Double]) -> (p50: Double, p95: Double) {
            let s = v.sorted()
            func q(_ f: Double) -> Double { s[min(s.count - 1, Int(f * Double(s.count)))] }
            return (q(0.5), q(0.95))
        }
        _ = cronometrar(10)                              // calentar cachés de texto
        let conW = resumen(cronometrar(60))
        // Mismo documento, widgets convertidos en tarjetas vacías: la línea base.
        l.doc.cargar(widgets.map { w in
            var j = w.crudo
            if case .objeto(var o) = j { o["role"] = .texto("card"); j = .objeto(o) }
            return Elemento(j)
        })
        l.layoutSubtreeIfNeeded()
        _ = cronometrar(10)
        let sinW = resumen(cronometrar(60))

        traza(String(format: "CENTRO_MANDO fotograma CON widgets · p50=%.2f p95=%.2f ms", conW.p50, conW.p95))
        traza(String(format: "CENTRO_MANDO fotograma SIN widgets · p50=%.2f p95=%.2f ms", sinW.p50, sinW.p95))
        traza(String(format: "CENTRO_MANDO precio de los 3 widgets · p50 +%.2f ms · p95 +%.2f ms",
                     conW.p50 - sinW.p50, conW.p95 - sinW.p95))
        // La vara del spec: el panel ya iba a ~22.5 ms de arrastre y esto no
        // puede empeorarlo "sustancialmente". 30 ms = 33 fps, el suelo de lo
        // que la mano no nota como frenazo en un lienzo de este tamaño.
        exigir("el fotograma con widgets se mantiene bajo 30 ms en p95", conW.p95 < 30)

        traza("CENTRO_MANDO \(pasos - fallos)/\(pasos) pasos" + (fallos == 0 ? " · TODO VERDE" : " · \(fallos) FALLOS"))
    }

    /// El MISMO cronómetro, pero sobre el lienzo maestro DE VERDAD (104
    /// elementos + los tres widgets), que es lo que Daniel arrastra. Medir solo
    /// tres widgets en un lienzo vacío diría el precio del widget y no el
    /// precio del PANEL, que es la pregunta.
    static func costeDelPanelReal(_ els: [Elemento]) {
        let marco = NSRect(x: 0, y: 0, width: 1800, height: 1000)
        let win = NSWindow(contentRect: marco, styleMask: [.borderless], backing: .buffered, defer: false)
        let l = Lienzo(frame: marco)
        win.contentView = l
        l.camara = Camara(x: 2830, y: 1300, zoom: 0.34)
        l.layoutSubtreeIfNeeded()

        func medir(_ e: [Elemento]) -> (Double, Double) {
            l.doc.cargar(e); l.layoutSubtreeIfNeeded()
            var ms: [Double] = []
            for i in 0..<70 {
                l.camara.x += (i % 2 == 0 ? 12 : -12)
                let t = DispatchTime.now().uptimeNanoseconds
                l.display()
                if i >= 10 { ms.append(Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6) }
            }
            let s = ms.sorted()
            return (s[s.count / 2], s[min(s.count - 1, Int(0.95 * Double(s.count)))])
        }
        let con = medir(els)
        // La misma página con los widgets FUERA: la línea base de la iteración 2.
        let sin = medir(els.filter { $0.rol != "widget" })
        traza(String(format: "PANEL_REAL con widgets · p50=%.2f p95=%.2f ms · %d elementos", con.0, con.1, els.count))
        traza(String(format: "PANEL_REAL sin widgets · p50=%.2f p95=%.2f ms (línea base iter-2)", sin.0, sin.1))
        traza(String(format: "PANEL_REAL precio del DÍA · p50 +%.2f ms · p95 +%.2f ms", con.0 - sin.0, con.1 - sin.1))
    }

}
