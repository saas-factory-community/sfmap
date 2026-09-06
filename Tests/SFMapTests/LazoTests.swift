import XCTest
import AppKit
@testable import SFMap

/**
 * EL LAZO RESPONDE DE VERDAD — y enseña lo que dice enseñar.
 *
 * Tres leyes, tres pruebas: con regreso el pulso da vueltas hasta que el sensor
 * dice que quedó · sin regreso entrega sin llegar · con la referencia baja
 * termina antes y con menos. Más las de siempre: determinista, no escribe en
 * el documento, y el reloj se muere.
 */
final class LazoTests: XCTestCase {

    private func elemento(_ ref: Double = 0.78) -> Elemento {
        Elemento(.objeto([
            "id": .texto("lz"), "type": .texto("shape"), "shape": .texto("rect"),
            "role": .texto("card"), "tint": .texto("morado"),
            "x": .numero(10), "y": .numero(10), "width": .numero(900), "height": .numero(420),
            "mecanismo": .objeto(["tipo": .texto("lazo"), "valor": .numero(ref), "rotulo": .texto("referencia")]),
        ]))
    }

    /// Corre el lazo entero a pasos fijos de reloj (sin Timer): función pura.
    private func correr(_ v: Lazo.Vivo, tope: Double = 60) -> Double {
        Lazo.arrancar(v)
        var t = 0.0
        while v.corriendo && t < tope { Lazo.avanzar(v, dt: 1.0 / 60); t += 1.0 / 60 }
        return t
    }

    func testConRegresoDaVueltasHastaLlegar() {
        let v = Lazo.Vivo(referencia: 0.78)
        _ = correr(v)
        XCTAssertTrue(v.terminado)
        XCTAssertEqual(v.veredicto, "LLEGÓ")
        XCTAssertGreaterThanOrEqual(v.resultado, 0.78)
        XCTAssertGreaterThanOrEqual(v.vueltas, 4, "0.12 + 0.17·n ≥ 0.78 exige al menos 4 vueltas")
        XCTAssertEqual(v.caliente, 4)
    }

    func testSinRegresoEntregaSinLlegar() {
        let v = Lazo.Vivo(referencia: 0.78); v.regreso = false
        _ = correr(v)
        XCTAssertTrue(v.terminado)
        XCTAssertEqual(v.veredicto, "ENTREGÓ SIN LLEGAR")
        XCTAssertEqual(v.vueltas, 1, "sin ciclo el pulso pasa UNA vez y entrega")
        XCTAssertGreaterThan(Lazo.error(v), 0)
    }

    /// La referencia es un TECHO: bajarla termina antes y con menos.
    func testLaReferenciaBajaTerminaAntesYConMenos() {
        let alta = Lazo.Vivo(referencia: 0.78), baja = Lazo.Vivo(referencia: 0.30)
        let tAlta = correr(alta), tBaja = correr(baja)
        XCTAssertEqual(baja.veredicto, "LLEGÓ")
        XCTAssertLessThan(baja.vueltas, alta.vueltas)
        XCTAssertLessThan(tBaja, tAlta)
        XCTAssertLessThan(baja.resultado, alta.resultado)
    }

    func testElPulsoRecorreLosTramosEnOrden() {
        let e = elemento()
        let c = Lazo.centros(e)
        XCTAssertEqual(c.count, 5)
        let ini = Lazo.puntoPulso(e, seg: 0, t: 0), fin = Lazo.puntoPulso(e, seg: 0, t: 1)
        XCTAssertLessThan(ini.x, fin.x, "el tramo 0 va de ENTRADA hacia HACER")
        // El regreso pasa por DEBAJO de los nodos: no se confunde con la ida.
        let medio = Lazo.puntoPulso(e, seg: 3, t: 0.5)
        XCTAssertGreaterThan(medio.y, c[1].y + Lazo.radio(e))
        XCTAssertLessThan(Lazo.puntoPulso(e, seg: 3, t: 1).x, Lazo.puntoPulso(e, seg: 3, t: 0).x)
    }

    // ── PÍXELES ─────────────────────────────────────────────────────────────

    private func ctxDe(_ tema: Tema) -> CGContext? {
        guard let ctx = CGContext(data: nil, width: 940, height: 460, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(tema.lienzo.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 940, height: 460))
        return ctx
    }
    private func pixeles(_ ctx: CGContext) -> [UInt8] {
        guard let d = ctx.data else { return [] }
        let p = d.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * ctx.height)
        var out: [UInt8] = []
        for y in 0..<ctx.height { for x in 0..<(ctx.width * 4) { out.append(p[y * ctx.bytesPerRow + x]) } }
        return out
    }

    func testCorrerCambiaElDibujoYElMismoEstadoPintaLoMismo() {
        let tema = Tema.claro, e = elemento()
        guard let a = ctxDe(tema), let b = ctxDe(tema), let c = ctxDe(tema) else { return XCTFail("sin contexto") }
        let quieto = Lazo.Vivo(referencia: 0.78)
        let enMarcha = Lazo.Vivo(referencia: 0.78); Lazo.arrancar(enMarcha); Lazo.avanzar(enMarcha, dt: 0.2)
        Mecanismo.pintar(e, a, tema, valor: 0.78, lazo: quieto)
        Mecanismo.pintar(e, b, tema, valor: 0.78, lazo: enMarcha)
        Mecanismo.pintar(e, c, tema, valor: 0.78, lazo: quieto)
        XCTAssertNotEqual(pixeles(a), pixeles(b), "el pulso corrió y el dibujo no cambió")
        XCTAssertEqual(pixeles(a), pixeles(c), "el mismo estado tiene que pintar lo mismo")
    }

    /// Nada de esto toca el documento: el JSON del elemento es el mismo antes
    /// y después de correr el lazo entero.
    func testElValorNoSeGuardaEnElElemento() {
        let e = elemento()
        let antes = "\(e.crudo)"
        let st = Mecanismo.Estado()
        st.correr(e)
        var t = 0.0
        while st.tick(dt: 1.0 / 60) && t < 60 { t += 1.0 / 60 }
        XCTAssertEqual("\(e.crudo)", antes)
        XCTAssertTrue(st.lazo(e).terminado)
    }

    /// El reloj se muere: cuando ningún lazo corre, `tick` dice que no hay vida.
    func testElRelojMuereAlLlegar() {
        let e = elemento()
        let st = Mecanismo.Estado()
        st.correr(e)
        var vivo = true, t = 0.0
        while vivo && t < 60 { vivo = st.tick(dt: 1.0 / 60); t += 1.0 / 60 }
        XCTAssertFalse(vivo)
        XCTAssertFalse(st.lazo(e).corriendo)
    }

    /// Alternar el regreso reinicia el lazo y pinta la flecha apagada; correr
    /// de nuevo termina sin llegar.
    func testAlternarRegresoCambiaElVeredicto() {
        let e = elemento()
        let st = Mecanismo.Estado()
        st.alternarRegreso(e)
        XCTAssertFalse(st.lazo(e).regreso)
        st.correr(e)
        var t = 0.0
        while st.tick(dt: 1.0 / 60) && t < 60 { t += 1.0 / 60 }
        XCTAssertEqual(st.lazo(e).veredicto, "ENTREGÓ SIN LLEGAR")
    }
}
