import CoreGraphics
import Foundation

/**
 * La geometria del lienzo. UN SOLO LUGAR.
 *
 * En el v3 el contorno de cada figura estaba escrito TRES veces —el que
 * dibuja, el que clickea y el que ancla conectores— y ya habian divergido: una
 * estrella se anclaba con un radio interno distinto al que pintaba, y el
 * hit-test ignoraba el espejado por completo. Aqui hay una funcion que devuelve
 * el contorno y todos la consumen: si algun dia diverge, divergen los tres
 * juntos, que es la unica forma honesta de fallar.
 */
enum Geo {

    // ── contorno ────────────────────────────────────────────────────────────

    /// El contorno de una figura como puntos. `nil` = tiene camino propio
    /// (rectangulo redondeado, pildora, elipse).
    static func contorno(_ figura: String, _ r: CGRect) -> [CGPoint]? {
        let cx = r.midX, cy = r.midY
        switch figura {
        case "triangle":
            return [CGPoint(x: cx, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        case "diamond":
            return [CGPoint(x: cx, y: r.minY), CGPoint(x: r.maxX, y: cy),
                    CGPoint(x: cx, y: r.maxY), CGPoint(x: r.minX, y: cy)]
        case "hexagon":
            // Hexagono "de tarjeta": lados verticales rectos y puntas a los
            // lados. El regular se ve decorativo en un diagrama.
            let corte = min(r.width * 0.22, r.height * 0.5)
            return [CGPoint(x: r.minX + corte, y: r.minY), CGPoint(x: r.maxX - corte, y: r.minY),
                    CGPoint(x: r.maxX, y: cy),
                    CGPoint(x: r.maxX - corte, y: r.maxY), CGPoint(x: r.minX + corte, y: r.maxY),
                    CGPoint(x: r.minX, y: cy)]
        case "arrow":
            let puntaW = min(r.width * 0.38, r.height * 0.9)
            let cuerpo = r.height * 0.24
            return [CGPoint(x: r.minX, y: r.minY + cuerpo), CGPoint(x: r.maxX - puntaW, y: r.minY + cuerpo),
                    CGPoint(x: r.maxX - puntaW, y: r.minY), CGPoint(x: r.maxX, y: cy),
                    CGPoint(x: r.maxX - puntaW, y: r.maxY), CGPoint(x: r.maxX - puntaW, y: r.maxY - cuerpo),
                    CGPoint(x: r.minX, y: r.maxY - cuerpo)]
        case "star":
            let rx = r.width / 2, ry = r.height / 2, interior = 0.42
            return (0..<10).map { i in
                let ang = Double.pi * Double(i) / 5 - .pi / 2
                let f = i % 2 == 0 ? 1.0 : interior
                return CGPoint(x: cx + cos(ang) * rx * f, y: cy + sin(ang) * ry * f)
            }
        default:
            return nil   // rect, pill, ellipse
        }
    }

    /// ¿El punto cae DENTRO de la figura? Usa el MISMO contorno que se dibuja.
    ///
    /// Una estrella tiene huecos entre sus puntas y un triangulo deja media
    /// caja vacia: tratarlos como rectangulos hace que se agarren por el aire y
    /// que tapen lo que tienen detras en esos huecos.
    static func dentro(_ figura: String, _ r: CGRect, _ p: CGPoint) -> Bool {
        if figura == "ellipse" {
            let rx = r.width / 2, ry = r.height / 2
            guard rx > 0, ry > 0 else { return false }
            let dx = (p.x - (r.minX + rx)) / rx, dy = (p.y - (r.minY + ry)) / ry
            return dx * dx + dy * dy <= 1
        }
        guard let pts = contorno(figura, r) else { return r.contains(p) }
        // Test del rayo.
        var dentro = false
        var j = pts.count - 1
        for i in 0..<pts.count {
            let yi = pts[i].y, yj = pts[j].y
            if (yi > p.y) != (yj > p.y) {
                let corte = (pts[j].x - pts[i].x) * (p.y - yi) / (yj - yi) + pts[i].x
                if p.x < corte { dentro.toggle() }
            }
            j = i
        }
        return dentro
    }

    // ── giro ────────────────────────────────────────────────────────────────

    static func estaGirado(_ e: Elemento) -> Bool { abs(e.giro) > 1e-4 }

    /// Lleva un punto del MUNDO al marco propio del elemento (deshace el giro).
    ///
    /// El v3 tenia el giro en el pintor y NO en el hit-test: una figura girada
    /// se veia en un sitio y se agarraba en otro.
    static func aLocal(_ e: Elemento, _ p: CGPoint) -> CGPoint {
        guard estaGirado(e) else { return p }
        let c = CGPoint(x: e.caja.midX, y: e.caja.midY)
        let a = -e.giro, co = cos(a), si = sin(a)
        let dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(x: c.x + dx * co - dy * si, y: c.y + dx * si + dy * co)
    }

    static func aMundo(_ e: Elemento, _ p: CGPoint) -> CGPoint {
        guard estaGirado(e) else { return p }
        let c = CGPoint(x: e.caja.midX, y: e.caja.midY)
        let co = cos(e.giro), si = sin(e.giro)
        let dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(x: c.x + dx * co - dy * si, y: c.y + dx * si + dy * co)
    }

    private static let GRADO = Double.pi / 180

    /// Ajusta el angulo a un valor limpio.
    ///
    /// SIEMPRE se imanta a los multiplos de 90° dentro de 5°: el ojo no
    /// distingue 0.4° pero el archivo lo guarda para siempre, y volver a dejar
    /// algo derecho a mano seria imposible. Con Shift, escalones de 15°.
    static func ajustarAngulo(_ rad: Double, shift: Bool) -> Double {
        if shift { return (rad / (15 * GRADO)).rounded() * (15 * GRADO) }
        let cuarto = Double.pi / 2
        let cerca = (rad / cuarto).rounded() * cuarto
        return abs(rad - cerca) <= 5 * GRADO ? cerca : rad
    }

    /// El angulo del puntero respecto al centro. El cero esta ARRIBA, que es de
    /// donde sale el tirador que la mano agarra.
    static func anguloHacia(_ centro: CGPoint, _ p: CGPoint) -> Double {
        atan2(p.y - centro.y, p.x - centro.x) + .pi / 2
    }

    static func normalizar(_ rad: Double) -> Double {
        let dosPi = Double.pi * 2
        var r = rad.truncatingRemainder(dividingBy: dosPi)
        if r > .pi { r -= dosPi }
        if r <= -.pi { r += dosPi }
        return r
    }

    static func enGrados(_ rad: Double) -> Int { Int((normalizar(rad) / GRADO).rounded()) }

    // ── hit test ────────────────────────────────────────────────────────────

    private static let AGARRE = 6.0

    /// Interna a propósito: la goma mide con la MISMA cuenta que el hit-test
    /// del puntero. Dos distancias distintas para la misma pregunta acaban
    /// divergiendo, y entonces el ojo y la mano dejan de coincidir.
    static func distanciaASegmento(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 == 0 { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
        t = max(0, min(1, t))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// El elemento de mas arriba bajo el punto, o nil.
    ///
    /// ⚠️ LO BLOQUEADO SE PUEDE SELECCIONAR, pero no mover. Saltarlo aqui
    /// convierte el candado en una trampa: sin panel de capas, un elemento que
    /// no se puede seleccionar no se puede desbloquear NUNCA. Lo que impide el
    /// movimiento es el arrastre, que es donde pertenece la regla.
    static func elegir(_ elementos: [Elemento], _ punto: CGPoint, zoom: Double) -> Elemento? {
        let agarre = AGARRE / zoom
        for e in elementos.sorted(by: { $0.z > $1.z }) {
            let p = aLocal(e, punto)

            if e.tipo == "connector" {
                let r = TrazoConector.muestras(e)
                for i in 0..<max(0, r.count - 1) where distanciaASegmento(p, r[i], r[i + 1]) <= agarre {
                    return e
                }
                continue
            }
            if e.tipo == "ink" {
                // Un trazo se agarra por su TINTA, no por su caja: la caja de
                // una firma diagonal es enorme y casi toda vacia.
                let pts = e.trazoPuntos
                // El radio de agarre sale del MOTOR, no de `grosor/2`: con
                // presión alta la tinta se pinta más ancha que su grosor
                // nominal, y con el radio viejo se podía clicar encima de
                // tinta visible y no agarrar nada — el peor tipo de fallo,
                // porque el ojo dice que ahí hay algo.
                //
                // Se calcula UNA vez por trazo, no por segmento: `grosorTinta`,
                // `esMarcador` y el origen leen el JSON crudo en cada acceso, y
                // esto corre en cada movimiento del ratón contra cada punto de
                // cada trazo — 19,000 vueltas en una página escrita a mano.
                let medio = Tinta.diametro(Tinta.Opciones(grosor: e.grosorTinta,
                                                          marcador: e.esMarcador)) * 0.5 * Tinta.ANCHO_MAX
                let radio = agarre + medio
                let ox = e.x, oy = e.y
                for i in 0..<max(0, pts.count - 1) {
                    let a = CGPoint(x: ox + pts[i].x, y: oy + pts[i].y)
                    let b = CGPoint(x: ox + pts[i + 1].x, y: oy + pts[i + 1].y)
                    if distanciaASegmento(p, a, b) <= radio { return e }
                }
                continue
            }

            let b = e.caja
            guard b.insetBy(dx: -agarre, dy: -agarre).contains(p) else { continue }
            if e.tipo == "shape" {
                if dentro(e.figura, b, p) { return e }
                // Cerca del borde tambien cuenta: si no, el propio trazo del
                // contorno queda fuera de su zona de clic.
                if dentro(e.figura, b.insetBy(dx: -agarre, dy: -agarre), p) { return e }
                continue
            }
            return e
        }
        return nil
    }

    /**
     * A QUÉ se va a conectar una flecha soltada aquí.
     *
     * ⚠️ NO es `elegir`. Es la razón por la que Daniel no podía conectar dos
     * cajas: `elegir` prueba contra `caja`, y el PIE de una tarjeta compilada
     * cuelga POR DEBAJO de ella. En un diagrama real, media superficie visible
     * de cada tarjeta es su pie — soltar ahí caía en "vacío" y en vez de
     * conectar nacía una figura nueva. El mecanismo estaba bien; lo que estaba
     * mal era dónde se podía soltar.
     *
     * Aquí manda la caja VISUAL (la que el ojo ve, pie incluido) con un margen
     * generoso: apuntar a un blanco de 6 px es un castigo, y en un gesto que
     * cruza el lienzo entero la mano llega con inercia.
     */
    static func candidatoConexion(_ els: [Elemento], _ p: CGPoint, zoom: Double,
                                  excluir: String) -> Elemento? {
        if let exacto = elegir(els, p, zoom: zoom), exacto.id != excluir,
           aceptaPuertos(exacto) { return exacto }
        let margen = 20 / zoom
        return els.sorted { $0.z > $1.z }.first {
            $0.id != excluir && aceptaPuertos($0)
                && $0.cajaVisual.insetBy(dx: -margen, dy: -margen).contains(p)
        }
    }

    // ── manijas ─────────────────────────────────────────────────────────────

    static let MANIJAS = ["nw", "n", "ne", "e", "se", "s", "sw", "w"]
    static let GIRO = "rotate"
    /// Lado en px de PANTALLA. Una manija que encoge al alejarse se vuelve
    /// inagarrable justo cuando mas falta hace.
    static let MANIJA_PX = 9.0
    static let GIRO_SEPARACION_PX = 26.0
    private static let GIRO_AGARRE_PX = 13.0

    static func centroManija(_ r: CGRect, _ h: String) -> CGPoint {
        switch h {
        case "nw": return CGPoint(x: r.minX, y: r.minY)
        case "n":  return CGPoint(x: r.midX, y: r.minY)
        case "ne": return CGPoint(x: r.maxX, y: r.minY)
        case "e":  return CGPoint(x: r.maxX, y: r.midY)
        case "se": return CGPoint(x: r.maxX, y: r.maxY)
        case "s":  return CGPoint(x: r.midX, y: r.maxY)
        case "sw": return CGPoint(x: r.minX, y: r.maxY)
        default:   return CGPoint(x: r.minX, y: r.midY)
        }
    }

    static func centroGiro(_ r: CGRect, zoom: Double) -> CGPoint {
        CGPoint(x: r.midX, y: r.minY - GIRO_SEPARACION_PX / zoom)
    }

    /// Cuanto se extiende POR FUERA la zona de giro de cada esquina.
    static let GIRO_ESQUINA_PX = 20.0

    /**
     * GIRAR DESDE LAS ESQUINAS, como Miro y como Figma.
     *
     * Daniel: *"hace falta una flechita que me permita rotar componentes a las
     * afueras del mismo, en múltiples lados"*. El tirador de arriba sigue, pero
     * era el UNICO sitio: para girar algo pegado al borde superior de la
     * pantalla no habia forma de agarrarlo.
     *
     * La zona vive en el CUADRANTE EXTERIOR de cada esquina —fuera de la caja y
     * fuera de la manija de redimensionar, que gana por estar antes— asi que
     * nunca le roba el gesto a nada: ese trozo de lienzo no hacia nada.
     */
    static func giroEnEsquina(_ r: CGRect, _ p: CGPoint, zoom: Double) -> String? {
        let fuera = GIRO_ESQUINA_PX / zoom
        let dentro = (MANIJA_PX / 2 + 3) / zoom
        for h in ["nw", "ne", "se", "sw"] {
            let c = centroManija(r, h)
            let dx = p.x - c.x, dy = p.y - c.y
            guard abs(dx) <= fuera, abs(dy) <= fuera else { continue }
            // Solo hacia AFUERA: hacia adentro esta la figura, y ahi mandan el
            // arrastre y las manijas.
            let haciaFuera = (h == "nw" && dx <= dentro && dy <= dentro)
                || (h == "ne" && dx >= -dentro && dy <= dentro)
                || (h == "se" && dx >= -dentro && dy >= -dentro)
                || (h == "sw" && dx <= dentro && dy >= -dentro)
            guard haciaFuera else { continue }
            // Y fuera del cuadrado de la manija, que se prueba antes.
            if abs(dx) <= dentro && abs(dy) <= dentro { continue }
            return h
        }
        return nil
    }

    /// Que manija hay bajo el punto. El GIRO se prueba primero: vive fuera de
    /// la caja, asi que casi nunca compite, y cuando lo hace gana girar.
    static func manijaEn(_ r: CGRect, _ p: CGPoint, zoom: Double, texto: Bool = false) -> String? {
        let g = centroGiro(r, zoom: zoom)
        if !texto, hypot(p.x - g.x, p.y - g.y) <= GIRO_AGARRE_PX / zoom { return GIRO }
        let radio = (MANIJA_PX / 2 + 3) / zoom
        for h in MANIJAS where !texto || !["n", "s"].contains(h) {
            let c = centroManija(r, h)
            if abs(p.x - c.x) <= radio && abs(p.y - c.y) <= radio { return h }
        }
        if giroEnEsquina(r, p, zoom: zoom) != nil { return GIRO }
        return nil
    }

    static func cursorDeManija(_ h: String) -> NSCursorTipo {
        switch h {
        case "nw", "se": return .diagonalNWSE
        case "ne", "sw": return .diagonalNESW
        case "n", "s":   return .vertical
        case "e", "w":   return .horizontal
        default:         return .normal
        }
    }

    /// La caja resultante de arrastrar una manija. Se NORMALIZA: cruzar el lado
    /// opuesto da tamaño negativo, y sin normalizar el elemento desaparece en
    /// vez de voltearse.
    static func redimensionar(_ original: CGRect, _ h: String, _ d: CGPoint, proporcional: Bool) -> CGRect {
        var x = original.minX, y = original.minY, w = original.width, hh = original.height
        let oeste = h == "nw" || h == "w" || h == "sw"
        let este = h == "ne" || h == "e" || h == "se"
        let norte = h == "nw" || h == "n" || h == "ne"
        let sur = h == "sw" || h == "s" || h == "se"

        if oeste { x += d.x; w -= d.x }
        if este { w += d.x }
        if norte { y += d.y; hh -= d.y }
        if sur { hh += d.y }

        if proporcional && original.width > 0 && original.height > 0 {
            let aspecto = original.width / original.height
            // Manda el eje que mas se movio, o el gesto se siente pegajoso.
            if abs(d.x) > abs(d.y) {
                let nuevoAlto = w / aspecto
                if norte { y += hh - nuevoAlto }
                hh = nuevoAlto
            } else {
                let nuevoAncho = hh * aspecto
                if oeste { x += w - nuevoAncho }
                w = nuevoAncho
            }
        }
        if w < 0 { x += w; w = -w }
        if hh < 0 { y += hh; hh = -hh }
        return CGRect(x: x, y: y, width: max(8, w), height: max(8, hh))
    }

    // ── puertos ─────────────────────────────────────────────────────────────

    static let PUERTOS = ["n", "e", "s", "w"]
    /// Separacion del borde en px de PANTALLA. Los "milimetros afuera" que pidio
    /// Daniel, como los hace Notion.
    static let PUERTO_AIRE_PX = 13.0
    static let PUERTO_R_PX = 6.5
    private static let PUERTO_AGARRE_PX = 13.0

    static func puertosDe(_ e: Elemento, zoom: Double) -> [(id: String, p: CGPoint)] {
        let b = e.caja
        let g = PUERTO_AIRE_PX / zoom
        return [("n", CGPoint(x: b.midX, y: b.minY - g)),
                ("e", CGPoint(x: b.maxX + g, y: b.midY)),
                ("s", CGPoint(x: b.midX, y: b.maxY + g)),
                ("w", CGPoint(x: b.minX - g, y: b.midY))]
    }

    static func puertoEn(_ e: Elemento, _ p: CGPoint, zoom: Double) -> String? {
        let r = PUERTO_AGARRE_PX / zoom
        for (id, q) in puertosDe(e, zoom: zoom) where hypot(p.x - q.x, p.y - q.y) <= r { return id }
        return nil
    }

    // ── extremos de un conector ─────────────────────────────────────────────

    static let EXTREMOS = ["desde", "hasta"]
    static let EXTREMO_R_PX = 6.0
    private static let EXTREMO_AGARRE_PX = 12.0

    /**
     * Los dos puntos AGARRABLES de una flecha.
     *
     * Daniel: *"las flechas debo poder conectarlas a cualquier parte"*. Hasta
     * ahora una flecha nacia con su destino y se moria con el: la unica forma de
     * cambiarlo era borrarla y volver a trazarla. Y como un conector no muestra
     * manijas —su geometria se deriva de sus extremos, estirarle la caja no
     * significa nada— no habia NADA que agarrar.
     */
    static func extremosDe(_ conn: Elemento) -> [(cual: String, p: CGPoint)] {
        let r = conn.ruta
        guard r.count >= 2 else { return [] }
        return [("desde", r[0]), ("hasta", r[r.count - 1])]
    }

    static func extremoEn(_ conn: Elemento, _ p: CGPoint, zoom: Double) -> String? {
        let radio = EXTREMO_AGARRE_PX / zoom
        for (cual, q) in extremosDe(conn) where hypot(p.x - q.x, p.y - q.y) <= radio { return cual }
        return nil
    }

    /// Que elementos ACEPTAN puertos. Un conector no se conecta a otro conector
    /// y la tinta no tiene lados: pintar puertos sobre un garabato promete algo
    /// que el modelo no puede cumplir.
    static func aceptaPuertos(_ e: Elemento) -> Bool {
        ["shape", "frame", "image", "table", "code", "text", "embed"].contains(e.tipo)
    }

    /// ¿Se muestran los puertos de este elemento ahora mismo? Solo con el
    /// puntero cerca: pintarlos siempre llena el lienzo de puntos flotantes.
    static func cercaDe(_ e: Elemento, _ p: CGPoint, zoom: Double) -> Bool {
        let m = (PUERTO_AIRE_PX + PUERTO_R_PX * 2) / zoom
        return e.caja.insetBy(dx: -m, dy: -m).contains(p)
    }

    // ── imantado ────────────────────────────────────────────────────────────

    struct Guia { var eje: String; var valor: Double; var desde: Double; var hasta: Double }
    struct Iman { var dx: Double; var dy: Double; var guias: [Guia] }

    private static let IMAN_PX = 7.0

    /// El imantado de una caja contra las demas: los dos bordes y el centro de
    /// cada eje. Se queda con el candidato MAS CERCANO por eje — imantar a
    /// varios a la vez produce saltos contradictorios.
    ///
    /// La guia y el iman van juntos: mostrar la guia sin imantar es decorativo,
    /// imantar sin mostrarla se siente embrujado.
    static func imantar(_ movida: CGRect, _ otros: [Elemento], zoom: Double, ignorar: Set<String>) -> Iman {
        let radio = IMAN_PX / zoom
        let cajas = otros.filter { !ignorar.contains($0.id) && $0.tipo != "connector" }.map(\.caja)
        let refX = { (c: CGRect) -> [Double] in [c.minX, c.midX, c.maxX] }
        let refY = { (c: CGRect) -> [Double] in [c.minY, c.midY, c.maxY] }

        var mejorX: (delta: Double, valor: Double, otra: CGRect)?
        var mejorY: (delta: Double, valor: Double, otra: CGRect)?
        for otra in cajas {
            for rx in refX(otra) {
                for mx in refX(movida) {
                    let d = rx - mx
                    if abs(d) <= radio && (mejorX == nil || abs(d) < abs(mejorX!.delta)) {
                        mejorX = (d, rx, otra)
                    }
                }
            }
            for ry in refY(otra) {
                for my in refY(movida) {
                    let d = ry - my
                    if abs(d) <= radio && (mejorY == nil || abs(d) < abs(mejorY!.delta)) {
                        mejorY = (d, ry, otra)
                    }
                }
            }
        }
        var guias: [Guia] = []
        // La guia se extiende solo entre las dos cajas implicadas. Una linea de
        // borde a borde es ruido: no dice CON QUE te estas alineando.
        if let m = mejorX {
            guias.append(Guia(eje: "x", valor: m.valor,
                              desde: Double(min(movida.minY, m.otra.minY)) - 16,
                              hasta: Double(max(movida.maxY, m.otra.maxY)) + 16))
        }
        if let m = mejorY {
            guias.append(Guia(eje: "y", valor: m.valor,
                              desde: Double(min(movida.minX, m.otra.minX)) - 16,
                              hasta: Double(max(movida.maxX, m.otra.maxX)) + 16))
        }
        return Iman(dx: mejorX?.delta ?? 0, dy: mejorY?.delta ?? 0, guias: guias)
    }

    // ── alinear y distribuir ────────────────────────────────────────────────

    /// Alinea. Devuelve nil con menos de dos: alinear uno consigo mismo no
    /// significa nada, y fingir que se hizo algo es peor que no hacerlo — el v3
    /// reportaba exito INCONDICIONALMENTE.
    static func alinear(_ els: [Elemento], _ ids: Set<String>, _ eje: String) -> [String: CGPoint]? {
        let cs = els.filter { ids.contains($0.id) }
        guard cs.count >= 2 else { return nil }
        let minX = Double(cs.map(\.caja.minX).min()!), maxX = Double(cs.map(\.caja.maxX).max()!)
        let minY = Double(cs.map(\.caja.minY).min()!), maxY = Double(cs.map(\.caja.maxY).max()!)
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        var out: [String: CGPoint] = [:]
        for c in cs {
            var dx = 0.0, dy = 0.0
            switch eje {
            case "izquierda": dx = minX - Double(c.caja.minX)
            case "derecha":   dx = maxX - Double(c.caja.maxX)
            case "centro-h":  dx = cx - Double(c.caja.midX)
            case "arriba":    dy = minY - Double(c.caja.minY)
            case "abajo":     dy = maxY - Double(c.caja.maxY)
            default:          dy = cy - Double(c.caja.midY)
            }
            out[c.id] = CGPoint(x: dx, y: dy)
        }
        return out
    }

    /// Distribuye dejando el MISMO HUECO, no el mismo paso entre centros: con
    /// tamaños distintos el ojo mide el AIRE, no la aritmetica.
    static func distribuir(_ els: [Elemento], _ ids: Set<String>, horizontal: Bool) -> [String: CGPoint]? {
        let cs = els.filter { ids.contains($0.id) }
        guard cs.count >= 3 else { return nil }
        let orden = cs.sorted { horizontal ? $0.caja.minX < $1.caja.minX : $0.caja.minY < $1.caja.minY }
        let inicio = Double(horizontal ? orden[0].caja.minX : orden[0].caja.minY)
        let fin = Double(horizontal ? orden.last!.caja.maxX : orden.last!.caja.maxY)
        let ocupado = orden.reduce(0.0) { $0 + Double(horizontal ? $1.caja.width : $1.caja.height) }
        let hueco = (fin - inicio - ocupado) / Double(orden.count - 1)
        var out: [String: CGPoint] = [:]
        var cursor = inicio
        for c in orden {
            let actual = Double(horizontal ? c.caja.minX : c.caja.minY)
            let d = cursor - actual
            out[c.id] = horizontal ? CGPoint(x: d, y: 0) : CGPoint(x: 0, y: d)
            cursor += Double(horizontal ? c.caja.width : c.caja.height) + hueco
        }
        return out
    }
}

/// Los cursores que el lienzo usa. Un enum propio para no repartir literales
/// de AppKit por la maquina de punteros.
enum NSCursorTipo { case normal, mano, cruz, texto, diagonalNWSE, diagonalNESW, vertical, horizontal }
