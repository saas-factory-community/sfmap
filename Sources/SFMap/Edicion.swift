import CoreGraphics
import Foundation

/**
 * LA PUERTA DE MUTACION. Una sola, y por eso el contrato no se puede olvidar.
 *
 * ⚠️ POR QUE EXISTE. sfmap movia elementos SIN fijarlos. Nada fallaba: se
 * movian, se guardaban, todo verde — y el siguiente `compileRegion` los
 * devolvia a su sitio borrando la decision de la mano, en silencio.
 *
 * El arreglo obvio era añadir el fijado dentro de `mover`. Es el arreglo
 * equivocado: en cuanto existan quince mutaciones (redimensionar, girar,
 * cambiar el rol, escribir texto, acomodar…), la decimosexta se olvidara de
 * hacerlo. Con `tocar` como unica via, la regla se cumple por construccion:
 * quien escriba una mutacion nueva no PUEDE saltarsela sin escribir en `crudo`
 * a mano, que es visible en una revision.
 *
 * Las tres cosas que hace, siempre:
 *   1. escribe conservando TODO lo que sfmap no conoce (`Json.con`),
 *   2. sella `updatedAt` — el arbitro de la fusion entre dispositivos,
 *   3. FIJA lo compilado (`origin.pinned`).
 */
extension Elemento {

    mutating func tocar(_ patch: [String: Json?]) {
        var p = patch
        p["updatedAt"] = .numero(Date().timeIntervalSince1970 * 1000)
        if let o = crudo["origin"]?.obj, (o["pinned"]?.b ?? false) == false {
            var nuevo = o
            nuevo["pinned"] = .bool(true)
            p["origin"] = .objeto(nuevo)
        }
        crudo = crudo.con(p)
    }

    /// Escritura que NO es de la mano: el ruteo de un conector, la fusion desde
    /// la nube. No fija, porque fijar significa "Daniel decidio esto".
    mutating func tocarSinFijar(_ patch: [String: Json?]) {
        var p = patch
        p["updatedAt"] = .numero(Date().timeIntervalSince1970 * 1000)
        crudo = crudo.con(p)
    }

    // ── geometria ───────────────────────────────────────────────────────────

    mutating func ponerCaja(_ r: CGRect) {
        if tipo == "ink" {
            // La tinta escala sus PUNTOS, no su caja: la caja de un trazo se
            // DERIVA de los puntos, asi que cambiarla sola no haria nada.
            let b = caja
            guard b.width > 0, b.height > 0 else { return }
            let sx = r.width / b.width, sy = r.height / b.height
            let pts = crudo["points"]?.arr ?? []
            tocar([
                "x": .numero(x + (r.minX - b.minX)), "y": .numero(y + (r.minY - b.minY)),
                "points": .lista(pts.map { p in
                    p.con(["x": .numero((p["x"]?.num ?? 0) * sx), "y": .numero((p["y"]?.num ?? 0) * sy)])
                }),
                "size": .numero(grosorTinta * min(sx, sy)),
            ])
            return
        }
        tocar(["x": .numero(r.minX), "y": .numero(r.minY),
               "width": .numero(max(8, r.width)), "height": .numero(max(8, r.height))])
    }

    mutating func ponerGiro(_ rad: Double) { tocar(["rotation": .numero(rad)]) }

    /// La ruta de un conector NO es una decision de la mano: la calcula el
    /// router en cada movimiento. Por eso va sin fijar.
    mutating func ponerRuta(_ pts: [CGPoint]) {
        tocarSinFijar(["points": .lista(pts.map { .objeto(["x": .numero($0.x), "y": .numero($0.y)]) })])
    }

    // ── atributos ───────────────────────────────────────────────────────────

    /// Un color elegido a mano, compuesto CAMPO POR CAMPO.
    ///
    /// Elegir el relleno no debe borrar el contorno que ya se habia elegido. Un
    /// override que reemplaza el objeto entero convierte cada ajuste en un
    /// reinicio silencioso.
    ///
    /// Un valor `nil` explicito significa "devuelvelo al ROL": se BORRA la
    /// llave. Dejarla presente la mantendria viva en el JSON y la proxima
    /// mezcla la reviviria.
    mutating func ponerColor(_ campos: [String: String?]) {
        var mezcla = crudo["color"]?.obj ?? [:]
        for (k, v) in campos {
            if let v { mezcla[k] = .texto(v) } else { mezcla.removeValue(forKey: k) }
        }
        let quedan = mezcla.keys.filter { $0 != "explicit" }
        if quedan.isEmpty { tocar(["color": nil]) }
        else {
            mezcla["explicit"] = .bool(true)
            tocar(["color": .objeto(mezcla)])
        }
    }

    /// El trazo, con la misma composicion campo por campo que el color.
    mutating func ponerTrazo(estilo: String? = nil, grosor: Double? = nil, radio: Double? = nil) {
        var mezcla = crudo["trazo"]?.obj ?? [:]
        if let e = estilo { mezcla["style"] = .texto(e) }
        if let g = grosor { mezcla["width"] = .numero(g) }
        if let r = radio { mezcla["radius"] = .numero(r) }
        mezcla["explicit"] = .bool(true)
        tocar(["trazo": .objeto(mezcla)])
    }

    mutating func poner(_ clave: String, _ v: Json?) { tocar([clave: v]) }

    // ── texto ───────────────────────────────────────────────────────────────

    /// El texto que el editor MUESTRA de este elemento.
    var textoEditable: String {
        switch tipo {
        case "text":  return textoLibre ?? ""
        case "shape": return textoLigado?.first?.texto ?? ""
        case "frame": return titulo ?? ""
        // Un bloque de CÓDIGO guarda su texto en `code`. Sin esta línea, el
        // editor lo abría en blanco y al confirmar lo dejaba vacío.
        case "code":  return crudo["code"]?.s ?? ""
        default:      return ""
        }
    }

    /**
     * ESCRIBIR TEXTO. Un solo camino.
     *
     * ⚠️ EXISTE POR UN BUG MEDIDO. La logica vivia suelta dentro del editor y
     * decia `partes.isEmpty ? [] : [primera con el texto nuevo]`. Dos perdidas
     * silenciosas en una linea: si la figura NO tenia parte de texto, lo escrito
     * se DESCARTABA (crear un rectangulo, escribir y dar Enter dejaba la figura
     * vacia, sin error); y si tenia VARIAS —una tarjeta compilada con titulo,
     * renglones, pie y etiquetas— se quedaba SOLO con la primera, asi que
     * corregir el titulo borraba el resto.
     */
    mutating func escribir(_ texto: String) {
        switch tipo {
        case "frame":
            tocar(["title": .texto(texto)])
        case "text":
            let est = estilo
            let m = cortar(texto, est, maxAncho: max(40, ancho))
            tocar(["text": .texto(texto),
                   "lines": .lista(m.lineas.map { .texto($0.texto) }),
                   "height": .numero(ceil(m.alto))])
        case "shape":
            var partes = crudo["text"]?.arr ?? []
            if partes.isEmpty {
                if texto.isEmpty { return }
                partes = [Crear.parteLigada(self, texto)]
            } else {
                // La PRIMERA parte es el titulo: la que el editor muestra y la
                // mano corrige. Las demas se conservan intactas.
                partes[0] = partes[0].con("text", .texto(texto))
            }
            tocar(["text": .lista(partes)])
            remaquetar()
        /*
         * CÓDIGO. El alto se DERIVA de las líneas, con la misma cuenta que usa
         * el generador (36 + n × tamaño × 1.5) y que el pintor respeta al
         * componer. Si el alto no siguiera al texto, añadir una línea la
         * escondería debajo del borde: el bloque recorta a su caja.
         */
        case "code":
            let n = max(1, texto.components(separatedBy: "\n").count)
            tocar(["code": .texto(texto),
                   "height": .numero(36 + Double(n) * estilo.tamano * 1.5)])
        default: break
        }
    }

    /**
     * Re-ajusta el texto ligado tras un cambio de tamaño, fuente o contenido.
     *
     * ⚠️ LA VERSION ANTERIOR DEL LIENZO WEB DESTRUIA DATOS: tomaba la PRIMERA
     * parte y tiraba las demas. Una tarjeta compilada tiene titulo, renglones,
     * pie y etiquetas; redimensionarla la dejaba con el titulo y nada mas.
     *
     * Aqui cada parte se re-maqueta CONSERVANDO su clase, y la pila se recompone
     * en el orden que la construyo el compositor.
     */
    mutating func remaquetar() {
        if tipo == "text" {
            let m = cortar(textoLibre ?? "", estilo, maxAncho: max(40, ancho))
            tocar(["lines": .lista(m.lineas.map { .texto($0.texto) }), "height": .numero(ceil(m.alto))])
            return
        }
        guard tipo == "shape", let partes = crudo["text"]?.arr, !partes.isEmpty else { return }

        // Caso simple: figura de la mano con un solo rotulo. Se centra.
        if partes.count == 1, (partes[0]["kind"]?.s ?? "title") == "title" {
            let est = EstiloTexto(partes[0]["style"])
            var nueva = Crear.parteLigada(self, partes[0]["text"]?.s ?? "", estilo: est)
            // Se respeta el estilo que la mano eligio: el ajuste decide el
            // TAMAÑO que cabe, jamas la familia ni el peso.
            var e2 = est
            e2.tamano = EstiloTexto(nueva["style"]).tamano
            nueva = nueva.con("style", e2.json)
            tocar(["text": .lista([nueva])])
            return
        }

        let inner = max(20, ancho - Crear.PAD * 2)
        var out: [Json] = []
        var y = Crear.PAD

        for p in partes where ["title", "item"].contains(p["kind"]?.s ?? "") {
            let est = EstiloTexto(p["style"])
            let m = cortar(p["text"]?.s ?? "", est, maxAncho: inner)
            out.append(p.con(["x": .numero(Crear.PAD), "y": .numero(y),
                              "width": .numero(inner), "height": .numero(ceil(m.alto)),
                              "lines": .lista(m.lineas.map { .texto($0.texto) })]))
            y += ceil(m.alto) + ((p["kind"]?.s ?? "") == "title" ? 8 : 4)
        }
        for p in partes where (p["kind"]?.s ?? "") == "chip" {
            // La etiqueta no envuelve: es corta por definicion. Se ancla abajo a
            // la derecha, que es donde el estandar visual la pone.
            let est = EstiloTexto(p["style"])
            let t = p["text"]?.s ?? ""
            let w = ceil(Medidor.medir(t, est)) + 16
            let h = ceil(Medidor.vertical(est).altoNatural) + 4
            out.append(p.con(["x": .numero(max(Crear.PAD, ancho - Crear.PAD - w)),
                              "y": .numero(alto - Crear.PAD - h),
                              "width": .numero(w), "height": .numero(h),
                              "lines": .lista([.texto(t)])]))
        }
        for p in partes where (p["kind"]?.s ?? "") == "caption" {
            // El pie envuelve al ancho de SU tarjeta, con el mismo piso que usa
            // el compilador: mas angosto produce una palabra por renglon.
            let est = EstiloTexto(p["style"])
            let anchoPie = max(220, ancho)
            let m = cortar(p["text"]?.s ?? "", est, maxAncho: anchoPie)
            out.append(p.con(["x": .numero(0), "y": .numero(alto + 10),
                              "width": .numero(anchoPie), "height": .numero(ceil(m.alto)),
                              "lines": .lista(m.lineas.map { .texto($0.texto) })]))
        }
        tocar(["text": .lista(out)])
    }

    /// El mismo elemento SIN su texto, para pintarlo mientras el editor está
    /// encima. No toca el documento: es una copia de pintado.
    var sinTexto: Elemento {
        var e = self
        switch tipo {
        case "shape": e.crudo = e.crudo.con("text", .lista([]))
        case "frame": e.crudo = e.crudo.con("title", .texto(""))
        default: break
        }
        return e
    }

    // ── tipografia ──────────────────────────────────────────────────────────

    /// Los estilos que hay DENTRO de un elemento, para poder leer el estado.
    var estilos: [EstiloTexto] {
        switch tipo {
        case "text", "table", "code": return [estilo]
        case "shape": return (crudo["text"]?.arr ?? []).map { EstiloTexto($0["style"]) }
        default: return []
        }
    }

    var tieneTexto: Bool {
        if ["text", "table", "code"].contains(tipo) { return true }
        return tipo == "shape" && !(crudo["text"]?.arr ?? []).isEmpty
    }

    /**
     * Aplica tipografia. EL TAMAÑO ESCALA, no aplana.
     *
     * Un titulo de 24 y un pie de 16 tienen esa diferencia por diseño;
     * igualarlos a los dos en 20 destruye la jerarquia que el compilador
     * construyo. El factor sale del renglon MAS GRANDE, que es el que el ojo
     * lee como "el tamaño" del elemento.
     */
    mutating func aplicarTipografia(_ p: Tipografia) {
        let ests = estilos
        guard !ests.isEmpty || p.alineacion != nil else { return }
        let mayor = ests.map(\.tamano).max() ?? 0
        let factor = (p.tamano != nil && mayor > 0) ? p.tamano! / mayor : 1

        func aplicado(_ s: EstiloTexto) -> EstiloTexto {
            var o = s
            if let v = p.familia { o.familia = v }
            if let v = p.peso { o.peso = v }
            if let v = p.cursiva { o.cursiva = v }
            if let v = p.subrayado { o.subrayado = v }
            if let v = p.tachado { o.tachado = v }
            if let v = p.interlineado { o.interlineado = v }
            if let v = p.espaciado { o.espaciado = v }
            // Piso de 6 px: mas chico que eso no es texto, es ruido.
            if factor != 1 { o.tamano = max(6, (s.tamano * factor * 10).rounded() / 10) }
            return o
        }

        switch tipo {
        case "text":
            var patch: [String: Json?] = ["style": aplicado(estilo).json]
            if let a = p.alineacion { patch["align"] = .texto(a) }
            tocar(patch)
            remaquetar()
        case "table", "code":
            tocar(["style": aplicado(estilo).json])
        case "shape":
            var patch: [String: Json?] = [:]
            // La alineacion de una FIGURA vive en el elemento, no en cada parte:
            // es una decision del contenedor. Alinear el titulo a la izquierda y
            // el pie al centro seria un accidente, no una intencion.
            if let a = p.alineacion { patch["textAlign"] = .texto(a) }
            let partes = crudo["text"]?.arr ?? []
            if !partes.isEmpty {
                patch["text"] = .lista(partes.map { $0.con("style", aplicado(EstiloTexto($0["style"])).json) })
            }
            tocar(patch)
            remaquetar()
        case "frame":
            if let a = p.alineacion { tocar(["textAlign": .texto(a)]) }
        default: break
        }
    }
}

/// El parche de tipografia. Cada campo ausente = no se toca.
struct Tipografia {
    var familia: String?
    var peso: Double?
    var cursiva: Bool?
    var subrayado: Bool?
    var tachado: Bool?
    /// Tamaño OBJETIVO del renglon mas grande. El resto escala con el.
    var tamano: Double?
    var interlineado: Double?
    var espaciado: Double?
    var alineacion: String?
}

/// Las familias que la interfaz ofrece.
let FAMILIAS: [(id: String, nombre: String)] = [
    ("montserrat", "Montserrat"), ("roboto-slab", "Roboto Slab"),
    ("caveat", "Caveat"), ("jetbrains-mono", "JetBrains Mono"),
    ("cormorant", "Cormorant Garamond"),
]

/// Rango de peso REAL de cada archivo. Pedir 900 a Caveat da 700 y confunde.
let PESOS: [String: [Double]] = [
    "montserrat": [300, 400, 500, 600, 700, 800, 900],
    "roboto-slab": [300, 400, 500, 600, 700, 800, 900],
    "caveat": [400, 500, 600, 700],
    "jetbrains-mono": [300, 400, 500, 600, 700, 800],
    "cormorant": [300, 400, 500, 600, 700],
]
