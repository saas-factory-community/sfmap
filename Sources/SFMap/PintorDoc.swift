import AppKit
import CoreGraphics

/**
 * EL WIDGET-DOCUMENTO — un nodo que se VE como el documento que abre.
 *
 * Gen robado del tablero de Mateo (`miro-mateo-widgets-preview-docs.png`): sus
 * tarjetas AVATAR / OFERTA / PRODUCTO no dicen "hay un documento aquí", enseñan
 * una MINIATURA del documento. Daniel: *"obviamente mejor acomodado; no nos
 * interesan los logos de gdocs"* — así que aquí no hay iconografía ajena: la
 * miniatura es del markdown REAL del repo, y la marca es nuestra.
 *
 * ⚠️ QUE SE DIBUJA Y POR QUE ASI. A los zooms de trabajo (0.3-0.5) un cuerpo de
 * texto a 5pt no se lee: se ve como una mancha. Así que se pinta lo que SÍ
 * comunica a ese tamaño y es igual de honesto:
 *
 *   - los TITULARES, con su texto real (son lo que identifica al documento);
 *   - el cuerpo, como renglones cuya LONGITUD sale de la longitud real de cada
 *     línea (la mancha tiene la forma del documento, no una forma inventada);
 *   - los bloques de código, como una placa;
 *   - las listas, con su viñeta.
 *
 * No es un adorno con forma de documento: es el documento a 12% de tamaño.
 *
 * El coste se paga UNA vez: la miniatura se calcula al leer el archivo y se
 * cachea por ruta + fecha de modificación. Editar el markdown la refresca sola.
 */
extension Pintor {

    struct Miniatura {
        enum Renglon {
            case titulo(String, nivel: Int)
            case linea(Double)            // 0-1: qué tan largo, del real
            case punto(Double)
            case placa(Int)               // renglones de código
        }
        var renglones: [Renglon]
        var nombre: String
    }

    private static var cacheMini: [String: (fecha: Date?, mini: Miniatura)] = [:]

    static func miniatura(_ relativa: String) -> Miniatura? {
        let url = Enlace.rutaDoc(relativa)
        let fecha = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let c = cacheMini[relativa], c.fecha == fecha { return c.mini }
        guard let crudo = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var rs: [Miniatura.Renglon] = []
        for b in Markdown.analizar(crudo) {
            switch b {
            case .titulo(let n, let t):
                rs.append(.titulo(t.map(\.texto).joined(), nivel: n))
            case .parrafo(let t):
                // Un párrafo se parte en renglones de ~62 caracteres, que es lo
                // que cabe en una columna: así la mancha tiene el mismo ritmo
                // que el documento de verdad.
                let n = max(1, t.map(\.texto).joined().count / 62 + 1)
                let total = t.map(\.texto).joined().count
                for i in 0..<min(n, 6) {
                    let resto = total - i * 62
                    rs.append(.linea(min(1, Double(resto) / 62)))
                }
            case .punto(_, _, let t):
                rs.append(.punto(min(1, Double(t.map(\.texto).joined().count) / 58)))
            case .codigo(let c, _):
                rs.append(.placa(min(8, c.components(separatedBy: "\n").count)))
            case .cita(let t):
                rs.append(.punto(min(1, Double(t.map(\.texto).joined().count) / 58)))
            case .tabla(_, let f):
                rs.append(.placa(min(6, f.count + 1)))
            case .ficha, .regla:
                rs.append(.linea(0.35))
            }
            if rs.count > 40 { break }
        }
        let m = Miniatura(renglones: rs, nombre: url.lastPathComponent)
        cacheMini[relativa] = (fecha, m)
        return m
    }

    /// El widget entero: hoja + miniatura + rótulo. Se pinta DENTRO de la caja
    /// del elemento, que el generador ya dimensionó.
    func documento(_ e: Elemento) {
        guard case .documento(let ruta)? = Enlace.leer(e.enlace) else { return }
        let r = e.caja
        ctx.saveGState()
        ctx.setAlpha(e.opacidad)

        // ── el RÓTULO, arriba y fuera de la hoja (como en el referente) ──────
        let etiqueta = (e.crudo["doc"]?["etiqueta"]?.s ?? "").uppercased()
        let titulo = e.crudo["doc"]?["titulo"]?.s ?? Pintor.miniatura(ruta)?.nombre ?? ruta
        var y = r.minY
        if !etiqueta.isEmpty {
            pintarTexto(etiqueta, en: CGPoint(x: r.minX, y: y),
                        tamano: 11, peso: 800, color: tema.pieTexto, mono: true, espaciado: 1.4)
            y += 18
        }
        pintarTexto(titulo, en: CGPoint(x: r.minX, y: y), tamano: 17, peso: 800, color: tema.tituloTexto)
        y += 26

        // ── la HOJA ─────────────────────────────────────────────────────────
        let hoja = CGRect(x: r.minX, y: y, width: r.width, height: max(40, r.maxY - y))
        let camino = CGMutablePath()
        camino.addRoundedRectSeguro(in: hoja, cornerWidth: 5, cornerHeight: 5)
        ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 12,
                      color: NSColor.black.withAlphaComponent(tema.nombre == "oscuro" ? 0.55 : 0.16).cgColor)
        ctx.addPath(camino)
        ctx.setFillColor(tema.rol("card").relleno.cgColor)
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.addPath(camino)
        ctx.setStrokeColor(tema.rol("card").trazo.color.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.strokePath()

        // EL SELLO: un ancla de "esto es un documento" que no exige leer. Un
        // crítico ciego lo pidió con estas palabras: *"no lleva ninguna señal
        // mínima que ancle 'esto es markdown' si convive con otros widgets"*.
        // Monocromo y en su esquina: iconografía de apps a color es justo lo que
        // ensucia el referente.
        let sello = CGRect(x: hoja.maxX - 40, y: hoja.minY + 9, width: 31, height: 15)
        let ps = CGMutablePath()
        ps.addRoundedRectSeguro(in: sello, cornerWidth: 3, cornerHeight: 3)
        ctx.addPath(ps)
        ctx.setFillColor(tema.acento.withAlphaComponent(0.14).cgColor)
        ctx.fillPath()
        pintarTexto("md", en: CGPoint(x: sello.minX + 9, y: sello.minY + 2),
                    tamano: 9.5, peso: 800, color: tema.acento, mono: true, espaciado: 0.5)

        guard let mini = Pintor.miniatura(ruta) else {
            pintarTexto("sin documento", en: CGPoint(x: hoja.minX + 12, y: hoja.midY - 6),
                        tamano: 11, peso: 500, color: tema.pieTexto, mono: true)
            ctx.restoreGState(); return
        }

        // ── LA MINIATURA, clipada a la hoja ─────────────────────────────────
        ctx.saveGState()
        ctx.addPath(camino); ctx.clip()
        let pad = 11.0
        var cy = hoja.minY + pad
        let ancho = hoja.width - pad * 2
        let tope = hoja.maxY - pad

        for ren in mini.renglones {
            if cy > tope { break }
            switch ren {
            case .titulo(let s, let nivel):
                let tam = [11.5, 9.5, 8.0][max(0, min(2, nivel - 1))]
                cy += nivel <= 2 ? 5 : 3
                if cy > tope { break }
                pintarTexto(String(s.prefix(46)), en: CGPoint(x: hoja.minX + pad, y: cy),
                            tamano: tam, peso: 800, color: tema.tituloTexto)
                cy += tam + 4.5
                if nivel == 1 {
                    ctx.setFillColor(tema.acento.cgColor)
                    ctx.fill(CGRect(x: hoja.minX + pad, y: cy - 2.5, width: 26, height: 2))
                    cy += 4
                }
            case .linea(let f):
                ctx.setFillColor(tema.cuerpoTexto.withAlphaComponent(0.38).cgColor)
                ctx.fill(CGRect(x: hoja.minX + pad, y: cy, width: ancho * max(0.12, f), height: 2.6))
                cy += 6.4
            case .punto(let f):
                ctx.setFillColor(tema.acento.withAlphaComponent(0.6).cgColor)
                ctx.fillEllipse(in: CGRect(x: hoja.minX + pad, y: cy, width: 2.6, height: 2.6))
                ctx.setFillColor(tema.cuerpoTexto.withAlphaComponent(0.32).cgColor)
                ctx.fill(CGRect(x: hoja.minX + pad + 7, y: cy, width: (ancho - 7) * max(0.12, f), height: 2.6))
                cy += 6.4
            case .placa(let n):
                let alto = Double(n) * 5.2 + 8
                ctx.setFillColor(tema.rol("sensor").relleno.cgColor)
                let p = CGMutablePath()
                p.addRoundedRectSeguro(in: CGRect(x: hoja.minX + pad, y: cy + 2, width: ancho, height: alto),
                                 cornerWidth: 3, cornerHeight: 3)
                ctx.addPath(p); ctx.fillPath()
                ctx.setFillColor(tema.acento.withAlphaComponent(0.42).cgColor)
                for i in 0..<n {
                    let w = ancho * (0.35 + Double((i * 37) % 55) / 100)
                    ctx.fill(CGRect(x: hoja.minX + pad + 6, y: cy + 7 + Double(i) * 5.2,
                                    width: min(w, ancho - 12), height: 2))
                }
                cy += alto + 7
            }
        }
        ctx.restoreGState()

        // El velo del pie: la hoja SIGUE, y decirlo con un desvanecido es más
        // honesto que cortar el texto a media línea.
        if cy > tope {
            let alto = 26.0
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [tema.rol("card").relleno.withAlphaComponent(0).cgColor,
                                           tema.rol("card").relleno.cgColor] as CFArray,
                                  locations: [0, 1]) {
                ctx.saveGState()
                ctx.addPath(camino); ctx.clip()
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: hoja.maxY - alto),
                                       end: CGPoint(x: 0, y: hoja.maxY), options: [])
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()
    }
}
