import XCTest
@testable import SFMap

/// Las reglas del documento, medidas.
///
/// Existen porque sfmap escribe en la MISMA fila que el lienzo web: una regla
/// que aquí se interprete distinto produce un documento que la otra superficie
/// no entiende, y eso se descubre cuando ya se guardó encima.
final class ModeloTests: XCTestCase {

    private func elemento(_ extra: [String: Json] = [:]) -> Elemento {
        var o: [String: Json] = [
            "id": .texto("x"), "type": .texto("shape"),
            "x": .numero(10), "y": .numero(20),
            "width": .numero(100), "height": .numero(50),
            "rotation": .numero(0), "zIndex": .numero(1), "opacity": .numero(1),
            "locked": .bool(false), "version": .numero(1),
            "createdAt": .numero(0), "updatedAt": .numero(0),
        ]
        for (k, v) in extra { o[k] = v }
        return Elemento(.objeto(o))
    }

    /// ⭐ EL CONTRATO ENTRE LAS DOS CAPAS. Tocar algo compilado lo FIJA.
    func testMoverFijaLoCompilado() {
        var e = elemento(["origin": .objeto(["regionId": .texto("r1"), "nodeId": .texto("n1")])])
        XCTAssertFalse(e.fijado, "nace sin fijar")
        e.mover(dx: 5, dy: 7)
        XCTAssertTrue(e.fijado, "moverlo con la mano lo fija: el compilador deja de mandarlo")
        XCTAssertEqual(e.x, 15); XCTAssertEqual(e.y, 27)
    }

    /// Y lo que NO es compilado no gana un `origin` de la nada.
    func testMoverNoInventaOrigen() {
        var e = elemento()
        e.mover(dx: 1, dy: 1)
        XCTAssertFalse(e.compilado, "un elemento libre sigue libre")
    }

    /// Fijar es idempotente: mover diez veces no reescribe el resto del origen.
    func testFijarNoPisaElOrigen() {
        var e = elemento(["origin": .objeto(["regionId": .texto("r1"), "nodeId": .texto("n1")])])
        e.mover(dx: 1, dy: 0); e.mover(dx: 1, dy: 0)
        XCTAssertEqual(e.crudo["origin"]?["nodeId"]?.s, "n1", "el nodeId sobrevive")
        XCTAssertEqual(e.crudo["origin"]?["regionId"]?.s, "r1")
    }

    /// ⭐ LO QUE sfmap NO ENTIENDE, SOBREVIVE. Es la condición para poder
    /// escribir en el mismo documento que el lienzo web sin vaciarlo.
    func testMoverConservaCamposDesconocidos() {
        var e = elemento(["campoDelFuturo": .texto("no lo toques"),
                          "trazo": .objeto(["style": .texto("dashed"), "explicit": .bool(true)])])
        e.mover(dx: 3, dy: 3)
        XCTAssertEqual(e.crudo["campoDelFuturo"]?.s, "no lo toques")
        XCTAssertEqual(e.crudo["trazo"]?["style"]?.s, "dashed")
    }

    /// La alineación por defecto es la MISMA regla que el motor web: compilado
    /// a la izquierda, de la mano al centro.
    func testAlineacionPorDefecto() {
        XCTAssertEqual(elemento().alineacion, "center", "de la mano: centrado")
        XCTAssertEqual(elemento(["origin": .objeto(["regionId": .texto("r")])]).alineacion, "left",
                       "compilado: el compositor lo colocó a propósito")
        XCTAssertEqual(elemento(["textAlign": .texto("right")]).alineacion, "right", "lo explícito manda")
    }

    /// La caja VISUAL incluye el pie, que cuelga fuera del rectángulo. Sin esto
    /// encuadrar y seleccionar cortan las descripciones.
    func testCajaVisualIncluyeElPie() {
        let e = elemento(["text": .lista([.objeto([
            "kind": .texto("caption"), "text": .texto("pie"), "lines": .lista([.texto("pie")]),
            "x": .numero(0), "y": .numero(60), "width": .numero(120), "height": .numero(30),
            "style": .objeto(["family": .texto("montserrat"), "weight": .numero(400), "size": .numero(12)]),
        ])])])
        XCTAssertEqual(e.caja.height, 50)
        XCTAssertEqual(e.cajaVisual.height, 90, "la caja visual llega hasta el final del pie")
    }

    /// Un color sin la firma `explicit` NO gana: es lo que deja que el tema
    /// repinte el documento entero.
    func testColorSinFirmaNoGana() {
        let sinFirma = elemento(["color": .objeto(["fill": .texto("#ff0000")])])
        XCTAssertNil(sinFirma.relleno, "sin `explicit` manda el rol")
        let conFirma = elemento(["color": .objeto(["fill": .texto("#ff0000"), "explicit": .bool(true)])])
        XCTAssertEqual(conFirma.relleno, "#ff0000")
    }
}
