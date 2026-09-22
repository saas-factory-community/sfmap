import AppKit

/// El tema: rol → pintura. Espejo de `theme/tokens.ts`.
///
/// LA DOCTRINA, y no es decorativa: un elemento guarda su ROL, nunca un color.
/// El color se resuelve AL PINTAR. Por eso cambiar de tema repinta todo el
/// documento, incluido lo que ya estaba dibujado. Un literal es la excepción
/// que la mano firma (`color.explicit`), y solo esa gana.
struct Trazo { var color: NSColor; var grosor: Double; var estilo: String }
struct EstiloRol { var relleno: NSColor; var trazo: Trazo; var radio: Double; var sombra: Bool }

extension NSColor {
    /// #rgb, #rrggbb, #rrggbbaa y rgba(). El documento trae las cuatro formas.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("rgba(") || s.hasPrefix("rgb(") {
            let n = s.drop { $0 != "(" }.dropFirst().dropLast()
                     .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard n.count >= 3 else { return nil }
            self.init(srgbRed: n[0]/255, green: n[1]/255, blue: n[2]/255,
                      alpha: n.count > 3 ? n[3] : 1)
            return
        }
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard let v = UInt32(s, radix: 16) else { return nil }
        switch s.count {
        case 6: self.init(srgbRed: Double((v >> 16) & 255)/255, green: Double((v >> 8) & 255)/255,
                          blue: Double(v & 255)/255, alpha: 1)
        case 8: self.init(srgbRed: Double((v >> 24) & 255)/255, green: Double((v >> 16) & 255)/255,
                          blue: Double((v >> 8) & 255)/255, alpha: Double(v & 255)/255)
        default: return nil
        }
    }
}

private func c(_ h: String) -> NSColor { NSColor(hex: h) ?? .black }

struct Tema {
    var nombre: String
    var lienzo: NSColor
    var reticula: NSColor
    var acento: NSColor
    var seleccion: NSColor
    var tituloTexto: NSColor
    var cuerpoTexto: NSColor
    var pieTexto: NSColor
    var chipTexto: NSColor
    var tinta: NSColor
    var roles: [String: EstiloRol]
    var aristas: [String: Trazo]
    var tintes: [String: (relleno: NSColor, trazo: NSColor, etiqueta: NSColor)]

    static let claro: Tema = Tema(
        nombre: "claro",
        lienzo: c("#ffffff"), reticula: c("#eeeef1"),
        acento: c("#8C27F1"), seleccion: c("#8C27F1"),
        tituloTexto: c("#111114"), cuerpoTexto: c("#3f3f49"),
        pieTexto: c("#5c5c68"), chipTexto: c("#3f3f49"),
        tinta: c("#1a1a22"),
        roles: [
            "card": EstiloRol(relleno: c("#ffffff"), trazo: Trazo(color: c("#c9c9d1"), grosor: 1.5, estilo: "solid"), radio: 12, sombra: false),
            "module": EstiloRol(relleno: c("#ffffff"), trazo: Trazo(color: c("#c9c9d1"), grosor: 1.5, estilo: "solid"), radio: 12, sombra: false),
            "form": EstiloRol(relleno: c("#f0eaff"), trazo: Trazo(color: c("#8C27F1"), grosor: 2, estilo: "solid"), radio: 4, sombra: false),
            "callout": EstiloRol(relleno: c("#e2d4ff"), trazo: Trazo(color: c("#8C27F1"), grosor: 3.5, estilo: "solid"), radio: 12, sombra: false),
            "deliverable": EstiloRol(relleno: c("#fff7e8"), trazo: Trazo(color: c("#c98a12"), grosor: 1.5, estilo: "solid"), radio: 4, sombra: true),
            "trigger": EstiloRol(relleno: c("#ffffff"), trazo: Trazo(color: c("#c9c9d1"), grosor: 1.5, estilo: "solid"), radio: 12, sombra: false),
            "risk": EstiloRol(relleno: c("#fdeaea"), trazo: Trazo(color: c("#dc2626"), grosor: 2.5, estilo: "solid"), radio: 12, sombra: false),
            "agent": EstiloRol(relleno: c("#f0eaff"), trazo: Trazo(color: c("#8C27F1"), grosor: 2.5, estilo: "solid"), radio: 12, sombra: false),
            "tray": EstiloRol(relleno: c("#f7f7f9"), trazo: Trazo(color: c("#e4e4e8"), grosor: 1, estilo: "solid"), radio: 20, sombra: false),
            "sticky": EstiloRol(relleno: c("#faf7ff"), trazo: Trazo(color: c("#e4e4e8"), grosor: 1, estilo: "solid"), radio: 6, sombra: false),
            "nota": EstiloRol(relleno: c("#fff5c2"), trazo: Trazo(color: c("#e6cf6a"), grosor: 1, estilo: "solid"), radio: 6, sombra: false),
            "sensor": EstiloRol(relleno: c("#f1f3f8"), trazo: Trazo(color: c("#8a8d9c"), grosor: 1.5, estilo: "solid"), radio: 6, sombra: false),
            "widget": EstiloRol(relleno: c("#fbfbfd"), trazo: Trazo(color: c("#8a8d9c"), grosor: 1.5, estilo: "solid"), radio: 10, sombra: false),
            "drawn": EstiloRol(relleno: NSColor.clear, trazo: Trazo(color: c("#3a3a44"), grosor: 2.5, estilo: "solid"), radio: 12, sombra: false),
        ],
        aristas: [
            "flujo": Trazo(color: c("#9a9aa6"), grosor: 2, estilo: "solid"),
            "agente": Trazo(color: c("#8C27F1"), grosor: 3, estilo: "dashed"),
            "fragil": Trazo(color: c("#c98a12"), grosor: 3, estilo: "dashed"),
            "hueco": Trazo(color: c("#c4c4cc"), grosor: 1.5, estilo: "dashed"),
            // ESTADO DE SEGURIDAD sobre la arista (5 sep 2026, «La Red» de El Ecosistema).
            // La gramática de 5 colores del handoff (verde/azul/ámbar/gris/rojo) ya estaba
            // firmada para NODOS con leyenda; estas dos clases la llevan al cable cuando el
            // camino mismo es la exposición (rojo, sólida: se ve de lejos) o el arreglo que
            // aún no está en producción (azul, punteada). Ámbar sigue siendo `fragil`.
            "expuesto": Trazo(color: c("#dc2626"), grosor: 3.5, estilo: "solid"),
            "lab": Trazo(color: c("#2f6fd6"), grosor: 2.5, estilo: "dashed"),
        ],
        tintes: [
            "neutro": (c("#f7f7f9"), c("#dcdce2"), c("#6a6a76")),
            "morado": (c("#f6f0ff"), c("#c9a8f5"), c("#7126c4")),
            // ⚠️ El filo del ámbar sube de #e8c07a a #d99a1f. El anterior sobre
            // blanco daba un dorado pálido que un crítico describió como "de
            // bajísimo contraste, casi confundido con el gris del texto
            // secundario" — y ese filo es el que lleva el gatillo del pacto y
            // el contorno del reloj del HT. El tono sigue siendo el mismo
            // ámbar: cambia cuánto, no cuál.
            "ambar": (c("#fff7e8"), c("#d99a1f"), c("#9a6206")),
            "verde": (c("#eefaf3"), c("#94d3b0"), c("#11734a")),
            "azul": (c("#eef4ff"), c("#9dbcf0"), c("#1b4fa8")),
            "rosa": (c("#fff0f6"), c("#f0a6c4"), c("#a41d5c")),
            "rojo": (c("#fdeeee"), c("#eda2a2"), c("#a52020")),
        ])

    static let oscuro: Tema = Tema(
        nombre: "oscuro",
        lienzo: c("#0a0b10"), reticula: c("#16171f"),
        acento: c("#8C27F1"), seleccion: c("#8C27F1"),
        tituloTexto: c("#f6f7fb"), cuerpoTexto: c("#c3c7d4"),
        pieTexto: c("#9599a6"), chipTexto: c("#c3c7d4"),
        tinta: c("#eceef6"),
        roles: [
            "card": EstiloRol(relleno: c("#12131b"), trazo: Trazo(color: c("#33343f"), grosor: 1.5, estilo: "solid"), radio: 12, sombra: false),
            "module": EstiloRol(relleno: c("#12131b"), trazo: Trazo(color: c("#33343f"), grosor: 1.5, estilo: "solid"), radio: 12, sombra: false),
            "form": EstiloRol(relleno: c("#1d1733"), trazo: Trazo(color: c("#8C27F1"), grosor: 2, estilo: "solid"), radio: 4, sombra: false),
            "callout": EstiloRol(relleno: c("#2a1d4d"), trazo: Trazo(color: c("#8C27F1"), grosor: 3.5, estilo: "solid"), radio: 12, sombra: false),
            "deliverable": EstiloRol(relleno: c("#241c0d"), trazo: Trazo(color: c("#ff9101"), grosor: 1.5, estilo: "solid"), radio: 4, sombra: true),
            "trigger": EstiloRol(relleno: c("#12131b"), trazo: Trazo(color: c("#33343f"), grosor: 1.5, estilo: "solid"), radio: 12, sombra: false),
            "risk": EstiloRol(relleno: c("#2a1416"), trazo: Trazo(color: c("#ef4444"), grosor: 2.5, estilo: "solid"), radio: 12, sombra: false),
            "agent": EstiloRol(relleno: c("#1d1733"), trazo: Trazo(color: c("#8C27F1"), grosor: 2.5, estilo: "solid"), radio: 12, sombra: false),
            "tray": EstiloRol(relleno: c("#101119"), trazo: Trazo(color: c("#26272f"), grosor: 1, estilo: "solid"), radio: 20, sombra: false),
            "sticky": EstiloRol(relleno: c("#181528"), trazo: Trazo(color: c("#26272f"), grosor: 1, estilo: "solid"), radio: 6, sombra: false),
            "nota": EstiloRol(relleno: c("#332b0e"), trazo: Trazo(color: c("#7a6a24"), grosor: 1, estilo: "solid"), radio: 6, sombra: false),
            "sensor": EstiloRol(relleno: c("#14161f"), trazo: Trazo(color: c("#4a4d5e"), grosor: 1.5, estilo: "solid"), radio: 6, sombra: false),
            "widget": EstiloRol(relleno: c("#0d0f17"), trazo: Trazo(color: c("#4a4d5e"), grosor: 1.5, estilo: "solid"), radio: 10, sombra: false),
            "drawn": EstiloRol(relleno: NSColor.clear, trazo: Trazo(color: c("#c8c9d4"), grosor: 2.5, estilo: "solid"), radio: 12, sombra: false),
        ],
        aristas: [
            "flujo": Trazo(color: c("#6a6c7c"), grosor: 2, estilo: "solid"),
            "agente": Trazo(color: c("#9d3cf5"), grosor: 3, estilo: "dashed"),
            "fragil": Trazo(color: c("#ffac3d"), grosor: 3, estilo: "dashed"),
            "hueco": Trazo(color: c("#3a3b47"), grosor: 1.5, estilo: "dashed"),
            "expuesto": Trazo(color: c("#ff5a5a"), grosor: 3.5, estilo: "solid"),
            "lab": Trazo(color: c("#6fa2ff"), grosor: 2.5, estilo: "dashed"),
        ],
        tintes: [
            "neutro": (c("#15161d"), c("#2f313c"), c("#9a9cab")),
            "morado": (c("#1b1330"), c("#8C27F1"), c("#c79cff")),
            "ambar": (c("#241c0d"), c("#ff9101"), c("#ffb64d")),
            "verde": (c("#0f2019"), c("#2c6a4c"), c("#6fd3a4")),
            "azul": (c("#111a2c"), c("#2f5490"), c("#8fb4f5")),
            "rosa": (c("#26121c"), c("#8a3a63"), c("#f095bd")),
            "rojo": (c("#261314"), c("#8c3a3a"), c("#f09a9a")),
        ])

    /**
     * ⭐ EL ROL `tapa` — el PAPEL, pintado ENCIMA (26 ago 2026).
     *
     * Daniel, dictando el curso v2: *"pongámosle como que una tarjeta del color
     * del fondo por encima, para que parezca que está en blanco, y que yo con
     * el mouse pueda darle clic y arrastrarlo, de modo que la puedo quitar para
     * explicar parte por parte"*. Es una cortina: mientras está puesta el
     * concepto no existe; al arrastrarla fuera, aparece.
     *
     * NO es un literal blanco. La doctrina de este archivo —*"un elemento
     * guarda su ROL, nunca un color"*— ya se rompió una vez por la puerta de
     * atrás (la silueta del reloj de arena, 25 ago) y costó dos bloques casi
     * blancos en el tema oscuro. Una tapa con `#ffffff` sería el MISMO fallo,
     * y encima más visible: en oscuro sería un parche de nieve en la página.
     * Por eso el relleno de la tapa **es** `lienzo`: el mismo color que la
     * página, en el tema que sea. Si el papel cambia, la tapa cambia con él.
     *
     * Sin contorno (grosor 0) y sin radio: un borde delataría el rectángulo y
     * la ilusión —"aquí no hay nada"— se cae antes de empezar.
     */
    func rol(_ n: String) -> EstiloRol {
        if n == "tapa" {
            return EstiloRol(relleno: lienzo,
                             trazo: Trazo(color: lienzo, grosor: 0, estilo: "solid"),
                             radio: 0, sombra: false)
        }
        return roles[n] ?? roles["card"]!
    }

    /**
     * LA TINTA QUE SE LEE SOBRE UN FONDO DADO — medida, no supuesta.
     *
     * Regla de sistema de diseño (25 ago 2026), y nace de un fallo que estuvo
     * a la vista tres iteraciones: los rótulos de banda se pintaban con el
     * color del LIENZO, asumiendo que la pastilla siempre sería un color
     * saturado. Con el tinte `neutro` —el de las tres bandas del tablero— eso
     * daba negro sobre negro en oscuro y blanco sobre blanco en claro.
     *
     * **Cualquier texto que caiga sobre un fondo de color pasa por aquí.** Una
     * convención ("sobre pastilla va el color del lienzo") se rompe en silencio
     * el día que alguien añade un tinte; una medición no se rompe nunca.
     *
     * ⚠️ Y SE MIDE EL CONTRASTE DE LAS DOS OPCIONES, no se decide por umbral.
     *
     * La primera versión usaba un umbral fijo de luminancia (0.55): por encima
     * tinta oscura, por debajo clara. Su propia prueba la tumbó — sobre el
     * morado de marca daba 1.9:1 y sobre el ámbar 2.1:1, los dos ilegibles. El
     * umbral acierta en los extremos y falla justo en los tonos MEDIOS, que son
     * los interesantes. Calcular el contraste real de las dos candidatas y
     * quedarse con la mejor no tiene ese punto ciego.
     *
     * Se devuelven los textos del TEMA y no blanco/negro puros, para que el
     * rótulo pertenezca al mismo sistema que el resto del tablero.
     */
    static func tintaSobre(_ fondo: NSColor) -> NSColor {
        func luz(_ col: NSColor) -> Double {
            guard let c = col.usingColorSpace(.sRGB) else { return 0 }
            func lin(_ v: Double) -> Double {
                v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent)
                 + 0.0722 * lin(c.blueComponent)
        }
        let lf = luz(fondo)
        func contraste(_ t: NSColor) -> Double {
            let lt = luz(t)
            return (max(lt, lf) + 0.05) / (min(lt, lf) + 0.05)
        }
        let oscura = Tema.claro.tituloTexto, clara = Tema.oscuro.tituloTexto
        return contraste(oscura) >= contraste(clara) ? oscura : clara
    }

    /**
     * LA RAMPA DE UN TINTE — tres pasos del MISMO color.
     *
     * Daniel, mirando los Miro de Mateo (25 ago): *"nota cómo Mateo utiliza
     * varios morados de la misma paleta para dar estructura"*. Y es exacto: en
     * su tablero la profundidad no la da un color nuevo, la da el MISMO color
     * en tres intensidades. Eso NO rompe la paleta reducida — la refuerza,
     * porque el matiz sigue significando lo mismo y lo que cambia es cuánto.
     *
     * `paso` va de 0 (tenue, el fondo) a 1 (fuerte, el filo). Se usa para
     * codificar PROFUNDIDAD: en un embudo, la boca es tenue y el cuello es
     * fuerte, así que el color dice a qué altura del embudo estás. Un degradado
     * que no significa nada sería decoración; este mide.
     */
    func rampa(_ tinte: String, _ paso: Double) -> NSColor {
        guard let t = tintes[tinte] else { return rol("card").relleno }
        let p = max(0, min(1, paso))
        // ⚠️ La mezcla llega hasta el 100% del filo a proposito. Con el 55%
        // que tenia, un critico midio 5-8 unidades RGB entre el primer paso y
        // el ultimo: una rampa que no se ve no esta pagando su complejidad.
        return t.relleno.blended(withFraction: p, of: t.trazo) ?? t.relleno
    }

    /// El color de relleno que toca pintar. El literal de la mano gana; luego el
    /// TERRITORIO (`tint`); si no, manda el rol.
    ///
    /// ⚠️ POR QUE UNA FIGURA PUEDE LLEVAR `tint` (enmienda 25 ago 2026, y nace
    /// de un fallo medido). La silueta del reloj de arena se pintó con un
    /// LITERAL del tema claro, y un literal NO se repinta al cambiar de tema:
    /// en oscuro quedaron dos bloques casi blancos que se comían el tablero.
    /// La doctrina estaba escrita desde el día uno —*"un elemento guarda su
    /// ROL, nunca un color"*— y el literal la rompió por la puerta de atrás.
    ///
    /// El arreglo no es otro literal para el oscuro: es que el TERRITORIO sea
    /// una capa del tema, igual que ya lo era para las secciones. Una figura
    /// con `tint` es territorio de forma no rectangular, y su color lo resuelve
    /// el tema en los DOS.
    func relleno(_ e: Elemento) -> NSColor {
        if let h = e.relleno, let col = NSColor(hex: h) { return col }
        if let t = e.territorio, let tt = tintes[t] {
            // `marcador: true` = el subrayado del título: quiere el tono FUERTE
            // del tinte (su filo), no el fondo tenue de un territorio.
            if e.crudo["marcador"]?.b ?? false { return tt.trazo }
            /*
             * ⚠️ LA SILUETA NECESITA MÁS CUERPO QUE UNA SECCIÓN (25 ago 2026).
             *
             * Es el MISMO fallo del 24 ago, espejado. Aquel día la silueta del
             * reloj salía lavada en OSCURO; el arreglo fue que el territorio lo
             * resolviera el tema. Pero el tinte que se eligió es el de una
             * SECCIÓN —pensado para vivir DEBAJO de tarjetas sin competir— y en
             * CLARO eso es `#f6f0ff` sobre `#ffffff`: el crítico del pase de
             * integración lo describió como *"el mapa del sistema pierde su
             * forma justo en el tema claro"*.
             *
             * Una silueta no es un fondo: es el ARGUMENTO (la forma del embudo
             * ES la tesis). Se le da un paso más hacia su filo, lo justo para
             * separarse de la página. `FiguraVisibleTests` mide que en los DOS
             * temas la silueta se distinga del lienzo.
             */
            if e.rol == "drawn" {
                return tt.relleno.blended(withFraction: nombre == "claro" ? 0.28 : 0.10,
                                          of: tt.trazo) ?? tt.relleno
            }
            return tt.relleno
        }
        return rol(e.rol).relleno
    }
    func contorno(_ e: Elemento) -> Trazo {
        var t = rol(e.rol).trazo
        if let n = e.territorio, let tt = tintes[n] {
            t.color = tt.trazo
            /*
             * EL CONTORNO DE LA SILUETA ES GRUESO. Orden de Daniel (25 ago):
             * *"a los relojes de arena yo les pondría un contorno ámbar y
             * morado grueso"*.
             *
             * Y no es capricho: la silueta es el ARGUMENTO del tablero (la
             * forma del embudo ES la tesis). Con relleno tenue y línea de un
             * pelo, la forma solo se percibía de cerca; el filo grueso la hace
             * legible al zoom al que se mira el panel entero. El color sigue
             * siendo el del territorio —morado el LT, ámbar el HT—, así que no
             * entra ni un matiz nuevo al vocabulario.
             */
            if e.rol == "drawn" { t.grosor = 7 }
        }
        if let h = e.contorno, let col = NSColor(hex: h) { t.color = col }
        if let s = e.estiloLinea { t.estilo = s }
        if let g = e.grosorLinea { t.grosor = g }
        return t
    }
    func radio(_ e: Elemento) -> Double { e.radioEsquina ?? rol(e.rol).radio }
}
