import AppKit

/**
 * MARKDOWN → TEXTO ATRIBUIDO. Nativo, sin webview.
 *
 * ⚠️ POR QUE NO HAY UN WKWebView AQUI. Ya hay lápida: los *embeds vivos*
 * murieron el 20 ago 2026 y Daniel escribió por qué — *"lo siento medio buggy,
 * prefiero el fucking localhost simple"*. Y la razón de existir de sfmap es
 * abrir instantáneo: montar WebKit para pintar un README cuesta el arranque de
 * un navegador entero por documento. AppKit ya sabe maquetar texto rico; lo que
 * faltaba era el traductor.
 *
 * El alcance es el markdown que de verdad hay en el repo de Daniel: títulos,
 * negrita/cursiva/código, listas anidadas, citas, bloques cercados, reglas,
 * tablas y el frontmatter de las skills. Lo que no entiende NO se traga: cae a
 * párrafo, que es texto legible, nunca una excepción.
 */
enum Markdown {

    // ── el árbol ───────────────────────────────────────────────────────────
    struct Trozo: Equatable {
        var texto: String
        var negrita = false, cursiva = false, codigo = false
        var liga: String? = nil
    }

    enum Bloque: Equatable {
        case titulo(Int, [Trozo])
        case parrafo([Trozo])
        /// `orden` nil = viñeta. `nivel` empieza en 0.
        case punto(orden: Int?, nivel: Int, [Trozo])
        case cita([Trozo])
        case codigo(String, lenguaje: String?)
        case regla
        case tabla(cabeza: [[Trozo]], filas: [[[Trozo]]])
        /// El bloque `---` del principio de una skill. Se pinta como ficha.
        case ficha([(String, String)])

        static func == (a: Bloque, b: Bloque) -> Bool {
            switch (a, b) {
            case (.titulo(let n1, let t1), .titulo(let n2, let t2)): n1 == n2 && t1 == t2
            case (.parrafo(let t1), .parrafo(let t2)): t1 == t2
            case (.punto(let o1, let n1, let t1), .punto(let o2, let n2, let t2)): o1 == o2 && n1 == n2 && t1 == t2
            case (.cita(let t1), .cita(let t2)): t1 == t2
            case (.codigo(let c1, let l1), .codigo(let c2, let l2)): c1 == c2 && l1 == l2
            case (.regla, .regla): true
            case (.tabla(let c1, let f1), .tabla(let c2, let f2)): c1 == c2 && f1 == f2
            case (.ficha(let a1), .ficha(let a2)): a1.map(\.0) == a2.map(\.0) && a1.map(\.1) == a2.map(\.1)
            default: false
            }
        }
    }

    // ── el análisis ────────────────────────────────────────────────────────

    static func analizar(_ md: String) -> [Bloque] {
        var out: [Bloque] = []
        let lineas = md.components(separatedBy: "\n")
        var i = 0

        // Frontmatter: solo cuenta si abre en la PRIMERA línea. Un `---` en
        // mitad del texto es una regla horizontal, y confundirlos se comía
        // medio documento en silencio.
        if lineas.first?.trimmingCharacters(in: .whitespaces) == "---" {
            var j = 1
            var pares: [(String, String)] = []
            while j < lineas.count, lineas[j].trimmingCharacters(in: .whitespaces) != "---" {
                let l = lineas[j]
                if let r = l.range(of: ":"), !l.hasPrefix(" ") {
                    var v = String(l[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if v.hasPrefix("\""), v.hasSuffix("\""), v.count > 1 { v = String(v.dropFirst().dropLast()) }
                    pares.append((String(l[l.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces), v))
                } else if var (k, v) = pares.popLast() {
                    v += " " + l.trimmingCharacters(in: .whitespaces); pares.append((k, v))
                }
                j += 1
            }
            if j < lineas.count { out.append(.ficha(pares)); i = j + 1 }
        }

        var parrafo: [String] = []
        func cerrarParrafo() {
            guard !parrafo.isEmpty else { return }
            out.append(.parrafo(enLinea(parrafo.joined(separator: " "))))
            parrafo = []
        }

        while i < lineas.count {
            let cruda = lineas[i]
            let l = cruda.trimmingCharacters(in: .whitespaces)

            // bloque cercado
            if l.hasPrefix("```") || l.hasPrefix("~~~") {
                cerrarParrafo()
                let valla = String(l.prefix(3))
                let lenguaje = String(l.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var cuerpo: [String] = []
                i += 1
                while i < lineas.count, !lineas[i].trimmingCharacters(in: .whitespaces).hasPrefix(valla) {
                    cuerpo.append(lineas[i]); i += 1
                }
                i += 1
                out.append(.codigo(cuerpo.joined(separator: "\n"), lenguaje: lenguaje.isEmpty ? nil : lenguaje))
                continue
            }

            if l.isEmpty { cerrarParrafo(); i += 1; continue }

            // regla
            if l.count >= 3, l.allSatisfy({ $0 == "-" }) || l.allSatisfy({ $0 == "*" }) || l.allSatisfy({ $0 == "_" }) {
                cerrarParrafo(); out.append(.regla); i += 1; continue
            }

            // título
            if l.hasPrefix("#") {
                let n = l.prefix(while: { $0 == "#" }).count
                if n <= 6, l.dropFirst(n).hasPrefix(" ") {
                    cerrarParrafo()
                    out.append(.titulo(n, enLinea(String(l.dropFirst(n + 1)))))
                    i += 1; continue
                }
            }

            // tabla: la fila de guiones de la SEGUNDA línea es lo que la
            // distingue de un párrafo que casualmente lleva barras.
            if l.hasPrefix("|"), i + 1 < lineas.count, esSeparadorTabla(lineas[i + 1]) {
                cerrarParrafo()
                let cabeza = celdas(l)
                i += 2
                var filas: [[[Trozo]]] = []
                while i < lineas.count, lineas[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    filas.append(celdas(lineas[i])); i += 1
                }
                out.append(.tabla(cabeza: cabeza, filas: filas))
                continue
            }

            // cita
            if l.hasPrefix(">") {
                cerrarParrafo()
                var cuerpo: [String] = []
                while i < lineas.count {
                    let c = lineas[i].trimmingCharacters(in: .whitespaces)
                    guard c.hasPrefix(">") else { break }
                    cuerpo.append(String(c.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                out.append(.cita(enLinea(cuerpo.joined(separator: " "))))
                continue
            }

            // punto de lista (la sangría manda el nivel: 2 espacios = 1 nivel)
            if let p = punto(cruda) {
                cerrarParrafo()
                out.append(.punto(orden: p.orden, nivel: p.nivel, enLinea(p.texto)))
                i += 1; continue
            }

            parrafo.append(l)
            i += 1
        }
        cerrarParrafo()
        return out
    }

    private static func esSeparadorTabla(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("|") else { return false }
        return t.allSatisfy { "|-: ".contains($0) } && t.contains("-")
    }

    private static func celdas(_ s: String) -> [[Trozo]] {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { enLinea($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func punto(_ cruda: String) -> (orden: Int?, nivel: Int, texto: String)? {
        let sangria = cruda.prefix { $0 == " " || $0 == "\t" }
            .reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let l = cruda.trimmingCharacters(in: .whitespaces)
        let nivel = min(3, sangria / 2)
        for m in ["- ", "* ", "+ "] where l.hasPrefix(m) {
            return (nil, nivel, String(l.dropFirst(2)))
        }
        // "12. texto"
        let digitos = l.prefix { $0.isNumber }
        if !digitos.isEmpty, l.dropFirst(digitos.count).hasPrefix(". ") {
            return (Int(digitos), nivel, String(l.dropFirst(digitos.count + 2)))
        }
        return nil
    }

    /// El marcado EN LINEA. Un solo barrido: el anidamiento de negrita dentro
    /// de cursiva es raro en documentos reales y no vale el analizador que
    /// costaría — lo que sí vale es que nada se pierda por el camino.
    static func enLinea(_ s: String) -> [Trozo] {
        var out: [Trozo] = []
        var buf = ""
        var neg = false, cur = false
        let cs = Array(s)
        var i = 0
        func volcar() { if !buf.isEmpty { out.append(Trozo(texto: buf, negrita: neg, cursiva: cur)); buf = "" } }

        while i < cs.count {
            let c = cs[i]
            // código en línea: gana a todo lo demás (dentro no hay marcado)
            if c == "`" {
                var j = i + 1
                while j < cs.count, cs[j] != "`" { j += 1 }
                if j < cs.count {
                    volcar()
                    out.append(Trozo(texto: String(cs[(i + 1)..<j]), codigo: true))
                    i = j + 1; continue
                }
            }
            // enlace [texto](url)
            if c == "[", let cierre = indice(cs, desde: i + 1, hasta: "]"),
               cierre + 1 < cs.count, cs[cierre + 1] == "(",
               let fin = indice(cs, desde: cierre + 2, hasta: ")") {
                volcar()
                let texto = String(cs[(i + 1)..<cierre])
                let url = String(cs[(cierre + 2)..<fin])
                for var t in enLinea(texto) { t.liga = url; t.negrita = t.negrita || neg; out.append(t) }
                i = fin + 1; continue
            }
            if c == "*" || c == "_" {
                let doble = i + 1 < cs.count && cs[i + 1] == c
                // Un `_` dentro de palabra (snake_case, nombres de archivo) NO
                // es cursiva. Sin esta guarda, `daily_business_metrics` salía a
                // medias en cursiva y el documento parecía roto.
                let pegado = c == "_" && ((i > 0 && (cs[i-1].isLetter || cs[i-1].isNumber))
                                          || (i + 1 < cs.count && !doble && (cs[i+1].isLetter || cs[i+1].isNumber) && i > 0))
                if !pegado {
                    volcar()
                    if doble { neg.toggle(); i += 2 } else { cur.toggle(); i += 1 }
                    continue
                }
            }
            buf.append(c); i += 1
        }
        volcar()
        return out.isEmpty ? [Trozo(texto: s)] : out
    }

    private static func indice(_ cs: [Character], desde: Int, hasta: Character) -> Int? {
        var i = desde
        while i < cs.count {
            if cs[i] == hasta { return i }
            if cs[i] == "\n" { return nil }
            i += 1
        }
        return nil
    }
}
