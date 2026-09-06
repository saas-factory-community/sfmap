import AppKit

/**
 * EL CRONÓMETRO DEL ARRASTRE. `sfmap --medir <page_id>`.
 *
 * Daniel: *"al arrastrar este componente rápidamente como que se traba, va de
 * saltos en saltos"*. Un tirón se puede achacar a cuatro sitios distintos —el
 * imantado, el ruteo, el pintado, la cadencia de eventos— y adivinar cuál sale
 * caro: se optimiza lo que no era y el tirón sigue ahí.
 *
 * Esto carga SU página de verdad (no una sintética de 5 cajas) y cronometra
 * cada pieza por separado, con la ventana fuera de pantalla. El número que
 * importa es cuánto cuesta UN fotograma de arrastre: por encima de 8 ms el
 * ratón entrega más eventos de los que se pueden atender y la cola se acumula.
 */
enum Cronometro {
    static func ruta() -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--medir") else { return nil }
        return i + 1 < a.count ? a[i + 1] : nil
    }

    private static func ms(_ n: Int = 1, _ f: () -> Void) -> Double {
        let t0 = ProcessInfo.processInfo.systemUptime
        for _ in 0..<n { f() }
        return (ProcessInfo.processInfo.systemUptime - t0) * 1000 / Double(n)
    }

    static func correr(_ pageId: String) async {
        Fuentes.registrar()
        Nube.cargarConfig()
        let p: Nube.Pagina
        do { p = try await Nube.abrir(pageId) }
        catch { print("MEDIR_ERROR \(error)"); return }
        await MainActor.run {
            let els = p.elementos
            print("MEDIR página '\(p.nombre)' · \(els.count) elementos "
                  + "(\(els.filter { $0.tipo == "connector" }.count) conectores)")

            let marco = NSRect(x: 0, y: 0, width: 1600, height: 1000)
            let win = NSWindow(contentRect: marco, styleMask: [.borderless], backing: .buffered, defer: false)
            let l = Lienzo(frame: marco)
            win.contentView = l
            l.doc.cargar(els)
            l.encuadrar()

            // 1 · PINTAR. Lo que cuesta un fotograma entero del lienzo.
            guard let rep = l.bitmapImageRepForCachingDisplay(in: l.bounds) else { return }
            _ = ms(3) { l.cacheDisplay(in: l.bounds, to: rep) }   // calentar cachés
            let pintar = ms(10) { l.cacheDisplay(in: l.bounds, to: rep) }

            /*
             * 1b · EL DESGLOSE — ¿dónde se van los milisegundos?
             *
             * Sin esto, «el fotograma cuesta 21 ms» no dice qué arreglar, y se
             * optimiza a ojo (lo que ya costó una reversión: agrupar los puntos
             * de la retícula en un path MIDIÓ PEOR). Se resta por capas usando
             * el MISMO lienzo: vacío y liso = el suelo de AppKit; vacío con
             * puntos = lo que cuesta la retícula; con todo = lo que cuestan los
             * elementos.
             */
            let vacio = Lienzo(frame: marco)
            NSWindow(contentRect: marco, styleMask: [.borderless],
                     backing: .buffered, defer: false).contentView = vacio
            vacio.camara = l.camara
            vacio.fondo = .liso
            guard let rep2 = vacio.bitmapImageRepForCachingDisplay(in: vacio.bounds) else { return }
            _ = ms(3) { vacio.cacheDisplay(in: vacio.bounds, to: rep2) }
            let suelo = ms(10) { vacio.cacheDisplay(in: vacio.bounds, to: rep2) }
            vacio.fondo = .puntos
            let conReticula = ms(10) { vacio.cacheDisplay(in: vacio.bounds, to: rep2) }
            print(String(format: "MEDIR desglose · suelo=%.2fms retícula=%.2fms elementos=%.2fms (%d elementos)",
                         suelo, conReticula - suelo, pintar - conReticula, els.count))

            // ¿Cuánto de «elementos» son las SOMBRAS? Cada una fuerza un buffer
            // aparte en CoreGraphics, así que es el sospechoso natural cuando el
            // coste no escala con el número de elementos.
            Pintor.sinSombras = true
            let sinSombra = ms(10) { l.cacheDisplay(in: l.bounds, to: rep) }
            Pintor.sinSombras = false
            Pintor.sinTexto = true
            let sinTxt = ms(10) { l.cacheDisplay(in: l.bounds, to: rep) }
            Pintor.sinTexto = false
            print(String(format: "MEDIR texto = %.2fms de los elementos", pintar - sinTxt))
            print(String(format: "MEDIR sombras = %.2fms de los elementos", pintar - sinSombra))

            // Y el MODO CLASE, que es como se graba: apaga la retícula.
            l.enact.entrar(tope: Enactar.tope(els))
            l.enact.revelarTodo()
            let enClase = ms(10) { l.cacheDisplay(in: l.bounds, to: rep) }
            l.enact.salir()
            print(String(format: "MEDIR modo clase (F5) = %.2fms  (%.0f%% del normal)",
                         enClase, enClase / pintar * 100))

            /*
             * ⚠️ SE MIDE MOVIENDO LO QUE MÁS DUELE, no lo primero que hay.
             *
             * La primera versión cogía `els.first { tipo != "connector" }` — y
             * resultó ser una caja SIN conectores, así que `rerutear` no ruteaba
             * nada y devolvía 0.74 ms. Un número precioso que medía el coste de
             * recorrer un array. El caso real es la caja con más flechas
             * colgando, que es la que la mano arrastra y la que dispara trabajo.
             */
            var grado: [String: Int] = [:]
            for c in els where c.tipo == "connector" {
                grado[c.desdeId ?? "", default: 0] += 1
                grado[c.hastaId ?? "", default: 0] += 1
            }
            let movible = els.filter { $0.tipo != "connector" }
                .max { (grado[$0.id] ?? 0) < (grado[$1.id] ?? 0) }
            let conectados = grado[movible?.id ?? ""] ?? 0
            print("MEDIR se arrastra '\(movible?.id ?? "?")' con \(conectados) flechas colgando")
            let caja = movible?.caja ?? .zero
            let imantar = ms(50) {
                _ = Geo.imantar(caja.offsetBy(dx: 7, dy: 3), els, zoom: 1,
                                ignorar: Set([movible?.id ?? ""]))
            }

            // 3 · RERUTEAR solo lo que toca el movido.
            let movidos = Set([movible?.id ?? ""])
            let rerutear = ms(50) { _ = Conectores.rerutear(els, movidos: movidos, rapido: true) }
            let ruteoBueno = ms(10) { _ = Conectores.rerutear(els, movidos: movidos) }

            // 4 · RERUTEAR TODO (lo que corre al soltar).
            let todo = ms(5) { _ = Conectores.reruteaTodo(els) }

            print(String(format: "MEDIR pintar=%.2fms imantar=%.2fms rerutear(rapido)=%.2fms rerutear(bueno)=%.2fms reruteaTodo=%.2fms",
                         pintar, imantar, rerutear, ruteoBueno, todo))
            print(String(format: "MEDIR fotograma de arrastre ≈ %.2fms  (presupuesto 8.3ms a 120Hz)",
                         pintar + imantar + rerutear))
        }
    }
}
