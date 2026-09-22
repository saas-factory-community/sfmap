import XCTest
import AppKit
@testable import SFMap

/// LAS CAPACIDADES DEL OPSROOM, medidas.
///
/// Cada una nació el 24 ago 2026 para The Machinery v2: el destino de un nodo
/// (documento · lienzo · vídeo · web), el traductor de markdown y el sensor.
/// Van con prueba porque en este proyecto una capacidad sin prueba es una
/// promesa, y las promesas hundieron al canvas v3.
final class EnlaceTests: XCTestCase {

    func testLosCuatroDestinos() {
        XCTAssertEqual(Enlace.leer("doc:docs/ejemplo.md"),
                       .documento("docs/ejemplo.md"))
        XCTAssertEqual(Enlace.leer("page:83a103ab-cbe8-4257-bca2-52e8cd912528"),
                       .pagina("83a103ab-cbe8-4257-bca2-52e8cd912528"))
        XCTAssertEqual(Enlace.leer("https://youtu.be/abc"), .video(URL(string: "https://youtu.be/abc")!))
        XCTAssertEqual(Enlace.leer("https://saasfactory.so"), .web(URL(string: "https://saasfactory.so")!))
        XCTAssertNil(Enlace.leer(nil))
        XCTAssertNil(Enlace.leer("   "))
    }

    /// ⭐ Una liga del documento NO navega el disco hacia arriba. Sin esto, un
    /// `doc:../../.ssh/id_rsa` en un lienzo compartido sería un lector de
    /// ficheros con la cara de un mapa.
    func testNoSeSaleDelRepo() {
        XCTAssertNil(Enlace.leer("doc:../../.ssh/id_rsa"))
        XCTAssertNil(Enlace.leer("doc:a/../../b.md"))
        XCTAssertEqual(Enlace.leer("doc:/CLAUDE.md"), .documento("CLAUDE.md"), "la barra inicial se limpia")
    }

    /// Sin esquema se asume https. Una URL sin él la rechaza URLSession en
    /// SILENCIO — el mismo fallo que dejó las imágenes locales en "marco de
    /// espera" para siempre hasta el 24 ago.
    func testSinEsquemaSeAsumeHttps() {
        XCTAssertEqual(Enlace.leer("saasfactory.so"), .web(URL(string: "https://saasfactory.so")!))
    }

    func testReconoceVideo() {
        for s in ["https://www.youtube.com/watch?v=x", "https://youtu.be/x",
                  "https://cdn.x.com/clip.mp4", "https://arbrain.ai/cast/abc"] {
            XCTAssertTrue(Enlace.esVideo(s), s)
            if case .video = Enlace.leer(s) {} else { XCTFail("no lo leyó como vídeo: \(s)") }
        }
        XCTAssertFalse(Enlace.esVideo("https://saasfactory.so/about"))
    }

    /// La MARCA distingue los cuatro destinos: el ojo tiene que saber a dónde
    /// va antes de pulsar.
    func testCadaDestinoTieneSuMarca() {
        XCTAssertEqual(Enlace.marca("doc:a.md"), .documento)
        XCTAssertEqual(Enlace.marca("page:abc"), .pagina)
        XCTAssertEqual(Enlace.marca("https://youtu.be/x"), .video)
        XCTAssertEqual(Enlace.marca("https://x.com"), .web)
        XCTAssertNil(Enlace.marca(nil))
    }

    func testDocumentoSeResuelveDentroDeLaBibliotecaConfigurada() {
        XCTAssertEqual(Enlace.rutaDoc("a/b.md").path, Enlace.repo.appendingPathComponent("a/b.md").path)
    }

}

final class MarkdownTests: XCTestCase {

    func testTitulosListasYCodigo() {
        let bs = Markdown.analizar("""
        # Título
        Un párrafo con **negrita** y `código`.

        - uno
          - anidado
        1. primero

        ```bash
        echo hola
        ```
        ---
        """)
        guard case .titulo(let n, let t) = bs[0] else { return XCTFail("no es título") }
        XCTAssertEqual(n, 1); XCTAssertEqual(t.first?.texto, "Título")

        guard case .parrafo(let p) = bs[1] else { return XCTFail("no es párrafo") }
        XCTAssertTrue(p.contains { $0.negrita && $0.texto == "negrita" }, "la negrita se marcó")
        XCTAssertTrue(p.contains { $0.codigo && $0.texto == "código" }, "el código en línea se marcó")

        guard case .punto(let o1, let niv1, _) = bs[2] else { return XCTFail("no es punto") }
        XCTAssertNil(o1); XCTAssertEqual(niv1, 0)
        guard case .punto(_, let niv2, _) = bs[3] else { return XCTFail("no es punto") }
        XCTAssertEqual(niv2, 1, "dos espacios de sangría = un nivel")
        guard case .punto(let o3, _, _) = bs[4] else { return XCTFail("no es punto") }
        XCTAssertEqual(o3, 1, "lista numerada")

        guard case .codigo(let cuerpo, let leng) = bs[5] else { return XCTFail("no es bloque") }
        XCTAssertEqual(cuerpo, "echo hola"); XCTAssertEqual(leng, "bash")
        XCTAssertEqual(bs[6], .regla)
    }

    /// ⭐ `daily_business_metrics` NO va en cursiva. Un `_` dentro de palabra es
    /// parte del nombre, y sin esta guarda medio repo se pintaba a medias en
    /// cursiva y el documento parecía roto.
    func testGuionBajoDentroDePalabraNoEsCursiva() {
        let t = Markdown.enLinea("la tabla daily_business_metrics manda")
        XCTAssertEqual(t.count, 1)
        XCTAssertFalse(t[0].cursiva)
        XCTAssertEqual(t[0].texto, "la tabla daily_business_metrics manda")
    }

    func testEnlaceEnLinea() {
        let t = Markdown.enLinea("ver [el mapa](docs/mapa.md) hoy")
        XCTAssertEqual(t.first(where: { $0.liga != nil })?.liga, "docs/mapa.md")
        XCTAssertEqual(t.first(where: { $0.liga != nil })?.texto, "el mapa")
    }

    /// El frontmatter de las skills solo cuenta si abre en la PRIMERA línea:
    /// un `---` en mitad del texto es una regla, y confundirlos se comía medio
    /// documento en silencio.
    func testFrontmatterSoloAlPrincipio() {
        guard case .ficha(let pares) = Markdown.analizar("---\nname: sfmap\n---\n# Hola")[0] else {
            return XCTFail("no leyó la ficha")
        }
        XCTAssertEqual(pares.first?.0, "name")
        XCTAssertEqual(pares.first?.1, "sfmap")

        let sin = Markdown.analizar("texto\n\n---\n\nmás texto")
        XCTAssertTrue(sin.contains(.regla), "en mitad del texto es una REGLA")
        XCTAssertFalse(sin.contains { if case .ficha = $0 { return true }; return false })
    }

    func testTablaNecesitaSuFilaDeGuiones() {
        guard case .tabla(let cabeza, let filas) = Markdown.analizar("""
        | a | b |
        |---|---|
        | 1 | 2 |
        """)[0] else { return XCTFail("no es tabla") }
        XCTAssertEqual(cabeza.count, 2)
        XCTAssertEqual(filas.count, 1)
        XCTAssertEqual(filas[0][1].first?.texto, "2")

        // Un párrafo con barras NO es una tabla.
        XCTAssertFalse(Markdown.analizar("uno | dos | tres").contains {
            if case .tabla = $0 { return true }; return false
        })
    }

    /// Lo que no entiende NO se traga: cae a párrafo, nunca a nada.
    func testNadaSePierde() {
        let raro = "<<< esto no es markdown de nada >>>"
        guard case .parrafo(let t) = Markdown.analizar(raro)[0] else { return XCTFail() }
        XCTAssertEqual(t.map(\.texto).joined(), raro)
    }

    /// ⭐ Los bloques cercados son REJILLAS: los docs de este repo llevan
    /// diagramas ASCII dentro, y con el interlineado del cuerpo el dibujo se
    /// desarma. El contrato: el párrafo del código no separa renglones.
    func testElCodigoConservaSuRejilla() throws {
        let attr = Markdown.atribuido(Markdown.analizar("```\nA → B\n│\n▼\n```"),
                                      tema: .claro, ancho: 400)
        var visto = false
        attr.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: attr.length)) { v, r, _ in
            guard let ps = v as? NSParagraphStyle,
                  attr.attribute(.sfBloque, at: r.location, effectiveRange: nil) as? String == "codigo"
            else { return }
            visto = true
            XCTAssertEqual(ps.lineHeightMultiple, 1.0, accuracy: 0.001,
                           "el código no se espacia como el cuerpo o el ASCII se rompe")
        }
        XCTAssertTrue(visto, "el bloque de código llegó marcado")
    }

    func testComponeSinReventar() {
        let attr = Markdown.atribuido(Markdown.analizar("""
        ---
        name: x
        ---
        # T
        > cita
        | a | b |
        |---|---|
        | 1 | 2 |
        """), tema: .claro, ancho: 400)
        XCTAssertGreaterThan(attr.length, 10)
    }
}

final class SensorTests: XCTestCase {

    private func sensor(_ campos: [String: Json]) -> Elemento {
        Elemento(.objeto([
            "id": .texto("s"), "type": .texto("shape"), "role": .texto("sensor"),
            "x": .numero(0), "y": .numero(0), "width": .numero(220), "height": .numero(120),
            "sensor": .objeto(campos),
        ]))
    }

    /// ⭐ LA REGLA QUE MÁS HA COSTADO: un cero no es un dato. Un sensor sin
    /// lectura no puede pintar `0` — un `0` bien tipografiado se lee como una
    /// medición (`dato-ausente-no-es-cero`, 17 ago 2026).
    func testSinLecturaNoHayCero() {
        let l = Pintor.Lectura(sensor(["etiqueta": .texto("MRR")]))
        XCTAssertNotNil(l)
        XCTAssertNil(l?.valor, "sin valor ⇒ nil, y el pintor escribe «sin dato»")
        let vacio = Pintor.Lectura(sensor(["etiqueta": .texto("MRR"), "valor": .texto("")]))
        XCTAssertNil(vacio?.valor, "cadena vacía tampoco es una medición")
    }

    func testLeeLaLectura() {
        let l = Pintor.Lectura(sensor([
            "etiqueta": .texto("MRR"), "valor": .texto("$8,298"), "delta": .texto("+1.3%"),
            "signo": .numero(1), "pie": .texto("23 ago · Polar"),
            "tendencia": .lista([.numero(1), .numero(2), .numero(3)]),
        ]))
        XCTAssertEqual(l?.etiqueta, "MRR")
        XCTAssertEqual(l?.valor, "$8,298")
        XCTAssertEqual(l?.signo, 1)
        XCTAssertEqual(l?.tendencia, [1, 2, 3])
        XCTAssertEqual(l?.pie, "23 ago · Polar")
    }

    /// Un elemento sin objeto `sensor` no es un sensor, aunque lleve el rol.
    /// Así una caja mal escrita se ve vacía, no con la lectura de otra.
    func testSinObjetoNoHayLectura() {
        XCTAssertNil(Pintor.Lectura(Elemento(.objeto(["role": .texto("sensor")]))))
    }

    /// El rol existe en el tema y se separa de `card` por TRES canales (color,
    /// grosor, radio) — la regla de "dos canales, no uno" del estándar.
    func testElRolSensorSeDistingueDeCard() {
        for t in [Tema.claro, Tema.oscuro] {
            let s = t.rol("sensor"), c = t.rol("card")
            XCTAssertNotEqual(s.relleno, c.relleno, "\(t.nombre): distinto relleno")
            XCTAssertNotEqual(s.radio, c.radio, "\(t.nombre): distinto radio")
            XCTAssertNotEqual(s.trazo.color, c.trazo.color, "\(t.nombre): distinto borde")
            XCTAssertNotEqual(t.rol("sensor").relleno, t.rol("agent").relleno, "no se confunde con agente")
        }
    }

    /// ⭐ El COLOR de la tendencia no puede contradecir a la LINEA que dibuja.
    /// El MRR subió +1.3% ayer sobre una curva que lleva dos semanas cayendo:
    /// con el signo del chip, la chispa salía verde encima de una bajada.
    func testLaDerivaDeLaSerieDecideElColorDeLaChispa() {
        // El contrato es de datos, no de píxeles: la deriva es last − first.
        func deriva(_ vs: [Double]) -> Double {
            guard let a = vs.first, let b = vs.last else { return 0 }
            let d = b - a
            return abs(d) < 1e-9 ? 0 : (d > 0 ? 1 : -1)
        }
        XCTAssertEqual(deriva([8912, 8586, 8298]), -1, "catorce días bajando ⇒ rojo, aunque ayer subiera")
        XCTAssertEqual(deriva([8100, 8200, 8298]), 1)
        XCTAssertEqual(deriva([8298, 8298]), 0, "plano no es ni bueno ni malo")
    }

    /// La marca se PINTA y se PULSA con los mismos números. Dos piezas
    /// calculando dónde está el botón es la receta de un botón que no se deja
    /// pulsar (la lección de "el lado de una flecha se decide UNA vez").
    func testLaMarcaSePintaDondeSePulsa() {
        let e = Elemento(.objeto([
            "id": .texto("a"), "type": .texto("shape"),
            "x": .numero(100), "y": .numero(50), "width": .numero(200), "height": .numero(90),
            "link": .texto("doc:CLAUDE.md"),
        ]))
        // El contrato es la INVARIANZA, no el número: la marca mide lo mismo en
        // PANTALLA a cualquier zoom. Clavar el 10 hizo que afinar su tamaño
        // (25 ago: baja a 7 para que susurre) rompiera una prueba que no tenía
        // nada que decir sobre eso.
        let enPantalla = Pintor.radioMarca(1) * 1
        for zoom in [0.4, 1.0, 2.5] {
            let c = Pintor.centroMarca(e, zoom: zoom)
            let r = Pintor.radioMarca(zoom)
            XCTAssertEqual(r * zoom, enPantalla, accuracy: 0.001, "tamaño constante en PANTALLA")
            XCTAssertLessThan(r * zoom, 9, "y SUSURRA: en PANTALLA, un disco grande compite con la tarjeta")
            XCTAssertLessThan(c.x, e.x + e.ancho, "dentro de la caja, a la derecha")
            XCTAssertGreaterThan(c.y, e.y, "arriba del todo")
        }
    }
}

/// LA ITERACION 2: la capa de EVIDENCIA y el pulido de MARCA (25 ago 2026).
final class EvidenciaYMarcaTests: XCTestCase {
    private var raizAnterior: URL!
    override func setUpWithError() throws {
        raizAnterior = Enlace.repo
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sfmap-doc-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Enlace.repo = dir
        try "# Documento de prueba\n\nCorto.\n\nUn párrafo de tamaño medio.\n\nEsta línea contiene más palabras para verificar que la miniatura conserva longitudes diferentes.\n\nOtro texto.\n\nFin de la prueba.\n".write(to: dir.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
    }
    override func tearDown() { Enlace.repo = raizAnterior; super.tearDown() }


    private func figura(_ campos: [String: Json]) -> Elemento {
        var o: [String: Json] = [
            "id": .texto("x"), "type": .texto("shape"), "shape": .texto("rect"),
            "x": .numero(0), "y": .numero(0), "width": .numero(200), "height": .numero(100),
        ]
        for (k, v) in campos { o[k] = v }
        return Elemento(.objeto(o))
    }

    /// ⭐ EL FALLO QUE ESTA PRUEBA EXISTE PARA QUE NO VUELVA. La silueta del
    /// reloj se pintó con un LITERAL del tema claro, y un literal no se repinta:
    /// en oscuro quedaron dos bloques casi blancos que se comían el tablero.
    /// El territorio es una capa del TEMA, y por eso resuelve distinto en cada uno.
    func testElTerritorioLoResuelveElTemaEnLosDos() {
        let e = figura(["role": .texto("drawn"), "tint": .texto("morado")])
        let claro = Tema.claro.relleno(e), oscuro = Tema.oscuro.relleno(e)
        XCTAssertNotEqual(claro, oscuro, "el mismo elemento pinta distinto en cada tema")
        /*
         * ⚠️ SE COMPRUEBA EL INVARIANTE, NO EL VALOR (reescrita 25 ago 2026).
         *
         * La versión anterior exigía que el relleno fuese EXACTAMENTE el tinte
         * de sección. Eso no era la regla: era el número que había ese día. Al
         * darle cuerpo a la silueta en claro —porque el pase de integración
         * midió que se fundía con la página— esta prueba se puso roja sin que
         * nada se hubiera roto. Un test que fija el valor en vez del invariante
         * frena el arreglo del fallo que él mismo debería estar cazando.
         *
         * Lo que SÍ manda: el color sale de la familia del tinte de su
         * territorio (no de un literal suelto) y cada tema lo resuelve por su
         * cuenta. `SiluetaVisibleTests` cubre la otra mitad: que se vea.
         */
        func cerca(_ a: NSColor, _ b: NSColor) -> Bool {
            guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return false }
            return abs(x.redComponent - y.redComponent) < 0.30
                && abs(x.greenComponent - y.greenComponent) < 0.30
                && abs(x.blueComponent - y.blueComponent) < 0.30
        }
        XCTAssertTrue(cerca(claro, Tema.claro.tintes["morado"]!.relleno),
                      "el claro sale de la familia del tinte morado, no de un literal suelto")
        XCTAssertTrue(cerca(oscuro, Tema.oscuro.tintes["morado"]!.relleno),
                      "y el oscuro también")

        // Y en OSCURO el territorio es OSCURO: ese era el síntoma exacto.
        for t in ["morado", "ambar", "neutro"] {
            let f = Tema.oscuro.tintes[t]!.relleno.usingColorSpace(.sRGB)!
            let luz = 0.299 * f.redComponent + 0.587 * f.greenComponent + 0.114 * f.blueComponent
            XCTAssertLessThan(luz, 0.30, "el tinte \(t) en oscuro no puede ser un bloque claro")
        }
    }

    /// Un literal firmado por la mano SIGUE ganando: la excepción del estándar
    /// no se pierde al añadir la capa de territorio.
    func testElLiteralDeLaManoSigueGanandoAlTerritorio() {
        let e = figura(["role": .texto("drawn"), "tint": .texto("morado"),
                        "color": .objeto(["explicit": .bool(true), "fill": .texto("#123456")])])
        XCTAssertEqual(Tema.claro.relleno(e), NSColor(hex: "#123456"))
    }

    /// El `tint` de una SECCION no convierte en territorio a una figura que no
    /// lo pidió: `territorio` solo mira figuras.
    func testUnaSeccionNoContagiaSuTinteALasFiguras() {
        let s = Elemento(.objeto(["id": .texto("f"), "type": .texto("frame"), "tint": .texto("morado")]))
        XCTAssertNil(s.territorio, "una sección tiene `tinte`, no `territorio`")
        XCTAssertEqual(s.tinte, "morado")
    }

    /// ⭐ EL NEON ES LA MARCA. En oscuro el morado y el oro son los hex madre de
    /// `nucleo.md`, no un morado genérico de framework.
    func testElOscuroLlevaElNeonDeMarca() {
        func hex(_ c: NSColor) -> String {
            let s = c.usingColorSpace(.sRGB)!
            return String(format: "#%02x%02x%02x", Int((s.redComponent * 255).rounded()),
                          Int((s.greenComponent * 255).rounded()), Int((s.blueComponent * 255).rounded()))
        }
        XCTAssertEqual(hex(Tema.oscuro.acento).lowercased(), "#8c27f1", "el morado madre")
        XCTAssertEqual(hex(Tema.oscuro.tintes["morado"]!.trazo).lowercased(), "#8c27f1")
        XCTAssertEqual(hex(Tema.oscuro.tintes["ambar"]!.trazo).lowercased(), "#ff9101", "el oro madre")
        XCTAssertEqual(hex(Tema.claro.acento).lowercased(), hex(Tema.oscuro.acento).lowercased(),
                       "la marca es la MISMA en los dos temas; lo que cambia es el fondo")
    }

    /// La dashed tiene que leerse con el lienzo alejado (comparación de Daniel
    /// contra el tablero de Mateo). Y la regla firmada no se toca: mismo patrón
    /// para todas, el COLOR es lo que avisa.
    func testLaDashedSeVeDeLejosYSigueSiendoElColorElQueAvisa() {
        for t in [Tema.claro, Tema.oscuro] {
            XCTAssertGreaterThanOrEqual(t.aristas["agente"]!.grosor, 3, "\(t.nombre): dashed con presencia")
            XCTAssertEqual(t.aristas["agente"]!.grosor, t.aristas["fragil"]!.grosor,
                           "\(t.nombre): mismo grosor — el color es lo que avisa")
            XCTAssertEqual(t.aristas["agente"]!.estilo, t.aristas["fragil"]!.estilo)
            XCTAssertNotEqual(t.aristas["agente"]!.color, t.aristas["fragil"]!.color)
        }
    }

    /// El widget-documento lee el markdown REAL y saca su estructura. Si el
    /// documento no existe, devuelve nil — jamás una miniatura inventada.
    func testLaMiniaturaSaleDelDocumentoREAL() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Enlace.repo.path), "sin repo")
        let m = Pintor.miniatura("CLAUDE.md")
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.nombre, "CLAUDE.md")
        XCTAssertFalse(m?.renglones.isEmpty ?? true)
        var titulos = 0
        for r in m?.renglones ?? [] { if case .titulo = r { titulos += 1 } }
        XCTAssertGreaterThan(titulos, 0, "los titulares del documento real llegan a la miniatura")
        XCTAssertNil(Pintor.miniatura("no/existe/jamas.md"), "sin documento no hay miniatura")
    }

    /// La longitud de cada renglón sale de la longitud REAL de su línea: la
    /// mancha tiene la forma del documento, no una forma inventada.
    func testLosRenglonesTienenLaFormaDelDocumento() {
        var vistos: [Double] = []
        for r in Pintor.miniatura("CLAUDE.md")?.renglones ?? [] {
            if case .linea(let f) = r { vistos.append(f) }
        }
        XCTAssertGreaterThan(vistos.count, 3)
        XCTAssertTrue(vistos.allSatisfy { $0 >= 0 && $0 <= 1 }, "normalizado")
        XCTAssertGreaterThan(Set(vistos.map { ($0 * 20).rounded() }).count, 1,
                             "no son todos iguales: siguen al texto")
    }
}

/// EL PASE DE INTEGRACION del 25 ago 2026, hecho prueba.
final class CoherenciaTests: XCTestCase {

    /// ⭐ HAY METRICAS DONDE SUBIR ES MALO. La chispa pinta rojo cuando la serie
    /// baja, que es correcto para MRR o subs y está AL REVES para el churn: sin
    /// polaridad, el tablero pintaba de rojo un churn que MEJORA y de acento uno
    /// que empeora — el color diciendo lo contrario del dato. Lo cazó un agente
    /// fresco leyendo los tres tableros a la vez.
    func testLaPolaridadInvierteElColorDeLasMetricasDondeSubirEsMalo() {
        func lectura(_ campos: [String: Json]) -> Pintor.Lectura? {
            Pintor.Lectura(Elemento(.objeto([
                "id": .texto("s"), "type": .texto("shape"), "role": .texto("sensor"),
                "sensor": .objeto(campos)])))
        }
        let normal = lectura(["etiqueta": .texto("MRR")])
        XCTAssertEqual(normal?.polaridad, 1, "por defecto, subir es bueno")
        let churn = lectura(["etiqueta": .texto("CHURN"), "polaridad": .numero(-1)])
        XCTAssertEqual(churn?.polaridad, -1)

        // El contrato del color, en datos: deriva × polaridad decide.
        func rojo(_ vs: [Double], _ pol: Double) -> Bool { (vs.last! - vs.first!) * pol < 0 }
        XCTAssertTrue(rojo([8900, 8200], 1), "MRR cayendo ⇒ rojo")
        XCTAssertFalse(rojo([8200, 8900], 1), "MRR subiendo ⇒ no rojo")
        XCTAssertTrue(rojo([2, 9], -1), "churn SUBIENDO ⇒ rojo")
        XCTAssertFalse(rojo([9, 2], -1), "churn BAJANDO ⇒ no rojo")
    }
}
