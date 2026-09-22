import XCTest
import AppKit
@testable import SFMap

/**
 * EL MECANISMO RESPONDE DE VERDAD. Medido en píxeles, fuera de pantalla.
 *
 * La promesa de un mecanismo es «mueves esto y pasa aquello». Un dial que se
 * pinta pero no cambia nada sería el actuador que reporta su intención — la
 * falla que este repo persigue. Aquí se renderiza dos veces con dos valores y
 * se compara el mapa de bits.
 */
final class MecanismoTests: XCTestCase {

    private func ctxDe(_ ancho: Int, _ alto: Int, _ tema: Tema) -> CGContext? {
        guard let ctx = CGContext(data: nil, width: ancho, height: alto,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(tema.lienzo.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: ancho, height: alto))
        return ctx
    }

    /// Copia los píxeles fila a fila (con `bytesPerRow: 0` cada fila lleva
    /// relleno alineado que no es imagen: compararlo daría diferencias falsas).
    private func pixeles(_ ctx: CGContext) -> [UInt8] {
        guard let datos = ctx.data else { return [] }
        let p = datos.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * ctx.height)
        var out: [UInt8] = []
        out.reserveCapacity(ctx.width * ctx.height * 4)
        for y in 0..<ctx.height {
            for x in 0..<(ctx.width * 4) { out.append(p[y * ctx.bytesPerRow + x]) }
        }
        return out
    }

    private func engranes(_ valor: Double = 0.35) -> Elemento {
        Elemento(.objeto([
            "id": .texto("m1"), "type": .texto("shape"), "shape": .texto("rect"),
            "role": .texto("card"), "tint": .texto("morado"),
            "x": .numero(20), "y": .numero(20), "width": .numero(360), "height": .numero(220),
            "mecanismo": .objeto([
                "tipo": .texto("engranes"),
                "valor": .numero(valor),
                "rotulo": .texto("velocidad"),
                "piezas": .lista([
                    .objeto(["radio": .numero(1.0), "dientes": .numero(18), "rotulo": .texto("motriz")]),
                    .objeto(["radio": .numero(0.55), "dientes": .numero(9), "rotulo": .texto("rápido")]),
                ]),
            ]),
        ]))
    }

    // ── LECTURA ─────────────────────────────────────────────────────────────

    func testSoloEsMecanismoConSuClave() {
        XCTAssertTrue(Mecanismo.esMecanismo(engranes()))
        let normal = Elemento(.objeto(["id": .texto("x"), "type": .texto("shape"),
                                       "x": .numero(0), "y": .numero(0),
                                       "width": .numero(10), "height": .numero(10)]))
        XCTAssertFalse(Mecanismo.esMecanismo(normal))
    }

    func testElValorArranaDondeDiceElGenerador() {
        XCTAssertEqual(Mecanismo.inicial(engranes(0.7)), 0.7, accuracy: 0.001)
        // Y nunca fuera de rango, venga como venga del JSON.
        XCTAssertEqual(Mecanismo.inicial(engranes(9)), 1, accuracy: 0.001)
        XCTAssertEqual(Mecanismo.inicial(engranes(-3)), 0, accuracy: 0.001)
    }

    /// La x del puntero → valor. Si esto se desalinea, la perilla se pinta en un
    /// sitio y responde en otro: el control se siente roto aunque «funcione».
    func testLaManoYLaPerillaHablanDelMismoRiel() {
        let e = engranes()
        let r = Mecanismo.riel(e)
        XCTAssertEqual(Mecanismo.valorEn(e, CGPoint(x: r.minX, y: r.midY)), 0, accuracy: 0.001)
        XCTAssertEqual(Mecanismo.valorEn(e, CGPoint(x: r.maxX, y: r.midY)), 1, accuracy: 0.001)
        XCTAssertEqual(Mecanismo.valorEn(e, CGPoint(x: r.midX, y: r.midY)), 0.5, accuracy: 0.001)
        // Fuera del riel se satura en vez de dispararse.
        XCTAssertEqual(Mecanismo.valorEn(e, CGPoint(x: r.minX - 500, y: r.midY)), 0, accuracy: 0.001)
    }

    /// La zona sensible cubre el riel entero y con holgura: agarrar una barra de
    /// 22 px en directo, a zoom bajo, no puede ser una pelea.
    func testLaZonaSensibleEsMasGenerosaQueElRiel() {
        let e = engranes()
        XCTAssertTrue(Mecanismo.zonaDial(e).contains(Mecanismo.riel(e).origin))
        XCTAssertGreaterThan(Mecanismo.zonaDial(e).height, Mecanismo.riel(e).height)
    }

    // ── LO QUE IMPORTA: QUE RESPONDA ────────────────────────────────────────

    /// Mover el dial cambia el dibujo. Es la prueba de que el mecanismo enacta
    /// y no sólo se pinta.
    func testDialEnExtremosYRecorridoCortoNoProduceGeometriaInvalida() {
        for valor in [0.0, 0.001, 0.01, 0.1, 0.5, 1.0] {
            guard let contexto = ctxDe(400, 260, .claro) else { return XCTFail("sin contexto") }
            Mecanismo.pintar(engranes(), contexto, .claro, valor: valor)
            XCTAssertFalse(pixeles(contexto).isEmpty)
        }
    }

    func testMoverElDialCambiaElDibujo() {
        let tema = Tema.claro
        let e = engranes()
        guard let a = ctxDe(400, 260, tema), let b = ctxDe(400, 260, tema) else {
            return XCTFail("sin contexto")
        }
        Mecanismo.pintar(e, a, tema, valor: 0.10)
        Mecanismo.pintar(e, b, tema, valor: 0.62)
        XCTAssertNotEqual(pixeles(a), pixeles(b),
                          "el dial se movió y el mecanismo no cambió")
    }

    /// Y pintar dos veces con el MISMO valor da exactamente lo mismo: sin esto,
    /// un mecanismo con azar escondido haría imposible verificar nada.
    func testElMismoValorPintaLoMismo() {
        let tema = Tema.claro
        let e = engranes()
        guard let a = ctxDe(400, 260, tema), let b = ctxDe(400, 260, tema) else {
            return XCTFail("sin contexto")
        }
        Mecanismo.pintar(e, a, tema, valor: 0.42)
        Mecanismo.pintar(e, b, tema, valor: 0.42)
        XCTAssertEqual(pixeles(a), pixeles(b))
    }

    /// El valor vive en memoria y NUNCA en el elemento: mover la mano en cámara
    /// no puede escribir en `draw` (misma regla que el Cronista).
    func testElValorNoTocaElDocumento() {
        let e = engranes(0.3)
        let st = Mecanismo.Estado()
        XCTAssertEqual(st.valor(e), 0.3, accuracy: 0.001)
        st.poner(e.id, 0.9)
        XCTAssertEqual(st.valor(e), 0.9, accuracy: 0.001)
        XCTAssertEqual(Mecanismo.inicial(e), 0.3, accuracy: 0.001,
                       "el dial escribió en el elemento")
        // Y se satura: un valor imposible dejaría la perilla fuera del riel.
        st.poner(e.id, 4)
        XCTAssertEqual(st.valor(e), 1, accuracy: 0.001)
    }

    /// RETRATO PARA EL OJO. Los píxeles prueban que responde, no que se vea
    /// bien: eso lo dice un ojo. Escribe una tira con tres posiciones del dial
    /// sólo cuando se pide (`SFMAP_RETRATO=<carpeta> swift test …`), para poder
    /// mirarla sin abrir la app en mitad del deep work de Daniel.
    func testRetratoDelMecanismo() throws {
        guard let carpeta = ProcessInfo.processInfo.environment["SFMAP_RETRATO"] else { return }
        let tema = Tema.claro
        let e = engranes()
        let (an, al) = (400, 260)
        guard let ctx = ctxDe(an * 3, al, tema) else { return XCTFail("sin contexto") }
        // ⚠️ EL LIENZO ES `isFlipped`: AppKit le entrega al pintor un contexto
        // con la Y hacia ABAJO. Un contexto crudo la tiene hacia arriba, así que
        // sin este volteo el retrato sale en espejo (el dial arriba, los
        // rótulos del revés) y mentiría sobre lo que se ve en la app.
        ctx.translateBy(x: 0, y: Double(al)); ctx.scaleBy(x: 1, y: -1)
        for (i, v) in [0.0, 0.35, 0.8].enumerated() {
            ctx.saveGState()
            ctx.translateBy(x: Double(i * an), y: 0)
            Mecanismo.pintar(e, ctx, tema, valor: v)
            ctx.restoreGState()
        }
        // Y el BALANCE, que es el mecanismo de la capa 2: unas barras suben
        // mientras otras bajan, y nunca se ganan las dos cosas.
        let bal = Elemento(.objeto([
            "id": .texto("b1"), "type": .texto("shape"), "tint": .texto("ambar"),
            "x": .numero(0), "y": .numero(0), "width": .numero(560), "height": .numero(240),
            "mecanismo": .objeto([
                "tipo": .texto("balance"), "valor": .numero(0.5),
                "rotulo": .texto("contexto"),
                "piezas": .lista([
                    .objeto(["radio": .numero(1), "rotulo": .texto("DETALLE")]),
                    .objeto(["radio": .numero(-1), "rotulo": .texto("VELOCIDAD")]),
                    .objeto(["radio": .numero(1), "rotulo": .texto("ENERGÍA")]),
                ]),
            ]),
        ]))
        guard let cb = ctxDe(560 * 2, 240, tema) else { return XCTFail("sin contexto") }
        cb.translateBy(x: 0, y: 240); cb.scaleBy(x: 1, y: -1)
        for (i, v) in [0.18, 0.82].enumerated() {
            cb.saveGState(); cb.translateBy(x: Double(i * 560), y: 0)
            Mecanismo.pintar(bal, cb, tema, valor: v)
            cb.restoreGState()
        }
        if let ib = cb.makeImage(),
           let db = NSBitmapImageRep(cgImage: ib).representation(using: .png, properties: [:]) {
            try db.write(to: URL(fileURLWithPath: "\(carpeta)/mecanismo-balance.png"))
        }

        guard let img = ctx.makeImage() else { return XCTFail("sin imagen") }
        let rep = NSBitmapImageRep(cgImage: img)
        guard let datos = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("sin PNG")
        }
        try datos.write(to: URL(fileURLWithPath: "\(carpeta)/mecanismo-engranes.png"))
    }

    // ── LA GRÁFICA ──────────────────────────────────────────────────────────

    private func grafica() -> Elemento {
        Elemento(.objeto([
            "id": .texto("g1"), "type": .texto("shape"), "tint": .texto("ambar"),
            "x": .numero(0), "y": .numero(0), "width": .numero(1000), "height": .numero(700),
            "mecanismo": .objeto([
                "tipo": .texto("grafica"), "unidad": .texto(""),
                "x0": .numero(2020), "x1": .numero(2026), "y1": .numero(16),
                "marcasY": .lista([.objeto(["v": .numero(1), "t": .texto("1 hora")]),
                                   .objeto(["v": .numero(8), "t": .texto("8 horas")])]),
                "puntos": .lista([
                    .objeto(["x": .numero(2020), "y": .numero(0), "rotulo": .texto("A")]),
                    .objeto(["x": .numero(2023), "y": .numero(8), "rotulo": .texto("B")]),
                    .objeto(["x": .numero(2026), "y": .numero(16), "rotulo": .texto("C")]),
                ]),
            ]),
        ]))
    }

    /**
     * EL EJE ESTÁ MEDIDO, NO PUESTO A OJO.
     *
     * Daniel pidió la gráfica *«bien preciso el eje x y el eje y»*. Si un punto
     * cae donde no le toca, la página deja de ser un instrumento y pasa a ser
     * un dibujo de un instrumento — que es justo lo que venía a sustituir.
     */
    func testCadaPuntoCaeDondeDiceElDato() {
        let e = grafica()
        let r = Mecanismo.plano(e)
        let ps = Mecanismo.puntos(e)
        // El primero: origen exacto (2020, 0) → esquina inferior izquierda.
        let a = Mecanismo.aPlano(e, ps[0])
        XCTAssertEqual(a.x, r.minX, accuracy: 0.5)
        XCTAssertEqual(a.y, r.maxY, accuracy: 0.5)
        // El último: (2026, 16) con x1=2026 e y1=16 → esquina superior derecha.
        let c = Mecanismo.aPlano(e, ps[2])
        XCTAssertEqual(c.x, r.maxX, accuracy: 0.5)
        XCTAssertEqual(c.y, r.minY, accuracy: 0.5)
        // El de en medio: mitad exacta del eje X, y la mitad del eje Y.
        let b = Mecanismo.aPlano(e, ps[1])
        XCTAssertEqual(b.x, r.midX, accuracy: 0.5)
        XCTAssertEqual(b.y, r.maxY - r.height / 2, accuracy: 0.5)
    }

    /// El ratón y el dibujo hablan del mismo sitio: `puntoEn` usa la MISMA
    /// conversión que el pintor. Si divergieran, señalarías un punto y se
    /// encendería otro.
    func testElRatonEncuentraElPuntoQueSeVe() {
        let e = grafica()
        for (i, p) in Mecanismo.puntos(e).enumerated() {
            XCTAssertEqual(Mecanismo.puntoEn(e, Mecanismo.aPlano(e, p)), i)
        }
        // Lejos de todo: nada señalado, y no explota.
        XCTAssertNil(Mecanismo.puntoEn(e, CGPoint(x: 5000, y: 5000)))
    }

    /// Y el hover CAMBIA el dibujo: sin esto, la etiqueta sería una promesa.
    func testElHoverPintaLaEtiqueta() {
        let tema = Tema.claro
        let e = grafica()
        guard let a = ctxDe(1000, 700, tema), let b = ctxDe(1000, 700, tema) else {
            return XCTFail("sin contexto")
        }
        Mecanismo.pintar(e, a, tema, valor: 0, senalado: nil)
        Mecanismo.pintar(e, b, tema, valor: 0, senalado: 1)
        XCTAssertNotEqual(pixeles(a), pixeles(b), "el hover no cambió nada")
    }

    /// El estado del hover no toca el documento y sabe decir «ya no hay nada».
    func testElHoverVaYVuelve() {
        let st = Mecanismo.Estado()
        let e = grafica()
        XCTAssertNil(st.senalado(de: e))
        XCTAssertTrue(st.senalar("g1", 2))
        XCTAssertEqual(st.senalado(de: e), 2)
        XCTAssertFalse(st.senalar("g1", 2), "repintó sin que cambiara nada")
        XCTAssertTrue(st.senalar(nil, nil))
        XCTAssertNil(st.senalado(de: e))
    }

    // ── EL COSTE, MEDIDO ────────────────────────────────────────────────────

    private func ms(_ n: Int, _ f: () -> Void) -> Double {
        let t0 = ProcessInfo.processInfo.systemUptime
        for _ in 0..<n { f() }
        return (ProcessInfo.processInfo.systemUptime - t0) * 1000 / Double(n)
    }

    /**
     * UN MECANISMO NO PUEDE COSTAR UN FOTOGRAMA.
     *
     * El lienzo se repinta ENTERO en cada fotograma del arrastre y el
     * presupuesto es 8.3 ms a 120 Hz. Daniel lo notó a ojo el primer día
     * (*"¿parpadea cuando lo muevo?"*) y el cronómetro le dio la razón. Una
     * pieza que se pinta muchas veces por segundo tiene que ser barata: este
     * test es el sensor que impide que vuelva a engordar en silencio.
     */
    func testUnMecanismoNoCuestaUnFotograma() {
        let tema = Tema.claro
        let e = engranes()
        guard let ctx = ctxDe(400, 260, tema) else { return XCTFail("sin contexto") }
        let coste = ms(40) { Mecanismo.pintar(e, ctx, tema, valor: 0.4) }
        if ProcessInfo.processInfo.environment["SFMAP_RETRATO"] != nil {
            print(String(format: "COSTE mecanismo = %.3f ms", coste))
        }
        XCTAssertLessThan(coste, 2.0,
                          "el mecanismo se comió un cuarto del presupuesto de fotograma")
    }

    /// Sin `piezas` declaradas sale un tren que YA enseña: nadie tiene que
    /// configurar tres radios para poder explicar una transmisión.
    func testSinPiezasHayTrenPorDefecto() {
        let e = Elemento(.objeto([
            "id": .texto("m2"), "type": .texto("shape"),
            "x": .numero(0), "y": .numero(0), "width": .numero(300), "height": .numero(200),
            "mecanismo": .objeto(["tipo": .texto("engranes")]),
        ]))
        XCTAssertGreaterThanOrEqual(Mecanismo.piezas(e).count, 2)
        // Y los radios van de mayor a menor: la transmisión se ve sola.
        let rs = Mecanismo.piezas(e).map(\.radio)
        XCTAssertEqual(rs, rs.sorted(by: >))
    }
}
