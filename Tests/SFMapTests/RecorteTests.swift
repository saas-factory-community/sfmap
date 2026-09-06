import XCTest
import CoreGraphics
@testable import SFMap

/// LA TIJERA. La aritmética del recorte se prueba sin abrir una ventana porque
/// el sitio donde se cuela el error —componer un recorte sobre otro— no se ve
/// hasta el tercero, y para entonces nadie sabe cuál de los tres estaba mal.
final class RecorteTests: XCTestCase {

    private func imagen(_ x: Double = 100, _ y: Double = 100,
                        _ w: Double = 400, _ h: Double = 200,
                        crop: CGRect? = nil) -> Elemento {
        var j: [String: Json] = ["id": .texto("im"), "type": .texto("image"),
                                 "x": .numero(x), "y": .numero(y),
                                 "width": .numero(w), "height": .numero(h)]
        if let c = crop {
            j["crop"] = .objeto(["x": .numero(c.minX), "y": .numero(c.minY),
                                 "w": .numero(c.width), "h": .numero(c.height)])
        }
        return Elemento(.objeto(j))
    }

    func testSinRecorteSeVeLaImagenEntera() {
        XCTAssertEqual(Recorte.de(imagen()), CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertFalse(Recorte.tieneRecorte(imagen()))
    }

    /// La mitad derecha de una imagen sin recortar es la mitad derecha del
    /// original, y la caja nueva es EXACTAMENTE lo que se marcó: lo que queda
    /// se queda donde estaba.
    func testRecortarLaMitadDerecha() {
        let e = imagen()   // 100,100 400×200
        let r = Recorte.aplicar(e, seleccion: CGRect(x: 300, y: 100, width: 200, height: 200))
        XCTAssertEqual(r?.crop, CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(r?.caja, CGRect(x: 300, y: 100, width: 200, height: 200))
    }

    /**
     * ⚠️ EL CASO QUE IMPORTA: recortar lo YA recortado.
     *
     * La imagen ya enseña solo su mitad derecha. Pedir ahora "la mitad derecha
     * de lo que veo" tiene que dar el ÚLTIMO CUARTO del original (0.75…1), no
     * la mitad otra vez. La versión ingenua —guardar la fracción de la caja
     * actual— daría 0.5 y el segundo recorte no movería nada.
     */
    func testRecortarLoYaRecortadoCompone() {
        let e = imagen(300, 100, 200, 200, crop: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        let r = Recorte.aplicar(e, seleccion: CGRect(x: 400, y: 100, width: 100, height: 200))
        XCTAssertEqual(r?.crop.minX ?? 0, 0.75, accuracy: 0.0001)
        XCTAssertEqual(r?.crop.width ?? 0, 0.25, accuracy: 0.0001)
    }

    /// Lo que se marca FUERA de la imagen no cuenta: el recorte se queda dentro.
    func testLaSeleccionSeMeteDentroDeLaImagen() {
        let e = imagen()
        let r = Recorte.aplicar(e, seleccion: CGRect(x: -500, y: -500, width: 900, height: 900))
        XCTAssertEqual(r?.caja, CGRect(x: 100, y: 100, width: 300, height: 200))
    }

    /// Un clic mal soltado NO deja una imagen de dos píxeles.
    func testUnaSeleccionMinusculaNoRecorta() {
        XCTAssertNil(Recorte.aplicar(imagen(), seleccion: CGRect(x: 200, y: 150, width: 3, height: 3)))
    }

    /// Quitar el recorte devuelve la imagen entera CONSERVANDO la esquina: si
    /// se viera media imagen a 200 de ancho, entera mide 400 y sigue empezando
    /// donde estaba. Re-encuadrarla obligaría a recolocarla.
    func testQuitarElRecorteDevuelveElTamañoOriginal() {
        let e = imagen(300, 100, 200, 200, crop: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        let p = Recorte.quitar(e)
        XCTAssertEqual(p["width"]??.num, 400)
        XCTAssertEqual(p["height"]??.num, 200)
        XCTAssertNil(p["crop"] ?? nil, "la marca de recorte desaparece del elemento")
    }

    /// La `CGImage` cuenta su Y desde ARRIBA, igual que este `crop`: si esto se
    /// invirtiera, todo recorte saldría espejado en vertical y solo se notaría
    /// mirando la imagen.
    func testElRectanguloDePixeles() {
        let r = Recorte.enPixeles(CGRect(x: 0.5, y: 0.25, width: 0.5, height: 0.5),
                                  ancho: 1000, alto: 800)
        XCTAssertEqual(r, CGRect(x: 500, y: 200, width: 500, height: 400))
    }

    // ── la máquina del gesto ───────────────────────────────────────────────

    /// Entrar y pulsar Enter SIN arrastrar no puede borrar la imagen: la
    /// selección arranca siendo todo y `recorta` dice que no hay nada que hacer.
    func testEntrarYConfirmarSinArrastrarNoRecortaNada() {
        var s = Recorte.Sesion(id: "im", caja: CGRect(x: 0, y: 0, width: 400, height: 200))
        XCTAssertFalse(s.recorta)
        s.empezar(CGPoint(x: 10, y: 10)); s.soltar()      // clic seco
        XCTAssertFalse(s.recorta, "un clic sin arrastre vuelve a ser la imagen entera")
    }

    func testArrastrarEnCualquierDireccionDaElMismoRectangulo() {
        let caja = CGRect(x: 0, y: 0, width: 400, height: 200)
        var a = Recorte.Sesion(id: "im", caja: caja)
        a.empezar(CGPoint(x: 300, y: 150)); a.mover(CGPoint(x: 100, y: 50)); a.soltar()
        var b = Recorte.Sesion(id: "im", caja: caja)
        b.empezar(CGPoint(x: 100, y: 50)); b.mover(CGPoint(x: 300, y: 150)); b.soltar()
        XCTAssertEqual(a.seleccion, b.seleccion)
        XCTAssertTrue(a.recorta)
    }

    /// El arrastre no se sale de la imagen ni tirando del ratón al infinito.
    func testElArrastreSeQuedaDentro() {
        var s = Recorte.Sesion(id: "im", caja: CGRect(x: 0, y: 0, width: 400, height: 200))
        s.empezar(CGPoint(x: 200, y: 100)); s.mover(CGPoint(x: 9999, y: 9999)); s.soltar()
        XCTAssertEqual(s.seleccion, CGRect(x: 200, y: 100, width: 200, height: 100))
    }
}
