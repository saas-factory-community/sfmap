import XCTest
import AppKit
@testable import SFMap

/**
 * DE LEJOS NO SE COMPONE TEXTO — y se cuenta, no se supone.
 *
 * Nació el 5 sep 2026 con «La Red» de El Ecosistema: a zoom 0.06 todo el lienzo está
 * a la vista y el recorte por viewport no ahorra nada; lo que cuesta es componer con
 * CoreText cientos de renglones de un píxel. El nivel de detalle los pinta como
 * silueta. Esta prueba pinta offscreen y le pregunta al lienzo cuántos omitió.
 */
final class NivelDeDetalleTests: XCTestCase {

    private func texto(_ id: String, tam: Double) -> Elemento {
        Elemento(.objeto([
            "id": .texto(id), "type": .texto("text"),
            "text": .texto("uno\ndos\ntres"), "lines": .lista([.texto("uno"), .texto("dos"), .texto("tres")]),
            "style": .objeto(["size": .numero(tam), "weight": .numero(600)]),
            "x": .numero(0), "y": .numero(0), "width": .numero(300), "height": .numero(tam * 4),
            "rotation": .numero(0), "zIndex": .numero(1), "opacity": .numero(1),
            "locked": .bool(false), "version": .numero(1), "createdAt": .numero(0), "updatedAt": .numero(0),
        ]))
    }

    private func lienzo(_ els: [Elemento]) -> Lienzo {
        let marco = NSRect(x: 0, y: 0, width: 800, height: 600)
        let win = NSWindow(contentRect: marco, styleMask: [.borderless], backing: .buffered, defer: false)
        let l = Lienzo(frame: marco)
        win.contentView = l
        l.doc.cargar(els)
        return l
    }

    private func pintar(_ l: Lienzo) {
        let rep = l.bitmapImageRepForCachingDisplay(in: l.bounds)!
        l.cacheDisplay(in: l.bounds, to: rep)
    }

    override func tearDown() { Pintor.sinLOD = false }

    func testLegibleDependeDelZoomYDelTamano() {
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let lejos = Pintor(ctx: ctx, tema: .claro, camara: Camara(x: 0, y: 0, zoom: 0.05), tamano: CGSize(width: 4, height: 4))
        XCTAssertFalse(lejos.legible(20), "20 pt a zoom 0.05 = 1 px: no se lee")
        XCTAssertTrue(lejos.legible(150), "un rótulo de territorio (150 pt) sí se lee de lejos")
        let cerca = Pintor(ctx: ctx, tema: .claro, camara: Camara(x: 0, y: 0, zoom: 1), tamano: CGSize(width: 4, height: 4))
        XCTAssertTrue(cerca.legible(12))
    }

    func testDeLejosSeOmitenRenglonesYDeCercaNo() {
        let l = lienzo([texto("t", tam: 20)])
        l.camara = Camara(x: 150, y: 40, zoom: 0.05)
        pintar(l)
        XCTAssertEqual(l.omitidosUltimoCuadro, 3, "tres renglones de 1 px: silueta, no CoreText")
        l.camara = Camara(x: 150, y: 40, zoom: 1)
        pintar(l)
        XCTAssertEqual(l.omitidosUltimoCuadro, 0)
    }

    func testExportYFotoNuncaRecortan() {
        let l = lienzo([texto("t", tam: 20)])
        l.camara = Camara(x: 150, y: 40, zoom: 0.05)
        Pintor.sinLOD = true
        pintar(l)
        XCTAssertEqual(l.omitidosUltimoCuadro, 0, "con sinLOD (export/foto) se compone todo")
    }
}
