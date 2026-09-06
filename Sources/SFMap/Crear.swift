import CoreGraphics
import Foundation

/**
 * Las fabricas de elementos que pone LA MANO.
 *
 * Distinto del puente compilador→elementos: eso materializa semantica, esto
 * nace de un gesto. Lo que sale de aqui NO lleva `origin`, y por eso el
 * compilador ni lo mira: es de Daniel, punto.
 *
 * Todo elemento con texto nace con sus LINEAS YA CORTADAS. El pintor no vuelve
 * a decidir donde parte una frase — es la regla que cerro el desajuste
 * modelo↔pintor que dibujaba una linea donde el modelo decia dos.
 */
enum Crear {
    static let PAD = 16.0
    static let STICKY_W = 220.0
    static let STICKY_H = 160.0
    /// Separacion estandar entre dos piezas encadenadas. Cabe una flecha legible.
    static let SALTO = 90.0

    private static var contador = 0
    static func nuevoId(_ prefijo: String) -> String {
        contador += 1
        let t = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        return "\(prefijo)-\(t)-\(String(contador, radix: 36))"
    }

    static let ESTILO_NOTA = { var e = EstiloTexto(); e.peso = 500; e.tamano = 18; return e }()
    static let ESTILO_TEXTO = { var e = EstiloTexto(); e.peso = 500; e.tamano = 20; return e }()
    static let ESTILO_FIGURA = { var e = EstiloTexto(); e.peso = 700; e.tamano = 20; return e }()
    static let ESTILO_TABLA = { var e = EstiloTexto(); e.peso = 500; e.tamano = 15; return e }()
    static let ESTILO_CODIGO = { var e = EstiloTexto(); e.familia = "jetbrains-mono"; e.peso = 500; e.tamano = 14; return e }()

    private static func base(_ id: String, _ tipo: String, _ r: CGRect, _ z: Double) -> [String: Json] {
        let ahora = Date().timeIntervalSince1970 * 1000
        return [
            "id": .texto(id), "type": .texto(tipo),
            "x": .numero(r.minX), "y": .numero(r.minY),
            "width": .numero(r.width), "height": .numero(r.height),
            "rotation": .numero(0), "zIndex": .numero(z), "opacity": .numero(1),
            "locked": .bool(false), "version": .numero(1),
            "createdAt": .numero(ahora), "updatedAt": .numero(ahora),
        ]
    }

    /**
     * Texto centrado dentro de una figura, ajustado a su interior.
     *
     * `ajustar` devuelve `desborda` cuando ni al tamaño minimo cupo, y ese dato
     * NO se traga. El v3 recortaba en silencio con un clip y el contenido
     * desaparecia sin que nadie se enterara.
     */
    static func parteLigada(_ el: Elemento, _ texto: String, estilo: EstiloTexto = ESTILO_FIGURA) -> Json {
        let inner = max(20, el.ancho - PAD * 2)
        let m = ajustar(texto, estilo, maxAncho: inner, maxAlto: max(20, el.alto - PAD * 2), minTamano: 11)
        var est = estilo
        est.tamano = m.tamano
        return .objeto([
            "kind": .texto("title"), "text": .texto(texto),
            "lines": .lista(m.lineas.map { .texto($0.texto) }),
            "x": .numero(PAD), "y": .numero(max(PAD, (el.alto - m.alto) / 2)),
            "width": .numero(inner), "height": .numero(m.alto),
            "style": est.json,
        ])
    }

    /// Nota adhesiva. El texto se AJUSTA a la nota; una nota no crece sola.
    static func nota(_ w: CGPoint, texto: String = "", z: Double) -> Elemento {
        let r = CGRect(x: w.x - STICKY_W / 2, y: w.y - STICKY_H / 2, width: STICKY_W, height: STICKY_H)
        var o = base(nuevoId("sticky"), "shape", r, z)
        o["shape"] = .texto("rect")
        // El amarillo de siempre. El rol vive en el tema (`nota`), no como color
        // literal: una nota con el amarillo horneado dejaría de seguir al tema y
        // en oscuro seguiría siendo un fosforito.
        o["role"] = .texto("nota")
        var e = Elemento(.objeto(o))
        if !texto.isEmpty {
            let inner = STICKY_W - PAD * 2
            let m = ajustar(texto, ESTILO_NOTA, maxAncho: inner, maxAlto: STICKY_H - PAD * 2)
            var est = ESTILO_NOTA; est.tamano = m.tamano
            o["text"] = .lista([.objeto([
                "kind": .texto("title"), "text": .texto(texto),
                "lines": .lista(m.lineas.map { .texto($0.texto) }),
                "x": .numero(PAD), "y": .numero(PAD),
                "width": .numero(inner), "height": .numero(m.alto), "style": est.json,
            ])])
            e = Elemento(.objeto(o))
        } else {
            o["text"] = .lista([])
            e = Elemento(.objeto(o))
        }
        return e
    }

    /**
     * Bloque de texto libre. Al reves que la nota: la caja se ajusta AL TEXTO.
     *
     * `maxAncho` es la COLUMNA que la mano dibujo al arrastrar. La primera
     * version del lienzo web lo ignoraba y media siempre contra 520 px, asi que
     * una caja dibujada de 690 nacia de 125 y partia la frase en renglones de
     * dos palabras. En un lienzo, el ancho del arrastre ES la instruccion.
     */
    static func texto(_ w: CGPoint, texto: String = "", z: Double, maxAncho: Double? = nil) -> Elemento {
        let columna = max(40, maxAncho ?? 520)
        let m = cortar(texto, ESTILO_TEXTO, maxAncho: columna)
        // El ancho lo manda la COLUMNA pedida, no lo que midio el texto: si nace
        // con el ancho de la frase, el siguiente re-layout la vuelve a partir.
        let w0 = maxAncho != nil ? ceil(columna) : max(40, ceil(m.ancho))
        var o = base(nuevoId("text"), "text",
                     CGRect(x: w.x, y: w.y, width: w0, height: max(24, ceil(m.alto))), z)
        o["text"] = .texto(texto)
        o["lines"] = .lista(m.lineas.map { .texto($0.texto) })
        o["style"] = ESTILO_TEXTO.json
        // CENTRADO por defecto. Un bloque de texto suelto en un lienzo es casi
        // siempre un rótulo, y un rótulo se centra: alinearlo a la izquierda
        // obliga a corregirlo cada vez.
        o["align"] = .texto("center")
        return Elemento(.objeto(o))
    }

    /// Figura dibujada arrastrando, con texto opcional ajustado a su interior.
    static func figura(_ kind: String, _ r: CGRect, z: Double, texto: String = "", rol: String = "drawn") -> Elemento {
        var o = base(nuevoId(kind), "shape", r, z)
        o["shape"] = .texto(kind)
        o["role"] = .texto(rol)
        o["text"] = .lista([])
        var e = Elemento(.objeto(o))
        if !texto.isEmpty {
            o["text"] = .lista([parteLigada(e, texto)])
            e = Elemento(.objeto(o))
        }
        return e
    }

    /**
     * Seccion: un territorio con titulo que agrupa lo que cae dentro.
     *
     * Va al FONDO (z negativo) SIEMPRE. Una seccion pintada encima de su
     * contenido lo tapa, y una que compite en z se lleva los clics que iban a
     * las tarjetas de adentro.
     */
    static func seccion(_ r: CGRect, titulo: String = "Sección") -> Elemento {
        var o = base(nuevoId("section"), "frame",
                     CGRect(x: r.minX, y: r.minY, width: max(160, r.width), height: max(120, r.height)), -100)
        o["title"] = .texto(titulo)
        o["role"] = .texto("tray")
        return Elemento(.objeto(o))
    }

    /**
     * Tabla con anchos de columna MEDIDOS, no repartidos en partes iguales.
     *
     * Una columna de "Sí/No" no necesita el mismo ancho que una de
     * descripciones. Repartir parejo es lo que hace que las tablas generadas se
     * vean amateur — y en el v3 estos anchos se escribian en tres sitios y el
     * motor los IGNORABA por completo.
     */
    static func tabla(_ w: CGPoint, celdas: [[String]], z: Double) -> Elemento {
        let cols = celdas.map(\.count).max() ?? 1
        var anchos: [Double] = []
        for c in 0..<cols {
            var mx = 0.0
            for fila in celdas where c < fila.count { mx = max(mx, Medidor.medir(fila[c], ESTILO_TABLA)) }
            // Piso y techo: una columna vacia no colapsa, y una con un parrafo
            // no se come la tabla entera.
            anchos.append(min(320, max(80, ceil(mx) + 24)))
        }
        let ancho = anchos.reduce(0, +)
        let altoFila = 38.0
        let alto = Double(celdas.count) * altoFila
        var o = base(nuevoId("table"), "table",
                     CGRect(x: w.x - ancho / 2, y: w.y - alto / 2, width: ancho, height: alto), z)
        o["cells"] = .lista(celdas.map { .lista($0.map { .texto($0) }) })
        o["headerRow"] = .bool(true)
        o["colWidths"] = .lista(anchos.map { .numero($0) })
        o["rowHeight"] = .numero(altoFila)
        o["style"] = ESTILO_TABLA.json
        return Elemento(.objeto(o))
    }

    /**
     * Bloque de codigo. Su caja se dimensiona por la linea MAS LARGA: el codigo
     * no se re-envuelve, asi que la caja tiene que caber tal cual o la linea se
     * recorta y dice otra cosa.
     */
    static func codigo(_ w: CGPoint, codigo: String, lenguaje: String = "ts", z: Double) -> Elemento {
        let lineas = codigo.components(separatedBy: "\n")
        // En una fuente MONO el ancho por caracter es constante por definicion,
        // asi que contar caracteres SI mide bien aqui.
        let masLarga = Double(lineas.map(\.count).max() ?? 10)
        let ancho = min(680, max(240, masLarga * ESTILO_CODIGO.tamano * 0.6 + 28))
        let alto = max(70, Double(lineas.count) * ESTILO_CODIGO.tamano * 1.5 + 28)
        var o = base(nuevoId("code"), "code",
                     CGRect(x: w.x - ancho / 2, y: w.y - alto / 2, width: ancho, height: alto), z)
        o["code"] = .texto(codigo)
        o["language"] = .texto(lenguaje)
        o["style"] = ESTILO_CODIGO.json
        return Elemento(.objeto(o))
    }

    static func embed(_ w: CGPoint, url: String, z: Double) -> Elemento {
        var o = base(nuevoId("embed"), "embed", CGRect(x: w.x - 320, y: w.y - 200, width: 640, height: 400), z)
        o["url"] = .texto(url)
        o["interactive"] = .bool(false)
        return Elemento(.objeto(o))
    }

    private static let IMG_MAX = 520.0

    /// Imagen. Su caja nace con la PROPORCION real del archivo, acotada a un
    /// maximo: sin eso una captura de 3400 px entra ocupando media pantalla del
    /// mundo y hay que redimensionarla a mano cada vez.
    static func imagen(_ w: CGPoint, src: String, natural: CGSize, z: Double, alt: String? = nil) -> Elemento {
        let escala = min(1, IMG_MAX / max(natural.width, natural.height))
        let ww = (natural.width * escala).rounded(), hh = (natural.height * escala).rounded()
        var o = base(nuevoId("img"), "image", CGRect(x: w.x - ww / 2, y: w.y - hh / 2, width: ww, height: hh), z)
        o["src"] = .texto(src)
        o["naturalWidth"] = .numero(natural.width)
        o["naturalHeight"] = .numero(natural.height)
        if let a = alt { o["alt"] = .texto(a) }
        return Elemento(.objeto(o))
    }

    /// Conector. Nace SIN ruta: la calcula el router contra el estado actual.
    static func conector(_ desde: String, _ hasta: String, z: Double = -1,
                         puertoDesde: String? = nil, puertoHasta: String? = nil) -> Elemento {
        var o = base(nuevoId("conn"), "connector", .zero, z)
        o["fromId"] = .texto(desde)
        o["toId"] = .texto(hasta)
        o["points"] = .lista([])
        o["arrowEnd"] = .bool(true)
        if let p = puertoDesde { o["fromPort"] = .texto(p) }
        if let p = puertoHasta { o["toPort"] = .texto(p) }
        return Elemento(.objeto(o))
    }

    /**
     * Caja centrada donde soltaste, del tamaño del origen.
     *
     * IMANTADA a la fila y la columna del origen: si sueltas casi alineado,
     * queda EXACTAMENTE alineado. Es lo que hace que una cadena hecha a pulso
     * salga recta sin que nadie la acomode despues, y la tolerancia se mide en
     * px de MUNDO, asi que no cambia con el zoom.
     */
    static func cajaFantasma(_ origen: CGRect, _ punto: CGPoint) -> CGRect {
        let w = max(80, origen.width), h = max(56, origen.height)
        let iman = 28.0
        let cx = abs(punto.x - origen.midX) < iman ? origen.midX : punto.x
        let cy = abs(punto.y - origen.midY) < iman ? origen.midY : punto.y
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /**
     * Caja a un salto estandar en la direccion de un puerto. Es el gesto de
     * CLIC (sin arrastrar): sale alineada por construccion, que es justo lo que
     * se quiere cuando no apuntaste a ningun sitio.
     */
    static func cajaEnDireccion(_ origen: CGRect, _ puerto: String?) -> CGRect {
        let w = max(80, origen.width), h = max(56, origen.height)
        // Sin puerto (el gesto vino de la herramienta de conector, no de un
        // lado) el default es a la derecha: es la direccion en la que se lee.
        switch puerto ?? "e" {
        case "n": return CGRect(x: origen.midX - w / 2, y: origen.minY - SALTO - h, width: w, height: h)
        case "s": return CGRect(x: origen.midX - w / 2, y: origen.maxY + SALTO, width: w, height: h)
        case "w": return CGRect(x: origen.minX - SALTO - w, y: origen.midY - h / 2, width: w, height: h)
        default:  return CGRect(x: origen.maxX + SALTO, y: origen.midY - h / 2, width: w, height: h)
        }
    }

    /**
     * Que elementos caen DENTRO de una seccion, por contencion geometrica.
     *
     * Se CALCULA, no se mantiene: una lista de hijos que hay que sincronizar
     * con la realidad se desincroniza siempre — es lo que le paso al `frame`
     * del v3, que decia tener hijos que no se movian con el.
     *
     * Por el CENTRO, no por contencion total: exigir que quepa entero haria que
     * una tarjeta que asoma un pixel dejara de pertenecer a su seccion.
     */
    static func hijosDeSeccion(_ seccion: Elemento, _ els: [Elemento]) -> Set<String> {
        Set(els.filter { e in
            guard e.id != seccion.id, e.tipo != "frame" else { return false }
            return seccion.caja.contains(CGPoint(x: e.caja.midX, y: e.caja.midY))
        }.map(\.id))
    }
}
