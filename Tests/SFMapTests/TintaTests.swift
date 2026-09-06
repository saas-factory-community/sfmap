import XCTest
import CoreGraphics
@testable import SFMap

/**
 * Las pruebas del motor de tinta.
 *
 * No comprueban que "se vea bonito" —eso lo juzga el banco con imágenes— sino
 * las propiedades que, si se rompen, rompen el trazo sin que nadie lo note:
 * que el borrador y el guardado sean el MISMO camino, que un trazo viejo sin
 * inclinación ni tiempos siga saliendo, que la respuesta de presión sea
 * monótona, y que ningún caso degenerado escupa un NaN dentro de un CGPath.
 */
final class TintaTests: XCTestCase {

    /**
     * LA RUEDA ANDA POR LA ESCALERA DEL PANEL, no de medio en medio pixel.
     *
     * ⚠️ Esta prueba clavaba el contrato ANTERIOR (4 → 4.5) y ese contrato era
     * el fallo: el dial dejaba el grosor ENTRE los valores de la fila del
     * panel, ninguna casilla quedaba marcada, y girar la rueda parecia no
     * hacer efecto aunque lo hiciera. Se cambia la prueba porque se cambio la
     * decision, y queda escrito para que no vuelva por descuido.
     */
    func testLaRuedaAndaPorLaEscaleraDelPanel() {
        let e = RailHerramientas.grosores
        XCTAssertEqual(e.count, 9, "nueve peldaños")

        // Cada giro cae SIEMPRE en un peldaño, que es lo que el panel marca.
        var g = e[0]
        for _ in 0..<20 {
            g = Tinta.grosorAjustado(g, pasos: 1)
            XCTAssertTrue(e.contains(g), "\(g) no es un peldaño")
        }
        XCTAssertEqual(g, e.last!, "arriba se queda en el ultimo, sin dar la vuelta")

        var b = e.last!
        for _ in 0..<20 { b = Tinta.grosorAjustado(b, pasos: -1) }
        XCTAssertEqual(b, e.first!, "y abajo en el primero")
    }

    /// Un valor que NO es peldaño (trazo importado, version anterior) entra por
    /// el de al lado: el primer giro coloca, no salta uno por haber empezado
    /// descolocado.
    func testUnValorDescolocadoEntraPorElDeAlLado() {
        let e = RailHerramientas.grosores
        // 5.5 y no el punto medio exacto: en un empate las dos respuestas son
        // igual de correctas y la prueba estaria clavando cual gana el desempate,
        // que es un detalle de implementacion y no una promesa.
        let entre = 5.5                                     // entre 4 y 6
        XCTAssertEqual(Tinta.grosorAjustado(entre, pasos: 1), e[4], "arriba, al de encima")
        XCTAssertEqual(Tinta.grosorAjustado(entre, pasos: -1), e[3], "abajo, al de debajo")
        XCTAssertEqual(Tinta.grosorAjustado(entre, pasos: 0), e[4], "sin pasos, al mas cercano")
    }

    /// Y los peldaños CRECEN cada vez mas: la diferencia que el ojo nota entre
    /// 1 y 2 es la misma que entre 12 y 24, asi que pasos iguales en px darian
    /// cuatro finos indistinguibles y un salto brutal al final.
    func testLaEscaleraSeAbreHaciaArriba() {
        let e = RailHerramientas.grosores
        let saltos = zip(e, e.dropFirst()).map { $1 - $0 }
        XCTAssertEqual(saltos, saltos.sorted(), "ningun salto es menor que el anterior")
        XCTAssertGreaterThan(saltos.last!, saltos.first!)
    }

    // ── utilidades ──────────────────────────────────────────────────────────

    private func puntos(_ n: Int, presion: (Int) -> Double = { _ in 0.4 },
                        conTiempo: Bool = false) -> [PuntoTinta] {
        (0..<n).map { i in
            let t = Double(i) / Double(max(1, n - 1))
            return PuntoTinta(x: 20 + 200 * t, y: 60 + 40 * sin(t * 3),
                              p: presion(i), ix: 0, iy: 0,
                              t: conTiempo ? Double(i) * 8 : -1)
        }
    }

    /// Los vértices de un camino, en orden. Compararlos es más estricto que
    /// comparar la caja: dos caminos distintos pueden tener la misma caja.
    private func vertices(_ c: CGPath) -> [CGPoint] {
        var out: [CGPoint] = []
        c.applyWithBlock { e in
            let p = e.pointee
            switch p.type {
            case .moveToPoint, .addLineToPoint: out.append(p.points[0])
            case .addQuadCurveToPoint: out.append(p.points[0]); out.append(p.points[1])
            case .addCurveToPoint: out.append(p.points[0]); out.append(p.points[1]); out.append(p.points[2])
            default: break
            }
        }
        return out
    }

    private func finito(_ c: CGPath) -> Bool {
        vertices(c).allSatisfy { $0.x.isFinite && $0.y.isFinite }
    }

    // ── el requisito que el spec pide y aquí es estructural ─────────────────

    /**
     * EL BORRADOR Y EL GUARDADO SON EL MISMO CAMINO.
     *
     * El referente tiene un modo `last: !live` que hace que el trazo en curso
     * y el committeado sean dos dibujos distintos. Aquí el motor no tiene modo:
     * es una función pura de los puntos. Esta prueba comprueba lo que de verdad
     * pasa en la app — el vivo pinta en coordenadas de MUNDO y el guardado en
     * coordenadas RELATIVAS al origen con la matriz trasladada — y exige que
     * salga el mismo dibujo hasta el último decimal.
     */
    func testBorradorYGuardadoSonElMismoCamino() {
        let vivo = puntos(40, presion: { 0.05 + Double($0) * 0.012 }, conTiempo: true)
        let opc = Tinta.Opciones(grosor: 4)

        let minX = vivo.map(\.x).min()!, minY = vivo.map(\.y).min()!
        let guardado = vivo.map { q -> PuntoTinta in
            var r = q; r.x -= minX; r.y -= minY; return r
        }

        guard let a = Tinta.camino(vivo, opc), let b = Tinta.camino(guardado, opc) else {
            return XCTFail("el motor no devolvió camino")
        }
        let va = vertices(a)
        let vb = vertices(b).map { CGPoint(x: $0.x + minX, y: $0.y + minY) }
        XCTAssertEqual(va.count, vb.count, "distinto número de vértices")
        for (p, q) in zip(va, vb) {
            XCTAssertEqual(p.x, q.x, accuracy: 1e-9)
            XCTAssertEqual(p.y, q.y, accuracy: 1e-9)
        }
    }

    /// El mismo trazo dibujado dos veces da el mismo camino. Sin esto, la caché
    /// serviría un dibujo distinto del que se recalcula.
    func testEsDeterminista() {
        let p = puntos(60, presion: { 0.2 + 0.3 * sin(Double($0) / 7) }, conTiempo: true)
        let a = vertices(Tinta.camino(p, Tinta.Opciones(grosor: 5))!)
        let b = vertices(Tinta.camino(p, Tinta.Opciones(grosor: 5))!)
        XCTAssertEqual(a.count, b.count)
        for (x, y) in zip(a, b) { XCTAssertEqual(x.x, y.x, accuracy: 0); XCTAssertEqual(x.y, y.y, accuracy: 0) }
    }

    /**
     * UN TRAZO CRECE POR EL FINAL, NO POR EL PRINCIPIO.
     *
     * Mientras se dibuja, el motor corre entero sobre el arreglo que crece. Si
     * el filtro no fuera causal, cada muestra nueva movería el trazo YA
     * pintado: la tinta "respiraría" detrás de la pluma. Se comprueba que el
     * principio del camino no se mueve al añadir puntos al final.
     */
    func testLoYaPintadoNoSeMueve() {
        let todo = puntos(60, presion: { 0.1 + Double($0) * 0.008 }, conTiempo: true)
        let opc = Tinta.Opciones(grosor: 4)
        let corto = Array(todo.prefix(30))
        guard let a = Tinta.camino(corto, opc), let b = Tinta.camino(todo, opc) else {
            return XCTFail("sin camino")
        }
        // El lado IZQUIERDO del contorno se emite en orden desde el inicio, así
        // que los primeros vértices de los dos caminos son el mismo trecho.
        let va = vertices(a), vb = vertices(b)
        var iguales = 0
        for i in 0..<min(20, min(va.count, vb.count)) {
            if abs(va[i].x - vb[i].x) < 0.05 && abs(va[i].y - vb[i].y) < 0.05 { iguales += 1 }
        }
        XCTAssertGreaterThanOrEqual(iguales, 18, "el trazo ya pintado se movió al seguir dibujando")
    }

    // ── compatibilidad hacia atrás ──────────────────────────────────────────

    /// Un trazo VIEJO —sin inclinación, sin tiempos— tiene que salir, y con
    /// ancho variable. Es el caso de los 32 trazos que ya existen.
    func testTrazoViejoSinInclinacionNiTiempo() {
        let p = puntos(30, presion: { 0.004 + Double($0) * 0.015 }, conTiempo: false)
        guard let c = Tinta.camino(p, Tinta.Opciones(grosor: 4)) else {
            return XCTFail("un trazo sin tilt ni tiempo no debe desaparecer")
        }
        XCTAssertTrue(finito(c))
        XCTAssertGreaterThan(vertices(c).count, 50)
        XCTAssertFalse(c.boundingBox.isEmpty)
    }

    /// Los puntos del elemento se leen del JSON crudo, y los campos aditivos
    /// que no están se leen como AUSENTES, no como cero: `t` negativo es "sin
    /// dato" y 0 sería "el primer milisegundo".
    func testElementoSinCamposAditivos() {
        let e = Elemento(.objeto([
            "id": .texto("ink-1"), "type": .texto("ink"),
            "x": .numero(10), "y": .numero(20), "size": .numero(4),
            "points": .lista([
                .objeto(["x": .numero(0), "y": .numero(0), "pressure": .numero(0.2)]),
                .objeto(["x": .numero(30), "y": .numero(5), "pressure": .numero(0.5)]),
            ]),
        ]))
        let pts = e.trazoTinta
        XCTAssertEqual(pts.count, 2)
        XCTAssertEqual(pts[0].ix, 0)
        XCTAssertLessThan(pts[0].t, 0, "sin tiempo guardado, `t` tiene que ser negativo")
        XCTAssertNotNil(Tinta.camino(pts, Tinta.Opciones(grosor: e.grosorTinta)))
    }

    /// Y los que SÍ están se leen. Es el contrato del formato aditivo.
    func testElementoConCamposAditivos() {
        let e = Elemento(.objeto([
            "id": .texto("ink-2"), "type": .texto("ink"), "size": .numero(6),
            "points": .lista([
                .objeto(["x": .numero(0), "y": .numero(0), "pressure": .numero(0.3),
                         "tiltX": .numero(0.5), "tiltY": .numero(-0.2), "t": .numero(0)]),
                .objeto(["x": .numero(40), "y": .numero(10), "pressure": .numero(0.4),
                         "tiltX": .numero(0.5), "tiltY": .numero(-0.2), "t": .numero(120)]),
            ]),
        ]))
        let pts = e.trazoTinta
        XCTAssertEqual(pts[1].ix, 0.5)
        XCTAssertEqual(pts[1].iy, -0.2)
        XCTAssertEqual(pts[1].t, 120)
    }

    // ── la respuesta de presión ─────────────────────────────────────────────

    /// Más presión, más ancho. Siempre. Una respuesta no monótona haría que
    /// apretar más adelgazara el trazo en algún tramo.
    func testLaRespuestaDePresionEsMonotona() {
        var previa = -1.0
        for i in 0...100 {
            let r = Tinta.respuesta(Double(i) / 100)
            XCTAssertGreaterThanOrEqual(r, previa, "la respuesta bajó en u=\(Double(i) / 100)")
            previa = r
        }
        XCTAssertEqual(Tinta.respuesta(0), 0, accuracy: 1e-12)
        XCTAssertEqual(Tinta.respuesta(1), 1, accuracy: 1e-12)
    }

    /// El contraste medido: el ancho a la presión más alta que da la Kamvas
    /// contra el de un roce. Es el número que separa "una línea gruesa" de
    /// "una letra", y no puede caerse sin que alguien se entere.
    func testElContrasteEsAlMenosCuatroVeces() {
        func ancho(_ p: Double) -> Double {
            Tinta.ANCHO_MIN + (Tinta.ANCHO_MAX - Tinta.ANCHO_MIN)
                * Tinta.respuesta(min(1, p / Tinta.TOPE_PRESION))
        }
        let contraste = ancho(0.62) / ancho(0.03)
        XCTAssertGreaterThan(contraste, 4.0, "contraste medido: \(contraste)")
    }

    // ── casos degenerados ───────────────────────────────────────────────────

    func testSinPuntosNoHayCamino() {
        XCTAssertNil(Tinta.camino([], Tinta.Opciones()))
    }

    /// Dos muestras en el mismo sitio son un TOQUE: tiene que quedar un punto
    /// visible, no la nada. Es `ink-mt55kmkv-24` de la tinta real.
    func testToqueDejaPunto() {
        let p = [PuntoTinta(x: 0.04, y: 0, p: 0.0001), PuntoTinta(x: 0, y: 0.09, p: 0.0002)]
        guard let c = Tinta.camino(p, Tinta.Opciones(grosor: 4)) else {
            return XCTFail("un toque no puede desaparecer")
        }
        let b = c.boundingBox
        XCTAssertGreaterThan(b.width, 1.5, "el punto salió invisible (\(b.width) unidades)")
        XCTAssertLessThan(b.width, 8, "el punto salió como un borrón")
    }

    func testPuntosRepetidosNoProducenNaN() {
        var p = [PuntoTinta](repeating: PuntoTinta(x: 50, y: 50, p: 0.4), count: 12)
        p.append(PuntoTinta(x: 90, y: 50, p: 0.5))
        p.append(contentsOf: [PuntoTinta](repeating: PuntoTinta(x: 90, y: 50, p: 0.5), count: 9))
        guard let c = Tinta.camino(p, Tinta.Opciones(grosor: 4)) else { return XCTFail("sin camino") }
        XCTAssertTrue(finito(c))
    }

    func testValoresNoFinitosNoRompen() {
        let p = [PuntoTinta(x: 0, y: 0, p: 0.3),
                 PuntoTinta(x: .nan, y: 10, p: 0.4),
                 PuntoTinta(x: 40, y: 20, p: .infinity),
                 PuntoTinta(x: 80, y: 10, p: 0.5)]
        guard let c = Tinta.camino(p, Tinta.Opciones(grosor: 4)) else { return XCTFail("sin camino") }
        XCTAssertTrue(finito(c), "un NaN de entrada se coló hasta el camino")
    }

    /// El contorno no puede salirse de la caja de los puntos más el ancho
    /// máximo. Es la red que caza un desbordamiento de la spline: un control
    /// mal calculado dispara el trazo a otro sitio y esto lo ve.
    func testElContornoNoSeSaleDeSuCaja() {
        let p = puntos(50, presion: { _ in 0.62 }, conTiempo: true)
        guard let c = Tinta.camino(p, Tinta.Opciones(grosor: 6)) else { return XCTFail("sin camino") }
        let d = Tinta.diametro(Tinta.Opciones(grosor: 6))
        let holgura = d * Tinta.ANCHO_MAX
        let mnx = p.map(\.x).min()! - holgura, mxx = p.map(\.x).max()! + holgura
        let mny = p.map(\.y).min()! - holgura, mxy = p.map(\.y).max()! + holgura
        let b = c.boundingBox
        XCTAssertGreaterThanOrEqual(b.minX, mnx)
        XCTAssertLessThanOrEqual(b.maxX, mxx)
        XCTAssertGreaterThanOrEqual(b.minY, mny)
        XCTAssertLessThanOrEqual(b.maxY, mxy)
    }

    // ── presión real contra plana ───────────────────────────────────────────

    func testPresionPlanaNoCuentaComoReal() {
        XCTAssertFalse(Tinta.presionReal(puntos(30, presion: { _ in 1.0 })))
        XCTAssertTrue(Tinta.presionReal(puntos(30, presion: { 0.1 + Double($0) * 0.02 })))
    }

    /// Con presión plana (ratón) el ancho lo pone la VELOCIDAD, así que un
    /// trazo rápido tiene que salir más fino que el mismo trazo lento. El motor
    /// viejo pintaba los dos idénticos.
    func testConRatonLaVelocidadAdelgaza() {
        func recta(_ msPorMuestra: Double) -> Double {
            let p = (0..<40).map { i in
                PuntoTinta(x: 20 + Double(i) * 12, y: 60, p: 1.0,
                           t: Double(i) * msPorMuestra)
            }
            return Tinta.camino(p, Tinta.Opciones(grosor: 5))!.boundingBox.height
        }
        let lento = recta(40), rapido = recta(4)
        XCTAssertGreaterThan(lento, rapido * 1.15,
                             "lento \(lento) vs rápido \(rapido): la velocidad no está adelgazando")
    }

    // ── la plumilla ─────────────────────────────────────────────────────────

    /**
     * LA INCLINACIÓN CAMBIA EL TRAZO, Y CAMBIA SEGÚN LA DIRECCIÓN.
     *
     * Una recta horizontal con la pluma recostada HACIA los lados sale fina;
     * la misma recta con la pluma recostada hacia ARRIBA sale ancha. Si las dos
     * salieran igual, la plumilla sería decorativa.
     */
    func testLaPlumillaRespondeAlAngulo() {
        func recta(_ ix: Double, _ iy: Double) -> Double {
            let p = (0..<30).map { i in
                PuntoTinta(x: 20 + Double(i) * 8, y: 60, p: 0.4, ix: ix, iy: iy, t: Double(i) * 8)
            }
            return Tinta.camino(p, Tinta.Opciones(grosor: 6))!.boundingBox.height
        }
        let siguiendo = recta(0.95, 0)     // recostada a lo largo del trazo
        let cruzando = recta(0, 0.95)      // recostada a través del trazo
        let recta0 = recta(0, 0)
        XCTAssertGreaterThan(cruzando, siguiendo * 1.3,
                             "cruzar \(cruzando) contra seguir \(siguiendo): la plumilla no gira")
        XCTAssertGreaterThan(cruzando, recta0)
        XCTAssertLessThan(siguiendo, recta0)
    }

    /// Sin inclinación el trazo es el de siempre: la plumilla no puede cobrar
    /// peaje a los 32 trazos que ya existen.
    func testSinInclinacionLaPlumillaEsRedonda() {
        let p = (0..<30).map { i in
            PuntoTinta(x: 20 + Double(i) * 8, y: 60, p: 0.4, t: Double(i) * 8)
        }
        let a = Tinta.camino(p, Tinta.Opciones(grosor: 6))!.boundingBox
        let b = Tinta.camino(p.map { var q = $0; q.ix = 0; q.iy = 0; return q },
                             Tinta.Opciones(grosor: 6))!.boundingBox
        XCTAssertEqual(a.height, b.height, accuracy: 1e-9)
    }

    // ── el marcador ─────────────────────────────────────────────────────────

    /// El marcador es casi de ancho constante: su gracia es la banda pareja.
    func testElMarcadorApenasVariaDeAncho() {
        let flojo = (0..<30).map { i in PuntoTinta(x: 20 + Double(i) * 8, y: 60, p: 0.05, t: Double(i) * 8) }
        let fuerte = flojo.map { var q = $0; q.p = 0.6; return q }
        let a = Tinta.camino(flojo, Tinta.Opciones(grosor: 18, marcador: true))!.boundingBox.height
        let b = Tinta.camino(fuerte, Tinta.Opciones(grosor: 18, marcador: true))!.boundingBox.height
        XCTAssertLessThan(b / a, 1.45, "el marcador varía demasiado: \(a) → \(b)")
    }

    // ── la caché ────────────────────────────────────────────────────────────

    /// La clave cambia cuando cambia lo que se dibuja, y NO cambia por mover el
    /// trazo: el camino se guarda en coordenadas locales.
    func testLaClaveDeCacheIgnoraLaPosicion() {
        var e = Elemento(.objeto([
            "id": .texto("ink-3"), "type": .texto("ink"), "size": .numero(4),
            "x": .numero(0), "y": .numero(0), "updatedAt": .numero(1000),
            "points": .lista([.objeto(["x": .numero(0), "y": .numero(0), "pressure": .numero(0.3)]),
                              .objeto(["x": .numero(20), "y": .numero(0), "pressure": .numero(0.4)])]),
        ]))
        let antes = e.claveTinta
        e.crudo = e.crudo.con(["x": .numero(500), "y": .numero(300)])
        XCTAssertEqual(antes, e.claveTinta, "mover no puede invalidar la geometría")
        e.crudo = e.crudo.con(["size": .numero(9)])
        XCTAssertNotEqual(antes, e.claveTinta, "cambiar el grosor SÍ tiene que invalidar")
    }

    func testLaCacheDevuelveElMismoObjeto() {
        let c = CacheTinta()
        var veces = 0
        let hacer: () -> CGPath? = {
            veces += 1
            return CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: nil)
        }
        _ = c.camino("k", hacer)
        _ = c.camino("k", hacer)
        XCTAssertEqual(veces, 1)
        c.vaciar()
        _ = c.camino("k", hacer)
        XCTAssertEqual(veces, 2)
    }

    // ── el banco ────────────────────────────────────────────────────────────

    /// El fixture del banco está en el repo y se lee. Sin esto, el A/B sería
    /// irrepetible en cuanto la fila de la base cambiara.
    func testElBancoTieneLaTintaReal() {
        let ruta = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("banco/trazos.json").path
        let casos = BancoTinta.leerFixture(ruta)
        XCTAssertGreaterThanOrEqual(casos.count, 10, "faltan casos en el banco")
        guard let completo = casos.first(where: { $0.nombre == "real-completo" }) else {
            return XCTFail("falta el caso con la tinta real de Daniel")
        }
        XCTAssertEqual(completo.trazos.count, 32)
        XCTAssertEqual(completo.trazos.reduce(0) { $0 + $1.puntos.count }, 555)
        for t in completo.trazos {
            XCTAssertNotNil(Tinta.camino(t.puntos, Tinta.Opciones(grosor: t.grosor, marcador: t.marcador)),
                            "un trazo real dejó de dibujarse")
        }
    }

    // ── rendimiento ─────────────────────────────────────────────────────────

    /**
     * EL PRESUPUESTO DE UN FOTOGRAMA.
     *
     * Mientras se dibuja, el trazo en curso se recalcula ENTERO en cada
     * fotograma (el guardado va por caché). A 120 Hz el fotograma dura 8.3 ms y
     * ahí dentro cabe todo lo demás. Un trazo de 600 muestras —cinco segundos
     * de pluma sin fusionar eventos— tiene que costar una fracción de eso.
     *
     * ⚠️ EL TOPE DEPENDE DE LA CONFIGURACIÓN, y no es una excusa: `swift test`
     * compila en DEBUG, donde Swift no inline nada y cada `CGPoint` que aquí se
     * pasa por valor cuesta una llamada. Medido en la misma máquina: 0.18 ms en
     * release contra 3.7 en debug, veinte veces. Un tope único mediría la
     * bandera del compilador, no el motor — que es exactamente la trampa contra
     * la que avisa el spec. Así que se comprueba el presupuesto REAL donde el
     * presupuesto existe (release, que es lo que empaqueta `package.sh`) y en
     * debug queda una red que sigue cazando una regresión de orden de magnitud.
     */
    func testUnTrazoLargoCabeEnUnFotograma() {
        let p = (0..<600).map { i -> PuntoTinta in
            let t = Double(i) / 599
            return PuntoTinta(x: 40 + 900 * t, y: 300 + 220 * sin(t * 9),
                              p: 0.15 + 0.4 * abs(sin(t * 5)), t: Double(i) * 4)
        }
        let opc = Tinta.Opciones(grosor: 4)
        _ = Tinta.camino(p, opc)                       // calentar
        let t0 = CFAbsoluteTimeGetCurrent()
        let vueltas = 20
        for _ in 0..<vueltas { _ = Tinta.camino(p, opc) }
        let ms = (CFAbsoluteTimeGetCurrent() - t0) / Double(vueltas) * 1000
        // Medido en esta máquina: 0.23 ms en release, 7.7 en debug — 34×. El
        // tope de release es el presupuesto REAL (es lo que empaqueta
        // `package.sh`); el de debug lleva holgura a propósito, porque un tope
        // apretado sobre un número que la carga de la máquina mueve un 50% da
        // un rojo intermitente, y una prueba que falla sola se deja de leer.
        #if DEBUG
        let tope = 20.0
        #else
        let tope = 1.0
        #endif
        print("TINTA_PERF trazo de 600 muestras: \(String(format: "%.3f", ms)) ms (tope \(tope))")
        XCTAssertLessThan(ms, tope, "la geometría de un trazo de 600 muestras costó \(ms) ms")
    }
}
