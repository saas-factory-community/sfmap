import XCTest
@testable import SFMap

/**
 * LOS ESPACIOS (11 sep 2026). Daniel: *"abres la app y te manda a los espacios…
 * seleccionando uno, solo veo los de ese grupo"*.
 *
 * Un espacio es una carpeta raíz; el panel enseña solo su subárbol. Estas
 * pruebas cubren la lógica pura: qué cuelga de qué, qué se ve en cada vista y
 * que las flechas no se salen del espacio.
 */
final class EspaciosTests: XCTestCase {

    private let carpetas = [
        Carpeta(id: "negocio", nombre: "Negocio", madre: nil),
        Carpeta(id: "contenido", nombre: "Contenido", madre: nil),
        Carpeta(id: "curso", nombre: "Curso", madre: "contenido"),
        Carpeta(id: "videos", nombre: "Videos", madre: "contenido"),
        Carpeta(id: "lab", nombre: "Lab", madre: nil),
    ]
    private let paginas = [
        ResumenPagina(id: "p1", nombre: "El Negocio", folderId: "negocio", elementos: -1),
        ResumenPagina(id: "p2", nombre: "01 · Motor", folderId: "curso", elementos: -1),
        ResumenPagina(id: "p3", nombre: "Tailscale", folderId: "videos", elementos: -1),
        ResumenPagina(id: "p4", nombre: "Huérfana", folderId: nil, elementos: -1),
        ResumenPagina(id: "p5", nombre: "Carpeta borrada", folderId: "fantasma", elementos: -1),
    ]

    func testLaRaizDeUnaSubcarpetaEsSuEspacio() {
        XCTAssertEqual(Lateral.raizDe(carpetas, carpeta: "curso"), "contenido")
        XCTAssertEqual(Lateral.raizDe(carpetas, carpeta: "negocio"), "negocio")
        XCTAssertNil(Lateral.raizDe(carpetas, carpeta: nil))
        XCTAssertNil(Lateral.raizDe(carpetas, carpeta: "fantasma"), "una carpeta desconocida no tiene raíz: es huérfana")
    }

    func testUnCicloEnParentIdNoCuelgaLaApp() {
        let ciclo = [Carpeta(id: "a", nombre: "A", madre: "b"), Carpeta(id: "b", nombre: "B", madre: "a")]
        XCTAssertNotNil(Lateral.raizDe(ciclo, carpeta: "a"))
    }

    func testElSubarbolDeUnEspacioNoIncluyeLaRaizNiOtrosEspacios() {
        XCTAssertEqual(Lateral.carpetasDe(carpetas, espacio: "contenido").map(\.id).sorted(), ["curso", "videos"])
        XCTAssertTrue(Lateral.carpetasDe(carpetas, espacio: "negocio").isEmpty)
        XCTAssertTrue(Lateral.carpetasDe(carpetas, espacio: nil).isEmpty, "la portada no enseña carpetas")
    }

    func testLosLienzosDeUnEspacioSonLosDeSuRaizYSusSubcarpetas() {
        XCTAssertEqual(Lateral.paginasDe(paginas, carpetas, espacio: "contenido").map(\.id).sorted(), ["p2", "p3"])
        XCTAssertEqual(Lateral.paginasDe(paginas, carpetas, espacio: "negocio").map(\.id), ["p1"])
        XCTAssertTrue(Lateral.paginasDe(paginas, carpetas, espacio: "lab").isEmpty)
    }

    func testLaPortadaEnseñaLosHuerfanosParaQueNoSePierdan() {
        // Sin carpeta y con carpeta desconocida: los dos son huérfanos.
        XCTAssertEqual(Lateral.paginasDe(paginas, carpetas, espacio: nil).map(\.id).sorted(), ["p4", "p5"])
    }

    func testLaPortadaListaLosEspaciosPorNombreConSuCuenta() {
        let e = Lateral.espacios(carpetas, paginas)
        XCTAssertEqual(e.map(\.carpeta.nombre), ["Contenido", "Lab", "Negocio"])
        XCTAssertEqual(e.map(\.cuenta), [2, 0, 1])
    }

    func testLasFlechasRecorrenSoloLasCarpetasDelEspacio() {
        let visibles = Lateral.carpetasDe(carpetas, espacio: "contenido")
        XCTAssertEqual(Lateral.carpetasEnOrden(visibles, raiz: "contenido").map(\.id), ["curso", "videos"])
        XCTAssertEqual(Lateral.carpetaVecina(visibles, raiz: "contenido", de: "curso", paso: 1), "videos")
        XCTAssertNil(Lateral.carpetaVecina(visibles, raiz: "contenido", de: "videos", paso: 1), "al final, se acabó: no salta a otro espacio")
    }

    func testCambiarDeEspacioLimpiaCursorYCarpetasAbiertas() {
        let l = Lateral(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
        l.carpetas = carpetas; l.paginas = paginas
        l.espacio = "contenido"
        l.abrir("curso"); l.foco = "curso"
        XCTAssertEqual(l.carpetaContexto, "curso")
        l.espacio = "negocio"
        XCTAssertNil(l.carpetaContexto)
        XCTAssertNil(l.foco)
        XCTAssertTrue(l.carpetasVisibles.isEmpty)
        XCTAssertEqual(l.paginasVisibles.map(\.id), ["p1"])
    }

    func testUnEspacioBorradoDevuelveALaPortada() {
        let l = Lateral(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
        l.carpetas = carpetas; l.paginas = paginas
        l.espacio = "lab"
        l.carpetas = carpetas.filter { $0.id != "lab" }
        XCTAssertNil(l.espacio)
    }
}
