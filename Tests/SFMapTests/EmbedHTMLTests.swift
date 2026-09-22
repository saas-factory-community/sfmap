import XCTest
import AppKit
@testable import SFMap

final class EmbedHTMLTests: XCTestCase {
    @MainActor func testModoTrabajoPermiteVolverAEditar() {
        let host = EmbedHTML(frame: .zero)
        host.ponerModoTrabajo(true)
        XCTAssertTrue(host.interactivo)
        host.desactivar()
        XCTAssertFalse(host.interactivo)
        host.ponerModoTrabajo(true)
        XCTAssertTrue(host.interactivo)
    }

    @MainActor func testPanNoRepiteMaquetacion() {
        let host = EmbedHTML(frame: .zero)
        let e = Elemento(.objeto(["id":.texto("perf"), "type":.texto("embed"),
            "url":.texto("doc:no-existe.html"), "x":.numero(0), "y":.numero(0),
            "width":.numero(1440), "height":.numero(1000)]))
        host.colocar(e, camara: Camara(x: 0, y: 0, zoom: 0.5), viewport: CGSize(width: 1600,height: 1000))
        let antes = host.maquetaciones
        let inicio = ProcessInfo.processInfo.systemUptime
        for i in 0..<1000 {
            host.colocar(e, camara: Camara(x: Double(i % 100), y: 0, zoom: 0.5), viewport: CGSize(width: 1600,height: 1000))
        }
        print("PAN_1000_MS", (ProcessInfo.processInfo.systemUptime-inicio)*1000)
        XCTAssertEqual(host.maquetaciones, antes, "Pan no debe forzar layout de WebKit")
        XCTAssertEqual(host.bounds.width, 1440)
    }

    func testElMarcoSigueAlObjetoYCambiaConLaCamara() {
        let caja = CGRect(x: 1000, y: 500, width: 2400, height: 2200)
        let a = EmbedHTML.marco(caja, camara: Camara(x: 1000, y: 500, zoom: 0.25), viewport: CGSize(width: 1600, height: 1000))
        XCTAssertEqual(a, CGRect(x: 800, y: 500, width: 600, height: 550))
        let b = EmbedHTML.marco(caja, camara: Camara(x: 1400, y: 700, zoom: 0.5), viewport: CGSize(width: 1600, height: 1000))
        XCTAssertEqual(b, CGRect(x: 600, y: 400, width: 1200, height: 1100))
    }

    func testSoloHTMLLocalEnElementosEmbed() {
        let e = Elemento(.objeto(["id":.texto("html"), "type":.texto("embed"),
                                  "url":.texto("doc:biblioteca/nate/index.html#mapa")]))
        XCTAssertEqual(EmbedHTML.ruta(e), "biblioteca/nate/index.html#mapa")
        XCTAssertNil(EmbedHTML.ruta(Elemento(.objeto(["type":.texto("embed"), "url":.texto("https://example.com")]))))
    }

    @MainActor func testEscalarElObjetoNoRemaquetaNiReiniciaElHTML() async throws {
        _ = NSApplication.shared
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: raiz) }
        try "<html><head><title>Embed</title></head><body><button onclick='window.pasos++'>Paso</button><script>window.pasos=0</script></body></html>"
            .write(to: raiz.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let host = EmbedHTML(frame: CGRect(x: 0, y: 0, width: 720, height: 600))
        host.bounds = CGRect(x: 0, y: 0, width: 1440, height: 1200)
        host.layoutSubtreeIfNeeded()
        host.documento.abrir(try XCTUnwrap(ArtefactoHTML.resolver("index.html", repo: raiz)))
        for _ in 0..<200 {
            if host.documento.estado != "cargando" { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(host.documento.estado, "listo")
        let antes = try await host.documento.web.evaluateJavaScript("innerWidth") as? Int
        _ = try await host.documento.web.evaluateJavaScript("document.querySelector('button').click()")
        host.frame = CGRect(x: 250, y: 120, width: 360, height: 300)
        host.bounds = CGRect(x: 0, y: 0, width: 1440, height: 1200)
        host.layoutSubtreeIfNeeded()
        let despues = try await host.documento.web.evaluateJavaScript("innerWidth") as? Int
        let pasos = try await host.documento.web.evaluateJavaScript("window.pasos") as? Int
        XCTAssertEqual(antes, 1438)
        XCTAssertEqual(despues, antes, "hacer zoom en el lienzo no dispara el diseño móvil de la web")
        XCTAssertEqual(pasos, 1)
        XCTAssertNil(host.hitTest(NSPoint(x: 400, y: 220)), "inactivo: el lienzo recibe los eventos")
    }
}
