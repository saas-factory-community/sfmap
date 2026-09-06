import XCTest
import AppKit
@testable import SFMap

/**
 * UNA IMAGEN EN EL LIENZO SE PINTA — píxeles, no intención.
 *
 * Repro del 24 ago 2026: los logos cargaban (`Imagenes.de` devolvía la imagen)
 * y aún así una página los mostraba y otra no. Este test pinta un lienzo
 * offscreen con UN elemento image y le pregunta a los píxeles.
 */
final class ImagenPintadaTests: XCTestCase {

    func testImagenLocalSePintaEnElLienzo() throws {
        // Un PNG morado sólido en disco.
        let img = NSImage(size: NSSize(width: 40, height: 40), flipped: false) { r in
            NSColor(red: 0.5, green: 0.1, blue: 0.9, alpha: 1).setFill(); r.fill(); return true
        }
        let rep0 = NSBitmapImageRep(data: img.tiffRepresentation!)!
        let png = rep0.representation(using: .png, properties: [:])!
        let ruta = NSTemporaryDirectory() + "sfmap-pinta-\(ProcessInfo.processInfo.globallyUniqueString).png"
        try png.write(to: URL(fileURLWithPath: ruta))
        defer { try? FileManager.default.removeItem(atPath: ruta) }

        let e = Elemento(.objeto([
            "id": .texto("img1"), "type": .texto("image"), "src": .texto(ruta),
            "x": .numero(50), "y": .numero(50), "width": .numero(100), "height": .numero(100),
            "rotation": .numero(0), "zIndex": .numero(1), "opacity": .numero(1),
            "locked": .bool(false), "version": .numero(1),
            "createdAt": .numero(0), "updatedAt": .numero(0),
        ]))

        // Réplica del caso real: la imagen convive con TEXTOS de z mayor
        // (la página demo del 24 ago: textos z=5, imágenes z=1).
        let t = Elemento(.objeto([
            "id": .texto("titulo"), "type": .texto("text"), "text": .texto("Un título"),
            "lines": .lista([.texto("Un título")]), "align": .texto("left"),
            "style": .objeto(["size": .numero(30), "family": .texto("roboto-slab"), "weight": .numero(900)]),
            "x": .numero(50), "y": .numero(10), "width": .numero(300), "height": .numero(40),
            "rotation": .numero(0), "zIndex": .numero(5), "opacity": .numero(1),
            "locked": .bool(false), "version": .numero(1),
            "createdAt": .numero(0), "updatedAt": .numero(0),
        ]))

        let marco = NSRect(x: 0, y: 0, width: 400, height: 400)
        let win = NSWindow(contentRect: marco, styleMask: [.borderless], backing: .buffered, defer: false)
        let l = Lienzo(frame: marco)
        win.contentView = l
        l.doc.cargar([e, t])
        l.encuadrar()

        let rep = l.bitmapImageRepForCachingDisplay(in: l.bounds)!
        l.cacheDisplay(in: l.bounds, to: rep)
        l.cacheDisplay(in: l.bounds, to: rep)

        // El bbox encuadrado incluye al texto, así que el centro de la vista NO
        // es necesariamente la imagen (ese fue un falso positivo el 24 ago: el
        // "bug" era un muestreo mal apuntado + un PNG recortado en blanco). Se
        // BUSCA el morado en toda la superficie: existe o no existe.
        var hayMorado = false
        for py in stride(from: 0, to: rep.pixelsHigh, by: 6) {
            for px in stride(from: 0, to: rep.pixelsWide, by: 6) {
                if let c = rep.colorAt(x: px, y: py),
                   c.blueComponent > 0.5, c.redComponent < 0.75, c.greenComponent < 0.5 {
                    hayMorado = true; break
                }
            }
            if hayMorado { break }
        }
        XCTAssertTrue(hayMorado, "el morado del PNG debería estar pintado en alguna parte")
    }
}
