import XCTest
@testable import SFMap

/// El zoom del SISTEMA y el ancho del panel (24 ago 2026): los topes son parte
/// del contrato, no decoración — un cromo a 0.3 es invisible y un panel de
/// 1000 px se come el lienzo.
final class CromoAjustesTests: XCTestCase {

    func testEscalaUITieneTopes() {
        XCTAssertEqual(Estilo.clampEscalaUI(0.1), 0.7)
        XCTAssertEqual(Estilo.clampEscalaUI(1.0), 1.0)
        XCTAssertEqual(Estilo.clampEscalaUI(9.0), 1.6)
    }

    func testAnchoLateralTieneTopes() {
        XCTAssertEqual(Estilo.clampAnchoLateral(50), 220)
        XCTAssertEqual(Estilo.clampAnchoLateral(300), 300)
        XCTAssertEqual(Estilo.clampAnchoLateral(2000), 480)
    }

    /// El agarre existe y reporta la x de ventana al arrastrar (el contrato de
    /// coordenadas: el panel vive en x=0, esa x ES el ancho visual pedido).
    func testAgarreReportaAlCallback() {
        let g = AgarreLateral()
        var recibido: CGFloat?
        g.alArrastrar = { recibido = $0 }
        g.alArrastrar?(345)
        XCTAssertEqual(recibido, 345)
    }
}
