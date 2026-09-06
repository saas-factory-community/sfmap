import AppKit

/**
 * EL PANEL DEL DOCUMENTO — el mapa deja de contener la operación y la INDEXA.
 *
 * El gen viene del Miro del growth partner de Daniel: cada widget del tablero
 * abría un documento. Allá el documento vivía en Word y en la nube de otro;
 * aquí vive en el repo, en markdown, y ya existe — lo único que faltaba era que
 * el mapa apuntara a él. Por eso un nodo con `doc:ruta.md` no COPIA nada: abre
 * el canónico. Copiarlo habría fundado un segundo original, que es exactamente
 * la enfermedad que `MAPA-FUENTES-DE-VERDAD.md` existe para evitar.
 *
 * Vive a la DERECHA y el lienzo se encoge, no se tapa: leer un SOP mientras se
 * mira el sistema es el gesto entero. Un panel modal habría obligado a elegir.
 */

/// Las claves de atributo propias. Marcan QUE ES un tramo para que el fondo se
/// pueda pintar después: el texto atribuido sabe de tipografía, no de cajas.
extension NSAttributedString.Key {
    static let sfBloque = NSAttributedString.Key("sfBloque")
    static let sfLiga = NSAttributedString.Key("sfLiga")
}

extension Markdown {

    /// Los bloques, ya vestidos. El ancho entra porque las tablas se maquetan
    /// con tabuladores medidos, no con espacios.
    static func atribuido(_ bloques: [Bloque], tema: Tema, ancho: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString()

        func fuente(_ tam: Double, _ peso: Double, cursiva: Bool = false, mono: Bool = false) -> NSFont {
            Fuentes.fuente(familia: mono ? "jetbrains-mono" : "montserrat",
                           peso: peso, tamano: tam, cursiva: cursiva) as NSFont
        }

        func parrafo(_ ajuste: (NSMutableParagraphStyle) -> Void) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = 1.34
            p.paragraphSpacing = 11
            ajuste(p)
            return p
        }

        func pegar(_ trozos: [Trozo], base: Double, peso: Double, color: NSColor,
                   estilo: NSParagraphStyle, bloque: String? = nil) {
            for t in trozos {
                var a: [NSAttributedString.Key: Any] = [
                    .font: fuente(t.codigo ? base * 0.94 : base,
                                  t.negrita ? max(peso, 700) : peso,
                                  cursiva: t.cursiva, mono: t.codigo),
                    .foregroundColor: color,
                    .paragraphStyle: estilo,
                ]
                if t.codigo {
                    a[.foregroundColor] = tema.acento
                    a[.sfBloque] = "codigo-linea"
                }
                if let l = t.liga {
                    a[.foregroundColor] = tema.acento
                    a[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    a[.sfLiga] = l
                }
                if let b = bloque, a[.sfBloque] == nil { a[.sfBloque] = b }
                out.append(NSAttributedString(string: t.texto, attributes: a))
            }
        }

        func salto(_ n: Int = 1, estilo: NSParagraphStyle? = nil) {
            var a: [NSAttributedString.Key: Any] = [.font: fuente(4, 400)]
            if let e = estilo { a[.paragraphStyle] = e }
            out.append(NSAttributedString(string: String(repeating: "\n", count: n), attributes: a))
        }

        for (i, b) in bloques.enumerated() {
            switch b {
            case .ficha(let pares):
                let est = parrafo { $0.firstLineHeadIndent = 14; $0.headIndent = 14; $0.paragraphSpacing = 4 }
                for (k, v) in pares {
                    out.append(NSAttributedString(string: k.uppercased() + "  ", attributes: [
                        .font: fuente(10, 700, mono: true), .foregroundColor: tema.pieTexto,
                        .paragraphStyle: est, .sfBloque: "ficha", .kern: 0.6,
                    ]))
                    out.append(NSAttributedString(string: String(v.prefix(400)) + "\n", attributes: [
                        .font: fuente(12, 500), .foregroundColor: tema.cuerpoTexto,
                        .paragraphStyle: est, .sfBloque: "ficha",
                    ]))
                }
                salto()

            case .titulo(let n, let t):
                // La escala tipográfica es la del cromo, no una nueva: un solo
                // sistema de tamaños en toda la app o cada superficie inventa
                // su propia jerarquía y ninguna se lee como la otra.
                let tam: Double = [26, 20, 16, 14, 13, 12][min(n, 5) - 1 + (n == 0 ? 1 : 0)]
                let est = parrafo {
                    $0.paragraphSpacingBefore = i == 0 ? 0 : (n <= 2 ? 22 : 16)
                    $0.paragraphSpacing = 7
                    $0.lineHeightMultiple = 1.18
                }
                pegar(t, base: tam, peso: n <= 2 ? 800 : 700, color: tema.tituloTexto,
                      estilo: est, bloque: n == 1 ? "h1" : nil)
                salto(1, estilo: est)

            case .parrafo(let t):
                pegar(t, base: 13.5, peso: 500, color: tema.cuerpoTexto, estilo: parrafo { _ in })
                salto()

            case .punto(let orden, let nivel, let t):
                let sangria = CGFloat(18 + nivel * 18)
                let est = parrafo {
                    $0.firstLineHeadIndent = sangria - 14
                    $0.headIndent = sangria
                    $0.paragraphSpacing = 5
                }
                let vinieta = orden.map { "\($0). " } ?? (nivel == 0 ? "•  " : "–  ")
                out.append(NSAttributedString(string: vinieta, attributes: [
                    .font: fuente(13.5, 700), .foregroundColor: orden == nil ? tema.acento : tema.pieTexto,
                    .paragraphStyle: est,
                ]))
                pegar(t, base: 13.5, peso: 500, color: tema.cuerpoTexto, estilo: est)
                salto(1, estilo: est)

            case .cita(let t):
                let est = parrafo {
                    $0.firstLineHeadIndent = 20; $0.headIndent = 20
                    $0.paragraphSpacingBefore = 8; $0.paragraphSpacing = 12
                }
                pegar(t, base: 13, peso: 500, color: tema.pieTexto, estilo: est, bloque: "cita")
                salto(1, estilo: est)

            case .codigo(let cuerpo, _):
                // ⚠️ INTERLINEADO 1.0 EN LOS BLOQUES DE CODIGO, y no es un
                // detalle tipográfico: los documentos de este repo están llenos
                // de DIAGRAMAS ASCII (la escalera de valor es uno). Con el
                // interlineado del cuerpo, las flechas y las cajas se separan
                // de sus renglones y el dibujo deja de ser un dibujo. Un
                // bloque cercado es una rejilla; se respeta como rejilla.
                let est = parrafo {
                    $0.firstLineHeadIndent = 14; $0.headIndent = 14
                    $0.lineHeightMultiple = 1.0
                    $0.lineSpacing = 1
                    $0.paragraphSpacingBefore = 8; $0.paragraphSpacing = 12
                }
                out.append(NSAttributedString(string: cuerpo + "\n", attributes: [
                    .font: fuente(11.5, 500, mono: true), .foregroundColor: tema.cuerpoTexto,
                    .paragraphStyle: est, .sfBloque: "codigo",
                ]))

            case .regla:
                let est = parrafo { $0.paragraphSpacingBefore = 10; $0.paragraphSpacing = 10 }
                out.append(NSAttributedString(string: "\n", attributes: [
                    .font: fuente(2, 400), .paragraphStyle: est, .sfBloque: "regla",
                ]))

            case .tabla(let cabeza, let filas):
                // Tabuladores MEDIDOS: el ancho de columna sale del contenido
                // real, no de un espaciado fijo que se desalinea a la tercera
                // fila. Es la misma doctrina del medidor del lienzo.
                let cols = max(cabeza.count, filas.map(\.count).max() ?? 0)
                guard cols > 0 else { break }
                let paso = max(90, min(230, (ancho - 30) / CGFloat(cols)))
                let est = parrafo {
                    $0.tabStops = (1...max(1, cols)).map {
                        NSTextTab(textAlignment: .left, location: CGFloat($0) * paso)
                    }
                    $0.defaultTabInterval = paso
                    $0.headIndent = 0; $0.paragraphSpacing = 3
                    $0.lineHeightMultiple = 1.2
                    $0.lineBreakMode = .byTruncatingTail
                }
                func fila(_ celdas: [[Trozo]], cabecera: Bool) {
                    for (j, c) in celdas.enumerated() {
                        pegar(c, base: 12, peso: cabecera ? 700 : 500,
                              color: cabecera ? tema.tituloTexto : tema.cuerpoTexto,
                              estilo: est, bloque: cabecera ? "tabla-cabeza" : "tabla")
                        if j < celdas.count - 1 {
                            out.append(NSAttributedString(string: "\t", attributes: [
                                .font: fuente(12, 500), .paragraphStyle: est,
                                .sfBloque: cabecera ? "tabla-cabeza" : "tabla",
                            ]))
                        }
                    }
                    out.append(NSAttributedString(string: "\n", attributes: [
                        .font: fuente(12, 500), .paragraphStyle: est,
                        .sfBloque: cabecera ? "tabla-cabeza" : "tabla",
                    ]))
                }
                fila(cabeza, cabecera: true)
                for f in filas { fila(f, cabecera: false) }
                salto()
            }
        }
        return out
    }
}

/// El texto con los fondos de bloque pintados debajo. Un `NSTextView` maqueta
/// tipografía; las cajas de código, la barra de la cita y la regla son
/// GEOMETRIA, y se pintan aquí con los rectángulos que el maquetador ya sabe.
final class VistaDoc: NSTextView {
    var tema: Tema = .claro { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirty: NSRect) {
        pintarFondos(dirty)
        super.draw(dirty)
    }

    private func pintarFondos(_ dirty: NSRect) {
        guard let lm = layoutManager, let tc = textContainer,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        let texto = attributedString()
        guard texto.length > 0 else { return }
        let origen = textContainerOrigin

        texto.enumerateAttribute(.sfBloque, in: NSRange(location: 0, length: texto.length)) { v, r, _ in
            guard let clase = v as? String else { return }
            let glifos = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            var caja = lm.boundingRect(forGlyphRange: glifos, in: tc)
            caja.origin.x += origen.x; caja.origin.y += origen.y
            guard caja.intersects(dirty) || caja.height > 0 else { return }

            switch clase {
            case "codigo":
                let c = caja.insetBy(dx: -8, dy: -6)
                ctx.setFillColor(tema.rol("sensor").relleno.cgColor)
                let p = CGMutablePath()
                p.addRoundedRect(in: CGRect(x: 4, y: c.minY, width: bounds.width - 20, height: c.height),
                                 cornerWidth: 8, cornerHeight: 8)
                ctx.addPath(p); ctx.fillPath()
            case "cita":
                ctx.setFillColor(tema.acento.withAlphaComponent(0.55).cgColor)
                ctx.fill(CGRect(x: 6, y: caja.minY - 2, width: 3, height: caja.height + 4))
            case "ficha":
                ctx.setFillColor(tema.rol("sticky").relleno.cgColor)
                ctx.fill(CGRect(x: 4, y: caja.minY - 1, width: bounds.width - 20, height: caja.height + 2))
            case "tabla-cabeza":
                ctx.setFillColor(tema.rol("tray").relleno.cgColor)
                ctx.fill(CGRect(x: 4, y: caja.minY - 3, width: bounds.width - 20, height: caja.height + 6))
                ctx.setFillColor(tema.reticula.cgColor)
                ctx.fill(CGRect(x: 4, y: caja.maxY + 2, width: bounds.width - 20, height: 1))
            case "regla":
                ctx.setFillColor(tema.reticula.cgColor)
                ctx.fill(CGRect(x: 4, y: caja.midY, width: bounds.width - 20, height: 1))
            case "h1":
                ctx.setFillColor(tema.acento.cgColor)
                ctx.fill(CGRect(x: 4, y: caja.maxY + 5, width: 42, height: 3))
            default: break
            }
        }
    }

    /// Un clic sobre una liga del documento la abre. Sin esto, un `[texto](url)`
    /// se pinta como enlace y no lo es: prometer y no cumplir es el pecado que
    /// este lienzo persigue.
    var alAbrirLiga: ((String) -> Void)?

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if let lm = layoutManager, let tc = textContainer {
            let o = textContainerOrigin
            let i = lm.characterIndex(for: CGPoint(x: p.x - o.x, y: p.y - o.y),
                                      in: tc, fractionOfDistanceBetweenInsertionPoints: nil)
            if i < attributedString().length,
               let liga = attributedString().attribute(.sfLiga, at: i, effectiveRange: nil) as? String {
                alAbrirLiga?(liga); return
            }
        }
        super.mouseDown(with: e)
    }
}

/// El panel entero: cabecera con la ruta, el texto y su desplazamiento.
final class PanelDoc: NSView {
    private let scroll = NSScrollView()
    private let texto = VistaDoc()
    private let titulo = NSTextField(labelWithString: "")
    private let ruta = NSTextField(labelWithString: "")
    private let cerrar = NSButton()
    var tema: Tema = .claro { didSet { aplicarTema() } }
    var alCerrar: (() -> Void)?
    var alAbrirLiga: ((String) -> Void)? { didSet { texto.alAbrirLiga = alAbrirLiga } }
    private(set) var docActual: String?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        titulo.font = Estilo.fuente(14, 700)
        titulo.lineBreakMode = .byTruncatingTail
        ruta.font = Estilo.mono(10, 500)
        ruta.lineBreakMode = .byTruncatingHead

        cerrar.isBordered = false
        cerrar.title = ""
        cerrar.image = Icono.equis
        cerrar.imageScaling = .scaleProportionallyDown
        cerrar.target = self
        cerrar.action = #selector(pulsarCerrar)

        texto.isEditable = false
        texto.isSelectable = true
        texto.drawsBackground = false
        texto.textContainerInset = NSSize(width: 16, height: 14)
        texto.textContainer?.lineFragmentPadding = 0
        texto.autoresizingMask = [.width]

        scroll.documentView = texto
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true

        addSubview(scroll); addSubview(titulo); addSubview(ruta); addSubview(cerrar)
        aplicarTema()
    }
    required init?(coder: NSCoder) { nil }

    @objc private func pulsarCerrar() { alCerrar?() }

    private func aplicarTema() {
        texto.tema = tema
        titulo.textColor = tema.tituloTexto
        ruta.textColor = tema.pieTexto
        cerrar.image = Estilo.iconoBisel(Icono.equis, tema)
        needsDisplay = true
    }

    override func draw(_ dirty: NSRect) {
        Estilo.pintarBisel(self, tema, radio: 0)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // El filo IZQUIERDO: es lo único que separa el panel del tablero, y sin
        // él las dos superficies se funden en una sola mancha clara.
        ctx.setFillColor(tema.reticula.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: bounds.height))
        ctx.fill(CGRect(x: 0, y: cabecera - 1, width: bounds.width, height: 1))
    }

    private let cabecera: CGFloat = 54

    override func layout() {
        super.layout()
        let a: CGFloat = 14
        cerrar.frame = NSRect(x: bounds.width - 30, y: 12, width: 20, height: 20)
        titulo.frame = NSRect(x: a, y: 10, width: bounds.width - a - 38, height: 18)
        ruta.frame = NSRect(x: a, y: 30, width: bounds.width - a - 38, height: 14)
        scroll.frame = NSRect(x: 0, y: cabecera, width: bounds.width, height: bounds.height - cabecera)
        texto.frame.size.width = scroll.contentSize.width
        texto.textContainer?.containerSize = NSSize(width: scroll.contentSize.width - 32,
                                                    height: .greatestFiniteMagnitude)
    }

    /// Carga un markdown del repo. Devuelve el error EN EL PANEL, nunca en
    /// silencio: un nodo que promete un documento y no abre nada es peor que un
    /// nodo sin liga, porque enseña a no volver a pulsarlo.
    @discardableResult
    func mostrar(_ relativa: String) -> Bool {
        docActual = relativa
        let url = Enlace.rutaDoc(relativa)
        titulo.stringValue = url.lastPathComponent
        ruta.stringValue = relativa
        let ancho = max(240, scroll.contentSize.width - 32)

        guard let crudo = try? String(contentsOf: url, encoding: .utf8) else {
            texto.textStorage?.setAttributedString(NSAttributedString(
                string: "No encontré el documento.\n\n\(relativa)\n\nLo busqué en:\n\(url.path)",
                attributes: [.font: Estilo.mono(12, 500), .foregroundColor: tema.pieTexto]))
            return false
        }
        let attr = Markdown.atribuido(Markdown.analizar(crudo), tema: tema, ancho: ancho)
        texto.textStorage?.setAttributedString(attr)
        texto.scroll(.zero)
        needsLayout = true
        return true
    }
}
