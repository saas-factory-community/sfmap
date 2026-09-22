import XCTest
import AppKit
@testable import SFMap

/// DOBLE CLIC SOBRE UNA IMAGEN CON `link` LA ABRE (6 sep 2026).
///
/// Nació con las tarjetas de enlace del lienzo de embudos (miniaturas de video,
/// portadas de abouts, vistas previas de otros lienzos): una tarjeta que solo se
/// abre con ⌘ o acertándole a una marca de 7 px no es una tarjeta. Se prueba el
/// DESPACHO, no la navegación: `alAbrirEnlace` se captura sin abrir nada.
final class EnlaceDobleClicTests: XCTestCase {

    private func elemento(_ id: String, tipo: String, liga: String?, x: Double = 0) -> Elemento {
        var o: [String: Json] = [
            "id": .texto(id), "type": .texto(tipo), "shape": .texto("rect"), "role": .texto("drawn"),
            "x": .numero(x), "y": .numero(0), "width": .numero(200), "height": .numero(120),
            "rotation": .numero(0), "zIndex": .numero(1), "opacity": .numero(1),
            "locked": .bool(false), "version": .numero(1),
            "createdAt": .numero(0), "updatedAt": .numero(0), "text": .lista([]),
        ]
        if let liga { o["link"] = .texto(liga) }
        return Elemento(.objeto(o))
    }

    /// Lienzo en ventana real (sin ventana, `convert(from: nil)` no tiene marco)
    /// con la cámara en (0,0) y zoom 1: el centro de la vista es el mundo (0,0).
    private func montar(_ els: [Elemento]) -> (Lienzo, NSWindow) {
        let marco = NSRect(x: 0, y: 0, width: 800, height: 600)
        let win = NSWindow(contentRect: marco, styleMask: [.borderless], backing: .buffered, defer: false)
        let l = Lienzo(frame: marco)
        win.contentView = l
        l.doc.cargar(els)
        l.camara = Camara(x: 0, y: 0, zoom: 1)
        l.herramienta = .seleccionar
        return (l, win)
    }

    private func clic(_ l: Lienzo, _ win: NSWindow, mundo: CGPoint, clics: Int) -> NSEvent {
        let p = CGPoint(x: (mundo.x - l.camara.x) * l.camara.zoom + l.bounds.width / 2,
                        y: (mundo.y - l.camara.y) * l.camara.zoom + l.bounds.height / 2)
        return NSEvent.mouseEvent(with: .leftMouseDown, location: l.convert(p, to: nil), modifierFlags: [],
                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber,
                                  context: nil, eventNumber: 0, clickCount: clics, pressure: 1)!
    }

    func testDobleClicEnImagenConLinkDespachaSuDestino() {
        let (l, win) = montar([elemento("img", tipo: "image", liga: "https://www.youtube.com/watch?v=ihZZCCleDKs")])
        var recibido: [String] = []
        l.alAbrirEnlace = { recibido.append($0) }
        l.mouseDown(with: clic(l, win, mundo: CGPoint(x: 100, y: 60), clics: 2))
        XCTAssertEqual(recibido, ["https://www.youtube.com/watch?v=ihZZCCleDKs"], "dos clics sobre la imagen abren su destino")
    }

    /// Un clic simple selecciona, no abre: si abriera, no habría forma de moverla.
    func testUnClicNoAbre() {
        let (l, win) = montar([elemento("img", tipo: "image", liga: "https://saasfactory.so/about")])
        var recibido: [String] = []
        l.alAbrirEnlace = { recibido.append($0) }
        l.mouseDown(with: clic(l, win, mundo: CGPoint(x: 100, y: 60), clics: 1))
        XCTAssertTrue(recibido.isEmpty, "un clic sobre el cuerpo de la imagen no despacha nada")
    }

    /// En una caja el doble clic sigue siendo del editor de texto, no del enlace.
    func testDobleClicEnCajaNoAbreElEnlace() {
        let (l, win) = montar([elemento("caja", tipo: "shape", liga: "https://saasfactory.so/about")])
        var recibido: [String] = []
        l.alAbrirEnlace = { recibido.append($0) }
        l.mouseDown(with: clic(l, win, mundo: CGPoint(x: 100, y: 60), clics: 2))
        XCTAssertTrue(recibido.isEmpty, "la caja conserva su doble clic para editar")
    }

    /// Una imagen sin `link` no abre nada aunque la pulsen dos veces.
    func testImagenSinLinkNoAbre() {
        let (l, win) = montar([elemento("img", tipo: "image", liga: nil)])
        var recibido: [String] = []
        l.alAbrirEnlace = { recibido.append($0) }
        l.mouseDown(with: clic(l, win, mundo: CGPoint(x: 100, y: 60), clics: 2))
        XCTAssertTrue(recibido.isEmpty)
    }
}
