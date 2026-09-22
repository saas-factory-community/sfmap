import XCTest
import AppKit
@testable import SFMap

/**
 * LO QUE NO ESTÁ EN PANTALLA NO SE PINTA — y se cuenta, no se supone.
 *
 * Nació el 5 sep 2026 con «El Ecosistema»: 818 elementos en un solo lienzo
 * costaban 130-190 ms por fotograma en release porque el pintor recorría el
 * documento entero en cada cuadro. El recorte por viewport deja el coste en
 * el de lo VISIBLE. Esta prueba pinta offscreen y le pregunta al lienzo cuántos
 * elementos pintó.
 */
final class RecorteVistaTests: XCTestCase {

    private func caja(_ id: String, x: Double, y: Double, giro: Double = 0) -> Elemento {
        Elemento(.objeto([
            "id": .texto(id), "type": .texto("shape"), "shape": .texto("rect"), "role": .texto("card"),
            "x": .numero(x), "y": .numero(y), "width": .numero(120), "height": .numero(60),
            "rotation": .numero(giro), "zIndex": .numero(1), "opacity": .numero(1),
            "locked": .bool(false), "version": .numero(1),
            "createdAt": .numero(0), "updatedAt": .numero(0),
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

    func testVistaEncuentraLaCurvaAunqueSusExtremosQuedenFuera() {
        let e=Elemento(.objeto(["id":.texto("curva"),"type":.texto("connector"),
            "routing":.texto("curva"),"curveStyle":.texto("ports"),
            "fromPort":.texto("w"),"toPort":.texto("w"),
            "points":.lista([.objeto(["x":.numero(0),"y":.numero(0)]),
                            .objeto(["x":.numero(0),"y":.numero(1000)])])]))
        XCTAssertTrue(Lienzo.tocaVista(e,CGRect(x:-330,y:480,width:30,height:40)))
        XCTAssertFalse(Lienzo.tocaVista(e,CGRect(x:-1000,y:480,width:30,height:40)))
    }

    func testRectMundoEsLaInversaDeLaCamara() {
        let r = Lienzo.rectMundo(camara: Camara(x: 100, y: 100, zoom: 0.5),
                                 tamano: CGSize(width: 800, height: 600), holgura: 0)
        XCTAssertEqual(r, CGRect(x: -700, y: -500, width: 1600, height: 1200))
    }

    func testLoQueNoEstaEnPantallaNoSePinta() {
        let l = lienzo([caja("cerca", x: 0, y: 0), caja("lejos", x: 9000, y: 9000)])
        l.camara = Camara(x: 60, y: 30, zoom: 1)
        pintar(l)
        XCTAssertEqual(l.pintadosUltimoCuadro, 1, "solo la caja cercana toca la vista")
        l.encuadrar()
        pintar(l)
        XCTAssertEqual(l.pintadosUltimoCuadro, 2, "encuadrado, las dos están a la vista")
    }

    func testLaHolguraConservaLoQueAsomaYLoGirado() {
        // Una caja justo fuera del borde derecho de la vista (800 px a zoom 1 → x=400 es el
        // borde), pero dentro de la holgura de 320: se pinta, porque su sombra y su pie asoman.
        let borde = caja("borde", x: 500, y: 0)
        // Una caja lejos pero GIRADA cuyo centro queda a 380 px: su diagonal alcanza la holgura.
        let girada = caja("girada", x: 700, y: 0, giro: 0.8)
        let l = lienzo([borde, girada, caja("fuera", x: 3000, y: 0)])
        l.camara = Camara(x: 0, y: 0, zoom: 1)
        pintar(l)
        XCTAssertEqual(l.pintadosUltimoCuadro, 2)
    }

    func testUnConectorSePintaSiAlgunoDeSusPuntosAsoma() {
        let c = Elemento(.objeto([
            "id": .texto("c"), "type": .texto("connector"), "fromId": .texto("a"), "toId": .texto("b"),
            "points": .lista([.objeto(["x": .numero(-2000), "y": .numero(0)]), .objeto(["x": .numero(2000), "y": .numero(0)])]),
            "x": .numero(0), "y": .numero(0), "width": .numero(0), "height": .numero(0),
            "rotation": .numero(0), "zIndex": .numero(0), "opacity": .numero(1),
            "locked": .bool(false), "version": .numero(1), "createdAt": .numero(0), "updatedAt": .numero(0),
        ]))
        let vista = CGRect(x: -400, y: -300, width: 800, height: 600)
        XCTAssertTrue(Lienzo.tocaVista(c, vista), "cruza la vista por el medio")
        let lejos = CGRect(x: 5000, y: 5000, width: 800, height: 600)
        XCTAssertFalse(Lienzo.tocaVista(c, lejos))
    }
}
