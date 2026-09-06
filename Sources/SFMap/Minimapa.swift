import AppKit

/**
 * EL MINIMAPA, abajo a la izquierda.
 *
 * Para qué sirve de verdad: un lienzo de sistemas se dibuja alejado y se edita
 * acercado, y a 200% no hay forma de saber dónde estás dentro del mapa. El
 * minimapa es la ÚNICA superficie que responde "¿en qué parte del documento
 * estoy?" sin obligarte a alejarte y volver.
 *
 * Se pinta con formas SÓLIDAS, no con el dibujo real en miniatura: a esa escala
 * el texto es ruido y los contornos de 1.5 px desaparecen. Lo que tiene que
 * leerse es la MANCHA — dónde hay masa y dónde hay hueco.
 *
 * Y se puede pulsar: llevar la cámara a un sitio es el otro gesto que un mapa
 * promete solo con existir.
 */
final class Minimapa: NSView {
    var tema: Tema = .claro { didSet { repintar() } }
    var elementos: [Elemento] = [] { didSet { needsDisplay = true } }
    var camara = Camara() { didSet { needsDisplay = true } }
    var seleccion: Set<String> = [] { didSet { needsDisplay = true } }
    /// El tamaño de la vista del lienzo, para dibujar el rectángulo de "aquí estás".
    var vista: NSSize = .zero { didSet { needsDisplay = true } }
    var alIrA: ((CGPoint) -> Void)?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 150))
        repintar()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func repintar() {
        Estilo.tarjeta(self, tema: tema, radio: 12)
        needsDisplay = true
    }

    /// La caja del MUNDO que el minimapa representa: todo lo dibujado más lo
    /// que se ve ahora. Sin incluir la vista, panear al vacío deja el
    /// rectángulo pegado a un borde sin decir cuánto te alejaste.
    private var mundo: CGRect? {
        var r: CGRect?
        for e in elementos {
            r = r.map { $0.union(e.cajaVisual) } ?? e.cajaVisual
        }
        guard vista.width > 0 else { return r }
        let visible = CGRect(x: camara.x - vista.width / 2 / camara.zoom,
                             y: camara.y - vista.height / 2 / camara.zoom,
                             width: vista.width / camara.zoom, height: vista.height / camara.zoom)
        return r.map { $0.union(visible) } ?? visible
    }

    private func transformar(_ m: CGRect) -> (escala: Double, dx: Double, dy: Double) {
        let pad = 9.0
        let dispW = bounds.width - pad * 2, dispH = bounds.height - pad * 2
        let escala = min(dispW / max(1, m.width), dispH / max(1, m.height))
        return (escala,
                pad + (dispW - m.width * escala) / 2 - m.minX * escala,
                pad + (dispH - m.height * escala) / 2 - m.minY * escala)
    }

    /// El marco de la mano izquierda: la pieza de metal.
    private let MARCO: CGFloat = 5

    /**
     * BISEL FUERA, PANTALLA DENTRO.
     *
     * De todas las superficies del cromo, esta es la única que literalmente ES
     * una pantalla: enseña el documento en miniatura. Así que se construye como
     * lo que es —una placa de titanio con un visor hundido— en vez de como una
     * tarjeta blanca con un dibujo encima.
     *
     * El visor lleva el color del LIENZO, no el del cromo, y por eso el
     * minimapa se lee de un vistazo como "esto es el mapa" y no como "otro
     * panel más": comparte piel con lo que representa.
     */
    override func draw(_ dirty: NSRect) {
        Estilo.pintarBisel(self, tema, radio: 12)
        guard let c = NSGraphicsContext.current?.cgContext else { return }

        let visor = bounds.insetBy(dx: MARCO, dy: MARCO)
        let caminoVisor = CGPath(roundedRect: visor, cornerWidth: 7, cornerHeight: 7, transform: nil)
        // La MISMA pieza que el rótulo de zoom de la barra: lo único que cambia
        // es que aquí lo hundido enseña el lienzo, así que lleva su color.
        Estilo.pintarVisor(self, tema, en: visor, relleno: tema.lienzo)

        guard let m = mundo else { return }
        // Todo el mapa vive DENTRO del visor: sin recorte, una caja lejana se
        // pintaba encima del marco y se salía de la placa.
        c.saveGState()
        defer { c.restoreGState() }
        c.addPath(caminoVisor); c.clip()
        let t = transformar(m)
        func aVista(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * t.escala + t.dx, y: r.minY * t.escala + t.dy,
                   width: max(1.5, r.width * t.escala), height: max(1.5, r.height * t.escala))
        }

        for e in elementos.sorted(by: { $0.z < $1.z }) {
            let r = aVista(e.cajaVisual)
            guard r.maxX > 0, r.minX < bounds.width, r.maxY > 0, r.minY < bounds.height else { continue }
            switch e.tipo {
            case "connector":
                // Los conectores como una línea fina: sin ellos la mancha se ve
                // como islas sueltas y el mapa deja de parecerse al diagrama.
                let pts = e.ruta
                guard pts.count >= 2 else { continue }
                c.setStrokeColor(tema.pieTexto.withAlphaComponent(0.35).cgColor)
                c.setLineWidth(0.6)
                c.move(to: CGPoint(x: pts[0].x * t.escala + t.dx, y: pts[0].y * t.escala + t.dy))
                for p in pts.dropFirst() {
                    c.addLine(to: CGPoint(x: p.x * t.escala + t.dx, y: p.y * t.escala + t.dy))
                }
                c.strokePath()
            case "frame":
                let tin = tema.tintes[e.tinte] ?? tema.tintes["neutro"]!
                let camino = CGMutablePath()
                camino.addRoundedRect(in: r, cornerWidth: 2, cornerHeight: 2)
                c.addPath(camino); c.setFillColor(tin.relleno.cgColor); c.fillPath()
                c.addPath(camino); c.setStrokeColor(tin.trazo.withAlphaComponent(0.6).cgColor)
                c.setLineWidth(0.8); c.strokePath()
            default:
                let camino = CGMutablePath()
                camino.addRoundedRect(in: r, cornerWidth: 1.5, cornerHeight: 1.5)
                c.addPath(camino)
                let elegido = seleccion.contains(e.id)
                c.setFillColor((elegido ? tema.acento : tema.rol(e.rol).trazo.color.withAlphaComponent(0.55)).cgColor)
                c.fillPath()
            }
        }

        // El rectángulo de "aquí estás".
        guard vista.width > 0 else { return }
        let visible = aVista(CGRect(x: camara.x - vista.width / 2 / camara.zoom,
                                    y: camara.y - vista.height / 2 / camara.zoom,
                                    width: vista.width / camara.zoom, height: vista.height / camara.zoom))
        c.setStrokeColor(tema.acento.cgColor)
        c.setLineWidth(1.5)
        c.setFillColor(tema.acento.withAlphaComponent(0.10).cgColor)
        let camino = CGMutablePath()
        camino.addRoundedRect(in: visible.insetBy(dx: 0.75, dy: 0.75), cornerWidth: 2, cornerHeight: 2)
        c.addPath(camino); c.fillPath()
        c.addPath(camino); c.strokePath()
    }

    override func mouseDown(with e: NSEvent) { irA(e) }
    override func mouseDragged(with e: NSEvent) { irA(e) }

    private func irA(_ e: NSEvent) {
        guard let m = mundo else { return }
        let t = transformar(m)
        let p = convert(e.locationInWindow, from: nil)
        alIrA?(CGPoint(x: (p.x - t.dx) / t.escala, y: (p.y - t.dy) / t.escala))
    }
}
