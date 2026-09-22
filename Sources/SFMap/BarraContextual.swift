import AppKit

/// Una muestra de color de la paleta. `color` nulo = manda el rol/tema.
struct Muestra { var id: String; var color: String?; var etiqueta: String }

/**
 * LA PALETA DE LA MANO.
 *
 * Dos decisiones que no son cosmeticas:
 *
 * 1. La primera casilla NUNCA es un color: es "lo que diga el tema" — el unico
 *    valor que sobrevive un cambio de claro a oscuro. Todo lo demas es un
 *    literal, y un literal es una EXCEPCION que la mano firma. Sin esa casilla
 *    no habria forma de DESHACER una eleccion de color, solo de sustituirla.
 *
 * 2. Los colores de marca van PRIMERO y con nombre. Miro tiene ahi un
 *    "+ Agregar colores" vacio que nadie llena nunca; los de Daniel ya existen
 *    y estar en la primera fila es lo que hace que un diagrama suyo se vea suyo
 *    sin disciplina.
 *
 * Los tonos generales son de rango MEDIO a proposito: tienen que leerse sobre
 * el lienzo claro Y sobre el oscuro, porque un literal no cambia con el tema.
 */
enum Paletas {
    static let sinColor = Muestra(id: "tema", color: nil, etiqueta: "Del tema (sigue al claro/oscuro)")
    static let marca = [Muestra(id: "morado", color: "#8C27F1", etiqueta: "Morado de marca"),
                        Muestra(id: "oro", color: "#ff9101", etiqueta: "Oro de marca")]

    static let trazos: [Muestra] = zip(
        ["rojo","naranja","ambar","lima","verde","turquesa","cian","azul","indigo",
         "violeta","rosa","carmin","cafe","pizarra","grafito","negro","gris","blanco"],
        ["#e5484d","#f76b15","#e0a90a","#8ab917","#26a769","#0eaa9b","#0d9bd4","#3a6ff0","#6355e0",
         "#9333ea","#e2429b","#c02456","#95653b","#64748b","#3f3f4a","#101014","#a8a8b3","#ffffff"]
    ).map { Muestra(id: $0.0, color: $0.1, etiqueta: $0.0.capitalized) }

    /// Los mismos tonos ACLARADOS, para rellenos: uno saturado se come el texto
    /// que lleva encima y reprueba el contraste.
    static let rellenos: [Muestra] = zip(
        ["rojo","naranja","ambar","lima","verde","turquesa","cian","azul","indigo",
         "violeta","rosa","carmin","cafe","pizarra","grafito","negro","gris","blanco"],
        ["#fde8e8","#feeade","#fdf3d6","#eef7d8","#e0f5ea","#dcf4f2","#ddf0fa","#e4ecfd","#e7e5fb",
         "#f3e6fe","#fce3f0","#fbe0e8","#f2e8df","#e9edf2","#e4e4e8","#d6d6dc","#f0f0f3","#ffffff"]
    ).map { Muestra(id: $0.0, color: $0.1, etiqueta: $0.0.capitalized) }

    /// Los tonos de RESALTADO: translucidos, para que el texto siga encima.
    static let resaltados: [Muestra] = zip(
        ["amarillo","verde","cian","rosa","morado","oro"],
        ["rgba(255,224,80,.62)","rgba(120,231,160,.55)","rgba(120,210,255,.55)",
         "rgba(255,150,205,.55)","rgba(180,130,255,.50)","rgba(255,175,60,.55)"]
    ).map { Muestra(id: $0.0, color: $0.1, etiqueta: $0.0.capitalized) }
}

/// Un deslizador que el historial ve como UN cambio, no como cuarenta.
///
/// `super.mouseDown` de AppKit BLOQUEA hasta soltar, asi que el gesto se abre y
/// se cierra alrededor de esa llamada. En el navegador hubo que colgar un
/// listener de la ventana para lo mismo — y la primera version no lo hizo, con
/// lo que arrastrar el grosor de 1.5 a 6 dejaba DIEZ entradas en el historial.
final class Deslizador: NSView {
    var minimo = 0.0
    var maximo = 1.0
    var valor = 0.5 { didSet { needsDisplay = true } }
    var tema: Tema = .claro { didSet { needsDisplay = true } }
    var paso: Double = 0
    var alMover: ((Double) -> Void)?
    var alAbrir: (() -> Void)?
    var alCerrar: (() -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ r: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        let y = bounds.midY, alto = 4.0
        let riel = NSRect(x: 7, y: y - alto / 2, width: bounds.width - 14, height: alto)
        let camino = CGMutablePath()
        camino.addRoundedRect(in: riel, cornerWidth: 2, cornerHeight: 2)
        c.addPath(camino); c.setFillColor(tema.rol("card").trazo.color.cgColor); c.fillPath()
        // Clamp SIEMPRE: un valor fuera de rango (el radio 999 de un rol viejo)
        // pintaba la barra 15x más ancha que el riel — la "línea que se sale".
        let t = maximo > minimo ? max(0, min(1, (valor - minimo) / (maximo - minimo))) : 0
        let lleno = NSRect(x: riel.minX, y: riel.minY, width: riel.width * t, height: alto)
        let c2 = CGMutablePath(); c2.addRoundedRect(in: lleno, cornerWidth: 2, cornerHeight: 2)
        c.addPath(c2); c.setFillColor(tema.acento.cgColor); c.fillPath()
        let cx = riel.minX + riel.width * t
        c.setFillColor(tema.rol("card").relleno.cgColor)
        c.setStrokeColor(tema.acento.cgColor)
        c.setLineWidth(2)
        let botonRect = NSRect(x: cx - 6.5, y: y - 6.5, width: 13, height: 13)
        c.fillEllipse(in: botonRect); c.strokeEllipse(in: botonRect)
    }

    private func valorEn(_ p: NSPoint) -> Double {
        let riel = bounds.width - 14
        var t = riel > 0 ? Double((p.x - 7) / riel) : 0
        t = max(0, min(1, t))
        var v = minimo + t * (maximo - minimo)
        if paso > 0 { v = (v / paso).rounded() * paso }
        return v
    }

    override func mouseDown(with e: NSEvent) {
        alAbrir?()
        valor = valorEn(convert(e.locationInWindow, from: nil))
        alMover?(valor)
        // Bucle propio: `NSView` no rastrea solo, y usar `NSSlider` traeria el
        // aspecto del sistema justo en la barra que mas se mira.
        var siguiendo = true
        while siguiendo, let ev = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if ev.type == .leftMouseUp { siguiendo = false; break }
            valor = valorEn(convert(ev.locationInWindow, from: nil))
            alMover?(valor)
        }
        alCerrar?()
    }
}

/**
 * Una cuadricula de muestras de color — y, debajo, TODOS los demas.
 *
 * Las muestras son la paleta de RESTRICCION y siguen mandando: se abarcan de un
 * vistazo y se eligen sin apuntar. El espectro es la valvula de escape, y desde
 * el 30 ago 2026 la monta cualquier panel que enseñe color, no solo el lapiz.
 */
final class VistaPaleta: NSView {
    var tema: Tema = .claro { didSet { needsDisplay = true } }
    var muestras: [Muestra] = []
    var valor: String? { didSet { needsDisplay = true; alCambiarValor?(valor) } }
    /// Para que el campo hex diga siempre lo mismo que la paleta: se elige del
    /// cuadro y el texto tiene que seguir, o el panel dice dos cosas a la vez.
    var alCambiarValor: ((String?) -> Void)?
    var redondo = false
    var conMarca = true
    /// Las dos barras del arcoiris debajo de la cuadricula.
    var conEspectro = false
    /**
     * El color que se ESTA VIENDO cuando `valor` es nil.
     *
     * Sin esto la barra de luz partiria del negro en cuanto el elemento sigue a
     * su rol, y el primer arrastre daria un salto en vez de un ajuste. El panel
     * ya calcula el efectivo para pintar el icono de la barra: se reusa.
     */
    var efectivo: NSColor?
    /// Si esta puesto, el espectro emite `rgba(...)` con este alfa en vez de
    /// hex: es lo que pide el RESALTADO, que tiene que dejar leer el texto.
    var alfa: Double?
    /// Bajo que nombre recuerda ESTE panel los colores que se eligieron a mano.
    /// Nulo = no recuerda (la paleta no tiene fila de recientes).
    var ambito: String?
    /// Donde empieza el cuadro cuando el elemento todavia sigue a su rol y no
    /// hay saturacion de la que partir: x = saturacion, y = 1 - brillo. En un
    /// relleno se quiere un pastel; en un trazo, un tono vivo.
    var puntoNuevo = NSPoint(x: 0.85, y: 0.15)
    /// El delegado del campo hex, sostenido aqui: `NSTextField` no lo retiene.
    var puenteCampo: AnyObject?
    var alElegir: ((String?) -> Void)?
    /// Un arrastre por el espectro es UN cambio para el historial, no cuarenta.
    /// Misma regla que el `Deslizador`, y por el mismo motivo.
    var alAbrirGesto: (() -> Void)?
    var alCerrarGesto: ((String) -> Void)?

    override var isFlipped: Bool { true }
    /// Qué superficie del espectro tiene agarrada la mano ahora mismo.
    private var zonaViva: Espectro.Zona?

    /**
     * ⚠️ LAS CASILLAS SE CALCULAN, IGUAL QUE LAS BARRAS.
     *
     * Estaban en una lista que rellenaba `draw`, y por eso un panel recién
     * abierto no respondía al primer clic hasta haberse pintado. En la app no
     * se nota —siempre se pinta antes de que la mano llegue— y por eso el fallo
     * vivió meses: lo caza la escena, que pulsa sin esperar. Un control cuyo
     * hit-test depende de haberse dibujado miente mientras no lo mires.
     */
    private var casillas: [(r: NSRect, m: Muestra)] {
        var out: [(NSRect, Muestra)] = []
        var y: CGFloat = 0
        if conMarca {
            out.append((NSRect(x: 0, y: 0, width: 24, height: 24), Paletas.sinColor))
            for (i, m) in Paletas.marca.enumerated() {
                out.append((NSRect(x: 33 + CGFloat(i) * 30, y: 0, width: 24, height: 24), m))
            }
            y = 34
        }
        for (i, m) in muestras.enumerated() {
            out.append((NSRect(x: CGFloat(i % 6) * 30, y: y + CGFloat(i / 6) * 30,
                               width: 24, height: 24), m))
        }
        if let ambito {
            let yR = cajaRecientes.minY + 16
            for (i, hx) in Recientes.lista(ambito).enumerated() {
                out.append((NSRect(x: CGFloat(i) * 30, y: yR, width: 24, height: 24),
                            Muestra(id: hx, color: hx, etiqueta: hx)))
            }
        }
        return out
    }

    /**
     * ⚠️ LA GEOMETRÍA DEL ESPECTRO SE CALCULA, NO SE RECUERDA.
     *
     * La paleta del lápiz guarda sus dos barras en variables que rellena
     * `draw`, y por eso su escena de verificación tiene que forzar un pintado
     * antes de poder pulsarlas. Un control cuyo hit-test depende de haberse
     * dibujado es un control que miente mientras no lo mires. Aquí sale de
     * `bounds`, que existe desde que la vista tiene marco.
     */
    /// El ancho útil: seis casillas de 30 menos el hueco que sobra a la derecha.
    static let UTIL: CGFloat = 6 * 30 - 6

    private var yEspectro: CGFloat { (conMarca ? 34 : 0) + CGFloat((muestras.count + 5) / 6) * 30 }
    private var cajas: (cuadro: NSRect, tono: NSRect) {
        Espectro.cajas(x: 0, y: yEspectro, ancho: Self.UTIL)
    }
    /// Dónde cae el cuadro de saturación × brillo.
    var cajaCuadro: NSRect { conEspectro ? cajas.cuadro : .zero }
    /// Dónde cae la barra del arcoíris, para quien tenga que pulsarla.
    var cajaTono: NSRect { conEspectro ? cajas.tono : .zero }
    /// La fila del campo hex y el cuentagotas.
    var cajaExacto: NSRect {
        guard conEspectro else { return .zero }
        return NSRect(x: 0, y: yEspectro + Espectro.ALTO + 8, width: Self.UTIL, height: 24)
    }
    /// El botón que roba un color de cualquier punto de la pantalla.
    var cajaGotero: NSRect {
        guard conEspectro else { return .zero }
        return NSRect(x: Self.UTIL - 28, y: cajaExacto.minY, width: 28, height: 24)
    }
    /// Dónde empieza la fila de los colores que Daniel ya eligió a mano.
    var cajaRecientes: NSRect {
        guard ambito != nil else { return .zero }
        return NSRect(x: 0, y: yEspectro + (conEspectro ? Espectro.ALTO + 32 : 0),
                      width: Self.UTIL, height: Recientes.ALTO)
    }

    static func alto(_ n: Int, conMarca: Bool, conEspectro: Bool = false,
                     conRecientes: Bool = false) -> CGFloat {
        let filas = CGFloat((n + 5) / 6)
        return (conMarca ? 34 : 0) + filas * 30
             + (conEspectro ? Espectro.ALTO + 32 : 0)   // + la fila del hex y el gotero
             + (conRecientes ? Recientes.ALTO : 0)
    }

    /// El color del que parte el espectro: el elegido, o el que se ve.
    private var base: NSColor {
        valor.flatMap { NSColor(hex: $0) } ?? efectivo ?? tema.cuerpoTexto
    }

    override func draw(_ dirty: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        for (r, m) in casillas { casilla(c, r, m) }
        if conMarca {
            c.setFillColor(tema.rol("card").trazo.color.cgColor)
            c.fill(NSRect(x: 27, y: 2, width: 1, height: 20))
            let etq = NSAttributedString(string: "MARCA", attributes: [
                .font: Estilo.fuente(9, 700), .foregroundColor: tema.pieTexto, .kern: 0.5])
            etq.draw(at: NSPoint(x: 33 + CGFloat(Paletas.marca.count) * 30 + 2, y: 7))
        }
        // El ancho del espectro es el de la CUADRICULA (seis casillas de 30
        // menos el hueco final), no el del marco: alinearlo con la ultima
        // columna es lo que hace que se lea como parte de la misma paleta.
        if conEspectro {
            Espectro.pintar(c, cuadro: cajas.cuadro, tono: cajas.tono, base: base,
                            hayColor: valor != nil, tema: tema)
            pintarExacto(c)
        }
        guard let ambito else { return }
        /*
         * LA FILA DE LOS TUYOS.
         *
         * El hueco se reserva SIEMPRE que el panel recuerde, aunque esté vacío.
         * Si apareciera al guardar el primero, la fila nacería FUERA de la
         * tarjeta: el marco de la vista ya está puesto cuando el panel se abre y
         * no vuelve a medirse. Vacío se ve el rótulo solo, que además dice qué
         * va a pasar ahí.
         */
        let etq = NSAttributedString(
            string: Recientes.lista(ambito).isEmpty ? "TUS COLORES · elige del cuadro" : "TUS COLORES",
            attributes: [.font: Estilo.fuente(9, 700), .foregroundColor: tema.pieTexto, .kern: 0.5])
        etq.draw(at: NSPoint(x: 1, y: cajaRecientes.minY + 2))
    }

    /**
     * LA FILA DEL COLOR EXACTO: escribirlo, o robarlo de la pantalla.
     *
     * El cuadro sirve para BUSCAR un color; estos dos para PONER uno que ya
     * sabes cuál es. El campo es para cuando lo traes escrito (una marca, un
     * token del sistema de diseño) y el gotero para cuando está delante de ti
     * —en una miniatura, en una captura— y no tiene nombre.
     */
    private func pintarExacto(_ c: CGContext) {
        let campo = NSRect(x: 0, y: cajaExacto.minY, width: Self.UTIL - 34, height: 24)
        let cp = CGMutablePath(); cp.addRoundedRect(in: campo, cornerWidth: 7, cornerHeight: 7)
        c.addPath(cp); c.setFillColor(tema.lienzo.cgColor); c.fillPath()
        c.addPath(cp); c.setStrokeColor(tema.rol("card").trazo.color.cgColor)
        c.setLineWidth(1); c.strokePath()
        // El texto lo pinta el NSTextField que vive encima; aquí va solo su caja.

        let g = cajaGotero
        let gp = CGMutablePath(); gp.addRoundedRect(in: g, cornerWidth: 7, cornerHeight: 7)
        c.addPath(gp); c.setFillColor(tema.lienzo.cgColor); c.fillPath()
        c.addPath(gp); c.setStrokeColor(tema.rol("card").trazo.color.cgColor)
        c.setLineWidth(1); c.strokePath()
        // Una gota con su punta arriba: un círculo a secas se lee como otra
        // muestra de color, que es justo lo que este botón NO es.
        let cx = g.midX, cy = g.midY + 2, r: CGFloat = 4.5
        let gota = CGMutablePath()
        gota.move(to: CGPoint(x: cx, y: cy - r * 2.1))
        gota.addQuadCurve(to: CGPoint(x: cx + r, y: cy), control: CGPoint(x: cx + r * 0.9, y: cy - r))
        gota.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: .pi, clockwise: false)
        gota.addQuadCurve(to: CGPoint(x: cx, y: cy - r * 2.1), control: CGPoint(x: cx - r * 0.9, y: cy - r))
        c.addPath(gota)
        c.setStrokeColor(tema.cuerpoTexto.cgColor); c.setLineWidth(1.4); c.strokePath()
    }

    private func casilla(_ c: CGContext, _ r: NSRect, _ m: Muestra) {
        let camino = CGMutablePath()
        let radio: CGFloat = redondo ? 12 : 7
        camino.addRoundedRect(in: r, cornerWidth: radio, cornerHeight: radio)
        c.addPath(camino)
        c.setFillColor((m.color.flatMap { NSColor(hex: $0) } ?? tema.rol("card").relleno).cgColor)
        c.fillPath()
        let activo = valor == m.color
        c.addPath(camino)
        c.setStrokeColor((activo ? tema.acento : tema.rol("card").trazo.color).cgColor)
        c.setLineWidth(activo ? 2.5 : 1)
        c.strokePath()
        // La casilla del tema lleva una diagonal: es la unica que NO es un color
        // y sin marca se confunde con "blanco".
        if m.color == nil {
            c.setStrokeColor(tema.pieTexto.cgColor); c.setLineWidth(2)
            c.move(to: CGPoint(x: r.minX + 5, y: r.maxY - 5))
            c.addLine(to: CGPoint(x: r.maxX - 5, y: r.minY + 5))
            c.strokePath()
        }
    }

    /// El texto de un color en el formato que guarda este campo.
    func texto(_ c: NSColor) -> String {
        alfa.map { Espectro.rgba(c, $0) } ?? Espectro.hex(c)
    }

    /// El color que toca el punto dentro de la zona agarrada.
    func colorEn(_ p: NSPoint, _ z: Espectro.Zona? = nil) -> String? {
        guard conEspectro,
              let zona = z ?? Espectro.zona(p, cuadro: cajas.cuadro, tono: cajas.tono)
        else { return nil }
        return texto(Espectro.color(p, zona: zona, cuadro: cajas.cuadro, tono: cajas.tono,
                                    base: base, hayColor: valor != nil, puntoNuevo: puntoNuevo))
    }

    /**
     * ⭐ ROBAR UN COLOR DE CUALQUIER PUNTO DE LA PANTALLA.
     *
     * Es la respuesta corta a "el color exacto": el que quieres muchas veces ya
     * está delante —en una miniatura, en una captura, en otro lienzo— y no tiene
     * nombre ni cae en ninguna casilla. `NSColorSampler` es la lupa del sistema:
     * sin ventana propia, sin permisos, y devuelve el píxel exacto.
     *
     * Se guarda en "tus colores" como cualquier elección a mano: robarlo cuesta
     * el mismo gesto que buscarlo y perderlo dolería igual.
     */
    func robarDeLaPantalla() {
        NSColorSampler().show { [weak self] c in
            guard let self, let c else { return }
            let t = self.texto(c)
            self.valor = t
            self.alElegir?(t)
            if let a = self.ambito { Recientes.recordar(t, en: a) }
            self.needsDisplay = true
        }
    }

    /// Un color escrito a mano. Devuelve si valía.
    @discardableResult
    func escribir(_ crudo: String) -> Bool {
        guard let c = Espectro.leer(crudo) else { return false }
        let t = texto(c)
        valor = t
        alElegir?(t)
        if let a = ambito { Recientes.recordar(t, en: a) }
        needsDisplay = true
        return true
    }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if let hit = casillas.first(where: { $0.r.insetBy(dx: -3, dy: -3).contains(p) }) {
            valor = hit.m.color
            alElegir?(hit.m.color); return
        }
        if conEspectro, cajaGotero.contains(p) { robarDeLaPantalla(); return }
        guard let z = Espectro.zona(p, cuadro: cajas.cuadro, tono: cajas.tono),
              let c = colorEn(p, z) else { return }
        zonaViva = z
        alAbrirGesto?()
        valor = c
        alElegir?(c)
    }

    /// Arrastrar cambia el color EN VIVO: elegir un color es buscarlo, no
    /// acertarlo a la primera.
    override func mouseDragged(with e: NSEvent) {
        guard let z = zonaViva,
              let c = colorEn(convert(e.locationInWindow, from: nil), z) else { return }
        valor = c
        alElegir?(c)
    }

    override func mouseUp(with e: NSEvent) {
        guard zonaViva != nil else { return }
        zonaViva = nil
        // ⚠️ SE GUARDA AL SOLTAR. Buscar un color pasa por cuarenta tonos que no
        // quisiste; el que quisiste es donde levantaste el dedo.
        if let ambito, let v = valor, !muestras.contains(where: { $0.color == v }) {
            Recientes.recordar(v, en: ambito)
            needsDisplay = true
        }
        alCerrarGesto?("color")
    }
}

/// Un campo numerico con escalera, para el tamaño de letra.
final class CampoNumero: NSView {
    var tema: Tema = .claro { didSet { repintar() } }
    var valor: Double? { didSet { campo.stringValue = valor.map { "\(Int($0))" } ?? "" } }
    var alCambiar: ((Double) -> Void)?
    private let campo = NSTextField()
    /// El recuadro es una vista APARTE: dibujarlo sobre el propio campo obliga a
    /// que el texto se centre dentro de un control que no centra en vertical.
    private let marco = NSView(frame: NSRect(x: 0, y: 0, width: 38, height: 29))
    private let arriba = BotonPlano(icono: nil, ancho: 20, alto: 15)
    private let abajo = BotonPlano(icono: nil, ancho: 20, alto: 15)

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 58, height: 28))
        /*
         * El número va CENTRADO de verdad.
         *
         * `alignment = .center` centra en horizontal; en vertical un NSTextField
         * sin bisel apoya el texto en la línea base y queda alto dentro de su
         * caja. Se compensa con la altura de la caja y el propio campo más bajo
         * y centrado dentro de ella — que es lo que el ojo mide contra los
         * botones vecinos, todos de 32.
         */
        campo.frame = NSRect(x: 0, y: 5, width: 38, height: 19)
        campo.alignment = .center
        campo.usesSingleLineMode = true
        campo.cell?.wraps = false
        campo.font = Estilo.fuente(12, 500)
        campo.isBordered = false
        campo.drawsBackground = true
        campo.focusRingType = .none
        campo.placeholderString = "—"
        campo.target = self
        campo.action = #selector(escribio)
        addSubview(marco)
        addSubview(campo)
        arriba.image = Icono.chevronArriba
        abajo.image = Icono.chevronAbajo
        arriba.frame = NSRect(x: 38, y: 14, width: 20, height: 15)
        abajo.frame = NSRect(x: 38, y: -1, width: 20, height: 15)
        arriba.alPulsar = { [weak self] in self?.escalon(1) }
        abajo.alPulsar = { [weak self] in self?.escalon(-1) }
        addSubview(arriba); addSubview(abajo)
        repintar()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func escalon(_ d: Double) {
        // La escalera sube y baja DE UNO. Un menu de tallas obliga a aceptar un
        // salto de 20 a 24 cuando lo que querias era 22.
        let v = max(6, min(400, (valor ?? 20) + d))
        valor = v
        alCambiar?(v)
    }

    @objc private func escribio() {
        let n = Double(campo.stringValue.filter(\.isNumber)) ?? 0
        guard n >= 6, n <= 400 else { campo.stringValue = valor.map { "\(Int($0))" } ?? ""; return }
        valor = n
        alCambiar?(n)
    }

    private func repintar() {
        campo.textColor = tema.cuerpoTexto
        campo.backgroundColor = .clear
        campo.drawsBackground = false
        marco.wantsLayer = true
        marco.layer?.cornerRadius = 7
        marco.layer?.cornerCurve = .continuous
        marco.layer?.backgroundColor = NSColor.clear.cgColor
        marco.layer?.borderWidth = 0
        marco.layer?.borderColor = tema.rol("card").trazo.color.cgColor
        arriba.plano = true; abajo.plano = true
        arriba.tema = tema; abajo.tema = tema
    }
}

/**
 * LA BARRA CONTEXTUAL.
 *
 * Reemplaza a las dos barras FIJAS arriba al centro que tenia la primera
 * version. Dos problemas, los dos señalados por Daniel con capturas de Miro al
 * lado:
 *
 *  1. FIJA arriba = tienes que mirar a otro sitio para editar lo que tienes
 *     delante. Esta va anclada DEBAJO del elemento, se mueve con el, y salta
 *     arriba cuando no cabe.
 *  2. DOS barras = el mismo elemento se edita en dos sitios y hay que aprenderse
 *     cual controla que. Una sola, con separadores.
 *
 * QUE SE TOMA DE MIRO Y QUE NO:
 *   · SE TOMA la gramatica de los botones (relleno lleno / contorno anillo, el
 *     tamaño con escalera) porque es literal y no hay que aprenderla.
 *   · NO se toma el boton de comentario: sin multijugador seria una capacidad
 *     prometida y vacia — el pecado que el v3 cometio diez veces.
 *   · SE AGREGA el ROL, que Miro no puede tener: es lo que deja que un cambio
 *     de tema repinte el lienzo entero. Un color suelto no sobrevive el cambio.
 *   · SE AGREGA ACOMODAR, que es el motor de layout hecho gesto.
 */
final class BarraContextual: NSView {
    static let ALTO: CGFloat = 42
    /// Aire entre la barra y el elemento. Pegada se lee como parte del dibujo.
    static let AIRE: CGFloat = 14

    var tema: Tema = .claro
    var seleccion: [Elemento] = []

    // Los lazos hacia el documento.
    var alCambiar: ((_ patch: [String: Json?], _ solo: ((Elemento) -> Bool)?) -> Void)?
    var alColor: ((_ campos: [String: String?]) -> Void)?
    var alTrazo: ((_ estilo: String?, _ grosor: Double?, _ radio: Double?) -> Void)?
    var alTipografia: ((Tipografia) -> Void)?
    var alAbrirGesto: (() -> Void)?
    var alCerrarGesto: ((String) -> Void)?
    var alBorrar: (() -> Void)?
    var alDuplicar: (() -> Void)?
    var alFrente: (() -> Void)?
    var alFondo: (() -> Void)?
    var alAdelante: (() -> Void)?
    var alAtras: (() -> Void)?
    var alRecortar: (() -> Void)?
    var alAgrupar: (() -> Void)?
    var alDesagrupar: (() -> Void)?
    var alAcomodar: (() -> Void)?
    var acomodarBloqueados = 0
    var alAnclaje: ((Bool) -> Void)?

    private var panel: NSView?
    private var abierto: String?

    /// ¿Hay un panel de estilo abierto? Lo miran las pruebas: el fallo del 25
    /// ago era invisible desde fuera (el panel se cerraba y se volvía a poder
    /// abrir, así que "funcionaba"), y solo se ve preguntando por este estado
    /// ANTES y DESPUÉS de un cambio.
    var hayPanelAbierto: Bool { panel != nil }
    var panelAbierto: String? { abierto }

    /// Abre un panel por su id, sin pasar por el clic. Solo para escenas: el
    /// gesto real vale más, pero abrir el panel de trazo requiere pulsar un
    /// botón cuya posición depende de qué elementos hay seleccionados.
    func abrirPanelDePrueba(_ id: String) {
        switch id {
        case "trazo", "contorno": abrirPanelContorno()   // el de ESTILO: grosor, esquinas, opacidad y color
        case "mas": abrirPanelMas()                      // el de "…": apilado, agrupar, duplicar, eliminar
        default: break
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    override func draw(_ r: NSRect) {
        let forma = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        (tema.nombre == "oscuro" ? NSColor(white: 0.14, alpha: 1) : .white).setFill()
        forma.fill()
        tema.cuerpoTexto.withAlphaComponent(0.10).setStroke()
        forma.lineWidth = 1
        forma.stroke()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// La barra se traga sus propios clics: sin esto, pulsarla panea el lienzo.
    override func hitTest(_ p: NSPoint) -> NSView? {
        let local = convert(p, from: superview)
        guard bounds.contains(local) else { return nil }
        return super.hitTest(p) ?? self
    }

    func cerrarPanel() { panel?.removeFromSuperview(); panel = nil; abierto = nil }

    // ── lectura de la seleccion ─────────────────────────────────────────────

    /**
     * El valor que la barra ENSEÑA para un atributo.
     *
     * Si no coincide, `nil`: un control en blanco significa "hay varios
     * valores", nunca "es este".
     *
     * ⚠️ RECIBE SOBRE QUE PREGUNTAR. La primera version preguntaba siempre sobre
     * TODA la seleccion, y un conector no tiene forma ni rol — asi que elegir
     * tres figuras identicas mas sus dos flechas hacia decir "Varios" en los dos
     * botones. Se vio en una captura: el modelo estaba bien y lo que mentia era
     * la pantalla.
     */
    private func comun<T: Equatable>(_ sobre: [Elemento], _ f: (Elemento) -> T?) -> T? {
        guard let primero = sobre.first else { return nil }
        let v = f(primero)
        return sobre.allSatisfy { f($0) == v } ? v : nil
    }

    private var figuras: [Elemento] { seleccion.filter { $0.tipo == "shape" } }
    private var secciones: [Elemento] { seleccion.filter { $0.tipo == "frame" } }
    private var conTrazo: [Elemento] { figuras + secciones }
    private var conLetras: [Elemento] { seleccion.filter { $0.tipo == "shape" || $0.tipo == "text" } }
    /// ¿Se ofrecen los controles de texto?
    ///
    /// Una figura VACÍA también los ofrece: acabas de crearla, el cursor está
    /// dentro esperando, y esconder la tipografía justo cuando vas a escribir
    /// obliga a teclear, salir, y volver a entrar para elegir la letra.
    private var conTexto: Bool {
        seleccion.contains { $0.tieneTexto || ["shape", "text", "frame"].contains($0.tipo) }
    }

    /// El estilo comun de la seleccion. El tamaño que se ENSEÑA es el MAYOR: es
    /// el que el ojo lee como "el tamaño" y el que la escala usa de referencia.
    private var estiloComun: (familia: String?, peso: Double?, cursiva: Bool?, subrayado: Bool?,
                              tamano: Double?, alineacion: String?) {
        var todos = seleccion.flatMap(\.estilos)
        // Figura recién creada, sin partes de texto todavía: se enseña el estilo
        // con el que va a nacer. Un control en blanco significa "valores
        // distintos", y sobre una figura vacía eso sería mentira.
        if todos.isEmpty, seleccion.contains(where: { ["shape", "text", "frame"].contains($0.tipo) }) {
            todos = [Crear.ESTILO_FIGURA]
        }
        let alineaciones = seleccion.compactMap { e -> String? in
            (e.tipo == "text" || (e.tipo == "shape" && e.tieneTexto)) ? e.alineacion : nil
        }
        func igual<T: Equatable>(_ f: (EstiloTexto) -> T) -> T? {
            guard let p = todos.first else { return nil }
            let v = f(p)
            return todos.allSatisfy { f($0) == v } ? v : nil
        }
        return (igual { $0.familia }, igual { $0.peso }, igual { $0.cursiva }, igual { $0.subrayado },
                todos.map(\.tamano).max(),
                alineaciones.allSatisfy { $0 == alineaciones.first } ? alineaciones.first : nil)
    }

    // ── construccion ────────────────────────────────────────────────────────

    private func nuevoBoton(_ icono: NSImage?, texto: String = "", activo: Bool = false,
                            ancho: CGFloat? = nil, globo: String? = nil,
                            _ accion: @escaping () -> Void) -> BotonPlano {
        let w = ancho ?? (texto.isEmpty ? 32 : max(32, texto.size(withAttributes: [.font: Estilo.fuente(12)]).width + 24))
        let b = BotonPlano(icono: icono, titulo: texto, ancho: w, alto: 32)
        b.plano = true
        if !texto.isEmpty { b.attributedTitle = NSAttributedString(string: texto, attributes: [.font: Estilo.fuente(12, 500)]) }
        b.tema = tema
        b.activo = activo
        b.globo = globo
        b.alPulsar = accion
        return b
    }

    private func separador() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 7, height: 20))
        v.wantsLayer = true
        let l = NSView(frame: NSRect(x: 3, y: 0, width: 1, height: 20))
        l.wantsLayer = true
        l.layer?.backgroundColor = tema.rol("card").trazo.color.withAlphaComponent(0.7).cgColor
        v.addSubview(l)
        return v
    }

    private func etiqueta(_ s: String, _ tam: CGFloat = 12, _ peso: CGFloat = 600, color: NSColor? = nil) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = Estilo.fuente(tam, peso)
        t.textColor = color ?? tema.pieTexto
        t.sizeToFit()
        return t
    }

    private func rotulo(_ s: String) -> NSTextField {
        let t = NSTextField(labelWithString: s.uppercased())
        t.font = Estilo.fuente(10, 700)
        t.textColor = tema.pieTexto
        t.sizeToFit()
        return t
    }

    /// Reconstruye la barra entera para la seleccion actual y la coloca.
    /// Qué elementos tenía la barra la última vez que se armó. Si la selección
    /// no cambió, reconstruir es tirar y rehacer lo mismo.
    private var firmaSeleccion: String = ""

    func reconstruir(caja: CGRect, camara: Camara, viewport: NSSize,
                     conservarPosicion: Bool = false) {
        let origenAntes = frame.origin
        func restaurarOrigen() {
            guard conservarPosicion else { return }
            // Un control no puede huir de debajo de la mano por el cambio que
            // EL MISMO acaba de provocar. Al bajar la tipografia, remaquetar
            // encoge las cajas y la barra antes seguia enseguida la nueva caja:
            // el siguiente clic caia en el lienzo vacio y borraba la seleccion.
            // Se conserva el origen, acotado por si cambió el ancho de la barra.
            frame.origin = NSPoint(
                x: min(max(8, origenAntes.x), max(8, viewport.width - frame.width - 8)),
                y: min(max(8, origenAntes.y), max(8, viewport.height - frame.height - 8)))
        }
        /*
         * ⚠️ UN PANEL ABIERTO NO SE TIRA POR UN CAMBIO QUE ÉL MISMO CAUSÓ.
         *
         * Daniel, 25 ago: *"el componente que me permite modificar el grosor de
         * este rombo, al intentar adaptarlo, como que desaparece; es molesta la
         * experiencia"*. Y era literal: mover el slider cambia el documento →
         * el documento avisa → la barra se reconstruye → y lo PRIMERO que hacía
         * `reconstruir` era `cerrarPanel()`. El control se suicidaba en cuanto
         * lo tocabas, y con él se iba el arrastre del ratón.
         *
         * Si la SELECCIÓN es la misma y hay un panel abierto, no hay nada que
         * reconstruir: los botones son los mismos y el panel sigue siendo
         * válido. Solo se recoloca la barra, que es lo único que sí cambia
         * cuando el elemento se mueve.
         */
        let firma = seleccion.map(\.id).sorted().joined(separator: ",")
        if panel != nil, firma == firmaSeleccion, !seleccion.isEmpty {
            colocar(caja: caja, camara: camara, viewport: viewport)
            restaurarOrigen()
            return
        }
        firmaSeleccion = firma
        cerrarPanel()
        subviews.forEach { $0.removeFromSuperview() }
        guard !seleccion.isEmpty else { isHidden = true; return }
        isHidden = false
        Estilo.tarjeta(self, tema: tema, radio: 8)
        layer?.shadowOpacity = 0.10
        layer?.shadowRadius = 5
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        var piezas: [NSView] = []
        let est = estiloComun

        // ── QUE ES. Solo con VARIOS: con uno, los iconos ya lo dicen y la
        //    palabra solo roba ancho. Con varios "3 elementos" es la unica pista
        //    de sobre cuantas cosas va a caer el siguiente clic.
        if seleccion.count > 1 {
            piezas.append(etiqueta("\(seleccion.count) elementos"))
            piezas.append(separador())
        }
        if seleccion.contains(where: { $0.fijado }) {
            let p = nuevoBoton(Icono.chincheta, globo: "Lo tocó tu mano: el compilador ya no lo manda") {}
            p.tinteIcono = tema.acento
            piezas.append(p)
        }

        // ── FIGURA ──────────────────────────────────────────────────────────
        if !figuras.isEmpty {
            let actual = comun(figuras) { $0.figura }
            piezas.append(nuevoBoton(actual.map { Herramienta(rawValue: $0)?.icono ?? Icono.figuras } ?? Icono.figuras,
                                     activo: abierto == "forma", ancho: 44, globo: "Cambiar la forma") { [weak self] in
                self?.abrirPanelForma()
            })
            let rol = comun(figuras) { $0.rol }
            piezas.append(nuevoBoton(muestraDeRol(rol), texto: rol.map { Self.nombreRol($0) } ?? "Varios",
                                     activo: abierto == "rol", globo: "Rol: decide su color en cualquier tema") { [weak self] in
                self?.abrirPanelRol()
            })
        }

        // ── TIPOGRAFIA ──────────────────────────────────────────────────────
        if conTexto {
            if !figuras.isEmpty || !secciones.isEmpty { piezas.append(separador()) }
            let nombreFam = est.familia.flatMap { f in FAMILIAS.first { $0.id == f }?.nombre } ?? "Varias"
            piezas.append(nuevoBoton(nil, texto: nombreFam, activo: abierto == "familia",
                                     globo: "Tipografía") { [weak self] in self?.abrirPanelFamilia() })

            let num = CampoNumero()
            num.tema = tema
            num.valor = est.tamano.map { $0.rounded() }
            num.alCambiar = { [weak self] v in self?.alTipografia?(Tipografia(tamano: v)) }
            piezas.append(num)

            let negrita = (est.peso ?? 400) >= 600
            piezas.append(nuevoBoton(Icono.negrita, activo: negrita, globo: "Negrita  ⌘B") { [weak self] in
                self?.alTipografia?(Tipografia(peso: negrita ? 400 : 700))
            })
            piezas.append(nuevoBoton(Icono.alinear(est.alineacion ?? "center"), activo: abierto == "alinear",
                                     globo: "Alineación") { [weak self] in self?.abrirPanelAlinear() })

            let colorTexto = comun(conLetras.isEmpty ? seleccion : conLetras) { $0.colorTexto }
            piezas.append(nuevoBoton(tinte(Icono.colorTexto, colorTexto ?? hex(tema.cuerpoTexto)),
                                     activo: abierto == "texto", globo: "Color del texto") { [weak self] in
                self?.abrirPanelColor("texto", "Color del texto", Paletas.trazos, colorTexto,
                                      efectivo: self?.tema.cuerpoTexto) { [weak self] c in
                    self?.alColor?(["text": c])
                }
            })
            let resaltado = comun(conLetras.isEmpty ? seleccion : conLetras) { $0.resaltado }
            piezas.append(nuevoBoton(tinte(Icono.resaltar, resaltado ?? hex(tema.pieTexto)),
                                     activo: abierto == "resaltar", globo: "Resaltar") { [weak self] in
                // El resaltado emite `rgba(...)`: opaco taparia el texto que
                // esta ahi justo para que se lea.
                self?.abrirPanelColor("resaltar", "Resaltado", Paletas.resaltados, resaltado,
                                      conMarca: false, efectivo: NSColor(hex: "#ffe050"),
                                      alfa: 0.55) { [weak self] c in
                    self?.alColor?(["highlight": c])
                }
            })
        }

        // ── CONTORNO Y RELLENO ──────────────────────────────────────────────
        if !conTrazo.isEmpty {
            piezas.append(separador())
            let contorno = comun(conTrazo) { $0.contorno }
            let efectivo = figuras.first.map { tema.contorno($0).color } ?? tema.cuerpoTexto
            piezas.append(nuevoBoton(tinte(Icono.contornoIcono, contorno ?? hex(efectivo)),
                                     activo: abierto == "contorno", globo: "Contorno") { [weak self] in
                self?.abrirPanelContorno()
            })
            if !figuras.isEmpty {
                let relleno = comun(figuras) { $0.relleno }
                let ef = figuras.first.map { tema.relleno($0) } ?? tema.lienzo
                piezas.append(nuevoBoton(tinte(Icono.rellenoIcono, relleno ?? hex(ef)),
                                         activo: abierto == "relleno", globo: "Relleno") { [weak self] in
                    self?.abrirPanelColor("relleno", "Relleno", Paletas.rellenos, relleno, redondo: true,
                                          nota: "Un color elegido a mano deja de seguir al tema. Vuelve a la primera casilla para devolvérselo al rol.",
                                          // Todas las muestras del relleno son claras: el
                                          // primer toque del cuadro cae en pastel, no en neón.
                                          efectivo: ef, puntoNuevo: NSPoint(x: 0.30, y: 0)) { [weak self] c in
                        self?.alColor?(["fill": c])
                    }
                })
            }
        }

        // ── SECCION ─────────────────────────────────────────────────────────
        if !secciones.isEmpty {
            piezas.append(separador())
            let tinteActual = secciones[0].tinte
            piezas.append(nuevoBoton(muestraDeTinte(tinteActual), activo: abierto == "tinte", ancho: 44,
                                     globo: "Tinte de la sección") { [weak self] in self?.abrirPanelTinte() })
        }

        // ── TINTA ───────────────────────────────────────────────────────────
        if seleccion.allSatisfy({ $0.tipo == "ink" }) {
            piezas.append(separador())
            /*
             * ⚠️ CINCO COLORES SUELTOS EN LA BARRA, NO.
             *
             * Un trazo ya dibujado tenia menos colores para repintarse que una
             * caja: cinco discos en fila contra las dieciocho muestras y el
             * arcoiris del panel de relleno. Y la barra pagaba 168 px por esos
             * cinco. Ahora es UN boton con el mismo panel que todo lo demas —
             * misma paleta, mismo espectro, misma primera casilla que devuelve
             * la tinta al tema.
             */
            let actual = comun(seleccion) { $0.colorTinta }
            piezas.append(nuevoBoton(muestraColor(actual ?? hex(tema.tinta), marcada: actual != nil),
                                     activo: abierto == "tinta", globo: "Color de la tinta") { [weak self] in
                self?.abrirPanelColor("tinta", "Tinta", Paletas.trazos, actual, redondo: true,
                                      efectivo: self?.tema.tinta) { [weak self] c in
                    self?.alCambiar?(["color": c.map { Json.texto($0) } ?? nil], { $0.tipo == "ink" })
                }
            })
            piezas.append(separador())
            let g = comun(seleccion) { $0.grosorTinta }
            for s in [3.0, 6.0, 12.0] {
                piezas.append(nuevoBoton(Icono.grosor(s), activo: g == s, globo: "Grosor \(Int(s))") { [weak self] in
                    self?.alCambiar?(["size": .numero(s)], { $0.tipo == "ink" })
                })
            }
        }

        // ── CONECTOR ────────────────────────────────────────────────────────
        if seleccion.count == 1, seleccion[0].tipo == "connector" {
            let c = seleccion[0]
            piezas.append(separador())
            piezas.append(nuevoBoton(Icono.ruta(c.ruteo), activo: abierto == "ruta", ancho: 40,
                                     globo: "Ruta") { [weak self] in self?.abrirPanelRuta() })
            piezas.append(nuevoBoton(Icono.clase(c.claseArista), activo: abierto == "clase", ancho: 40,
                                     globo: "Clase de relación") { [weak self] in self?.abrirPanelClase() })
            piezas.append(nuevoBoton(Icono.punta(c.puntaInicio, invertida: true), activo: abierto == "ini", ancho: 40,
                                     globo: "Punta de inicio") { [weak self] in self?.abrirPanelPunta(inicio: true) })
            piezas.append(nuevoBoton(Icono.punta(c.puntaFin), activo: abierto == "fin", ancho: 40,
                                     globo: "Punta de fin") { [weak self] in self?.abrirPanelPunta(inicio: false) })
            let fijo = c.crudo["fromPort"] != nil || c.crudo["toPort"] != nil
            piezas.append(nuevoBoton(Icono.chincheta, activo: fijo, globo: fijo
                ? "Anclaje fijo: la flecha se queda por donde la conectaste. Clic para soltarla."
                : "Anclaje libre: el lado se recalcula al mover. Clic para fijarlo donde está.") { [weak self] in
                self?.alAnclaje?(!fijo)
            })
            let campo = NSTextField(frame: NSRect(x: 0, y: 0, width: 104, height: 28))
            campo.stringValue = c.etiqueta ?? ""
            campo.placeholderString = "etiqueta…"
            campo.font = Estilo.fuente(12, 600)
            campo.isBordered = false
            campo.drawsBackground = true
            campo.wantsLayer = true
            campo.layer?.cornerRadius = 7
            campo.layer?.backgroundColor = tema.lienzo.cgColor
            campo.layer?.borderWidth = 1
            campo.layer?.borderColor = tema.rol("card").trazo.color.cgColor
            campo.textColor = tema.cuerpoTexto
            campo.focusRingType = .none
            campo.target = self
            campo.action = #selector(escribioEtiqueta(_:))
            piezas.append(campo)
        }

        // ── ENLACE · CANDADO · ACOMODAR · MAS ───────────────────────────────
        piezas.append(separador())
        let enlace = comun(seleccion) { $0.enlace }
        piezas.append(nuevoBoton(Icono.enlace, activo: abierto == "enlace" || enlace != nil,
                                 globo: enlace.map { "Enlace: \($0)" } ?? "Insertar enlace") { [weak self] in
            self?.abrirPanelEnlace(enlace)
        })
        let bloqueado = seleccion.contains { $0.bloqueado }
        piezas.append(nuevoBoton(bloqueado ? Icono.candado : Icono.candadoAbierto, activo: bloqueado,
                                 globo: bloqueado ? "Desbloquear  ⌘⇧L" : "Bloquear  ⌘⇧L") { [weak self] in
            self?.alCambiar?(["locked": .bool(!bloqueado)], nil)
        })
        if alAcomodar != nil {
            let aviso = acomodarBloqueados > 0
                ? "  ·  \(acomodarBloqueados) bloqueada\(acomodarBloqueados > 1 ? "s" : "") no se mover\(acomodarBloqueados > 1 ? "án" : "á")" : ""
            let b = nuevoBoton(Icono.destello, globo: "Acomodar: colocar estas figuras siguiendo sus flechas" + aviso) { [weak self] in
                self?.alAcomodar?()
            }
            b.layer?.backgroundColor = tema.acento.cgColor
            b.tinteIcono = .white
            piezas.append(b)
        }
        piezas.append(nuevoBoton(Icono.tresPuntos, activo: abierto == "mas", globo: "Más") { [weak self] in
            self?.abrirPanelMas()
        })

        // ── colocar ─────────────────────────────────────────────────────────
        var x: CGFloat = 5
        for v in piezas {
            v.frame.origin = NSPoint(x: x, y: (Self.ALTO - v.frame.height) / 2)
            addSubview(v)
            x += v.frame.width + 1
        }
        let ancho = x + 5

        colocar(caja: caja, camara: camara, viewport: viewport, ancho: ancho)
        restaurarOrigen()
    }

    /* DONDE VA. Arriba de la caja de la selección, centrada en ella. Si no
       cabe arriba salta abajo; si tampoco (elemento mas alto que la
       pantalla) se pega al borde inferior — porque una barra fuera de la
       pantalla es una barra que no existe.

       Vive APARTE de `reconstruir` desde el 25 ago: cuando hay un panel
       abierto la barra NO se reconstruye (tirarla se llevaba el control que
       estabas usando), pero sí tiene que seguir al elemento si se mueve. */
    private func colocar(caja: CGRect, camara: Camara, viewport: NSSize, ancho: CGFloat? = nil) {
        let ancho = ancho ?? frame.width
        func aPantalla(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - camara.x) * camara.zoom + viewport.width / 2,
                    y: (p.y - camara.y) * camara.zoom + viewport.height / 2)
        }
        let inf = aPantalla(CGPoint(x: caja.midX, y: caja.maxY))
        let sup = aPantalla(CGPoint(x: caja.midX, y: caja.minY))
        // La vista NO esta volteada: en AppKit la Y crece hacia ARRIBA, asi que
        // "debajo del elemento" es una Y MENOR.
        let yInf = viewport.height - inf.y - Self.AIRE - Self.ALTO
        let ySup = viewport.height - sup.y + Self.AIRE
        let crudo = ySup + Self.ALTO < viewport.height - 8 ? ySup : (yInf > 8 ? yInf : 10)
        /* ACOTADA A LA PANTALLA, SIEMPRE. Sin este acote, elegir algo y panear
           hasta sacarlo de vista se lleva la barra con el — y lo que ves es que
           la barra "desaparecio", no que el elemento se fue. */
        let y = min(max(8, crudo), max(8, viewport.height - Self.ALTO - 8))
        let left = min(max(8, inf.x - ancho / 2), max(8, viewport.width - ancho - 8))
        frame = NSRect(x: left, y: y, width: ancho, height: Self.ALTO)
    }

    @objc private func escribioEtiqueta(_ c: NSTextField) {
        alCambiar?(["label": .texto(c.stringValue)], { $0.tipo == "connector" })
    }

    // ── paneles ─────────────────────────────────────────────────────────────

    private func abrirPanel(_ id: String, ancho: CGFloat, alto: CGFloat, desdeX: CGFloat = 0,
                            _ contenido: (NSView) -> Void) {
        let estaba = abierto == id
        cerrarPanel()
        if estaba { return }
        abierto = id
        let v = Tarjeta(tema: tema, radio: 11)
        /*
         * ⚠️ SI NO CABE DEBAJO, SALTA ARRIBA. No se acota.
         *
         * La primera versión hacía `max(8, ...)`: un panel alto —el de contorno
         * mide 460— se pegaba al borde inferior y su parte de arriba quedaba
         * ENCIMA de la propia barra, tapando los botones de forma y rol. Se ve
         * como si la barra no los tuviera.
         *
         * Es la misma regla que la barra ya aplica para colocarse a sí misma, y
         * no aplicarla aquí fue copiar la mitad de la solución.
         */
        let raizAncho = superview?.bounds.width ?? 1200
        let raizAlto = superview?.bounds.height ?? 800
        let x = min(max(8, frame.minX + desdeX), raizAncho - ancho - 8)
        let debajo = frame.minY - alto - 6
        let arriba = frame.maxY + 6
        let y = debajo >= 8 ? debajo
              : (arriba + alto <= raizAlto - 8 ? arriba : max(8, raizAlto - alto - 8))
        /*
         * ⚠️ EL TAMAÑO VA ANTES QUE EL CONTENIDO.
         *
         * La primera versión llamaba a `contenido(v)` con el marco todavía en
         * cero, y los paneles que colocan de arriba hacia abajo —el de contorno
         * lo hace— partían de `frame.height` = 0. Sus etiquetas y deslizadores
         * salían con Y negativa: se pintaban DEBAJO de la tarjeta, sueltos
         * sobre el lienzo, mientras el panel se veía medio vacío.
         *
         * No fallaba nada: se veía como un panel mal diseñado.
         */
        v.frame = NSRect(x: x, y: y, width: ancho, height: alto)
        contenido(v)
        superview?.addSubview(v)
        panel = v
        subviews.compactMap { $0 as? BotonPlano }.forEach { _ in }
    }

    private func abrirPanelForma() {
        let formas = ["rect", "pill", "ellipse", "diamond", "triangle", "hexagon", "star", "arrow"]
        abrirPanel("forma", ancho: 4 * 38 + 16, alto: 2 * 38 + 34) { v in
            let r = rotulo("Forma"); r.frame.origin = NSPoint(x: 8, y: 2 * 38 + 12); v.addSubview(r)
            for (i, f) in formas.enumerated() {
                let b = nuevoBoton(Herramienta(rawValue: f)?.icono, ancho: 34) { [weak self] in
                    self?.alCambiar?(["shape": .texto(f)], { $0.tipo == "shape" })
                    self?.cerrarPanel()
                }
                b.activo = comun(figuras) { $0.figura } == f
                b.frame = NSRect(x: 8 + CGFloat(i % 4) * 38, y: 8 + CGFloat(1 - i / 4) * 38, width: 34, height: 34)
                v.addSubview(b)
            }
        }
    }

    /// Los roles que se ofrecen a mano.
    ///
    /// ⚠️ `drawn` TIENE QUE ESTAR: es el rol con el que nace toda figura
    /// dibujada, y sin entrada aqui el boton enseñaba el id interno crudo — se
    /// veia "drawn" en la barra, en ingles y sin significado.
    private static let roles: [(String, String)] = [
        ("drawn", "A mano"), ("card", "Neutro"), ("module", "Módulo"), ("form", "Entrada"),
        ("callout", "Llamada"), ("deliverable", "Entregable"), ("trigger", "Disparador"),
        ("agent", "Agente"), ("risk", "Riesgo"),
        ("nota", "Nota"), ("sticky", "Sutil"),
    ]
    static func nombreRol(_ r: String) -> String { roles.first { $0.0 == r }?.1 ?? r }

    private func abrirPanelRol() {
        abrirPanel("rol", ancho: 186, alto: CGFloat(Self.roles.count) * 30 + 34) { v in
            let r = rotulo("Rol"); r.frame.origin = NSPoint(x: 8, y: CGFloat(Self.roles.count) * 30 + 12); v.addSubview(r)
            for (i, par) in Self.roles.enumerated() {
                let b = nuevoBoton(muestraDeRol(par.0), texto: par.1, ancho: 170) { [weak self] in
                    self?.alCambiar?(["role": .texto(par.0)], { $0.tipo == "shape" })
                    self?.cerrarPanel()
                }
                b.activo = comun(figuras) { $0.rol } == par.0
                b.alignment = .left
                b.frame = NSRect(x: 8, y: 6 + CGFloat(Self.roles.count - 1 - i) * 30, width: 170, height: 30)
                v.addSubview(b)
            }
        }
    }

    private func abrirPanelFamilia() {
        let est = estiloComun
        let pesos = PESOS[est.familia ?? "montserrat"] ?? PESOS["montserrat"]!
        let filasPeso = CGFloat((pesos.count + 3) / 4)
        abrirPanel("familia", ancho: 200, alto: CGFloat(FAMILIAS.count) * 32 + filasPeso * 30 + 60) { v in
            var y = v.frame.height
            let r = rotulo("Tipografía")
            for (i, f) in FAMILIAS.enumerated() {
                let b = nuevoBoton(nil, texto: f.nombre, ancho: 184) { [weak self] in
                    self?.alTipografia?(Tipografia(familia: f.id)); self?.cerrarPanel()
                }
                b.activo = est.familia == f.id
                b.alignment = .left
                b.attributedTitle = NSAttributedString(string: f.nombre, attributes: [
                    // La muestra se pinta CON su propia fuente: elegir una letra
                    // leyendo su nombre en otra tipografia es elegir a ciegas.
                    .font: Fuentes.fuente(familia: f.id, peso: 600, tamano: 14, cursiva: false) as NSFont,
                    .foregroundColor: b.activo ? tema.acento : tema.cuerpoTexto,
                ])
                b.frame = NSRect(x: 8, y: CGFloat(FAMILIAS.count - 1 - i) * 32 + filasPeso * 30 + 16,
                                 width: 184, height: 32)
                v.addSubview(b)
            }
            y = filasPeso * 30 + 16
            r.frame.origin = NSPoint(x: 8, y: v.frame.height - 22); v.addSubview(r)
            let rp = rotulo("Grosor"); rp.frame.origin = NSPoint(x: 8, y: y + 4); v.addSubview(rp)
            for (i, p) in pesos.enumerated() {
                let b = nuevoBoton(nil, texto: "\(Int(p))", ancho: 42) { [weak self] in
                    self?.alTipografia?(Tipografia(peso: p))
                }
                b.activo = est.peso == p
                b.attributedTitle = NSAttributedString(string: "\(Int(p))", attributes: [
                    .font: Estilo.fuente(11, p),
                    .foregroundColor: b.activo ? tema.acento : tema.cuerpoTexto,
                ])
                b.frame = NSRect(x: 8 + CGFloat(i % 4) * 45, y: 6 + CGFloat(filasPeso - 1 - CGFloat(i / 4)) * 30,
                                 width: 42, height: 26)
                v.addSubview(b)
            }
        }
    }

    private func abrirPanelAlinear() {
        abrirPanel("alinear", ancho: 3 * 36 + 14, alto: 40) { v in
            for (i, a) in ["left", "center", "right"].enumerated() {
                let b = nuevoBoton(Icono.alinear(a), ancho: 34) { [weak self] in
                    self?.alTipografia?(Tipografia(alineacion: a)); self?.cerrarPanel()
                }
                b.activo = estiloComun.alineacion == a
                b.frame = NSRect(x: 7 + CGFloat(i) * 36, y: 4, width: 34, height: 32)
                v.addSubview(b)
            }
        }
    }

    /**
     * El panel de color: muestras arriba, espectro debajo.
     *
     * `aplicar` es generico a proposito. La mayoria de los colores viven dentro
     * del objeto `color` del elemento y se escriben con `alColor`, pero la TINTA
     * guarda el suyo en un campo suelto — y tener dos paneles casi iguales para
     * eso fue justo lo que dejo al lapiz con gradiente y a todo lo demas sin el.
     */
    private func abrirPanelColor(_ id: String, _ titulo: String, _ muestras: [Muestra], _ valor: String?,
                                 redondo: Bool = false, conMarca: Bool = true, nota: String? = nil,
                                 efectivo: NSColor? = nil, alfa: Double? = nil,
                                 puntoNuevo: NSPoint = NSPoint(x: 0.85, y: 0.15),
                                 _ aplicar: @escaping (String?) -> Void) {
        let altoPaleta = VistaPaleta.alto(muestras.count, conMarca: conMarca,
                                          conEspectro: true, conRecientes: true)
        /*
         * ⚠️ EL ALTO DE LA NOTA SE MIDE, no se estima.
         *
         * Estaba clavado en 46 y la nota del relleno son cinco líneas: la
         * tarjeta cortaba el texto en "Vuelve a la primera" y la frase perdía
         * justo la mitad que dice QUÉ hacer. Un número mágico al lado de un
         * texto que se edita se desincroniza en cuanto alguien toca el texto.
         */
        let fuenteNota = Estilo.fuente(10, 500)
        let altoNota: CGFloat = nota.map {
            ceil(($0 as NSString).boundingRect(
                with: NSSize(width: CGFloat(6 * 30), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: fuenteNota]).height) + 14
        } ?? 0
        abrirPanel(id, ancho: 6 * 30 + 22, alto: altoPaleta + 34 + altoNota, desdeX: -70) { v in
            let r = rotulo(titulo); r.frame.origin = NSPoint(x: 10, y: v.frame.height - 22); v.addSubview(r)
            let p = VistaPaleta(frame: NSRect(x: 10, y: altoNota + 6, width: 6 * 30, height: altoPaleta))
            p.tema = tema; p.muestras = muestras; p.valor = valor
            p.redondo = redondo; p.conMarca = conMarca
            p.conEspectro = true; p.efectivo = efectivo; p.alfa = alfa
            p.puntoNuevo = puntoNuevo
            // Cada panel recuerda LO SUYO: los pasteles del relleno no valen
            // para el trazo, ni el `rgba` del resaltado para nada mas.
            p.ambito = id
            p.alElegir = { c in aplicar(c) }
            p.alAbrirGesto = { [weak self] in self?.alAbrirGesto?() }
            p.alCerrarGesto = { [weak self] _ in self?.alCerrarGesto?(titulo.lowercased()) }
            v.addSubview(p)
            montarCampoHex(en: v, paleta: p, efectivo: efectivo)
            if let n = nota {
                let t = NSTextField(wrappingLabelWithString: n)
                t.font = fuenteNota
                t.textColor = tema.pieTexto
                t.frame = NSRect(x: 10, y: 8, width: 6 * 30, height: altoNota - 14)
                v.addSubview(t)
            }
        }
    }

    /**
     * EL CAMPO HEX va ENCIMA de su caja, no dentro de la vista pintada.
     *
     * Escribir necesita un `NSTextField` de verdad —cursor, selección, pegar—;
     * el recuadro lo pinta la paleta para que case con el resto del cromo, que
     * no se puede pedir a un control del sistema. Y se monta desde AQUÍ para los
     * dos sitios que abren paleta: tenerlo solo en uno fue lo que dejó al panel
     * de contorno con una caja bonita que no escribía nada.
     */
    private func montarCampoHex(en v: NSView, paleta p: VistaPaleta, efectivo: NSColor?) {
        let campo = NSTextField(frame: .zero)
        campo.font = Estilo.mono(11, 600)
        campo.alignment = .left
        campo.isBordered = false
        campo.drawsBackground = false
        campo.focusRingType = .none
        // El placeholder es el color que se ESTÁ VIENDO: aunque el elemento siga
        // a su rol, ahí se lee qué tono tiene ahora mismo.
        campo.placeholderString = efectivo.map { Espectro.hex($0) } ?? "#rrggbb"
        campo.stringValue = p.valor ?? ""
        campo.textColor = tema.cuerpoTexto
        // ⚠️ El marco se traduce: la paleta está VOLTEADA y el panel no, así que
        // la Y del campo se mide desde abajo de la paleta.
        let e = p.cajaExacto
        campo.frame = NSRect(x: p.frame.minX + 8, y: p.frame.maxY - e.maxY + 4,
                             width: e.width - 42, height: 17)
        let puente = PuenteCampo(paleta: p, campo: campo)
        campo.delegate = puente
        p.puenteCampo = puente
        p.alCambiarValor = { [weak campo] val in campo?.stringValue = val ?? "" }
        v.addSubview(campo)
    }

    private func abrirPanelContorno() {
        let ref = conTrazo.first
        let efectivo = ref.map { tema.contorno($0) } ?? Trazo(color: tema.cuerpoTexto, grosor: 1.5, estilo: "solid")
        let radioEf = ref.map { tema.radio($0) } ?? 12
        let opacidad = comun(seleccion) { $0.opacidad } ?? 1
        let altoPaleta = VistaPaleta.alto(Paletas.trazos.count, conMarca: true,
                                          conEspectro: true, conRecientes: true)
        abrirPanel("contorno", ancho: 236, alto: altoPaleta + 262, desdeX: -100) { v in
            var y = v.frame.height - 22
            func rot(_ s: String) { let r = rotulo(s); r.frame.origin = NSPoint(x: 12, y: y); v.addSubview(r); y -= 8 }
            rot("Estilo")
            y -= 32
            for (i, e) in ["solid", "dashed", "dotted"].enumerated() {
                let b = nuevoBoton(Icono.linea(e), ancho: 68) { [weak self] in self?.alTrazo?(e, nil, nil) }
                b.activo = (ref?.estiloLinea ?? efectivo.estilo) == e
                b.frame = NSRect(x: 12 + CGFloat(i) * 71, y: y, width: 68, height: 30)
                v.addSubview(b)
            }
            y -= 14
            func deslizador(_ titulo: String, _ nombreGesto: String, _ min: Double, _ max: Double,
                            _ paso: Double, _ valor: Double, _ aplicar: @escaping (Double) -> Void) {
                let t = self.etiqueta(titulo, 11, 600)
                y -= 18
                t.frame.origin = NSPoint(x: 12, y: y)
                v.addSubview(t)
                let d = Deslizador(frame: NSRect(x: 10, y: y - 22, width: 214, height: 20))
                d.tema = tema; d.minimo = min; d.maximo = max; d.paso = paso; d.valor = valor
                d.alAbrir = { [weak self] in self?.alAbrirGesto?() }
                d.alCerrar = { [weak self] in self?.alCerrarGesto?(nombreGesto) }
                d.alMover = { v2 in
                    aplicar(v2)
                    t.stringValue = "\(titulo.components(separatedBy: " ·")[0]) · \(paso < 1 ? String(format: "%.1f", v2) : "\(Int(v2))")"
                }
                v.addSubview(d)
                y -= 30
            }
            deslizador("Grosor · \(String(format: "%.1f", ref?.grosorLinea ?? efectivo.grosor))", "grosor",
                       0, 12, 0.5, ref?.grosorLinea ?? efectivo.grosor) { [weak self] v2 in
                self?.alTrazo?(nil, v2, nil)
            }
            // El radio efectivo nunca supera lo que el pintor puede curvar
            // (min(w,h)/2) ni el tope del gesto: mostrar 999 aquí era mentirle
            // al usuario sobre un valor que jamás se pinta.
            let radioTope = conTrazo.first.map { min($0.caja.width, $0.caja.height) / 2 } ?? 64
            let radioVivo = min(ref?.radioEsquina ?? radioEf, min(64, radioTope))
            deslizador("Esquinas · \(Int(radioVivo))", "esquinas",
                       0, 64, 1, radioVivo) { [weak self] v2 in
                self?.alTrazo?(nil, nil, v2)
            }
            deslizador("Opacidad · \(Int(opacidad * 100))", "opacidad", 0.05, 1, 0.05, opacidad) { [weak self] v2 in
                self?.alCambiar?(["opacity": .numero(v2)], nil)
            }
            y -= 8
            rot("Color del contorno")
            let p = VistaPaleta(frame: NSRect(x: 12, y: 8, width: 6 * 30, height: altoPaleta))
            p.tema = tema; p.muestras = Paletas.trazos
            p.valor = comun(conTrazo) { $0.contorno }
            p.redondo = true
            p.conEspectro = true; p.efectivo = efectivo.color; p.ambito = "contorno"
            p.alElegir = { [weak self] c in self?.alColor?(["stroke": c]) }
            p.alAbrirGesto = { [weak self] in self?.alAbrirGesto?() }
            p.alCerrarGesto = { [weak self] _ in self?.alCerrarGesto?("contorno") }
            v.addSubview(p)
            montarCampoHex(en: v, paleta: p, efectivo: efectivo.color)
        }
    }

    private static let tintes = ["neutro", "morado", "ambar", "verde", "azul", "rosa", "rojo"]

    private func abrirPanelTinte() {
        abrirPanel("tinte", ancho: 7 * 30 + 20, alto: 108, desdeX: -40) { v in
            let r = rotulo("Tinte"); r.frame.origin = NSPoint(x: 10, y: 82); v.addSubview(r)
            for (i, t) in Self.tintes.enumerated() {
                let b = nuevoBoton(muestraDeTinte(t), ancho: 26) { [weak self] in
                    self?.alCambiar?(["tint": .texto(t)], { $0.tipo == "frame" })
                }
                b.activo = (secciones.first?.tinte ?? "neutro") == t
                b.frame = NSRect(x: 10 + CGFloat(i) * 30, y: 48, width: 26, height: 26)
                v.addSubview(b)
            }
            let recorta = secciones.first?.crudo["clip"]?.b ?? false
            let b = nuevoBoton(Icono.recortar, texto: "Recortar lo que sobresale", ancho: 7 * 30) { [weak self] in
                self?.alCambiar?(["clip": .bool(!recorta)], { $0.tipo == "frame" })
            }
            b.activo = recorta
            b.alignment = .left
            b.frame = NSRect(x: 10, y: 10, width: 7 * 30, height: 30)
            v.addSubview(b)
        }
    }

    private static let rutas = [("ortogonal", "Codos"), ("recta", "Recta"), ("curva", "Curva")]
    private static let clases = [("flujo", "Flujo"), ("agente", "Agente"), ("fragil", "Frágil"), ("hueco", "Hueco")]
    private static let puntas = [("ninguna", "Ninguna"), ("flecha", "Flecha"), ("triangulo", "Triángulo"),
                                 ("rombo", "Rombo"), ("circulo", "Círculo"), ("barra", "Barra")]

    private func menuSimple(_ id: String, _ titulo: String, _ opciones: [(String, String)],
                            _ activo: String, _ icono: @escaping (String) -> NSImage,
                            _ aplicar: @escaping (String) -> Void) {
        abrirPanel(id, ancho: 180, alto: CGFloat(opciones.count) * 30 + 34) { v in
            let r = rotulo(titulo); r.frame.origin = NSPoint(x: 8, y: CGFloat(opciones.count) * 30 + 12); v.addSubview(r)
            for (i, o) in opciones.enumerated() {
                let b = nuevoBoton(icono(o.0), texto: o.1, ancho: 164) {
                    aplicar(o.0)
                }
                b.activo = o.0 == activo
                b.alignment = .left
                b.frame = NSRect(x: 8, y: 6 + CGFloat(opciones.count - 1 - i) * 30, width: 164, height: 30)
                v.addSubview(b)
            }
        }
    }

    private func abrirPanelRuta() {
        menuSimple("ruta", "Ruta", Self.rutas, seleccion[0].ruteo, { Icono.ruta($0) }) { [weak self] r in
            // Al cambiar de ruta se sueltan los codos: eran de la ruta anterior
            // y aplicarlos a otra geometria produce una linea sin sentido.
            self?.alCambiar?(["routing": .texto(r), "waypoints": nil], { $0.tipo == "connector" })
            self?.cerrarPanel()
        }
    }
    private func abrirPanelClase() {
        menuSimple("clase", "Clase de relación", Self.clases, seleccion[0].claseArista, { Icono.clase($0) }) { [weak self] k in
            self?.alCambiar?(["kind": .texto(k)], { $0.tipo == "connector" })
            self?.cerrarPanel()
        }
    }
    private func abrirPanelPunta(inicio: Bool) {
        let c = seleccion[0]
        menuSimple(inicio ? "ini" : "fin", inicio ? "Punta de inicio" : "Punta de fin", Self.puntas,
                   inicio ? c.puntaInicio : c.puntaFin,
                   { Icono.punta($0, invertida: inicio) }) { [weak self] p in
            if inicio {
                self?.alCambiar?(["headStart": .texto(p)], { $0.tipo == "connector" })
            } else {
                self?.alCambiar?(["headEnd": .texto(p), "arrowEnd": .bool(p != "ninguna")], { $0.tipo == "connector" })
            }
            self?.cerrarPanel()
        }
    }

    private func abrirPanelEnlace(_ actual: String?) {
        abrirPanel("enlace", ancho: 268, alto: 118, desdeX: -110) { v in
            let r = rotulo("Enlace"); r.frame.origin = NSPoint(x: 10, y: 92); v.addSubview(r)
            let campo = NSTextField(frame: NSRect(x: 10, y: 56, width: 248, height: 32))
            campo.stringValue = actual ?? ""
            campo.placeholderString = "https://…"
            campo.font = Estilo.fuente(12, 500)
            campo.isBordered = false; campo.drawsBackground = true
            campo.wantsLayer = true
            campo.layer?.cornerRadius = 8
            campo.layer?.backgroundColor = tema.lienzo.cgColor
            campo.layer?.borderWidth = 1
            campo.layer?.borderColor = tema.rol("card").trazo.color.cgColor
            campo.textColor = tema.cuerpoTexto
            campo.focusRingType = .none
            v.addSubview(campo)
            let guardar = nuevoBoton(nil, texto: "Guardar", ancho: actual != nil ? 168 : 248) { [weak self] in
                let t = campo.stringValue.trimmingCharacters(in: .whitespaces)
                self?.alCambiar?(["link": t.isEmpty ? nil : .texto(t)], nil)
                self?.cerrarPanel()
            }
            guardar.layer?.backgroundColor = tema.acento.cgColor
            guardar.attributedTitle = NSAttributedString(string: "Guardar", attributes: [
                .font: Estilo.fuente(12, 700), .foregroundColor: NSColor.white])
            guardar.frame = NSRect(x: 10, y: 20, width: actual != nil ? 168 : 248, height: 30)
            v.addSubview(guardar)
            if actual != nil {
                let quitar = nuevoBoton(nil, texto: "Quitar", ancho: 72) { [weak self] in
                    self?.alCambiar?(["link": nil], nil); self?.cerrarPanel()
                }
                quitar.contentTintColor = tema.rol("risk").trazo.color
                quitar.frame = NSRect(x: 186, y: 20, width: 72, height: 30)
                v.addSubview(quitar)
            }
            let nota = NSTextField(labelWithString: "Aparece una marca en la esquina. ⌘ + clic lo abre.")
            nota.font = Estilo.fuente(10, 500); nota.textColor = tema.pieTexto
            nota.frame = NSRect(x: 10, y: 2, width: 248, height: 14)
            v.addSubview(nota)
        }
    }

    private func abrirPanelMas() {
        var filas: [(String, NSImage, String, () -> Void)] = [
            // Las CUATRO, y con su atajo escrito al lado. El panel no es solo
            // una forma de ejecutar: es donde se APRENDE que el atajo existe.
            // Teniendo solo los dos extremos, nadie descubria que se puede
            // mover una sola capa — y eso es lo que se necesita cuando dos
            // cosas se tapan y solo quieres cambiar cual de las DOS gana.
            ("Traer al frente", Icono.alFrente, "⌘⇧]", { [weak self] in self?.alFrente?() }),
            ("Una capa adelante", Icono.alFrente, "⌘]", { [weak self] in self?.alAdelante?() }),
            ("Una capa atrás", Icono.alFondo, "⌘[", { [weak self] in self?.alAtras?() }),
            ("Enviar al fondo", Icono.alFondo, "⌘⇧[", { [weak self] in self?.alFondo?() }),
            ("Duplicar", Icono.duplicar, "⌘D", { [weak self] in self?.alDuplicar?() }),
            ("Eliminar", Icono.basura, "Supr", { [weak self] in self?.alBorrar?() }),
        ]
        /*
         * AGRUPAR VIVÍA ESCONDIDO.
         *
         * El documento sabe agrupar desde el primer día y el atajo ⌘G funciona,
         * pero este panel —el único sitio donde se MIRA lo que se puede hacer
         * con una selección— no lo listaba. Daniel, 26 ago, con seis logos
         * seleccionados: *"mira cómo no hay para agrupar componentes"*. Tenía
         * razón en el único sentido que importa: una capacidad que no aparece
         * donde se busca no existe.
         *
         * Se insertan ARRIBA de duplicar/eliminar porque agrupar es una
         * decisión sobre la ESTRUCTURA, del mismo orden que el apilado, y no
         * una acción destructiva.
         */
        if conTexto {
            let est = estiloComun
            filas.insert(("Cursiva", Icono.cursiva, "⌘I", { [weak self] in
                self?.alTipografia?(Tipografia(cursiva: !(est.cursiva ?? false)))
            }), at: 0)
            filas.insert(("Subrayado", Icono.subrayado, "⌘U", { [weak self] in
                self?.alTipografia?(Tipografia(subrayado: !(est.subrayado ?? false)))
            }), at: 1)
        }
        // RECORTAR, sobre una imagen sola. Se pone lo primero: es lo que se
        // busca aquí cuando se acaba de pegar una captura con su borde.
        if seleccion.count == 1, seleccion[0].tipo == "image" {
            filas.insert(("Recortar", Icono.recortar, "⌘K",
                          { [weak self] in self?.alRecortar?() }), at: 0)
        }
        if seleccion.count >= 2 {
            filas.insert(("Agrupar", Icono.agrupar, "⌘G",
                          { [weak self] in self?.alAgrupar?() }), at: 4)
        }
        if seleccion.contains(where: { $0.grupo != nil }) {
            filas.insert(("Desagrupar", Icono.desagrupar, "⌘⇧G",
                          { [weak self] in self?.alDesagrupar?() }),
                         at: seleccion.count >= 2 ? 5 : 4)
        }
        abrirPanel("mas", ancho: 200, alto: CGFloat(filas.count) * 30 + 16, desdeX: frame.width - 200) { v in
            for (i, f) in filas.enumerated() {
                let b = nuevoBoton(f.1, texto: f.2.isEmpty ? f.0 : "\(f.0)  \(f.2)", ancho: 184) { [weak self] in
                    f.3(); self?.cerrarPanel()
                }
                b.alignment = .left
                if f.0 == "Eliminar" {
                    b.contentTintColor = tema.rol("risk").trazo.color
                    b.tinteIcono = tema.rol("risk").trazo.color
                }
                b.frame = NSRect(x: 8, y: 8 + CGFloat(filas.count - 1 - i) * 30, width: 184, height: 30)
                v.addSubview(b)
            }
        }
    }

    // ── muestras dibujadas ──────────────────────────────────────────────────

    private func hex(_ c: NSColor) -> String {
        guard let s = c.usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02x%02x%02x", Int(s.redComponent * 255), Int(s.greenComponent * 255), Int(s.blueComponent * 255))
    }

    /// Un icono tintado con un color concreto: es como la barra DICE que color
    /// esta puesto sin abrir el panel.
    private func tinte(_ img: NSImage, _ color: String) -> NSImage {
        let c = NSColor(hex: color) ?? .gray
        let salida = NSImage(size: img.size, flipped: false) { r in
            img.draw(in: r)
            c.set()
            r.fill(using: .sourceAtop)
            return true
        }
        salida.isTemplate = false
        return salida
    }

    private func muestraColor(_ color: String, marcada: Bool) -> NSImage {
        NSImage(size: NSSize(width: 20, height: 20), flipped: true) { [tema] r in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            let camino = CGMutablePath()
            camino.addRoundedRect(in: r.insetBy(dx: 1, dy: 1), cornerWidth: 6, cornerHeight: 6)
            c.addPath(camino); c.setFillColor((NSColor(hex: color) ?? .gray).cgColor); c.fillPath()
            c.addPath(camino)
            c.setStrokeColor((marcada ? tema.acento : tema.rol("card").trazo.color).cgColor)
            c.setLineWidth(marcada ? 2 : 1); c.strokePath()
            return true
        }
    }

    /// La muestra de un ROL: su relleno y su borde REALES, con su estilo de
    /// linea. Es lo que hace que elegir un rol no sea leer una palabra.
    private func muestraDeRol(_ rol: String?) -> NSImage {
        // ⚠️ `isTemplate = false` explícito: esta muestra TRAE su color (el del
        // rol) y el bisel no debe reemplazarlo. Sin declararlo, los tres
        // cuadros de la barra —contorno, relleno y rol— salían idénticos.
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { [tema] r in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            let camino = CGMutablePath()
            camino.addRoundedRect(in: r.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 4, cornerHeight: 4)
            guard let rol else {
                c.addPath(camino)
                c.setStrokeColor(tema.pieTexto.cgColor); c.setLineWidth(2)
                c.setLineDash(phase: 0, lengths: [2.4, 2])
                c.strokePath()
                return true
            }
            let e = tema.rol(rol)
            c.addPath(camino); c.setFillColor(e.relleno.cgColor); c.fillPath()
            c.addPath(camino)
            c.setStrokeColor(e.trazo.color.cgColor); c.setLineWidth(2)
            switch e.trazo.estilo {
            case "dashed": c.setLineDash(phase: 0, lengths: [3, 2])
            case "dotted": c.setLineDash(phase: 0, lengths: [0.1, 2.6]); c.setLineCap(.round)
            default: break
            }
            c.strokePath()
            return true
        }
        img.isTemplate = false
        return img
    }

    private func muestraDeTinte(_ t: String) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: true) { [tema] r in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            let tin = tema.tintes[t] ?? tema.tintes["neutro"]!
            let camino = CGMutablePath()
            camino.addRoundedRect(in: r.insetBy(dx: 1, dy: 1), cornerWidth: 5, cornerHeight: 5)
            c.addPath(camino); c.setFillColor(tin.relleno.cgColor); c.fillPath()
            c.addPath(camino); c.setStrokeColor(tin.trazo.cgColor); c.setLineWidth(2); c.strokePath()
            return true
        }
    }
}

/**
 * El puente entre el campo de texto del hex y la paleta que lo pinta.
 *
 * ⚠️ Un `NSTextField` no retiene a su delegado. Sin alguien que lo sostenga
 * —aquí, la propia paleta— el puente muere en cuanto termina de construirse el
 * panel y escribir un color deja de hacer nada, sin error ni aviso.
 */
final class PuenteCampo: NSObject, NSTextFieldDelegate {
    private weak var paleta: VistaPaleta?
    private weak var campo: NSTextField?

    init(paleta: VistaPaleta, campo: NSTextField) {
        self.paleta = paleta; self.campo = campo
        super.init()
    }

    /// Al confirmar (Enter o salir del campo). Si el texto no vale, el campo
    /// vuelve a lo que había: dejar escrito un color imposible sería enseñar un
    /// estado que el documento no tiene.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let paleta, let campo else { return }
        if !paleta.escribir(campo.stringValue) { campo.stringValue = paleta.valor ?? "" }
    }
}
