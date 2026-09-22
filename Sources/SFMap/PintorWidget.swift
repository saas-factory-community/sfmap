import AppKit
import CoreGraphics

/**
 * EL WIDGET VIVO — la ventana a otro sistema, dentro del mapa.
 *
 * El sensor dice CUÁNTO (una cifra medida). El widget-documento enseña QUÉ DICE
 * un documento del repo. Faltaba lo que pasa AHORA: la agenda, el día del
 * monje, lo que está pendiente. Eso no cabe en una cifra ni en una miniatura —
 * es una vista de otro sistema, viva, y por eso es vocabulario nuevo.
 *
 * ════════════════════════════════════════════════════════════════════════════
 * LAS REGLAS QUE MANDAN AQUÍ
 * ════════════════════════════════════════════════════════════════════════════
 *
 * 1. **ESPEJO, NO CABINA** (Regla de Oro #5). Ninguna interacción escribe. La
 *    ÚNICA que existe es el conmutador de vista del calendario, porque cambiar
 *    de vista es MIRAR, no operar. Para todo lo demás, Daniel le habla a Levy.
 *
 * 2. **EL DATO NO VIVE EN EL DOCUMENTO.** El elemento guardado dice «aquí va el
 *    calendario» y nada más. Lo que se pinta sale de `EstadoDia`, que el
 *    Cronista refresca solo. Hornear la agenda en el JSON de la página haría un
 *    póster y encima escribiría en `draw` cada minuto.
 *
 * 3. **SIN DATO SE DICE.** Cada widget lleva su hora de última lectura. Si la
 *    fuente no contesta, lo escribe: «sin dato desde hh:mm». Un calendario
 *    vacío se lee como un día libre, y eso es una mentira cara.
 *
 * 4. **LA GEOMETRÍA LA CALCULA QUIEN PINTA.** El conmutador se puede pulsar
 *    porque `chipsDeVista` es la MISMA función que dibuja los chips y que los
 *    localiza. Dos piezas calculando dónde está un botón es la receta del botón
 *    que no se deja pulsar (lección de la marca de destino).
 */

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Vocabulario
// ════════════════════════════════════════════════════════════════════════════

enum VistaCalendario: String, CaseIterable {
    case mes, semana, cuatro, dia

    var vistaSFCal: String {
        switch self { case .mes: return "month"; case .semana: return "week"; case .cuatro: return "fourDay"; case .dia: return "day" }
    }

    var rotulo: String {
        switch self {
        case .mes: return "MES"
        case .semana: return "7D"
        case .cuatro: return "4D"
        case .dia: return "1D"
        }
    }

    /// Cuántas columnas de día pinta. El mes tiene su propia rejilla.
    var columnas: Int {
        switch self {
        case .mes: return 7
        case .semana: return 7
        case .cuatro: return 4
        case .dia: return 1
        }
    }

    /// Los días que enseña. Semana y mes son del periodo EN CURSO; 4d y 1d
    /// arrancan hoy. No hay avanzar/retroceder a propósito: el panel es un
    /// espejo del ahora, y navegar el pasado es trabajo de sfcal.
    func dias(_ hoy: Date = Date()) -> [Date] {
        switch self {
        case .mes:    return DateKit.monthGrid(hoy)
        case .semana: return DateKit.weekDays(hoy)
        case .cuatro: return (0..<4).map { DateKit.addDays(DateKit.startOfDay(hoy), $0) }
        case .dia:    return [DateKit.startOfDay(hoy)]
        }
    }

    /// La vista elegida se recuerda entre sesiones. Es estado de VISTA (como el
    /// zoom), no dato: no viaja al documento ni a la nube.
    static var elegida: VistaCalendario {
        get {
            if let f = forzada { return f }
            return VistaCalendario(rawValue: UserDefaults.standard.string(forKey: "sfmap.vistaCal") ?? "") ?? .semana
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "sfmap.vistaCal") }
    }

    /// `--vista <x>`: manda solo en esta corrida y NO se escribe en preferencias.
    nonisolated(unsafe) static var forzada: VistaCalendario?
}

/// LA VENTANA de los sensores del negocio. Daniel, 25 ago: *"¿hay forma de
/// tener un botón para vistas mensuales y quarters?"*.
///
/// Es estado de VISTA, igual que el conmutador del calendario: cambiarla no
/// consulta nada. Las tres series las deja escritas el cron una vez al día
/// (`sensores.py`), así que el botón solo elige cuál mirar — meter una llamada
/// a Supabase en un clic convertiría el espejo en un cliente de base de datos.
enum VentanaSensor: String, CaseIterable {
    case semana, mes, trimestre

    var dias: Int {
        switch self {
        case .semana: return 7
        case .mes: return 30
        case .trimestre: return 90
        }
    }
    var rotulo: String {
        switch self {
        case .semana: return "7D"
        case .mes: return "30D"
        case .trimestre: return "90D"
        }
    }

    nonisolated(unsafe) static var forzada: VentanaSensor?

    static var elegida: VentanaSensor {
        get {
            if let f = forzada { return f }
            return VentanaSensor(rawValue: UserDefaults.standard.string(forKey: "sfmap.ventanaSensor") ?? "")
                ?? .semana
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "sfmap.ventanaSensor") }
    }
}

extension Pintor {

    /// La declaración que vive en el documento. Sin datos: solo qué widget es.
    struct Widget {
        var tipo: String
        init?(_ e: Elemento) {
            guard e.rol == "widget", let t = e.crudo["widget"]?["tipo"]?.s else { return nil }
            tipo = t
        }
    }

    // ── medidas base ────────────────────────────────────────────────────────
    // Tipografía en unidades de MUNDO, pensada para que la banda EL DÍA se lea
    // entera a los zooms de trabajo del panel (~0.35–0.6). Números fijos y no
    // proporcionales al alto: un widget que encoge su letra al encogerse acaba
    // ilegible sin avisar, y prefiero que se note que falta sitio.
    static let wPad = 26.0
    static let wCabecera = 60.0

    // ════════════════════════════════════════════════════════════════════════
    // MARK: - Reparto
    // ════════════════════════════════════════════════════════════════════════

    func widget(_ e: Elemento) {
        guard let w = Widget(e) else { return }
        let r = e.caja
        ctx.saveGState()
        ctx.setAlpha(e.opacidad)
        // Recorte al marco: un evento que se sale del widget se lee como un
        // error del lienzo, no como una agenda que no cabe.
        let camino = CGMutablePath()
        camino.addRoundedRect(in: r, cornerWidth: 10, cornerHeight: 10)
        ctx.addPath(camino); ctx.clip()
        switch w.tipo {
        case "calendario": widgetCalendario(r)
        case "monk":       widgetMonk(r)
        case "tareas":     widgetTareas(r)
        case "trofeo":     widgetTrofeo(r)
        default:
            wTexto("widget desconocido: \(w.tipo)", CGPoint(x: r.minX + Pintor.wPad, y: r.minY + Pintor.wPad),
                   tam: 22, peso: 700, color: tema.pieTexto, mono: true)
        }
        ctx.restoreGState()
    }

    // ── utilidades de texto ─────────────────────────────────────────────────

    func wTexto(_ s: String, _ p: CGPoint, tam: Double, peso: Double, color: NSColor,
                mono: Bool = false, kern: Double = 0) {
        pintarTexto(s, en: p, tamano: tam, peso: peso, color: color, mono: mono, espaciado: kern)
    }

    func wAncho(_ s: String, tam: Double, peso: Double, mono: Bool) -> Double {
        var e = EstiloTexto()
        e.familia = mono ? "jetbrains-mono" : "montserrat"
        e.peso = peso; e.tamano = tam
        return Medidor.medir(s, e)
    }

    /// Parte en N líneas por PALABRAS y solo trunca la última. Un título
    /// cortado con «…» esconde justo la parte que dice de qué va el bloque
    /// («Videollamada Semanal — Prod…»): si la caja da de sí, se envuelve.
    func wEnvolver(_ s: String, ancho: Double, tam: Double, peso: Double, lineas: Int) -> [String] {
        guard lineas > 1, wAncho(s, tam: tam, peso: peso, mono: false) > ancho else {
            return [wCortar(s, ancho: ancho, tam: tam, peso: peso)]
        }
        var out: [String] = []
        var actual = ""
        for palabra in s.split(separator: " ").map(String.init) {
            let prueba = actual.isEmpty ? palabra : actual + " " + palabra
            if wAncho(prueba, tam: tam, peso: peso, mono: false) <= ancho {
                actual = prueba
            } else {
                if !actual.isEmpty { out.append(actual) }
                actual = palabra
                if out.count == lineas - 1 { break }
            }
        }
        if out.count < lineas, !actual.isEmpty {
            // Lo que quede de la frase entra en la última línea, y SOLO esa se
            // trunca si hace falta.
            let usadas = out.joined(separator: " ")
            let resto = usadas.isEmpty ? s : String(s.dropFirst(usadas.count + 1))
            out.append(wCortar(resto, ancho: ancho, tam: tam, peso: peso))
        }
        return Array(out.prefix(lineas))
    }

    /// Corta a lo ancho con puntos suspensivos. Cortar en seco a mitad de
    /// palabra hace que un título largo parezca otro título.
    func wCortar(_ s: String, ancho: Double, tam: Double, peso: Double, mono: Bool = false) -> String {
        guard wAncho(s, tam: tam, peso: peso, mono: mono) > ancho else { return s }
        var t = s
        while !t.isEmpty, wAncho(t + "…", tam: tam, peso: peso, mono: mono) > ancho { t.removeLast() }
        return t.trimmingCharacters(in: .whitespaces) + "…"
    }

    func wCaja(_ r: CGRect, radio: Double, relleno: NSColor?, trazo: NSColor? = nil, grosor: Double = 1.5) {
        let p = CGMutablePath()
        p.addRoundedRect(in: r, cornerWidth: radio, cornerHeight: radio)
        if let f = relleno { ctx.addPath(p); ctx.setFillColor(f.cgColor); ctx.fillPath() }
        if let t = trazo {
            ctx.addPath(p); ctx.setStrokeColor(t.cgColor); ctx.setLineWidth(grosor)
            ctx.setLineDash(phase: 0, lengths: []); ctx.strokePath()
        }
    }

    /// La cabecera común: rótulo del instrumento a la izquierda, sello de
    /// frescura a la derecha. El sello NO es decoración: un panel que vive
    /// abierto tiene que poder decir de cuándo es lo que enseña.
    @discardableResult
    func wCabeceraDe(_ r: CGRect, rotulo: String, sub: String?, alDia: Date?, vara: TimeInterval,
                     fallo: String?) -> Double {
        let pad = Pintor.wPad
        wTexto(rotulo.uppercased(), CGPoint(x: r.minX + pad, y: r.minY + pad),
               tam: 20, peso: 800, color: tema.pieTexto, mono: true, kern: 2.2)
        if let s = sub {
            wTexto(s, CGPoint(x: r.minX + pad, y: r.minY + pad + 26),
                   tam: 27, peso: 800, color: tema.tituloTexto)
        }
        // El sello: hh:mm si la lectura está fresca; si no, lo que pasa.
        let fresca = Cronista.fresca(alDia, vara: vara)
        let sello: String
        var col = tema.pieTexto
        if let h = Cronista.sello(alDia) {
            sello = fresca ? "al día \(h)" : "sin dato desde \(h)"
            if !fresca { col = tema.tintes["rojo"]?.etiqueta ?? col }
        } else {
            sello = fallo.map { "sin dato · \($0.prefix(38))" } ?? "sin lectura"
            col = tema.tintes["rojo"]?.etiqueta ?? col
        }
        let w = wAncho(sello, tam: 17, peso: 700, mono: true)
        wTexto(sello, CGPoint(x: r.maxX - pad - w, y: r.minY + pad), tam: 17, peso: 700,
               color: col, mono: true)
        return r.minY + Pintor.wCabecera
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: - 1. CALENDARIO
    // ════════════════════════════════════════════════════════════════════════

    /// Los chips del conmutador, EN ORDEN, con su caja. La misma función pinta
    /// y localiza (ver regla 4 de la cabecera).
    static func chipsDeVista(_ e: Elemento) -> [(VistaCalendario, CGRect)] {
        guard let w = Widget(e), w.tipo == "calendario" else { return [] }
        let r = e.caja
        let alto = 32.0, hueco = 8.0
        var cajas: [(VistaCalendario, CGRect)] = []
        let anchos: [VistaCalendario: Double] = [.mes: 62, .semana: 52, .cuatro: 52, .dia: 52]
        let total = VistaCalendario.allCases.reduce(0.0) { $0 + (anchos[$1] ?? 52) + hueco } - hueco
        // ⚠️ EN LA MISMA FILA QUE EL RÓTULO, a la izquierda del sello.
        //
        // La primera versión los puso una línea más abajo y quedaban DEBAJO de
        // la banda AHORA, medio tapados: un botón medio tapado no se descubre.
        // Se reserva sitio fijo para el sello porque su texto cambia de largo
        // («al día 09:41» vs «sin dato desde 09:41») y no puede empujarlos.
        let sitioSello = 340.0
        var x = r.maxX - wPad - sitioSello - total
        let y = r.minY + wPad - 6
        for v in VistaCalendario.allCases {
            let w = anchos[v] ?? 52
            cajas.append((v, CGRect(x: x, y: y, width: w, height: alto)))
            x += w + hueco
        }
        return cajas
    }

    /// ¿El punto cae en un chip? Devuelve la vista que pide.
    static func vistaEn(_ e: Elemento, _ punto: CGPoint) -> VistaCalendario? {
        chipsDeVista(e).first { $0.1.insetBy(dx: -3, dy: -3).contains(punto) }?.0
    }

    // ── la ventana de los sensores, sobre su BANDA ──────────────────────────

    /// Los chips 7D/30D/90D de una sección marcada con `ventanas: true`.
    /// Se colocan en la fila del rótulo, pegados al borde derecho de la banda:
    /// el rótulo dice QUÉ es la franja y el conmutador CUÁNTO abarca.
    static func chipsDeVentana(_ e: Elemento) -> [(VentanaSensor, CGRect)] {
        guard e.tipo == "frame", e.crudo["ventanas"]?.b == true else { return [] }
        let alto = 30.0, hueco = 8.0, ancho = 62.0
        let total = Double(VentanaSensor.allCases.count) * (ancho + hueco) - hueco
        var x = e.x + e.ancho - 26 - total
        let y = e.y - alto - 4                    // sobre el borde, como el rótulo
        return VentanaSensor.allCases.map { v in
            defer { x += ancho + hueco }
            return (v, CGRect(x: x, y: y, width: ancho, height: alto))
        }
    }

    static func ventanaEn(_ e: Elemento, _ punto: CGPoint) -> VentanaSensor? {
        chipsDeVentana(e).first { $0.1.insetBy(dx: -3, dy: -3).contains(punto) }?.0
    }

    /// Los pinta. Lo llama `Pintor.seccion` para las bandas que las declaran.
    func ventanasDeSeccion(_ e: Elemento) {
        let activa = VentanaSensor.elegida
        for (v, caja) in Pintor.chipsDeVentana(e) {
            let on = v == activa
            wCaja(caja, radio: 7,
                  relleno: on ? tema.acento : tema.rol("sticky").relleno,
                  trazo: on ? nil : tema.rol("card").trazo.color, grosor: 1)
            let w = wAncho(v.rotulo, tam: 15, peso: 800, mono: true)
            wTexto(v.rotulo, CGPoint(x: caja.midX - w / 2, y: caja.minY + 7),
                   tam: 15, peso: 800,
                   color: on ? Tema.tintaSobre(tema.acento) : tema.cuerpoTexto,
                   mono: true, kern: 0.6)
        }
    }

    private func pintarConmutador(_ r: CGRect, elemento: Elemento?) {
        guard let e = elemento else { return }
        let activa = VistaCalendario.elegida
        for (v, caja) in Pintor.chipsDeVista(e) {
            let on = v == activa
            wCaja(caja, radio: 7,
                  relleno: on ? tema.acento : tema.rol("sticky").relleno,
                  trazo: on ? nil : tema.rol("card").trazo.color, grosor: 1)
            let w = wAncho(v.rotulo, tam: 16, peso: 800, mono: true)
            wTexto(v.rotulo, CGPoint(x: caja.midX - w / 2, y: caja.minY + 8),
                   tam: 16, peso: 800, color: on ? .white : tema.cuerpoTexto, mono: true, kern: 0.6)
        }
    }

    /// El elemento que se está pintando. Lo necesita el conmutador para saber
    /// su caja; se pasa por aquí para no cambiar la firma de `figura`.
    nonisolated(unsafe) static var elementoEnCurso: Elemento?

    /// Las CASILLAS de las tareas: id de Todoist → caja donde se pintó.
    ///
    /// Se llena al pintar y la lee el hit-test, que es la única forma de que el
    /// blanco esté donde el ojo lo ve (misma lección que la marca de destino y
    /// que el conmutador de vista). Se limpia en cada pasada del widget: si
    /// quedaran cajas de un pintado viejo, una tarea que ya no está seguiría
    /// teniendo un botón vivo encima.
    nonisolated(unsafe) static var casillasTarea: [(String, CGRect)] = []

    /// ¿El punto cae en la casilla de alguna tarea?
    static func tareaEn(_ punto: CGPoint) -> String? {
        casillasTarea.first { $0.1.insetBy(dx: -5, dy: -5).contains(punto) }?.0
    }

    /// Las que se acaban de cerrar y aún no han desaparecido de la lectura.
    /// Sin esto, la tarea se queda palomeada y ahí hasta el siguiente refresco
    /// —hasta dos minutos— y parece que el clic no hizo nada.
    nonisolated(unsafe) static var cerradas: Set<String> = []

    func widgetCalendario(_ r: CGRect) {
        let est = dia
        let pad = Pintor.wPad
        let hoy = Date()
        let vista = VistaCalendario.elegida
        var y = wCabeceraDe(r, rotulo: "calendario · \(DateKit.cap(DateKit.monthYear.string(from: hoy)))",
                            sub: nil,
                            alDia: est.eventos.alDia, vara: Cronista.varaCalendario,
                            fallo: est.eventos.fallo)
        pintarConmutador(r, elemento: Pintor.elementoEnCurso)

        let eventos = est.eventos.valor ?? []
        // BANDA AHORA/SIGUE — la respuesta de tres segundos. El referente de
        // sfcal obliga a buscar la línea del ahora entre siete columnas; aquí
        // se dice con letra.
        y = bandaAhora(r, y: y, eventos: eventos, hoy: hoy)

        let rejilla = CGRect(x: r.minX + pad, y: y + 10, width: r.width - pad * 2, height: r.maxY - y - pad - 10)
        guard rejilla.height > 80 else { return }
        if est.eventos.valor == nil {
            wTexto("sin lectura del calendario — no se pinta un día vacío como si fuera un día libre",
                   CGPoint(x: rejilla.minX, y: rejilla.minY + 12), tam: 19, peso: 600, color: tema.pieTexto)
            return
        }
        if vista == .mes { rejillaMes(rejilla, eventos: eventos, hoy: hoy) }
        else { rejillaHoras(rejilla, eventos: eventos, hoy: hoy, dias: vista.dias(hoy)) }
    }

    /// Qué toca AHORA y qué sigue. Sale de los eventos reales de hoy.
    private func bandaAhora(_ r: CGRect, y: Double, eventos: [CalEvent], hoy: Date) -> Double {
        let pad = Pintor.wPad
        let deHoy = eventos.filter { DateKit.isToday($0.start) && !$0.isAllDay && $0.status != "cancelled" }
            .sorted { $0.start < $1.start }
        let ahora = deHoy.first { $0.start <= hoy && $0.end > hoy }
        let sigue = deHoy.first { $0.start > hoy }
        let alto = 112.0
        let caja = CGRect(x: r.minX + pad, y: y, width: r.width - pad * 2, height: alto)
        wCaja(caja, radio: 8, relleno: tema.rol("sticky").relleno, trazo: nil)
        // El filo neón: es la única cosa del widget que grita, y grita AHORA.
        wCaja(CGRect(x: caja.minX, y: caja.minY, width: 6, height: caja.height), radio: 3,
              relleno: tema.acento)

        let x = caja.minX + 20
        wTexto("AHORA", CGPoint(x: x, y: caja.minY + 16), tam: 17, peso: 800,
               color: tema.acento, mono: true, kern: 1.8)
        if let a = ahora {
            let queda = Int(a.end.timeIntervalSince(hoy) / 60)
            let cola = queda >= 60 ? "queda \(queda / 60)h \(queda % 60)m" : "queda \(queda)m"
            let anchoCola = wAncho(cola, tam: 19, peso: 700, mono: true)
            wTexto(wCortar(a.summary, ancho: caja.width - 110 - anchoCola - 34, tam: 31, peso: 800),
                   CGPoint(x: x + 88, y: caja.minY + 8), tam: 31, peso: 800, color: tema.tituloTexto)
            wTexto(cola, CGPoint(x: caja.maxX - 22 - anchoCola, y: caja.minY + 16),
                   tam: 19, peso: 700, color: tema.pieTexto, mono: true)
        } else {
            wTexto("nada agendado en este momento", CGPoint(x: x + 88, y: caja.minY + 12),
                   tam: 26, peso: 600, color: tema.pieTexto)
        }
        wTexto("SIGUE", CGPoint(x: x, y: caja.minY + 66), tam: 17, peso: 800,
               color: tema.pieTexto, mono: true, kern: 1.8)
        if let s = sigue {
            let h = DateKit.timeShort.string(from: s.start)
            wTexto(h, CGPoint(x: x + 88, y: caja.minY + 62), tam: 22, peso: 800,
                   color: tema.cuerpoTexto, mono: true)
            wTexto(wCortar(s.summary, ancho: caja.width - 250, tam: 23, peso: 600),
                   CGPoint(x: x + 88 + wAncho("00:00", tam: 22, peso: 800, mono: true) + 16,
                           y: caja.minY + 64),
                   tam: 23, peso: 600, color: tema.cuerpoTexto)
        } else {
            wTexto("nada más hoy", CGPoint(x: x + 88, y: caja.minY + 64), tam: 23, peso: 600,
                   color: tema.pieTexto)
        }
        return caja.maxY + 12
    }

    /// El color del calendario de un evento, del propio Google. Es el único
    /// sitio donde entra un color ajeno, y entra como FILO (no como relleno):
    /// la regla de la paleta reducida sigue mandando en el fondo.
    private func filoDe(_ e: CalEvent) -> NSColor {
        guard let c = dia.calendarios.first(where: { $0.id == e.calendarId }),
              let col = NSColor(hex: c.bgColorHex) else { return tema.acento }
        return col
    }

    private func esObjetivo(_ e: CalEvent) -> Bool {
        dia.calendarios.first { $0.id == e.calendarId }?.isObjetivo ?? false
    }

    // ── vista de horas (7d · 4d · 1d) ───────────────────────────────────────

    static func tareasCalendario(_ tareas: [TareaDia], dia: Date) -> [TareaDia] {
        tareas.filter { $0.dia == GDate.formatDay(dia) && !cerradas.contains($0.id) }
            .sorted { ($0.hora ?? "", $0.prioridad, $0.contenido) < ($1.hora ?? "", $1.prioridad, $1.contenido) }
    }

    private func rejillaHoras(_ r: CGRect, eventos: [CalEvent], hoy: Date, dias: [Date]) {
        guard let d0 = dias.first, let dN = dias.last else { return }
        let finVentana = DateKit.addDays(dN, 1)
        let visibles = eventos.filter {
            !$0.isAllDay && $0.status != "cancelled" && !esObjetivo($0)
                && $0.end > d0 && $0.start < finVentana
        }
        // La ventana de horas se AJUSTA a lo que hay. Un 0–24 fijo dedica media
        // rejilla a horas en las que nunca pasa nada, y encoge lo que sí pasa.
        var h0 = 24.0, h1 = 0.0
        for e in visibles {
            h0 = min(h0, floor(DateKit.minutesIntoDay(e.start) / 60))
            h1 = max(h1, ceil(DateKit.minutesIntoDay(e.end) / 60))
        }
        if h0 > h1 { h0 = 5; h1 = 22 }
        h0 = max(0, min(h0, 8)); h1 = min(24, max(h1, h0 + 8))
        let horas = h1 - h0

        let gutter = 62.0
        let tareas = (dia.tareas.valor ?? []).filter {
            dia.filtro.deja(frente: $0.frenteId, prioridad: $0.prioridad, etiquetas: $0.etiquetas, dia: $0.dia)
        }
        let filasTareas = min(3, dias.map { Self.tareasCalendario(tareas, dia: $0).count }.max() ?? 0)
        let altoTareas = filasTareas > 0 ? Double(filasTareas) * 27 + 12 : 0
        let cabDias = 44.0 + altoTareas
        let x0 = r.minX + gutter
        let anchoCol = (r.width - gutter) / Double(dias.count)
        let top = r.minY + cabDias
        let alto = r.height - cabDias
        let porHora = alto / horas

        // ── cabecera de días
        for (i, d) in dias.enumerated() {
            let cx = x0 + Double(i) * anchoCol
            let esHoy = DateKit.isSameDay(d, hoy)
            let dow = DateKit.weekdayShort.string(from: d).replacingOccurrences(of: ".", with: "")
            let num = DateKit.dayNum.string(from: d)
            let wDow = wAncho(dow, tam: 18, peso: 700, mono: false)
            let wNum = wAncho(num, tam: 22, peso: 800, mono: false)
            let ancho = wDow + 10 + wNum
            let ix = cx + (anchoCol - ancho) / 2
            wTexto(dow, CGPoint(x: ix, y: r.minY + 10), tam: 18, peso: 700,
                   color: esHoy ? tema.acento : tema.pieTexto)
            if esHoy {
                let d0x = ix + wDow + 10
                wCaja(CGRect(x: d0x - 8, y: r.minY + 5, width: wNum + 16, height: 30), radio: 15,
                      relleno: tema.acento)
            }
            wTexto(num, CGPoint(x: ix + wDow + 10, y: r.minY + 7), tam: 22, peso: 800,
                   color: esHoy ? .white : tema.tituloTexto)
            if esHoy {
                // La columna de hoy vive sobre un suelo propio: se encuentra sin
                // buscar el círculo morado.
                wCaja(CGRect(x: cx, y: top, width: anchoCol, height: alto), radio: 0,
                      relleno: tema.acento.withAlphaComponent(tema.nombre == "oscuro" ? 0.07 : 0.05))
            }
        }

        // Misma fuente Todoist que la lista. Fecha sin hora sigue siendo día,
        // nunca se convierte en una cita ficticia a medianoche.
        if filasTareas > 0 {
            wTexto("tareas", CGPoint(x:r.minX+3,y:r.minY+48),tam:12,peso:600,color:tema.pieTexto)
            for (i,d) in dias.enumerated() {
                let lista = Self.tareasCalendario(tareas, dia:d)
                let cx = x0 + Double(i)*anchoCol
                for (j,t) in lista.prefix(3).enumerated() {
                    let caja = CGRect(x:cx+3,y:r.minY+44+Double(j)*27,width:anchoCol-6,height:24)
                    wCaja(caja,radio:4,relleno:tema.acento.withAlphaComponent(0.05),trazo:tema.acento.withAlphaComponent(0.4),grosor:1)
                    let prefijo = t.hora.map { $0+" · " } ?? ""
                    let extra = j == 2 && lista.count > 3 ? " (+\(lista.count-3))" : ""
                    wTexto(wCortar("○ "+prefijo+t.contenido+extra,ancho:caja.width-10,tam:12,peso:600),CGPoint(x:caja.minX+5,y:caja.minY+4),tam:12,peso:600,color:tema.tituloTexto)
                }
            }
        }

        // ── rejilla de horas
        ctx.setLineDash(phase: 0, lengths: [])
        for k in 0...Int(horas) {
            let y = top + Double(k) * porHora
            ctx.setStrokeColor(tema.reticula.cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: r.maxX, y: y))
            ctx.strokePath()
            if k < Int(horas) {
                let et = String(format: "%02.0f", h0 + Double(k))
                wTexto(et, CGPoint(x: r.minX + 12, y: y + 4), tam: 18, peso: 700,
                       color: tema.pieTexto, mono: true)
            }
        }
        for i in 0...dias.count {
            let x = x0 + Double(i) * anchoCol
            ctx.setStrokeColor(tema.reticula.cgColor); ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: x, y: top)); ctx.addLine(to: CGPoint(x: x, y: top + alto))
            ctx.strokePath()
        }

        // ── bloques
        for (i, d) in dias.enumerated() {
            let finDia = DateKit.addDays(d, 1)
            let delDia = visibles.filter { $0.end > d && $0.start < finDia }
            let sitios = OverlapLayout.layout(delDia.map { LayoutItem(id: $0.id, start: $0.start, end: $0.end) })
            let cx = x0 + Double(i) * anchoCol
            for e in delDia {
                let s = e.start < d ? 0 : DateKit.minutesIntoDay(e.start)
                var f = e.end > finDia ? 1440 : DateKit.minutesIntoDay(e.end)
                if f <= s { f = 1440 }
                let yTop = top + (s / 60 - h0) * porHora
                let yBot = top + (f / 60 - h0) * porHora
                guard yBot > top, yTop < top + alto else { continue }
                let pos = sitios[e.id]
                let n = Double(pos?.columnCount ?? 1), col = Double(pos?.column ?? 0)
                let w = (anchoCol - 6) / n
                let caja = CGRect(x: cx + 3 + col * w, y: max(yTop, top) + 1.5,
                                  width: w - 3, height: max(min(yBot, top + alto) - max(yTop, top) - 3, 14))
                bloqueEvento(e, caja, ahora: hoy, compacto: caja.height < 46 || vistaCompacta(anchoCol))
            }
        }

        // ── la línea del AHORA, encima de todo
        if let i = dias.firstIndex(where: { DateKit.isSameDay($0, hoy) }) {
            let m = DateKit.minutesIntoDay(hoy)
            let y = top + (m / 60 - h0) * porHora
            if y > top && y < top + alto {
                ctx.setStrokeColor(tema.acento.cgColor)
                ctx.setLineWidth(3)
                ctx.setLineDash(phase: 0, lengths: [])
                ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: r.maxX, y: y))
                ctx.strokePath()
                let cx = x0 + Double(i) * anchoCol
                ctx.setFillColor(tema.acento.cgColor)
                ctx.fillEllipse(in: CGRect(x: cx - 7, y: y - 7, width: 14, height: 14))
                let et = DateKit.timeShort.string(from: hoy)
                let w = wAncho(et, tam: 16, peso: 800, mono: true)
                wCaja(CGRect(x: r.minX + 6, y: y - 13, width: w + 14, height: 26), radio: 6,
                      relleno: tema.acento)
                wTexto(et, CGPoint(x: r.minX + 13, y: y - 9), tam: 16, peso: 800, color: .white, mono: true)
            }
        }
    }

    private func vistaCompacta(_ anchoCol: Double) -> Bool { anchoCol < 210 }

    private func bloqueEvento(_ e: CalEvent, _ caja: CGRect, ahora: Date, compacto: Bool) {
        let vivo = e.start <= ahora && e.end > ahora
        let pasado = e.end <= ahora
        let filo = filoDe(e)
        /*
         * ⚠️ ESPEJO FIEL: el bloque va RELLENO del color de su calendario.
         *
         * La primera versión lo pintó neutro con un filo de color, razonando
         * desde la "paleta reducida" del estándar. Daniel lo corrigió el 25
         * ago: *"al ser esto un espejo asegúrate que se conserven los colores
         * del calendario, tipografía tal cual como en la otra vista"*.
         *
         * Y tiene razón por encima de la regla: la paleta reducida existe para
         * que el color no decore en un DIAGRAMA. Aquí el color no decora — es
         * el mismo código de color con el que él lee su semana en sfcal desde
         * hace meses (lila = rutina, gris = bloques de trabajo, rosa = cuerpo,
         * verde agua = clases). Un espejo que reordena los colores del original
         * obliga a aprender dos idiomas para el mismo día.
         *
         * El alfa lo pone el TEMA, no un literal: sobre negro el mismo pastel
         * de sfcal se comería el texto, así que en oscuro entra tenue y en
         * claro casi pleno — el color es el mismo, cambia cuánto.
         */
        let oscuro = tema.nombre == "oscuro"
        let alfa = (pasado ? 0.55 : 1.0) * (oscuro ? 0.30 : 0.45)
        wCaja(caja, radio: 6, relleno: filo.withAlphaComponent(alfa),
              trazo: vivo ? tema.acento : filo.withAlphaComponent(oscuro ? 0.55 : 0.75),
              grosor: vivo ? 3 : 1)
        // El filo IZQUIERDO, más grueso: es el ancla de color de sfcal.
        wCaja(CGRect(x: caja.minX, y: caja.minY, width: 5, height: caja.height), radio: 2.5,
              relleno: pasado ? filo.withAlphaComponent(0.5) : filo)

        let colTit = pasado ? tema.cuerpoTexto : tema.tituloTexto
        let pad = 12.0
        let anchoTxt = caja.width - pad - 8
        guard anchoTxt > 30 else { return }
        ctx.saveGState()
        ctx.clip(to: caja.insetBy(dx: 2, dy: 1))
        defer { ctx.restoreGState() }
        let tam = min(compacto ? 14.0 : 17.0, max(9, caja.height - 7))
        // Cuántas líneas caben de verdad: el título se ENVUELVE antes que
        // truncarse (lo pidió un crítico ciego el 25 ago viendo cómo
        // «Videollamada Semanal — Prod…» perdía justo el sustantivo).
        let cabenLineas = max(1, min(2, Int((caja.height - 26) / (tam + 3))))
        let filas = wEnvolver(e.summary, ancho: anchoTxt, tam: tam, peso: 700, lineas: cabenLineas)
        for (i, f) in filas.enumerated() {
            wTexto(f, CGPoint(x: caja.minX + pad, y: caja.minY + 5 + Double(i) * (tam + 3)),
                   tam: tam, peso: 700, color: colTit)
        }
        let usado = Double(filas.count - 1) * (tam + 3)
        if caja.height > tam + 26 + usado {
            let h = "\(DateKit.timeShort.string(from: e.start))–\(DateKit.timeShort.string(from: e.end))"
            wTexto(h, CGPoint(x: caja.minX + pad, y: caja.minY + tam + 8 + usado), tam: 15, peso: 600,
                   color: tema.pieTexto, mono: true)
        }
        // EN 1 DÍA la columna es ancha y el bloque queda casi vacío: ahí SÍ cabe
        // lo que Daniel escribió en el evento. Es lo que hace que la vista de un
        // día sea otra cosa y no la de siete con menos columnas.
        if caja.width > 700, caja.height > 74 + usado {
            let nota = MonkMode.limpiarNota(e.notes)
            if !nota.isEmpty {
                let una = nota.split(separator: "\n").first.map(String.init) ?? nota
                wTexto(wCortar(una, ancho: anchoTxt, tam: 17, peso: 500),
                       CGPoint(x: caja.minX + pad, y: caja.minY + tam + 30 + usado), tam: 17, peso: 500,
                       color: tema.pieTexto)
            }
            if let loc = e.location, !loc.isEmpty {
                wTexto(wCortar("· \(loc)", ancho: anchoTxt, tam: 15, peso: 500),
                       CGPoint(x: caja.minX + pad, y: caja.minY + tam + 52 + usado), tam: 15, peso: 500,
                       color: tema.pieTexto, mono: true)
            }
        }
    }

    // ── vista de mes ────────────────────────────────────────────────────────

    private func rejillaMes(_ r: CGRect, eventos: [CalEvent], hoy: Date) {
        let dias = DateKit.monthGrid(hoy)
        let cabDias = 34.0
        let anchoCol = r.width / 7
        let top = r.minY + cabDias
        let altoFila = (r.height - cabDias) / 6
        let mesActual = DateKit.cal.component(.month, from: hoy)

        for i in 0..<7 {
            let dow = DateKit.weekdayShort.string(from: dias[i]).replacingOccurrences(of: ".", with: "").uppercased()
            let w = wAncho(dow, tam: 16, peso: 800, mono: true)
            wTexto(dow, CGPoint(x: r.minX + Double(i) * anchoCol + (anchoCol - w) / 2, y: r.minY + 6),
                   tam: 16, peso: 800, color: tema.pieTexto, mono: true, kern: 1.4)
        }
        for (k, d) in dias.enumerated() {
            let cx = r.minX + Double(k % 7) * anchoCol
            let cy = top + Double(k / 7) * altoFila
            let celda = CGRect(x: cx, y: cy, width: anchoCol, height: altoFila)
            let esHoy = DateKit.isSameDay(d, hoy)
            let delMes = DateKit.cal.component(.month, from: d) == mesActual
            wCaja(celda.insetBy(dx: 1, dy: 1), radio: 4,
                  relleno: esHoy ? tema.acento.withAlphaComponent(tema.nombre == "oscuro" ? 0.12 : 0.08) : nil,
                  trazo: tema.reticula, grosor: 1)
            let num = DateKit.dayNum.string(from: d)
            wTexto(num, CGPoint(x: celda.minX + 9, y: celda.minY + 5), tam: 18,
                   peso: esHoy ? 800 : 600,
                   color: esHoy ? tema.acento : (delMes ? tema.cuerpoTexto : tema.reticula))
            let finDia = DateKit.addDays(d, 1)
            let delDia = eventos.filter {
                !$0.isAllDay && $0.status != "cancelled" && !esObjetivo($0)
                    && $0.end > d && $0.start < finDia
            }.sorted { $0.start < $1.start }
            let sitio = Int((altoFila - 30) / 22)
            for (j, e) in delDia.prefix(max(sitio, 0)).enumerated() {
                let y = celda.minY + 28 + Double(j) * 22
                wCaja(CGRect(x: celda.minX + 8, y: y, width: 4, height: 15), radio: 2, relleno: filoDe(e))
                wTexto(wCortar(e.summary, ancho: anchoCol - 28, tam: 15, peso: 600),
                       CGPoint(x: celda.minX + 18, y: y - 1), tam: 15, peso: 600,
                       color: delMes ? tema.cuerpoTexto : tema.pieTexto)
            }
            if delDia.count > max(sitio, 0) {
                wTexto("+\(delDia.count - max(sitio, 0))",
                       CGPoint(x: celda.minX + 18, y: celda.maxY - 22), tam: 14, peso: 700,
                       color: tema.pieTexto, mono: true)
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: - 2. MONK MODE
    // ════════════════════════════════════════════════════════════════════════

    func widgetMonk(_ r: CGRect) {
        let est = dia
        let pad = Pintor.wPad
        let hoy = Date()
        let n = MonkMode.dayNumber(hoy)
        let quedan = MonkMode.totalDays - n
        let oro = tema.tintes["ambar"]?.trazo ?? tema.acento

        // La frescura del rótulo sale del CALENDARIO, que es de donde salen la
        // rutina y el objetivo (el 80% de lo que se lee aquí). Colgarla de los
        // hábitos hacía que el widget entero se declarara «sin dato» por una
        // sección que sí sabe decir lo suyo: una alarma que exagera se ignora.
        var y = wCabeceraDe(r, rotulo: "monk mode", sub: nil,
                            alDia: est.eventos.alDia, vara: Cronista.varaCalendario,
                            fallo: est.eventos.fallo)

        // ── DÍA N de 90 + la barra de los 90 días.
        // El referente enseña el número; la BARRA enseña el arco, que es lo que
        // el número no puede decir: cuánto se lleva y cuánto queda, de un ojo.
        let sN = "\(n)"
        let wN = wAncho(sN, tam: 62, peso: 800, mono: false)
        wTexto("DÍA", CGPoint(x: r.minX + pad, y: y + 20), tam: 20, peso: 800,
               color: tema.pieTexto, mono: true, kern: 2)
        wTexto(sN, CGPoint(x: r.minX + pad + 54, y: y - 2), tam: 62, peso: 800, color: oro)
        wTexto("de \(MonkMode.totalDays)", CGPoint(x: r.minX + pad + 54 + wN + 12, y: y + 30),
               tam: 20, peso: 700, color: tema.pieTexto, mono: true)
        let fin = DateKit.dayMonth.string(from: MonkMode.end)
        let cola = "quedan \(quedan) · termina \(fin)"
        let wc = wAncho(cola, tam: 17, peso: 600, mono: true)
        wTexto(cola, CGPoint(x: r.maxX - pad - wc, y: y + 30), tam: 17, peso: 600,
               color: tema.pieTexto, mono: true)
        y += 76
        let barra = CGRect(x: r.minX + pad, y: y, width: r.width - pad * 2, height: 12)
        wCaja(barra, radio: 6, relleno: tema.rol("sticky").relleno)
        let frac = max(0, min(1, Double(n) / Double(MonkMode.totalDays)))
        wCaja(CGRect(x: barra.minX, y: barra.minY, width: barra.width * frac, height: barra.height),
              radio: 6, relleno: oro)
        y += 34

        // ── EL OBJETIVO DEL DÍA (calendario "Objetivo del día", nivel DÍA)
        y = seccionRotulo(r, y: y, texto: "el objetivo del día")
        // El objetivo de nivel DÍA que cubre hoy. Misma selección que hace
        // `EventStore.objetivos(covering:)` en sfcal, con el MISMO
        // `nivelObjetivo` (núcleo compartido): dos clasificaciones del mismo
        // calendario acabarían señalando objetivos distintos en dos pantallas.
        let inicioHoy = DateKit.startOfDay(hoy)
        let finHoy = DateKit.addDays(inicioHoy, 1)
        let objetivos = (est.eventos.valor ?? []).filter { ev in
            guard let c = dia.calendarios.first(where: { $0.id == ev.calendarId }) else { return false }
            return c.isObjetivo && c.nivelObjetivo == "DÍA" && ev.start < finHoy && ev.end > inicioHoy
        }
        let cajaObj = CGRect(x: r.minX + pad, y: y, width: r.width - pad * 2, height: 76)
        // ⚠️ EL CLARO NECESITA MÁS, no lo mismo. Con el mismo 10% de oro, en
        // tema claro esta tarjeta —el aviso de más consecuencia del tablero—
        // salía crema sobre blanco y se fundía con la página: la alarma perdía
        // su urgencia justo en el turno en que más se mira. El alfa que hace
        // "tenue" sobre negro hace "invisible" sobre blanco.
        let oscuro = tema.nombre == "oscuro"
        wCaja(cajaObj, radio: 8, relleno: oro.withAlphaComponent(oscuro ? 0.12 : 0.20),
              trazo: oro.withAlphaComponent(oscuro ? 0.55 : 0.95), grosor: oscuro ? 1.5 : 2.5)
        estrella(CGPoint(x: cajaObj.minX + 24, y: cajaObj.minY + 26), r: 11, color: oro)
        if let o = objetivos.first {
            wTexto(wCortar(o.summary, ancho: cajaObj.width - 66, tam: 23, peso: 800),
                   CGPoint(x: cajaObj.minX + 44, y: cajaObj.minY + 14), tam: 23, peso: 800,
                   color: tema.tituloTexto)
            if let nota = MonkMode.limpiarNota(o.notes) as String?, !nota.isEmpty {
                wTexto(wCortar(nota, ancho: cajaObj.width - 66, tam: 17, peso: 500),
                       CGPoint(x: cajaObj.minX + 44, y: cajaObj.minY + 44), tam: 17, peso: 500,
                       color: tema.pieTexto)
            }
        } else {
            wTexto("Sin objetivo firmado para hoy", CGPoint(x: cajaObj.minX + 44, y: cajaObj.minY + 14),
                   tam: 23, peso: 800, color: tema.tituloTexto)
            wTexto("Un día sin objetivo se gasta solo. Díctamelo y lo agendo.",
                   CGPoint(x: cajaObj.minX + 44, y: cajaObj.minY + 44), tam: 17, peso: 500,
                   color: tema.pieTexto)
        }
        y = cajaObj.maxY + 20

        // ── LA RUTINA de hoy, con el ahora marcado
        let bloques = MonkMode.bloquesDeHoy(
            eventos: (est.eventos.valor ?? []).filter { DateKit.isToday($0.start) && !esObjetivo($0) },
            date: hoy)
        y = seccionRotulo(r, y: y, texto: "la rutina · hoy")
        let m = DateKit.minutesIntoDay(hoy)
        /*
         * ⚠️ EL REPARTO SE NEGOCIA, NO SE RESERVA A CIEGAS.
         *
         * La versión anterior le reservaba a LOS HÁBITOS su alto ideal
         * (8 × 34 + 40 = 312) y le daba a la rutina lo que sobrara. Al recortar
         * el widget un tercio, "lo que sobraba" salió NEGATIVO: la rutina
         * desapareció entera —un hueco en blanco donde iba el día— y los
         * hábitos se cortaron en el quinto. Se veía roto sin que nada fallara.
         *
         * Ahora las dos listas piden lo suyo y, si no cabe, **las dos ceden a la
         * vez** en proporción. Reservar en firme para uno y dejar al otro el
         * resto es lo que convierte "no cabe" en "desapareció".
         */
        let nBloques = max(bloques.count, 1)
        let pideRutina = Double(nBloques) * 38
        let pideHab = Double(Habitos.todos.count) * 30 + 34
        let hay = r.maxY - pad - y
        let ajuste = min(1.0, hay / max(1, pideRutina + pideHab))
        let hHab = pideHab * ajuste
        let hFila = max(20.0, min(46.0, (pideRutina * ajuste) / Double(nBloques)))
        for (i, b) in bloques.enumerated() {
            let fy = y + Double(i) * hFila
            guard fy + hFila <= r.maxY - pad - hHab else { break }
            let vivo = b.desde <= m && b.hasta > m
            let pasado = b.hasta <= m
            if vivo {
                wCaja(CGRect(x: r.minX + pad - 6, y: fy - 2, width: Double(r.width) - pad * 2 + 12, height: hFila),
                      radio: 6, relleno: tema.acento.withAlphaComponent(tema.nombre == "oscuro" ? 0.16 : 0.10))
                wCaja(CGRect(x: r.minX + pad - 6, y: fy - 2, width: 4, height: hFila), radio: 2,
                      relleno: tema.acento)
            }
            // ⚠️ El pasado se ATENÚA, no se borra. Con `reticula` sobre el fondo
            // oscuro la primera fila del día quedaba invisible: un bloque que ya
            // pasó sigue siendo información (dice por dónde vas).
            let apagado = tema.pieTexto.withAlphaComponent(0.5)
            let col = vivo ? tema.tituloTexto : (pasado ? apagado : tema.cuerpoTexto)
            wTexto(b.hora, CGPoint(x: r.minX + pad + 6, y: fy + 6), tam: 16, peso: 700,
                   color: pasado ? apagado : tema.pieTexto, mono: true)
            let wh = 118.0
            wTexto(wCortar(b.titulo, ancho: r.width - pad * 2 - wh - 12, tam: 19,
                           peso: vivo ? 800 : 600),
                   CGPoint(x: r.minX + pad + wh, y: fy + 4), tam: 19, peso: vivo ? 800 : 600, color: col)
        }
        y += Double(bloques.count) * hFila + 18

        // ── LOS HÁBITOS — en COLUMNA, con su nombre.
        //
        // La primera versión los puso en una fila de ocho casillas: cabía, pero
        // los rótulos salían a 12pt y a los zooms de trabajo eran una mancha.
        // Un hábito que no se puede leer no se puede consultar, y entonces la
        // casilla decora. En vertical caben con su nombre entero, que es como
        // están en la pared impresa y en sfcal.
        let hab = est.habitos.valor
        let hechos = hab.map { h in Habitos.todos.filter { h.marcas[$0.clave] == .hecho }.count }
        y = seccionRotulo(r, y: y, texto: "los hábitos · hoy",
                          derecha: hechos.map { "\($0)/\(Habitos.todos.count)" } ?? "sin registro")
        let hFilaHab = max(19.0, min(34.0, (r.maxY - pad - y) / Double(Habitos.todos.count)))
        for (i, h) in Habitos.todos.enumerated() {
            let fy = y + Double(i) * hFilaHab
            guard fy + hFilaHab <= r.maxY - pad else { break }
            let lado = min(20.0, hFilaHab - 8)
            let celda = CGRect(x: r.minX + pad, y: fy + (hFilaHab - lado) / 2 - 2, width: lado, height: lado)
            switch hab?.marcas[h.clave] {
            case .hecho:
                wCaja(celda, radio: 4, relleno: oro)
                palomita(CGRect(x: celda.midX - 6, y: celda.midY - 5, width: 12, height: 11),
                         color: tema.nombre == "oscuro" ? .black : .white)
            case .fallado:
                wCaja(celda, radio: 4, relleno: nil, trazo: tema.tintes["rojo"]?.trazo, grosor: 2)
                equis(celda.insetBy(dx: 5, dy: 5), color: tema.tintes["rojo"]?.etiqueta ?? .red)
            case .none:
                // Sin lectura del archivo: RAYA, no casilla vacía. Una casilla
                // vacía afirma "no lo hizo"; la raya dice "no lo sé". Los dos se
                // pintan igual de fácil y solo uno es verdad.
                let sinArchivo = hab == nil
                wCaja(celda, radio: 4, relleno: nil,
                      trazo: sinArchivo ? tema.reticula : tema.rol("card").trazo.color,
                      grosor: sinArchivo ? 1 : 1.5)
                if sinArchivo {
                    ctx.setStrokeColor(tema.reticula.cgColor); ctx.setLineWidth(1.5)
                    ctx.move(to: CGPoint(x: celda.midX - 5, y: celda.midY))
                    ctx.addLine(to: CGPoint(x: celda.midX + 5, y: celda.midY)); ctx.strokePath()
                }
            }
            // Los tres NO NEGOCIABLES llevan su estrella: es la jerarquía que la
            // hoja impresa marca y que un listado plano pierde.
            var tx = celda.maxX + 12
            if h.estrella { estrella(CGPoint(x: tx + 6, y: celda.midY), r: 6.5, color: oro); tx += 19 }
            wTexto(wCortar(h.nombre, ancho: r.maxX - pad - tx, tam: 18, peso: h.estrella ? 700 : 600),
                   CGPoint(x: tx, y: fy + (hFilaHab - 22) / 2),
                   tam: 18, peso: h.estrella ? 700 : 600,
                   color: hab?.marcas[h.clave] == .hecho ? tema.tituloTexto : tema.cuerpoTexto)
        }
        if hab == nil {
            wTexto("sin registro en esta máquina · ~/.sfcal/habitos.json",
                   CGPoint(x: r.minX + pad, y: y + hFilaHab * Double(Habitos.todos.count) + 6),
                   tam: 14, peso: 600, color: tema.pieTexto, mono: true)
        }
        y += hFilaHab * Double(Habitos.todos.count) + (hab == nil ? 40 : 20)

        // ── LO QUE VIENE — las fechas del programa, con los días que faltan.
        //
        // Es lo que un panel de 90 días tiene que decir y el número solo no
        // dice: hacia QUÉ se está componiendo. Sale del núcleo compartido
        // (`MonkMode.fechas`), así que siempre hay dato — y llena con sentido
        // el hueco que dejaba un día de pocos bloques, en vez de dejar negro.
        let futuras = MonkMode.fechas.compactMap { f -> (String, String, Int)? in
            guard let d = DateKit.cal.date(from: f.comps) else { return nil }
            let faltan = DateKit.cal.dateComponents([.day], from: DateKit.startOfDay(hoy),
                                                    to: DateKit.startOfDay(d)).day ?? 0
            return faltan >= 0 ? (f.titulo, f.detalle, faltan) : nil
        }
        guard !futuras.isEmpty, r.maxY - pad - y > 60 else { return }
        y = seccionRotulo(r, y: y, texto: "lo que viene")
        for (t, det, faltan) in futuras.prefix(2) {
            guard y + 44 <= r.maxY - pad else { break }
            // El contador es lo que aprieta: "31 AGO" es una fecha, "faltan 6
            // días" es una cuenta atrás.
            let cuenta = faltan == 0 ? "HOY" : "faltan \(faltan)"
            let wc = wAncho(cuenta, tam: 16, peso: 800, mono: true)
            wTexto(t, CGPoint(x: r.minX + pad, y: y), tam: 19, peso: 800, color: oro, mono: true, kern: 0.8)
            wTexto(cuenta, CGPoint(x: r.maxX - pad - wc, y: y + 2), tam: 16, peso: 800,
                   color: faltan <= 7 ? oro : tema.pieTexto, mono: true)
            wTexto(wCortar(det, ancho: r.width - pad * 2, tam: 16, peso: 500),
                   CGPoint(x: r.minX + pad, y: y + 22), tam: 16, peso: 500, color: tema.cuerpoTexto)
            y += 48
        }
    }

    @discardableResult
    private func seccionRotulo(_ r: CGRect, y: Double, texto: String, derecha: String? = nil) -> Double {
        wTexto(texto.uppercased(), CGPoint(x: r.minX + Pintor.wPad, y: y), tam: 15, peso: 800,
               color: tema.pieTexto, mono: true, kern: 1.8)
        if let d = derecha {
            let w = wAncho(d, tam: 15, peso: 800, mono: true)
            wTexto(d, CGPoint(x: r.maxX - Pintor.wPad - w, y: y), tam: 15, peso: 800,
                   color: tema.cuerpoTexto, mono: true)
        }
        return y + 26
    }

    private func estrella(_ c: CGPoint, r rad: Double, color: NSColor) {
        let p = CGMutablePath()
        for i in 0..<10 {
            let a = -Double.pi / 2 + Double(i) * .pi / 5
            let rr = i % 2 == 0 ? rad : rad * 0.44
            let pt = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        ctx.addPath(p); ctx.setFillColor(color.cgColor); ctx.fillPath()
    }

    private func palomita(_ r: CGRect, color: NSColor) {
        ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(3); ctx.setLineCap(.round)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.move(to: CGPoint(x: r.minX, y: r.midY))
        ctx.addLine(to: CGPoint(x: r.minX + r.width * 0.36, y: r.maxY))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    private func equis(_ r: CGRect, color: NSColor) {
        ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(2.5); ctx.setLineCap(.round)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.move(to: CGPoint(x: r.minX, y: r.minY)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        ctx.move(to: CGPoint(x: r.maxX, y: r.minY)); ctx.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: - 4. EL TROFEO — el pacto del fierro
    // ════════════════════════════════════════════════════════════════════════

    /**
     * EL PACTO DEL FIERRO, visible todos los días.
     *
     * Daniel lo firmó en frío la mañana del 25 ago: *"dejémoslo en 15K MRR
     * mínimo de aquí a dos meses. Es el pacto, la meta, y como trofeo una
     * imagen del M5 Ultra 512GB en el panel."* Nace del diagnóstico del 20 ago
     * —*"tengo lo suficiente como para no tener la urgencia suficiente"*— así
     * que este widget ES el algedónico cercano que faltaba.
     *
     * ⚠️ TRES COSAS QUE ESTE WIDGET NO HACE, y las tres son el canónico:
     *
     * · No dice "inversión". Esa palabra está marcada en el pacto como el
     *   permiso que dejaría comprarla sin pegar el número.
     * · No tiene modo "casi". Si el 31 de octubre el MRR no llegó, no hay
     *   máquina y el widget lo dice sin suavizarlo.
     * · La barra NO nace en cero: nace en la BASE del día que se firmó
     *   ($8,220). Desde cero, el día uno ya iba por el 55% — una barra que
     *   nace medio llena no aprieta a nadie.
     */
    func widgetTrofeo(_ r: CGRect) {
        let est = dia
        let pad = Pintor.wPad
        let oro = tema.tintes["ambar"]?.trazo ?? tema.acento
        let hoy = Date()
        var y = wCabeceraDe(r, rotulo: "meta · ejemplo configurable", sub: nil,
                            alDia: est.mrr.alDia, vara: Cronista.varaMRR, fallo: est.mrr.fallo)

        // ── LA IMAGEN REAL del fierro. Es la mitad del punto: un número no da
        // ganas de nada, y el pacto existe para dar ganas.
        // Sobre una PLACA clara y deliberada: la foto de producto de Apple vive
        // sobre blanco, y recortarle el fondo a mano dejaba un halo dentado en
        // los cantos —peor que el marco—. Una placa con esquinas redondeadas
        // dice "esto es una foto de producto" y se acabó el problema.
        let hImg = min(r.height * 0.26, 230)
        let placa = CGRect(x: r.minX + pad, y: y + 4, width: r.width - pad * 2, height: hImg)
        // ⚠️ EN CLARO la placa necesita BORDE. Sobre la tarjeta blanca, una
        // placa blanca no tiene canto: el crítico midió que *"la foto se funde
        // con la tarjeta, no queda marco ni sombra que la separe"*. En oscuro
        // el contraste lo pone el fondo y el borde estorbaría.
        wCaja(placa, radio: 10, relleno: NSColor(hex: "#fafafa") ?? .white,
              trazo: tema.nombre == "claro" ? tema.rol("card").trazo.color : nil, grosor: 1.5)
        imagenDeArchivo(Pacto.imagen, en: placa.insetBy(dx: 10, dy: 10))
        let cajaImg = placa
        y = cajaImg.maxY + 14

        wTexto(Pacto.trofeo, CGPoint(x: r.minX + pad, y: y), tam: 24, peso: 800, color: tema.tituloTexto)
        y += 32
        wTexto(Pacto.gatillo.uppercased(), CGPoint(x: r.minX + pad, y: y), tam: 16, peso: 800,
               color: oro, mono: true, kern: 1.4)
        y += 30

        // ── EL PROGRESO. Sin dato del MRR no se pinta una barra a cero: una
        // barra vacía se lee como "no has avanzado nada", que es una medición.
        guard let serie = est.mrr.valor, let ultimo = serie.last else {
            wTexto("sin lectura del MRR — la barra no se pinta en cero",
                   CGPoint(x: r.minX + pad, y: y), tam: 17, peso: 600, color: tema.pieTexto)
            return
        }
        let avance = Pacto.avance(ultimo.mrr)
        let faltan = max(0, Pacto.meta - ultimo.mrr)
        let dias = Pacto.diasRestantes(hoy)

        let cifra = "$" + NumberFormatter.localizedString(
            from: NSNumber(value: Int(ultimo.mrr.rounded())), number: .decimal)
        wTexto(cifra, CGPoint(x: r.minX + pad, y: y), tam: 44, peso: 800, color: tema.tituloTexto, mono: true)
        let wMeta = wAncho("de $\(Int(Pacto.meta))", tam: 19, peso: 700, mono: true)
        wTexto("de $\(Int(Pacto.meta))", CGPoint(x: r.maxX - pad - wMeta, y: y + 22), tam: 19, peso: 700,
               color: tema.pieTexto, mono: true)
        y += 56

        // La barra, con la MARCA de la base: se ve de dónde arrancó el pacto.
        let barra = CGRect(x: r.minX + pad, y: y, width: r.width - pad * 2, height: 16)
        wCaja(barra, radio: 8, relleno: tema.rol("sticky").relleno)
        if avance > 0 {
            wCaja(CGRect(x: barra.minX, y: barra.minY, width: max(barra.width * avance, 10),
                         height: barra.height), radio: 8, relleno: oro)
        }
        y += 26
        let pct = Int((avance * 100).rounded())
        wTexto("\(pct)% desde la base del pacto (configurable)",
               CGPoint(x: r.minX + pad, y: y), tam: 15, peso: 600, color: tema.pieTexto, mono: true)
        y += 30

        // ── LO QUE FALTA, en las dos monedas que importan: dinero y días.
        let mitad = (r.width - pad * 2 - 14) / 2
        for (i, par) in [("FALTAN", "$" + NumberFormatter.localizedString(
                              from: NSNumber(value: Int(faltan.rounded())), number: .decimal)),
                         ("DÍAS", dias > 0 ? "\(dias)" : "SE ACABÓ")].enumerated() {
            let c = CGRect(x: r.minX + pad + Double(i) * (mitad + 14), y: y, width: mitad, height: 74)
            wCaja(c, radio: 8, relleno: tema.rol("sticky").relleno)
            wTexto(par.0, CGPoint(x: c.minX + 14, y: c.minY + 10), tam: 14, peso: 800,
                   color: tema.pieTexto, mono: true, kern: 1.6)
            // Los últimos 14 días el contador se pone en oro: es el tramo donde
            // el pacto se gana o se pierde.
            let urge = par.0 == "DÍAS" && dias <= 14
            wTexto(par.1, CGPoint(x: c.minX + 14, y: c.minY + 30), tam: 30, peso: 800,
                   color: urge ? oro : tema.tituloTexto, mono: true)
        }
        y += 88

        if y + 44 <= r.maxY - pad {
            wTexto("Si no se pega el número, no hay máquina. No se re-litiga.",
                   CGPoint(x: r.minX + pad, y: y), tam: 15, peso: 700, color: tema.pieTexto)
            wTexto("El delta lo genera el negocio; jamás los ahorros.",
                   CGPoint(x: r.minX + pad, y: y + 20), tam: 14, peso: 500,
                   color: tema.pieTexto.withAlphaComponent(0.75))
            y += 52
        }

        // ── LA SUBIDA Y LA PENDIENTE QUE HACE FALTA.
        //
        // La cifra dice dónde estás y la barra cuánto llevas; ninguna de las dos
        // dice si vas A TIEMPO. Esto sí: el trazo lleno es el MRR real de las
        // últimas semanas, y la línea punteada es la pendiente que hay que
        // sostener DESDE HOY para llegar a $15,000 el 31 de octubre.
        //
        // El eje X no son "los últimos N días": va de la historia reciente al
        // LÍMITE del pacto. Un gráfico que acaba hoy puede verse bien yendo
        // cuesta abajo; este pone el destino dentro del cuadro, así que la
        // distancia que falta se ve, no se calcula.
        guard r.maxY - pad - y > 110 else { return }
        y = seccionRotulo(r, y: y, texto: "la subida · y la pendiente que falta")
        let caja = CGRect(x: r.minX + pad, y: y, width: r.width - pad * 2,
                          height: r.maxY - pad - y - 22)
        let t0 = serie.first.flatMap { GDate.dayOnly.date(from: $0.dia) } ?? hoy
        let t1 = Pacto.fin
        let lo = min(Pacto.base, serie.map(\.mrr).min() ?? Pacto.base) - 150
        let hi = Pacto.meta + 400
        func py(_ v: Double) -> Double { caja.maxY - (v - lo) / max(1, hi - lo) * caja.height }
        func px(_ d: Date) -> Double {
            let f = d.timeIntervalSince(t0) / max(1, t1.timeIntervalSince(t0))
            return caja.minX + max(0, min(1, f)) * caja.width
        }

        // La META, arriba del todo.
        ctx.setStrokeColor(oro.withAlphaComponent(0.5).cgColor); ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [7, 5])
        ctx.move(to: CGPoint(x: caja.minX, y: py(Pacto.meta)))
        ctx.addLine(to: CGPoint(x: caja.maxX, y: py(Pacto.meta)))
        ctx.strokePath()
        wTexto("$\(Int(Pacto.meta)) · \(GDate.formatDay(Pacto.fin))", CGPoint(x: caja.minX + 4, y: py(Pacto.meta) + 4), tam: 13,
               peso: 700, color: oro.withAlphaComponent(0.85), mono: true)

        // LA PENDIENTE QUE FALTA: de donde estás HOY al gatillo.
        ctx.setStrokeColor(oro.withAlphaComponent(0.75).cgColor); ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [5, 6])
        ctx.move(to: CGPoint(x: px(hoy), y: py(ultimo.mrr)))
        ctx.addLine(to: CGPoint(x: px(t1), y: py(Pacto.meta)))
        ctx.strokePath()

        // El trazo REAL. Sin suavizar y sin rellenar los huecos: los días que
        // el sensor no midió NO están, y el trazo los salta.
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setStrokeColor(oro.cgColor); ctx.setLineWidth(3)
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        for (i, p) in serie.enumerated() {
            guard let d = GDate.dayOnly.date(from: p.dia) else { continue }
            let pt = CGPoint(x: px(d), y: py(p.mrr))
            i == 0 ? ctx.move(to: pt) : ctx.addLine(to: pt)
        }
        ctx.strokePath()
        ctx.setLineCap(.butt); ctx.setLineJoin(.miter)
        let fin = CGPoint(x: px(hoy), y: py(ultimo.mrr))
        ctx.setFillColor(oro.cgColor)
        ctx.fillEllipse(in: CGRect(x: fin.x - 5, y: fin.y - 5, width: 10, height: 10))
        // Y la línea de HOY, para saber dónde acaba lo medido y empieza lo que
        // falta por hacer.
        ctx.setStrokeColor(tema.reticula.cgColor); ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [3, 4])
        ctx.move(to: CGPoint(x: fin.x, y: caja.minY)); ctx.addLine(to: CGPoint(x: fin.x, y: caja.maxY))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        wTexto("hoy", CGPoint(x: fin.x + 6, y: caja.maxY - 18), tam: 13, peso: 700,
               color: tema.pieTexto, mono: true)
    }

    /// Una imagen del repo dentro de un widget. Reusa el mismo caché por ruta
    /// que las imágenes del lienzo, y encaja SIN deformar: estirar el producto
    /// de otro para que llene una caja es la forma más rápida de que se note
    /// que es un recorte.
    func imagenDeArchivo(_ ruta: String, en caja: CGRect) {
        let abs = Enlace.rutaDoc(ruta).path
        guard let img = Imagenes.de(abs, alLlegar: {}),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            wCaja(caja, radio: 8, relleno: tema.rol("sticky").relleno,
                  trazo: tema.rol("card").trazo.color, grosor: 1)
            wTexto("sin imagen del trofeo", CGPoint(x: caja.minX + 12, y: caja.midY - 8),
                   tam: 15, peso: 600, color: tema.pieTexto, mono: true)
            return
        }
        let prop = Double(cg.width) / Double(cg.height)
        var d = caja
        if caja.width / caja.height > prop {
            d.size.width = caja.height * prop
            d.origin.x = caja.midX - d.width / 2
        } else {
            d.size.height = caja.width / prop
            d.origin.y = caja.midY - d.height / 2
        }
        ctx.saveGState()
        ctx.translateBy(x: d.minX, y: d.minY + d.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: d.width, height: d.height))
        ctx.restoreGState()
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: - 3. TAREAS (Todoist)
    // ════════════════════════════════════════════════════════════════════════

    func widgetTareasHistorico(_ r: CGRect) {
        Pintor.casillasTarea.removeAll(keepingCapacity: true)
        let est = dia
        let pad = Pintor.wPad
        var y = wCabeceraDe(r, rotulo: "tareas · vía todoist", sub: nil,
                            alDia: est.tareas.alDia, vara: Cronista.varaTareas,
                            fallo: est.tareas.fallo)
        guard let tareas = est.tareas.valor else {
            wTexto("sin lectura de Todoist — cero tareas no es lo mismo que ninguna tarea",
                   CGPoint(x: r.minX + pad, y: y + 8), tam: 17, peso: 600, color: tema.pieTexto)
            return
        }

        // Clasificación IDÉNTICA a `query_todoist()` + el render de
        // `now-snapshot.py`: comparación de cadenas ISO, que para días es
        // barata y correcta. Dos clasificaciones distintas del mismo Todoist
        // serían dos respuestas a "¿qué sigue?".
        // ⚠️ EL MISMO FILTRO QUE LA CABINA, con la MISMA función. sfcal es
        // quien lo pone; aquí solo se obedece. Dos implementaciones del mismo
        // filtro acabarían enseñando listas distintas del mismo Todoist — que
        // es justo el desfase que costó la tarde de hoy.
        let filtro = est.filtro
        let visibles: [TareaDia] = tareas.filter {
            filtro.deja(frente: $0.frenteId, prioridad: $0.prioridad,
                        etiquetas: $0.etiquetas, dia: $0.dia)
        }
        let ocultas: Int = tareas.count - visibles.count
        let total: Int = tareas.count
        /*
         * ⚠️ MAÑANA ES SU PROPIO GRUPO (25 ago). Daniel: *"sabes diferenciar
         * entre hoy, mañana y próximos siete días"*. Antes, todo lo que no era
         * hoy caía en "esta semana", así que lo de mañana se perdía entre lo
         * del sábado — y el día que de verdad se planea por la noche es el
         * siguiente.
         *
         * ⚠️ Y la ventana ya no es "hasta el domingo" sino **7 días rodantes**:
         * con la semana del calendario, un viernes por la tarde "esta semana"
         * significaba dos días, y el lunes siguiente desaparecía de la vista.
         * Es la misma ventana que enseña sfcal.
         */
        let hoyISO = GDate.formatDay(Date())
        let mananaISO = GDate.formatDay(DateKit.addDays(Date(), 1))
        let finSemana = GDate.formatDay(DateKit.addDays(Date(), 7))
        let vencidas = visibles.filter { ($0.dia ?? "") < hoyISO && $0.dia != nil }
            .sorted { ($0.prioridad, $0.dia ?? "") < ($1.prioridad, $1.dia ?? "") }
        let deHoy = visibles.filter { $0.dia == hoyISO }
            .sorted { ($0.prioridad, $0.hora ?? "99") < ($1.prioridad, $1.hora ?? "99") }
        let deManana = visibles.filter { $0.dia == mananaISO }
            .sorted { ($0.prioridad, $0.hora ?? "99") < ($1.prioridad, $1.hora ?? "99") }
        let semana = visibles.filter { let d = $0.dia ?? ""; return d > mananaISO && d <= finSemana }
            .sorted { ($0.dia ?? "", $0.prioridad) < ($1.dia ?? "", $1.prioridad) }
        let proximas = visibles.filter { ($0.dia ?? "") > finSemana }
            .sorted { ($0.dia ?? "", $0.prioridad) < ($1.dia ?? "", $1.prioridad) }
        let backlog = visibles.filter { $0.dia == nil }

        // EL CONTADOR DE OCULTAS. No es opcional: un filtro que esconde en
        // silencio es la misma mentira que un cero sin medir — la lista se ve
        // corta y parece que no hay trabajo. (Lección del 25 ago, dos veces en
        // el mismo día.)
        if ocultas > 0 {
            let oro = tema.tintes["ambar"]?.trazo ?? tema.acento
            let et = "FILTRO DE SFCAL · \(ocultas) ocultas"
            wTexto(et, CGPoint(x: r.minX + pad, y: y - 4), tam: 15, peso: 800,
                   color: oro, mono: true, kern: 1.2)
            y += 24
        }
        let rojo = tema.tintes["rojo"]?.etiqueta ?? .red
        let grupos: [(String, [TareaDia], NSColor)] = [
            ("vencidas", vencidas, rojo),
            ("hoy", deHoy, tema.acento),
            ("mañana", deManana, tema.acento.withAlphaComponent(0.6)),
            ("próximos 7 días", semana, tema.pieTexto),
            ("próximas", proximas, tema.pieTexto),
        ]

        // ⚠️ LA ALTURA DE FILA SE REPARTE, no se fija.
        //
        // Una lista de tareas varía de 3 a 30 según el día. Con alto fijo, un
        // día flojo dejaba media tarjeta en negro —y un widget medio vacío se
        // lee como un widget roto, no como "tienes poco pendiente"—. Repartir
        // el sitio disponible entre las filas que HAY convierte el hueco en
        // aire. Con TOPE: sin él, tres tareas se volvían tres pancartas.
        let nGrupos = grupos.filter { !$0.1.isEmpty }.count
        let nFilas = grupos.reduce(0) { $0 + $1.1.count }
        let hBacklog = backlog.isEmpty ? 0.0 : 78.0
        let libre = r.maxY - pad - hBacklog - y - Double(nGrupos) * 38
        let hFila = nFilas > 0 ? max(58.0, min(82.0, libre / Double(nFilas))) : 62.0
        let hGrupo = 38.0
        for (nombre, lista, color) in grupos where !lista.isEmpty {
            guard y + hGrupo + hFila <= r.maxY - pad - hBacklog else { break }
            // Punto de color + rótulo + cuenta. El color solo en el punto: en
            // una lista de veinte líneas, veinte fondos de color es ruido.
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: r.minX + pad, y: y + 5, width: 10, height: 10))
            wTexto(nombre.uppercased(), CGPoint(x: r.minX + pad + 19, y: y), tam: 17, peso: 800,
                   color: nombre == "vencidas" ? rojo : tema.pieTexto, mono: true, kern: 1.8)
            let c = "\(lista.count)"
            let wc = wAncho(c, tam: 17, peso: 800, mono: true)
            wTexto(c, CGPoint(x: r.maxX - pad - wc, y: y), tam: 17, peso: 800,
                   color: tema.cuerpoTexto, mono: true)
            y += hGrupo
            for t in lista {
                guard y + hFila <= r.maxY - pad - hBacklog else { break }
                filaTarea(t, CGRect(x: r.minX + pad, y: y, width: r.width - pad * 2, height: hFila),
                          urgente: nombre == "vencidas")
                y += hFila
            }
            y += 8
        }
        // Todo escondido por el filtro NO es "cero pendientes".
        if visibles.isEmpty, total > 0 {
            wTexto("ninguna pasa el filtro de sfcal — tienes \(total)",
                   CGPoint(x: r.minX + pad, y: y + 8), tam: 18, peso: 700,
                   color: tema.tintes["ambar"]?.trazo ?? tema.pieTexto)
        }
        if !backlog.isEmpty {
            let by = r.maxY - pad - 52
            ctx.setStrokeColor(tema.reticula.cgColor); ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.move(to: CGPoint(x: r.minX + pad, y: by - 14))
            ctx.addLine(to: CGPoint(x: r.maxX - pad, y: by - 14)); ctx.strokePath()
            wTexto("\(backlog.count) SIN FECHA", CGPoint(x: r.minX + pad, y: by), tam: 16, peso: 800,
                   color: tema.pieTexto, mono: true, kern: 1.4)
            // El desglose POR FRENTE, igual que `now-snapshot.py`: sin él, "9
            // sin fecha" no dice dónde se está apilando la deuda de triaje.
            var porFrente: [String: Int] = [:]
            for t in backlog { porFrente[t.frente ?? "sin frente", default: 0] += 1 }
            let d = porFrente.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .map { "\($0.value) \($0.key)" }.joined(separator: "  ·  ")
            wTexto(wCortar(d, ancho: r.width - pad * 2, tam: 15, peso: 600, mono: true),
                   CGPoint(x: r.minX + pad, y: by + 22), tam: 15, peso: 600,
                   color: tema.pieTexto, mono: true)
            wTexto("se procesan en la revisión del domingo",
                   CGPoint(x: r.minX + pad, y: by + 42), tam: 14, peso: 500,
                   color: tema.pieTexto.withAlphaComponent(0.7), mono: true)
        }
    }

    func filaTarea(_ t: TareaDia, _ r: CGRect, urgente: Bool) {
        let pad = 4.0
        let hecha = Pintor.cerradas.contains(t.id)
        // ── LA CASILLA. Blanco pequeño a propósito: desde aquí no hay deshacer,
        // así que cerrar una tarea tiene que costar apuntar.
        let lado = 19.0
        let casilla = CGRect(x: r.minX, y: r.minY + 4, width: lado, height: lado)
        Pintor.casillasTarea.append((t.id, casilla))
        if hecha {
            wCaja(casilla, radio: 5, relleno: tema.tintes["ambar"]?.trazo)
            palomita(CGRect(x: casilla.midX - 6, y: casilla.midY - 5, width: 12, height: 11),
                     color: tema.nombre == "oscuro" ? .black : .white)
        } else {
            wCaja(casilla, radio: 5, relleno: nil,
                  trazo: urgente ? (tema.tintes["rojo"]?.trazo ?? tema.pieTexto)
                                 : tema.rol("card").trazo.color, grosor: 1.5)
        }
        // p1/p2 llevan chip; el resto no. Resaltar todo es no resaltar nada.
        var x = r.minX + lado + 12
        if t.prioridad <= 2 {
            let et = "p\(t.prioridad)"
            let w = wAncho(et, tam: 15, peso: 800, mono: true) + 14
            let tinte = t.prioridad == 1 ? (tema.tintes["rojo"] ?? tema.tintes["neutro"]!)
                                         : tema.tintes["ambar"]!
            wCaja(CGRect(x: x, y: r.minY + 3, width: w, height: 23), radio: 4, relleno: tinte.relleno)
            wTexto(et, CGPoint(x: x + 7, y: r.minY + 6), tam: 15, peso: 800,
                   color: tinte.etiqueta, mono: true)
            x += w + 10
        }
        let anchoTit = r.maxX - x
        let lineas = wEnvolver(t.contenido, ancho: anchoTit, tam: 20, peso: urgente ? 800 : 600,
                              lineas: r.height >= 76 ? 2 : 1)
        for (i,linea) in lineas.enumerated() {
            wTexto(linea, CGPoint(x:x,y:r.minY+pad+Double(i)*24),tam:20,peso:urgente ? 800 : 600,color:tema.tituloTexto)
        }
        let pieY = r.minY + pad + Double(lineas.count)*24 + 5
        // Pie: frente · cuándo. Lo que hace falta para decidir sin abrir la app.
        var pie: [String] = []
        if let f = t.frente { pie.append(f) }
        if let d = t.dia, let fecha = GDate.dayOnly.date(from: d) {
            let et = DateKit.dayMonth.string(from: fecha)
            pie.append(urgente ? "venció \(et)" : et)
        }
        if let h = t.hora { pie.append(h) }
        if !pie.isEmpty {
            wTexto(wCortar(pie.joined(separator: " · "), ancho: r.width, tam: 16, peso: 600, mono: true),
                   CGPoint(x: r.minX + lado + 12, y: pieY), tam: 16, peso: 600,
                   color: urgente ? (tema.tintes["rojo"]?.etiqueta ?? tema.pieTexto) : tema.pieTexto,
                   mono: true)
        }
    }
}
