import XCTest
import CoreGraphics
@testable import SFMap

/**
 * LO QUE EL ARRASTRE NO PUEDE ROMPER.
 *
 * El 20 ago 2026, arrastrar una tarjeta con tres flechas costaba **297 ms por
 * fotograma** (medido en release sobre la página real de Daniel): el ratón
 * entrega eventos cada pocos milisegundos y cada uno lanzaba hasta nueve
 * búsquedas A* sobre una rejilla construida con TODOS los obstáculos del
 * documento. Daniel: *"al arrastrar se traba, va de saltos en saltos"*.
 *
 * El arreglo tiene tres piezas y cada una podría romperse en silencio, así que
 * cada una tiene su prueba: la rejilla local, el montículo de la frontera y la
 * escuadra rápida del arrastre. Un router que se acelera y empieza a dibujar
 * flechas diagonales no es más rápido, es otro producto.
 */
final class RuteoRapidoTests: XCTestCase {

    private func caja(_ id: String, _ r: CGRect) -> Elemento {
        Elemento(.objeto([
            "id": .texto(id), "type": .texto("shape"), "shape": .texto("rect"),
            "role": .texto("card"),
            "x": .numero(r.minX), "y": .numero(r.minY),
            "width": .numero(r.width), "height": .numero(r.height),
            "rotation": .numero(0), "zIndex": .numero(1), "opacity": .numero(1),
            "locked": .bool(false), "version": .numero(1),
            "createdAt": .numero(0), "updatedAt": .numero(0), "text": .lista([]),
        ]))
    }

    /// EL MONTÍCULO ENTREGA EL MÍNIMO. Es la única propiedad de la que depende
    /// A*: si el orden se cuela, la búsqueda deja de ser óptima y las rutas
    /// salen feas sin que nada falle.
    func testElMonticuloSacaSiempreElMenor() {
        var m = MonticuloMin(50) { $0 < $1 }
        // Un orden adverso a propósito: descendente y con repetidos.
        for x in [99, 3, 77, 3, 41, 1, 100, 8, 8, 0, 62] { m.meter(x) }
        var salida: [Int] = []
        while let x = m.sacar() { salida.append(x) }
        XCTAssertEqual(salida, salida.sorted())
        XCTAssertEqual(salida.count, 12)
    }

    /// LA ESCUADRA DEL ARRASTRE SIGUE SIENDO ORTOGONAL. Es lo que se ve mientras
    /// la mano mueve la caja, así que una diagonal aquí se lee como que la app
    /// se rompió al tocarla.
    func testLaRutaRapidaEsOrtogonal() {
        let cajas: [(String, CGRect)] = [
            ("A", CGRect(x: 0, y: 0, width: 200, height: 120)),
            ("B", CGRect(x: 420, y: 300, width: 200, height: 120)),
            ("C", CGRect(x: 40, y: 420, width: 200, height: 120)),
        ]
        let els = cajas.map { caja($0.0, $0.1) }
        for (a, b) in [("A", "B"), ("B", "C"), ("C", "A")] {
            let c = Crear.conector(a, b)
            let ruta = Conectores.rutear(c, els + [c], rapido: true).ruta
            XCTAssertGreaterThanOrEqual(ruta.count, 2, "\(a)→\(b) sin ruta")
            for i in 0..<(ruta.count - 1) {
                let p = ruta[i], q = ruta[i + 1]
                XCTAssertTrue(abs(p.x - q.x) < 0.5 || abs(p.y - q.y) < 0.5,
                              "tramo \(i) diagonal en \(a)→\(b)")
            }
        }
    }

    /**
     * LA REJILLA LOCAL NO CAMBIA LA RUTA.
     *
     * El filtro solo mira los obstáculos que caen en la zona de las dos puntas.
     * Para que sea una optimización y no un cambio de comportamiento, meter una
     * caja LEJOS —fuera de la zona— tiene que dar exactamente la misma ruta que
     * si no estuviera. Si algún día el margen se queda corto, esto lo dice.
     */
    func testUnObstaculoLejanoNoCambiaLaRuta() {
        let a = caja("A", CGRect(x: 0, y: 0, width: 200, height: 120))
        let b = caja("B", CGRect(x: 500, y: 0, width: 200, height: 120))
        let lejos = caja("Z", CGRect(x: 6000, y: 6000, width: 300, height: 300))
        let c = Crear.conector("A", "B")
        let sin = Conectores.rutear(c, [a, b, c]).ruta
        let con = Conectores.rutear(c, [a, b, lejos, c]).ruta
        XCTAssertEqual(sin.count, con.count, "el obstáculo lejano cambió la ruta")
        for (p, q) in zip(sin, con) {
            XCTAssertEqual(p.x, q.x, accuracy: 0.5)
            XCTAssertEqual(p.y, q.y, accuracy: 0.5)
        }
    }

    /// Y UNO CERCA SÍ LA CAMBIA — si no, el filtro estaría tirando obstáculos
    /// que sí estorban y la prueba de arriba pasaría por el motivo equivocado.
    func testUnObstaculoEnMedioSiCambiaLaRuta() {
        let a = caja("A", CGRect(x: 0, y: 0, width: 200, height: 120))
        let b = caja("B", CGRect(x: 600, y: 0, width: 200, height: 120))
        let medio = caja("M", CGRect(x: 300, y: -40, width: 200, height: 200))
        let c = Crear.conector("A", "B")
        let libre = Conectores.rutear(c, [a, b, c]).ruta
        let rodeo = Conectores.rutear(c, [a, b, medio, c]).ruta
        XCTAssertGreaterThan(rodeo.count, libre.count, "no rodeó la caja de en medio")
    }
}
