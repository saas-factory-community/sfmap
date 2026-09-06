import AppKit

/**
 * LA FOTO DE UNA PÁGINA REAL. `sfmap --foto <page_id> <salida.png>`
 *
 * Nació el 24 ago 2026 verificando los logos del mapa de la máquina:
 * `screencapture -l <windowID>` devuelve *"could not create image from window"*
 * sin el permiso de grabación de pantalla — y un sensor que depende de un
 * permiso de UI no es un sensor (la misma razón por la que existe `--cromo`).
 *
 * Carga la página de verdad por la nube, la pinta FUERA de pantalla dos veces
 * (el primer pase dispara las cargas de imagen; las rutas locales llegan
 * síncronas, las remotas en el segundo si ya viajaron) y escribe el PNG.
 */
enum Foto {

    /// Si la página lleva widgets vivos, se ESPERA una lectura antes de pintar.
    /// Un export con los tres widgets diciendo «sin lectura» sería honesto en
    /// pantalla e inservible como prueba de que pintan datos reales.
    static func cargarDiaSiHayWidgets(_ els: [Elemento]) async {
        guard els.contains(where: { $0.rol == "widget" }) else { return }
        await Cronista.compartido.cargarUnaVez()
    }

    static func argumentos() -> (id: String, salida: String)? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--foto"), i + 2 < a.count else { return nil }
        return (a[i + 1], a[i + 2])
    }

    /// `--export <page_id> <salida.png> [--escala N] [--tema claro|oscuro]`
    /// La diferencia con --foto: --foto es un SENSOR (¿se pinta?); --export es
    /// un ASSET (recorte ajustado al contenido, 2x, listo para publicar).
    static func argumentosExport() -> (id: String, salida: String, escala: Double)? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--export"), i + 2 < a.count else { return nil }
        var escala = 2.0
        if let j = a.firstIndex(of: "--escala"), j + 1 < a.count, let v = Double(a[j + 1]) {
            escala = max(0.5, min(4, v))
        }
        return (a[i + 1], a[i + 2], escala)
    }

    /// La caja que abraza TODO el contenido (texto ligado incluido, vía
    /// cajaVisual). Los conectores viven entre cajas, así que la unión de las
    /// figuras ya los contiene.
    static func limites(_ els: [Elemento]) -> CGRect? {
        let visibles = els.filter { $0.tipo != "connector" && ($0.caja.width > 0 || $0.tipo == "text") }
        guard var r = visibles.first?.cajaVisual else { return nil }
        for e in visibles.dropFirst() { r = r.union(e.cajaVisual) }
        return r.insetBy(dx: -60, dy: -60)
    }

    /// `--marco x,y,w,h` recorta a un rectángulo del MUNDO en vez de al
    /// contenido. Existe para verificar una zona concreta —una banda de
    /// widgets, un módulo— sin exportar 6600 px de tablero y buscar a ojo.
    static func marcoPedido() -> CGRect? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--marco"), i + 1 < a.count else { return nil }
        let n = a[i + 1].split(separator: ",").compactMap { Double($0) }
        guard n.count == 4 else { return nil }
        return CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
    }

    static func exportar(_ pageId: String, _ salida: String, _ escala: Double) async {
        Fuentes.registrar()
        Nube.cargarConfig()
        let p: Nube.Pagina
        do { p = try await Nube.abrir(pageId) }
        catch { print("EXPORT_ERROR \(error)"); return }
        await cargarDiaSiHayWidgets(p.elementos)
        await MainActor.run {
            guard let r = marcoPedido() ?? limites(p.elementos) else { print("EXPORT_ERROR página vacía"); return }
            // Tope duro de píxeles: un lienzo de 6 columnas a 4x no debe
            // producir un PNG de 500 MB por accidente.
            let esc = min(escala, 12000 / max(r.width, r.height))
            let marco = NSRect(x: 0, y: 0, width: r.width * esc, height: r.height * esc)
            let win = NSWindow(contentRect: marco, styleMask: [.borderless],
                               backing: .buffered, defer: false)
            let l = Lienzo(frame: marco)
            win.contentView = l
            if let i = CommandLine.arguments.firstIndex(of: "--tema"),
               i + 1 < CommandLine.arguments.count, CommandLine.arguments[i + 1] == "oscuro" {
                l.tema = .oscuro
            }
            l.doc.cargar(p.elementos)
            l.camara = Camara(x: r.midX, y: r.midY, zoom: esc)
            guard let rep = l.bitmapImageRepForCachingDisplay(in: l.bounds) else {
                print("EXPORT_ERROR sin bitmap"); return
            }
            l.cacheDisplay(in: l.bounds, to: rep)   // dispara las cargas de imagen
            l.cacheDisplay(in: l.bounds, to: rep)   // pinta con lo que ya llegó
            guard let png = rep.representation(using: .png, properties: [:]) else {
                print("EXPORT_ERROR sin png"); return
            }
            do {
                try png.write(to: URL(fileURLWithPath: salida))
                print("EXPORT_OK \(salida) · \(Int(marco.width))x\(Int(marco.height)) px · \(p.elementos.count) elementos")
            } catch { print("EXPORT_ERROR \(error)") }
        }
    }

    static func correr(_ pageId: String, _ salida: String) async {
        Fuentes.registrar()
        Nube.cargarConfig()
        let p: Nube.Pagina
        do { p = try await Nube.abrir(pageId) }
        catch { print("FOTO_ERROR \(error)"); return }
        await cargarDiaSiHayWidgets(p.elementos)
        await MainActor.run {
            let marco = NSRect(x: 0, y: 0, width: 1600, height: 1000)
            let win = NSWindow(contentRect: marco, styleMask: [.borderless],
                               backing: .buffered, defer: false)
            let l = Lienzo(frame: marco)
            win.contentView = l
            l.doc.cargar(p.elementos)
            l.encuadrar()
            guard let rep = l.bitmapImageRepForCachingDisplay(in: l.bounds) else {
                print("FOTO_ERROR sin bitmap"); return
            }
            l.cacheDisplay(in: l.bounds, to: rep)   // dispara las cargas de imagen
            l.cacheDisplay(in: l.bounds, to: rep)   // pinta con lo que ya llegó
            guard let png = rep.representation(using: .png, properties: [:]) else {
                print("FOTO_ERROR sin png"); return
            }
            do {
                try png.write(to: URL(fileURLWithPath: salida))
                let imgs = p.elementos.filter { $0.tipo == "image" }
                print("FOTO_OK \(salida) · \(p.elementos.count) elementos (\(imgs.count) imágenes)")
                // El acuse por imagen: qué src ve el pintor y si cargó de verdad.
                for e in imgs {
                    let src = e.crudo["src"]?.s ?? "(sin src)"
                    let cargo = Imagenes.de(src) {} != nil
                    print("FOTO_IMG \(cargo ? "OK " : "FALLO") \(e.id) \(src)")
                }
            } catch { print("FOTO_ERROR \(error)") }
        }
    }
}
