import XCTest
@testable import SFMap

/// SALTAR DE LIENZO CON 0-9 Y CON LAS FLECHAS. Lo que se prueba es el
/// VECINDARIO: qué lista ve el atajo. Si no es exactamente la que el panel
/// enseña, pulsar el 3 lleva a algo que en pantalla no es el cuarto.
final class NavegarLienzosTests: XCTestCase {

    private func p(_ id: String, _ n: String, _ c: String?) -> ResumenPagina {
        ResumenPagina(id: id, nombre: n, folderId: c, elementos: 0)
    }

    /// Llegan desordenadas (como del servidor) y salen como se leen.
    private lazy var todas = [
        p("b", "02 · Los ARNESES", "curso"),
        p("z", "The Machinery", "otra"),
        p("a", "00 · El Hook", "curso"),
        p("s", "Estándar de lienzo", nil),
        p("c", "10 · El cierre", "curso"),
        p("d", "01 · Los MODELOS", "curso"),
    ]

    func testSoloLosDeSuCarpetaYEnElOrdenDelPanel() {
        let v = Lateral.vecindario(todas, de: "b")
        XCTAssertEqual(v.map(\.id), ["a", "d", "b", "c"], "00, 01, 02, 10 — y nadie de otra carpeta")
    }

    /// ⚠️ El `10` va DESPUÉS del `02`, no entre el `01` y el `02`. Es el mismo
    /// criterio natural del panel; con un `<` de texto el capítulo 10 se
    /// colaría delante del 2 y el atajo mandaría al sitio equivocado.
    func testElDiezNoSeCuelaEntreElUnoYElDos() {
        XCTAssertEqual(Lateral.vecindario(todas, de: "a").last?.id, "c")
    }

    /// Un lienzo suelto tiene de vecinos a los demás sueltos: "SIN CARPETA" es
    /// un vecindario como cualquier otro, no un limbo sin atajos.
    func testLosSueltosSonUnVecindarioTambien() {
        XCTAssertEqual(Lateral.vecindario(todas, de: "s").map(\.id), ["s"])
    }

    /// Sin lienzo actual conocido, el vecindario es el de los sueltos — no la
    /// lista entera. Devolver TODO haría que el `0` saltara a un lienzo de otra
    /// carpeta sin que nada lo explique.
    func testSinActualNoDevuelveElMundoEntero() {
        XCTAssertEqual(Lateral.vecindario(todas, de: nil).map(\.id), ["s"])
    }

    /// Los límites: el 7 en una carpeta de cuatro no lleva a ningún sitio. Si
    /// cayera en el último, el 7 y el 3 acabarían en el mismo lienzo y el
    /// atajo dejaría de significar una posición.
    func testFueraDeRangoNoAdivina() {
        XCTAssertEqual(Lateral.enPosicion(todas, de: "b", 0), "a")
        XCTAssertEqual(Lateral.enPosicion(todas, de: "b", 3), "c")
        XCTAssertNil(Lateral.enPosicion(todas, de: "b", 7), "4 lienzos: el 7 no existe")
    }

    /// ⚠️ LO QUE SE PIDIO EXPLICITAMENTE: las flechas NO cruzan de carpeta.
    /// En el primero, "anterior" no existe; en el último, "siguiente" tampoco.
    /// Ni se envuelve ni se salta al vecindario de al lado — las dos cosas te
    /// dejarían en otro sitio del árbol sin que nada te avise.
    func testLasFlechasNoSalenDeLaCarpeta() {
        XCTAssertNil(Lateral.vecino(todas, de: "a", paso: -1), "en el primero no hay anterior")
        XCTAssertNil(Lateral.vecino(todas, de: "c", paso: 1), "en el último no hay siguiente")
        XCTAssertEqual(Lateral.vecino(todas, de: "a", paso: 1), "d")
        XCTAssertEqual(Lateral.vecino(todas, de: "b", paso: -1), "d")
    }

    /// Y tampoco alcanzan a los de otra carpeta ni por posición: "z" vive sola
    /// en "otra", así que su vecindario es de uno y ahí se acaba todo.
    func testUnaCarpetaDeUnoNoTienePorDondeSalir() {
        XCTAssertNil(Lateral.vecino(todas, de: "z", paso: 1))
        XCTAssertNil(Lateral.vecino(todas, de: "z", paso: -1))
        XCTAssertEqual(Lateral.enPosicion(todas, de: "z", 0), "z")
        XCTAssertNil(Lateral.enPosicion(todas, de: "z", 1))
    }
}

/// EL CURSOR DE CARPETAS: ← y → lo mueven SIN abrir nada; ↓ y ↑ entran a los
/// lienzos de donde esté el cursor. Los dos ejes hacen cosas de naturaleza
/// distinta y esa es toda la idea.
final class CursorCarpetasTests: XCTestCase {

    private func c(_ id: String, _ n: String, _ madre: String? = nil) -> Carpeta {
        Carpeta(id: id, nombre: n, madre: madre)
    }

    private lazy var carpetas = [
        c("z", "The Machinery"),
        c("a", "Accelerator"),
        c("cc", "Curso Claude Code", "cont"),   // hija de Contenido
        c("cont", "Contenido"),
    ]

    /// El orden es el que enseña el panel: cada raíz seguida de sus hijas. Si
    /// la flecha recorriera solo las raíces, las subcarpetas serían invisibles
    /// al teclado aunque estén ahí delante.
    func testRecorreLasHijasDentroDeSuMadre() {
        XCTAssertEqual(Lateral.carpetasEnOrden(carpetas).map(\.id), ["a", "cont", "cc", "z"])
    }

    func testDerechaAvanzaEIzquierdaRetrocede() {
        XCTAssertEqual(Lateral.carpetaVecina(carpetas, de: "cont", paso: 1), "cc")
        XCTAssertEqual(Lateral.carpetaVecina(carpetas, de: "cc", paso: -1), "cont")
    }

    /// Sin vuelta, igual que los lienzos: en la última no hay siguiente.
    func testSeQuedaEnLosExtremos() {
        XCTAssertNil(Lateral.carpetaVecina(carpetas, de: "z", paso: 1))
        XCTAssertNil(Lateral.carpetaVecina(carpetas, de: "a", paso: -1))
    }

    /// ⚠️ Sin cursor todavía, la PRIMERA flecha aterriza en la primera carpeta
    /// en vez de no hacer nada: pulsar y que no pase nada se lee como que el
    /// atajo no existe.
    func testLaPrimeraFlechaAterrizaEnAlgo() {
        XCTAssertEqual(Lateral.carpetaVecina(carpetas, de: nil, paso: 1), "a")
        XCTAssertEqual(Lateral.carpetaVecina(carpetas, de: "inexistente", paso: -1), "a")
    }

    /// Al saltar a otra rama se cierra la que dejas: acordeón.
    func testCierraLaQueDejasAtras() {
        XCTAssertEqual(Lateral.aPlegar(carpetas, saliendoDe: "a", entrandoA: "z"), ["a"])
    }

    /// ⚠️ BAJAR A UNA HIJA NO ES SALIR. Plegar "Contenido" al entrar en su hija
    /// "Curso Claude Code" escondería la fila a la que acabas de llegar, y el
    /// cursor se quedaría marcando algo invisible. La regla no es "cierra la
    /// anterior" a secas: es "cierra lo que dejas atrás", y a una madre no la
    /// dejas atrás mientras estás dentro de ella.
    func testNoCierraLaMadreDeLaQueEntras() {
        XCTAssertEqual(Lateral.aPlegar(carpetas, saliendoDe: "cont", entrandoA: "cc"), [])
    }

    /// Y al revés: al salir de una hija hacia otra rama cae también la madre,
    /// o se queda abierta enseñando lienzos de un sitio donde ya no estás.
    func testAlSalirDeUnaHijaCaeTambienLaMadre() {
        XCTAssertEqual(Lateral.aPlegar(carpetas, saliendoDe: "cc", entrandoA: "z"), ["cc", "cont"])
    }

    /**
     * SUBIR DE LA HIJA A SU MADRE SÍ RECOGE LA HIJA — y está bien.
     *
     * Escribí la prueba esperando `[]`, razonando "sigues dentro del mismo
     * árbol". Salió `["cc"]` y el código tiene razón: la madre queda
     * desplegada, así que la FILA de la hija se sigue viendo; lo único que se
     * recoge son sus lienzos, que es justo el desorden que se quería quitar.
     *
     * Lo que nunca puede pasar es plegar un ANCESTRO del destino: eso sí
     * escondería la fila a la que llegas. Y eso no ocurre aquí.
     */
    func testSubirALaMadreRecogeLaHijaPeroNoLaMadre() {
        XCTAssertEqual(Lateral.aPlegar(carpetas, saliendoDe: "cc", entrandoA: "cont"), ["cc"])
        XCTAssertFalse(Lateral.aPlegar(carpetas, saliendoDe: "cc", entrandoA: "cont").contains("cont"),
                       "jamás se pliega el destino ni sus ancestros")
    }

    /// Sin carpeta previa, y quedarse donde estás, no cierran nada.
    func testSinAnteriorNoHayNadaQueCerrar() {
        XCTAssertEqual(Lateral.aPlegar(carpetas, saliendoDe: nil, entrandoA: "z"), [])
        XCTAssertEqual(Lateral.aPlegar(carpetas, saliendoDe: "z", entrandoA: "z"), [])
    }

    /// `lienzosDe` parte de una CARPETA, no del lienzo abierto — es justo lo
    /// que permite mover el cursor a otra carpeta sin abrir nada de ella.
    func testLosLienzosSalenDeLaCarpetaDelCursorNoDelAbierto() {
        let pgs = [
            ResumenPagina(id: "p2", nombre: "01 · dos", folderId: "cc", elementos: 0),
            ResumenPagina(id: "otro", nombre: "El Negocio", folderId: "z", elementos: 0),
            ResumenPagina(id: "p1", nombre: "00 · uno", folderId: "cc", elementos: 0),
        ]
        XCTAssertEqual(Lateral.lienzosDe(pgs, carpeta: "cc").map(\.id), ["p1", "p2"])
        XCTAssertEqual(Lateral.lienzosDe(pgs, carpeta: "z").map(\.id), ["otro"])
    }
}
