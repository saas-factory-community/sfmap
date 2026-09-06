import AppKit
import CoreGraphics

/**
 * El juego de iconos, dibujado.
 *
 * Ni emojis ni SF Symbols: SF Symbols tiene un peso y un remate propios que al
 * lado de los del lienzo se ven de otra familia, y mezclar los dos delata al
 * instante que la ventana no es de la misma casa. Estos son los mismos trazos
 * de 1.6 sobre rejilla de 24 que usa la interfaz web.
 *
 * Todos son `isTemplate`, asi que el color lo pone quien los usa: uno tintado a
 * mano no seguiria al tema.
 */
extension Icono {
    private static func linea(_ c: CGContext, _ a: (Double, Double), _ b: (Double, Double)) {
        c.move(to: CGPoint(x: a.0, y: a.1)); c.addLine(to: CGPoint(x: b.0, y: b.1)); c.strokePath()
    }
    private static func poli(_ c: CGContext, _ pts: [(Double, Double)], cerrar: Bool = true) {
        guard let f = pts.first else { return }
        c.move(to: CGPoint(x: f.0, y: f.1))
        for p in pts.dropFirst() { c.addLine(to: CGPoint(x: p.0, y: p.1)) }
        if cerrar { c.closePath() }
        c.strokePath()
    }

    // ── panel de lienzos ────────────────────────────────────────────────────

    /// La equis de limpiar el buscador. Fina y chica: si pesara como los demás
    /// competiría con la lupa en un campo de 28 px de alto.
    static let equis = dibujar { c, _ in
        c.setLineWidth(1.9)
        linea(c, (7.4, 7.4), (16.6, 16.6))
        linea(c, (16.6, 7.4), (7.4, 16.6))
    }

    /// La MISMA carpeta, destapada. Una lista donde todas se ven igual obliga a
    /// leer el chevrón para saber cuál está abierta; con dos dibujos, el estado
    /// se ve sin leer nada.
    static let carpetaAbierta = dibujar { c, _ in
        c.move(to: CGPoint(x: 3.2, y: 18.6))
        c.addLine(to: CGPoint(x: 3.2, y: 7.4))
        c.addQuadCurve(to: CGPoint(x: 4.6, y: 6.0), control: CGPoint(x: 3.2, y: 6.0))
        c.addLine(to: CGPoint(x: 9.0, y: 6.0))
        c.addLine(to: CGPoint(x: 11.2, y: 8.6))
        c.addLine(to: CGPoint(x: 17.6, y: 8.6))
        c.addQuadCurve(to: CGPoint(x: 19.0, y: 10.0), control: CGPoint(x: 19.0, y: 8.6))
        c.addLine(to: CGPoint(x: 19.0, y: 11.6))
        c.strokePath()
        // La tapa abatida: un paralelogramo que sale del lomo hacia la derecha.
        poli(c, [(3.2, 18.6), (6.6, 11.6), (21.9, 11.6), (18.5, 18.6)])
    }

    /**
     * EL LIENZO — y a propósito NO es el icono de "documento".
     *
     * Las filas de páginas eran texto pelado sobre el panel: sin ancla visual,
     * veinte nombres seguidos se leen como un párrafo. La tentación es la hoja
     * con la esquina doblada, que es lo que pone todo el mundo — y sería mentira:
     * aquí dentro no hay un texto, hay un DIAGRAMA. Dos cajas y un codo entre
     * ellas dicen qué se abre al pulsar, y de paso es el retrato de esta app: el
     * ruteo ortogonal es lo único que ninguna otra dibuja igual.
     */
    static let lienzo = dibujar { c, _ in
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 3.4, y: 4.8, width: 17.2, height: 14.4),
                         cornerWidth: 2.6, cornerHeight: 2.6)
        c.addPath(p); c.strokePath()
        c.setLineWidth(1.35)
        for r in [CGRect(x: 6.3, y: 7.6, width: 5.2, height: 3.8),
                  CGRect(x: 12.6, y: 12.6, width: 5.2, height: 3.8)] {
            let q = CGMutablePath()
            q.addRoundedRect(in: r, cornerWidth: 1.1, cornerHeight: 1.1)
            c.addPath(q); c.strokePath()
        }
        c.move(to: CGPoint(x: 8.9, y: 11.4))
        c.addLine(to: CGPoint(x: 8.9, y: 14.5))
        c.addLine(to: CGPoint(x: 12.6, y: 14.5))
        c.strokePath()
    }

    /// Crear: la pieza **y** un más pegado abajo a la derecha, sobre el hueco
    /// que deja el propio dibujo. Un `+` suelto no dice QUÉ crea, y en la
    /// cabecera del panel había dos botones que solo se distinguían por eso.
    private static func conMas(_ cuerpo: @escaping (CGContext) -> Void) -> NSImage {
        dibujar { c, _ in
            cuerpo(c)
            c.setLineWidth(2.0)
            linea(c, (18.6, 15.2), (18.6, 21.4))
            linea(c, (15.5, 18.3), (21.7, 18.3))
        }
    }
    /// ⚠️ La primera versión llevaba dos renglones dentro y en la hoja de
    /// contacto se leía como una NOTA con un más — que es justo el icono de al
    /// lado en el rail. Un icono de "crear" tiene que enseñar la misma pieza que
    /// crea: aquí, el lienzo con su nodo y su codo, encogido.
    static let lienzoMas = conMas { c in
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 2.6, y: 4.2, width: 14.2, height: 12.2),
                         cornerWidth: 2.4, cornerHeight: 2.4)
        c.addPath(p); c.strokePath()
        c.setLineWidth(1.3)
        let q = CGMutablePath()
        q.addRoundedRect(in: CGRect(x: 5.0, y: 6.6, width: 4.6, height: 3.4),
                         cornerWidth: 1, cornerHeight: 1)
        c.addPath(q); c.strokePath()
        c.move(to: CGPoint(x: 7.3, y: 10.0))
        c.addLine(to: CGPoint(x: 7.3, y: 12.8))
        c.addLine(to: CGPoint(x: 12.6, y: 12.8))
        c.strokePath()
    }
    static let carpetaMas = conMas { c in
        c.move(to: CGPoint(x: 2.6, y: 16.4))
        c.addLine(to: CGPoint(x: 2.6, y: 6.4))
        c.addQuadCurve(to: CGPoint(x: 3.9, y: 5.1), control: CGPoint(x: 2.6, y: 5.1))
        c.addLine(to: CGPoint(x: 7.8, y: 5.1))
        c.addLine(to: CGPoint(x: 9.8, y: 7.4))
        c.addLine(to: CGPoint(x: 15.9, y: 7.4))
        c.addQuadCurve(to: CGPoint(x: 17.2, y: 8.7), control: CGPoint(x: 17.2, y: 7.4))
        c.addLine(to: CGPoint(x: 17.2, y: 16.4))
        c.closePath(); c.strokePath()
    }

    // ── herramientas ────────────────────────────────────────────────────────
    //
    // SÓLIDOS, no de trazo (24 ago 2026). Daniel eligió la familia "Sólido"
    // sobre una matriz de 5 y luego el tratamiento "Bisel" sobre otra de 5: el
    // gradiente de titanio necesita SUPERFICIE para verse, y un trazo de 1.6
    // no la tiene. Los iconos del PANEL (carpeta, lienzo, lupa…) siguen de
    // trazo a propósito: a 15 px una silueta llena se lee mancha.

    /// Poligono RELLENO. El hermano de `poli`, para la familia sólida.
    private static func llena(_ c: CGContext, _ pts: [(Double, Double)]) {
        guard let f = pts.first else { return }
        c.move(to: CGPoint(x: f.0, y: f.1))
        for p in pts.dropFirst() { c.addLine(to: CGPoint(x: p.0, y: p.1)) }
        c.closePath()
        c.fillPath()
    }

    static let cursor = dibujar { c, _ in
        // La flecha de la matriz elegida: m4 4 7.07 17 2.51-7.39 L21 11.07 z
        llena(c, [(4, 4), (11.07, 21), (13.58, 13.61), (21, 11.07)])
    }
    /// La MANO de panear, en cuerpos separados que el ojo junta solo — ahora
    /// llenos: palma, tres dedos y pulgar.
    static let mano = dibujar { c, _ in
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 6.6, y: 11, width: 11.4, height: 9.4), cornerWidth: 4.2, cornerHeight: 4.2)
        for (x, y, h) in [(8.4, 6.2, 7.0), (11.2, 4.6, 8.6), (14.0, 6.2, 7.0)] {
            p.addRoundedRect(in: CGRect(x: x, y: y, width: 2.4, height: h), cornerWidth: 1.2, cornerHeight: 1.2)
        }
        p.addRoundedRect(in: CGRect(x: 4.2, y: 12.4, width: 2.4, height: 5.4), cornerWidth: 1.2, cornerHeight: 1.2)
        c.addPath(p); c.fillPath()
    }
    /// La nota con su pestaña MORDIDA (even-odd): la muesca es parte de la
    /// silueta, como en la matriz.
    static let nota = dibujar { c, _ in
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 4, y: 4, width: 16, height: 16), cornerWidth: 3, cornerHeight: 3)
        p.addRect(CGRect(x: 13.5, y: 13.5, width: 6.5, height: 6.5))
        c.addPath(p)
        c.fillPath(using: .evenOdd)
    }
    /// La T serifada de la matriz, llena.
    static let textoT = dibujar { c, _ in
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 4, y: 4.5))
        for (x, y) in [(20.0, 4.5), (20.0, 8.5), (18.0, 8.5), (18.0, 7.5), (13.0, 7.5), (13.0, 18.5),
                       (15.0, 18.5), (15.0, 20.5), (9.0, 20.5), (9.0, 18.5), (11.0, 18.5), (11.0, 7.5),
                       (6.0, 7.5), (6.0, 8.5), (4.0, 8.5)] {
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.closeSubpath()
        c.addPath(p); c.fillPath()
    }
    static let cuadrado = dibujar { c, _ in
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 4.5, y: 5.5, width: 15, height: 13), cornerWidth: 3, cornerHeight: 3)
        c.addPath(p); c.fillPath()
    }
    static let circulo = dibujar { c, _ in
        c.fillEllipse(in: CGRect(x: 4.2, y: 4.2, width: 15.6, height: 15.6))
    }
    static let triangulo = dibujar { c, _ in llena(c, [(12, 4.6), (20, 19), (4, 19)]) }
    static let rombo = dibujar { c, _ in llena(c, [(12, 4), (20, 12), (12, 20), (4, 12)]) }
    static let estrella = dibujar { c, _ in
        var pts: [(Double, Double)] = []
        for i in 0..<10 {
            let a = Double.pi * Double(i) / 5 - .pi / 2
            let r = i % 2 == 0 ? 8.6 : 3.8
            pts.append((12 + cos(a) * r, 12 + sin(a) * r))
        }
        llena(c, pts)
    }
    static let pildora = dibujar { c, _ in
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 3.5, y: 7.5, width: 17, height: 9), cornerWidth: 4.5, cornerHeight: 4.5)
        c.addPath(p); c.fillPath()
    }
    static let hexagono = dibujar { c, _ in
        llena(c, [(8, 5), (16, 5), (20, 12), (16, 19), (8, 19), (4, 12)])
    }
    static let flechaFigura = dibujar { c, _ in
        llena(c, [(3.5, 9.5), (13, 9.5), (13, 5.5), (20.5, 12), (13, 18.5), (13, 14.5), (3.5, 14.5)])
    }
    /**
     * EL CONECTOR ES UNA FLECHA. Daniel: *"acuérdate que son flechas"*.
     *
     * El referente lo dibuja como dos nodos unidos por una curva — describe el
     * MECANISMO (une dos cosas) y no el RESULTADO (una flecha). En una barra
     * donde todo lo demás enseña lo que produce, ese es el único icono que
     * enseña cómo funciona por dentro. Se dibuja lo que sale.
     */
    static let conector = dibujar { c, _ in
        poli(c, [(4.2, 19.8), (13.6, 10.4)], cerrar: false)
        poli(c, [(9.6, 4.2), (19.8, 4.2), (19.8, 14.4)], cerrar: false)
        c.move(to: CGPoint(x: 19.8, y: 4.2))
        c.addLine(to: CGPoint(x: 13.4, y: 10.6))
        c.strokePath()
    }
    /// La SECCIÓN de la matriz elegida: cuatro esquineros sólidos.
    static let seccion = dibujar { c, _ in
        llena(c, [(4, 5), (9, 5), (9, 8), (7, 8), (7, 10), (4, 10)])
        llena(c, [(15, 5), (20, 5), (20, 10), (17, 10), (17, 8), (15, 8)])
        llena(c, [(20, 14), (20, 19), (15, 19), (15, 16), (17, 16), (17, 14)])
        llena(c, [(9, 19), (4, 19), (4, 14), (7, 14), (7, 16), (9, 16)])
    }
    /// El lápiz de la matriz: silueta llena, punta abajo-izquierda.
    static let lapiz = dibujar { c, _ in
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 16.6, y: 3.4))
        p.addCurve(to: CGPoint(x: 20.6, y: 7.4),
                   control1: CGPoint(x: 18.2, y: 1.9), control2: CGPoint(x: 20.9, y: 2.6))
        p.addLine(to: CGPoint(x: 7.5, y: 20.5))
        p.addLine(to: CGPoint(x: 2, y: 22))
        p.addLine(to: CGPoint(x: 3.5, y: 16.5))
        p.closeSubpath()
        c.addPath(p); c.fillPath()
    }
    /// El marcador: cuerpo lleno de punta plana + su línea de tinta.
    static let marcador = dibujar { c, _ in
        llena(c, [(15.5, 3.6), (20.4, 8.5), (9.4, 19.5), (4.5, 19.5), (4.5, 14.6)])
        c.setLineWidth(2.4)
        linea(c, (4.5, 22), (19.5, 22))
    }
    /// La GOMA: el bloque inclinado, lleno, con su línea de borrado.
    static let goma = dibujar { c, _ in
        llena(c, [(7.4, 16.6), (14.4, 6.4), (19.6, 10.0), (12.6, 20.2)])
        c.setLineWidth(2.2)
        linea(c, (3.6, 21.6), (20.4, 21.6))
    }
    /// La tabla de la matriz: banda de encabezado + dos celdas. Los surcos se
    /// RESTAN de la pieza (even-odd): dos calles de 2 px.
    static let tabla = dibujar { c, _ in
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 3.6, y: 4.8, width: 16.8, height: 14.4), cornerWidth: 2.4, cornerHeight: 2.4)
        p.addRect(CGRect(x: 3.6, y: 9.6, width: 16.8, height: 2))
        p.addRect(CGRect(x: 11.1, y: 11.6, width: 2, height: 7.6))
        c.addPath(p)
        c.fillPath(using: .evenOdd)
    }
    static let imagen = dibujar { c, _ in
        c.setLineWidth(2.1)
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 3.6, y: 5.4, width: 16.8, height: 13.2), cornerWidth: 2.4, cornerHeight: 2.4)
        c.addPath(p); c.strokePath()
        c.addEllipse(in: CGRect(x: 7, y: 8.4, width: 3, height: 3)); c.strokePath()
        poli(c, [(4.6, 17.4), (10, 12.4), (13.4, 15.4), (16, 13), (19.4, 16.4)], cerrar: false)
    }
    static let embed = dibujar { c, _ in
        c.setLineWidth(2.1)
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 3.6, y: 5, width: 16.8, height: 14), cornerWidth: 2.4, cornerHeight: 2.4)
        c.addPath(p); c.strokePath()
        linea(c, (3.6, 9.2), (20.4, 9.2))
        c.fillEllipse(in: CGRect(x: 5.8, y: 6.4, width: 1.6, height: 1.6))
        c.fillEllipse(in: CGRect(x: 8.6, y: 6.4, width: 1.6, height: 1.6))
    }
    static let codigo = dibujar { c, _ in
        c.setLineWidth(2.1)
        poli(c, [(8.6, 7.6), (4, 12), (8.6, 16.4)], cerrar: false)
        poli(c, [(15.4, 7.6), (20, 12), (15.4, 16.4)], cerrar: false)
        linea(c, (13.4, 5.4), (10.6, 18.6))
    }

    // ── barra contextual ────────────────────────────────────────────────────
    /// La B, con sus dos panzas cerrando contra el asta.
    ///
    /// La versión anterior dibujaba dos arcos sueltos que no tocaban el asta:
    /// a 15 px se leía como una D partida. Las curvas se cierran a mano.
    static let negrita = dibujar { c, _ in
        c.setLineWidth(2.4)
        c.move(to: CGPoint(x: 7.6, y: 4.6))
        c.addLine(to: CGPoint(x: 7.6, y: 19.4))
        c.strokePath()
        c.move(to: CGPoint(x: 7.6, y: 4.6))
        c.addLine(to: CGPoint(x: 13.4, y: 4.6))
        c.addCurve(to: CGPoint(x: 13.4, y: 11.6), control1: CGPoint(x: 17.6, y: 4.6), control2: CGPoint(x: 17.6, y: 11.6))
        c.addLine(to: CGPoint(x: 7.6, y: 11.6))
        c.strokePath()
        c.move(to: CGPoint(x: 7.6, y: 11.6))
        c.addLine(to: CGPoint(x: 14.2, y: 11.6))
        c.addCurve(to: CGPoint(x: 14.2, y: 19.4), control1: CGPoint(x: 18.8, y: 11.6), control2: CGPoint(x: 18.8, y: 19.4))
        c.addLine(to: CGPoint(x: 7.6, y: 19.4))
        c.strokePath()
    }
    static let cursiva = dibujar { c, _ in
        linea(c, (9.5, 5), (18, 5)); linea(c, (6, 19), (14.5, 19)); linea(c, (14, 5), (10.5, 19))
    }
    static let subrayado = dibujar { c, _ in
        poli(c, [(7, 4.5), (7, 12), (17, 12), (17, 4.5)], cerrar: false)
        c.addArc(center: CGPoint(x: 12, y: 12), radius: 5, startAngle: 0, endAngle: .pi, clockwise: false)
        c.strokePath()
        linea(c, (6, 19.5), (18, 19.5))
    }
    static func alinear(_ modo: String) -> NSImage {
        dibujar { c, _ in
            let ys = [6.5, 10.2, 13.8, 17.5]
            for (i, y) in ys.enumerated() {
                let corto = i % 2 == 1
                let w = corto ? 10.0 : 16.0
                let x: Double = modo == "left" ? 4 : modo == "right" ? 20 - w : 12 - w / 2
                linea(c, (x, y), (x + w, y))
            }
        }
    }
    /// La A con su banda de color. La versión anterior tenía el travesaño
    /// demasiado abajo y la letra se leía como un triángulo sobre una barra.
    static let colorTexto = dibujar { c, _ in
        poli(c, [(5.4, 15.6), (12.0, 4.6), (18.6, 15.6)], cerrar: false)
        linea(c, (8.3, 11.6), (15.7, 11.6))
        c.fill(CGRect(x: 4.6, y: 18.4, width: 14.8, height: 3.4))
    }
    static let resaltar = dibujar { c, _ in
        poli(c, [(6.5, 13.5), (14, 6), (18, 10), (10.5, 17.5), (6.5, 17.5)], cerrar: false)
        c.fill(CGRect(x: 4.5, y: 19.5, width: 15, height: 2.6))
    }
    static let contornoIcono = dibujar { c, _ in
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 4.5, y: 6, width: 15, height: 12), cornerWidth: 2.6, cornerHeight: 2.6)
        c.setLineWidth(2.6); c.addPath(p); c.strokePath()
    }
    static let rellenoIcono = dibujar { c, _ in
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 4.5, y: 6, width: 15, height: 12), cornerWidth: 2.6, cornerHeight: 2.6)
        c.addPath(p); c.fillPath()
    }
    /// EL ENLACE: dos eslabones entrelazados, no dos arcos sueltos.
    ///
    /// La versión anterior dibujaba dos semicírculos separados y salía una "S".
    /// Un eslabón es una CÁPSULA, y dos cápsulas giradas 45° que se solapan es
    /// lo que el ojo reconoce como cadena.
    static let enlace = dibujar { c, _ in
        for (dx, dy) in [(-2.6, 2.6), (2.6, -2.6)] {
            c.saveGState()
            c.translateBy(x: 12 + dx, y: 12 + dy)
            c.rotate(by: -.pi / 4)
            let p = CGMutablePath()
            p.addRoundedRect(in: CGRect(x: -5.6, y: -2.9, width: 11.2, height: 5.8),
                             cornerWidth: 2.9, cornerHeight: 2.9)
            c.addPath(p); c.strokePath()
            c.restoreGState()
        }
    }
    static let candado = dibujar { c, _ in
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 5.4, y: 10.6, width: 13.2, height: 9.4), cornerWidth: 2.2, cornerHeight: 2.2)
        c.addPath(p); c.strokePath()
        c.addArc(center: CGPoint(x: 12, y: 10.4), radius: 3.8, startAngle: .pi, endAngle: 0, clockwise: false)
        c.strokePath()
    }
    static let candadoAbierto = dibujar { c, _ in
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 5.4, y: 10.6, width: 13.2, height: 9.4), cornerWidth: 2.2, cornerHeight: 2.2)
        c.addPath(p); c.strokePath()
        c.addArc(center: CGPoint(x: 16.6, y: 10.4), radius: 3.8, startAngle: .pi, endAngle: .pi * 1.75, clockwise: false)
        c.strokePath()
    }
    static let destello = dibujar { c, _ in
        poli(c, [(12, 3.6), (14, 9.6), (20, 11.6), (14, 13.6), (12, 19.6), (10, 13.6), (4, 11.6), (10, 9.6)])
        c.fillEllipse(in: CGRect(x: 18, y: 4.4, width: 2.4, height: 2.4))
    }
    static let chincheta = dibujar { c, _ in
        poli(c, [(9, 3.6), (15, 3.6), (14, 9.6), (17.6, 13.2), (6.4, 13.2), (10, 9.6)])
        linea(c, (12, 13.2), (12, 20.4))
    }
    static let esquina = dibujar { c, _ in
        poli(c, [(5, 19), (5, 10), (10, 5), (19, 5)], cerrar: false)
    }
    static let recortar = dibujar { c, _ in
        linea(c, (7, 3), (7, 17)); linea(c, (3, 7), (17, 7))
        linea(c, (7, 17), (21, 17)); linea(c, (17, 7), (17, 21))
    }
    static let basura = dibujar { c, _ in
        linea(c, (4.4, 6.6), (19.6, 6.6))
        poli(c, [(6.6, 6.6), (7.6, 20), (16.4, 20), (17.4, 6.6)], cerrar: false)
        poli(c, [(9.4, 6.6), (9.4, 4), (14.6, 4), (14.6, 6.6)], cerrar: false)
        linea(c, (10.4, 10), (10.8, 16.6)); linea(c, (13.6, 10), (13.2, 16.6))
    }
    static let duplicar = dibujar { c, _ in
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 8, y: 8, width: 12, height: 12), cornerWidth: 2.2, cornerHeight: 2.2)
        c.addPath(p); c.strokePath()
        poli(c, [(15.6, 4.6), (4.6, 4.6), (4.6, 15.6)], cerrar: false)
    }
    /// AGRUPAR y DESAGRUPAR, otro PAR: dos piezas y el MARCO de puntos que las
    /// abraza. El marco es lo que significa "grupo" —agrupar lo pone,
    /// desagrupar lo quita— y por eso es lo unico que cambia entre los dos.
    static let agrupar = dibujar { c, _ in
        for r in [CGRect(x: 7, y: 7, width: 7, height: 7), CGRect(x: 12, y: 12, width: 7, height: 7)] {
            let p = CGMutablePath()
            p.addRoundedRect(in: r, cornerWidth: 1.6, cornerHeight: 1.6)
            c.addPath(p); c.strokePath()
        }
        c.saveGState()
        c.setLineDash(phase: 0, lengths: [2.2, 2])
        c.stroke(CGRect(x: 3.6, y: 3.6, width: 18.8, height: 18.8))
        c.restoreGState()
    }
    static let desagrupar = dibujar { c, _ in
        for r in [CGRect(x: 4.4, y: 4.4, width: 8, height: 8), CGRect(x: 13.6, y: 13.6, width: 8, height: 8)] {
            let p = CGMutablePath()
            p.addRoundedRect(in: r, cornerWidth: 1.8, cornerHeight: 1.8)
            c.addPath(p); c.strokePath()
        }
    }
    /// AL FRENTE y AL FONDO, un PAR: dos cuadrados solapados donde el LLENO es
    /// el que manda. La versión anterior mezclaba corchetes con relleno y los dos
    /// iconos no se leían como opuestos del mismo gesto.
    static let alFrente = dibujar { c, _ in
        let atras = CGMutablePath()
        atras.addRoundedRect(in: CGRect(x: 4.4, y: 4.4, width: 11, height: 11), cornerWidth: 2, cornerHeight: 2)
        c.addPath(atras); c.strokePath()
        let frente = CGMutablePath()
        frente.addRoundedRect(in: CGRect(x: 8.6, y: 8.6, width: 11, height: 11), cornerWidth: 2, cornerHeight: 2)
        c.addPath(frente); c.setFillColor(NSColor.black.cgColor); c.fillPath()
    }
    static let alFondo = dibujar { c, _ in
        let atras = CGMutablePath()
        atras.addRoundedRect(in: CGRect(x: 4.4, y: 4.4, width: 11, height: 11), cornerWidth: 2, cornerHeight: 2)
        c.addPath(atras); c.setFillColor(NSColor.black.cgColor); c.fillPath()
        let frente = CGMutablePath()
        frente.addRoundedRect(in: CGRect(x: 8.6, y: 8.6, width: 11, height: 11), cornerWidth: 2, cornerHeight: 2)
        c.addPath(frente); c.setStrokeColor(NSColor.white.cgColor); c.setLineWidth(3.2); c.strokePath()
        c.addPath(frente); c.setStrokeColor(NSColor.black.cgColor); c.setLineWidth(1.6); c.strokePath()
    }
    static let tresPuntos = dibujar { c, _ in
        for x in [6.4, 12.0, 17.6] { c.fillEllipse(in: CGRect(x: x - 1.3, y: 10.7, width: 2.6, height: 2.6)) }
    }
    /// DESHACER: una flecha que da la vuelta por arriba y apunta a la izquierda.
    ///
    /// ⚠️ La versión anterior era un arco de 200° con tres líneas sueltas: en la
    /// barra se veía como un fragmento de círculo roto, imposible de reconocer.
    /// Daniel los señaló sin poder nombrarlos, y con razón — a 18 px un arco sin
    /// punta no es una flecha, es una raya curva.
    /**
     * DESHACER, portado del referente: `M4 8.5h9.5a5.5 5.5 0 010 11H8`.
     *
     * ⚠️ Mis dos intentos anteriores fueron a ojo y los dos salieron mal — un
     * arco sin punta primero, un gancho después. El referente tenía la forma
     * resuelta desde el principio: asta horizontal arriba, media vuelta de radio
     * 5.5 hacia abajo, y una punta en CHEVRON —no rellena— a la izquierda.
     *
     * Es la tercera vez hoy que escribo de memoria con el original a un Read de
     * distancia. Aquí está la geometría exacta, no una aproximación.
     */
    static let deshacer = dibujar { c, _ in
        c.move(to: CGPoint(x: 4, y: 8.5))
        c.addLine(to: CGPoint(x: 13.5, y: 8.5))
        // El arco de radio 5.5 con barrido grande: de (13.5,8.5) a (13.5,19.5).
        c.addArc(tangent1End: CGPoint(x: 19, y: 8.5), tangent2End: CGPoint(x: 19, y: 19.5), radius: 5.5)
        c.addLine(to: CGPoint(x: 19, y: 14))
        c.addArc(tangent1End: CGPoint(x: 19, y: 19.5), tangent2End: CGPoint(x: 8, y: 19.5), radius: 5.5)
        c.addLine(to: CGPoint(x: 8, y: 19.5))
        c.strokePath()
        poli(c, [(7.5, 5), (4, 8.5), (7.5, 12)], cerrar: false)
    }
    /// REHACER: el mismo trazo, espejado. `M20 8.5h-9.5a5.5 5.5 0 000 11H16`.
    static let rehacer = dibujar { c, _ in
        c.saveGState()
        c.translateBy(x: 24, y: 0); c.scaleBy(x: -1, y: 1)
        c.move(to: CGPoint(x: 4, y: 8.5))
        c.addLine(to: CGPoint(x: 13.5, y: 8.5))
        c.addArc(tangent1End: CGPoint(x: 19, y: 8.5), tangent2End: CGPoint(x: 19, y: 19.5), radius: 5.5)
        c.addLine(to: CGPoint(x: 19, y: 14))
        c.addArc(tangent1End: CGPoint(x: 19, y: 19.5), tangent2End: CGPoint(x: 8, y: 19.5), radius: 5.5)
        c.addLine(to: CGPoint(x: 8, y: 19.5))
        c.strokePath()
        poli(c, [(7.5, 5), (4, 8.5), (7.5, 12)], cerrar: false)
        c.restoreGState()
    }
    static let descargar = dibujar { c, _ in
        linea(c, (12, 3.6), (12, 15))
        poli(c, [(7.4, 10.6), (12, 15.2), (16.6, 10.6)], cerrar: false)
        poli(c, [(4.4, 15.6), (4.4, 20), (19.6, 20), (19.6, 15.6)], cerrar: false)
    }
    static let fondoLiso = dibujar { c, _ in
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 4, y: 4, width: 16, height: 16), cornerWidth: 2.4, cornerHeight: 2.4)
        c.addPath(p); c.strokePath()
    }
    static let fondoPuntos = dibujar { c, _ in
        for y in [7.0, 12.0, 17.0] { for x in [7.0, 12.0, 17.0] {
            c.fillEllipse(in: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2))
        } }
    }
    static let fondoCuadricula = dibujar { c, _ in
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 4, y: 4, width: 16, height: 16), cornerWidth: 2.4, cornerHeight: 2.4)
        c.addPath(p); c.strokePath()
        linea(c, (4, 12), (20, 12)); linea(c, (12, 4), (12, 20))
    }
    static func linea(_ estilo: String) -> NSImage {
        dibujar { c, _ in
            c.setLineWidth(2.2); c.setLineCap(.round)
            switch estilo {
            case "dashed": c.setLineDash(phase: 0, lengths: [4.4, 3])
            case "dotted": c.setLineDash(phase: 0, lengths: [0.1, 4])
            default: break
            }
            linea(c, (3.4, 12), (20.6, 12))
        }
    }
    static func ruta(_ tipo: String) -> NSImage {
        dibujar { c, _ in
            switch tipo {
            case "recta": poli(c, [(4, 19), (20, 5)], cerrar: false)
            case "curva":
                c.move(to: CGPoint(x: 4, y: 19))
                c.addCurve(to: CGPoint(x: 20, y: 5), control1: CGPoint(x: 12, y: 19), control2: CGPoint(x: 12, y: 5))
                c.strokePath()
            default: poli(c, [(4, 19), (12, 19), (12, 5), (20, 5)], cerrar: false)
            }
        }
    }
    /// La punta de un conector, para elegirla en la barra.
    static func punta(_ tipo: String, invertida: Bool = false) -> NSImage {
        dibujar { c, _ in
            if invertida { c.translateBy(x: 24, y: 0); c.scaleBy(x: -1, y: 1) }
            linea(c, (3, 12), (14, 12))
            switch tipo {
            case "ninguna": break
            case "circulo": c.fillEllipse(in: CGRect(x: 14.4, y: 9.4, width: 5.2, height: 5.2))
            case "barra": c.setLineWidth(2.4); linea(c, (17, 6.4), (17, 17.6))
            case "rombo":
                c.move(to: CGPoint(x: 20.6, y: 12)); c.addLine(to: CGPoint(x: 17, y: 8.4))
                c.addLine(to: CGPoint(x: 13.4, y: 12)); c.addLine(to: CGPoint(x: 17, y: 15.6))
                c.closePath(); c.fillPath()
            case "triangulo":
                c.move(to: CGPoint(x: 20.6, y: 12)); c.addLine(to: CGPoint(x: 13.4, y: 7.6))
                c.addLine(to: CGPoint(x: 13.4, y: 16.4)); c.closePath(); c.fillPath()
            default:
                poli(c, [(14, 7.6), (20.6, 12), (14, 16.4)], cerrar: false)
            }
        }
    }
    /// La clase de una arista: el mismo lenguaje de dos canales que el tema.
    static func clase(_ k: String) -> NSImage {
        dibujar { c, _ in
            c.setLineCap(.round)
            switch k {
            case "agente": c.setLineWidth(2.2); c.setLineDash(phase: 0, lengths: [0.1, 3.6])
            case "fragil": c.setLineWidth(2.2); c.setLineDash(phase: 0, lengths: [4.4, 3])
            case "hueco":  c.setLineWidth(1.2); c.setLineDash(phase: 0, lengths: [3, 3])
            default:       c.setLineWidth(1.8)
            }
            linea(c, (3.4, 12), (20.6, 12))
        }
    }
    static let chevronArriba = dibujar { c, _ in
        c.move(to: CGPoint(x: 6, y: 14.5)); c.addLine(to: CGPoint(x: 12, y: 8.5))
        c.addLine(to: CGPoint(x: 18, y: 14.5)); c.strokePath()
    }
    /// Una barra del grosor pedido, para elegirlo viendolo.
    static func grosor(_ g: Double) -> NSImage {
        dibujar { c, _ in
            // ACOTADO: a tamaño real, 20 px llenan la casilla y las dos muestras
            // más gruesas se ven como el mismo círculo negro.
            let h = max(2, min(9, g * 0.8))
            let r = CGRect(x: 3.4, y: 12 - h / 2, width: 17.2, height: h)
            let p = CGMutablePath()
            p.addRoundedRect(in: r, cornerWidth: h / 2, cornerHeight: h / 2)
            c.addPath(p); c.fillPath()
        }
    }
    static let figuras = dibujar { c, _ in
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 3.6, y: 3.6, width: 9.6, height: 9.6), cornerWidth: 1.8, cornerHeight: 1.8)
        c.addPath(p); c.strokePath()
        c.addEllipse(in: CGRect(x: 11.4, y: 11.4, width: 9.2, height: 9.2)); c.strokePath()
    }
    /// Las tres FORMAS de flecha: con codos, recta y curva. Son variantes de la
    /// misma herramienta, igual que las ocho figuras lo son del rectángulo.
    static func flecha(_ forma: String) -> NSImage {
        dibujar { c, _ in
            // El asta acompaña a la familia sólida del rail: 1.6 se veía de
            // otra casa junto a las siluetas llenas.
            c.setLineWidth(2.6)
            switch forma {
            // ⚠️ La punta de una flecha DIAGONAL se ve más chica que la de una
            // recta al mismo tamaño: el ojo la mide contra la longitud del asta,
            // que en diagonal es mayor. Las dos diagonales llevan punta grande.
            case "recta":
                c.move(to: CGPoint(x: 4.4, y: 19.6)); c.addLine(to: CGPoint(x: 16.4, y: 7.6))
                c.strokePath()
                cabeza(c, desde: CGPoint(x: 14.4, y: 9.6), hasta: CGPoint(x: 20.2, y: 3.8), largo: 7.4, ancho: 4.2)
            case "curva":
                c.move(to: CGPoint(x: 4.2, y: 19.8))
                c.addCurve(to: CGPoint(x: 17.4, y: 6.6),
                           control1: CGPoint(x: 5.4, y: 11.2), control2: CGPoint(x: 11.6, y: 7.4))
                c.strokePath()
                cabeza(c, desde: CGPoint(x: 14.6, y: 8.6), hasta: CGPoint(x: 20.4, y: 4.2), largo: 7.4, ancho: 4.2)
            default:
                poli(c, [(4.2, 19.8), (4.2, 9.2), (16.4, 9.2)], cerrar: false)
                cabeza(c, desde: CGPoint(x: 14.4, y: 9.2), hasta: CGPoint(x: 20.4, y: 9.2))
            }
        }
    }

    /// Una punta de flecha RELLENA. A 18 px una punta de tres líneas se lee como
    /// un garabato; rellena se lee como flecha.
    private static func cabeza(_ c: CGContext, desde a: CGPoint, hasta b: CGPoint,
                               largo l: Double = 6.2, ancho w: Double = 3.4) {
        let ang = atan2(b.y - a.y, b.x - a.x)
        c.move(to: b)
        c.addLine(to: CGPoint(x: b.x - cos(ang) * l - sin(ang) * w, y: b.y - sin(ang) * l + cos(ang) * w))
        c.addLine(to: CGPoint(x: b.x - cos(ang) * l + sin(ang) * w, y: b.y - sin(ang) * l - cos(ang) * w))
        c.closePath(); c.fillPath()
    }

    /// El interruptor del PANEL: la misma metáfora que macOS usa en todas sus
    /// apps con barra lateral — un rectángulo con su columna izquierda marcada.
    static let panel = dibujar { c, _ in
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 3.4, y: 5.4, width: 17.2, height: 13.2),
                         cornerWidth: 2.4, cornerHeight: 2.4)
        c.addPath(p); c.strokePath()
        linea(c, (10.2, 5.4), (10.2, 18.6))
        c.fill(CGRect(x: 4.9, y: 8.2, width: 4, height: 1.5))
        c.fill(CGRect(x: 4.9, y: 11.4, width: 4, height: 1.5))
    }

    /**
     * ⚠️ OCHO RAYOS ALREDEDOR DE UN CIRCULO SON UN SOL, NO UN ENGRANE.
     *
     * La version anterior dibujaba el nucleo y ocho lineas radiales sueltas —su
     * propio comentario decia "menos se lee como un sol" y con ocho se leia
     * igual—. Daniel: *"asegúrate de que el icono de la esquina superior derecha
     * sea un engrane, no el actual"*. Un engrane no son rayos: es UN contorno
     * cerrado que sube al diente y baja al valle, con el eje hueco en medio. Es
     * como lo dibujan Lucide y SF Symbols, y es lo que la vista reconoce sin
     * tener que leerlo.
     */
    static let engrane = dibujar { c, _ in
        let n = 8, paso = 2 * Double.pi / 8
        let fuera = 10.2, dentro = 7.2
        func p(_ a: Double, _ r: Double) -> CGPoint {
            CGPoint(x: 12 + cos(a) * r, y: 12 + sin(a) * r)
        }
        var camino: [CGPoint] = []
        for i in 0..<n {
            let s = Double(i) * paso - paso / 2
            camino.append(p(s + paso * 0.08, fuera))
            camino.append(p(s + paso * 0.42, fuera))
            camino.append(p(s + paso * 0.58, dentro))
            camino.append(p(s + paso * 0.92, dentro))
        }
        c.setLineJoin(.round)
        c.move(to: camino[0])
        for q in camino.dropFirst() { c.addLine(to: q) }
        c.closePath()
        c.strokePath()
        // El eje. Sin el hueco central el engrane se lee como una estrella.
        c.addEllipse(in: CGRect(x: 12 - 3.4, y: 12 - 3.4, width: 6.8, height: 6.8))
        c.strokePath()
    }

    static let interrogacion = dibujar { c, _ in
        c.addArc(center: CGPoint(x: 12, y: 8.6), radius: 3.8, startAngle: .pi * 0.9, endAngle: .pi * 0.3, clockwise: false)
        c.strokePath()
        linea(c, (12, 12.4), (12, 15.4))
        c.fillEllipse(in: CGRect(x: 10.8, y: 18, width: 2.4, height: 2.4))
    }
    /**
     * RECOMPILAR: el texto entra por la izquierda, sale hecho geometría.
     *
     * ⚠️ La versión anterior se salía de su caja: los renglones iban centrados
     * en y=12 pero el galón vivía entre 4.6 y 14.6 —centro 9.6— y llegaba hasta
     * x=21 de 24. Dos ejes distintos en un icono de 18 px se leen como un dibujo
     * torcido, y Daniel lo cazó antes que la hoja de contacto. Ahora las dos
     * mitades comparten el eje y el galón cabe con el mismo aire que los demás.
     */
    static let compilar = dibujar { c, _ in
        poli(c, [(4.2, 7.4), (13.2, 7.4)], cerrar: false)
        poli(c, [(4.2, 12.0), (11.0, 12.0)], cerrar: false)
        poli(c, [(4.2, 16.6), (13.2, 16.6)], cerrar: false)
        poli(c, [(15.6, 7.6), (20.0, 12.0), (15.6, 16.4)], cerrar: false)
    }
}
