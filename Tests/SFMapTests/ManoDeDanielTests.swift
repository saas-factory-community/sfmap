import XCTest
import AppKit
@testable import SFMap

/**
 * LO QUE LA MANO DE DANIEL PIERDE CUANDO NADIE MIRA (26 ago 2026).
 *
 * Tres fallos del mismo día, los tres invisibles desde fuera: el trabajo no
 * daba error, simplemente dejaba de estar. Se prueban aquí porque ninguno se
 * ve mirando la pantalla — se ven en el estado, después.
 */
final class ManoDeDanielTests: XCTestCase {

    private func el(_ id: String, _ x: Double = 0) -> Elemento {
        Elemento(.objeto(["id": .texto(id), "type": .texto("shape"),
                          "x": .numero(x), "y": .numero(0),
                          "width": .numero(100), "height": .numero(50)]))
    }

    /**
     * ⌘Z DEJABA DE DESHACER tras una recarga remota.
     *
     * Daniel borró unos elementos, el generador escribió por el otro lado, la
     * app se enteró y recargó sola — y el `limpiar()` de `cargar` le vació la
     * historia por debajo: *"el comando zeta no funcionó, ahorita lo presiono
     * y ya no recupero algo que eliminé"*.
     */
    func testLaRecargaRemotaNoSeLlevaElDeshacer() {
        let doc = Documento()
        doc.cargar([el("a"), el("b")])
        doc.seleccion = ["b"]
        doc.borrarSeleccion()
        XCTAssertEqual(doc.elementos.count, 1)

        // Llega la versión de la nube (el generador escribió algo más).
        doc.cargar([el("a"), el("c")], recarga: true)
        XCTAssertTrue(doc.historial.puedeDeshacer, "la recarga NO borra la historia")

        doc.deshacer()
        XCTAssertTrue(doc.elementos.contains { $0.id == "b" }, "⌘Z repone lo borrado")
        XCTAssertTrue(doc.elementos.contains { $0.id == "c" },
                      "y sin tirar lo que llegó de la nube: el historial son parches por id")
    }

    /// Abrir OTRO lienzo sí empieza de cero: ahí la historia no habla de lo
    /// que hay en pantalla, y deshacer traería elementos de otra página.
    func testCambiarDePaginaSiLimpiaLaHistoria() {
        let doc = Documento()
        doc.cargar([el("a")])
        doc.seleccion = ["a"]
        doc.borrarSeleccion()
        doc.cargar([el("z")])
        XCTAssertFalse(doc.historial.puedeDeshacer)
    }

    /**
     * ⛔ EL GRANDE: UN ARRASTRE NUNCA MARCABA SUCIO, ASÍ QUE NUNCA SE GUARDABA.
     *
     * Los cambios de dentro de un gesto van por `volatil` (avisa con
     * `persistente: false`, para no escribir en cada fotograma del arrastre) y
     * `cerrarGesto` registraba el paso de deshacer SIN avisar de que el
     * documento había cambiado. Resultado: mover, redimensionar, girar o
     * doblar con el ratón se quedaba en memoria y se perdía en la siguiente
     * relectura. Daniel, tres veces en una tarde: *"los logos los centro y el
     * cuadro lo cubro de blanco, regreso y vuelve a estar así"*.
     *
     * Y colocar un lienzo es CASI TODO arrastres: se perdía casi todo.
     */
    func testCerrarUnGestoMarcaElDocumentoComoSucio() {
        let doc = Documento()
        doc.cargar([el("a")])
        var persistentes = 0
        doc.alCambiar = { p in if p { persistentes += 1 } }

        doc.abrirGesto()
        doc.mover(["a"], dx: 120, dy: 40)          // el arrastre, fotograma a fotograma
        XCTAssertEqual(persistentes, 0, "durante el arrastre NO se guarda")
        doc.cerrarGesto("mover")
        XCTAssertEqual(persistentes, 1, "al soltar SÍ: si no, el movimiento no se guarda jamás")
        XCTAssertTrue(doc.historial.puedeDeshacer)
    }

    /// Un gesto que no movió nada no gasta guardado ni paso de deshacer:
    /// pulsar y soltar sobre una figura no es una edición.
    func testUnGestoQueNoCambioNadaNoMarcaSucio() {
        let doc = Documento()
        doc.cargar([el("a")])
        var persistentes = 0
        doc.alCambiar = { p in if p { persistentes += 1 } }
        doc.abrirGesto()
        doc.cerrarGesto("mover")
        XCTAssertEqual(persistentes, 0)
        XCTAssertFalse(doc.historial.puedeDeshacer)
    }

    /**
     * AGRUPAR NO APARECÍA EN EL PANEL DE «…».
     *
     * El documento sabía agrupar desde el primer día y ⌘G funcionaba, pero el
     * único sitio donde se MIRA qué se puede hacer con una selección no lo
     * listaba. Daniel, con seis logos seleccionados: *"mira cómo no hay para
     * agrupar componentes"*. Una capacidad que no aparece donde se busca no
     * existe.
     */
    @MainActor
    func testElPanelDeMasOfreceAgrupar() {
        let barra = enMarco()
        barra.seleccion = [el("a"), el("b", 200)]
        barra.abrirPanelDePrueba("mas")
        XCTAssertTrue(titulos(barra).contains { $0.hasPrefix("Agrupar") },
                      "con dos o más seleccionados, agrupar está a la vista")
    }

    /// Con UNO solo no se ofrece: agrupar uno no significa nada, y una fila
    /// que nunca hace nada enseña que el panel miente.
    @MainActor
    func testConUnSoloElementoNoSeOfreceAgrupar() {
        let barra = enMarco()
        barra.seleccion = [el("a")]
        barra.abrirPanelDePrueba("mas")
        XCTAssertFalse(titulos(barra).contains { $0.hasPrefix("Agrupar") })
    }

    /// Y DESAGRUPAR solo cuando hay grupo que deshacer.
    @MainActor
    func testDesagruparSoloSiHayGrupo() {
        let barra = enMarco()
        var a = el("a"), b = el("b", 200)
        a.crudo = a.crudo.con(["groupId": .texto("g1")])
        b.crudo = b.crudo.con(["groupId": .texto("g1")])
        barra.seleccion = [a, b]
        barra.abrirPanelDePrueba("mas")
        XCTAssertTrue(titulos(barra).contains { $0.hasPrefix("Desagrupar") })
    }

    /**
     * BAJAR TAMAÑO NO MUEVE EL CONTROL DEBAJO DEL CURSOR.
     *
     * La tipografía remaqueta las cajas seleccionadas. Si la barra vuelve a
     * anclarse durante ese mismo clic, el botón de disminuir huye y el clic
     * siguiente cae en el lienzo vacío, que borra la selección múltiple.
     */
    @MainActor
    func testLaBarraNoHuyeMientrasEditaLaSeleccion() {
        let raiz = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        let barra = BarraContextual(frame: .zero)
        raiz.addSubview(barra)
        barra.seleccion = [el("a"), el("b", 500)]

        let camara = Camara(x: 0, y: 0, zoom: 1)
        barra.reconstruir(caja: NSRect(x: -300, y: -100, width: 900, height: 300),
                          camara: camara, viewport: raiz.bounds.size)
        let origen = barra.frame.origin

        // La caja se encogió y cambió de centro, justo lo que hace remaquetar
        // al bajar el tamaño de varios componentes.
        barra.reconstruir(caja: NSRect(x: -100, y: -40, width: 380, height: 120),
                          camara: camara, viewport: raiz.bounds.size,
                          conservarPosicion: true)

        XCTAssertEqual(barra.frame.origin.x, origen.x, accuracy: 0.001)
        XCTAssertEqual(barra.frame.origin.y, origen.y, accuracy: 0.001)
        XCTAssertEqual(barra.seleccion.count, 2)
    }

    /// ⚠️ La barra NECESITA una vista madre: sus paneles se cuelgan del
    /// `superview`, no de ella. Sin madre el panel se construye y se tira, y
    /// la prueba no encuentra nada — pareciendo un fallo de la fila que busca.
    @MainActor
    private func enMarco() -> BarraContextual {
        let raiz = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        let barra = BarraContextual(frame: NSRect(x: 100, y: 500, width: 600, height: 44))
        raiz.addSubview(barra)
        return barra
    }

    @MainActor
    private func titulos(_ barra: BarraContextual) -> [String] {
        (barra.superview?.subviews ?? []).flatMap { $0.subviews }
            .compactMap { ($0 as? NSButton)?.title }
    }
}
