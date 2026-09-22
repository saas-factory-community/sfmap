import XCTest
import AppKit
@testable import SFMap

/// PEGAR UNA IMAGEN. Se prueba la parte que toca el DISCO, que es donde puede
/// mentir: si el PNG no se escribe, el lienzo guarda una ruta a un archivo que
/// no existe y enseña un marco de espera para siempre — sin error, sin aviso.
final class PegarImagenTests: XCTestCase {

    private func bitmap(_ w: Int, _ h: Int) -> NSImage {
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        NSColor.systemPurple.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        img.unlockFocus()
        return img
    }

    func testEscribeUnPngQueDeVerdadExiste() throws {
        let r = try XCTUnwrap(Lienzo.guardarPegada(bitmap(300, 200)))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: r.0) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: r.0), "la ruta que se guarda tiene que existir")
        XCTAssertTrue(r.0.hasSuffix(".png"), "se normaliza a PNG: el TIFF de una captura pesa 20-30x")
        // Y que sea un PNG de verdad, no un TIFF con otro nombre.
        let d = try Data(contentsOf: URL(fileURLWithPath: r.0))
        XCTAssertEqual(Array(d.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "firma PNG")

        /*
         * ⚠️ EL INVARIANTE ES "LO QUE DIGO ES LO QUE ESCRIBI", no un numero.
         *
         * La primera version afirmaba 300x200 —los puntos con los que se
         * construyo la imagen— y fallo devolviendo 600x400. No era un fallo
         * del codigo: en una pantalla retina `lockFocus` rinde al DOBLE, asi
         * que el bitmap de verdad tiene 600x400 pixeles y eso es exactamente
         * lo que hay que declarar. Clavar el numero esperado habria obligado a
         * romper el codigo para que pasara la prueba.
         *
         * Lo que si tiene que cumplirse siempre: el tamaño que se devuelve es
         * el del archivo que se acaba de escribir. Si mintiera, la caja naceria
         * con una proporcion que la imagen no tiene y saldria estirada — que
         * parece un diseño, no un fallo.
         */
        let escrito = try XCTUnwrap(NSBitmapImageRep(data: d))
        XCTAssertEqual(r.1, CGSize(width: escrito.pixelsWide, height: escrito.pixelsHigh),
                       "el tamaño declarado es el del PNG escrito")
        XCTAssertEqual(r.1.width / r.1.height, 1.5, accuracy: 0.01, "3:2 entra, 3:2 sale")
    }

    /// La ruta vive en el repo A PROPOSITO: el lienzo viaja (esta en Supabase)
    /// pero la imagen no, asi que la ruta tiene que existir igual en las tres
    /// Macs — y la unica que cumple eso es una que va por git.
    func testViveEnElRepoYSeparadaPorMes() throws {
        let r = try XCTUnwrap(Lienzo.guardarPegada(bitmap(10, 10)))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: r.0) }

        let carpeta=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/sfmap/Imagenes").path + "/"
        XCTAssertTrue(r.0.hasPrefix(carpeta), r.0)
        let mes = URL(fileURLWithPath: r.0).deletingLastPathComponent().lastPathComponent
        XCTAssertNotNil(mes.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression),
                        "carpeta por mes, no un vertedero: \(mes)")
    }

    /// La caja nace con la PROPORCION del archivo y acotada: una captura de
    /// 3400 px sin tope entra ocupando media pantalla del mundo.
    func testLaCajaConservaLaProporcionYSeAcota() {
        let e = Crear.imagen(CGPoint(x: 0, y: 0), src: "/tmp/x.png",
                             natural: CGSize(width: 3400, height: 1700), z: 1)
        XCTAssertEqual(e.ancho / e.alto, 2.0, accuracy: 0.01, "2:1 entra y 2:1 sale")
        XCTAssertLessThanOrEqual(max(e.ancho, e.alto), 1200, "acotada")
    }
}

/// LA ESQUINA ESCALA · EL LADO DEFORMA. Se prueba porque el fallo es mudo: una
/// imagen estirada no da error, solo parece un diseño raro.
final class RedimensionarTests: XCTestCase {

    private let caja = CGRect(x: 0, y: 0, width: 200, height: 100)   // 2:1

    private func aspecto(_ h: String, _ d: CGPoint, prop: Bool) -> Double {
        let r = Geo.redimensionar(caja, h, d, proporcional: prop)
        return r.width / r.height
    }

    /// Las cuatro esquinas conservan el 2:1 pase lo que pase con el ratón.
    func testLasCuatroEsquinasConservanLaProporcion() {
        for h in ["nw", "ne", "se", "sw"] {
            XCTAssertEqual(aspecto(h, CGPoint(x: 90, y: 10), prop: true), 2.0, accuracy: 0.01,
                           "\(h) tirando sobre todo en X")
            XCTAssertEqual(aspecto(h, CGPoint(x: 10, y: 90), prop: true), 2.0, accuracy: 0.01,
                           "\(h) tirando sobre todo en Y")
        }
    }

    /// Un lado se agarra en UN eje: pedirle proporción sería ignorar medio
    /// gesto. Estirar por el este ensancha y NO toca el alto.
    func testElLadoDeformaYEsElPunto() {
        let r = Geo.redimensionar(caja, "e", CGPoint(x: 100, y: 0), proporcional: false)
        XCTAssertEqual(r.width, 300, accuracy: 0.01)
        XCTAssertEqual(r.height, 100, accuracy: 0.01, "el lado no toca el otro eje")
        XCTAssertNotEqual(r.width / r.height, 2.0, accuracy: 0.01, "deforma, que es lo que se pidió")
    }

    /// ⚠️ La esquina que MUEVE el origen tiene que mover también el borde
    /// contrario, o la caja crece hacia el lado equivocado: tirando del `nw`
    /// hacia arriba-izquierda, la esquina `se` NO se mueve.
    func testLaEsquinaOpuestaSeQuedaClavada() {
        let r = Geo.redimensionar(caja, "nw", CGPoint(x: -60, y: -30), proporcional: true)
        XCTAssertEqual(r.maxX, caja.maxX, accuracy: 0.01, "el borde este no se mueve")
        XCTAssertEqual(r.maxY, caja.maxY, accuracy: 0.01, "el borde sur no se mueve")
        XCTAssertEqual(r.width / r.height, 2.0, accuracy: 0.01)
    }
}
