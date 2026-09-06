import XCTest
@testable import SFMap

/**
 * El CONTEXTO de carpeta: donde cae el siguiente lienzo nuevo.
 *
 * Daniel abrió "Agosto 2026", pidió un lienzo nuevo, y nació en "SIN CARPETA".
 * El contrato (23 ago 2026): la última carpeta abierta y SIGUE abierta es donde
 * estás — como en VSCode — y plegarla te devuelve a la raíz.
 */
final class LateralContextoTests: XCTestCase {

    private func lateral() -> Lateral {
        let l = Lateral(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
        l.carpetas = [
            Carpeta(id: "agosto", nombre: "Agosto 2026", madre: nil),
            Carpeta(id: "hija", nombre: "Sub", madre: "agosto"),
            Carpeta(id: "julio", nombre: "Julio", madre: nil),
        ]
        l.paginas = []
        return l
    }

    func testSinAbrirNadaElContextoEsLaRaiz() {
        XCTAssertNil(lateral().carpetaContexto)
    }

    func testLaCarpetaAbiertaEsElContexto() {
        let l = lateral()
        l.abrir("agosto")
        XCTAssertEqual(l.carpetaContexto, "agosto")
    }

    func testAbrirOtraCarpetaMueveElContexto() {
        let l = lateral()
        l.abrir("agosto")
        l.abrir("julio")
        XCTAssertEqual(l.carpetaContexto, "julio")
    }

    func testPlegarLaCarpetaDevuelveElContextoALaRaiz() {
        let l = lateral()
        l.abrir("agosto")
        l.alternarExpansion("agosto")   // el mismo camino que el clic de la fila
        XCTAssertNil(l.carpetaContexto)
    }

    func testPlegarOtraCarpetaNoTocaElContexto() {
        let l = lateral()
        l.abrir("agosto")
        l.abrir("julio")
        l.alternarExpansion("julio")
        XCTAssertEqual(l.carpetaContexto, "agosto")
    }

    func testElContextoDeUnaSubcarpetaNoAnidaUnaTercera() {
        // El botón de carpeta nueva solo anida en madres de primer nivel; el
        // contexto de una subcarpeta no puede volverse madre.
        let l = lateral()
        l.abrir("hija")
        XCTAssertEqual(l.carpetaContexto, "hija")
        let ctx = l.carpetaContexto.flatMap { id in
            // misma regla que aplica el botón masCarpeta
            l.carpetas.first { $0.id == id }?.madre == nil ? id : nil
        }
        XCTAssertNil(ctx)
    }
}

/// EL ORDEN DE LA LISTA. Se prueba porque el fallo no da error: una lista mal
/// ordenada funciona perfectamente, solo enseña el curso al reves.
final class OrdenLateralTests: XCTestCase {

    private func ordenar(_ n: [String]) -> [String] {
        n.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Un curso numerado se lee 00 → 08, no al reves.
    func testLosNumerosVanEnOrdenAscendente() {
        XCTAssertEqual(ordenar(["03 · Capa 1", "00 · El Hook", "08 · El PRO", "01 · Los MODELOS"]),
                       ["00 · El Hook", "01 · Los MODELOS", "03 · Capa 1", "08 · El PRO"])
    }

    /// ⚠️ LA RAZON DE `localizedStandardCompare` Y NO `<`.
    /// Con `<` sobre texto, "10" va antes que "2" porque compara caracter a
    /// caracter: el '1' pesa menos que el '2'. Un indice que pone el capitulo
    /// 10 antes del 2 esta roto aunque nunca falle.
    func testDosDigitosNoSeCuelanAntesDeUnDigito() {
        XCTAssertEqual(ordenar(["10 · diez", "2 · dos", "1 · uno"]),
                       ["1 · uno", "2 · dos", "10 · diez"])
        XCTAssertTrue("10" < "2", "si esto cambia, el comentario de arriba sobra")
    }

    /// Y la razon de que ignore mayusculas: en ASCII toda mayuscula pesa menos
    /// que cualquier minuscula, asi que `<` agrupaba por CAJA antes que por
    /// alfabeto — "Estructura" delante de "control" sin motivo legible.
    func testLaMayusculaNoSeCuelaDelante() {
        XCTAssertEqual(ordenar(["control · cajas v1", "Estructura General", "avatar"]),
                       ["avatar", "control · cajas v1", "Estructura General"])
    }
}
