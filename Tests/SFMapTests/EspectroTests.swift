import XCTest
import AppKit
@testable import SFMap

/**
 * EL ESPECTRO, MEDIDO.
 *
 * Nació porque el gradiente vivía SOLO en la paleta del lápiz y Daniel pidió
 * que estuviera "en múltiples componentes si no es que en todos donde incluimos
 * colores". Sacar un mecanismo de su instrumento es exactamente donde se cuelan
 * las regresiones silenciosas: el arcoíris se pinta igual, pero el color que
 * DEVUELVE cambia según de dónde partas. Eso es lo que se mide aquí.
 */
final class EspectroTests: XCTestCase {

    private func rgb(_ h: String) -> NSColor { (NSColor(hex: h) ?? .black).usingColorSpace(.deviceRGB)! }

    private let cuadro = NSRect(x: 0, y: 10, width: 174, height: 80)
    private let tono   = NSRect(x: 0, y: 96, width: 174, height: 14)

    /**
     * ⭐ LA PRUEBA QUE JUSTIFICA EL CUADRO.
     *
     * La versión de dos barras metía saturación y brillo en UN eje: del blanco
     * al tono puro y de ahí al negro. Esa curva pasa por brillo 1 o por
     * saturación máxima, nunca por el medio — así que los tonos MUDOS (un
     * pizarra, un caqui, un vino apagado) no existían en el picker. Daniel:
     * *"es difícil escoger el color exacto"*. No era pulso: faltaba un eje.
     */
    func testElCuadroAlcanzaLosTonosMudos() {
        let pizarra = rgb("#64748b")
        XCTAssertLessThan(pizarra.saturationComponent, 0.35, "premisa: saturación media-baja")
        XCTAssertLessThan(pizarra.brightnessComponent, 0.7, "premisa: brillo medio")
        // Su posición existe en el cuadro y devuelve ESE color, no uno parecido.
        let p = Espectro.punto(pizarra, en: cuadro)
        let vuelta = Espectro.delCuadro(p, en: cuadro, tono: pizarra.hueComponent)
            .usingColorSpace(.deviceRGB)!
        XCTAssertEqual(vuelta.saturationComponent, pizarra.saturationComponent, accuracy: 0.02)
        XCTAssertEqual(vuelta.brightnessComponent, pizarra.brightnessComponent, accuracy: 0.02)
    }

    /// Las cuatro esquinas dicen lo que prometen: blanco, tono puro, negro.
    func testLasEsquinasDelCuadro() {
        let arribaIzq = Espectro.delCuadro(NSPoint(x: 0, y: 10), en: cuadro, tono: 0.5)
            .usingColorSpace(.deviceRGB)!
        XCTAssertEqual(arribaIzq.brightnessComponent, 1, accuracy: 0.01)
        XCTAssertEqual(arribaIzq.saturationComponent, 0, accuracy: 0.01, "arriba-izquierda es BLANCO")
        let arribaDer = Espectro.delCuadro(NSPoint(x: 174, y: 10), en: cuadro, tono: 0.5)
            .usingColorSpace(.deviceRGB)!
        XCTAssertEqual(arribaDer.saturationComponent, 1, accuracy: 0.01, "arriba-derecha es el tono PURO")
        let abajo = Espectro.delCuadro(NSPoint(x: 90, y: 90), en: cuadro, tono: 0.5)
            .usingColorSpace(.deviceRGB)!
        XCTAssertEqual(abajo.brightnessComponent, 0, accuracy: 0.01, "la fila de abajo es NEGRO")
    }

    /// Y un punto que se sale por arrastrar se pega al filo, no da la vuelta.
    func testElCuadroSeAcotaEnLosFilos() {
        let fuera = Espectro.delCuadro(NSPoint(x: -300, y: -300), en: cuadro, tono: 0.5)
            .usingColorSpace(.deviceRGB)!
        XCTAssertEqual(fuera.saturationComponent, 0, accuracy: 0.01)
        XCTAssertEqual(fuera.brightnessComponent, 1, accuracy: 0.01)
    }

    /**
     * ⭐ GIRAR EL TONO NO DESTRUYE LO QUE EL CUADRO ACABA DE AJUSTAR.
     *
     * Es la regla de cualquier picker y la razón de que el cuadro pueda ser
     * pequeño: buscas la mezcla una vez y luego recorres tonos con ella puesta.
     */
    func testElTonoConservaSaturacionYBrillo() {
        let base = rgb("#64748b")
        let girado = Espectro.color(NSPoint(x: 87, y: 100), zona: .tono, cuadro: cuadro,
                                    tono: tono, base: base, hayColor: true)
            .usingColorSpace(.deviceRGB)!
        XCTAssertEqual(girado.hueComponent, 0.5, accuracy: 0.02, "el tono es el que se pidió")
        XCTAssertEqual(girado.saturationComponent, base.saturationComponent, accuracy: 0.02)
        XCTAssertEqual(girado.brightnessComponent, base.brightnessComponent, accuracy: 0.02)
    }

    /// Sin color del que partir manda `puntoNuevo`, que lo pone el panel: un
    /// relleno quiere pastel (sus dieciocho muestras lo son), un trazo no.
    func testSinColorMandaElPuntoDeSalidaDelPanel() {
        let pastel = Espectro.color(NSPoint(x: 87, y: 100), zona: .tono, cuadro: cuadro, tono: tono,
                                    base: rgb("#f2f2f5"), hayColor: false,
                                    puntoNuevo: NSPoint(x: 0.30, y: 0)).usingColorSpace(.deviceRGB)!
        XCTAssertEqual(pastel.saturationComponent, 0.30, accuracy: 0.02)
        XCTAssertEqual(pastel.brightnessComponent, 1, accuracy: 0.02)
        let vivo = Espectro.color(NSPoint(x: 87, y: 100), zona: .tono, cuadro: cuadro, tono: tono,
                                  base: rgb("#f2f2f5"), hayColor: false).usingColorSpace(.deviceRGB)!
        XCTAssertGreaterThan(vivo.saturationComponent, 0.7)
    }

    /**
     * Un gris NEUTRO no tiene tono: su `hueComponent` es 0 —rojo— y usarlo
     * pintaría el cuadro entero de rojo sin que nada en pantalla lo justifique.
     * Un gris que SÍ tira a un lado (el pizarra `#a8a8b3` es azulado) conserva
     * el suyo: ahí el tono es real, aunque apenas se vea.
     */
    func testSoloElGrisNeutroCedeElTono() {
        XCTAssertEqual(Espectro.matiz(rgb("#808080"), 0.75), 0.75, accuracy: 0.001)
        XCTAssertEqual(Espectro.matiz(rgb("#a8a8b3"), 0.75), rgb("#a8a8b3").hueComponent, accuracy: 0.01,
                       "un gris azulado sí tiene tono, y es el suyo")
        XCTAssertEqual(Espectro.matiz(rgb("#e5484d"), 0.75), rgb("#e5484d").hueComponent, accuracy: 0.001)
    }

    // ── Qué agarró el dedo ──────────────────────────────────────────────────

    func testCadaZonaEsLaSuya() {
        XCTAssertEqual(Espectro.zona(NSPoint(x: 80, y: 40), cuadro: cuadro, tono: tono), .cuadro)
        XCTAssertEqual(Espectro.zona(NSPoint(x: 80, y: 102), cuadro: cuadro, tono: tono), .tono)
        XCTAssertNil(Espectro.zona(NSPoint(x: 80, y: 200), cuadro: cuadro, tono: tono))
    }

    /**
     * ⭐ LA ZONA SE DECIDE AL PULSAR Y EL ARRASTRE LA CONSERVA.
     *
     * Con hit-test por posición en cada paso, salirte del cuadro por abajo hacía
     * saltar el color al arcoíris: la mano no soltó nada, pero el control cambió
     * de instrumento debajo del dedo.
     */
    func testUnArrastreQueSaleDelCuadroSigueSiendoDelCuadro() {
        let base = rgb("#e5484d")
        let c = Espectro.color(NSPoint(x: 174, y: 300), zona: .cuadro, cuadro: cuadro,
                               tono: tono, base: base, hayColor: true).usingColorSpace(.deviceRGB)!
        XCTAssertEqual(c.brightnessComponent, 0, accuracy: 0.01, "se pega al filo de abajo del CUADRO")
        XCTAssertEqual(Espectro.zona(NSPoint(x: 174, y: 300), cuadro: cuadro, tono: tono), nil,
                       "y por posición ya no sería de nadie: por eso la zona se recuerda")
    }

    // ── Los formatos ────────────────────────────────────────────────────────

    func testHexEsElFormatoQueGuardaElModelo() {
        XCTAssertEqual(Espectro.hex(rgb("#8C27F1")), "#8c27f1")
    }

    /**
     * ⭐ EL RESALTADO SALE TRANSLÚCIDO.
     *
     * Sus muestras son `rgba(...)` porque el texto tiene que seguir leyéndose
     * encima. Un espectro que emitiera hex opaco en ese panel taparía la única
     * cosa que el resaltado existe para señalar.
     */
    func testElResaltadoEmiteRgbaConSuAlfa() {
        let s = Espectro.rgba(rgb("#ffe050"), 0.55)
        XCTAssertEqual(s, "rgba(255,224,80,0.55)")
        XCTAssertEqual(NSColor(hex: s)?.alphaComponent ?? 0, 0.55, accuracy: 0.01,
            "y el modelo tiene que poder volver a leerlo")
    }

    /// El campo hex perdona: con almohadilla o sin ella, corto o largo.
    func testElCampoHexPerdonaComoSeEscriba() {
        XCTAssertEqual(Espectro.leer("#8C27F1").map { Espectro.hex($0) }, "#8c27f1")
        XCTAssertEqual(Espectro.leer("8C27F1").map { Espectro.hex($0) }, "#8c27f1")
        XCTAssertEqual(Espectro.leer("  #abc ").map { Espectro.hex($0) }, "#aabbcc")
        XCTAssertNil(Espectro.leer("no soy un color"))
        XCTAssertNil(Espectro.leer(""))
    }

    // ── El sitio que ocupa ──────────────────────────────────────────────────

    /**
     * La paleta CRECE con el espectro y crece exactamente lo que el espectro
     * mide, más la fila del hex. El panel calcula su alto con esta función: si
     * se desincronizan, el cuadro se pinta FUERA de la tarjeta — el mismo fallo
     * que ya costó la fila de grosores del lápiz.
     */
    func testLaPaletaPideSitioParaElEspectro() {
        let sin = VistaPaleta.alto(18, conMarca: true, conEspectro: false)
        let con = VistaPaleta.alto(18, conMarca: true, conEspectro: true)
        XCTAssertEqual(con - sin, Espectro.ALTO + 32)
    }

    /// Y el cuadro y la barra caben dentro de lo que el espectro pide.
    func testCuadroYBarraCabenEnSuAlto() {
        let (q, t) = Espectro.cajas(x: 0, y: 0, ancho: 174)
        XCTAssertGreaterThanOrEqual(q.minY, 0)
        XCTAssertGreaterThanOrEqual(t.minY, q.maxY)
        XCTAssertLessThanOrEqual(t.maxY, Espectro.ALTO)
    }

    /**
     * ⭐ LAS BANDAS DE LA PALETA DEL LÁPIZ NO SE PISAN.
     *
     * Su geometría estaba en números sueltos repartidos por `draw` y copiados a
     * mano en la escena que la pulsa. Ahora cada banda sale de la anterior, y
     * esto lo comprueba: si una crece y no se recolocan las de abajo, el panel
     * pinta encima de sí mismo y nadie se entera hasta verlo.
     */
    func testLasBandasDeLaPaletaDelLapizNoSePisan() {
        let tintas = PaletaTinta.Y_TINTAS + 44
        XCTAssertLessThanOrEqual(tintas, PaletaTinta.Y_ESPECTRO)
        XCTAssertLessThanOrEqual(PaletaTinta.Y_ESPECTRO + Espectro.ALTO, PaletaTinta.Y_GROSORES)
        XCTAssertLessThanOrEqual(PaletaTinta.Y_GROSORES + 30, PaletaTinta.Y_RECIENTES)
        XCTAssertLessThanOrEqual(PaletaTinta.Y_RECIENTES + Recientes.ALTO, PaletaTinta.ALTO)
    }
}

/**
 * TUS COLORES: la memoria de lo que se eligió a mano.
 *
 * Daniel, 30 ago: *"recordar los últimos colores escogidos manualmente… que ahí
 * se queden en memoria para conservar ciertos colores de mi gusto"*. El espectro
 * abrió la puerta a cualquier color y con eso trajo su problema: un tono que
 * buscaste arrastrando se perdía al cerrar el panel.
 */
final class RecientesTests: XCTestCase {

    /// ⚠️ Con su propio almacén: una prueba NO escribe en los ajustes de Daniel.
    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = UserDefaults(suiteName: "sfmap.pruebas.recientes")!
        suite.removePersistentDomain(forName: "sfmap.pruebas.recientes")
        Recientes.almacen = suite
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: "sfmap.pruebas.recientes")
        Recientes.almacen = .standard
        super.tearDown()
    }

    func testElUltimoVaPrimero() {
        Recientes.recordar("#111111", en: "relleno")
        Recientes.recordar("#222222", en: "relleno")
        XCTAssertEqual(Recientes.lista("relleno"), ["#222222", "#111111"])
    }

    /**
     * ⭐ REPETIR UN COLOR LO SUBE, NO LO DUPLICA.
     *
     * La fila mide seis. Gastar dos casillas en el mismo tono —que es lo que
     * pasa en cuanto vuelves a un color que te gusta— sería perder un tercio de
     * la memoria justo con el color que más usas.
     */
    func testUnColorRepetidoSubeEnVezDeDuplicarse() {
        for c in ["#111111", "#222222", "#333333"] { Recientes.recordar(c, en: "relleno") }
        Recientes.recordar("#111111", en: "relleno")
        XCTAssertEqual(Recientes.lista("relleno"), ["#111111", "#333333", "#222222"])
    }

    /// Y da igual cómo venga escrito: `#AABBCC` y `#aabbcc` son el mismo color.
    func testElMismoColorEnMayusculasNoSeDuplica() {
        Recientes.recordar("#aabbcc", en: "relleno")
        Recientes.recordar("#AABBCC", en: "relleno")
        XCTAssertEqual(Recientes.lista("relleno").count, 1)
    }

    func testLaFilaNoPasaDeSeis() {
        for i in 0..<12 { Recientes.recordar(String(format: "#%06x", i * 1000), en: "relleno") }
        XCTAssertEqual(Recientes.lista("relleno").count, Recientes.TOPE)
        XCTAssertEqual(Recientes.lista("relleno").first, String(format: "#%06x", 11 * 1000),
                       "y el que sobrevive arriba es el último")
    }

    /**
     * ⭐ CADA PANEL RECUERDA LO SUYO.
     *
     * Una sola lista global mezclaría los pasteles del relleno con los saturados
     * del trazo y con los `rgba` translúcidos del resaltado: tres formatos y
     * tres usos distintos en la misma fila de seis.
     */
    func testCadaPanelRecuerdaLoSuyo() {
        Recientes.recordar("#fde8e8", en: "relleno")
        Recientes.recordar("#e5484d", en: "contorno")
        XCTAssertEqual(Recientes.lista("relleno"), ["#fde8e8"])
        XCTAssertEqual(Recientes.lista("contorno"), ["#e5484d"])
    }

    /// El resaltado guarda su formato, no un hex.
    func testElResaltadoRecuerdaSuRgba() {
        Recientes.recordar(Espectro.rgba(NSColor.systemPink, 0.55), en: "resaltar")
        XCTAssertTrue(Recientes.lista("resaltar").first?.hasPrefix("rgba(") == true)
    }

    /**
     * ⭐ EL HUECO SE RESERVA AUNQUE ESTÉ VACÍO.
     *
     * Si la fila apareciera al guardar el primer color, nacería FUERA de la
     * tarjeta: el panel mide su caja al abrirse y no vuelve a medirla. Es el
     * mismo fallo que ya costó la fila de grosores del lápiz, y por eso el alto
     * no depende de cuántos colores haya guardados.
     */
    func testElAltoNoDependeDeCuantosHayaGuardados() {
        let vacio = VistaPaleta.alto(18, conMarca: true, conEspectro: true, conRecientes: true)
        for i in 0..<5 { Recientes.recordar(String(format: "#%06x", i * 1000), en: "relleno") }
        XCTAssertEqual(VistaPaleta.alto(18, conMarca: true, conEspectro: true, conRecientes: true), vacio)
        XCTAssertEqual(vacio - VistaPaleta.alto(18, conMarca: true, conEspectro: true), Recientes.ALTO)
    }

    /// Y la paleta del lápiz reserva el suyo en su alto fijo.
    func testLaPaletaDelLapizTambienReservaSuHueco() {
        XCTAssertEqual(PaletaTinta.ALTO, PaletaTinta.Y_RECIENTES + Recientes.ALTO)
    }
}
