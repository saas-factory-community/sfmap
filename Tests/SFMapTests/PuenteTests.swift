import XCTest
import AppKit
@testable import SFMap

/**
 * LA PUERTA AGÉNTICA, medida (24 ago 2026).
 *
 * Existe por una mañana de 6 relanzamientos: Levy escribía por REST y el espejo
 * no se enteraba. Estas pruebas cubren las decisiones que no se ven en pantalla:
 * cuándo procede recargar, que la orden se CONSUME, que la selección que se
 * publica es legible, y que el recorte del export abraza el texto ligado.
 */
final class PuenteTests: XCTestCase {

    // ── recarga: la mano de Daniel SIEMPRE gana ─────────────────────────────
    func testDebeRecargarSoloConVersionNuevaYManosQuietas() {
        XCTAssertTrue(Puente.debeRecargar(remota: 5, local: 4, sucio: false, guardando: false, botonesRaton: 0))
        XCTAssertFalse(Puente.debeRecargar(remota: 4, local: 4, sucio: false, guardando: false, botonesRaton: 0), "misma versión")
        XCTAssertFalse(Puente.debeRecargar(remota: nil, local: 4, sucio: false, guardando: false, botonesRaton: 0), "sin red no se decide")
        XCTAssertFalse(Puente.debeRecargar(remota: 5, local: 4, sucio: true, guardando: false, botonesRaton: 0), "con cambios sin guardar, jamás")
        XCTAssertFalse(Puente.debeRecargar(remota: 5, local: 4, sucio: false, guardando: true, botonesRaton: 0), "guardando, jamás")
        XCTAssertFalse(Puente.debeRecargar(remota: 5, local: 4, sucio: false, guardando: false, botonesRaton: 1), "con el ratón presionado, jamás")
    }

    // ── la orden se CONSUME al leerla ───────────────────────────────────────
    func testOrdenSeConsumeYParsea() throws {
        try FileManager.default.createDirectory(at: Puente.dir, withIntermediateDirectories: true)
        let respaldo = try? Data(contentsOf: Puente.ordenURL)   // no pisar una orden real
        defer { if let r = respaldo { try? r.write(to: Puente.ordenURL) } }

        try Data(#"{"abrir": "pagina-x", "centrar": "n:03", "enfocar": "zona", "ficha": "c:arista", "zoom": 1}"#.utf8).write(to: Puente.ordenURL)
        let o = Puente.leerOrden()
        XCTAssertEqual(o?.abrir, "pagina-x")
        XCTAssertEqual(o?.centrar, "n:03")
        XCTAssertEqual(o?.enfocar,"zona")
        XCTAssertEqual(o?.ficha,"c:arista")
        XCTAssertEqual(o?.zoom,1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: Puente.ordenURL.path),
                       "la orden debe borrarse al leerse — si sobrevive, se reaplica en loop")
        XCTAssertNil(Puente.leerOrden(), "sin archivo no hay orden")
    }

    // ── la selección publicada es legible para un agente ────────────────────
    func testSeleccionPublicadaTraeResumen() throws {
        let e = Elemento(.objeto([
            "id": .texto("n:07"), "type": .texto("shape"), "shape": .texto("rect"),
            "role": .texto("agent"), "x": .numero(0), "y": .numero(0),
            "width": .numero(100), "height": .numero(50),
            "text": .lista([.objeto(["kind": .texto("title"), "text": .texto("Context Eng."),
                                     "lines": .lista([.texto("Context Eng.")]),
                                     "x": .numero(10), "y": .numero(10),
                                     "width": .numero(80), "height": .numero(30)])]),
        ]))
        let respaldo = try? Data(contentsOf: Puente.seleccionURL)
        defer { if let r = respaldo { try? r.write(to: Puente.seleccionURL) }
                else { try? FileManager.default.removeItem(at: Puente.seleccionURL) } }

        Puente.escribirSeleccion(pagina: "pag-1", nombre: "Curso", elementos: [e])
        let d = try Data(contentsOf: Puente.seleccionURL)
        let j = try JSONDecoder().decode(Json.self, from: d)
        XCTAssertEqual(j["page_id"]?.s, "pag-1")
        XCTAssertEqual(j["ids"]?.arr?.first?.s, "n:07")
        let res = j["elementos"]?.arr?.first
        XCTAssertEqual(res?["rol"]?.s, "agent")
        XCTAssertEqual(res?["titulo"]?.s, "Context Eng.")
    }

    // ── centrar: la cámara queda EXACTO en el centro de la caja ─────────────
    func testCamaraCentrada() {
        let c = Camara.centradaEn(CGRect(x: 100, y: 200, width: 300, height: 100), zoom: 0.8)
        XCTAssertEqual(c.x, 250); XCTAssertEqual(c.y, 250); XCTAssertEqual(c.zoom, 0.8)
    }

    // ── export: el recorte abraza el TEXTO LIGADO, no solo la caja ──────────
    func testLimitesIncluyenCaption() {
        let e = Elemento(.objeto([
            "id": .texto("a"), "type": .texto("shape"), "shape": .texto("rect"),
            "x": .numero(0), "y": .numero(0), "width": .numero(200), "height": .numero(100),
            "text": .lista([.objeto(["kind": .texto("caption"), "text": .texto("pie"),
                                     "lines": .lista([.texto("pie")]),
                                     "x": .numero(0), "y": .numero(110),
                                     "width": .numero(200), "height": .numero(50)])]),
        ]))
        let r = Foto.limites([e])
        XCTAssertNotNil(r)
        // caja 0..100 + caption hasta 160, + margen 60 → el recorte llega a 220
        XCTAssertEqual(r!.maxY, 220, accuracy: 0.5,
                       "el caption vive FUERA de la caja y el export no debe decapitarlo")
    }
}
