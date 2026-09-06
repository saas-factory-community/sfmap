import XCTest
import AppKit
@testable import SFMap

/**
 * EL BISEL DE LOS ICONOS Y LOS CURSORES DE HERRAMIENTA (24 ago 2026).
 *
 * Tres contratos, cada uno nacido de un fallo o una decisión concreta:
 *
 * 1. Una imagen con ruta LOCAL carga. El pintor solo entendía data: y http, y
 *    `URL(string: "/Users/…")` producía una URL sin esquema que URLSession
 *    rechazaba en silencio: los logos del mapa de la máquina se quedaron en
 *    "marco de espera" para siempre y pareció que "el software no lo permite".
 *
 * 2. `iconoBisel` produce una pieza NO-plantilla del mismo tamaño, distinta por
 *    tema (si claro y oscuro salieran iguales, no se está adaptando a ambos), y
 *    cacheada (misma petición → mismo objeto: se cuece una vez).
 *
 * 3. El cursor del lápiz lleva el hotspot en la PUNTA: la tinta nace donde el
 *    grafito toca el papel, no en el centro del dibujo.
 */
final class BiselIconoTests: XCTestCase {

    func testImagenDeRutaLocalCargaInmediata() throws {
        // Un PNG diminuto de verdad, escrito a disco.
        let img = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { r in
            NSColor.systemPurple.setFill(); r.fill(); return true
        }
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("no se pudo fabricar el PNG de prueba")
        }
        let ruta = NSTemporaryDirectory() + "sfmap-prueba-\(ProcessInfo.processInfo.globallyUniqueString).png"
        try png.write(to: URL(fileURLWithPath: ruta))
        defer { try? FileManager.default.removeItem(atPath: ruta) }

        let cargada = Imagenes.de(ruta) {}
        XCTAssertNotNil(cargada, "una ruta local debe cargar SÍNCRONA, sin viaje por URLSession")
    }

    func testIconoBiselNoPlantillaMismoTamanoYDistintoPorTema() {
        let base = Icono.lapiz
        let claro = Estilo.iconoBisel(base, .claro)
        let oscuro = Estilo.iconoBisel(base, .oscuro)

        XCTAssertFalse(claro.isTemplate, "biselado = ya trae su color; plantilla lo aplanaría al tinte")
        XCTAssertEqual(claro.size, base.size)
        XCTAssertNotEqual(claro.tiffRepresentation, oscuro.tiffRepresentation,
                          "un solo diseño ADAPTADO a ambos temas: los píxeles deben diferir")
    }

    func testIconoBiselSeCachea() {
        let a = Estilo.iconoBisel(Icono.nota, .oscuro)
        let b = Estilo.iconoBisel(Icono.nota, .oscuro)
        XCTAssertTrue(a === b, "misma base+tema+tinte → el mismo objeto, cocido una vez")
        let tintado = Estilo.iconoBisel(Icono.nota, .oscuro, tinte: .systemPurple)
        XCTAssertFalse(a === tintado, "el tinte forma parte de la llave del cache")
    }

    func testCursorLapizHotspotEnLaPunta() {
        let c = NSCursor.lapizHerramienta
        XCTAssertEqual(c.hotSpot, NSPoint(x: 2, y: 22),
                       "el lápiz escribe por su punta (abajo-izquierda), no por su centro")
        XCTAssertEqual(NSCursor.marcadorHerramienta.hotSpot, NSPoint(x: 3.5, y: 20.5))
    }

    func testCursorColocacionSeCacheaPorIcono() {
        let a = NSCursor.colocacion(Icono.cuadrado)
        let b = NSCursor.colocacion(Icono.cuadrado)
        XCTAssertTrue(a === b)
        XCTAssertEqual(a.hotSpot, NSPoint(x: 8, y: 8), "el punto de trabajo es el centro de la cruz")
    }
}
