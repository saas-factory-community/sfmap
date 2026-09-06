import AppKit

/**
 * HOJA DE CONTACTO DEL CROMO. `sfmap --cromo <salida.png>`.
 *
 * Hermana de `--iconos`, y nació del mismo hueco: para juzgar una superficie hay
 * que verla, y **capturar la ventana no siempre se puede**. El 20 ago 2026 la
 * pantalla del Mac estaba bloqueada y `screencapture -l` devolvía *"could not
 * create image from window"* — con la app corriendo perfectamente. Un sensor
 * que depende de que alguien tenga el monitor encendido no es un sensor.
 *
 * Ésta monta las piezas del cromo en una ventana que nunca se enseña y las
 * dibuja en un mapa de bits. Corre con la sesión cerrada, corre en un cron, y de
 * paso pone los DOS temas uno al lado del otro sobre su propio lienzo — que es
 * la única forma honesta de ver si el bisel funciona contra el tablero, que es
 * el juicio que importa y que una captura de un solo tema no puede dar.
 *
 * ⚠️ Las vistas van dentro de un `NSWindow` de verdad aunque no se muestre.
 * `cacheDisplay` sobre una vista huérfana pinta los `NSButton` sin celda y salen
 * huecos: el juicio se haría sobre un dibujo que ningún usuario ve.
 */
enum HojaCromo {
    static func ruta() -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--cromo") else { return nil }
        return i + 1 < a.count ? a[i + 1] : "/tmp/cromo.png"
    }

    /**
     * EL TABLERO ES EL LIENZO DE VERDAD, no una imitación.
     *
     * La primera versión pintaba un rectángulo con puntos, y eso habría dejado
     * SIN VERIFICAR justo lo que más fácil se rompe: el lienzo está VOLTEADO y
     * el resto del cromo no, así que el canto hundido se pinta ahí por un camino
     * distinto. Una hoja de contacto que dibuja una copia del sujeto no prueba
     * nada del sujeto.
     */
    private static func tableroReal(_ tema: Tema, _ marco: NSRect) -> Lienzo {
        let l = Lienzo(frame: marco)
        l.tema = tema
        l.doc.cargar(muestras())
        // La cámara se corre a la derecha para que el contenido caiga en el
        // hueco libre y no debajo del panel o del rail: la hoja se mira para
        // juzgar el cromo CONTRA el contenido, no para taparlo con él.
        l.camara = Camara(x: 100, y: 150, zoom: 0.85)
        return l
    }

    /// Un par de cajas y su flecha: lo justo para que el tablero no salga vacío
    /// y se vea el contenido contra el cromo, que es el juicio que importa.
    private static func muestras() -> [Elemento] {
        func caja(_ id: String, _ x: Double, _ y: Double, _ t: String, _ rol: String) -> Elemento {
            Elemento(.objeto([
                "id": .texto(id), "type": .texto("shape"), "shape": .texto("rect"),
                "role": .texto(rol),
                "x": .numero(x), "y": .numero(y), "width": .numero(230), "height": .numero(92),
                "rotation": .numero(0), "zIndex": .numero(1), "opacity": .numero(1),
                "locked": .bool(false), "version": .numero(1),
                "createdAt": .numero(0), "updatedAt": .numero(0),
                "text": .lista([.objeto([
                    "role": .texto("title"),
                    "lines": .lista([.texto(t)]),
                ])]),
            ]))
        }
        let a = caja("a", 120, 40, "SF Engine · diagnosticar", "card")
        let b = caja("b", 120, 220, "El Protocolo", "module")
        let conn = Elemento(.objeto([
            "id": .texto("c1"), "type": .texto("connector"),
            "fromId": .texto("a"), "toId": .texto("b"),
            "edgeClass": .texto("flujo"),
            "x": .numero(0), "y": .numero(0), "width": .numero(0), "height": .numero(0),
            "rotation": .numero(0), "zIndex": .numero(0), "opacity": .numero(1),
            "locked": .bool(false), "version": .numero(1),
            "createdAt": .numero(0), "updatedAt": .numero(0),
        ]))
        return [a, b, conn]
    }

    private static let paginas: [ResumenPagina] = [
        ResumenPagina(id: "a", nombre: "El Camino v3", folderId: "f1", elementos: 358),
        ResumenPagina(id: "b", nombre: "La Máquina en Frío", folderId: "f1", elementos: 45),
        ResumenPagina(id: "c", nombre: "Escalera de valor", folderId: "f1", elementos: 22),
        ResumenPagina(id: "d", nombre: "Scaling laws · los dos relojes", folderId: "f2", elementos: 61),
        ResumenPagina(id: "e", nombre: "Notas sueltas", folderId: nil, elementos: 9),
    ]
    private static let carpetas: [Carpeta] = [
        Carpeta(id: "f1", nombre: "The Machinery"),
        Carpeta(id: "f2", nombre: "Contenido"),
        Carpeta(id: "f3", nombre: "Accelerator"),
    ]

    private static func mitad(_ tema: Tema, ancho: CGFloat, alto: CGFloat) -> NSView {
        /*
         * ⚠️ EL CROMO ES HERMANO DEL LIENZO, NO SU HIJO.
         *
         * La primera versión colgaba el panel y las barras DENTRO del lienzo, y
         * como el lienzo está volteado se maquetó todo del revés: la fila de
         * título abajo, la barra de estado arriba, y el texto de las cajas
         * espejado. En la app real son hermanos dentro de la vista raíz de la
         * ventana; una hoja de contacto con otra jerarquía retrata otra app.
         */
        let raiz = NSView(frame: NSRect(x: 0, y: 0, width: ancho, height: alto))
        raiz.addSubview(tableroReal(tema, raiz.bounds))

        let header = HeaderPulsable()
        header.tema = tema
        header.abierto = true
        header.poner(nombre: "La Máquina en Frío", carpeta: "The Machinery")
        header.frame = NSRect(x: 78, y: alto - HeaderPulsable.ALTO, width: 340, height: HeaderPulsable.ALTO)

        // La banda del cromo: la fila de título es la MISMA placa que el panel.
        let banda = Franja(frame: NSRect(x: 0, y: alto - HeaderPulsable.ALTO,
                                         width: ancho, height: HeaderPulsable.ALTO))
        banda.tema = tema
        raiz.addSubview(banda)

        let panel = Lateral(frame: NSRect(x: 0, y: 0, width: 236, height: alto - HeaderPulsable.ALTO))
        panel.tema = tema
        panel.carpetas = carpetas
        panel.paginas = paginas
        panel.activa = "b"
        panel.abrirTodas()
        raiz.addSubview(panel)
        raiz.addSubview(header)

        let rail = RailHerramientas()
        rail.tema = tema
        rail.activa = .rect
        rail.frame.origin = CGPoint(x: 236 + 16, y: alto - HeaderPulsable.ALTO - rail.frame.height - 40)
        raiz.addSubview(rail)

        let barra = BarraEstado()
        barra.tema = tema
        barra.zoom = 1
        barra.estado = ""
        barra.puedeDeshacer = true
        barra.frame.origin = CGPoint(x: ancho - barra.anchoIdeal - 14, y: 14)
        raiz.addSubview(barra)

        let mapa = Minimapa()
        mapa.tema = tema
        // Con el visor vacío el minimapa se ve como una placa rota; con el
        // mismo contenido del tablero se ve como lo que es.
        mapa.elementos = muestras()
        mapa.camara = Camara(x: 100, y: 150, zoom: 0.85)
        mapa.vista = NSSize(width: ancho - 236, height: alto - HeaderPulsable.ALTO)
        mapa.frame.origin = CGPoint(x: 236 + 16, y: 14)
        raiz.addSubview(mapa)

        return raiz
    }

    /// La banda de la fila de título: la misma placa que el panel, a lo ancho.
    private final class Franja: NSView {
        var tema: Tema = .claro
        override func draw(_ r: NSRect) {
            Estilo.pintarBisel(self, tema, radio: 0, borde: false)
            guard let c = NSGraphicsContext.current?.cgContext else { return }
            c.setFillColor(tema.filoCromo.cgColor)
            c.fill(NSRect(x: 0, y: 0, width: bounds.width, height: 1))
        }
    }

    static func generar(_ salida: String) {
        let ancho: CGFloat = 900, alto: CGFloat = 620
        let total = NSRect(x: 0, y: 0, width: ancho * 2, height: alto)
        let win = NSWindow(contentRect: total, styleMask: [.borderless],
                           backing: .buffered, defer: false)
        let raiz = NSView(frame: total)
        win.contentView = raiz

        for (i, t) in [Tema.claro, Tema.oscuro].enumerated() {
            let v = mitad(t, ancho: ancho, alto: alto)
            v.frame.origin.x = CGFloat(i) * ancho
            raiz.addSubview(v)
        }
        raiz.layoutSubtreeIfNeeded()
        // Dos pasadas: la primera coloca (los paneles se reconstruyen al saber su
        // ancho real), la segunda dibuja lo ya colocado.
        raiz.layoutSubtreeIfNeeded()

        guard let rep = raiz.bitmapImageRepForCachingDisplay(in: raiz.bounds) else { return }
        raiz.cacheDisplay(in: raiz.bounds, to: rep)
        guard let datos = rep.representation(using: .png, properties: [:]) else { return }
        try? datos.write(to: URL(fileURLWithPath: salida))
        print("CROMO_OK \(salida) \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }
}

/**
 * HOJA DEL PANEL DE DOCUMENTO. `sfmap --hoja-doc <ruta.md> <salida.png>`.
 *
 * Misma doctrina que `--cromo`, y por la misma razón: el panel de markdown hay
 * que MIRARLO para juzgarlo, y `screencapture -l` devuelve *"could not create
 * image from window"* con la sesión bloqueada. Esta hoja monta el panel real
 * —el mismo `PanelDoc` que usa la app, cargando el markdown de verdad del
 * repo— dentro de una ventana que nunca se enseña, en los DOS temas.
 *
 * Es el sensor de "¿lo que renderizo se LEE?", que es una pregunta distinta de
 * "¿el parser devolvió bloques?" (eso lo cubren las pruebas). Un parser correcto
 * con una maqueta ilegible es un fallo que ninguna prueba de unidad ve.
 */
enum HojaDoc {
    static func args() -> (String, String)? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--hoja-doc"), i + 1 < a.count else { return nil }
        return (a[i + 1], i + 2 < a.count ? a[i + 2] : "/tmp/doc.png")
    }

    static func generar(_ relativa: String, _ salida: String) {
        Fuentes.registrar()
        let ancho: CGFloat = 520, alto: CGFloat = 900
        let total = NSRect(x: 0, y: 0, width: ancho * 2, height: alto)
        let win = NSWindow(contentRect: total, styleMask: [.borderless],
                           backing: .buffered, defer: false)
        let raiz = NSView(frame: total)
        win.contentView = raiz

        var ok = true
        for (i, t) in [Tema.claro, Tema.oscuro].enumerated() {
            let p = PanelDoc(frame: NSRect(x: CGFloat(i) * ancho, y: 0, width: ancho, height: alto))
            p.tema = t
            raiz.addSubview(p)
            p.layoutSubtreeIfNeeded()
            if !p.mostrar(relativa) { ok = false }
            p.layoutSubtreeIfNeeded()
        }
        raiz.layoutSubtreeIfNeeded()
        raiz.layoutSubtreeIfNeeded()

        guard let rep = raiz.bitmapImageRepForCachingDisplay(in: raiz.bounds) else { return }
        raiz.cacheDisplay(in: raiz.bounds, to: rep)
        guard let datos = rep.representation(using: .png, properties: [:]) else { return }
        try? datos.write(to: URL(fileURLWithPath: salida))
        print("HOJADOC_\(ok ? "OK" : "FALLO") \(salida) \(rep.pixelsWide)x\(rep.pixelsHigh) · \(relativa)")
    }
}
