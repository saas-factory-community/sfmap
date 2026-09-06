import XCTest
import AppKit
@testable import SFMap

/**
 * NINGUNA FIGURA PUEDE SER INVISIBLE NI MENTIR SU RADIO.
 *
 * Medido el 24 ago 2026 en el lienzo de Daniel: el rol "trigger" trae
 * radio 999 (token píldora, espejo del web — legítimo). Dos fallos de UX:
 * el deslizador de Esquinas mostraba "999" y pintaba su barra 15x más ancha
 * que el riel ("la línea que se salió"), y al quitar el contorno un disparador
 * blanco sobre lienzo blanco desaparecía por completo — elemento perdido sin
 * error. Estas pruebas cierran las tres puertas.
 */
final class FiguraVisibleTests: XCTestCase {

    /// Estándar 24 ago 2026: ningún rol declara un radio que el gesto no pueda
    /// representar (tope del deslizador: 64). El centinela 999 no vuelve.
    func testNingunRolConRadioCentinela() {
        for tema in [Tema.claro, Tema.oscuro] {
            for (nombre, estilo) in tema.roles {
                XCTAssertLessThanOrEqual(estilo.radio, 64,
                    "rol \(nombre) en tema \(tema.nombre) declara radio \(estilo.radio)")
            }
        }
    }

    /// Una figura sin contorno cuyo relleno es del color del lienzo se pinta
    /// con el fantasma: sus píxeles NO pueden ser todos idénticos al fondo.
    func testFiguraInvisibleGanaFantasma() {
        let tema = Tema.claro
        let ancho = 120, alto = 80
        guard let ctx = CGContext(data: nil, width: ancho, height: alto,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return XCTFail("sin contexto")
        }
        ctx.setFillColor(tema.lienzo.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: ancho, height: alto))

        // disparador (relleno blanco) con el trazo quitado a mano
        let crudo: Json = .objeto([
            "id": .texto("t"), "type": .texto("shape"), "shape": .texto("rect"),
            "role": .texto("trigger"),
            "x": .numero(10), "y": .numero(10), "width": .numero(100), "height": .numero(60),
            "trazo": .objeto(["explicit": .bool(true), "width": .numero(0)]),
        ])
        let e = Elemento(crudo)
        let pintor = Pintor(ctx: ctx, tema: tema, camara: Camara(),
                            tamano: CGSize(width: ancho, height: alto))
        pintor.figura(e)

        guard let img = ctx.makeImage(), let data = img.dataProvider?.data else {
            return XCTFail("sin imagen")
        }
        let px = CFDataGetBytePtr(data)!
        let fondo = (px[0], px[1], px[2])
        var distintos = 0
        for i in stride(from: 0, to: CFDataGetLength(data), by: 4) {
            if (px[i], px[i+1], px[i+2]) != fondo { distintos += 1 }
        }
        XCTAssertGreaterThan(distintos, 0,
            "la figura sin contorno con relleno del color del lienzo se pintó invisible")
    }
}
