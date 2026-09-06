import AppKit
import CoreText

/// El estilo de un texto. Espejo de `text/types.ts`.
///
/// Vive suelto y no dentro de `Elemento` porque lo usan tres capas: el modelo
/// (lo guarda), el medidor (lo mide) y el pintor (lo dibuja). Un tipo por capa
/// seria el camino directo a que midan una cosa y pinten otra.
struct EstiloTexto: Equatable {
    var familia: String = "montserrat"
    var peso: Double = 500
    var tamano: Double = 16
    var interlineado: Double?
    var espaciado: Double?
    var cursiva = false
    var subrayado = false
    var tachado = false

    init() {}

    init(_ j: Json?) {
        familia = j?["family"]?.s ?? "montserrat"
        peso = j?["weight"]?.num ?? 500
        tamano = j?["size"]?.num ?? 16
        interlineado = j?["lineHeight"]?.num
        espaciado = j?["letterSpacing"]?.num
        cursiva = j?["italic"]?.b ?? false
        subrayado = j?["underline"]?.b ?? false
        tachado = j?["strike"]?.b ?? false
    }

    /// De vuelta a JSON, conservando el convenio de AUSENCIA.
    ///
    /// Un campo opcional que no se eligio NO se escribe como `false` o `0`: se
    /// omite. La diferencia importa porque el lienzo web distingue "nadie lo
    /// eligio" (manda el default) de "lo eligieron asi" — escribir `italic:
    /// false` en cada guardado convertiria una ausencia en una decision.
    var json: Json {
        var o: [String: Json] = [
            "family": .texto(familia), "weight": .numero(peso), "size": .numero(tamano),
        ]
        if let v = interlineado { o["lineHeight"] = .numero(v) }
        if let v = espaciado { o["letterSpacing"] = .numero(v) }
        if cursiva { o["italic"] = .bool(true) }
        if subrayado { o["underline"] = .bool(true) }
        if tachado { o["strike"] = .bool(true) }
        return .objeto(o)
    }
}

/// Una linea ya cortada, con su ancho medido.
struct LineaCortada { var texto: String; var ancho: Double }

struct Maqueta {
    var lineas: [LineaCortada]
    var ancho: Double
    var alto: Double
    var altoLinea: Double
    /// true si alguna palabra sola no cupo y hubo que partirla.
    var partioPalabra: Bool
    /// El tamaño con el que finalmente cupo. Puede ser menor al pedido.
    var tamano: Double = 0
    /// true si ni al tamaño minimo cupo. NO se traga: el llamador se entera.
    var desborda = false
}

/**
 * EL MEDIDOR. Un archivo de fuente, una medida.
 *
 * El v3 media con `anchoDeCaracter = tamaño * 0.62` porque `document` no existe
 * en el servidor. Medido contra el navegador real: ese heuristico se queda
 * corto un 8.8% en mayusculas pesadas, y por eso partia "LEVY" en dos.
 *
 * ⚠️ EL KERNING NO ES UN REFINAMIENTO. Sumar el avance de cada glifo por
 * separado da 164.44 px donde el renglon real mide 163.15: solo el par "AV"
 * vale −2.34. `CTLineGetTypographicBounds` mide el RENGLON COMPLETO, que es la
 * unica forma correcta.
 */
enum Medidor {
    private static var cacheAncho: [String: Double] = [:]
    private static var cacheVert: [String: (Double, Double, Double, Double)] = [:]

    static func medir(_ texto: String, _ e: EstiloTexto) -> Double {
        if texto.isEmpty { return 0 }
        let llave = "\(texto)|\(e.familia)|\(e.peso)|\(e.tamano)|\(e.espaciado ?? 0)|\(e.cursiva)"
        if let v = cacheAncho[llave] { return v }
        let f = Fuentes.fuente(familia: e.familia, peso: e.peso, tamano: e.tamano, cursiva: e.cursiva)
        var attrs: [NSAttributedString.Key: Any] = [.font: f]
        if let k = e.espaciado, k != 0 { attrs[.kern] = k }
        let linea = CTLineCreateWithAttributedString(NSAttributedString(string: texto, attributes: attrs))
        let w = Double(CTLineGetTypographicBounds(linea, nil, nil, nil))
        cacheAncho[llave] = w
        return w
    }

    /// Metricas verticales normalizadas al tamaño pedido.
    static func vertical(_ e: EstiloTexto) -> (ascenso: Double, descenso: Double, hueco: Double, altoNatural: Double) {
        let llave = "\(e.familia)|\(e.peso)|\(e.tamano)|\(e.cursiva)"
        if let v = cacheVert[llave] { return (v.0, v.1, v.2, v.3) }
        let f = Fuentes.fuente(familia: e.familia, peso: e.peso, tamano: e.tamano, cursiva: e.cursiva)
        let a = Double(CTFontGetAscent(f)), d = Double(CTFontGetDescent(f)), l = Double(CTFontGetLeading(f))
        let natural = a + d + l
        cacheVert[llave] = (a, d, l, natural)
        return (a, d, l, natural)
    }

    static func altoLinea(_ e: EstiloTexto) -> Double {
        if let m = e.interlineado { return e.tamano * m }
        return vertical(e).altoNatural
    }
}

/// Donde se puede cortar sin partir una palabra.
private let SEPARADORES: Set<Character> = [" ", "\t", "-", "—", "–", "/"]

private func trocear(_ texto: String) -> [String] {
    var out: [String] = []
    var actual = ""
    var enEspacio: Bool? = nil
    for c in texto {
        let esSep = SEPARADORES.contains(c)
        if esSep {
            // Un separador que NO es espacio (guion, barra) se queda pegado a
            // lo que lo precede: cortar "auto-" y dejar el guion solo al inicio
            // del renglon siguiente es exactamente lo que no hace ningun libro.
            if c == " " || c == "\t" {
                if enEspacio == true { actual.append(c) }
                else { if !actual.isEmpty { out.append(actual) }; actual = String(c) }
                enEspacio = true
            } else {
                actual.append(c)
                out.append(actual); actual = ""; enEspacio = nil
            }
        } else {
            if enEspacio == true { out.append(actual); actual = "" }
            actual.append(c)
            enEspacio = false
        }
    }
    if !actual.isEmpty { out.append(actual) }
    return out
}

private func esEspacio(_ s: String) -> Bool {
    !s.isEmpty && s.allSatisfy { $0 == " " || $0 == "\t" }
}

/// Parte UNA palabra que no cabe, por busqueda binaria sobre el medidor.
/// Solo se usa cuando no hay donde cortar: una URL, un identificador largo.
private func partirPalabra(_ palabra: String, _ e: EstiloTexto, _ maxAncho: Double) -> (String, String) {
    let cs = Array(palabra)
    var lo = 1, hi = cs.count, mejor = 1
    while lo <= hi {
        let mid = (lo + hi) / 2
        if Medidor.medir(String(cs[0..<mid]), e) <= maxAncho { mejor = mid; lo = mid + 1 }
        else { hi = mid - 1 }
    }
    return (String(cs[0..<mejor]), String(cs[mejor...]))
}

/// Corta el texto a lineas que caben en `maxAncho`. Respeta los saltos escritos.
func cortar(_ texto: String, _ e: EstiloTexto, maxAncho: Double) -> Maqueta {
    let alto = Medidor.altoLinea(e)
    var lineas: [LineaCortada] = []
    var partio = false

    for parrafo in texto.components(separatedBy: "\n") {
        if parrafo.isEmpty { lineas.append(LineaCortada(texto: "", ancho: 0)); continue }
        var actual = ""
        func volcar() {
            guard !actual.isEmpty else { return }
            lineas.append(LineaCortada(texto: actual, ancho: Medidor.medir(actual, e)))
            actual = ""
        }
        for var pedazo in trocear(parrafo) {
            // Un espacio al inicio de renglon no cuenta, igual que en CSS.
            if actual.isEmpty && esEspacio(pedazo) { continue }
            if Medidor.medir(actual + pedazo, e) <= maxAncho { actual += pedazo; continue }
            volcar()
            if esEspacio(pedazo) { continue }
            while Medidor.medir(pedazo, e) > maxAncho {
                let (cabeza, resto) = partirPalabra(pedazo, e, maxAncho)
                if cabeza.isEmpty { break }   // maxAncho menor que un glifo: se rinde
                partio = true
                lineas.append(LineaCortada(texto: cabeza, ancho: Medidor.medir(cabeza, e)))
                pedazo = resto
            }
            actual = pedazo
        }
        volcar()
    }
    let ancho = lineas.reduce(0.0) { max($0, $1.ancho) }
    return Maqueta(lineas: lineas, ancho: ancho, alto: Double(lineas.count) * alto,
                   altoLinea: alto, partioPalabra: partio, tamano: e.tamano)
}

/**
 * Ajusta el texto a una caja: baja el tamaño hasta que cabe.
 *
 * Devuelve `desborda` en vez de recortar en silencio. Esa es la diferencia con
 * el v3, que recibia un `autoShrink` y NUNCA lo leia: el texto de una figura se
 * recortaba con un clip y el de una nota se desbordaba por fuera. Dos fallas
 * distintas, y ninguna de las dos era ajustar.
 */
func ajustar(_ texto: String, _ e: EstiloTexto, maxAncho: Double, maxAlto: Double,
             minTamano: Double = 8, paso: Double = 1) -> Maqueta {
    var tam = e.tamano
    var est = e
    var m = cortar(texto, est, maxAncho: maxAncho)
    while m.alto > maxAlto && tam - paso >= minTamano {
        tam -= paso
        est.tamano = tam
        m = cortar(texto, est, maxAncho: maxAncho)
    }
    m.tamano = tam
    m.desborda = m.alto > maxAlto
    return m
}
