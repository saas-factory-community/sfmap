import AppKit

/**
 * EL ESPECTRO: las dos barras que dan CUALQUIER color.
 *
 * Nació dentro de la paleta del lápiz y vivió ahí solo durante meses, mientras
 * el relleno, el contorno, el texto y el resaltado seguían ofreciendo dieciocho
 * casillas y nada más. Daniel: *"deberíamos poder [elegir] todos los colores
 * dentro del gradiente en múltiples componentes si no es que en todos donde
 * incluimos colores"*. Así que el MECANISMO se saca del instrumento y se vuelve
 * un servicio que cualquier paleta monta debajo de sus muestras.
 *
 * Es el oficio, no la materia: la paleta del lápiz sigue siendo la paleta del
 * lápiz — solo dejó de ser la dueña del gradiente.
 *
 * ── POR QUÉ DOS BARRAS Y NO UN CUADRADO ──────────────────────────────────
 * En 180-216 px de ancho un cuadrado de saturación sale de 60x60 y elegir
 * dentro se vuelve puntería. Separadas, cada una es un gesto de UN eje —qué
 * tono, y cuánto claro u oscuro— que es como se piensa un color cuando ya
 * sabes cuál quieres.
 *
 * ── POR QUÉ NO SUSTITUYE A LAS MUESTRAS ──────────────────────────────────
 * La paleta de RESTRICCIÓN sigue arriba y sigue mandando: una fila que se
 * abarca de un vistazo se elige más rápido que un gradiente que hay que
 * apuntar. El espectro es la VÁLVULA DE ESCAPE, no el camino de siempre — por
 * eso va debajo, más pequeño, y la primera casilla (la del tema) sigue siendo
 * la que devuelve el color a su rol.
 */
enum Espectro {
    /// Alto del cuadro. Ochenta píxeles = ochenta niveles de brillo, y con 174
    /// de ancho da casi 14,000 posiciones donde antes había 174.
    static let CUADRO: CGFloat = 80
    /// Alto de la barra de tono.
    static let BARRA: CGFloat = 14
    /// Hueco entre el cuadro y la barra.
    static let HUECO: CGFloat = 6
    /// Aire por encima, para que no se pegue a las muestras.
    static let AIRE: CGFloat = 10
    /// Lo que el espectro entero le pide a quien lo monta.
    static let ALTO: CGFloat = AIRE + CUADRO + HUECO + BARRA

    /// El cuadro y la barra dentro de una caja que empieza en `y`.
    static func cajas(x: CGFloat, y: CGFloat, ancho: CGFloat) -> (cuadro: NSRect, tono: NSRect) {
        (NSRect(x: x, y: y + AIRE, width: ancho, height: CUADRO),
         NSRect(x: x, y: y + AIRE + CUADRO + HUECO, width: ancho, height: BARRA))
    }

    /**
     * Dónde cae un color dentro del cuadro. X = saturación, Y = brillo (arriba
     * claro, como en cualquier picker desde Photoshop).
     */
    static func punto(_ base: NSColor, en cuadro: NSRect) -> NSPoint {
        let c = base.usingColorSpace(.deviceRGB) ?? .black
        return NSPoint(x: cuadro.minX + c.saturationComponent * cuadro.width,
                       y: cuadro.minY + (1 - c.brightnessComponent) * cuadro.height)
    }

    /// El color de una posición del cuadro, con el tono que se traiga puesto.
    static func delCuadro(_ p: NSPoint, en cuadro: NSRect, tono t: CGFloat) -> NSColor {
        NSColor(hue: t,
                saturation: max(0, min(1, (p.x - cuadro.minX) / cuadro.width)),
                brightness: max(0, min(1, 1 - (p.y - cuadro.minY) / cuadro.height)),
                alpha: 1)
    }

    /**
     * El tono del que parte todo.
     *
     * ⚠️ Un gris no tiene tono: su `hueComponent` es 0 (rojo) y usarlo pintaría
     * el cuadro entero de rojo sin que nada en pantalla lo justifique. Cuando la
     * base no da tono, manda el que se pasa por defecto.
     */
    static func matiz(_ base: NSColor, _ porDefecto: CGFloat = 0.75) -> CGFloat {
        let c = base.usingColorSpace(.deviceRGB) ?? .black
        return c.saturationComponent > 0.04 ? c.hueComponent : porDefecto
    }

    /// Pinta el cuadro, la barra y las dos marcas de lo que hay puesto.
    static func pintar(_ c: CGContext, cuadro: NSRect, tono tonoR: NSRect,
                       base: NSColor, hayColor: Bool, tema: Tema) {
        let rgb = base.usingColorSpace(.deviceRGB) ?? .black
        let h = matiz(rgb)

        func redondeada(_ r: NSRect, _ radio: CGFloat) -> CGMutablePath {
            let p = CGMutablePath()
            p.addRoundedRect(in: r, cornerWidth: radio, cornerHeight: radio)
            return p
        }

        /*
         * ⚠️ EL CUADRO SE PINTA CON DOS DEGRADADOS, NO PÍXEL A PÍXEL.
         *
         * A mano son ~3,500 rectángulos por repintado, y esta vista se repinta
         * en cada paso de un arrastre. Blanco→tono en horizontal, transparente→
         * negro en vertical: exactamente el mismo resultado, con dos llamadas.
         */
        c.saveGState()
        c.addPath(redondeada(cuadro, 8)); c.clip()
        let esp = CGColorSpaceCreateDeviceRGB()
        if let g = CGGradient(colorsSpace: esp,
                              colors: [NSColor.white.cgColor,
                                       NSColor(hue: h, saturation: 1, brightness: 1, alpha: 1).cgColor] as CFArray,
                              locations: [0, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: cuadro.minX, y: cuadro.midY),
                                 end: CGPoint(x: cuadro.maxX, y: cuadro.midY), options: [])
        }
        if let g = CGGradient(colorsSpace: esp,
                              colors: [NSColor.black.withAlphaComponent(0).cgColor,
                                       NSColor.black.cgColor] as CFArray,
                              locations: [0, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: cuadro.midX, y: cuadro.minY),
                                 end: CGPoint(x: cuadro.midX, y: cuadro.maxY), options: [])
        }
        c.restoreGState()
        c.addPath(redondeada(cuadro, 8))
        c.setStrokeColor(tema.rol("card").trazo.color.cgColor); c.setLineWidth(1); c.strokePath()

        // TONO: el arcoíris entero, en franjas de 1 px.
        c.saveGState()
        c.addPath(redondeada(tonoR, tonoR.height / 2)); c.clip()
        var x = tonoR.minX
        while x < tonoR.maxX {
            c.setFillColor(NSColor(hue: (x - tonoR.minX) / tonoR.width,
                                   saturation: 1, brightness: 1, alpha: 1).cgColor)
            c.fill(NSRect(x: x, y: tonoR.minY, width: 1.5, height: tonoR.height))
            x += 1
        }
        c.restoreGState()
        c.addPath(redondeada(tonoR, tonoR.height / 2))
        c.setStrokeColor(tema.rol("card").trazo.color.cgColor); c.setLineWidth(1); c.strokePath()

        guard hayColor else { return }
        // La aguja del tono.
        if rgb.saturationComponent > 0.04 {
            let ax = tonoR.minX + h * tonoR.width
            c.setStrokeColor(NSColor.white.cgColor); c.setLineWidth(3)
            c.move(to: CGPoint(x: ax, y: tonoR.minY + 1)); c.addLine(to: CGPoint(x: ax, y: tonoR.maxY - 1))
            c.strokePath()
            c.setStrokeColor(NSColor.black.withAlphaComponent(0.55).cgColor); c.setLineWidth(1)
            c.move(to: CGPoint(x: ax, y: tonoR.minY + 1)); c.addLine(to: CGPoint(x: ax, y: tonoR.maxY - 1))
            c.strokePath()
        }
        // Y el punto del cuadro: un anillo, no un relleno. Tapar el color justo
        // donde estás mirando es lo que obliga a mover para ver qué elegiste.
        let p = punto(rgb, en: cuadro)
        c.setLineWidth(2)
        c.setStrokeColor(NSColor.white.cgColor)
        c.strokeEllipse(in: NSRect(x: p.x - 5.5, y: p.y - 5.5, width: 11, height: 11))
        c.setLineWidth(1)
        c.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        c.strokeEllipse(in: NSRect(x: p.x - 6.5, y: p.y - 6.5, width: 13, height: 13))
    }

    /// `#rrggbb` de un color, que es como los guarda el modelo.
    static func hex(_ c: NSColor) -> String {
        let r = c.usingColorSpace(.deviceRGB) ?? .black
        return String(format: "#%02x%02x%02x",
                      Int((r.redComponent * 255).rounded()),
                      Int((r.greenComponent * 255).rounded()),
                      Int((r.blueComponent * 255).rounded()))
    }

    /// `rgba(r,g,b,a)`, que es como el resaltado guarda los suyos: translúcidos
    /// para que el texto siga leyéndose encima.
    static func rgba(_ c: NSColor, _ alfa: Double) -> String {
        let r = c.usingColorSpace(.deviceRGB) ?? .black
        return String(format: "rgba(%d,%d,%d,%.2f)",
                      Int((r.redComponent * 255).rounded()),
                      Int((r.greenComponent * 255).rounded()),
                      Int((r.blueComponent * 255).rounded()), alfa)
    }

    /// Las dos superficies del espectro. La mano agarra UNA y no la suelta hasta
    /// levantar el dedo.
    enum Zona { case cuadro, tono }

    /**
     * Qué agarró el dedo, si agarró algo. `nil` = el punto no es del espectro.
     *
     * ⚠️ La zona se decide UNA VEZ, al pulsar, y el arrastre la conserva. Un
     * hit-test por posición en cada paso hace que al salirte del cuadro por
     * abajo el color salte de golpe al arcoíris: la mano no soltó nada, pero el
     * control cambió de instrumento debajo del dedo.
     */
    static func zona(_ p: NSPoint, cuadro: NSRect, tono: NSRect) -> Zona? {
        if cuadro.insetBy(dx: -3, dy: -3).contains(p) { return .cuadro }
        // Con holgura vertical: la barra mide 14 px y pedir puntería exacta en
        // un gesto rápido hace que el color deje de seguir a la mano.
        if tono.insetBy(dx: 0, dy: -5).contains(p) { return .tono }
        return nil
    }

    /**
     * El color de un punto dentro de la zona que la mano ya tiene agarrada.
     *
     * `puntoNuevo` es dónde empieza el cuadro cuando el elemento todavía sigue a
     * su rol y no hay saturación de la que partir: en un relleno se quiere un
     * pastel (todas sus muestras lo son), en un trazo un tono vivo. Va en
     * coordenadas del cuadro: x = saturación, y = 1 − brillo.
     */
    static func color(_ p: NSPoint, zona: Zona, cuadro: NSRect, tono: NSRect,
                      base: NSColor, hayColor: Bool,
                      puntoNuevo: NSPoint = NSPoint(x: 0.85, y: 0.15)) -> NSColor {
        let rgb = base.usingColorSpace(.deviceRGB) ?? .black
        switch zona {
        case .cuadro:
            return delCuadro(p, en: cuadro, tono: matiz(rgb))
        case .tono:
            // Girar el tono conserva saturación y brillo: es lo que el cuadro
            // acaba de ajustar, y ningún picker lo destruye al mover el tono.
            let vivo = hayColor && rgb.saturationComponent > 0.04
            return NSColor(hue: max(0, min(1, (p.x - tono.minX) / tono.width)),
                           saturation: vivo ? rgb.saturationComponent : puntoNuevo.x,
                           brightness: vivo ? rgb.brightnessComponent : 1 - puntoNuevo.y,
                           alpha: 1)
        }
    }

    /// Un texto de color escrito a mano → color. Acepta `#abc`, `#aabbcc`, con
    /// o sin almohadilla, y `rgba(...)`: lo que el modelo ya sabe leer.
    static func leer(_ texto: String) -> NSColor? {
        let t = texto.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        return NSColor(hex: t) ?? NSColor(hex: "#" + t)
    }
}

/**
 * LOS COLORES QUE TE GUSTAN, QUE NO SON LOS QUE VIENEN EN LA CAJA.
 *
 * Daniel, 30 ago 2026: *"asegúrate de recordar los últimos colores escogidos
 * manualmente, no sé, tipo 5-8, y que ahí se queden en memoria para conservar
 * ciertos colores de mi gusto"*.
 *
 * El espectro abrió la puerta a cualquier color y con eso llegó su problema:
 * un tono que buscaste arrastrando —el morado exacto de una sección, el verde
 * que le queda a esa caja— se pierde en cuanto cierras el panel, y volver a
 * acertarlo a mano es imposible. Las dieciocho muestras no ayudan: son las de
 * la casa, no las tuyas.
 *
 * ── TRES DECISIONES ──────────────────────────────────────────────────────
 *
 * 1. **Solo entra lo elegido A MANO en el arcoíris.** Una muestra de la
 *    cuadrícula ya está ahí arriba, siempre: repetirla debajo gastaría la fila
 *    en enseñar lo que ya se ve. Recientes es la memoria de lo que si no, se
 *    pierde.
 *
 * 2. **Cada panel recuerda LO SUYO.** Una sola lista global mezclaría los
 *    pasteles del relleno con los saturados del trazo y con los `rgba`
 *    translúcidos del resaltado — tres formatos y tres usos distintos en la
 *    misma fila. El ámbito es el panel.
 *
 * 3. **Se guarda al SOLTAR, no mientras arrastras.** Buscar un color pasa por
 *    cuarenta tonos que no quisiste; el que quisiste es donde levantaste el
 *    dedo. Misma razón por la que el arrastre es UN cambio en el historial.
 */
enum Recientes {
    /// SEIS y no ocho: la cuadrícula de las paletas es de seis columnas con
    /// paso 30, así que seis es UNA fila exacta y alineada. Ocho obligaría a
    /// encoger las casillas solo en esta fila, y una retícula que se rompe en
    /// un sitio deja de leerse como retícula.
    static let TOPE = 6

    /// Alto que la fila le pide a quien la monta: rótulo + una fila de casillas.
    static let ALTO: CGFloat = 42

    /// ⚠️ Inyectable para que las pruebas no escriban en los ajustes de Daniel.
    static var almacen: UserDefaults = .standard

    private static func clave(_ ambito: String) -> String { "recientes.\(ambito)" }

    static func lista(_ ambito: String) -> [String] {
        (almacen.array(forKey: clave(ambito)) as? [String] ?? []).prefix(TOPE).map { $0 }
    }

    /// Lo pone el primero. Si ya estaba, SUBE en vez de duplicarse: la fila mide
    /// seis y gastar dos en el mismo color es perder un tercio de la memoria.
    static func recordar(_ color: String, en ambito: String) {
        var l = lista(ambito).filter { $0.caseInsensitiveCompare(color) != .orderedSame }
        l.insert(color, at: 0)
        almacen.set(Array(l.prefix(TOPE)), forKey: clave(ambito))
    }

    static func olvidarTodo(_ ambito: String) { almacen.removeObject(forKey: clave(ambito)) }
}
