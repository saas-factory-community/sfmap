import XCTest
import AppKit
@testable import SFMap

/**
 * LAS REGLAS DEL BISEL, medidas.
 *
 * Existen por un fallo concreto: la primera versión del cromo pintaba el fondo
 * con `layer.backgroundColor`, y al mover la pintura a `draw` los paneles que
 * seguían siendo `NSView` pelados dejaron de pintar NADA. No falla, no avisa —
 * simplemente hay un panel invisible con botones flotando encima. La única
 * forma de cazar eso sin un ojo humano es pedirle píxeles al pintor.
 */
final class EstiloTests: XCTestCase {

    /**
     * NINGÚN RÓTULO DEL RAIL SE CORTA. La tira mide 58 px y el rótulo vive en
     * una caja de 48; el 23 ago "Seleccionar" se pintó a 9 pt fijos y salió
     * "SELECCIO". Esta prueba recorre las VEINTICUATRO herramientas: si mañana
     * nace una con nombre largo, falla aquí y no en la pantalla de Daniel.
     */
    func testTodosLosRotulosDelRailCabenSinCortarse() {
        let caja: CGFloat = 48          // ancho del rail (58) menos sus márgenes
        for h in Herramienta.allCases {
            let texto = h.rotulo.uppercased()
            let f = Estilo.fuenteQueCabe(texto, ancho: caja, desde: 9, hasta: 7, peso: 700)
            let ancho = (texto as NSString).size(withAttributes: [.font: f]).width
            XCTAssertLessThanOrEqual(ancho, caja,
                "«\(texto)» mide \(ancho) px a \(f.pointSize) pt y la caja son \(caja)")
            XCTAssertGreaterThanOrEqual(f.pointSize, 7,
                "«\(texto)» tuvo que bajar de 7 pt: hace falta un `rotulo` más corto")
        }
    }

    /// Y el ajuste no encoge lo que ya cabía: una palabra corta se queda a 9 pt.
    func testUnRotuloCortoNoSeEncoge() {
        XCTAssertEqual(Estilo.fuenteQueCabe("GOMA", ancho: 48, desde: 9, hasta: 7, peso: 700).pointSize, 9)
    }


    /// Luminancia relativa aproximada, suficiente para comparar dos grises.
    private func luz(_ c: NSColor) -> Double {
        let s = c.usingColorSpace(.sRGB) ?? c
        return 0.2126 * Double(s.redComponent) + 0.7152 * Double(s.greenComponent)
             + 0.0722 * Double(s.blueComponent)
    }

    /// LA LUZ CAE DESDE ARRIBA. Es la regla raíz de Titaniumorphism (núcleo §6.1)
    /// y la que separa "metal" de "rectángulo gris": el filo de arriba tiene que
    /// ser más claro que el borde, y la cara de arriba más clara que la de abajo.
    /// Invertir un par por descuido no rompe nada — solo hace que la pieza
    /// parezca iluminada desde el suelo, y eso no se detecta leyendo hexes.
    func testLaLuzCaeDesdeArriba() {
        for t in [Tema.claro, Tema.oscuro] {
            let b = t.bisel
            XCTAssertGreaterThan(luz(b.filoAlto), luz(b.borde), "\(t.nombre): el filo no es más claro que el borde")
            XCTAssertGreaterThan(luz(b.top), luz(b.bot), "\(t.nombre): la cara de arriba no es la clara")
        }
    }

    /// El titanio del tema oscuro es OSCURO y el aluminio del claro es CLARO.
    /// Suena obvio y es justo el par que se cruza al copiar un bloque de tokens.
    func testCadaTemaEnSuMitadDelGris() {
        XCTAssertLessThan(luz(Tema.oscuro.bisel.mid), 0.2)
        XCTAssertGreaterThan(luz(Tema.claro.bisel.mid), 0.8)
    }

    /// EL ORO ES DE LA FAMILIA, no un naranja parecido. El núcleo de marca lista
    /// `#ff9101` y su variante oscura `#cc7301` como los dos únicos legítimos;
    /// cualquier otro sería el enésimo delta sin declarar.
    func testElOroEsElDeLaCasa() {
        func hex(_ c: NSColor) -> String {
            let s = c.usingColorSpace(.sRGB)!
            return String(format: "#%02x%02x%02x", Int(s.redComponent * 255 + 0.5),
                          Int(s.greenComponent * 255 + 0.5), Int(s.blueComponent * 255 + 0.5))
        }
        XCTAssertEqual(hex(Tema.oscuro.oro), "#ff9101")
        XCTAssertEqual(hex(Tema.claro.oro), "#cc7301")
    }

    // ── el pintor de verdad ─────────────────────────────────────────────────

    private final class Lienza: NSView {
        var tema = Tema.claro
        var pozo = false
        override func draw(_ r: NSRect) { Estilo.pintarBisel(self, tema, radio: 10, pozo: pozo) }
    }

    /// Devuelve el color de un píxel tras dibujar la vista en un mapa de bits.
    private func pixel(_ v: NSView, _ x: Int, _ y: Int) -> NSColor {
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return .clear }
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? .clear
    }

    /// EL BISEL PINTA. La prueba que faltaba: un panel que no dibuja se ve igual
    /// que uno que dibuja transparente, y los dos se ven "bien" en el código.
    func testElBiselPintaDeVerdad() {
        let v = Lienza(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        v.tema = .oscuro
        let centro = pixel(v, 60, 40)
        XCTAssertGreaterThan(centro.alphaComponent, 0.9, "el bisel no pintó nada")
        XCTAssertLessThan(luz(centro), 0.2, "el titanio no puede salir claro")
    }

    /**
     * EL TEXTO NO PUEDE DEPENDER DE QUIÉN DIBUJÓ ANTES.
     *
     * ⚠️ `CGContext.textMatrix` NO forma parte del estado gráfico: `saveGState` y
     * `restoreGState` no lo tocan (está escrito así en la guía de Quartz 2D). El
     * pintor volteaba cada renglón con la CTM y confiaba en que el text matrix
     * llegara limpio; el SEGUNDO lienzo dibujado en el mismo contexto salía con
     * todo su texto girado 180°.
     *
     * En la app hay un lienzo por ventana y por eso nunca se vio. Lo destapó la
     * hoja de contacto al pintar los dos temas de una pasada — y ése es el
     * argumento entero a favor de tener el sensor: no encontró un defecto de la
     * hoja, encontró uno del pintor.
     *
     * La prueba REPRODUCE el caso, no lo imita: pinta la misma tarjeta dos veces
     * seguidas en el mismo contexto y exige que las dos mitades salgan idénticas.
     * Un intento anterior ensuciaba el text matrix a mano y pasaba igual con y
     * sin el arreglo — un test que no puede fallar no es un test.
     */
    func testElTextoNoHeredaElEstadoDeQuienDibujoAntes() {
        let w = 300, alto = 160
        // La franja de abajo es para el rótulo: si se encimara con los lienzos
        // ensuciaría la comparación con píxeles que no son del pintor.
        let franja = 26
        let raiz = NSView(frame: NSRect(x: 0, y: 0, width: w * 2, height: alto + franja))
        let tarjeta = Elemento(.objeto([
            "id": .texto("t"), "type": .texto("shape"), "shape": .texto("rect"),
            "role": .texto("card"),
            "x": .numero(30), "y": .numero(40), "width": .numero(230), "height": .numero(70),
            "rotation": .numero(0), "zIndex": .numero(1), "opacity": .numero(1),
            "locked": .bool(false), "version": .numero(1),
            "createdAt": .numero(0), "updatedAt": .numero(0),
            "text": .lista([.objeto([
                "role": .texto("title"), "lines": .lista([.texto("diagnosticar")]),
            ])]),
        ]))
        func lienzo(_ x: Int) -> Lienzo {
            let l = Lienzo(frame: NSRect(x: CGFloat(x), y: CGFloat(franja),
                                        width: CGFloat(w), height: CGFloat(alto)))
            l.tema = .claro
            l.fondo = .liso
            l.doc.cargar([tarjeta])
            l.camara = Camara(x: 145, y: 75, zoom: 1)
            return l
        }
        /*
         * DOS lienzos idénticos CON CROMO EN MEDIO. El cromo es la pieza clave y
         * costó encontrarla: dos lienzos seguidos salen bien, porque `CTLineDraw`
         * solo mueve la posición del text matrix. Quien lo deja con una escala
         * puesta es el texto de AppKit —una `NSTextField`, un rótulo, cualquier
         * etiqueta del panel—, y como el text matrix no se guarda ni se
         * restaura con el estado gráfico, el siguiente lienzo hereda esa escala
         * y pinta todo su texto girado 180°.
         *
         * Por eso la app real lo tenía y una prueba de dos lienzos pelados no:
         * en la app SIEMPRE hay etiquetas entre medias.
         */
        raiz.addSubview(lienzo(0))
        let rotulo = NSTextField(labelWithString: "LIENZOS")
        rotulo.frame = NSRect(x: 4, y: 3, width: CGFloat(w * 2) - 8, height: 18)
        raiz.addSubview(rotulo)
        raiz.addSubview(lienzo(w))
        guard let rep = raiz.bitmapImageRepForCachingDisplay(in: raiz.bounds) else {
            return XCTFail("sin mapa de bits")
        }
        raiz.cacheDisplay(in: raiz.bounds, to: rep)

        let escala = rep.pixelsWide / (w * 2)
        /*
         * Se compara el INTERIOR, no el borde. Los últimos 16 px de cada lienzo
         * los ocupa el canto hundido, y ahí los dos hermanos sí difieren de
         * verdad: el de la izquierda proyecta su sombra derecha contra el
         * segundo lienzo y el de la derecha contra el vacío del mapa de bits.
         * Eso es correcto y no tiene nada que ver con lo que esta prueba vigila.
         */
        // El canto y su sombra ocupan hasta 24 px efectivos en el bitmap.
        let margen = 24 * escala
        func tinta(_ x0: Int) -> [Int] {
            var v: [Int] = []
            for y in stride(from: (franja + 16) * escala, to: rep.pixelsHigh - margen, by: 2) {
                for x in stride(from: x0 + margen, to: x0 + w * escala - margen, by: 2) {
                    v.append(Int((rep.colorAt(x: x, y: y)?.brightnessComponent ?? 1) * 255))
                }
            }
            return v
        }
        let izq = tinta(0), der = tinta(w * escala)
        XCTAssertTrue(izq.contains { $0 < 120 }, "el texto no llegó a pintarse")
        let distintos = zip(izq, der).filter { $0 != $1 }.count
        XCTAssertEqual(distintos, 0, "\(distintos) muestras cambiaron en el segundo lienzo")
    }

    /// UN POZO ES UN BISEL AL REVÉS, y tiene que notarse en el píxel de arriba.
    /// Si un día el parámetro deja de leerse, el buscador y el botón pulsado se
    /// verían idénticos a una tarjeta — y la gramática de profundidad (lo que
    /// sobresale se pulsa, lo que se hunde se llena) se pierde sin un error.
    func testElPozoInvierteLaLuz() {
        let alto = NSRect(x: 0, y: 0, width: 120, height: 80)
        let a = Lienza(frame: alto); a.tema = .claro; a.pozo = false
        let b = Lienza(frame: alto); b.tema = .claro; b.pozo = true
        // Fila 6 desde arriba del mapa de bits: dentro de la cara superior y
        // lejos del filo de 1 px, que es la misma en los dos.
        let arribaTarjeta = luz(pixel(a, 60, 6))
        let arribaPozo = luz(pixel(b, 60, 6))
        XCTAssertGreaterThan(arribaTarjeta, arribaPozo,
                             "la cara de arriba del pozo debería ser la oscura")
    }
}
