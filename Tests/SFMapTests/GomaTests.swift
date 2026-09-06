import XCTest
@testable import SFMap

/**
 * LA GOMA, MEDIDA.
 *
 * Existen porque la goma anterior mentía: pintaba un disco de un tamaño y
 * borraba por un PUNTO, así que su grosor era decoración. Lo que estas pruebas
 * fijan es justo eso — que el número que se pinta y el que borra sean el mismo,
 * y que el alcance signifique algo.
 */
final class GomaTests: XCTestCase {

    private func figura(_ x: Double, _ y: Double, _ w: Double = 100, _ h: Double = 60,
                        tipo: String = "shape", bloqueado: Bool = false) -> Elemento {
        Elemento(.objeto([
            "id": .texto("\(tipo)-\(x)-\(y)"), "type": .texto(tipo),
            "x": .numero(x), "y": .numero(y),
            "width": .numero(w), "height": .numero(h),
            "locked": .bool(bloqueado), "zIndex": .numero(1),
        ]))
    }

    /// Un trazo horizontal de (0,0) a (100,0), grosor nominal 4.
    private func trazo(_ x: Double = 0, _ y: Double = 0, grosor: Double = 4) -> Elemento {
        Elemento(.objeto([
            "id": .texto("ink"), "type": .texto("ink"),
            "x": .numero(x), "y": .numero(y),
            "width": .numero(100), "height": .numero(1),
            "size": .numero(grosor), "zIndex": .numero(2),
            "points": .lista([
                .objeto(["x": .numero(0), "y": .numero(0), "pressure": .numero(0.5)]),
                .objeto(["x": .numero(100), "y": .numero(0), "pressure": .numero(0.5)]),
            ]),
        ]))
    }

    // ── el disco es la verdad ───────────────────────────────────────────────

    /// ⭐ EL CONTRATO. Lo que se pinta es lo que borra, al zoom que sea.
    func testElRadioQueSePintaEsElQueBorra() {
        let g = Goma(grosor: 40, alcance: .tinta)
        for z in [0.05, 0.3, 1.0, 2.5, 12.0] {
            XCTAssertEqual(g.radioPantalla(zoom: z), g.radioMundo(zoom: z) * z, accuracy: 0.0001,
                           "a zoom \(z) el disco de pantalla y el de mundo son el mismo")
        }
    }

    /// Alejarse no convierte la goma en una aguja invisible…
    func testAlAlejarseElDiscoNoBajaDelMinimo() {
        let g = Goma(grosor: 24, alcance: .tinta)
        XCTAssertEqual(g.radioPantalla(zoom: 0.02), Goma.MINIMO_PANTALLA / 2, accuracy: 0.001)
    }

    /// …ni acercarse la convierte en una pantalla entera.
    func testAlAcercarseElDiscoNoPasaDelMaximo() {
        let g = Goma(grosor: 80, alcance: .tinta)
        XCTAssertEqual(g.radioPantalla(zoom: 20), Goma.MAXIMO_PANTALLA / 2, accuracy: 0.001)
    }

    // ── el alcance significa algo ───────────────────────────────────────────

    /// El trazo se agarra por su TINTA, no por su caja.
    func testAlcanzaElTrazoPorSuTinta() {
        let t = trazo()
        XCTAssertTrue(Goma.alcanza(t, centro: CGPoint(x: 50, y: 3), radio: 6, alcance: .tinta),
                      "el disco roza la línea")
        XCTAssertFalse(Goma.alcanza(t, centro: CGPoint(x: 50, y: 80), radio: 6, alcance: .tinta),
                       "lejos de la línea no alcanza, aunque la caja del elemento sea grande")
    }

    /// ⭐ LO QUE HACE QUE LA GOMA SE USE SIN MIEDO: anotar sobre un diagrama y
    /// limpiar la anotación sin arriesgar el diagrama.
    func testEnModoTintaNoTocaLosComponentes() {
        let caja = figura(0, 0)
        XCTAssertFalse(Goma.alcanza(caja, centro: CGPoint(x: 50, y: 30), radio: 20, alcance: .tinta),
                       "con alcance tinta, una figura no se borra ni pasándole por encima")
        XCTAssertTrue(Goma.alcanza(caja, centro: CGPoint(x: 50, y: 30), radio: 20, alcance: .todo),
                      "con alcance todo, sí")
    }

    /// Y en `todo` también las flechas.
    func testEnModoTodoAlcanzaLosConectores() {
        let c = Elemento(.objeto([
            "id": .texto("c"), "type": .texto("connector"), "x": .numero(0), "y": .numero(0),
            "width": .numero(0), "height": .numero(0),
            "points": .lista([.objeto(["x": .numero(0), "y": .numero(0)]),
                              .objeto(["x": .numero(100), "y": .numero(0)])]),
        ]))
        XCTAssertTrue(Goma.alcanza(c, centro: CGPoint(x: 40, y: 4), radio: 8, alcance: .todo))
        XCTAssertFalse(Goma.alcanza(c, centro: CGPoint(x: 40, y: 4), radio: 8, alcance: .tinta),
                       "una flecha no es tinta")
    }

    /// ⭐ LA SECCIÓN SE AGARRA POR SU MARCO. Si contara su interior, barrer lo
    /// que hay DENTRO se llevaría el contenedor entero al primer roce.
    func testLaSeccionSeBorraPorElMarcoNoPorDentro() {
        let s = figura(0, 0, 600, 400, tipo: "frame")
        XCTAssertFalse(Goma.alcanza(s, centro: CGPoint(x: 300, y: 200), radio: 20, alcance: .todo),
                       "en mitad de la sección, no")
        XCTAssertTrue(Goma.alcanza(s, centro: CGPoint(x: 300, y: 6), radio: 20, alcance: .todo),
                      "sobre su borde, sí")
    }

    /// El candado manda: una goma que se lo salta lo convierte en decoración.
    func testLoBloqueadoNoSeBorra() {
        let caja = figura(0, 0, 100, 60, bloqueado: true)
        XCTAssertFalse(Goma.alcanza(caja, centro: CGPoint(x: 50, y: 30), radio: 40, alcance: .todo))
    }

    /// La tinta gorda se alcanza por donde SE VE, no por su grosor nominal: con
    /// presión alta se pinta más ancha, y pasar por encima de tinta visible sin
    /// llevársela es el peor fallo posible, porque el ojo dice que ahí hay algo.
    func testAlcanzaLaTintaPorDondeSeVeNoPorSuGrosorNominal() {
        let t = trazo(grosor: 20)
        let medio = Tinta.diametro(Tinta.Opciones(grosor: 20, marcador: false)) * 0.5 * Tinta.ANCHO_MAX
        XCTAssertGreaterThan(medio, 10, "la tinta se ensancha por encima de su grosor/2")
        XCTAssertTrue(Goma.alcanza(t, centro: CGPoint(x: 50, y: medio - 0.5), radio: 0.1, alcance: .tinta),
                      "el borde visible del trazo alcanza")
    }

    // ── el dial ─────────────────────────────────────────────────────────────

    func testElDialSubeYBajaPorLaListaConTope() {
        XCTAssertEqual(Goma.grosorAjustado(Goma.grosores[0], pasos: 1), Goma.grosores[1])
        XCTAssertEqual(Goma.grosorAjustado(Goma.grosores[0], pasos: -1), Goma.grosores[0],
                       "abajo del todo se queda quieto, no da la vuelta")
        XCTAssertEqual(Goma.grosorAjustado(Goma.grosores.last!, pasos: 1), Goma.grosores.last!)
    }

    /// Un valor que no está en la lista no clava el dial: arranca por el vecino.
    func testElDialSeMueveAunqueElValorNoEsteEnLaLista() {
        let raro = (Goma.grosores[1] + Goma.grosores[2]) / 2
        XCTAssertNotEqual(Goma.grosorAjustado(raro, pasos: 1), raro)
    }

    // ── marcar en conjunto ──────────────────────────────────────────────────

    /// El barrido devuelve TODO lo que alcanza en una pasada, que es lo que el
    /// gesto acumula para confirmar de una sola vez al soltar.
    func testAlcanzadosDevuelveTodoLoQueTocaElDisco() {
        let els = [figura(0, 0), figura(200, 0), trazo(0, 30)]
        let ids = Goma.alcanzados(els, centro: CGPoint(x: 50, y: 30), radio: 40, alcance: .todo)
        XCTAssertEqual(ids.count, 2, "la caja de la izquierda y el trazo; la de 200 no")
    }
}
