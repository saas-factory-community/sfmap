import XCTest
@testable import SFMap

final class ConfiguracionPublicaTests: XCTestCase {
    func testNubeExigeDuenoExplicitoYConfiguracionCompleta() throws {
        let base = ["MC_SUPABASE_URL": "https://example.supabase.co/", "MC_SUPABASE_KEY": "test-only-placeholder"]
        XCTAssertThrowsError(try Nube.configuracionRemota(base))
        var values = base
        values["MC_USER_ID"] = "00000000-0000-4000-8000-000000000001"
        let config = try Nube.configuracionRemota(values)
        XCTAssertEqual(config.url, "https://example.supabase.co")
        XCTAssertEqual(config.owner, values["MC_USER_ID"])
        values["MC_USER_ID"] = "x&select=*"
        XCTAssertThrowsError(try Nube.configuracionRemota(values))
        values["MC_USER_ID"] = config.owner
        values["MC_SUPABASE_URL"] = "no-url"
        XCTAssertThrowsError(try Nube.configuracionRemota(values))
    }
    func testPlantillaIncluidaAbreSinRecursosExternos() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let file = repo.appendingPathComponent("templates/tu-negocio/Tu-negocio.sfmap")
        let c = try ArchivoSFMap.leer(Data(contentsOf: file))
        XCTAssertTrue(c.plantilla)
        XCTAssertEqual(c.documento["elements"]?.arr?.count, 200)
        XCTAssertEqual(c.enlacesOmitidos, 0)
        for element in c.documento["elements"]!.arr! where element["type"]?.s == "image" {
            XCTAssertNotNil(try ArchivoSFMap.imagenEmbebida(element["src"]!.s!))
        }
    }
    /// La plantilla del programa: abre sola, no nombra nada privado y hace ida y vuelta sin cambios.
    func testMapaDeClaridadAbreYHaceIdaYVuelta() async throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let file = repo.appendingPathComponent("templates/mapa-de-claridad/Mapa-de-Claridad.sfmap")
        let data = try Data(contentsOf: file)
        let c = try ArchivoSFMap.leer(data)
        XCTAssertTrue(c.plantilla)
        XCTAssertEqual(c.nombre, "Mapa de Claridad · Arbrain")
        XCTAssertGreaterThan(c.documento["elements"]?.arr?.count ?? 0, 400)
        XCTAssertEqual(c.enlacesOmitidos, 0)
        for element in c.documento["elements"]!.arr! where element["type"]?.s == "image" {
            XCTAssertNotNil(try ArchivoSFMap.imagenEmbebida(element["src"]!.s!))
        }
        let texto = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #"data:image/[a-z]+;base64,[A-Za-z0-9+/=]+"#, with: "", options: .regularExpression)
        XCTAssertNil(texto.range(of: #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#, options: .regularExpression))
        for privado in ["/Users/", "supabase", ".env", "agent-server"] { XCTAssertFalse(texto.contains(privado), privado) }
        let (otra, omitidos) = try await ArchivoSFMap.preparar(nombre: c.nombre, documento: c.documento, plantilla: true)
        XCTAssertEqual(omitidos, 0)
        XCTAssertEqual(try ArchivoSFMap.leer(otra).documento, c.documento)
    }
}
