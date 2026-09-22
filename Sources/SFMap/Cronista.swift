import AppKit

/**
 * EL CRONISTA — el ciclo que mantiene VIVO el centro de mando.
 *
 * El panel del negocio vive abierto todo el día. Un widget que se pinta al
 * abrir y nunca más es un póster con cara de instrumento: a media tarde estaría
 * enseñando la mañana. Esto es lo que le entra dato.
 *
 * ════════════════════════════════════════════════════════════════════════════
 * LAS CUATRO REGLAS QUE ESTE ARCHIVO EXISTE PARA OBEDECER
 * ════════════════════════════════════════════════════════════════════════════
 *
 * 1. **NADA DE ESTO TOCA EL LIENZO GUARDADO.** El elemento del documento dice
 *    «aquí va el calendario»; el dato NO se escribe en él. Guardar la agenda de
 *    hoy dentro del JSON de la página convertiría un espejo en un archivo
 *    muerto — y encima escribiría en la tabla `draw` cada minuto.
 *
 * 2. **UN FALLO SE DICE, NO SE PINTA COMO CERO.** Cada fuente lleva su hora de
 *    último éxito y su motivo de fallo. Sin dato, el widget escribe «sin dato
 *    desde hh:mm». Un panel vacío que parece un día libre es peor que uno que
 *    admite que no pudo leer. (`dato-ausente-no-es-cero`, 17 ago 2026.)
 *
 * 3. **EL ARRASTRE MANDA SOBRE EL REFRESCO.** El lienzo se repinta entero en
 *    cada fotograma del arrastre; si el ciclo pidiera repintar cada segundo, o
 *    peor, si leyera en el hilo principal, el panel se sentiría pegajoso. Las
 *    lecturas van en segundo plano y **solo se repinta cuando el dato CAMBIÓ**
 *    (huella de contenido, no marca de tiempo: si nada cambió, la pantalla ya
 *    está diciendo la verdad y repintarla es trabajo por nada).
 *
 * 4. **CADENCIA POR VARA, NO POR COSTUMBRE.** Calendario y tareas ≤5 min de
 *    atraso; hábitos ≤15. Se refresca con margen (3 min / 2 min / 15 s) y no
 *    "cada segundo porque se puede": cada vuelta son ~14 peticiones a Google.
 */
/// EL DÍA, congelado. Lo produce el Cronista y lo lee el pintor: un valor
/// inmutable en vez de que el pintor pregunte a la red, que es lo que hace que
/// un fotograma tarde lo que tarda un servidor.
struct EstadoDia {
    var eventos = Lectura<[CalEvent]>.vacia()
    var calendarios: [CalendarInfo] = []
    var tareas = Lectura<[TareaDia]>.vacia()
    var completadas = Lectura<[TareaDia]>.vacia()
    var habitos = Lectura<LecturaHabitos.Estado>.vacia()
    /// EL PACTO: el MRR que decide si el trofeo se gana. Mismo SSOT que los
    /// sensores del negocio (`daily_business_metrics`, reconciliada de Polar).
    var mrr = Lectura<[LecturaMRR.Punto]>.vacia()
    /// EL FILTRO que Daniel dejó puesto en sfcal. El espejo tiene que enseñar lo
    /// mismo que la cabina: un panel que filtra distinto no es un espejo, es una
    /// segunda opinión.
    var filtro = FiltroTareas()

    /// Huella de CONTENIDO. No incluye horas de lectura a propósito: una
    /// lectura que confirma lo mismo no es un cambio en pantalla.
    var huella: String {
        let ev = (eventos.valor ?? []).map { "\($0.id)|\($0.summary)|\($0.start.timeIntervalSince1970)|\($0.end.timeIntervalSince1970)" }
        let ta = ((tareas.valor ?? []) + (completadas.valor ?? [])).map { "\($0.estado ?? "")|\($0.contenido)|\($0.dia ?? "")|\($0.hora ?? "")|\($0.prioridad)" }
        let ha = (habitos.valor?.marcas ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.rawValue)" }
        let fallos = [eventos.fallo, tareas.fallo, habitos.fallo].map { $0 ?? "" }
            // El MRR y el FILTRO también entran: si Daniel filtra en sfcal, el
            // espejo tiene que repintarse; si no, se queda enseñando la lista
            // vieja hasta que cambie otra cosa.
            let mr = (mrr.valor ?? []).map { "\($0.dia)|\($0.mrr)" }
            let fi = "f:" + filtro.frentes.sorted().joined(separator: ",")
                   + "|p:" + filtro.prioridades.sorted().map(String.init).joined(separator: ",")
            let partes: [[String]] = [ev, ["·"], ta, ["·"], ha, ["·"], mr, ["·", fi, "·"], fallos]
            return partes.flatMap { $0 }.joined(separator: ";")
    }
}

@MainActor
final class Cronista {


    static let compartido = Cronista()

    private(set) var estado = EstadoDia()
    /// Lo llama el ciclo cuando el CONTENIDO cambió. Lo cablea `main.swift` a
    /// `lienzo.needsDisplay`.
    var alCambiar: (() -> Void)?

    private var huellaVista = ""
    private var relojes: [Timer] = []
    private var enVuelo = Set<String>()
    private var mtimeHabitos: Date?
    private var mtimeFiltro: Date?
    private var encendido = false

    // Las varas del spec, en segundos. Con margen: la vara es el ATRASO máximo
    // aceptable, no el periodo — un periodo igual a la vara la incumple la
    // mitad del tiempo.
    private let periodoCalendario: TimeInterval = 180     // vara 5 min
    private let periodoTareas: TimeInterval = 120         // vara 5 min
    private let periodoHabitos: TimeInterval = 15         // vara 15 min (archivo local)
    private let periodoMRR: TimeInterval = 1800           // la tabla la cierra un cron diario

    /// Cuánto puede envejecer una lectura antes de que el widget deje de
    /// presentarla como verdad de ahora.
    nonisolated static let varaCalendario: TimeInterval = 5 * 60
    nonisolated static let varaTareas: TimeInterval = 5 * 60
    nonisolated static let varaHabitos: TimeInterval = 15 * 60
    /// El MRR del día ANTERIOR sigue siendo verdad todo el día: su vara es de
    /// horas, no de minutos.
    nonisolated static let varaMRR: TimeInterval = 6 * 3600

    // ── arranque ────────────────────────────────────────────────────────────

    /// Enciende el ciclo. Idempotente: llamarlo dos veces no duplica relojes
    /// (el pileup de crons del 18 jul enseñó lo que cuesta un actuador que se
    /// solapa consigo mismo).
    func encender() {
        guard !encendido else { return }
        encendido = true
        refrescarTodo()
        relojes = [
            Timer.scheduledTimer(withTimeInterval: periodoCalendario, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refrescarCalendario() }
            },
            Timer.scheduledTimer(withTimeInterval: periodoTareas, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refrescarTareas() }
            },
            Timer.scheduledTimer(withTimeInterval: periodoHabitos, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refrescarHabitos() }
            },
            Timer.scheduledTimer(withTimeInterval: periodoMRR, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refrescarMRR() }
            },
        ]
        // Volver a la ventana es la señal más honesta de "quiero mirar esto
        // ahora": se refresca sin esperar al reloj.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refrescarTodo() }
            }
    }

    /// UNA lectura completa, esperada. La usan la foto y el export: sin esto,
    /// un PNG del panel saldría con los tres widgets diciendo «sin lectura» —
    /// que es honesto en pantalla e inútil como prueba de que el widget pinta
    /// datos reales.
    func cargarUnaVez() async {
        let (d, h) = Cronista.ventana()
        async let ev = LecturaGoogle.eventos(desde: d, hasta: h)
        async let tk = LecturaTodoist.tareas()
        async let co = LecturaTodoist.completadas()
        async let mr = LecturaMRR.serie()
        let (e, t, m) = await (ev, tk, mr)
        estado.eventos = e
        estado.calendarios = LecturaGoogle.ultimosCalendarios
        estado.tareas = t
        estado.completadas = await co
        estado.mrr = m
        estado.habitos = LecturaHabitos.del(Date())
        estado.filtro = FiltroTareas.cargar()
    }

    func refrescarTodo() {
        refrescarCalendario()
        refrescarTareas()
        refrescarMRR()
        refrescarHabitos(forzar: true)
    }

    /// El MRR se mueve UNA vez al día (la tabla la cierra el cron de la
    /// mañana). Pedirlo cada tres minutos sería castigar a Supabase para
    /// confirmar el mismo número 480 veces.
    private func refrescarMRR() {
        guard !enVuelo.contains("mrr") else { return }
        enVuelo.insert("mrr")
        Task.detached(priority: .utility) {
            let l = await LecturaMRR.serie()
            await MainActor.run {
                self.enVuelo.remove("mrr")
                if l.valor != nil { self.estado.mrr = l } else { self.estado.mrr.fallo = l.fallo }
                self.avisarSiCambio()
            }
        }
    }

    // ── la ventana que se pide a Google ─────────────────────────────────────

    /// Cubre la rejilla del mes (42 celdas desde el lunes de la semana del día
    /// 1) y la semana en curso, que en los últimos días del mes cae fuera.
    nonisolated static func ventana(_ hoy: Date = Date()) -> (Date, Date) {
        let a = DateKit.startOfWeek(DateKit.startOfMonth(hoy))
        let b = DateKit.startOfWeek(hoy)
        let desde = DateKit.addDays(min(a, b), -1)
        return (desde, DateKit.addDays(desde, 50))
    }

    // ── las tres lecturas ───────────────────────────────────────────────────

    private func refrescarCalendario() {
        guard !enVuelo.contains("cal") else { return }     // anti-solape
        enVuelo.insert("cal")
        let (d, h) = Cronista.ventana()
        Task.detached(priority: .utility) {
            let l = await LecturaGoogle.eventos(desde: d, hasta: h)
            let cals = LecturaGoogle.ultimosCalendarios
            await MainActor.run {
                self.enVuelo.remove("cal")
                // Un fallo NO borra la última lectura buena: se conserva el
                // valor y se marca cuándo fue. Vaciar la pantalla ante un
                // wifi caído es perder información que sí teníamos.
                if l.valor != nil {
                    self.estado.eventos = l
                    self.estado.calendarios = cals
                } else {
                    self.estado.eventos.fallo = l.fallo
                }
                self.avisarSiCambio()
            }
        }
    }

    private func refrescarTareas() {
        guard !enVuelo.contains("todo") else { return }
        enVuelo.insert("todo")
        Task.detached(priority: .utility) {
            let l = await LecturaTodoist.tareas()
            let completadas = await LecturaTodoist.completadas()
            await MainActor.run {
                self.enVuelo.remove("todo")
                self.estado.completadas = completadas
                if l.valor != nil { self.estado.tareas = l }
                else { self.estado.tareas.fallo = l.fallo }
                self.avisarSiCambio()
            }
        }
    }

    /// Barato y local: se mira el `mtime` y solo se decodifica si cambió. El
    /// archivo lo reemplaza sfcal de forma atómica (inodo nuevo cada vez), así
    /// que vigilar un descriptor no serviría — el sondeo es lo correcto aquí.
    private func refrescarHabitos(forzar: Bool = false) {
        let mt = (try? FileManager.default.attributesOfItem(
            atPath: LecturaHabitos.ruta.path)[.modificationDate]) as? Date
        let mf = (try? FileManager.default.attributesOfItem(
            atPath: FiltroTareas.ruta.path)[.modificationDate]) as? Date
        if !forzar, let a = mtimeHabitos, let b = mt, a == b, mtimeFiltro == mf { return }
        mtimeFiltro = mf
        mtimeHabitos = mt
        // El FILTRO viaja en el mismo latido: los dos son archivos locales que
        // sfcal reescribe, y el espejo tiene que reaccionar en segundos — si
        // Daniel filtra en sfcal y el panel tarda dos minutos en seguirlo, deja
        // de ser un espejo y pasa a ser un retraso.
        let f = FiltroTareas.cargar()
        if f != estado.filtro { estado.filtro = f }
        let l = LecturaHabitos.del(Date())
        if l.valor != nil { estado.habitos = l } else { estado.habitos.fallo = l.fallo }
        avisarSiCambio()
    }

    private func avisarSiCambio() {
        let h = estado.huella
        guard h != huellaVista else { return }
        huellaVista = h
        alCambiar?()
    }

    // ── lo que el pintor pregunta ───────────────────────────────────────────

    /// «hh:mm» de la última lectura buena, o nil si nunca hubo una.
    nonisolated static func sello(_ cuando: Date?) -> String? {
        guard let c = cuando else { return nil }
        return DateKit.timeShort.string(from: c)
    }

    /// ¿La lectura sigue valiendo como verdad de ahora?
    nonisolated static func fresca(_ cuando: Date?, vara: TimeInterval) -> Bool {
        guard let c = cuando else { return false }
        return Date().timeIntervalSince(c) <= vara
    }
}
