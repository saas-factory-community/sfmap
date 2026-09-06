import XCTest
import CoreGraphics
@testable import SFMap

/// Las reglas de la SUPERFICIE, medidas.
///
/// Cada una existe porque su ausencia produjo un fallo concreto en el lienzo
/// web: un texto que se descartaba al escribirlo, un deshacer que retrocedia un
/// escalon, una flecha que saltaba de lado al mover la caja. Portar el
/// comportamiento sin portar sus pruebas seria portar tambien la posibilidad de
/// volver a romperlo en silencio.
final class LienzoTests: XCTestCase {

    private func figura(_ w: Double = 200, _ h: Double = 120, extra: [String: Json] = [:]) -> Elemento {
        var o: [String: Json] = [
            "id": .texto(Crear.nuevoId("t")), "type": .texto("shape"), "shape": .texto("rect"),
            "role": .texto("drawn"),
            "x": .numero(0), "y": .numero(0), "width": .numero(w), "height": .numero(h),
            "rotation": .numero(0), "zIndex": .numero(1), "opacity": .numero(1),
            "locked": .bool(false), "version": .numero(1),
            "createdAt": .numero(0), "updatedAt": .numero(0),
            "text": .lista([]),
        ]
        for (k, v) in extra { o[k] = v }
        return Elemento(.objeto(o))
    }

    // ── TEXTO ───────────────────────────────────────────────────────────────

    /// El medidor mide el RENGLON, no la suma de sus glifos. Sin kerning,
    /// "LEVY" mide de mas y el corte parte donde no debe.
    func testMedirNoEsCero() {
        var e = EstiloTexto(); e.peso = 800; e.tamano = 60
        let w = Medidor.medir("LEVY", e)
        XCTAssertGreaterThan(w, 100, "mide con la fuente real, no con un heuristico")
        XCTAssertLessThan(w, 400)
        XCTAssertEqual(Medidor.medir("", e), 0, "la cadena vacia mide cero")
    }

    /// El corte respeta el ancho pedido y NO pierde palabras.
    func testCortarRespetaElAncho() {
        var e = EstiloTexto(); e.tamano = 20
        let m = cortar("El vibe coding sin infraestructura es un hobby caro", e, maxAncho: 180)
        XCTAssertGreaterThan(m.lineas.count, 1, "una frase larga en 180px no cabe en un renglon")
        for l in m.lineas { XCTAssertLessThanOrEqual(l.ancho, 181, "ningun renglon se pasa: \(l.texto)") }
        let rehecho = m.lineas.map(\.texto).joined(separator: " ").replacingOccurrences(of: "  ", with: " ")
        for palabra in ["vibe", "infraestructura", "hobby", "caro"] {
            XCTAssertTrue(rehecho.contains(palabra), "no se perdio '\(palabra)'")
        }
    }

    /// Los saltos escritos a mano se respetan.
    func testCortarRespetaLosSaltos() {
        let m = cortar("uno\ndos", EstiloTexto(), maxAncho: 500)
        XCTAssertEqual(m.lineas.map(\.texto), ["uno", "dos"])
    }

    /// Una palabra que no cabe se PARTE en vez de desbordar.
    func testCortarParteLaPalabraQueNoCabe() {
        var e = EstiloTexto(); e.tamano = 20
        let m = cortar("supercalifragilisticoespialidoso", e, maxAncho: 60)
        XCTAssertTrue(m.partioPalabra, "lo declara en vez de tragarselo")
        XCTAssertGreaterThan(m.lineas.count, 1)
    }

    /// `ajustar` REDUCE el tamaño hasta que cabe, y DICE si no cupo.
    /// El v3 recibia un `autoShrink` y no lo leia nunca.
    func testAjustarReduceYDeclaraElDesborde() {
        var e = EstiloTexto(); e.tamano = 40
        let cabe = ajustar("hola", e, maxAncho: 200, maxAlto: 100)
        XCTAssertEqual(cabe.tamano, 40, "si cabe, no encoge")
        XCTAssertFalse(cabe.desborda)

        let aprieta = ajustar("una frase bastante larga que no cabe", e, maxAncho: 90, maxAlto: 40)
        XCTAssertLessThan(aprieta.tamano, 40, "encoge para caber")
        let imposible = ajustar("una frase bastante larga que no cabe de ninguna manera", e,
                                maxAncho: 40, maxAlto: 12, minTamano: 11)
        XCTAssertTrue(imposible.desborda, "ni al minimo cupo, y se DICE")
    }

    // ── ESCRIBIR ────────────────────────────────────────────────────────────

    /// ⭐ EL BUG DEL 20 AGO: escribir en una figura VACIA descartaba el texto.
    func testEscribirEnFiguraVaciaGuarda() {
        var e = figura()
        e.escribir("Videos YT")
        XCTAssertEqual(e.textoLigado?.first?.texto, "Videos YT")
        XCTAssertFalse(e.textoLigado?.first?.lineas.isEmpty ?? true, "nace con sus lineas cortadas")
    }

    /// ⭐ Y EL OTRO LADO DEL MISMO BUG: corregir el titulo de una tarjeta
    /// compuesta borraba sus renglones, su pie y sus etiquetas.
    func testEscribirConservaLasDemasPartes() {
        let estilo = EstiloTexto().json
        var e = figura(240, 160, extra: ["text": .lista([
            .objeto(["kind": .texto("title"), "text": .texto("viejo"), "lines": .lista([.texto("viejo")]),
                     "x": .numero(16), "y": .numero(16), "width": .numero(200), "height": .numero(20), "style": estilo]),
            .objeto(["kind": .texto("item"), "text": .texto("renglon"), "lines": .lista([.texto("renglon")]),
                     "x": .numero(16), "y": .numero(40), "width": .numero(200), "height": .numero(18), "style": estilo]),
            .objeto(["kind": .texto("caption"), "text": .texto("el pie"), "lines": .lista([.texto("el pie")]),
                     "x": .numero(0), "y": .numero(170), "width": .numero(240), "height": .numero(18), "style": estilo]),
            .objeto(["kind": .texto("chip"), "text": .texto("etq"), "lines": .lista([.texto("etq")]),
                     "x": .numero(180), "y": .numero(130), "width": .numero(44), "height": .numero(18), "style": estilo]),
        ])])
        e.escribir("nuevo titulo")
        let partes = e.textoLigado ?? []
        XCTAssertEqual(partes.count, 4, "las cuatro partes siguen ahi")
        XCTAssertEqual(partes.first(where: { $0.kind == "title" })?.texto, "nuevo titulo")
        XCTAssertEqual(partes.first(where: { $0.kind == "caption" })?.texto, "el pie")
        XCTAssertEqual(partes.first(where: { $0.kind == "chip" })?.texto, "etq")
    }

    /// El pie se re-maqueta COLGANDO por debajo de la caja, no dentro.
    func testElPieCuelgaPorDebajo() {
        let estilo = EstiloTexto().json
        var e = figura(240, 160, extra: ["text": .lista([
            .objeto(["kind": .texto("title"), "text": .texto("t"), "lines": .lista([.texto("t")]),
                     "x": .numero(16), "y": .numero(16), "width": .numero(200), "height": .numero(20), "style": estilo]),
            .objeto(["kind": .texto("caption"), "text": .texto("descripcion"), "lines": .lista([.texto("descripcion")]),
                     "x": .numero(0), "y": .numero(0), "width": .numero(240), "height": .numero(18), "style": estilo]),
        ])])
        e.remaquetar()
        let pie = e.textoLigado?.first(where: { $0.kind == "caption" })
        XCTAssertNotNil(pie)
        XCTAssertGreaterThanOrEqual(pie!.y, e.alto, "el pie empieza por debajo del borde de la caja")
    }

    /// Escribir tambien FIJA lo compilado: es la mano tocandolo.
    func testEscribirFijaLoCompilado() {
        var e = figura(extra: ["origin": .objeto(["regionId": .texto("r")])])
        e.escribir("editado")
        XCTAssertTrue(e.fijado)
    }

    // ── TIPOGRAFIA ──────────────────────────────────────────────────────────

    /// ⭐ EL TAMAÑO ESCALA, NO APLANA. Un titulo de 24 y un pie de 12 tienen esa
    /// diferencia por diseño: igualarlos destruye la jerarquia.
    func testTipografiaEscalaProporcionalmente() {
        var titulo = EstiloTexto(); titulo.tamano = 24
        var pie = EstiloTexto(); pie.tamano = 12
        var e = figura(240, 200, extra: ["text": .lista([
            .objeto(["kind": .texto("title"), "text": .texto("T"), "lines": .lista([.texto("T")]),
                     "x": .numero(16), "y": .numero(16), "width": .numero(200), "height": .numero(26), "style": titulo.json]),
            .objeto(["kind": .texto("item"), "text": .texto("p"), "lines": .lista([.texto("p")]),
                     "x": .numero(16), "y": .numero(50), "width": .numero(200), "height": .numero(14), "style": pie.json]),
        ])])
        e.aplicarTipografia(Tipografia(tamano: 48))
        let tams = (e.textoLigado ?? []).map(\.estilo.tamano)
        XCTAssertEqual(tams.max()!, 48, accuracy: 0.5, "el mayor llega al pedido")
        XCTAssertEqual(tams.min()!, 24, accuracy: 0.5, "el otro escala con el mismo factor, no se aplana")
    }

    /// La alineacion de una FIGURA vive en el elemento, no en cada parte.
    func testAlineacionViveEnLaFigura() {
        var e = figura()
        e.escribir("hola")
        e.aplicarTipografia(Tipografia(alineacion: "right"))
        XCTAssertEqual(e.alineacion, "right")
    }

    // ── COLOR Y TRAZO ───────────────────────────────────────────────────────

    /// ⭐ Cambiar el relleno NO borra el contorno ya elegido: un override que
    /// reemplaza el objeto entero convierte cada ajuste en un reinicio.
    func testColorSeComponeCampoPorCampo() {
        var e = figura()
        e.ponerColor(["stroke": "#111111"])
        e.ponerColor(["fill": "#eeeeee"])
        XCTAssertEqual(e.contorno, "#111111", "el contorno sobrevive al relleno")
        XCTAssertEqual(e.relleno, "#eeeeee")
    }

    /// Devolverle un campo al ROL BORRA la llave; dejarla en nulo la reviviria
    /// en la proxima mezcla.
    func testDevolverAlRolBorraLaLlave() {
        var e = figura()
        e.ponerColor(["fill": "#eeeeee", "stroke": "#111111"])
        e.ponerColor(["fill": nil])
        XCTAssertNil(e.relleno, "el relleno vuelve al rol")
        XCTAssertEqual(e.contorno, "#111111", "y el contorno sigue firmado")
        e.ponerColor(["stroke": nil])
        XCTAssertNil(e.crudo["color"], "sin ningun campo, el objeto entero se va")
    }

    /// Lo mismo para el trazo: elegir puntos no borra el grosor.
    func testTrazoSeComponeCampoPorCampo() {
        var e = figura()
        e.ponerTrazo(grosor: 6)
        e.ponerTrazo(estilo: "dotted")
        XCTAssertEqual(e.grosorLinea, 6)
        XCTAssertEqual(e.estiloLinea, "dotted")
    }

    // ── MANIJAS ─────────────────────────────────────────────────────────────

    /// Cruzar el lado opuesto VOLTEA la caja; sin normalizar, el elemento
    /// desaparece con un tamaño negativo.
    func testRedimensionarNormaliza() {
        let r = Geo.redimensionar(CGRect(x: 0, y: 0, width: 100, height: 100), "w",
                                  CGPoint(x: 160, y: 0), proporcional: false)
        XCTAssertGreaterThan(r.width, 0, "nunca ancho negativo")
        XCTAssertEqual(r.minX, 100, accuracy: 1)
    }

    /// Con Shift manda el eje que MAS se movio, o el gesto se siente pegajoso.
    func testRedimensionarProporcional() {
        let r = Geo.redimensionar(CGRect(x: 0, y: 0, width: 200, height: 100), "se",
                                  CGPoint(x: 100, y: 5), proporcional: true)
        XCTAssertEqual(r.width / r.height, 2, accuracy: 0.01, "conserva la proporcion")
    }

    /// El giro se prueba ANTES que las manijas: vive fuera de la caja.
    func testElGiroGanaALaManijaNorte() {
        let r = CGRect(x: 0, y: 0, width: 40, height: 40)
        let g = Geo.centroGiro(r, zoom: 1)
        XCTAssertEqual(Geo.manijaEn(r, g, zoom: 1), Geo.GIRO)
        XCTAssertEqual(Geo.manijaEn(r, CGPoint(x: 40, y: 40), zoom: 1), "se")
    }

    /// El angulo se imanta a los rectos: el ojo no distingue 0.4° pero el
    /// archivo lo guarda para siempre.
    func testAnguloSeImantaALosRectos() {
        let casi = 3.0 * .pi / 180
        XCTAssertEqual(Geo.ajustarAngulo(casi, shift: false), 0, accuracy: 1e-9)
        let lejos = 30.0 * .pi / 180
        XCTAssertEqual(Geo.ajustarAngulo(lejos, shift: false), lejos, accuracy: 1e-9)
        XCTAssertEqual(Geo.enGrados(Geo.ajustarAngulo(20.0 * .pi / 180, shift: true)), 15,
                       "con shift, escalones de 15°")
    }

    // ── PUERTOS Y CONECTORES ────────────────────────────────────────────────

    /// Los puertos viven FUERA del borde, y su distancia es constante EN
    /// PANTALLA: dividida entre el zoom.
    func testPuertosFueraDelBordeYConstantesEnPantalla() {
        let e = figura(100, 100)
        let p1 = Geo.puertosDe(e, zoom: 1).first { $0.id == "e" }!.p
        XCTAssertEqual(p1.x, 100 + Geo.PUERTO_AIRE_PX, accuracy: 0.01)
        let p2 = Geo.puertosDe(e, zoom: 2).first { $0.id == "e" }!.p
        XCTAssertEqual(p2.x, 100 + Geo.PUERTO_AIRE_PX / 2, accuracy: 0.01,
                       "al doble de zoom, la mitad de mundo: el ojo ve lo mismo")
    }

    /// ⭐ EL ANCLAJE FIJO. Peticion de Daniel: la flecha conectada por la
    /// izquierda se QUEDA por la izquierda aunque muevas la caja.
    func testAnclajeFijoNoSeMueve() {
        let caja = Obstaculo(id: "a", caja: CGRect(x: 0, y: 0, width: 100, height: 100))
        let porLaIzquierda = Ruteo.anclaje(caja, hacia: CGPoint(x: 500, y: 50), holgura: 0, lado: "w")
        XCTAssertEqual(porLaIzquierda.x, 0, "el destino esta a la derecha y aun asi sale por la w")
        let libre = Ruteo.anclaje(caja, hacia: CGPoint(x: 500, y: 50), holgura: 0)
        XCTAssertEqual(libre.x, 100, "sin lado fijo, manda el dominante")
    }

    /// La boca de ABAJO sale por debajo del PIE, no del borde: si no, la flecha
    /// atraviesa la descripcion de la tarjeta.
    func testLaBocaSurEsquivaElPie() {
        let o = Obstaculo(id: "a", caja: CGRect(x: 0, y: 0, width: 100, height: 100), pieAlto: 30)
        XCTAssertEqual(Ruteo.bocaDelLado(o, "s", holgura: 0).y, 130)
    }

    /// El router esquiva un obstaculo en medio, y su ruta es ORTOGONAL.
    func testRuterEsquivaYSaleOrtogonal() {
        let a = Obstaculo(id: "a", caja: CGRect(x: 0, y: 0, width: 80, height: 60))
        let b = Obstaculo(id: "b", caja: CGRect(x: 400, y: 0, width: 80, height: 60))
        let medio = Obstaculo(id: "m", caja: CGRect(x: 180, y: -40, width: 80, height: 140))
        let ruta = Ruteo.ortogonal(a, b, [a, b, medio])
        XCTAssertNotNil(ruta, "hay corredor por arriba o por abajo")
        let pegada = Ruteo.pegarALosBordes(ruta!, a, b, ladoA: "e", ladoB: "w")
        for i in 0..<(pegada.count - 1) {
            let p = pegada[i], q = pegada[i + 1]
            XCTAssertTrue(abs(p.x - q.x) < 0.5 || abs(p.y - q.y) < 0.5,
                          "cada tramo es horizontal o vertical")
        }
        // Y NO atraviesa la caja de en medio.
        for i in 0..<(pegada.count - 1) {
            let r = CGRect(x: min(pegada[i].x, pegada[i+1].x), y: min(pegada[i].y, pegada[i+1].y),
                           width: abs(pegada[i+1].x - pegada[i].x), height: abs(pegada[i+1].y - pegada[i].y))
            XCTAssertFalse(r.insetBy(dx: 1, dy: 1).intersects(medio.caja), "ningun tramo cruza el obstaculo")
        }
    }


    /**
     * ⚠️ UNA FLECHA NO ENTRA EN NINGUNA CAJA. NUNCA. Ni en las que une.
     *
     * Daniel, con la captura delante: *"flechas nunca adentro de componentes"*.
     * El caso que lo produjo son dos cajas en DIAGONAL —el router salia por el
     * sur y el pegado de extremos re-anclaba al este, dos jueces para la misma
     * pregunta— y la unica forma de unir esos dos puntos era cruzar la caja.
     *
     * Se prueban las 16 combinaciones de lados fijados a mano ADEMAS del
     * automatico: un lado elegido por la mano es justo donde el router y el
     * pegado pueden discrepar.
     */
    func testLaFlechaJamasEntraEnUnaCaja() {
        let cajas = [CGRect(x: 0, y: 0, width: 300, height: 340),      // A, arriba a la izquierda
                     CGRect(x: 330, y: 500, width: 300, height: 360)]  // B, abajo a la derecha
        var casos: [(String?, String?)] = [(nil, nil)]
        for x in ["n", "e", "s", "w"] { for y in ["n", "e", "s", "w"] { casos.append((x, y)) } }

        for (lA, lB) in casos {
            var a = figura(cajas[0].width, cajas[0].height)
            a.crudo = a.crudo.con(["id": .texto("A"), "x": .numero(cajas[0].minX), "y": .numero(cajas[0].minY)])
            var b = figura(cajas[1].width, cajas[1].height)
            b.crudo = b.crudo.con(["id": .texto("B"), "x": .numero(cajas[1].minX), "y": .numero(cajas[1].minY)])
            var c = Crear.conector("A", "B")
            if let l = lA { c.crudo = c.crudo.con("fromPort", .texto(l)) }
            if let l = lB { c.crudo = c.crudo.con("toPort", .texto(l)) }
            let ruta = Conectores.rutear(c, [a, b, c]).ruta
            let etiqueta = "\(lA ?? "auto")→\(lB ?? "auto")"
            XCTAssertGreaterThanOrEqual(ruta.count, 2, "hay ruta · \(etiqueta)")

            for i in 0..<(ruta.count - 1) {
                let p = ruta[i], q = ruta[i + 1]
                XCTAssertTrue(abs(p.x - q.x) < 0.5 || abs(p.y - q.y) < 0.5,
                              "tramo ortogonal · \(etiqueta)")
                // El tramo, encogido 1 px por lado para no contar el roce con el
                // borde: nacer EN el borde es correcto, entrar no lo es.
                let tramo = CGRect(x: min(p.x, q.x), y: min(p.y, q.y),
                                   width: abs(q.x - p.x), height: abs(q.y - p.y))
                    .insetBy(dx: 1, dy: 1)
                for caja in cajas {
                    XCTAssertFalse(tramo.intersects(caja.insetBy(dx: 1, dy: 1)),
                                   "el tramo \(i) no entra en la caja · \(etiqueta)")
                }
            }
        }
    }

    /// El primer y el ultimo tramo SALEN por la perpendicular de su boca. Es lo
    /// que hace que una flecha se lea como que sale de algo y no como una linea
    /// que pasaba por ahi — y lo que garantiza que el primer giro caiga fuera.
    func testLaFlechaSalePerpendicularASuBoca() {
        var a = figura(300, 340); a.crudo = a.crudo.con("id", .texto("A"))
        var b = figura(300, 360)
        b.crudo = b.crudo.con(["id": .texto("B"), "x": .numero(330), "y": .numero(500)])
        var c = Crear.conector("A", "B")
        c.crudo = c.crudo.con(["fromPort": .texto("e"), "toPort": .texto("n")])
        let r = Conectores.rutear(c, [a, b, c]).ruta
        XCTAssertEqual(r[0].y, r[1].y, accuracy: 0.5, "boca este ⇒ sale horizontal")
        XCTAssertEqual(r[0].x, 300, accuracy: 0.5, "nace EN el borde este")
        XCTAssertGreaterThan(r[1].x, r[0].x, "y se aparta hacia afuera")
        XCTAssertEqual(r[r.count - 1].x, r[r.count - 2].x, accuracy: 0.5, "boca norte ⇒ entra vertical")
        XCTAssertEqual(r[r.count - 1].y, 500, accuracy: 0.5, "muere EN el borde norte")
    }

    /// El codo puesto a mano DETRAS de la boca no arrastra la linea al interior:
    /// primero se sale, luego se va a buscarlo.
    func testUnCodoDetrasDeLaBocaNoMeteLaLineaEnLaCaja() {
        var a = figura(300, 340); a.crudo = a.crudo.con("id", .texto("A"))
        var b = figura(300, 360)
        b.crudo = b.crudo.con(["id": .texto("B"), "x": .numero(330), "y": .numero(500)])
        var c = Crear.conector("A", "B")
        c.crudo = c.crudo.con(["fromPort": .texto("e"), "toPort": .texto("w"),
                               "waypoints": .lista([.objeto(["x": .numero(150), "y": .numero(430)])])])
        let r = Conectores.rutear(c, [a, b, c]).ruta
        for i in 0..<(r.count - 1) {
            let tramo = CGRect(x: min(r[i].x, r[i+1].x), y: min(r[i].y, r[i+1].y),
                               width: abs(r[i+1].x - r[i].x), height: abs(r[i+1].y - r[i].y)).insetBy(dx: 1, dy: 1)
            XCTAssertFalse(tramo.intersects(CGRect(x: 0, y: 0, width: 300, height: 340).insetBy(dx: 1, dy: 1)),
                           "el codo de atras no mete la linea en su propia caja")
        }
    }


    /// GIRAR DESDE LAS ESQUINAS: la zona vive FUERA, nunca le roba el gesto ni
    /// a la manija de redimensionar ni al arrastre de la figura.
    func testElGiroDeEsquinaViveFuera() {
        let r = CGRect(x: 0, y: 0, width: 200, height: 120)
        XCTAssertEqual(Geo.giroEnEsquina(r, CGPoint(x: -12, y: -12), zoom: 1), "nw")
        XCTAssertEqual(Geo.giroEnEsquina(r, CGPoint(x: 212, y: 132), zoom: 1), "se")
        XCTAssertNil(Geo.giroEnEsquina(r, CGPoint(x: 0, y: 0), zoom: 1), "la manija gana en la esquina")
        XCTAssertNil(Geo.giroEnEsquina(r, CGPoint(x: 100, y: 60), zoom: 1), "dentro manda el arrastre")
        XCTAssertNil(Geo.giroEnEsquina(r, CGPoint(x: -40, y: -40), zoom: 1), "lejos, nada")
        // Y por el camino real: `manijaEn` la reporta como GIRO.
        XCTAssertEqual(Geo.manijaEn(r, CGPoint(x: -12, y: -12), zoom: 1), Geo.GIRO)
        XCTAssertEqual(Geo.manijaEn(r, CGPoint(x: 0, y: 0), zoom: 1), "nw")
    }

    /// El lado de SALIDA de una flecha es el del punto donde empezaste el
    /// trazo: empezar pegado al borde derecho ES decir "sale por la derecha".
    func testElLadoSaleDeDondePusisteElDedo() {
        let o = Obstaculo(id: "a", caja: CGRect(x: 0, y: 0, width: 200, height: 120))
        XCTAssertEqual(Ruteo.ladoIntencional(o, CGPoint(x: 195, y: 60)), "e")
        XCTAssertEqual(Ruteo.ladoIntencional(o, CGPoint(x: 5, y: 60)), "w")
        XCTAssertEqual(Ruteo.ladoIntencional(o, CGPoint(x: 100, y: 5)), "n")
        XCTAssertEqual(Ruteo.ladoIntencional(o, CGPoint(x: 100, y: 115)), "s")
        // ⚠️ Y en el CENTRO no hay intencion: decide el ruteo, no el desempate.
        XCTAssertNil(Ruteo.ladoIntencional(o, CGPoint(x: 100, y: 60)))
        XCTAssertNil(Ruteo.ladoIntencional(o, CGPoint(x: 120, y: 70)))
    }

    /// LA FLECHA ES EL DEFAULT, siempre. La herramienta NO se recuerda entre
    /// sesiones: abrir la app con el lápiz puesto de anoche hace que el primer
    /// clic dibuje cuando lo que querías era mirar.
    func testElLienzoNaceEnElSelector() {
        XCTAssertEqual(Lienzo(frame: NSRect(x: 0, y: 0, width: 800, height: 600)).herramienta,
                       .seleccionar)
    }

    /// Mover una caja RE-RUTEA sus flechas: un conector guarda a QUIEN une,
    /// jamas por donde pasa.
    func testMoverReruteaSusFlechas() {
        var a = figura(80, 60); a.crudo = a.crudo.con("id", .texto("A"))
        var b = figura(80, 60); b.crudo = b.crudo.con(["id": .texto("B"), "x": .numero(400)])
        let c = Crear.conector("A", "B")
        let doc = Documento()
        doc.cargar([a, b, Conectores.rutear(c, [a, b, c])])
        let antes = doc.porId(c.id)!.ruta
        XCTAssertFalse(antes.isEmpty)
        doc.mover(["A"], dx: 0, dy: 300)
        let despues = doc.porId(c.id)!.ruta
        XCTAssertNotEqual(antes.first!.y, despues.first!.y, "la flecha siguio a su caja")
    }

    /// Borrar un extremo se lleva la flecha: un conector a un destino que ya no
    /// existe es invisible pero clickeable — el fallo exacto del v3.
    func testBorrarSeLlevaLosConectoresHuerfanos() {
        var a = figura(); a.crudo = a.crudo.con("id", .texto("A"))
        var b = figura(); b.crudo = b.crudo.con("id", .texto("B"))
        let doc = Documento()
        doc.cargar([a, b, Crear.conector("A", "B")])
        doc.seleccion = ["A"]
        doc.borrarSeleccion()
        XCTAssertEqual(doc.elementos.count, 1, "se fueron la figura y su flecha")
        XCTAssertEqual(doc.elementos.first?.id, "B")
    }

    // ── HISTORIAL ───────────────────────────────────────────────────────────

    /// ⭐ UN GESTO = UNA ENTRADA. Arrastrar el grosor de 1.5 a 6 dejaba DIEZ
    /// entradas y un deshacer retrocedia un escalon.
    func testUnGestoEsUnaEntradaDelHistorial() {
        var e = figura()
        let doc = Documento()
        doc.cargar([e])
        doc.abrirGesto()
        for g in stride(from: 1.0, through: 6.0, by: 0.5) {
            doc.editar("grosor") { els in els[0].ponerTrazo(grosor: g) }
        }
        doc.cerrarGesto("grosor")
        XCTAssertEqual(doc.elementos[0].grosorLinea, 6)
        doc.deshacer()
        XCTAssertNil(doc.elementos[0].grosorLinea, "un solo deshacer devuelve al estado inicial")
        _ = e
    }

    /// Deshacer y rehacer devuelven exactamente lo que habia.
    func testDeshacerYRehacer() {
        let doc = Documento()
        doc.cargar([figura()])
        doc.editar("mover") { $0[0].mover(dx: 50, dy: 0) }
        XCTAssertEqual(doc.elementos[0].x, 50)
        doc.deshacer(); XCTAssertEqual(doc.elementos[0].x, 0)
        doc.rehacer(); XCTAssertEqual(doc.elementos[0].x, 50)
    }

    /// Una accion nueva invalida el futuro: rehacer despues de editar daria un
    /// estado que nunca existio.
    func testEditarInvalidaElRehacer() {
        let doc = Documento()
        doc.cargar([figura()])
        doc.editar("a") { $0[0].mover(dx: 10, dy: 0) }
        doc.deshacer()
        doc.editar("b") { $0[0].mover(dx: 0, dy: 10) }
        XCTAssertFalse(doc.historial.puedeRehacer)
    }

    // ── DOCUMENTO ───────────────────────────────────────────────────────────

    /// EL CANDADO MANDA sobre mover y borrar.
    func testElCandadoDetieneMoverYBorrar() {
        var e = figura(extra: ["locked": .bool(true), "id": .texto("L")])
        let doc = Documento()
        doc.cargar([e])
        doc.mover(["L"], dx: 100, dy: 100)
        XCTAssertEqual(doc.porId("L")?.x, 0, "no se movio")
        doc.seleccion = ["L"]
        doc.borrarSeleccion()
        XCTAssertEqual(doc.elementos.count, 1, "no se borro")
        _ = e
    }

    /// Duplicar re-apunta los conectores INTERNOS a las copias; sin eso la
    /// copia sale desconectada y hay que rehacer a mano lo que ya estaba hecho.
    func testDuplicarReapuntaLosConectores() {
        var a = figura(); a.crudo = a.crudo.con("id", .texto("A"))
        var b = figura(); b.crudo = b.crudo.con(["id": .texto("B"), "x": .numero(400)])
        let doc = Documento()
        doc.cargar([a, b, Crear.conector("A", "B")])
        let nuevos = doc.duplicar(["A", "B", doc.elementos[2].id])
        XCTAssertEqual(nuevos.count, 3)
        let copiaConn = doc.elementos.first { $0.tipo == "connector" && nuevos.contains($0.id) }!
        XCTAssertNotEqual(copiaConn.desdeId, "A", "apunta a la COPIA, no al original")
        XCTAssertTrue(nuevos.contains(copiaConn.desdeId ?? ""))
    }

    /// Agrupar hace que tocar uno seleccione a todos.
    func testGrupoExpandeLaSeleccion() {
        var a = figura(); a.crudo = a.crudo.con("id", .texto("A"))
        var b = figura(); b.crudo = b.crudo.con("id", .texto("B"))
        let doc = Documento()
        doc.cargar([a, b])
        doc.seleccion = ["A", "B"]
        doc.agrupar()
        XCTAssertEqual(doc.expandirSeleccion(["A"]), ["A", "B"])
        doc.desagrupar()
        XCTAssertEqual(doc.expandirSeleccion(["A"]), ["A"])
    }

    /// ACOMODAR coloca siguiendo las flechas y RESPETA los candados, diciendo
    /// cuantos quedaron fuera: un acomodo que respeta un candado se ve igual
    /// que uno roto si no lo dice.
    func testAcomodarSigueLasFlechasYRespetaCandados() {
        var a = figura(120, 60); a.crudo = a.crudo.con(["id": .texto("A"), "x": .numero(500), "y": .numero(500)])
        var b = figura(120, 60); b.crudo = b.crudo.con(["id": .texto("B"), "x": .numero(0), "y": .numero(0)])
        var c = figura(120, 60); c.crudo = c.crudo.con(["id": .texto("C"), "x": .numero(200), "y": .numero(900)])
        let doc = Documento()
        doc.cargar([a, b, c, Crear.conector("A", "B"), Crear.conector("B", "C")])
        doc.seleccion = ["A", "B", "C"]
        let r = doc.acomodar()
        XCTAssertGreaterThan(r.movidos, 0)
        XCTAssertEqual(r.bloqueados, 0)
        // A antes que B antes que C en el eje del flujo.
        let xa = doc.porId("A")!.x, xb = doc.porId("B")!.x, xc = doc.porId("C")!.x
        XCTAssertLessThan(xa, xb, "A va antes que B")
        XCTAssertLessThan(xb, xc, "y B antes que C")

        var d = figura(120, 60)
        d.crudo = d.crudo.con(["id": .texto("D"), "locked": .bool(true), "x": .numero(9000)])
        doc.cargar([doc.porId("A")!, doc.porId("B")!, d])
        doc.seleccion = ["A", "B", "D"]
        let r2 = doc.acomodar()
        XCTAssertEqual(r2.bloqueados, 1, "lo declara en vez de moverlo en silencio")
        XCTAssertEqual(doc.porId("D")!.x, 9000, "y no lo movio")
    }

    /// Acomodar NO teletransporta el grupo al origen del mundo.
    func testAcomodarConservaElCentroDeMasa() {
        var a = figura(100, 60); a.crudo = a.crudo.con(["id": .texto("A"), "x": .numero(1000), "y": .numero(1000)])
        var b = figura(100, 60); b.crudo = b.crudo.con(["id": .texto("B"), "x": .numero(1200), "y": .numero(1000)])
        let doc = Documento()
        doc.cargar([a, b, Crear.conector("A", "B")])
        doc.seleccion = ["A", "B"]
        doc.acomodar()
        let centro = doc.porId("A")!.caja.union(doc.porId("B")!.caja)
        XCTAssertEqual(Double(centro.midX), 1150, accuracy: 120, "sigue estando donde estaba")
        XCTAssertEqual(Double(centro.midY), 1030, accuracy: 120)
    }

    // ── FABRICAS ────────────────────────────────────────────────────────────

    /// Lo que nace de la mano NO lleva `origin`: el compilador ni lo mira.
    func testLoQueNaceDeLaManoEsLibre() {
        XCTAssertFalse(Crear.nota(CGPoint(x: 0, y: 0), z: 1).compilado)
        XCTAssertFalse(Crear.figura("rect", CGRect(x: 0, y: 0, width: 10, height: 10), z: 1).compilado)
    }

    /// ⭐ El ancho del ARRASTRE es la instruccion: un bloque de texto dibujado
    /// de 690px no puede nacer de 125 y partir la frase en dos palabras.
    func testElTextoRespetaLaColumnaArrastrada() {
        let e = Crear.texto(CGPoint(x: 0, y: 0), texto: "una frase larga de varias palabras seguidas",
                            z: 1, maxAncho: 690)
        XCTAssertEqual(e.ancho, 690, accuracy: 1)
    }

    /// La caja fantasma se IMANTA a la fila del origen: una cadena hecha a
    /// pulso sale recta sin que nadie la acomode despues.
    func testElFantasmaSeImanta() {
        let origen = CGRect(x: 0, y: 0, width: 100, height: 100)
        let casi = Crear.cajaFantasma(origen, CGPoint(x: 400, y: 58))
        XCTAssertEqual(casi.midY, 50, accuracy: 0.01, "58 esta dentro del iman de 28: queda alineado")
        let lejos = Crear.cajaFantasma(origen, CGPoint(x: 400, y: 300))
        XCTAssertEqual(lejos.midY, 300, accuracy: 0.01, "fuera del iman, manda el dedo")
    }

    /// Un clic (sin arrastrar) pone la figura a un salto EXACTO en su direccion.
    func testCajaEnDireccion() {
        let origen = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(Crear.cajaEnDireccion(origen, "e").minX, 100 + Crear.SALTO)
        XCTAssertEqual(Crear.cajaEnDireccion(origen, "n").maxY, -Crear.SALTO)
        XCTAssertEqual(Crear.cajaEnDireccion(origen, nil).minX, 100 + Crear.SALTO, "sin puerto, a la derecha")
    }

    /// La seccion nace al FONDO: pintada encima taparia su propio contenido.
    func testLaSeccionNaceAlFondo() {
        XCTAssertLessThan(Crear.seccion(CGRect(x: 0, y: 0, width: 300, height: 200)).z, 0)
    }

    /// La tabla MIDE sus columnas en vez de repartirlas en partes iguales.
    func testLaTablaMideSusColumnas() {
        let t = Crear.tabla(CGPoint(x: 0, y: 0),
                            celdas: [["Sí", "una descripción bastante más larga"], ["No", "otra"]], z: 1)
        let anchos = t.crudo["colWidths"]?.arr?.compactMap(\.num) ?? []
        XCTAssertEqual(anchos.count, 2)
        XCTAssertLessThan(anchos[0], anchos[1], "la columna de Sí/No es mas angosta que la de texto")
    }

    // ── IMANTADO ────────────────────────────────────────────────────────────

    /// La guia y el iman van JUNTOS: imantar sin mostrar la guia se siente
    /// embrujado, y mostrarla sin imantar es decorativo.
    func testImantarDevuelveDeltaYGuia() {
        var otro = figura(100, 100); otro.crudo = otro.crudo.con(["id": .texto("O"), "x": .numero(300)])
        let r = Geo.imantar(CGRect(x: 297, y: 400, width: 100, height: 100), [otro], zoom: 1, ignorar: [])
        XCTAssertEqual(r.dx, 3, accuracy: 0.01, "corrige los 3px que faltaban")
        XCTAssertFalse(r.guias.isEmpty, "y lo dice con una guia")
    }

    /// Lo que se esta moviendo NO se imanta consigo mismo.
    func testImantarIgnoraLoPropio() {
        var otro = figura(100, 100); otro.crudo = otro.crudo.con(["id": .texto("O"), "x": .numero(300)])
        let r = Geo.imantar(CGRect(x: 297, y: 400, width: 100, height: 100), [otro], zoom: 1, ignorar: ["O"])
        XCTAssertEqual(r.dx, 0)
    }

    // ── GEOMETRIA DE FIGURAS ────────────────────────────────────────────────

    /// Una estrella se agarra por su CONTORNO REAL, no por su caja: si no, se
    /// puede agarrar por el aire entre las puntas.
    func testLaEstrellaTieneHuecos() {
        let r = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertTrue(Geo.dentro("star", r, CGPoint(x: 50, y: 50)), "el centro es solido")
        XCTAssertFalse(Geo.dentro("star", r, CGPoint(x: 3, y: 3)), "la esquina es aire")
        XCTAssertTrue(Geo.dentro("rect", r, CGPoint(x: 3, y: 3)), "en un rectangulo la esquina SI es figura")
    }

    /// El hit-test deshace el GIRO. El v3 tenia el giro en el pintor y no aqui:
    /// una figura girada se veia en un sitio y se agarraba en otro.
    func testElHitTestDeshaceElGiro() {
        var e = figura(200, 40)
        e.crudo = e.crudo.con("rotation", .numero(.pi / 2))
        // Girada 90°, la barra ocupa una franja VERTICAL sobre su centro.
        let centro = CGPoint(x: 100, y: 20)
        let arriba = CGPoint(x: centro.x, y: centro.y - 80)
        XCTAssertNotNil(Geo.elegir([e], arriba, zoom: 1), "cae dentro del rectangulo girado")
        let derecha = CGPoint(x: centro.x + 80, y: centro.y)
        XCTAssertNil(Geo.elegir([e], derecha, zoom: 1), "y fuera por el lado corto")
    }

    /// Gana el de mas arriba en z, que es el que el ojo ve encima.
    func testElHitTestRespetaElZ() {
        var abajo = figura(100, 100); abajo.crudo = abajo.crudo.con(["id": .texto("abajo"), "zIndex": .numero(1)])
        var arriba = figura(100, 100); arriba.crudo = arriba.crudo.con(["id": .texto("arriba"), "zIndex": .numero(9)])
        XCTAssertEqual(Geo.elegir([abajo, arriba], CGPoint(x: 50, y: 50), zoom: 1)?.id, "arriba")
    }

    /// Lo BLOQUEADO se puede SELECCIONAR: sin panel de capas, un elemento que
    /// no se puede seleccionar no se puede desbloquear NUNCA.
    func testLoBloqueadoSeSeleccionaAunqueNoSeMueva() {
        let e = figura(extra: ["locked": .bool(true)])
        XCTAssertNotNil(Geo.elegir([e], CGPoint(x: 50, y: 50), zoom: 1))
    }
}

/// El tema es un ESPEJO de `theme/tokens.ts`, y esta prueba es el sensor.
///
/// ⚠️ Existe porque el espejo se rompió en silencio: la primera versión se
/// escribió de memoria y divergía en el fondo del lienzo, la retícula, los tres
/// colores de texto y el rol `callout` entero. Los dos lienzos pintaban el mismo
/// documento con colores distintos, y la única forma de verlo era poner las dos
/// ventanas lado a lado.
///
/// Si el referente no está (otra máquina, otro clon), la prueba lo DICE y no
/// falla: una prueba que revienta por un archivo ausente se acaba borrando.
final class TemaEspejoTests: XCTestCase {

    private var tokens: String? {
        let p = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Developer/business-os/arbrain/src/features/canvas/theme/tokens.ts")
        return try? String(contentsOf: p, encoding: .utf8)
    }

    private func hex(_ c: NSColor) -> String {
        let s = c.usingColorSpace(.sRGB)!
        return String(format: "#%02x%02x%02x", Int((s.redComponent * 255).rounded()),
                      Int((s.greenComponent * 255).rounded()), Int((s.blueComponent * 255).rounded()))
    }

    func testElTemaSigueSiendoElEspejoDeTokens() throws {
        guard let src = tokens else {
            print("⚠︎ sin tokens.ts a la vista: no se puede comprobar el espejo")
            return
        }
        func bloque(_ n: String) -> String {
            let i = src.range(of: "export const \(n): Theme = {")!.lowerBound
            let j = src.range(of: "\n}\n", range: i..<src.endIndex)!.lowerBound
            return String(src[i..<j])
        }
        func valor(_ t: String, _ k: String) -> String? {
            guard let r = t.range(of: "\(k): '") else { return nil }
            let resto = t[r.upperBound...]
            return String(resto[resto.startIndex..<resto.firstIndex(of: "'")!])
        }
        for (nombre, tema) in [("CLARO", Tema.claro), ("OSCURO", Tema.oscuro)] {
            let t = bloque(nombre)
            XCTAssertEqual(hex(tema.lienzo), valor(t, "canvas"), "\(nombre): el fondo del lienzo")
            XCTAssertEqual(hex(tema.reticula), valor(t, "grid"), "\(nombre): la retícula")
            XCTAssertEqual(hex(tema.acento).lowercased(), valor(t, "accent")?.lowercased(), "\(nombre): el acento")
            XCTAssertEqual(hex(tema.tituloTexto), valor(t, "title"), "\(nombre): el título")
            XCTAssertEqual(hex(tema.cuerpoTexto), valor(t, "body"), "\(nombre): el cuerpo")
            XCTAssertEqual(hex(tema.pieTexto), valor(t, "caption"), "\(nombre): el pie")
            XCTAssertEqual(hex(tema.tinta), valor(t, "lapiz"), "\(nombre): la tinta")
            // Y un rol de cada familia, con su relleno y su patrón de línea.
            XCTAssertEqual(tema.rol("callout").trazo.estilo, "solid")
            // Estándar firmado 24 ago 2026: muere la píldora, muere el dotted,
            // muere el dashed de cajas. El agente es morado SÓLIDO con pastel;
            // el dashed vive solo en las ARISTAS (agente/frágil, mismo patrón).
            XCTAssertEqual(tema.rol("agent").trazo.estilo, "solid", "\(nombre): el agente es morado sólido")
            XCTAssertEqual(tema.rol("module").trazo.estilo, "solid", "\(nombre): el dashed de cajas murió")
            XCTAssertEqual(tema.rol("trigger").radio, 12, "\(nombre): la píldora murió")
            XCTAssertEqual(tema.aristas["agente"]?.estilo, "dashed", "\(nombre): arista de agente es dashed")
            XCTAssertEqual(tema.aristas["agente"]?.grosor, tema.aristas["fragil"]?.grosor, "\(nombre): mismo grosor, el color avisa")
            XCTAssertTrue(tema.rol("deliverable").sombra, "\(nombre): el entregable lleva sombra")
        }
    }

    /// Estándar 24 ago 2026: las FAMILIAS que la leyenda promete distinguir se
    /// separan por DOS canales; y card/module/trigger comparten firma A PROPÓSITO
    /// (los tres son "proceso" — la píldora y el dashed de cajas murieron).
    func testCadaRolSeSeparaPorDosCanales() {
        func firma(_ tema: Tema, _ r: String) -> String {
            let e = tema.rol(r)
            return "\(hex(e.relleno))|\(hex(e.trazo.color))|\(e.trazo.estilo)|\(e.trazo.grosor)|\(e.radio)|\(e.sombra)"
        }
        for tema in [Tema.claro, Tema.oscuro] {
            let familias = ["card", "form", "callout", "deliverable", "risk", "agent"].map { firma(tema, $0) }
            XCTAssertEqual(Set(familias).count, familias.count,
                           "\(tema.nombre): dos familias con la misma firma visual son un rol que miente")
            XCTAssertEqual(firma(tema, "module"), firma(tema, "card"),
                           "\(tema.nombre): módulo ES proceso — si divergen, alguien resucitó el dashed")
            XCTAssertEqual(firma(tema, "trigger"), firma(tema, "card"),
                           "\(tema.nombre): disparador ES proceso — si divergen, alguien resucitó la píldora")
        }
    }
}

/// El botón de solo icono NO lleva texto. Nunca.
///
/// ⚠️ `NSButton` nace con el título "Button" puesto y lo esconde con
/// `imagePosition`. Cualquier cosa que vuelva a escribir el título lo resucita
/// encimado sobre el glifo — pasó el 20 ago 2026 en las ocho celdas del rail a
/// la vez, y una captura del rail entero fue la única forma de verlo.
final class BotonTests: XCTestCase {
    func testElBotonDeIconoNoLlevaTexto() {
        let b = BotonPlano(icono: Icono.cursor)
        b.tema = .claro
        XCTAssertEqual(b.title, "", "nace sin el 'Button' de fábrica")
        b.activo = true          // dispara el repintado, que es lo que lo resucitaba
        b.enfasis = .solido
        b.tema = .oscuro
        XCTAssertEqual(b.title, "", "y sigue sin él después de repintar")
        XCTAssertEqual(b.attributedTitle.string, "")
    }

    /// Y el que SÍ lleva texto lo conserva al repintar.
    func testElBotonConTextoLoConserva() {
        let b = BotonPlano(icono: nil, titulo: "Neutro", ancho: 100)
        b.tema = .claro
        b.activo = true
        XCTAssertEqual(b.attributedTitle.string, "Neutro")
    }
}

/// Un CODO en ruta ortogonal produce ángulos rectos, no diagonales.
///
/// El referente devolvía la polilínea cruda y una diagonal en una ruta "de
/// codos" se lee como que el conector se rompió. sfmap es el primer productor
/// de `waypoints` en las dos superficies: el campo existía en el modelo, el
/// router lo respetaba, y nada lo escribía nunca.
final class CodosTests: XCTestCase {

    /// ¿La ruta PASA por este punto? El codo no tiene por qué ser un vértice —
    /// puede quedar en medio de un tramo recto tras colapsar los colineales, y
    /// exigir que sea vértice sería exigir un detalle de implementación en vez
    /// del comportamiento: lo que la mano pidió es que la línea pase por ahí.
    private func pasaPor(_ ruta: [CGPoint], _ p: CGPoint) -> Bool {
        for i in 0..<max(0, ruta.count - 1) {
            let a = ruta[i], b = ruta[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let l2 = dx * dx + dy * dy
            if l2 == 0 { continue }
            let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
            if hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy)) < 0.6 { return true }
        }
        return false
    }

    func testElCodoSaleEnAngulosRectos() {
        let ruta = Conectores.enAngulosRectos([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 80), CGPoint(x: 220, y: 10)])
        for i in 0..<(ruta.count - 1) {
            let a = ruta[i], b = ruta[i + 1]
            XCTAssertTrue(abs(a.x - b.x) < 0.5 || abs(a.y - b.y) < 0.5,
                          "el tramo \(i) sale en diagonal: \(a) → \(b)")
        }
        XCTAssertTrue(pasaPor(ruta, CGPoint(x: 100, y: 80)),
                      "y la ruta pasa por el punto que la mano pidió")
    }

    /// Lo que ya era ortogonal no gana esquinas de más.
    func testLoQueYaEsRectoNoSeToca() {
        let recto = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 90)]
        XCTAssertEqual(Conectores.enAngulosRectos(recto).count, recto.count)
    }

    /// ⭐ Y NO SE DOBLA SOBRE SÍ MISMA. Con dos bocas horizontales y un codo
    /// debajo, la ruta tiene que dar una U — no bajar y volver a subir por la
    /// misma vertical, que es ortogonal y aun así se lee como un error.
    func testElCodoNoSeDoblaSobreSiMismo() {
        let ruta = Conectores.enAngulosRectos(
            [CGPoint(x: 0, y: 0), CGPoint(x: 500, y: 200), CGPoint(x: 1000, y: 0)], ejeInicial: "h")
        // Ningún par de tramos verticales comparte la misma X: eso es el doblez.
        var verticales: [Double] = []
        for i in 0..<(ruta.count - 1) where abs(ruta[i].x - ruta[i+1].x) < 0.5 {
            verticales.append(ruta[i].x)
        }
        XCTAssertEqual(Set(verticales).count, verticales.count,
                       "dos tramos verticales en la misma X = la ruta se dobla sobre sí misma")
        XCTAssertTrue(pasaPor(ruta, CGPoint(x: 500, y: 200)), "y sigue pasando por el codo")
    }
}

/// El lienzo se invalida ENTERO al cambiar de tamaño.
///
/// ⚠️ Con `layerContentsRedrawPolicy = .onSetNeedsDisplay`, AppKit solo marca
/// sucia la franja que CRECIÓ. En un lienzo cuya cámara se centra en
/// `bounds.width/2` eso deja un rectángulo con el encuadre anterior congelado —
/// medido: 655×148 arriba a la izquierda, sin retícula y con otro color, que no
/// se iba nunca. No falla nada: hay una zona que enseña un fotograma viejo.
final class RepintadoTests: XCTestCase {
    /// Va DENTRO de una ventana: fuera de una, `needsDisplay` no se sostiene —
    /// AppKit no tiene a quién avisar y lo descarta. Una prueba sobre una vista
    /// suelta mediría el descarte, no la invalidación.
    private func enVentana(_ ancho: CGFloat, _ alto: CGFloat) -> Lienzo {
        let v = NSWindow(contentRect: NSRect(x: 0, y: 0, width: ancho, height: alto),
                         styleMask: [.titled], backing: .buffered, defer: false)
        let l = Lienzo(frame: NSRect(x: 0, y: 0, width: ancho, height: alto))
        v.contentView = l
        return l
    }

    func testCambiarDeTamanoInvalidaTodoElLienzo() {
        let l = enVentana(400, 300)
        l.displayIfNeeded()
        l.setFrameSize(NSSize(width: 800, height: 600))
        // Se pregunta al LAYER, no a la vista: con `.onSetNeedsDisplay` la
        // invalidación viaja al layer y el flag de la vista puede volver a
        // false en la misma vuelta. Preguntarle a la vista mediría el flag, no
        // el repintado.
        XCTAssertTrue(l.layer?.needsDisplay() ?? false, "crecer tiene que ensuciar el layer entero")
        XCTAssertTrue(l.layer?.needsDisplayOnBoundsChange ?? false,
                      "y el layer tiene que invalidarse con sus propios límites")
    }

    /// El mismo tamaño NO pide repintado: invalidar en cada layout gastaría un
    /// frame entero por nada, que es lo contrario de por qué esto es nativo.
    func testElMismoTamanoNoPideNada() {
        let l = enVentana(400, 300)
        l.displayIfNeeded()
        l.setFrameSize(NSSize(width: 400, height: 300))
        XCTAssertFalse(l.layer?.needsDisplay() ?? true)
    }
}
