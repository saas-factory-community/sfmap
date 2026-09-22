import XCTest
@testable import SFMap

/// EL PANEL DE DOCUMENTOS SE REDIMENSIONA Y SU LETRA CRECE (6 sep 2026).
/// Daniel, con una tabla de 5 columnas truncada en 470 px: «permíteme un resizer que además
/// con cmd+/- me permita cambiar el tamaño de letra». Se prueban las dos funciones puras.
final class PanelDocEscalaTests: XCTestCase {

    func testLaEscalaSubeBajaYSeAcota() {
        XCTAssertEqual(PanelDoc.escalar(1.0, 1), 1.1)
        XCTAssertEqual(PanelDoc.escalar(1.0, -1), 0.9)
        XCTAssertEqual(PanelDoc.escalar(1.8, 1), 1.8, "tope superior: no crece sin fin")
        XCTAssertEqual(PanelDoc.escalar(0.7, -1), 0.7, "tope inferior: no desaparece")
        XCTAssertEqual(PanelDoc.escalar(1.4, 0), 1.0, "⌘0 vuelve a 1")
    }

    /// El panel vive pegado al canto derecho: el ancho es lo que queda del puntero al borde.
    func testElAnchoSaleDeLaXDelPuntero() {
        XCTAssertEqual(PanelDoc.anchoDesde(xVentana: 1000, anchoRaiz: 1600, escalaUI: 1), 600)
        XCTAssertEqual(PanelDoc.anchoDesde(xVentana: 1500, anchoRaiz: 1600, escalaUI: 1), 320, "mínimo legible")
        XCTAssertEqual(PanelDoc.anchoDesde(xVentana: 100, anchoRaiz: 1600, escalaUI: 1), 1100, "máximo: el lienzo no desaparece")
        // con el cromo al 150%, la ventana mide en puntos escalados y el ancho se reporta en puntos del cromo
        XCTAssertEqual(PanelDoc.anchoDesde(xVentana: 1500, anchoRaiz: 1600, escalaUI: 1.5), 600, accuracy: 0.01)
    }

    /// La escala multiplica TODO el documento: un h1 sigue siendo mayor que el cuerpo.
    func testLaEscalaConservaLaJerarquia() {
        let md = "# Título\n\nUn párrafo de cuerpo."
        let antes = PanelDoc.escala; defer { PanelDoc.escala = antes }
        PanelDoc.escala = 1.0
        let a = Markdown.atribuido(Markdown.analizar(md), tema: .claro, ancho: 600)
        PanelDoc.escala = 1.5
        let b = Markdown.atribuido(Markdown.analizar(md), tema: .claro, ancho: 600)
        func tam(_ s: NSAttributedString, _ i: Int) -> CGFloat { (s.attribute(.font, at: i, effectiveRange: nil) as! NSFont).pointSize }
        XCTAssertGreaterThan(tam(b, 0), tam(a, 0), "el título crece")
        let cuerpo = a.string.range(of: "Un párrafo")!.lowerBound.utf16Offset(in: a.string)
        XCTAssertGreaterThan(tam(b, cuerpo), tam(a, cuerpo), "el cuerpo crece")
        XCTAssertGreaterThan(tam(b, 0), tam(b, cuerpo), "y el título sigue mayor que el cuerpo")
    }
}
