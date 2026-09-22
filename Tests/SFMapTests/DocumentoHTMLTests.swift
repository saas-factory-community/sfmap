import XCTest
import AppKit
import WebKit
@testable import SFMap

final class DocumentoHTMLTests: XCTestCase {
    func testRutaLocalConEspaciosYFragmentoSinAccesoFueraDelRepo() throws {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: raiz) }
        let archivo = raiz.appendingPathComponent("Un atlas.html")
        try "<h1>Atlas</h1>".write(to: archivo, atomically: true, encoding: .utf8)
        let a = try XCTUnwrap(ArtefactoHTML.resolver("Un atlas.html#mapa", repo: raiz))
        XCTAssertEqual(a.destino.fragment, "mapa")
        XCTAssertEqual(a.archivo.path, archivo.resolvingSymlinksInPath().path)
        XCTAssertEqual(a.carpeta, raiz.resolvingSymlinksInPath())
        XCTAssertNil(ArtefactoHTML.resolver("../fuera.html", repo: raiz))
        XCTAssertNil(ArtefactoHTML.resolver("https://example.com/index.html", repo: raiz))
        XCTAssertNil(ArtefactoHTML.resolver("falta.html", repo: raiz))
        XCTAssertNil(ArtefactoHTML.resolver("/Un atlas.html", repo: raiz))
        try FileManager.default.createSymbolicLink(at: raiz.appendingPathComponent("escape.html"),
                                                   withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        XCTAssertNil(ArtefactoHTML.resolver("escape.html", repo: raiz))
    }

    func testAnchoMantieneEspacioParaElLienzo() {
        XCTAssertEqual(PanelDoc.anchoHTML(1500, raiz: 1920), 1500)
        XCTAssertEqual(PanelDoc.anchoHTML(1500, raiz: 1200), 840)
        XCTAssertEqual(PanelDoc.anchoHTML(80, raiz: 1200), 320)
    }

    @MainActor func testHTMLRealEjecutaJavaScriptCargaRecursosYConservaEstadoAlRedimensionar() async throws {
        _ = NSApplication.shared
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: raiz) }
        try #"<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"><rect width="18" height="18" fill="purple"/></svg>"#
            .write(to: raiz.appendingPathComponent("prueba.svg"), atomically: true, encoding: .utf8)
        try #"<html><head><title>Atlas de prueba</title></head><body><main><section class="panel" id="mapa"><button id="paso" onclick="this.textContent=String(++window.pasos)">0</button><img src="prueba.svg"></section></main><script>window.pasos=0</script></body></html>"#
            .write(to: raiz.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let vista = DocumentoHTML(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
        vista.layoutSubtreeIfNeeded()
        let artefacto = try XCTUnwrap(ArtefactoHTML.resolver("index.html#mapa", repo: raiz))
        vista.abrir(artefacto)
        for _ in 0..<200 {
            if vista.estado != "cargando" { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(vista.estado, "listo", vista.errorCarga ?? "no terminó la carga")
        XCTAssertEqual(vista.sha256.count, 64)
        let titulo = try await vista.web.evaluateJavaScript("document.title") as? String
        XCTAssertEqual(titulo, "Atlas de prueba")
        let imagen = try await vista.web.evaluateJavaScript("document.images[0].naturalWidth") as? Int
        XCTAssertEqual(imagen, 18)
        _ = try await vista.web.evaluateJavaScript("document.getElementById('paso').click()")
        vista.frame.size.width = 740
        vista.layoutSubtreeIfNeeded()
        vista.abrir(artefacto) // volver al mismo HTML no destruye la lectura
        let pasos = try await vista.web.evaluateJavaScript("window.pasos") as? Int
        XCTAssertEqual(pasos, 1)
        let lectura = try await vista.web.evaluateJavaScript(DocumentoHTML.lecturaJS) as? [String: Any]
        XCTAssertEqual(lectura?["fragmento"] as? String, "#mapa")
        XCTAssertEqual(lectura?["paneles"] as? [String], ["mapa"])
        _ = try await vista.web.evaluateJavaScript("const d=document.createElement('dialog');d.id='evidencia';d.innerHTML='<h2>Prueba del recorrido</h2>';document.body.appendChild(d);d.showModal()")
        let evidencia = try await vista.web.evaluateJavaScript(DocumentoHTML.lecturaJS) as? [String: Any]
        XCTAssertEqual((evidencia?["dialogos"] as? [[String: Any]])?.first?["id"] as? String, "evidencia")
        XCTAssertEqual(evidencia?["texto"] as? String, "Prueba del recorrido")
    }
}
