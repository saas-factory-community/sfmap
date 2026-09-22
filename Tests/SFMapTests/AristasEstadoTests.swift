import XCTest
@testable import SFMap

/// Las dos clases de arista que llevan el ESTADO de seguridad al cable (5 sep 2026):
/// `expuesto` (rojo, sólida, se ve de lejos) y `lab` (azul, punteada). Existen en los
/// dos temas o el pintor cae a `flujo` en silencio y el rojo desaparece del mapa.
final class AristasEstadoTests: XCTestCase {
    func testLasClasesDeEstadoExistenEnAmbosTemas() {
        for tema in [Tema.claro, Tema.oscuro] {
            XCTAssertNotNil(tema.aristas["expuesto"], "\(tema.nombre): falta expuesto")
            XCTAssertNotNil(tema.aristas["lab"], "\(tema.nombre): falta lab")
            XCTAssertEqual(tema.aristas["expuesto"]?.estilo, "solid")
            XCTAssertEqual(tema.aristas["lab"]?.estilo, "dashed")
            XCTAssertGreaterThan(tema.aristas["expuesto"]!.grosor, tema.aristas["flujo"]!.grosor)
        }
    }
}
