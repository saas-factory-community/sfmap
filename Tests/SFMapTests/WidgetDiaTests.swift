import XCTest
import AppKit
@testable import SFMap

/// EL CENTRO DE MANDO — lo que un widget vivo tiene prohibido hacer.
///
/// Estas pruebas no comprueban que se vea bonito (eso se mira). Comprueban las
/// promesas que se rompen EN SILENCIO: que un cero no se cuele como medición,
/// que el conmutador se pueda pulsar donde se pinta, que nada de esto escriba.
final class WidgetDiaTests: XCTestCase {

    func testDestinosExactosDeCalendario() {
        XCTAssertEqual(VistaCalendario.mes.vistaSFCal,"month")
        XCTAssertEqual(VistaCalendario.semana.vistaSFCal,"week")
        XCTAssertEqual(VistaCalendario.cuatro.vistaSFCal,"fourDay")
        XCTAssertEqual(VistaCalendario.dia.vistaSFCal,"day")
    }

    func testCalendarioUsaFechaTodoistSinInventarHora() throws {
        let dia = try XCTUnwrap(GDate.dayOnly.date(from: "2026-09-12"))
        let t = TareaDia(id:"cal-test",contenido:"Clase",prioridad:1,dia:"2026-09-12",hora:nil,frente:nil,frenteId:nil)
        let otra = TareaDia(id:"otra",contenido:"Otra",prioridad:2,dia:"2026-09-13",hora:nil,frente:nil,frenteId:nil)
        let lista = Pintor.tareasCalendario([otra,t],dia:dia)
        XCTAssertEqual(lista.map(\.id),["cal-test"])
        XCTAssertNil(lista.first?.hora)
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: 1. Un cero no es un dato
    // ════════════════════════════════════════════════════════════════════════

    /// La frescura de una fuente que nunca contestó NO es "hace 0 minutos".
    func testSinLecturaNoEsUnaLecturaDeCero() {
        XCTAssertNil(Cronista.sello(nil), "sin lectura no hay hora que enseñar")
        XCTAssertFalse(Cronista.fresca(nil, vara: 300),
                       "una fuente que nunca contestó no puede declararse fresca")
        XCTAssertTrue(Cronista.fresca(Date(), vara: 300))
        XCTAssertFalse(Cronista.fresca(Date().addingTimeInterval(-600), vara: 300),
                       "diez minutos con vara de cinco es atraso, no frescura")
    }

    /// El estado vacío se distingue del estado leído-y-vacío. Es la diferencia
    /// entre "no sé qué tienes hoy" y "hoy no tienes nada".
    func testEstadoVacioNoAfirmaNada() {
        let e = EstadoDia()
        XCTAssertNil(e.eventos.valor, "sin lectura, `valor` es nil — jamás []")
        XCTAssertNil(e.tareas.valor)
        XCTAssertNil(e.habitos.valor)
        var leido = EstadoDia()
        leido.tareas = Lectura(valor: [], alDia: Date(), fallo: nil)
        XCTAssertNotNil(leido.tareas.valor, "una lista vacía LEÍDA sí es un dato")
    }

    /// La huella cambia con el CONTENIDO y no con la hora de lectura: si el
    /// panel se repintara en cada vuelta del reloj, el arrastre pagaría un
    /// fotograma extra cada minuto para no enseñar nada nuevo.
    func testLaHuellaIgnoraLaHoraDeLectura() {
        let t = [TareaDia(id: "t1", contenido: "grabar", prioridad: 1, dia: "2026-08-25", hora: nil, frente: "YouTube", frenteId: "p1")]
        var a = EstadoDia(); a.tareas = Lectura(valor: t, alDia: Date(), fallo: nil)
        var b = EstadoDia(); b.tareas = Lectura(valor: t, alDia: Date().addingTimeInterval(600), fallo: nil)
        XCTAssertEqual(a.huella, b.huella, "misma verdad leída dos veces = un solo repintado")
        var c = EstadoDia()
        c.tareas = Lectura(valor: t + [TareaDia(id: "t2", contenido: "otra", prioridad: 4, dia: nil, hora: nil, frente: nil, frenteId: nil)],
                           alDia: Date(), fallo: nil)
        XCTAssertNotEqual(a.huella, c.huella, "una tarea nueva SÍ tiene que repintar")
    }

    /// Un fallo cambia la huella: el widget tiene que repintarse para poder
    /// DECIR que se quedó sin dato.
    func testUnFalloTambienRepinta() {
        var a = EstadoDia(); a.eventos = Lectura(valor: [], alDia: Date(), fallo: nil)
        var b = a; b.eventos.fallo = "HTTP 503"
        XCTAssertNotEqual(a.huella, b.huella)
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: 2. El conmutador se pulsa DONDE se pinta
    // ════════════════════════════════════════════════════════════════════════

    private func elementoWidget(_ tipo: String, x: Double = 100, y: Double = 100,
                                w: Double = 2760, h: Double = 1124) -> Elemento {
        Elemento(.objeto([
            "id": .texto("w:\(tipo)"), "type": .texto("shape"), "role": .texto("widget"),
            "shape": .texto("rect"),
            "x": .numero(x), "y": .numero(y), "width": .numero(w), "height": .numero(h),
            "widget": .objeto(["tipo": .texto(tipo)]),
        ]))
    }

    func testCadaChipDeVistaSeDejaPulsarEnSuCentro() {
        let e = elementoWidget("calendario")
        let chips = Pintor.chipsDeVista(e)
        XCTAssertEqual(chips.count, VistaCalendario.allCases.count,
                       "los cuatro modos del conmutador se pintan")
        for (v, caja) in chips {
            XCTAssertEqual(Pintor.vistaEn(e, CGPoint(x: caja.midX, y: caja.midY)), v,
                           "el chip \(v.rotulo) no responde en su propio centro")
            XCTAssertTrue(e.caja.contains(caja), "el chip \(v.rotulo) se sale del widget")
        }
    }

    /// Dos chips que se pisan es un botón que unas veces hace una cosa y otras
    /// otra: el fallo más caro de una barra de modos.
    func testLosChipsNoSePisan() {
        let chips = Pintor.chipsDeVista(elementoWidget("calendario"))
        for i in chips.indices {
            for j in chips.indices where j > i {
                XCTAssertFalse(chips[i].1.intersects(chips[j].1),
                               "\(chips[i].0.rotulo) pisa a \(chips[j].0.rotulo)")
            }
        }
    }

    /// El conmutador es del CALENDARIO. Un chip flotando sobre el monk mode
    /// sería una promesa de interacción que no lleva a ningún sitio.
    func testSoloElCalendarioLlevaConmutador() {
        XCTAssertTrue(Pintor.chipsDeVista(elementoWidget("monk")).isEmpty)
        XCTAssertTrue(Pintor.chipsDeVista(elementoWidget("tareas")).isEmpty)
        let centro = CGPoint(x: 1480, y: 662)
        XCTAssertNil(Pintor.vistaEn(elementoWidget("tareas"), centro))
    }

    /// El cuerpo del widget NO conmuta: pulsar en medio del calendario tiene
    /// que poder seguir seleccionando el elemento.
    func testElCuerpoDelWidgetNoConmuta() {
        let e = elementoWidget("calendario")
        XCTAssertNil(Pintor.vistaEn(e, CGPoint(x: e.caja.midX, y: e.caja.midY)))
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: 3. Las vistas dicen la verdad sobre el periodo
    // ════════════════════════════════════════════════════════════════════════

    func testCadaVistaEnseniaLosDiasQuePromete() {
        let hoy = DateKit.cal.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        XCTAssertEqual(VistaCalendario.dia.dias(hoy).count, 1)
        XCTAssertEqual(VistaCalendario.cuatro.dias(hoy).count, 4)
        XCTAssertEqual(VistaCalendario.semana.dias(hoy).count, 7)
        XCTAssertEqual(VistaCalendario.mes.dias(hoy).count, 42, "la rejilla del mes son 6 semanas")
        XCTAssertTrue(VistaCalendario.semana.dias(hoy).contains { DateKit.isSameDay($0, hoy) },
                      "la semana en curso contiene hoy")
        XCTAssertEqual(VistaCalendario.cuatro.dias(hoy).first.map { GDate.formatDay($0) },
                       "2026-08-25", "4 días arranca HOY, no el lunes")
    }

    /// La ventana que se le pide a Google tiene que cubrir lo que cualquier
    /// vista pueda enseñar. Si no, cambiar a MES pintaría un mes medio vacío
    /// que parecería un mes sin eventos.
    func testLaVentanaCubreTodasLasVistas() {
        for dia in [DateComponents(year: 2026, month: 8, day: 1),
                    DateComponents(year: 2026, month: 8, day: 25),
                    DateComponents(year: 2026, month: 8, day: 31),
                    DateComponents(year: 2026, month: 2, day: 28)] {
            let hoy = DateKit.cal.date(from: dia)!
            let (d, h) = Cronista.ventana(hoy)
            for v in VistaCalendario.allCases {
                for x in v.dias(hoy) {
                    XCTAssertGreaterThanOrEqual(x, d, "\(v.rotulo) pide un día ANTES de la ventana")
                    XCTAssertLessThan(x, h, "\(v.rotulo) pide un día DESPUÉS de la ventana")
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: 4. El vocabulario nuevo, en el tema y en su sitio
    // ════════════════════════════════════════════════════════════════════════

    /// El widget se separa del sensor por DOS canales (relleno y radio), que es
    /// la regla del estándar: un rol que se distingue por uno solo desaparece
    /// en cuanto alguien toca ese canal.
    func testElWidgetSeSeparaDelSensorPorDosCanales() {
        for tema in [Tema.claro, Tema.oscuro] {
            let w = tema.rol("widget"), s = tema.rol("sensor")
            XCTAssertNotEqual(w.radio, s.radio, "\(tema.nombre): mismo radio que el sensor")
            XCTAssertNotEqual(w.relleno, s.relleno, "\(tema.nombre): mismo relleno que el sensor")
            XCTAssertNotEqual(w.relleno, tema.rol("card").relleno,
                              "\(tema.nombre): un widget con cara de tarjeta no se lee como instrumento")
        }
    }

    /// El oscuro es NEÓN: el widget no puede ser un bloque lavado (el fallo
    /// medido del 24 ago con la silueta del reloj).
    func testElWidgetOscuroEsOscuro() {
        let l = Tema.oscuro.rol("widget").relleno.usingColorSpace(.sRGB)!
        let luz = 0.2126 * l.redComponent + 0.7152 * l.greenComponent + 0.0722 * l.blueComponent
        XCTAssertLessThan(luz, 0.20, "el widget en oscuro tiene que ser oscuro, no una placa clara")
    }

    /// Un `widget` sin tipo declarado no es un widget: es una caja que promete
    /// una ventana y no la abre.
    func testUnWidgetExigeSuTipo() {
        let sinTipo = Elemento(.objeto([
            "id": .texto("x"), "type": .texto("shape"), "role": .texto("widget"),
            "x": .numero(0), "y": .numero(0), "width": .numero(100), "height": .numero(100),
        ]))
        XCTAssertNil(Pintor.Widget(sinTipo))
        XCTAssertNotNil(Pintor.Widget(elementoWidget("calendario")))
        let noWidget = Elemento(.objeto([
            "id": .texto("y"), "type": .texto("shape"), "role": .texto("card"),
            "widget": .objeto(["tipo": .texto("calendario")]),
        ]))
        XCTAssertNil(Pintor.Widget(noWidget), "el `widget` de una tarjeta no convierte la tarjeta en widget")
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: 5. READ-ONLY, comprobado en el código y no en la intención
    // ════════════════════════════════════════════════════════════════════════

    /// LA PROMESA, CON SU ENMIENDA (25 ago).
    ///
    /// El contrato original era "aquí no existe un verbo que escriba". Daniel lo
    /// enmendó al pedir las casillas de las tareas, así que ahora el contrato es
    /// más preciso y esta prueba lo vigila con la misma dureza:
    ///
    /// · **DOS** POST y ni uno más: el refresh del token de Google (que no toca
    ///   datos de nadie) y CERRAR una tarea de Todoist por su id.
    /// · **CERO** PUT / PATCH / DELETE. Nada de crear, editar, reprogramar ni
    ///   borrar: el panel no puede inventar ni destruir nada.
    /// · Google sigue intacto — el único destino que escribe es `/tasks/…/close`.
    func testElTransporteDelDiaNoSabeEscribir() throws {
        let f = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SFMap/DiaFuentes.swift")
        let src = try String(contentsOf: f, encoding: .utf8)
        for verbo in ["\"PUT\"", "\"PATCH\"", "\"DELETE\""] {
            XCTAssertFalse(src.contains(verbo),
                           "las fuentes del día tienen prohibido escribir; apareció \(verbo)")
        }
        let posts = src.components(separatedBy: "httpMethod = \"POST\"").count - 1
        XCTAssertEqual(posts, 2, "solo dos POST: el refresh del token y cerrar una tarea")
        XCTAssertTrue(src.contains("archivo.refresh_token"),
                      "uno tiene que ser el refresh del token de Google")
        XCTAssertTrue(src.contains("/tasks/\\(idTarea)/close"),
                      "y el otro, cerrar UNA tarea por su id — nada más")
        // Y nada que escriba en Google: el calendario del panel es espejo puro.
        let googleEscribe = src.contains("calendar/v3") && (src.contains("\"DELETE\"") || src.contains("\"PUT\""))
        XCTAssertFalse(googleEscribe, "el calendario del panel jamás escribe")
    }

    /// El lector de hábitos LEE. sfcal es la cabina; esto es el espejo.
    func testLosHabitosSoloSeLeen() throws {
        let f = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SFMap/DiaFuentes.swift")
        let src = try String(contentsOf: f, encoding: .utf8)
        let trozo = src.components(separatedBy: "enum LecturaHabitos").last ?? ""
        for prohibido in ["write(to:", "removeItem", "replaceItemAt", "createDirectory"] {
            XCTAssertFalse(trozo.contains(prohibido),
                           "el lector de hábitos no puede \(prohibido): la cabina es sfcal")
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: 6. El núcleo compartido es UN archivo, no una copia
    // ════════════════════════════════════════════════════════════════════════

    /// `Sources/SFMap/Dia/` son ENLACES a los archivos de sfcal. Si alguien los
    /// convierte en copias, las dos apps empiezan a derivar el mismo día por
    /// separado y un martes cualquiera el panel dirá una cosa y la pared del
    /// monje otra — sin que nada falle.
    func testElNucleoDelDiaViajaEnElRepositorio() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/SFMap/Dia")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey])
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            XCTAssertFalse(try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? false)
            XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).isEmpty)
        }
    }

    /// El conteo del monk mode es el FIRMADO (día 1 = 9 ago 2026, 90 días,
    /// termina el 6 nov). Sale del núcleo compartido, así que esta prueba
    /// también vigila que el enlace siga trayendo la doctrina buena.
    func testElConteoDelMonkModeEsElFirmado() {
        XCTAssertEqual(MonkMode.totalDays, 90)
        let d1 = DateKit.cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        XCTAssertEqual(MonkMode.dayNumber(d1), 1, "el primer día del reto demo")
        XCTAssertEqual(GDate.formatDay(MonkMode.end), "2026-03-31", "fin del reto demo")
        XCTAssertEqual(MonkMode.dayNumber(MonkMode.end), 90)
        XCTAssertEqual(Habitos.todos.count, 6, "filas de la plantilla pública")
        XCTAssertEqual(Habitos.todos.filter(\.estrella).count, 3, "tres no negociables")
    }

    /// La rutina que se pinta sale del CALENDARIO REAL cuando lo hay, y del
    /// protocolo cuando el día está vacío. Nunca un hueco.
    func testLaRutinaPrefiereElCalendarioYNuncaDejaHueco() {
        let hoy = DateKit.cal.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        XCTAssertFalse(MonkMode.bloquesDeHoy(eventos: [], date: hoy).isEmpty,
                       "un día sin eventos cae al protocolo, no a un panel en blanco")
        let ev = CalEvent(id: "1", calendarId: "c", accountId: "a", summary: "Grabar el curso",
                          start: hoy.addingTimeInterval(9 * 3600), end: hoy.addingTimeInterval(11 * 3600),
                          isAllDay: false, status: "confirmed")
        let b = MonkMode.bloquesDeHoy(eventos: [ev], date: hoy)
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b.first?.titulo, "Grabar el curso", "lo agendado gana al protocolo")
    }
}

/// LA SILUETA SE VE EN LOS DOS TEMAS.
///
/// Dos fallos del mismo par, con un día de diferencia: el 24 ago la silueta
/// salía lavada en OSCURO (un literal del tema claro que no se repintaba); el
/// 25, con el territorio ya resuelto por el tema, salía lavada en CLARO —
/// porque el tinte elegido es el de una SECCIÓN, pensado para vivir debajo de
/// tarjetas sin competir. Una silueta no es un fondo: es el argumento.
final class SiluetaVisibleTests: XCTestCase {

    private func silueta(_ tinte: String) -> Elemento {
        Elemento(.objeto([
            "id": .texto("sil"), "type": .texto("shape"), "shape": .texto("triangle"),
            "role": .texto("drawn"), "tint": .texto(tinte),
            "x": .numero(0), "y": .numero(0), "width": .numero(2000), "height": .numero(1000),
        ]))
    }

    private func luz(_ c: NSColor) -> Double {
        let s = c.usingColorSpace(.sRGB)!
        return 0.2126 * s.redComponent + 0.7152 * s.greenComponent + 0.0722 * s.blueComponent
    }

    func testLaSiluetaSeSeparaDelLienzoEnLosDosTemas() {
        for tema in [Tema.claro, Tema.oscuro] {
            for tinte in ["morado", "ambar"] {
                let d = abs(luz(tema.relleno(silueta(tinte))) - luz(tema.lienzo))
                XCTAssertGreaterThan(d, 0.035,
                    "\(tema.nombre)/\(tinte): la silueta se funde con la página (Δluz \(d))")
            }
        }
    }

    /// Y sigue siendo FONDO, no bloque: si compitiera con las tarjetas que
    /// lleva encima, volveríamos al barro que el estándar prohíbe.
    func testLaSiluetaSigueSiendoFondo() {
        for tema in [Tema.claro, Tema.oscuro] {
            for tinte in ["morado", "ambar"] {
                let s = tema.relleno(silueta(tinte))
                let t = tema.tintes[tinte]!.trazo
                XCTAssertGreaterThan(abs(luz(s) - luz(t)), 0.06,
                    "\(tema.nombre)/\(tinte): la silueta se acercó tanto a su filo que ya es un bloque")
            }
        }
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - ENMIENDA 3b — el trofeo y la puerta a la cabina
// ════════════════════════════════════════════════════════════════════════════

/// EL PACTO DEL FIERRO. Los términos no se re-litigan, así que el código que
/// los pinta tampoco puede ablandarlos por accidente.
final class PactoDelFierroTests: XCTestCase {

    func testLosTerminosSonLosFirmados() {
        XCTAssertGreaterThan(Pacto.meta, Pacto.base)
        XCTAssertEqual(GDate.formatDay(Pacto.fin), "2026-12-31", "fecha del ejemplo")
        XCTAssertEqual(Pacto.base, 0, accuracy: 0.01)
    }

    /// ⭐ LA BARRA NACE EN LA BASE, NO EN CERO. Medido desde cero, el día que se
    /// firmó ya iba por el 55% — y una barra que nace medio llena no aprieta a
    /// nadie. Es la diferencia entre un instrumento y un adorno motivacional.
    func testElAvanceSeMideDesdeLaBaseDelPacto() {
        XCTAssertEqual(Pacto.avance(Pacto.base), 0, accuracy: 0.001,
                       "el día de la firma el avance es CERO")
        XCTAssertEqual(Pacto.avance(Pacto.meta), 1, accuracy: 0.001)
        XCTAssertEqual(Pacto.avance(Pacto.base + (Pacto.meta - Pacto.base) / 2), 0.5, accuracy: 0.001)
        XCTAssertEqual(Pacto.avance(20_000), 1, "pasarse no da más del 100%")
        XCTAssertEqual(Pacto.avance(Pacto.base - 1), 0, "caer por debajo de la base no da barra negativa")
    }

    func testLosDiasRestantesCuentanHaciaElLimite() {
        let f = { (m: Int, d: Int) in DateKit.cal.date(from: DateComponents(year: 2026, month: m, day: d))! }
        XCTAssertEqual(Pacto.diasRestantes(f(12, 31)), 0, "el día del límite quedan cero")
        XCTAssertEqual(Pacto.diasRestantes(f(12, 24)), 7)
        XCTAssertLessThan(Pacto.diasRestantes(Pacto.fin.addingTimeInterval(86400)), 0, "pasado el límite la cuenta es negativa")
    }

    /// La palabra "inversión" está marcada en el canónico como el permiso que
    /// dejaría comprarla sin pegar el número. No entra en el widget.
    func testElTrofeoNoSeLlamaInversion() throws {
        let f = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SFMap/PintorWidget.swift")
        let src = try String(contentsOf: f, encoding: .utf8)
        let trozo = src.components(separatedBy: "func widgetTrofeo").last ?? ""
        let visible = trozo.split(separator: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("*")
        }.joined()
        XCTAssertFalse(visible.lowercased().contains("inversión"),
                       "el canónico prohíbe esa palabra para el trofeo")
    }
}

/// LA PUERTA A LA CABINA — `app:`. El panel no escribe; lleva a donde se escribe.
final class PuertaALaCabinaTests: XCTestCase {

    func testElEsquemaAppSeLee() {
        XCTAssertEqual(Enlace.leer("app:sfcal"), .app("sfcal", nil))
        XCTAssertEqual(Enlace.leer("app:todoist"), .app("todoist", nil))
        XCTAssertEqual(Enlace.leer("APP:SFCal"), .app("sfcal", nil), "el esquema no distingue mayúsculas")
        XCTAssertNil(Enlace.leer("app:"), "sin app no hay destino")
    }

    /// La marca que se pinta en la esquina tiene que DECIR a dónde va. Cinco
    /// destinos con la misma marca es una promesa vaga, y una promesa vaga en
    /// un mapa vivo se deja de pulsar.
    func testCadaDestinoTieneSuMarca() {
        XCTAssertEqual(Enlace.marca("app:sfcal"), .app)
        XCTAssertEqual(Enlace.marca("doc:CLAUDE.md"), .documento)
        XCTAssertEqual(Enlace.marca("https://saasfactory.so"), .web)
        XCTAssertNotEqual(Enlace.marca("app:sfcal"), Enlace.marca("https://app.todoist.com"),
                          "abrir una app de escritorio y abrir una web no son el mismo gesto")
    }

    /// Las apps que el esquema conoce están CERRADAS. Un `app:` libre sería un
    /// lanzador de cualquier binario desde un documento de la nube: eso no es
    /// un destino, es una superficie de ataque.
    func testSoloLasDosAppsDeLaEnmienda() {
        XCTAssertNil(Enlace.rutaApp("Terminal"), "el esquema no conoce apps fuera de la enmienda")
        XCTAssertNil(Enlace.rutaApp("../../bin/sh"))
        XCTAssertNil(Enlace.webDeApp("sfcal"), "sfcal solo vive en su máquina: no hay web a la que caer")
        XCTAssertNotNil(Enlace.webDeApp("todoist"))
    }

    /// Y el escritor del lienzo rechaza lo que la app no sabría abrir, ANTES de
    /// guardarlo: un botón roto enseña a no volver a pulsarlo.
    func testElGeneradorRechazaUnAppDesconocida() throws {
        let g = Enlace.repo.appendingPathComponent(".claude/skills/sfmap/scripts/diagrama.py")
        guard FileManager.default.fileExists(atPath: g.path) else { throw XCTSkip("Integración opcional: generador externo no configurado") }
        let src = try String(contentsOf: g, encoding: .utf8)
        XCTAssertTrue(src.contains("app: solo conoce sfcal|todoist"),
                      "diagrama.py tiene que cerrar la lista de apps al escribir")
    }
}

/// LA CASILLA DE UNA TAREA — el único gesto del panel que cambia el mundo.
final class CasillaDeTareaTests: XCTestCase {

    override func tearDown() {
        Pintor.casillasTarea = []
        Pintor.cerradas = []
        super.tearDown()
    }

    /// El blanco está donde el ojo lo ve, porque lo registra el mismo código que
    /// lo pinta. Es la tercera vez que este proyecto aplica la regla (la marca
    /// de destino, el conmutador de vista, y ahora la casilla).
    func testLaCasillaSeAcierta() {
        Pintor.casillasTarea = [("t1", CGRect(x: 100, y: 200, width: 19, height: 19)),
                                ("t2", CGRect(x: 100, y: 262, width: 19, height: 19))]
        XCTAssertEqual(Pintor.tareaEn(CGPoint(x: 109, y: 209)), "t1")
        XCTAssertEqual(Pintor.tareaEn(CGPoint(x: 109, y: 271)), "t2")
        XCTAssertNil(Pintor.tareaEn(CGPoint(x: 400, y: 209)), "el TÍTULO de la tarea no la cierra")
        XCTAssertNil(Pintor.tareaEn(CGPoint(x: 109, y: 240)), "el hueco entre dos casillas no cierra ninguna")
    }

    /// ⚠️ Y no puede haber solape entre casillas: desde aquí no hay deshacer, y
    /// un blanco que a veces cierra la tarea de al lado sería el peor bug
    /// posible de esta pantalla.
    func testDosCasillasNoSePisanNiConSuMargen() {
        Pintor.casillasTarea = [("t1", CGRect(x: 100, y: 200, width: 19, height: 19)),
                                ("t2", CGRect(x: 100, y: 262, width: 19, height: 19))]
        for (id, caja) in Pintor.casillasTarea {
            for esquina in [CGPoint(x: caja.minX, y: caja.minY), CGPoint(x: caja.maxX, y: caja.maxY)] {
                XCTAssertEqual(Pintor.tareaEn(esquina), id, "la esquina de \(id) responde por otra")
            }
        }
        let separacion = 62.0 - 19.0
        XCTAssertGreaterThan(separacion, 10, "el margen del hit-test (5) no puede juntar dos casillas")
    }

    /// El acuse es INMEDIATO y local; la verdad la sigue teniendo Todoist. Si el
    /// POST falla, la palomita se retira — dejarla puesta sería el panel
    /// afirmando algo que no pasó.
    func testElAcuseSeRetiraSiFalla() throws {
        Pintor.cerradas.insert("t1")
        XCTAssertTrue(Pintor.cerradas.contains("t1"))
        Pintor.cerradas.remove("t1")
        XCTAssertFalse(Pintor.cerradas.contains("t1"))

        let f = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SFMap/main.swift")
        let src = try String(contentsOf: f, encoding: .utf8)
        XCTAssertTrue(src.contains("Pintor.cerradas.remove(id)"),
                      "un cierre que falla tiene que DESHACER la palomita")
    }

    /// Una tarea ya cerrada no se vuelve a mandar: dos POST del mismo id no
    /// hacen daño en Todoist, pero sí ensucian el acuse en pantalla.
    func testUnaTareaCerradaNoSeReenvia() {
        Pintor.cerradas.insert("t1")
        XCTAssertTrue(Pintor.cerradas.contains("t1"),
                      "el lienzo comprueba esto antes de despachar (ver Lienzo.mouseDown)")
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - EL FILTRO COMPARTIDO — la cabina lo pone, el espejo obedece
// ════════════════════════════════════════════════════════════════════════════

/// Daniel, 25 ago: *"permíteme filtrarlas estilo Notion… que sfcal recuerde mi
/// última configuración… y que el espejo en sfmap también se actualice"*.
///
/// Por eso el filtro vive en un ARCHIVO y no en `UserDefaults`: sfmap no puede
/// leer los defaults de sfcal. Y por eso la función que decide vive en el núcleo
/// compartido: dos implementaciones del mismo filtro acabarían enseñando listas
/// distintas del mismo Todoist — el desfase exacto que costó la tarde de hoy.
final class FiltroCompartidoTests: XCTestCase {

    /// ⭐ VACÍO = SIN RESTRICCIÓN, jamás "ninguno". Es la trampa clásica: si
    /// "nada marcado" significara "no mostrar nada", el primer clic de limpiar
    /// dejaría la lista en blanco y parecería que se borró todo.
    func testUnFiltroVacioNoEsconde() {
        let f = FiltroTareas()
        XCTAssertTrue(f.estaVacio)
        XCTAssertTrue(f.deja(frente: "cualquiera", prioridad: 1))
        XCTAssertTrue(f.deja(frente: nil, prioridad: 4), "ni siquiera una sin proyecto")
        XCTAssertEqual(f.ejesActivos, 0)
    }

    /// OR dentro de un eje.
    func testDentroDeUnEjeEsO() {
        var f = FiltroTareas(); f.frentes = ["yt", "com"]
        XCTAssertTrue(f.deja(frente: "yt", prioridad: 3))
        XCTAssertTrue(f.deja(frente: "com", prioridad: 3))
        XCTAssertFalse(f.deja(frente: "sistema", prioridad: 3))
        XCTAssertFalse(f.deja(frente: nil, prioridad: 3),
                       "una tarea sin proyecto no pasa un filtro DE proyecto")
    }

    /// AND entre ejes: «YouTube o Comunidad» Y «p1».
    func testEntreEjesEsY() {
        var f = FiltroTareas(); f.frentes = ["yt"]; f.prioridades = [1]
        XCTAssertTrue(f.deja(frente: "yt", prioridad: 1))
        XCTAssertFalse(f.deja(frente: "yt", prioridad: 2), "el frente pasa, la prioridad no")
        XCTAssertFalse(f.deja(frente: "com", prioridad: 1), "la prioridad pasa, el frente no")
        XCTAssertEqual(f.ejesActivos, 2)
    }

    /// La prioridad viaja YA invertida (1 = urgente), que es como la lee el
    /// resto del sistema. Si cada app la invirtiera por su cuenta, "p1" en sfcal
    /// y "p1" en el widget serían tareas distintas.
    func testLaPrioridadHablaElIdiomaDelSistema() {
        XCTAssertEqual(PrioridadTarea.delApi(4), 1, "la API llama 4 a la urgente")
        XCTAssertEqual(PrioridadTarea.delApi(1), 4)
        XCTAssertEqual(PrioridadTarea.rotulo(1), "p1")
        XCTAssertEqual(PrioridadTarea.todas, [1, 2, 3, 4])
    }

    /// Ida y vuelta por disco: es como el filtro llega de la cabina al espejo.
    func testElFiltroSobreviveAlDisco() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("filtro-prueba-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var f = FiltroTareas(); f.frentes = ["a", "b"]; f.prioridades = [1, 2]
        f.guardar(tmp)
        XCTAssertEqual(FiltroTareas.cargar(tmp), f, "lo que guarda la cabina es lo que lee el espejo")
    }

    /// Y SIN archivo no hay filtro — no un filtro vacío que oculte todo. Es la
    /// misma regla de arriba, en la puerta del disco.
    func testSinArchivoNoHayFiltro() {
        let noExiste = URL(fileURLWithPath: "/tmp/no-existe-jamas-\(UUID().uuidString).json")
        XCTAssertTrue(FiltroTareas.cargar(noExiste).estaVacio)
    }

    /// El filtro entra en la huella: si Daniel filtra en sfcal, el panel tiene
    /// que repintarse. Sin esto, el espejo se quedaría enseñando la lista vieja
    /// hasta que cambiara otra cosa.
    func testCambiarElFiltroRepintaElPanel() {
        var a = EstadoDia()
        a.tareas = Lectura(valor: [], alDia: Date(), fallo: nil)
        var b = a
        b.filtro.prioridades = [1]
        XCTAssertNotEqual(a.huella, b.huella, "filtrar en la cabina repinta el espejo")
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Contraste y ventanas (25 ago, tarde)
// ════════════════════════════════════════════════════════════════════════════

/// NEGRO SOBRE NEGRO, BLANCO SOBRE BLANCO. Daniel, viendo los rótulos de banda:
/// *"que no vuelva a ocurrir negro sobre negro y blanco sobre blanco en los
/// títulos de secciones"*.
///
/// La causa: el rótulo se pintaba con el color del LIENZO, asumiendo que la
/// pastilla siempre sería un color saturado. Cierto para morado y ámbar, FALSO
/// para `neutro` —el tinte de las tres bandas del tablero—, cuyo filo es un gris
/// medio. Los tres rótulos, ilegibles, en los dos temas.
final class ContrasteDeRotulosTests: XCTestCase {

    private func luz(_ c: NSColor) -> Double {
        let s = c.usingColorSpace(.sRGB)!
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(s.redComponent) + 0.7152 * lin(s.greenComponent) + 0.0722 * lin(s.blueComponent)
    }

    /// Contraste WCAG entre dos colores. 4.5:1 es el mínimo para texto normal;
    /// aquí el rótulo va en negrita y versalitas, así que 3:1 es la vara justa.
    private func contraste(_ a: NSColor, _ b: NSColor) -> Double {
        let (x, y) = (luz(a), luz(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// ⭐ TODO tinte, en TODO tema: el rótulo se lee.
    func testElRotuloSeLeeSobreCualquierTinte() {
        for tema in [Tema.claro, Tema.oscuro] {
            for (nombre, t) in tema.tintes {
                let tinta = Tema.tintaSobre(t.trazo)
                XCTAssertGreaterThan(contraste(tinta, t.trazo), 3.0,
                    "\(tema.nombre)/\(nombre): el rótulo no se lee sobre su pastilla")
            }
        }
    }

    /// La lápida del fallo: la regla vieja —usar el color del lienzo— habría
    /// fallado justo en `neutro`, que es el de las tres bandas del tablero.
    func testLaReglaViejaFallabaEnNeutro() {
        for tema in [Tema.claro, Tema.oscuro] {
            let pastilla = tema.tintes["neutro"]!.trazo
            XCTAssertLessThan(contraste(tema.lienzo, pastilla), 3.0,
                "\(tema.nombre): con el color del lienzo, el rótulo neutro era ilegible")
            XCTAssertGreaterThan(contraste(Tema.tintaSobre(pastilla), pastilla), 3.0,
                "\(tema.nombre): …y con la tinta medida, se lee")
        }
    }

    /// Y sirve para cualquier fondo, no solo para los tintes del tema: es una
    /// función de sistema de diseño, no un parche para este caso.
    func testLaTintaSeMideParaCualquierFondo() {
        for hex in ["#000000", "#ffffff", "#8C27F1", "#ff9101", "#808080", "#f1f3f8"] {
            let f = NSColor(hex: hex)!
            XCTAssertGreaterThan(contraste(Tema.tintaSobre(f), f), 3.0, "falla sobre \(hex)")
        }
    }
}

/// LAS TRES VENTANAS del centro de mando (7D · 30D · 90D).
final class VentanaDeSensoresTests: XCTestCase {

    override func tearDown() { VentanaSensor.forzada = nil; super.tearDown() }

    func testLasTresVentanasYSusDias() {
        XCTAssertEqual(VentanaSensor.allCases.map(\.dias), [7, 30, 90])
        XCTAssertEqual(VentanaSensor.semana.rotulo, "7D")
        XCTAssertEqual(VentanaSensor.trimestre.rotulo, "90D")
    }

    private func banda(_ conVentanas: Bool) -> Elemento {
        var o: [String: Json] = [
            "id": .texto("s:mando"), "type": .texto("frame"),
            "x": .numero(120), "y": .numero(230), "width": .numero(5420), "height": .numero(390),
        ]
        if conVentanas { o["ventanas"] = .bool(true) }
        return Elemento(.objeto(o))
    }

    func testCadaChipSeDejaPulsarEnSuCentro() {
        let e = banda(true)
        let chips = Pintor.chipsDeVentana(e)
        XCTAssertEqual(chips.count, 3)
        for (v, caja) in chips {
            XCTAssertEqual(Pintor.ventanaEn(e, CGPoint(x: caja.midX, y: caja.midY)), v)
        }
        for i in chips.indices {
            for j in chips.indices where j > i {
                XCTAssertFalse(chips[i].1.intersects(chips[j].1), "dos chips de ventana se pisan")
            }
        }
    }

    /// Solo la banda que los DECLARA los lleva. Un conmutador flotando sobre
    /// una sección cualquiera sería una promesa que no lleva a ningún sitio.
    func testSoloLaBandaQueLosDeclaraLosLleva() {
        XCTAssertTrue(Pintor.chipsDeVentana(banda(false)).isEmpty)
        XCTAssertNil(Pintor.ventanaEn(banda(false), CGPoint(x: 5400, y: 210)))
    }

    /// ⭐ El sensor LEE la ventana elegida, y cae a los campos planos si el
    /// lienzo es viejo. Sin eso, un tablero anterior al cambio se quedaría mudo.
    func testElSensorLeeLaVentanaYCaeAlPlanoSiNoLaHay() {
        func sensor(_ conVentanas: Bool) -> Elemento {
            var s: [String: Json] = ["etiqueta": .texto("MRR"), "valor": .texto("$8,220"),
                                     "tendencia": .lista([.numero(1), .numero(2)])]
            if conVentanas {
                s["ventanas"] = .objeto([
                    "7":  .objeto(["etiqueta": .texto("MRR"), "valor": .texto("SIETE")]),
                    "30": .objeto(["etiqueta": .texto("MRR"), "valor": .texto("TREINTA")]),
                    "90": .objeto(["etiqueta": .texto("MRR"), "valor": .texto("NOVENTA")]),
                ])
            }
            return Elemento(.objeto(["id": .texto("s"), "type": .texto("shape"),
                                     "role": .texto("sensor"), "sensor": .objeto(s)]))
        }
        VentanaSensor.forzada = .mes
        XCTAssertEqual(Pintor.Lectura(sensor(true))?.valor, "TREINTA")
        VentanaSensor.forzada = .trimestre
        XCTAssertEqual(Pintor.Lectura(sensor(true))?.valor, "NOVENTA")
        // Lienzo viejo: no hay `ventanas` y el plano manda.
        XCTAssertEqual(Pintor.Lectura(sensor(false))?.valor, "$8,220",
                       "un tablero anterior al cambio no puede quedarse mudo")
    }
}

/// EL HORIZONTE del filtro y los EJES de la gráfica (25 ago, noche).
final class HorizonteYEjesTests: XCTestCase {

    /// ⭐ LAS VENCIDAS ENTRAN SIEMPRE, elijas el horizonte que elijas. Un
    /// horizonte que esconde lo que ya se te pasó convierte una deuda en una
    /// sorpresa: justo lo contrario de para qué se mira la lista.
    func testLasVencidasNoLasEsconderNingunHorizonte() {
        let hoy = "2026-08-25"
        for h in FiltroTareas.Horizonte.allCases {
            var f = FiltroTareas(); f.horizonte = h
            XCTAssertTrue(f.deja(frente: nil, prioridad: 1, dia: "2026-08-20", hoy: hoy),
                          "\(h.rawValue) escondió una tarea vencida")
        }
    }

    func testCadaHorizonteRecortaHastaDondePromete() {
        let hoy = "2026-08-25"
        func pasa(_ h: FiltroTareas.Horizonte, _ dia: String) -> Bool {
            var f = FiltroTareas(); f.horizonte = h
            return f.deja(frente: nil, prioridad: 1, dia: dia, hoy: hoy)
        }
        XCTAssertTrue(pasa(.hoy, hoy))
        XCTAssertFalse(pasa(.hoy, "2026-08-26"), "mañana no es hoy")
        XCTAssertTrue(pasa(.semana, "2026-09-01"), "7 días justos entran")
        XCTAssertFalse(pasa(.semana, "2026-09-02"))
        XCTAssertTrue(pasa(.mes, "2026-09-24"))
        XCTAssertFalse(pasa(.mes, "2026-09-26"))
        XCTAssertTrue(pasa(.todas, "2027-01-01"), "«todas» no recorta nada")
    }

    /// Una tarea SIN fecha no cabe en un horizonte —no tiene dónde caer—, pero
    /// con «todas» sí: es la única vista donde el backlog existe.
    func testUnaTareaSinFechaSoloEntraEnTodas() {
        var f = FiltroTareas()
        XCTAssertTrue(f.deja(frente: nil, prioridad: 1, dia: nil))
        f.horizonte = .semana
        XCTAssertFalse(f.deja(frente: nil, prioridad: 1, dia: nil))
    }

    /// Las ETIQUETAS son un eje más: OR dentro, AND con los demás.
    func testLasEtiquetasSonUnEjeMas() {
        var f = FiltroTareas(); f.etiquetas = ["idea"]
        XCTAssertTrue(f.deja(frente: nil, prioridad: 1, etiquetas: ["idea", "x"]))
        XCTAssertFalse(f.deja(frente: nil, prioridad: 1, etiquetas: ["otra"]))
        XCTAssertFalse(f.deja(frente: nil, prioridad: 1, etiquetas: []))
        f.prioridades = [1]
        XCTAssertFalse(f.deja(frente: nil, prioridad: 2, etiquetas: ["idea"]), "AND con prioridad")
    }

    /// Y un filtro con horizonte NO está vacío: si lo estuviera, el botón de
    /// limpiar no aparecería y no habría forma de volver a verlas todas.
    func testUnHorizonteCuentaComoFiltro() {
        var f = FiltroTareas(); f.horizonte = .hoy
        XCTAssertFalse(f.estaVacio)
        XCTAssertEqual(f.ejesActivos, 1)
    }

    /// La fecha corta del eje X. Un ISO en un eje es ruido; "24 ago" se lee.
    func testLaFechaDelEjeXSeLee() {
        XCTAssertEqual(Pintor.Lectura.diaCorto("2026-08-24"), "24 ago")
        XCTAssertEqual(Pintor.Lectura.diaCorto("2026-01-01"), "1 ene")
        XCTAssertNil(Pintor.Lectura.diaCorto("basura"), "sin fecha válida, sin rótulo inventado")
        XCTAssertNil(Pintor.Lectura.diaCorto("2026-13-01"), "un mes 13 no se pinta")
    }

    /// El sensor lleva las FECHAS de su serie: sin ellas el eje X no existe.
    func testElSensorLlevaLasFechasDeSuSerie() {
        let e = Elemento(.objeto([
            "id": .texto("s"), "type": .texto("shape"), "role": .texto("sensor"),
            "sensor": .objeto(["etiqueta": .texto("MRR"), "valor": .texto("$8,220"),
                               "tendencia": .lista([.numero(1), .numero(2)]),
                               "fechas": .lista([.texto("2026-08-18"), .texto("2026-08-24")])]),
        ]))
        XCTAssertEqual(Pintor.Lectura(e)?.fechas, ["2026-08-18", "2026-08-24"])
        XCTAssertEqual(Pintor.Lectura(e)?.tendencia.count, 2,
                       "tantas fechas como puntos, o el eje apunta a otro sitio")
    }
}

/// LA VISTA PEDIDA — "llévame a esa vista", no solo a la app (25 ago).
final class PeticionDeVistaTests: XCTestCase {

    private func tmp() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vista-\(UUID().uuidString).json")
    }

    func testCadaWidgetSabeAQueVistaLleva() {
        XCTAssertEqual(PeticionVista.vistaDeWidget("monk"), "monkMode")
        XCTAssertEqual(PeticionVista.vistaDeWidget("tareas"), "tasks")
        XCTAssertEqual(PeticionVista.vistaDeWidget("calendario"), "week")
        XCTAssertNil(PeticionVista.vistaDeWidget("trofeo"), "el trofeo no vive en sfcal")
    }

    func testLaPeticionViajaYSeConsume() {
        let u = tmp()
        PeticionVista.pedir("monkMode", u)
        XCTAssertEqual(PeticionVista.consumir(u), "monkMode")
        XCTAssertNil(PeticionVista.consumir(u), "una petición se consume UNA vez")
        XCTAssertFalse(FileManager.default.fileExists(atPath: u.path), "…y el archivo se borra")
    }

    /// ⭐ LA PETICIÓN CADUCA. Sin esto, sfcal saltaría a Monk Mode cada vez que
    /// se abriera, para siempre, porque el archivo seguiría ahí.
    func testUnaPeticionViejaSeIgnora() {
        let u = tmp()
        defer { try? FileManager.default.removeItem(at: u) }
        PeticionVista.pedir("tasks", u)
        XCTAssertNil(PeticionVista.consumir(u, ahora: Date().addingTimeInterval(60)),
                     "una petición de hace un minuto ya no manda")
    }

    /// Y una del "futuro" tampoco: un reloj que se adelanta no puede dejar una
    /// petición viva indefinidamente.
    func testUnaPeticionDelFuturoTampoco() {
        let u = tmp()
        defer { try? FileManager.default.removeItem(at: u) }
        PeticionVista.pedir("tasks", u)
        XCTAssertNil(PeticionVista.consumir(u, ahora: Date().addingTimeInterval(-60)))
    }

    /// El esquema entiende la vista y sigue entendiendo la app a secas.
    func testElEsquemaLeeLaVista() {
        XCTAssertEqual(Enlace.leer("app:sfcal?vista=monkMode"), .app("sfcal", "monkMode"))
        XCTAssertEqual(Enlace.leer("app:sfcal"), .app("sfcal", nil),
                       "sin vista sigue abriendo la app y ya")
        XCTAssertEqual(Enlace.leer("app:todoist"), .app("todoist", nil))
        XCTAssertEqual(Enlace.marca("app:sfcal?vista=tasks"), .app)
    }

    /// MAÑANA es su propio escalón: de "hoy" a "7 días" hay un salto de seis, y
    /// el día que de verdad se planea por la noche es el siguiente.
    func testMananaEsUnHorizontePropio() {
        let hoy = "2026-08-25"
        func pasa(_ h: FiltroTareas.Horizonte, _ dia: String) -> Bool {
            var f = FiltroTareas(); f.horizonte = h
            return f.deja(frente: nil, prioridad: 1, dia: dia, hoy: hoy)
        }
        XCTAssertTrue(FiltroTareas.Horizonte.allCases.contains(.manana))
        XCTAssertTrue(pasa(.manana, "2026-08-26"))
        XCTAssertTrue(pasa(.manana, hoy), "mañana incluye hoy: es un horizonte, no un día suelto")
        XCTAssertFalse(pasa(.manana, "2026-08-27"))
        XCTAssertTrue(pasa(.manana, "2026-08-20"), "y las vencidas siguen entrando")
        XCTAssertEqual(FiltroTareas.Horizonte.manana.dias, 1)
    }
}

/// ⭐ EL BINARIO VIEJO CONTRA EL LIENZO NUEVO (25 ago, noche).
///
/// Los lienzos viajan por la nube y la app se instala aparte, así que SIEMPRE
/// puede correr una versión que no conoce el formato de un enlace recién
/// escrito. Pasó: el lienzo ganó `app:sfcal?vista=week` y el binario que
/// Daniel tenía abierto leyó todo eso como el NOMBRE de la app, no la encontró,
/// y no abrió nada. En silencio. *"El widget no me está redireccionando,
/// ninguno."*
///
/// La regla: **el resolutor de la app ignora cualquier cola que no entienda.**
/// Un sufijo desconocido puede costar una función; jamás la acción entera.
final class EnlaceToleranteTests: XCTestCase {

    func testElNombreDeLaAppSobreviveACualquierSufijo() {
        let ruta = Enlace.rutaApp("sfcal")
        XCTAssertEqual(Enlace.rutaApp("sfcal?vista=monkMode"), ruta)
        XCTAssertEqual(Enlace.rutaApp("sfcal?loQueSea=42&otro=1"), ruta,
                        "un sufijo que esta versión no conoce no puede romper la apertura")
        XCTAssertEqual(Enlace.rutaApp("SFCal?vista=week"), ruta, "ni las mayúsculas")
    }

    /// Y la lista sigue cerrada: tolerar un sufijo no es tolerar cualquier app.
    func testTolerarElSufijoNoAbreLaPuerta() {
        XCTAssertNil(Enlace.rutaApp("Terminal?vista=x"))
        XCTAssertNil(Enlace.rutaApp("../../bin/sh?vista=x"))
    }
}

/// ⌘R QUE DE VERDAD ADOPTA LA VERSIÓN NUEVA.
///
/// ⚠️ El fallo: `static let arranque = Date()`. En Swift un `static let` es
/// PEREZOSO — se inicializa la primera vez que alguien lo toca, y el primero
/// que lo tocaba era el propio ⌘R. Así que `arranque` acababa siendo el
/// instante del atajo, el binario nuevo jamás era "más nuevo que el arranque",
/// y la comprobación devolvía false en silencio. La app seguía con el binario
/// viejo y Daniel creyendo que lo había actualizado.
final class RelanzarTests: XCTestCase {

    /// El arranque sale del KERNEL, no de la primera vez que alguien pregunta.
    func testElArranqueEsElDelProcesoNoElDeLaPregunta() {
        let a = Relanzar.arranque
        XCTAssertGreaterThan(a.timeIntervalSince1970, 1_000_000,
                             "sin dato del kernel se asume 1970 y siempre ofrecería relanzar")
        XCTAssertLessThan(a, Date(), "el proceso arrancó ANTES de esta línea")
        // La prueba del fallo: el valor NO puede moverse por consultarlo. Con el
        // `static let = Date()` viejo, la primera lectura fijaba el reloj.
        XCTAssertEqual(a, Relanzar.arranque, "el arranque no puede depender de cuándo se pregunte")
    }

    /// Y es coherente con el reloj: el proceso de estas pruebas lleva vivo
    /// segundos, no horas ni un tiempo negativo.
    func testElArranqueEsCreible() {
        let vida = Date().timeIntervalSince(Relanzar.arranque)
        XCTAssertGreaterThan(vida, 0, "un proceso no puede arrancar en el futuro")
        XCTAssertLessThan(vida, 3600, "estas pruebas no llevan una hora corriendo")
    }
}
