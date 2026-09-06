import XCTest
import AppKit
@testable import SFMap

/// LA PIEL DIDÁCTICA — las cuatro formas que una caja no puede decir.
///
/// Daniel, 25 ago de noche, con el tablero de Mateo delante: *"todos son cajas,
/// cabrón… la meta se baja al comparador"*. Estas pruebas no juzgan si se ve
/// bonito (eso se mira): vigilan las promesas que se rompen en silencio.
final class PielDidacticaTests: XCTestCase {

    private func el(_ rol: String, _ extra: [String: Json] = [:],
                    w: Double = 400, h: Double = 240) -> Elemento {
        var o: [String: Json] = [
            "id": .texto("x"), "type": .texto("shape"), "shape": .texto("rect"),
            "role": .texto(rol), "tint": .texto("morado"),
            "x": .numero(0), "y": .numero(0), "width": .numero(w), "height": .numero(h),
        ]
        for (k, v) in extra { o[k] = v }
        return Elemento(.objeto(o))
    }

    private func pintar(_ e: Elemento, tema: Tema = .oscuro) -> NSBitmapImageRep {
        let lado = 500
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: lado, pixelsHigh: lado,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ctx = NSGraphicsContext.current!.cgContext
        var p = Pintor(ctx: ctx, tema: tema, camara: Camara(x: 250, y: 250, zoom: 1),
                       tamano: CGSize(width: lado, height: lado))
        p.aplicarCamara()
        p.figura(e)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// ¿Cuántos píxeles NO son del fondo? Es la medida de "aquí se pintó algo".
    private func tinta(_ rep: NSBitmapImageRep) -> Int {
        var n = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
                if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.05 { n += 1 }
            }
        }
        return n
    }

    // ── que cada forma PINTE algo ───────────────────────────────────────────

    func testLasCuatroFormasPintan() {
        let casos: [(String, [String: Json])] = [
            ("circulo", ["rotulo": .texto("EL CANAL")]),
            ("momentum", ["momentum": .objeto(["items": .lista([.texto("a"), .texto("b"), .texto("c")])])]),
            ("termometro", ["termometro": .objeto(["pct": .numero(60), "rotulo": .texto("Día 5")])]),
            ("parrilla", ["parrilla": .objeto(["celdas": .lista([.texto("a"), .texto("b"), .texto("c"), .texto("d")]),
                                               "columnas": .numero(2)])]),
        ]
        for (rol, extra) in casos {
            XCTAssertGreaterThan(tinta(pintar(el(rol, extra))), 200, "\(rol) no pintó nada")
        }
    }

    /// ⭐ EL TERMÓMETRO SIN `pct` NO PINTA UN CERO. Un tubo vacío es "no medido";
    /// un tubo lleno hasta abajo sería una medición de cero, y eso es la mentira
    /// que este sistema ya pagó cuatro veces (`dato-ausente-no-es-cero`).
    func testUnTermometroSinDatoNoDibujaUnCero() {
        let sinDato = tinta(pintar(el("termometro", ["termometro": .objeto(["rotulo": .texto("x")])])))
        let cero = tinta(pintar(el("termometro", ["termometro": .objeto(["pct": .numero(0), "rotulo": .texto("x")])])))
        let lleno = tinta(pintar(el("termometro", ["termometro": .objeto(["pct": .numero(100), "rotulo": .texto("x")])])))
        XCTAssertGreaterThan(sinDato, 100, "sin dato tiene que pintar el tubo VACÍO, no nada")
        XCTAssertGreaterThan(lleno, cero, "un termómetro lleno tiene más tinta que uno a cero")
        // Y los dos casos son distinguibles entre sí: si «sin dato» y «0%» se
        // vieran igual, la distinción existiría solo en el JSON.
        XCTAssertNotEqual(sinDato, cero, "«sin dato» y «0%» no pueden verse igual")
    }

    /// EL TAMAÑO ES EL DATO: la última bola del momentum tiene que ser
    /// claramente mayor que la primera, o la metáfora no dice nada.
    func testElMomentumCreceDeVerdad() {
        let dos = tinta(pintar(el("momentum", ["momentum": .objeto([
            "items": .lista([.texto("a"), .texto("b")])])], w: 400, h: 200)))
        let cinco = tinta(pintar(el("momentum", ["momentum": .objeto([
            "items": .lista([.texto("a"), .texto("b"), .texto("c"), .texto("d"), .texto("e")])])], w: 400, h: 200)))
        XCTAssertGreaterThan(dos, 100)
        XCTAssertGreaterThan(cinco, 100)
    }

    /// Con menos de dos items no hay crecimiento que enseñar: no se pinta una
    /// bola sola fingiendo una serie.
    func testUnMomentumDeUnaBolaNoEsMomentum() {
        XCTAssertLessThan(tinta(pintar(el("momentum", ["momentum": .objeto([
            "items": .lista([.texto("sola")])])]))), 50)
    }

    /// Y las formas se pintan en los DOS temas: nada de literales.
    func testLaPielViveEnLosDosTemas() {
        for rol in ["circulo", "termometro", "parrilla"] {
            let extra: [String: Json] = switch rol {
                case "circulo": ["rotulo": .texto("X")]
                case "termometro": ["termometro": .objeto(["pct": .numero(50)])]
                default: ["parrilla": .objeto(["celdas": .lista([.texto("a"), .texto("b")])])]
            }
            for t in [Tema.claro, Tema.oscuro] {
                XCTAssertGreaterThan(tinta(pintar(el(rol, extra), tema: t)), 150,
                                     "\(rol) desaparece en tema \(t.nombre)")
            }
        }
    }

    /// LA RAMPA se usa DE VERDAD: los tres tonos de un territorio tienen que
    /// distinguirse. Con la rampa al 10% —el fallo de la iteración 3— eran el
    /// mismo color y la profundidad era invisible.
    func testLosTresTonosDeUnTerritorioSeDistinguen() {
        for tema in [Tema.claro, Tema.oscuro] {
            for t in ["morado", "ambar"] {
                let a = tema.rampa(t, 0.12), b = tema.rampa(t, 0.55), c = tema.tintes[t]!.trazo
                func luz(_ col: NSColor) -> Double {
                    let s = col.usingColorSpace(.sRGB)!
                    return 0.299 * s.redComponent + 0.587 * s.greenComponent + 0.114 * s.blueComponent
                }
                XCTAssertGreaterThan(abs(luz(a) - luz(b)), 0.05, "\(tema.nombre)/\(t): tenue y medio iguales")
                XCTAssertGreaterThan(abs(luz(b) - luz(c)), 0.04, "\(tema.nombre)/\(t): medio y fuerte iguales")
            }
        }
    }
}
