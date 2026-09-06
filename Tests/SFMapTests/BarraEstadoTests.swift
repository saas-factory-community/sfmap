import XCTest
@testable import SFMap

/// LA BARRA DE ABAJO NO SE DEFORMA NI SE SALE. Las dos cosas venían del mismo
/// sitio: `layout()` recalculaba su propio `frame`/`bounds` mientras se
/// maquetaba, y eso se realimenta.
final class BarraEstadoTests: XCTestCase {

    private func colocada(a esc: CGFloat) -> BarraEstado {
        let b = BarraEstado(frame: .zero)
        b.tema = Tema.claro
        // Como la coloca `colocar()`: el FRAME primero y el BOUNDS despues.
        // Al reves, escribir el frame reescala el bounds para conservar la
        // escala vieja y deshace lo anterior — ese era el bug.
        let w = b.anchoIdeal
        b.frame.size = NSSize(width: w * esc, height: 54 * esc)
        b.bounds = NSRect(x: 0, y: 0, width: w, height: 54)
        b.layoutSubtreeIfNeeded()
        return b
    }

    /// ⚠️ EL SÍNTOMA QUE SE VEÍA: la cápsula estirada a lo ancho. Medido antes
    /// del arreglo, colocándola a escala 1.0 salía escX=1.407 con escY=1.000.
    func testLaEscalaEsLaMismaEnLosDosEjes() {
        for esc in [1.0, 1.6, 2.2] as [CGFloat] {
            let b = colocada(a: esc)
            let escX = b.frame.width / b.bounds.width
            let escY = b.frame.height / b.bounds.height
            XCTAssertEqual(escX, escY, accuracy: 0.001, "estirada a escala \(esc)")
            XCTAssertEqual(escX, esc, accuracy: 0.001)
        }
    }

    /// El otro síntoma, misma causa: los últimos botones —la luna— se pintaban
    /// fuera del bisel. Antes, el hijo más a la derecha llegaba a 388 con un
    /// `bounds` de 282.9: 105 px por fuera.
    func testNingunBotonSeSaleDelBisel() {
        for esc in [1.0, 1.6, 2.2] as [CGFloat] {
            let b = colocada(a: esc)
            let fuera = b.subviews.filter { !$0.isHidden && $0.frame.maxX > b.bounds.width + 0.5 }
            XCTAssertTrue(fuera.isEmpty,
                          "a escala \(esc) se salen \(fuera.count) (bounds.w=\(b.bounds.width))")
        }
    }

    /// Y el ancho declarado tiene que dar de sobra para lo que hay dentro, o
    /// quien la coloca la dibuja más corta de lo que ocupa.
    func testElAnchoDeclaradoCubreLoQueContiene() {
        let b = colocada(a: 1)
        let maxX = b.subviews.filter { !$0.isHidden }.map(\.frame.maxX).max() ?? 0
        XCTAssertLessThanOrEqual(maxX, b.anchoIdeal)
    }
}
