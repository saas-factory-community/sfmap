import XCTest
@testable import SFMap

/// EL APILADO. Se prueba aquí y no mirando la pantalla porque los fallos del
/// z-order no se ven: se ven DESPUÉS, cuando algo tapa a algo y ya no sabes por
/// qué. La lista va de FONDO a FRENTE.
final class OrdenTests: XCTestCase {

    private let todos = ["a", "b", "c", "d", "e"]

    private func mover(_ sel: [String], _ m: Orden.Movimiento) -> [String]? {
        Orden.reordenar(todos, seleccion: Set(sel), m)
    }

    func testAlFrenteYAlFondo() {
        XCTAssertEqual(mover(["b"], .alFrente), ["a", "c", "d", "e", "b"])
        XCTAssertEqual(mover(["d"], .alFondo), ["d", "a", "b", "c", "e"])
    }

    func testUnPasoEsUnPaso() {
        XCTAssertEqual(mover(["b"], .adelante), ["a", "c", "b", "d", "e"])
        XCTAssertEqual(mover(["d"], .atras), ["a", "b", "d", "c", "e"])
    }

    /// ⚠️ REGLA 1: lo seleccionado conserva su orden relativo. Si mandas tres
    /// cosas al frente siguen apiladas entre sí como estaban — reordenarlas de
    /// paso destruye trabajo que el ojo ya había hecho.
    func testVariosConservanSuOrdenRelativo() {
        XCTAssertEqual(mover(["d", "a", "b"], .alFrente), ["c", "e", "a", "b", "d"])
        XCTAssertEqual(mover(["e", "b"], .alFondo), ["b", "e", "a", "c", "d"])
    }

    /**
     * ⚠️ REGLA 2, la que se olvida: un paso salta al vecino NO seleccionado.
     *
     * "b" y "c" van juntos. Si cada uno se moviera un sitio a ciegas, "b"
     * adelantaría a "c" —se moverían uno CONTRA otro en vez de juntos— y a la
     * tercera pulsación el par estaría del revés. Los dos saltan sobre "d",
     * que es quien no va con ellos.
     */
    func testDosPegadosSeMuevenJuntosYNoSeAdelantan() {
        XCTAssertEqual(mover(["b", "c"], .adelante), ["a", "d", "b", "c", "e"])
        XCTAssertEqual(mover(["c", "d"], .atras), ["a", "c", "d", "b", "e"])
    }

    /// Y repetido hasta el tope siguen en el mismo orden entre sí.
    func testRepetirHastaElTopeNoLosDesordena() {
        var v = todos
        for _ in 0..<10 { v = Orden.reordenar(v, seleccion: ["b", "c"], .adelante) ?? v }
        XCTAssertEqual(v, ["a", "d", "e", "b", "c"])
    }

    /**
     * ⚠️ NIL CUANDO NO HAY CAMBIO, y no es cosmética: sin esto, pulsar
     * "adelante" sobre algo que ya está arriba apila un paso de deshacer que no
     * deshace nada. Tres pulsaciones de más y ⌘Z deja de responder durante tres
     * pulsaciones — el usuario cree que el deshacer está roto.
     */
    func testNoGastaHistoriaSiNoHayNadaQueMover() {
        XCTAssertNil(mover(["e"], .adelante), "ya está arriba del todo")
        XCTAssertNil(mover(["e"], .alFrente), "ya está arriba del todo")
        XCTAssertNil(mover(["a"], .atras), "ya está al fondo")
        XCTAssertNil(mover(["a"], .alFondo), "ya está al fondo")
        XCTAssertNil(mover(["d", "e"], .adelante), "el bloque ya está arriba")
        XCTAssertNil(mover([], .alFrente), "sin selección no hay gesto")
        XCTAssertNil(mover(todos, .alFrente), "moverlo TODO no mueve nada")
    }
}

/// JUNTAR AL AGRUPAR. Sin esto un extraño se queda atrapado entre dos miembros
/// y viaja con el grupo para siempre, partiéndolo por la mitad al pintar.
extension OrdenTests {

    func testAgruparJuntaSinCambiarLaAltura() {
        // "b" y "d" se agrupan; "c" estaba en medio y tiene que salir.
        XCTAssertEqual(Orden.juntar(["a", "b", "c", "d", "e"], grupo: ["b", "d"]),
                       ["a", "c", "b", "d", "e"])
    }

    /// ⚠️ Se suben al sitio del miembro MÁS ALTO, no al frente de todo:
    /// agrupar es una operación sobre la estructura, no sobre la profundidad.
    /// Traer el grupo al frente sin que lo hayas pedido te mueve trabajo que ya
    /// estaba colocado.
    func testNoLosTraeAlFrente() {
        let r = Orden.juntar(["a", "b", "c", "d", "e"], grupo: ["a", "c"])
        XCTAssertEqual(r, ["b", "a", "c", "d", "e"])
        XCTAssertEqual(r?.last, "e", "lo que estaba arriba sigue arriba")
    }

    func testSiYaEstabanJuntosNoGastaHistoria() {
        XCTAssertNil(Orden.juntar(["a", "b", "c"], grupo: ["a", "b"]))
        XCTAssertNil(Orden.juntar(["a", "b", "c"], grupo: ["b"]), "uno solo no es grupo")
    }
}
