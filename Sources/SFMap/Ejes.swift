import Foundation

/**
 * LOS EJES DE UNA GRÁFICA — la aritmética, aparte del pintor.
 *
 * Daniel, 25 ago: *"asegúrate de darme un eje X y un eje Y, me refiero a
 * MÉTRICAS… para el filtro de 7 días, en el eje X divide por 7 segmentos, y en
 * el eje Y depende de cada diagrama… si este va a ser el negocio en el que voy
 * a estar todo el día, quiero que quede bien sólido."*
 *
 * ════════════════════════════════════════════════════════════════════════════
 * POR QUÉ ESTO ES UN ARCHIVO PROPIO Y NO CUATRO LÍNEAS EN EL PINTOR
 * ════════════════════════════════════════════════════════════════════════════
 *
 * Porque es donde una gráfica MIENTE. Una curva sin escala se lee como uno
 * quiera —la misma serie parece un desplome o un temblor según cuánto zoom
 * tenga el eje Y— y los errores de escala no se ven: la gráfica sale bonita y
 * dice otra cosa. Separado del pintor se puede PROBAR con números, que es la
 * única forma de saber que un eje dice la verdad.
 */
enum Ejes {

    // ════════════════════════════════════════════════════════════════════════
    // MARK: - El eje Y: números REDONDOS, no los que salgan
    // ════════════════════════════════════════════════════════════════════════

    struct EscalaY {
        var lo: Double          // el suelo de la gráfica (ya redondeado)
        var hi: Double          // el techo
        var paso: Double        // distancia entre marcas
        var marcas: [Double]    // los valores rotulados, de abajo a arriba

        func fraccion(_ v: Double) -> Double {
            hi - lo < 1e-9 ? 0.5 : (v - lo) / (hi - lo)
        }
    }

    /**
     * La escala "bonita" de Wilkinson, reducida a lo que hace falta: se busca
     * un paso de la forma 1·10ⁿ, 2·10ⁿ o 5·10ⁿ que dé aproximadamente
     * `marcasDeseadas` divisiones cubriendo el rango.
     *
     * ⚠️ **NO se fuerza el cero.** Estas series son rangos estrechos (el MRR se
     * mueve entre 8.200 y 9.400) y anclar en cero aplastaría contra el borde
     * inferior justo lo que se quiere mirar. Un eje recortado SIN rótulos sí
     * es un engaño; con sus números escritos es un zoom declarado, que es lo
     * que hace cualquier terminal financiera.
     *
     * ⚠️ Y **serie plana ≠ rango cero**. Si todos los valores son iguales se
     * inventa un margen alrededor: sin eso la división por rango explota y la
     * línea se pinta pegada a un borde, que se lee como un mínimo histórico.
     */
    static func escalaY(_ vs: [Double], marcasDeseadas: Int = 4) -> EscalaY {
        guard let mn = vs.min(), let mx = vs.max() else {
            return EscalaY(lo: 0, hi: 1, paso: 1, marcas: [0, 1])
        }
        var lo = mn, hi = mx
        if hi - lo < 1e-9 {
            // Serie plana: un margen simétrico y honesto alrededor del valor.
            let m = max(abs(lo) * 0.1, 1)
            lo -= m; hi += m
        }
        let bruto = (hi - lo) / Double(max(1, marcasDeseadas))
        let magnitud = pow(10, floor(log10(bruto)))
        let norm = bruto / magnitud
        let paso = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10) * magnitud
        let piso = (lo / paso).rounded(.down) * paso
        let techo = (hi / paso).rounded(.up) * paso
        var marcas: [Double] = []
        var v = piso
        while v <= techo + paso * 0.001 && marcas.count < 12 {
            // −0.0 existe en coma flotante y se pinta como "-0". Se normaliza.
            marcas.append(abs(v) < 1e-9 ? 0 : v)
            v += paso
        }
        return EscalaY(lo: piso, hi: techo, paso: paso, marcas: marcas)
    }

    /// El rótulo de una marca, con los decimales que el PASO exige y ni uno más.
    /// Con paso 0.5 hace falta un decimal; con paso 20 sobra: "8,220" y no
    /// "8,220.0". Y a partir de 10.000 se abrevia, o cuatro rótulos de seis
    /// dígitos se comen el ancho de la gráfica.
    static func rotuloY(_ v: Double, paso: Double, moneda: Bool) -> String {
        let signo = v < 0 ? "−" : ""
        let a = abs(v)
        if a >= 10_000 {
            let k = a / 1000
            let s = k >= 100 ? String(format: "%.0f", k) : String(format: "%.1f", k)
            return signo + (moneda ? "$" : "") + s + "k"
        }
        let dec = paso < 0.1 ? 2 : (paso < 1 ? 1 : 0)
        let cuerpo: String
        if dec == 0 {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 0
            cuerpo = f.string(from: NSNumber(value: a)) ?? String(format: "%.0f", a)
        } else {
            cuerpo = String(format: "%.\(dec)f", a)
        }
        return signo + (moneda ? "$" : "") + cuerpo
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: - El eje X: los días, segmentados
    // ════════════════════════════════════════════════════════════════════════

    struct MarcaX {
        var indice: Int         // qué punto de la serie
        var rotulo: String
    }

    /// Divide el eje X en segmentos LEGIBLES para la ventana que se mira.
    ///
    /// Daniel pidió *"para el filtro de 7 días, divide por 7"*, y esa es la
    /// regla general llevada a las otras dos ventanas: **una marca por unidad
    /// natural del periodo**. 7 días → un día cada uno. 30 → una por semana.
    /// 90 → una por mes. Poner 90 rótulos en 700 px sería una mancha negra, y
    /// poner solo los extremos deja de ser un eje.
    ///
    /// Y hay un tope por ANCHO: si no caben, se ralean saltando de dos en dos.
    /// Un eje cuyos rótulos se pisan miente sobre dónde está cada punto.
    static func marcasX(fechas: [String], dias: Int, anchoDisponible: Double,
                        anchoRotulo: Double = 46) -> [MarcaX] {
        guard fechas.count >= 2 else { return [] }
        let caben = max(2, Int(anchoDisponible / anchoRotulo))
        let ideal: Int = switch dias {
            case ...7:  fechas.count          // una por día: lo que pidió
            case ...31: 5                     // ~una por semana
            default:    4                     // ~una por mes
        }
        let quiero = min(ideal, caben)
        guard quiero >= 2 else { return [] }
        // Se reparten los índices de forma pareja incluyendo SIEMPRE los dos
        // extremos: son los que anclan la lectura ("de cuándo a cuándo").
        var idx: [Int] = []
        for k in 0..<quiero {
            let i = Int((Double(k) / Double(quiero - 1) * Double(fechas.count - 1)).rounded())
            if idx.last != i { idx.append(i) }
        }
        return idx.compactMap { i in
            diaCorto(fechas[i]).map { MarcaX(indice: i, rotulo: $0) }
        }
    }

    /// "2026-08-24" → "24 ago". Un ISO en un eje es ruido.
    static func diaCorto(_ iso: String) -> String? {
        let p = iso.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m) else { return nil }
        let meses = ["ene", "feb", "mar", "abr", "may", "jun", "jul",
                     "ago", "sep", "oct", "nov", "dic"]
        return "\(d) \(meses[m - 1])"
    }
}
