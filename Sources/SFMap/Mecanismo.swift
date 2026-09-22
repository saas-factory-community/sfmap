import AppKit
import CoreGraphics

/**
 * EL MECANISMO — la pieza que se MUEVE con la mano y responde. Enactar 2D.
 *
 * ════════════════════════════════════════════════════════════════════════════
 * QUÉ PIDIÓ DANIEL, EXACTAMENTE (26 ago 2026)
 * ════════════════════════════════════════════════════════════════════════════
 *
 * *"Cuando me refiero a enactar un componente me refiero a poder tener por
 * ejemplo un DIAL, una barrita que yo arrastro, y algo en el componente va
 * cambiando. Por ejemplo… unos ENGRANES girando y cómo se relacionaba con back
 * propagation… podía modificar un dial que cambiaba la velocidad de un engrane
 * específico, que cambiaba la velocidad de todo el sistema."*
 *
 * Eso NO es una animación (una animación se mira), ni una lámina (una lámina
 * dice qué ES algo). Un mecanismo enseña **la RELACIÓN entre las partes**: el
 * alumno mueve una cosa y ve moverse otra, y la causalidad entra por la mano
 * antes que por la frase. Es el único de los tres medios que enseña CAUSALIDAD.
 *
 * ════════════════════════════════════════════════════════════════════════════
 * POR QUÉ NATIVO Y NO UN SERVIDOR CON HTML
 * ════════════════════════════════════════════════════════════════════════════
 *
 * Daniel dio permiso para montar un servidor detrás si hacía falta. No hace
 * falta, y el precio de montarlo sería alto: los embeds vivos ya murieron una
 * vez por buggy (`Markdown.swift`, 20 ago), un WebKit por tarjeta es el
 * arranque de un navegador por documento, y un servidor añade un proceso que
 * puede estar caído justo mientras se graba — el fallo más caro posible.
 *
 * Aquí no hace falta ninguna de las dos cosas: el pintor ya sabe dibujar
 * vectores y el lienzo ya sabe arrastrar. Un engranaje es geometría, y la
 * geometría es lo que este archivo hace. Sin proceso extra, sin red, sin
 * dependencias, y grabable dentro de sfmap — que es donde se graba el curso.
 *
 * ════════════════════════════════════════════════════════════════════════════
 * LA REGLA QUE DECIDE SI ALGO SE VUELVE MECANISMO
 * ════════════════════════════════════════════════════════════════════════════
 *
 * **Sólo si hay una relación que el alumno tiene que SENTIR** —transmisión,
 * saturación, compuesto, umbral—. Si la idea se entiende leyéndola, un
 * mecanismo es un juguete: cuesta atención y no paga. Misma vara que las
 * primitivas didácticas: se gana el sitio diciendo algo que una caja no puede
 * decir.
 *
 * ⚠️ EL VALOR NO SE GUARDA. Vive en memoria como el zoom o el paso de la
 * escena. Guardar la posición del dial en `draw` escribiría en la tabla cada
 * vez que Daniel mueve la mano en cámara — y convertiría un instrumento en un
 * archivo muerto (misma regla que el Cronista).
 */
enum Mecanismo {

    /// Los valores vivos de la página, por id de elemento. En memoria.
    final class Estado {
        private var valores: [String: Double] = [:]
        func valor(_ e: Elemento) -> Double {
            valores[e.id] ?? inicial(e)
        }
        func poner(_ id: String, _ v: Double) {
            valores[id] = max(0, min(1, v))
            // En un LAZO el dial es la referencia: mover la mano en cámara
            // mueve el techo, aun con el pulso corriendo.
            lazos[id]?.referencia = valores[id]!
        }
        func limpiar() {
            valores.removeAll(); senalado = nil
            lazos.removeAll(); reloj?.invalidate(); reloj = nil
        }

        // ── LOS LAZOS (Lazo.swift): estado vivo + el reloj que se muere ──
        private var lazos: [String: Lazo.Vivo] = [:]
        private var reloj: Timer?
        private var ultimoTick: TimeInterval = 0
        /// Lo llama el reloj: el lienzo se repinta.
        var alRepintar: (() -> Void)?

        func lazo(_ e: Elemento) -> Lazo.Vivo {
            if let v = lazos[e.id] { return v }
            let v = Lazo.Vivo(referencia: valor(e)); lazos[e.id] = v; return v
        }
        func correr(_ e: Elemento) {
            let v = lazo(e); guard !v.corriendo else { return }
            Lazo.arrancar(v); arrancarReloj()
        }
        func alternarRegreso(_ e: Elemento) {
            let v = lazo(e); guard !v.corriendo else { return }
            v.regreso.toggle(); Lazo.reiniciar(v)
        }
        func reiniciar(_ e: Elemento) {
            let v = lazo(e); guard !v.corriendo else { return }
            Lazo.reiniciar(v)
        }
        /// UN tick del reloj. Devuelve si algún lazo sigue corriendo — cuando
        /// ninguno corre, el reloj se muere (un temporizador latiendo con el
        /// lienzo quieto es un órgano zombie de escritorio).
        @discardableResult
        func tick(dt: Double) -> Bool {
            var vivo = false
            for v in lazos.values where v.corriendo { Lazo.avanzar(v, dt: dt); vivo = vivo || v.corriendo }
            alRepintar?()
            return vivo
        }
        private func arrancarReloj() {
            reloj?.invalidate()
            ultimoTick = ProcessInfo.processInfo.systemUptime
            reloj = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
                guard let s = self else { t.invalidate(); return }
                let ahora = ProcessInfo.processInfo.systemUptime
                let dt = min(0.1, ahora - s.ultimoTick); s.ultimoTick = ahora
                if !s.tick(dt: dt) { t.invalidate(); s.reloj = nil }
            }
            if let r = reloj { RunLoop.main.add(r, forMode: .eventTracking) }
            alRepintar?()
        }

        /// El punto de una GRÁFICA que tiene el ratón encima: (id, índice).
        /// Vive aquí y no en el documento por la misma razón que el dial —
        /// pasar el ratón por encima no puede escribir en `draw`.
        private(set) var senalado: (id: String, i: Int)?
        /// Devuelve true si cambió (para repintar solo cuando hace falta).
        @discardableResult
        func senalar(_ id: String?, _ i: Int?) -> Bool {
            let nuevo: (String, Int)? = (id != nil && i != nil) ? (id!, i!) : nil
            if nuevo?.0 == senalado?.id && nuevo?.1 == senalado?.i { return false }
            senalado = nuevo.map { (id: $0.0, i: $0.1) }
            return true
        }
        func senalado(de e: Elemento) -> Int? {
            senalado?.id == e.id ? senalado?.i : nil
        }
    }

    // ── LECTURA DEL ELEMENTO ────────────────────────────────────────────────

    static func esMecanismo(_ e: Elemento) -> Bool { e.crudo["mecanismo"] != nil }

    static func tipo(_ e: Elemento) -> String {
        e.crudo["mecanismo"]?["tipo"]?.s ?? "engranes"
    }

    /// El valor con el que el generador quiere que ARRANQUE. Ni 0 ni 1: en los
    /// extremos el mecanismo parece roto antes de que nadie lo toque.
    static func inicial(_ e: Elemento) -> Double {
        max(0, min(1, e.crudo["mecanismo"]?["valor"]?.num ?? 0.35))
    }

    static func rotulo(_ e: Elemento) -> String {
        e.crudo["mecanismo"]?["rotulo"]?.s ?? ""
    }

    /// Las piezas del tren: radio relativo (0..1 del alto útil) y rótulo.
    struct Pieza { var radio: Double; var dientes: Int; var rotulo: String }

    static func piezas(_ e: Elemento) -> [Pieza] {
        guard let lista = e.crudo["mecanismo"]?["piezas"]?.arr, !lista.isEmpty else {
            // Un tren por defecto que ya enseña: grande mueve chico, y el chico
            // da más vueltas. La transmisión se ve sin configurar nada.
            return [Pieza(radio: 1.0, dientes: 18, rotulo: ""),
                    Pieza(radio: 0.62, dientes: 11, rotulo: ""),
                    Pieza(radio: 0.40, dientes: 7, rotulo: "")]
        }
        return lista.map {
            Pieza(radio: max(0.15, min(1, $0["radio"]?.num ?? 0.6)),
                  dientes: max(5, Int($0["dientes"]?.num ?? 12)),
                  rotulo: $0["rotulo"]?.s ?? "")
        }
    }

    // ── LA ZONA DEL DIAL ────────────────────────────────────────────────────

    /// El riel del dial, en coordenadas de mundo. Vive en la banda de abajo del
    /// elemento: separado del dibujo para que la mano no tape el mecanismo
    /// justo mientras lo mueve.
    static func riel(_ e: Elemento) -> CGRect {
        let alto = 22.0
        let margen = min(40.0, e.ancho * 0.08)
        // El rótulo vive A LA IZQUIERDA del riel, como en cualquier panel de
        // control: «velocidad ▬▬●▬▬». Dentro competía con el relleno que marca
        // el valor, encima chocaba con los rótulos de las piezas y debajo no
        // cabe (el elemento se acaba 26 px más allá). Los tres medidos en el
        // retrato antes de decidir esto.
        let hueco = rotulo(e).isEmpty ? 0 : min(160.0, e.ancho * 0.30)
        return CGRect(x: e.x + margen + hueco, y: e.y + e.alto - alto - 26,
                      width: e.ancho - margen * 2 - hueco, height: alto)
    }

    /// Zona sensible al ratón: más generosa que el riel, porque agarrar una
    /// barra de 22 px en cámara y a zoom bajo es una pelea que nadie quiere dar
    /// en directo.
    static func zonaDial(_ e: Elemento) -> CGRect {
        riel(e).insetBy(dx: -20, dy: -26)
    }

    /// De la x del puntero al valor 0..1.
    static func valorEn(_ e: Elemento, _ p: CGPoint) -> Double {
        let r = riel(e)
        guard r.width > 0 else { return 0 }
        return max(0, min(1, (p.x - r.minX) / r.width))
    }

    // ── EL PINTADO ──────────────────────────────────────────────────────────

    static func pintar(_ e: Elemento, _ ctx: CGContext, _ tema: Tema, valor v: Double,
                       senalado: Int? = nil, lazo: Lazo.Vivo? = nil) {
        let tinte = e.territorio ?? "morado"
        let (tenue, medio, fuerte) = tonos(tema, tinte)

        switch tipo(e) {
        case "lazo":
            // El LAZO: grafo quieto + pulso que corre + comparador. Su dial es
            // la REFERENCIA (el techo). Ver `Lazo.swift`.
            let vivo = lazo ?? Lazo.Vivo(referencia: v)
            vivo.referencia = v
            Lazo.pintar(e, ctx, tema, vivo: vivo, tenue: tenue, medio: medio, fuerte: fuerte)
        case "balance": balance(e, ctx, tema, v, tenue, medio, fuerte)
        case "grafica":
            // La gráfica NO lleva dial: se opera con el ratón encima, no
            // arrastrando. Devuelve antes de llegar al riel.
            grafica(e, ctx, tema, senalado, tenue, medio, fuerte)
            return
        default:        engranes(e, ctx, tema, v, tenue, medio, fuerte)
        }
        dial(e, ctx, tema, v, medio, fuerte)
    }

    private static func tonos(_ tema: Tema, _ tinte: String) -> (NSColor, NSColor, NSColor) {
        guard let t = tema.tintes[tinte] else {
            return (tema.rol("card").relleno, tema.cuerpoTexto, tema.tituloTexto)
        }
        return (t.relleno, t.etiqueta, t.trazo)
    }

    // ── EL TREN DE ENGRANES ─────────────────────────────────────────────────
    /**
     * La transmisión, dibujada: el motriz gira lo que dice el dial y **cada
     * rueda siguiente gira al revés y más rápido en proporción a sus dientes**.
     * Eso es lo que hay que sentir — que tocar UNA cosa mueve TODO el sistema, y
     * que no todas se mueven igual.
     */
    private static func engranes(_ e: Elemento, _ ctx: CGContext, _ tema: Tema,
                                 _ v: Double, _ tenue: NSColor, _ medio: NSColor,
                                 _ fuerte: NSColor) {
        let ps = piezas(e)
        let hayRotulos = ps.contains { !$0.rotulo.isEmpty }
        // Lo que queda ENCIMA del dial, menos el renglón de rótulos si los hay:
        // una rueda que invade su propio rótulo es una rueda mal medida.
        let zonaAlto = e.alto - 74 - (hayRotulos ? 26 : 0)
        let dMax = min(zonaAlto * 0.92, e.ancho / Double(max(1, ps.count)) * 1.5)
        let radios = ps.map { $0.radio * dMax / 2 }
        // Se colocan tangentes: el borde de una toca el de la siguiente, que es
        // la única disposición en la que un engranaje se lee como engranaje. Y
        // el tren se CENTRA: pegado a la izquierda deja un vacío a la derecha
        // que el ojo lee como pieza faltante, no como aire.
        var dx: [Double] = [0]
        for i in 1..<max(1, radios.count) {
            dx.append(dx[i - 1] + (radios[i - 1] + radios[i]) * 0.90)
        }
        let ancho = (dx.last ?? 0) + radios[0] + (radios.last ?? 0)
        let x0 = e.x + (e.ancho - ancho) / 2 + radios[0]
        let cy = e.y + 26 + zonaAlto / 2
        let centros = dx.map { CGPoint(x: x0 + $0, y: cy) }

        // Ángulo del motriz: dos vueltas completas de extremo a extremo del
        // dial. Suficiente para ver girar, poco para marear.
        let anguloMotriz = v * 4 * .pi
        var angulo = anguloMotriz
        for (i, r) in radios.enumerated() {
            if i > 0 {
                // Relación de transmisión: menos dientes = más vueltas, y al revés.
                let k = Double(ps[i - 1].dientes) / Double(ps[i].dientes)
                angulo = -angulo * k
            }
            rueda(ctx, centros[i], r, ps[i].dientes, angulo,
                  relleno: i == 0 ? medio.withAlphaComponent(0.30) : tenue,
                  trazo: i == 0 ? fuerte : medio,
                  grosor: i == 0 ? 6 : 4)
            if !ps[i].rotulo.isEmpty {
                var est = EstiloTexto(); est.peso = 700; est.tamano = 15
                let p = Pintor(ctx: ctx, tema: tema, camara: Camara(),
                               tamano: CGSize(width: 1, height: 1))
                // TODOS los rótulos en la MISMA línea, la de la rueda más
                // grande. Colgado cada uno de su propia rueda, el renglón sube
                // y baja con los radios y se lee como cuatro pies de foto
                // sueltos en vez de una fila de nombres.
                p.renglon(ps[i].rotulo, est, tema.pieTexto,
                          x: centros[i].x - r, y: cy + (radios.max() ?? r) + 14,
                          ancho: r * 2, alinea: "center")
            }
        }
    }

    // ── EL BALANCE — lo que SUBE cuando algo BAJA ───────────────────────────
    /**
     * El otro mecanismo que el curso necesita: un **compromiso**. Un solo dial,
     * varias barras, y **unas suben mientras otras bajan**.
     *
     * Nace de la capa 2: *"un modelo con demasiado contexto te responde más a
     * detalle… pero es más lento. Uno con menos contexto es más rápido, consume
     * menos tokens, menos energía. Tu capacidad de ingeniería de contexto es
     * saber jugar entre ese balance"* (Daniel, 26 ago). Eso NO se entiende
     * leyéndolo: se entiende cuando mueves el dial y ves que **nunca ganas las
     * dos cosas a la vez**.
     *
     * Cada pieza declara si sigue al dial (`radio` ≥ 0) o si va al revés
     * (`radio` < 0). Es el mismo campo que en los engranes porque significa lo
     * mismo: cuánto y en qué sentido responde esta pieza a la que mandas.
     */
    private static func balance(_ e: Elemento, _ ctx: CGContext, _ tema: Tema,
                                _ v: Double, _ tenue: NSColor, _ medio: NSColor,
                                _ fuerte: NSColor) {
        let ps = piezasCrudas(e)
        guard !ps.isEmpty else { return }
        let zona = CGRect(x: e.x + 40, y: e.y + 26,
                          width: e.ancho - 80, height: e.alto - 100)
        let gap = 22.0
        let alto = (zona.height - gap * Double(ps.count - 1)) / Double(ps.count)
        let p = Pintor(ctx: ctx, tema: tema, camara: Camara(),
                       tamano: CGSize(width: 1, height: 1))
        for (i, pieza) in ps.enumerated() {
            let y = zona.minY + Double(i) * (alto + gap)
            // Signo negativo = va AL REVÉS que el dial. Ahí está la lección.
            let frac = pieza.radio >= 0 ? v : 1 - v
            let pista = CGRect(x: zona.minX + 210, y: y, width: zona.width - 210, height: alto)

            var est = EstiloTexto(); est.peso = 800; est.tamano = 19
            p.renglon(pieza.rotulo, est, tema.cuerpoTexto,
                      x: zona.minX, y: y + alto / 2 - 11, ancho: 196, alinea: "right")

            let fondo = CGMutablePath()
            fondo.addRoundedRectSeguro(in: pista, cornerWidth: 8, cornerHeight: 8)
            ctx.addPath(fondo)
            ctx.setFillColor(tema.rol("sticky").relleno.cgColor); ctx.fillPath()

            let lleno = CGRect(x: pista.minX, y: pista.minY,
                               width: max(6, pista.width * frac), height: pista.height)
            let camino = CGMutablePath()
            camino.addRoundedRectSeguro(in: lleno, cornerWidth: 8, cornerHeight: 8)
            ctx.saveGState(); ctx.addPath(fondo); ctx.clip()
            ctx.addPath(camino)
            ctx.setFillColor((pieza.radio >= 0 ? medio : fuerte).withAlphaComponent(0.55).cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.addPath(fondo)
            ctx.setStrokeColor(medio.withAlphaComponent(0.45).cgColor)
            ctx.setLineWidth(2); ctx.strokePath()
        }
    }

    // ── LA GRÁFICA — el único mecanismo que se opera con el ratón ENCIMA ────
    /**
     * UNA GRÁFICA MEDIDA, no una ilustración de una gráfica.
     *
     * Daniel, 26 ago: *«esta gráfica, en vez de una imagen, enacta una gráfica
     * que al hacer hover me muestre los modelos correctos… bien medido todo,
     * bien preciso el eje x y el eje y»*.
     *
     * La diferencia con la lámina que sustituye es de honestidad: una curva
     * dibujada a mano insinúa datos; esta los TIENE. Cada punto lleva su año y
     * sus horas y cae donde le toca, y la escala del eje Y la fija el punto más
     * alto — nada se coloca a ojo.
     *
     * ⚠️ LOS DATOS NO SON MÍOS: vienen declarados en el elemento, con su fuente
     * escrita en el pie. Este archivo los COLOCA; no los inventa.
     */
    struct Punto { var x: Double; var y: Double; var rotulo: String; var apagado: Bool }

    static func puntos(_ e: Elemento) -> [Punto] {
        guard let lista = e.crudo["mecanismo"]?["puntos"]?.arr else { return [] }
        return lista.map {
            Punto(x: $0["x"]?.num ?? 0, y: $0["y"]?.num ?? 0,
                  rotulo: $0["rotulo"]?.s ?? "", apagado: $0["apagado"]?.b ?? false)
        }
    }

    /// El marco de dibujo: deja sitio para los rótulos de los dos ejes.
    static func plano(_ e: Elemento) -> CGRect {
        CGRect(x: e.x + 150, y: e.y + 40, width: e.ancho - 200, height: e.alto - 130)
    }

    private static func ejeX(_ e: Elemento) -> (Double, Double) {
        let p = puntos(e)
        let x0 = e.crudo["mecanismo"]?["x0"]?.num ?? (p.map(\.x).min() ?? 0)
        let x1 = e.crudo["mecanismo"]?["x1"]?.num ?? (p.map(\.x).max() ?? 1)
        return (x0, x1 > x0 ? x1 : x0 + 1)
    }
    private static func ejeY(_ e: Elemento) -> Double {
        e.crudo["mecanismo"]?["y1"]?.num ?? max(1, puntos(e).map(\.y).max() ?? 1)
    }

    /// Mundo → plano. Es la ÚNICA función que convierte dato en píxel: si el
    /// hover y el pintado usaran cuentas distintas, la etiqueta señalaría un
    /// punto y el ratón otro.
    static func aPlano(_ e: Elemento, _ p: Punto) -> CGPoint {
        let r = plano(e), (x0, x1) = ejeX(e), y1 = ejeY(e)
        return CGPoint(x: r.minX + (p.x - x0) / (x1 - x0) * r.width,
                       y: r.maxY - min(p.y, y1) / y1 * r.height)
    }

    /// El punto bajo el ratón, si hay alguno cerca. Radio generoso: en cámara
    /// nadie acierta un círculo de 9 px.
    static func puntoEn(_ e: Elemento, _ w: CGPoint) -> Int? {
        var mejor: (Int, Double)? = nil
        for (i, p) in puntos(e).enumerated() {
            let c = aPlano(e, p)
            let d = Double(hypot(w.x - c.x, w.y - c.y))
            if d < 60 && (mejor == nil || d < mejor!.1) { mejor = (i, d) }
        }
        return mejor?.0
    }

    private static func grafica(_ e: Elemento, _ ctx: CGContext, _ tema: Tema,
                               _ senalado: Int?, _ tenue: NSColor, _ medio: NSColor,
                               _ fuerte: NSColor) {
        let r = plano(e), ps = puntos(e)
        let (x0, x1) = ejeX(e), y1 = ejeY(e)
        let p = Pintor(ctx: ctx, tema: tema, camara: Camara(),
                       tamano: CGSize(width: 1, height: 1))
        var chico = EstiloTexto(); chico.peso = 700; chico.tamano = 20
        var fuerteEst = EstiloTexto(); fuerteEst.peso = 800; fuerteEst.tamano = 22

        // ── la rejilla y los rótulos del eje Y ──
        let marcas = e.crudo["mecanismo"]?["marcasY"]?.arr ?? []
        ctx.saveGState()
        ctx.setLineWidth(1.5)
        ctx.setStrokeColor(tema.reticula.cgColor)
        for m in marcas {
            guard let v = m["v"]?.num else { continue }
            let y = r.maxY - min(v, y1) / y1 * r.height
            ctx.move(to: CGPoint(x: r.minX, y: y)); ctx.addLine(to: CGPoint(x: r.maxX, y: y))
            p.renglon(m["t"]?.s ?? "", chico, tema.pieTexto,
                      x: e.x, y: y - 12, ancho: 130, alinea: "right")
        }
        ctx.strokePath()

        // ── los ejes ──
        ctx.setStrokeColor(tema.cuerpoTexto.withAlphaComponent(0.55).cgColor)
        ctx.setLineWidth(3)
        ctx.move(to: CGPoint(x: r.minX, y: r.minY)); ctx.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        ctx.strokePath()

        // ── los rótulos del eje X (años enteros dentro del rango) ──
        var a = ceil(x0)
        while a <= x1 {
            let x = r.minX + (a - x0) / (x1 - x0) * r.width
            ctx.setStrokeColor(tema.reticula.cgColor); ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: x, y: r.maxY)); ctx.addLine(to: CGPoint(x: x, y: r.maxY + 10))
            ctx.strokePath()
            p.renglon(String(Int(a)), chico, tema.pieTexto,
                      x: x - 70, y: r.maxY + 18, ancho: 140, alinea: "center")
            a += 1
        }

        // ── la línea que une los puntos ──
        if ps.count > 1 {
            ctx.setStrokeColor(medio.cgColor)
            ctx.setLineWidth(4)
            ctx.setLineDash(phase: 0, lengths: [10, 8])
            for (i, pt) in ps.enumerated() {
                let c = aPlano(e, pt)
                i == 0 ? ctx.move(to: c) : ctx.addLine(to: c)
            }
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

        // ── los puntos ──
        for (i, pt) in ps.enumerated() {
            let c = aPlano(e, pt)
            let vivo = (i == senalado)
            let rad = vivo ? 22.0 : 13.0
            if vivo {
                ctx.setFillColor(fuerte.withAlphaComponent(0.20).cgColor)
                ctx.fillEllipse(in: CGRect(x: c.x - 40, y: c.y - 40, width: 80, height: 80))
            }
            ctx.setFillColor((pt.apagado ? tema.pieTexto : fuerte).cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2))
            ctx.setStrokeColor(tema.lienzo.cgColor); ctx.setLineWidth(3)
            ctx.strokeEllipse(in: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2))
        }

        // ── la etiqueta del punto señalado: NOMBRE y VALOR, no adivinanzas ──
        if let i = senalado, i < ps.count {
            let pt = ps[i], c = aPlano(e, pt)
            let texto = pt.rotulo
            let valor = e.crudo["mecanismo"]?["unidad"]?.s ?? ""
            let sub = valor.isEmpty ? "" : Self.formato(pt.y) + " " + valor
            let ancho = max(260.0, Double(texto.count) * 15 + 60)
            var caja = CGRect(x: c.x - ancho / 2, y: c.y - 130, width: ancho, height: 96)
            caja.origin.x = min(max(caja.minX, e.x + 8), e.x + e.ancho - ancho - 8)
            if caja.minY < e.y { caja.origin.y = c.y + 44 }
            let camino = CGMutablePath()
            camino.addRoundedRectSeguro(in: caja, cornerWidth: 10, cornerHeight: 10)
            ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 10,
                          color: NSColor.black.withAlphaComponent(0.22).cgColor)
            ctx.addPath(camino); ctx.setFillColor(tema.lienzo.cgColor); ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.addPath(camino); ctx.setStrokeColor(fuerte.cgColor); ctx.setLineWidth(3)
            ctx.strokePath()
            p.renglon(texto, fuerteEst, tema.tituloTexto,
                      x: caja.minX, y: caja.minY + 16, ancho: caja.width, alinea: "center")
            p.renglon(sub, chico, tema.pieTexto,
                      x: caja.minX, y: caja.minY + 54, ancho: caja.width, alinea: "center")
        } else {
            p.renglon(rotulo(e), chico, tema.pieTexto,
                      x: e.x, y: e.y + e.alto - 40, ancho: e.ancho, alinea: "center")
        }
        ctx.restoreGState()
    }

    /// 0.5 → «30 min» · 12 → «12 h». El eje habla en horas porque el dato son
    /// horas; escribir «0.5 h» sería exacto y a la vez ilegible.
    static func formato(_ h: Double) -> String {
        if h < 1 { return String(Int((h * 60).rounded())) + " min" }
        if h == h.rounded() { return String(Int(h)) + " h" }
        return String(format: "%.1f h", h)
    }

    /// Las piezas SIN normalizar el signo: el balance necesita saber si una
    /// pieza va al revés, y ese dato vive en el signo de `radio`.
    private static func piezasCrudas(_ e: Elemento) -> [Pieza] {
        guard let lista = e.crudo["mecanismo"]?["piezas"]?.arr else { return [] }
        return lista.map {
            Pieza(radio: $0["radio"]?.num ?? 1,
                  dientes: max(5, Int($0["dientes"]?.num ?? 12)),
                  rotulo: $0["rotulo"]?.s ?? "")
        }
    }

    /// Una rueda dentada: círculo + dientes trapezoidales, girada su ángulo.
    private static func rueda(_ ctx: CGContext, _ c: CGPoint, _ r: Double, _ dientes: Int,
                              _ angulo: Double, relleno: NSColor, trazo: NSColor,
                              grosor: Double) {
        let camino = CGMutablePath()
        let alto = r * 0.20                     // altura del diente
        let rInt = r - alto
        let paso = 2 * .pi / Double(dientes)
        for i in 0..<dientes {
            let a = angulo + Double(i) * paso
            // Cada diente: sube, cruza la punta, baja, y el valle hasta el
            // siguiente. Las puntas son más angostas que el valle (trapecio),
            // que es lo que hace que se lea como engrane y no como sol.
            let p0 = CGPoint(x: c.x + cos(a) * rInt, y: c.y + sin(a) * rInt)
            let p1 = CGPoint(x: c.x + cos(a + paso * 0.16) * r,
                             y: c.y + sin(a + paso * 0.16) * r)
            let p2 = CGPoint(x: c.x + cos(a + paso * 0.34) * r,
                             y: c.y + sin(a + paso * 0.34) * r)
            let p3 = CGPoint(x: c.x + cos(a + paso * 0.50) * rInt,
                             y: c.y + sin(a + paso * 0.50) * rInt)
            if i == 0 { camino.move(to: p0) } else { camino.addLine(to: p0) }
            camino.addLine(to: p1); camino.addLine(to: p2); camino.addLine(to: p3)
        }
        camino.closeSubpath()

        ctx.saveGState()
        ctx.addPath(camino)
        ctx.setFillColor(relleno.cgColor); ctx.fillPath()
        ctx.addPath(camino)
        ctx.setStrokeColor(trazo.cgColor)
        ctx.setLineWidth(grosor); ctx.setLineJoin(.round)
        ctx.strokePath()

        // El eje y UN radio marcado: sin una marca, un engrane girando se ve
        // idéntico a un engrane quieto. La marca ES el movimiento.
        ctx.setStrokeColor(trazo.cgColor); ctx.setLineWidth(grosor * 0.8)
        ctx.move(to: c)
        ctx.addLine(to: CGPoint(x: c.x + cos(angulo) * rInt * 0.82,
                                y: c.y + sin(angulo) * rInt * 0.82))
        ctx.strokePath()
        ctx.setFillColor(trazo.cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - r * 0.10, y: c.y - r * 0.10,
                                   width: r * 0.20, height: r * 0.20))
        ctx.restoreGState()
    }

    // ── EL DIAL ─────────────────────────────────────────────────────────────
    /**
     * Tiene que PEDIR que lo agarren. Un riel plano se confunde con una regla:
     * la perilla lleva sombra propia y un tamaño de dedo, y el riel se pinta
     * lleno hasta donde va — así el valor se lee sin números.
     */
    private static func dial(_ e: Elemento, _ ctx: CGContext, _ tema: Tema,
                             _ v: Double, _ medio: NSColor, _ fuerte: NSColor) {
        let r = riel(e)
        ctx.saveGState()
        let pista = CGMutablePath()
        pista.addRoundedRectSeguro(in: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2)
        ctx.addPath(pista)
        ctx.setFillColor(tema.rol("sticky").relleno.cgColor); ctx.fillPath()
        ctx.addPath(pista)
        ctx.setStrokeColor(medio.withAlphaComponent(0.55).cgColor)
        ctx.setLineWidth(2); ctx.strokePath()

        // Lo recorrido
        let lleno = CGRect(x: r.minX, y: r.minY, width: max(0, r.width * v), height: r.height)
        let camino = CGMutablePath()
        camino.addRoundedRectSeguro(in: lleno, cornerWidth: r.height / 2, cornerHeight: r.height / 2)
        ctx.saveGState(); ctx.addPath(pista); ctx.clip()
        ctx.addPath(camino); ctx.setFillColor(medio.withAlphaComponent(0.45).cgColor)
        ctx.fillPath(); ctx.restoreGState()

        // La perilla
        let cx = r.minX + r.width * v
        let rad = r.height * 0.95
        let perilla = CGRect(x: cx - rad, y: r.midY - rad, width: rad * 2, height: rad * 2)
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 6,
                      color: NSColor.black.withAlphaComponent(0.22).cgColor)
        ctx.setFillColor(fuerte.cgColor); ctx.fillEllipse(in: perilla)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setStrokeColor(tema.lienzo.cgColor); ctx.setLineWidth(3)
        ctx.strokeEllipse(in: perilla.insetBy(dx: 4, dy: 4))

        let texto = rotulo(e)
        if !texto.isEmpty {
            var est = EstiloTexto(); est.peso = 700; est.tamano = 15
            let p = Pintor(ctx: ctx, tema: tema, camara: Camara(),
                           tamano: CGSize(width: 1, height: 1))
            let margen = min(40.0, e.ancho * 0.08)
            p.renglon(texto, est, tema.pieTexto,
                      x: e.x + margen, y: r.midY - 9,
                      ancho: Double(r.minX) - (e.x + margen) - 14, alinea: "right")
        }
        ctx.restoreGState()
    }
}
