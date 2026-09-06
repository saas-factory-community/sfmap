import XCTest
import AppKit
@testable import SFMap

/**
 * EL MODO CLASE, MEDIDO. Ni la tapa se ve, ni lo que aún no toca se pinta.
 *
 * Las dos afirmaciones que sostienen el curso v2 son visuales, y una
 * afirmación visual sin píxeles medidos es un actuador reportando su
 * intención. Aquí se renderiza de verdad, fuera de pantalla, y se cuentan
 * píxeles.
 */
final class EnactarTests: XCTestCase {

    private func lienzoDePrueba(_ ancho: Int, _ alto: Int, _ tema: Tema) -> CGContext? {
        guard let ctx = CGContext(data: nil, width: ancho, height: alto,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(tema.lienzo.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: ancho, height: alto))
        return ctx
    }

    /// Cuántos píxeles NO son del color del lienzo.
    private func pintados(_ ctx: CGContext, _ tema: Tema) -> Int {
        guard let datos = ctx.data else { return -1 }
        /*
         * ⚠️ SE RECORRE POR FILAS, NO EN LÍNEA RECTA. Con `bytesPerRow: 0` el
         * sistema alinea cada fila (140 px = 560 B → 576 B) y ese relleno son
         * ceros: contarlo daba 348 píxeles "pintados" en un lienzo vacío. El
         * primer verde de esta prueba fue rojo por el instrumento, no por el
         * código medido.
         */
        let porFila = ctx.bytesPerRow
        let p = datos.bindMemory(to: UInt8.self, capacity: porFila * ctx.height)
        let fondo = tema.lienzo.usingColorSpace(.deviceRGB) ?? .white
        let r = UInt8(fondo.redComponent * 255), g = UInt8(fondo.greenComponent * 255)
        let b = UInt8(fondo.blueComponent * 255)
        var cuenta = 0
        for y in 0..<ctx.height {
            for x in 0..<ctx.width {
                let i = y * porFila + x * 4
                let dr = Int(p[i]) - Int(r), dg = Int(p[i + 1]) - Int(g)
                let db = Int(p[i + 2]) - Int(b)
                if abs(dr) + abs(dg) + abs(db) > 6 { cuenta += 1 }
            }
        }
        return cuenta
    }

    private func rect(_ id: String, rol: String, escena: Json? = nil) -> Elemento {
        var o: [String: Json] = [
            "id": .texto(id), "type": .texto("shape"), "shape": .texto("rect"),
            "role": .texto(rol),
            "x": .numero(20), "y": .numero(20), "width": .numero(80), "height": .numero(40),
            "trazo": .objeto(["explicit": .bool(true), "width": .numero(0)]),
        ]
        if let escena { o["escena"] = escena }
        return Elemento(.objeto(o))
    }

    // ── LA TAPA ─────────────────────────────────────────────────────────────

    /// El rol `tapa` es el ÚNICO que puede ser invisible: en los DOS temas su
    /// relleno es exactamente el papel, y no se le pinta fantasma. Si alguna
    /// vez se ve, la cortina delata el truco y el módulo se arruina en cámara.
    func testLaTapaNoDejaHuellaEnNingunTema() {
        for tema in [Tema.claro, Tema.oscuro] {
            guard let ctx = lienzoDePrueba(140, 90, tema) else { return XCTFail("sin contexto") }
            let pintor = Pintor(ctx: ctx, tema: tema, camara: Camara(),
                                tamano: CGSize(width: ctx.width, height: ctx.height))
            pintor.figura(rect("tapa1", rol: "tapa"))
            XCTAssertEqual(pintados(ctx, tema), 0,
                           "la tapa dejó huella en el tema \(tema.nombre)")
        }
    }

    /// La tapa es invisible al OJO pero no a la MANO: acepta puertos, así que
    /// el hover la delata al pasar el ratón y se puede agarrar para arrastrarla
    /// en cámara. Sin esto, una cortina invisible sería una cortina perdida.
    func testLaTapaSeEncuentraConElRaton() {
        XCTAssertTrue(Geo.aceptaPuertos(rect("tapa1", rol: "tapa")))
        XCTAssertFalse(rect("tapa1", rol: "tapa").bloqueado,
                       "una tapa bloqueada no se puede arrastrar")
    }

    /// Y la regla que protege el fantasma sigue en pie para todo lo demás: una
    /// figura invisible que NO es tapa se sigue marcando.
    func testElFantasmaSigueVivoFueraDeLaTapa() {
        let tema = Tema.claro
        guard let ctx = lienzoDePrueba(140, 90, tema) else { return XCTFail("sin contexto") }
        let pintor = Pintor(ctx: ctx, tema: tema, camara: Camara(), tamano: CGSize(width: ctx.width, height: ctx.height))
        pintor.figura(rect("t", rol: "trigger"))
        XCTAssertGreaterThan(pintados(ctx, tema), 0, "el fantasma se perdió")
    }

    // ── LAS ESCENAS ─────────────────────────────────────────────────────────

    func testLecturaDeEscena() {
        let e = rect("a", rol: "card",
                     escena: .objeto(["orden": .numero(3), "gesto": .texto("trazar")]))
        XCTAssertEqual(Enactar.orden(e), 3)
        XCTAssertEqual(Enactar.gesto(e), .trazar)
        // Sin `escena` = decorado, y el gesto cae al default sin explotar.
        let d = rect("b", rol: "card")
        XCTAssertEqual(Enactar.orden(d), 0)
        XCTAssertEqual(Enactar.gesto(d), .aparecer)
        XCTAssertEqual(Enactar.tope([e, d]), 3)
    }

    /// Lo que todavía no toca NO SE PINTA; lo ya dicho se pinta entero. Es la
    /// prueba de que el revelado es real y no una opacidad a medias.
    func testLoQueNoTocaNoSePinta() {
        let tema = Tema.claro
        let st = Enactar.Estado()
        let e = rect("a", rol: "card",
                     escena: .objeto(["orden": .numero(1), "gesto": .texto("aparecer")]))

        // Paso 0: el elemento del paso 1 no existe todavía.
        guard let ctx0 = lienzoDePrueba(140, 90, tema) else { return XCTFail("sin contexto") }
        st.entrar(tope: 1)
        let p0 = Pintor(ctx: ctx0, tema: tema, camara: Camara(), tamano: CGSize(width: ctx0.width, height: ctx0.height))
        let pintado0 = Enactar.conEscena(ctx0, e, st) { p0.figura(e) }
        XCTAssertFalse(pintado0, "se pintó un elemento de un paso que no ha llegado")
        XCTAssertEqual(pintados(ctx0, tema), 0)

        // Paso 1 ya revelado del todo: se pinta como cualquier figura.
        guard let ctx1 = lienzoDePrueba(140, 90, tema) else { return XCTFail("sin contexto") }
        st.revelarTodo()
        let p1 = Pintor(ctx: ctx1, tema: tema, camara: Camara(), tamano: CGSize(width: ctx1.width, height: ctx1.height))
        let pintado1 = Enactar.conEscena(ctx1, e, st) { p1.figura(e) }
        XCTAssertTrue(pintado1)
        XCTAssertGreaterThan(pintados(ctx1, tema), 0, "el elemento revelado no apareció")
    }

    /// Fuera del modo, el lienzo es el de siempre: un export nunca puede salir
    /// a medio revelar.
    func testFueraDelModoTodoSePinta() {
        let tema = Tema.claro
        guard let ctx = lienzoDePrueba(140, 90, tema) else { return XCTFail("sin contexto") }
        let st = Enactar.Estado()   // nunca entró
        let e = rect("a", rol: "card", escena: .objeto(["orden": .numero(9)]))
        let p = Pintor(ctx: ctx, tema: tema, camara: Camara(), tamano: CGSize(width: ctx.width, height: ctx.height))
        XCTAssertTrue(Enactar.conEscena(ctx, e, st) { p.figura(e) })
        XCTAssertGreaterThan(pintados(ctx, tema), 0)
    }

    func testElSuavizadoEsMonotonoYCierraEnUno() {
        XCTAssertEqual(Enactar.suave(0), 0, accuracy: 0.001)
        XCTAssertEqual(Enactar.suave(1), 1, accuracy: 0.001)
        var previo = -1.0
        for i in 0...10 {
            let v = Enactar.suave(Double(i) / 10)
            XCTAssertGreaterThan(v, previo); previo = v
        }
    }

    /// El paso no puede pasarse del tope ni bajar de cero: en cámara, una
    /// flecha de más no puede dejar la página en un estado imposible.
    func testElPasoViveEntreCeroYElTope() {
        let st = Enactar.Estado()
        st.entrar(tope: 2)
        XCTAssertEqual(st.paso, 0)
        XCTAssertFalse(st.retroceder())
        XCTAssertTrue(st.avanzar()); XCTAssertTrue(st.avanzar())
        XCTAssertFalse(st.avanzar(), "se pasó del tope")
        XCTAssertEqual(st.paso, 2)
        st.salir()
        XCTAssertFalse(st.avanzar(), "avanza fuera del modo")
    }
}
