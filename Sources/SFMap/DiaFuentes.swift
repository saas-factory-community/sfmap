import Foundation

/**
 * LAS FUENTES DEL DÍA — el transporte de SOLO LECTURA.
 *
 * El centro de mando mira tres cosas que no son suyas: el calendario de Google,
 * los hábitos que sfcal escribe en disco, y las tareas de Todoist. Este archivo
 * es el único sitio de sfmap que habla con ellas.
 *
 * ════════════════════════════════════════════════════════════════════════════
 * POR QUÉ EL TRANSPORTE **NO** SE COMPARTE CON SFCAL (y la derivación sí)
 * ════════════════════════════════════════════════════════════════════════════
 *
 * `Sources/SFMap/Dia/` enlaza los archivos de doctrina de sfcal (el conteo del
 * monk mode, la rutina, los hábitos, el calendario operativo). Esos SÍ son una
 * sola definición en disco: dos derivaciones del mismo día se separan en
 * silencio y un día el panel dice una cosa y la pared del monje otra.
 *
 * El CLIENTE de red no. El de sfcal sabe crear, mover y borrar eventos, y
 * enlazarlo aquí metería esa capacidad en una app cuya regla es que la UI es
 * espejo, no cabina. La promesa de solo-lectura no se sostiene con disciplina:
 * se sostiene porque en este archivo **no existe un método que escriba**. Por
 * eso `pedir()` no acepta verbo — siempre es GET — y por eso el único POST del
 * archivo es el refresh del token, que no toca datos de nadie.
 *
 * Las credenciales se leen de donde ya viven (`~/.sfcal/token-*.json`,
 * `agent-server/.env`). No se copian, no se mueven, no se imprimen.
 */

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Lo que una fuente devuelve
// ════════════════════════════════════════════════════════════════════════════

/// El resultado de una lectura, CON su hora. Nunca un valor pelado: un dato sin
/// marca de tiempo en un panel que vive abierto es una afirmación sobre ahora
/// que puede tener seis horas.
struct Lectura<T> {
    var valor: T?
    var alDia: Date?          // último éxito
    var fallo: String?        // por qué no hay dato nuevo

    static func vacia() -> Lectura<T> { Lectura(valor: nil, alDia: nil, fallo: nil) }
}

enum FuenteError: Error, CustomStringConvertible {
    case sinCredencial(String)
    case http(Int)
    case red(String)

    var description: String {
        switch self {
        case .sinCredencial(let q): return "sin credencial (\(q))"
        case .http(let c):          return "HTTP \(c)"
        case .red(let m):           return m
        }
    }
}

/// GET y solo GET. El verbo no es un parámetro a propósito (ver cabecera).
private func pedir(_ url: URL, cabeceras: [String: String]) async throws -> Data {
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.timeoutInterval = 20
    for (k, v) in cabeceras { req.setValue(v, forHTTPHeaderField: k) }
    do {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw FuenteError.red("respuesta no HTTP") }
        guard (200..<300).contains(http.statusCode) else { throw FuenteError.http(http.statusCode) }
        return data
    } catch let e as FuenteError {
        throw e
    } catch {
        throw FuenteError.red((error as NSError).localizedDescription)
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - La llave de Google (las MISMAS de sfcal)
// ════════════════════════════════════════════════════════════════════════════

/// Cambia el `refresh_token` del archivo de sfcal por un `access_token` vivo.
///
/// Es el único POST del archivo, y no escribe datos de nadie: es el intercambio
/// que Google exige para poder LEER. El token en memoria se reusa hasta un
/// minuto antes de expirar; sin eso, un panel que refresca cada minuto pediría
/// credencial nueva cada minuto.
actor LlaveSfcal {
    private struct Archivo: Codable {
        let client_id: String
        let client_secret: String
        let refresh_token: String
        let token_uri: String?
        let account: String?
    }

    nonisolated let etiqueta: String
    nonisolated let correo: String
    private let archivo: Archivo
    private var vigente: String?
    private var caduca: Date = .distantPast

    init?(etiqueta: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".sfcal/token-\(etiqueta).json")
        guard let d = try? Data(contentsOf: url),
              let a = try? JSONDecoder().decode(Archivo.self, from: d) else { return nil }
        self.etiqueta = etiqueta
        self.archivo = a
        self.correo = a.account ?? etiqueta
    }

    /// Las cuentas que sfcal tiene configuradas, en el orden en que las lista.
    static func cuentas() -> [LlaveSfcal] {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sfcal")
        let nombres = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return nombres
            .filter { $0.hasPrefix("token-") && $0.hasSuffix(".json") }
            .map { String($0.dropFirst(6).dropLast(5)) }
            .sorted()
            .compactMap { LlaveSfcal(etiqueta: $0) }
    }

    func token() async throws -> String {
        if let t = vigente, caduca > Date().addingTimeInterval(60) { return t }
        var req = URLRequest(url: URL(string: archivo.token_uri ?? "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = [
            "client_id=\(archivo.client_id)",
            "client_secret=\(archivo.client_secret)",
            "refresh_token=\(archivo.refresh_token)",
            "grant_type=refresh_token",
        ].joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw FuenteError.http((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
        struct R: Codable { let access_token: String; let expires_in: Double }
        let r = try JSONDecoder().decode(R.self, from: data)
        vigente = r.access_token
        caduca = Date().addingTimeInterval(r.expires_in)
        return r.access_token
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - El calendario (Google directo, GET)
// ════════════════════════════════════════════════════════════════════════════

enum LecturaGoogle {

    private struct ListaCal: Codable {
        struct Item: Codable {
            let id: String
            let summary: String?
            let summaryOverride: String?
            let backgroundColor: String?
            let foregroundColor: String?
            let accessRole: String?
            let primary: Bool?
        }
        let items: [Item]?
    }

    private struct Pagina: Codable {
        let items: [GEvent]?
        let nextPageToken: String?
    }

    /// Los calendarios que Daniel ESCONDIÓ en sfcal. Se respetan aquí porque el
    /// widget es un espejo del mismo calendario: enseñar un calendario que él
    /// apagó en la otra ventana sería una segunda opinión sobre lo mismo.
    static func ocultos() -> Set<String> {
        struct Estado: Codable { var hiddenCalendarIds: Set<String>? }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".sfcal/cache/state.json")
        guard let d = try? Data(contentsOf: url),
              let e = try? JSONDecoder().decode(Estado.self, from: d) else { return [] }
        return e.hiddenCalendarIds ?? []
    }

    /// Todos los eventos de todas las cuentas en la ventana pedida. Un
    /// calendario que falla NO tumba a los demás: se apunta el fallo y sigue,
    /// porque media agenda es mejor que ninguna y el widget lo va a decir.
    static func eventos(desde: Date, hasta: Date) async -> Lectura<[CalEvent]> {
        let llaves = LlaveSfcal.cuentas()
        guard !llaves.isEmpty else {
            return Lectura(valor: nil, alDia: nil, fallo: "sin token de sfcal en ~/.sfcal")
        }
        let escondidos = ocultos()
        var todos: [CalEvent] = []
        var fallos: [String] = []
        var calendarios: [CalendarInfo] = []

        for llave in llaves {
            do {
                let tk = try await llave.token()
                let cab = ["Authorization": "Bearer \(tk)"]
                let lista = try JSONDecoder().decode(ListaCal.self, from: try await pedir(
                    URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250")!,
                    cabeceras: cab))
                for it in lista.items ?? [] {
                    guard !escondidos.contains(it.id) else { continue }
                    let info = CalendarInfo(
                        id: it.id, accountId: llave.etiqueta,
                        summary: it.summaryOverride ?? it.summary ?? it.id,
                        bgColorHex: it.backgroundColor ?? "#8C27F1",
                        fgColorHex: it.foregroundColor ?? "#ffffff",
                        accessRole: it.accessRole ?? "reader",
                        isPrimary: it.primary ?? false)
                    calendarios.append(info)
                    todos += try await eventosDe(info, desde: desde, hasta: hasta, cabeceras: cab)
                }
            } catch {
                fallos.append("\(llave.etiqueta): \(error)")
            }
        }
        LecturaGoogle.ultimosCalendarios = calendarios
        if todos.isEmpty && !fallos.isEmpty {
            return Lectura(valor: nil, alDia: nil, fallo: fallos.joined(separator: " · "))
        }
        return Lectura(valor: todos.sorted { $0.start != $1.start ? $0.start < $1.start : $0.id < $1.id },
                       alDia: Date(),
                       fallo: fallos.isEmpty ? nil : fallos.joined(separator: " · "))
    }

    /// Los calendarios de la última lectura, para que el pintor sepa el color de
    /// cada evento y quién es de "Objetivo …".
    nonisolated(unsafe) private(set) static var ultimosCalendarios: [CalendarInfo] = []

    private static func eventosDe(_ cal: CalendarInfo, desde: Date, hasta: Date,
                                  cabeceras: [String: String]) async throws -> [CalEvent] {
        var salida: [CalEvent] = []
        var token: String?
        for _ in 0..<8 {
            var c = URLComponents(string:
                "https://www.googleapis.com/calendar/v3/calendars/\(cal.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? cal.id)/events")!
            c.queryItems = [
                .init(name: "timeMin", value: GDate.format(desde)),
                .init(name: "timeMax", value: GDate.format(hasta)),
                .init(name: "singleEvents", value: "true"),
                .init(name: "orderBy", value: "startTime"),
                .init(name: "maxResults", value: "250"),
                .init(name: "showDeleted", value: "false"),
            ]
            if let t = token { c.queryItems?.append(.init(name: "pageToken", value: t)) }
            let page = try JSONDecoder().decode(Pagina.self, from: try await pedir(c.url!, cabeceras: cabeceras))
            salida += (page.items ?? []).compactMap { $0.toCalEvent(calendarId: cal.id, accountId: cal.accountId) }
            guard let n = page.nextPageToken else { break }
            token = n
        }
        return salida
    }
}

/// El evento como lo manda Google. Vive aquí y no en el núcleo compartido
/// porque es forma de TRANSPORTE, no doctrina: `CalEvent` (compartido) es lo
/// que las dos apps entienden por un bloque del día.
struct GEvent: Codable {
    let id: String
    let etag: String?
    let status: String?
    let summary: String?
    let description: String?
    let location: String?
    let start: Marca?
    let end: Marca?
    let recurringEventId: String?
    let updated: String?

    struct Marca: Codable { var date: String?; var dateTime: String? }

    func toCalEvent(calendarId: String, accountId: String) -> CalEvent? {
        guard status != "cancelled" else { return nil }
        let todoElDia = start?.date != nil
        guard let s = (start?.dateTime ?? start?.date).flatMap(GDate.parse) else { return nil }
        let e = (end?.dateTime ?? end?.date).flatMap(GDate.parse) ?? s.addingTimeInterval(3600)
        return CalEvent(id: id, calendarId: calendarId, accountId: accountId,
                        summary: summary ?? "(sin título)", start: s, end: max(e, s),
                        isAllDay: todoElDia, status: status ?? "confirmed",
                        recurringEventId: recurringEventId, etag: etag,
                        notes: description, location: location,
                        updated: updated.flatMap(GDate.parse))
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Todoist (fuente ÚNICA de tareas, API v1, GET)
// ════════════════════════════════════════════════════════════════════════════

/// Una tarea, ya normalizada. Los nombres siguen a `query_todoist()` de
/// `now-snapshot.py`, que es la clasificación de referencia del sistema.
struct TareaDia: Hashable {
    /// El id de Todoist. Hace falta para poder CERRARLA desde el widget: sin él
    /// la casilla sería un dibujo de una casilla.
    var id: String
    var contenido: String
    var prioridad: Int          // 1 = urgente … 4 = normal (ya invertida)
    var dia: String?            // "YYYY-MM-DD"
    var hora: String?           // "HH:MM"
    var frente: String?         // el nombre del proyecto (para pintar)
    /// El ID del proyecto. El FILTRO trabaja con ids, no con nombres: renombrar
    /// un proyecto no puede vaciarle el filtro a nadie sin avisar.
    var frenteId: String?
    /// Las etiquetas de Todoist. Viajan porque el filtro compartido las usa.
    var etiquetas: [String] = []
    var estado: String? = nil
}

enum LecturaTodoist {

    /// El token vive donde ya vivía. Se lee del `.env` del agent-server, igual
    /// que lo hace `now-snapshot.py`.
    static func token() -> String? {
        if let t = ProcessInfo.processInfo.environment["TODOIST_API_TOKEN"], !t.isEmpty { return t }
        let env = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".sfmap/env")
        guard let txt = try? String(contentsOf: env, encoding: .utf8) else { return nil }
        for l in txt.split(separator: "\n") where l.hasPrefix("TODOIST_API_TOKEN=") {
            let v = String(l.dropFirst("TODOIST_API_TOKEN=".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            return v.isEmpty ? nil : v
        }
        return nil
    }

    private struct Pagina: Codable {
        struct Item: Codable {
            let id: String
            let content: String
            let priority: Int?
            let project_id: String?
            let due: Vence?
            let labels: [String]?
            let section_id: String?
            struct Vence: Codable { let date: String?; let datetime: String? }
        }
        let results: [Item]?
        let next_cursor: String?
    }

    private struct Proyectos: Codable {
        struct P: Codable { let id: String; let name: String? }
        let results: [P]?
    }

    static func tareas() async -> Lectura<[TareaDia]> {
        guard let tk = token() else {
            return Lectura(valor: nil, alDia: nil, fallo: "sin TODOIST_API_TOKEN")
        }
        let cab = ["Authorization": "Bearer \(tk)"]
        let base = "https://api.todoist.com/api/v1"

        // El mapa de proyectos es BEST-EFFORT: sin él las tareas salen sin
        // frente, que es mejor que con un frente inventado.
        var frentes: [String: String] = [:]
        if let d = try? await pedir(URL(string: "\(base)/projects?limit=200")!, cabeceras: cab),
           let p = try? JSONDecoder().decode(Proyectos.self, from: d) {
            for pr in p.results ?? [] { frentes[pr.id] = pr.name ?? "" }
        }

        var secciones: [String:String] = [:]
        if let d = try? await pedir(URL(string:"\(base)/sections?limit=200")!,cabeceras:cab),
           let p = try? JSONDecoder().decode(Proyectos.self,from:d) {
            for x in p.results ?? [] {secciones[x.id]=x.name}
        }
        var crudas: [Pagina.Item] = []
        var cursor: String?
        do {
            for _ in 0..<20 {                       // tope de páginas defensivo
                var u = "\(base)/tasks?limit=200"
                if let c = cursor, let q = c.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
                    u += "&cursor=\(q)"
                }
                let page = try JSONDecoder().decode(Pagina.self,
                                                    from: try await pedir(URL(string: u)!, cabeceras: cab))
                crudas += page.results ?? []
                guard let n = page.next_cursor else { break }
                cursor = n
            }
        } catch {
            return Lectura(valor: nil, alDia: nil, fallo: "\(error)")
        }

        let tareas = crudas.map { t -> TareaDia in
            let bruto = t.due?.datetime ?? t.due?.date ?? ""
            let conHora = bruto.contains("T")
            return TareaDia(
                id: t.id,
                contenido: t.content,
                // API: 4 = p1 (urgente) … 1 = p4. Se invierte como en el snapshot.
                prioridad: 5 - (t.priority ?? 1),
                dia: bruto.isEmpty ? nil : String(bruto.prefix(10)),
                hora: (conHora && bruto.count >= 16)
                    ? String(bruto[bruto.index(bruto.startIndex, offsetBy: 11)..<bruto.index(bruto.startIndex, offsetBy: 16)])
                    : nil,
                frente: t.project_id.flatMap { frentes[$0] },
                frenteId: t.project_id,
                etiquetas: t.labels ?? [], estado:t.section_id.flatMap{secciones[$0]})
        }
        return Lectura(valor: tareas, alDia: Date(), fallo: nil)
    }
}

extension LecturaTodoist {

    /**
     * ⚠️ EL ÚNICO VERBO DE ESTE ARCHIVO QUE ESCRIBE. Y está aquí por orden
     * explícita de Daniel (25 ago): *"permíteme añadir los checks a la parte de
     * tareas… que pueda marcar los checks desde acá justo como lo haría un
     * widget"*.
     *
     * Enmienda al read-only absoluto que él mismo firmó en el spec. Lo que la
     * regla protegía sigue en pie y hay que decirlo con precisión:
     *
     * · **Nada de crear, editar, reprogramar ni borrar.** Solo CERRAR una tarea
     *   que ya existe, por su id. No hay forma de que el panel invente nada.
     * · **Sigue sin haber formularios.** Palomear lo hecho no es "operar una
     *   interfaz": es el mismo gesto que marcar un hábito en sfcal, que es la
     *   cabina designada para eso. Lo que la Regla de Oro #5 mata es armar
     *   cosas a mano en pantalla, no confirmar lo que ya pasó.
     * · **Google sigue intacto.** El calendario del panel no escribe ni una
     *   coma: para mover un bloque, se le habla a Levy.
     *
     * Y una consecuencia que hay que tener presente: **desde aquí no hay
     * deshacer.** Por eso la casilla es un blanco pequeño y no la fila entera.
     */
    static func cerrar(_ idTarea: String) async -> String? {
        guard let tk = token() else { return "sin TODOIST_API_TOKEN" }
        var req = URLRequest(url: URL(string: "https://api.todoist.com/api/v1/tasks/\(idTarea)/close")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("Bearer \(tk)", forHTTPHeaderField: "Authorization")
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let c = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(c) ? nil : "HTTP \(c)"
        } catch {
            return (error as NSError).localizedDescription
        }
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - EL PACTO DEL FIERRO (los términos, y el MRR que los mide)
// ════════════════════════════════════════════════════════════════════════════

/// Datos DEMO del widget opcional de metas. Personalízalos antes de usarlo.
/// No son métricas ni compromisos de ningún negocio real.
enum Pacto {
    static let meta: Double = 10_000
    static let base: Double = 0
    static let firmado = DateComponents(year: 2026, month: 1, day: 1)
    static let limite = DateComponents(year: 2026, month: 12, day: 31)
    static let trofeo = "Tu siguiente meta · ejemplo"
    static let gatillo = "Configura tu objetivo y fecha"
    static let imagen = ""
    static let canonico = "doc:meta.md"

    static var fin: Date { DateKit.cal.date(from: limite) ?? Date() }

    static func diasRestantes(_ hoy: Date = Date()) -> Int {
        DateKit.cal.dateComponents([.day], from: DateKit.startOfDay(hoy),
                                   to: DateKit.startOfDay(fin)).day ?? 0
    }

    /// Cuánto del camino se lleva. **Desde la BASE del pacto, no desde cero**:
    /// medir desde cero regalaría un 55% de barra el día que se firmó, y una
    /// barra que nace medio llena no aprieta a nadie.
    static func avance(_ mrr: Double) -> Double {
        max(0, min(1, (mrr - base) / (meta - base)))
    }
}

/// El MRR vivo. Misma tabla que el cron de sensores (`daily_business_metrics`,
/// reconciliada de Polar). **JAMÁS de `community_purchases`** — regla dura de
/// billing, y la razón por la que este lector solo conoce una tabla.
enum LecturaMRR {

    struct Punto: Hashable { var dia: String; var mrr: Double; var subs: Int }

    private struct Fila: Codable { let date: String; let mrr_cents: Double?; let active_subs: Int? }

    private static func credenciales() -> (String, String)? {
        let env = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".sfmap/env")
        guard let txt = try? String(contentsOf: env, encoding: .utf8) else { return nil }
        var u: String?, k: String?
        for l in txt.split(separator: "\n") {
            if l.hasPrefix("SF_SUPABASE_URL=") { u = String(l.dropFirst(16)) }
            if l.hasPrefix("SF_SUPABASE_KEY=") { k = String(l.dropFirst(16)) }
        }
        guard let u, let k else { return nil }
        return (u, k)
    }

    /// Los últimos días, para la cifra y para la forma del tramo.
    static func serie(_ dias: Int = 30) async -> Lectura<[Punto]> {
        guard let (u, k) = credenciales() else {
            return Lectura(valor: nil, alDia: nil, fallo: "sin credenciales de SaaS Factory")
        }
        let url = URL(string: "\(u)/rest/v1/daily_business_metrics?select=date,mrr_cents,active_subs&order=date.desc&limit=\(dias)")!
        do {
            let d = try await pedir(url, cabeceras: ["apikey": k, "Authorization": "Bearer \(k)"])
            let filas = try JSONDecoder().decode([Fila].self, from: d)
            // ⚠️ Se descarta la fila de HOY: es un snapshot parcial de mediodía.
            // La misma regla que obedece `sensores.py` — publicar el parcial
            // convertiría el trofeo en un mentiroso el primer día.
            let hoy = GDate.formatDay(Date())
            /*
             * ⚠️ UN CERO NO ES UNA MEDICIÓN — y esta tabla tiene ceros.
             *
             * El 25 jul 2026 la fila trae `mrr_cents: 0` con `active_subs: 0`.
             * Un negocio con 437 suscripciones no amanece en cero: ese par es
             * un snapshot que FALLÓ. Dibujarlo como dato pintaba un desplome a
             * cero en mitad de la subida del trofeo — la mentira exacta que
             * `dato-ausente-no-es-cero` (17 ago) existe para evitar.
             *
             * Se DESCARTA, no se interpola: rellenar el hueco con la media
             * sería fabricar el día que falta. Un hueco es un hueco, y en una
             * línea de tiempo se ve como lo que es (el trazo salta ese día).
             */
            let puntos = filas.filter { $0.date != hoy }.compactMap { f -> Punto? in
                guard let c = f.mrr_cents, c > 0, (f.active_subs ?? 0) > 0 else { return nil }
                return Punto(dia: f.date, mrr: c / 100, subs: f.active_subs ?? 0)
            }.reversed()
            guard !puntos.isEmpty else {
                return Lectura(valor: nil, alDia: nil, fallo: "sin días cerrados en la tabla")
            }
            return Lectura(valor: Array(puntos), alDia: Date(), fallo: nil)
        } catch {
            return Lectura(valor: nil, alDia: nil, fallo: "\(error)")
        }
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Los hábitos (el archivo que sfcal escribe, aquí SOLO se lee)
// ════════════════════════════════════════════════════════════════════════════

/// `~/.sfcal/habitos.json`. sfcal lo documenta como archivo y no como
/// `UserDefaults` justo para que otros lo lean; esto es ese otro.
///
/// ⚠️ NUNCA escribe. Marcar un hábito es cabina, y la cabina de los hábitos es
/// sfcal (o Levy por conversación). Aquí solo se mira.
enum LecturaHabitos {

    private struct Archivo: Codable {
        var actualizado: String?
        var marcas: [String: [String: HabitEstado]]?
        var pasos: [String: [String]]?
    }

    struct Estado {
        var marcas: [String: HabitEstado] = [:]     // clave → estado, SOLO del día pedido
        var escritoEn: Date?                        // mtime del archivo
    }

    static var ruta: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sfcal/habitos.json")
    }

    static func del(_ dia: Date) -> Lectura<Estado> {
        let u = ruta
        guard let d = try? Data(contentsOf: u) else {
            return Lectura(valor: nil, alDia: nil, fallo: "sin ~/.sfcal/habitos.json")
        }
        guard let a = try? JSONDecoder().decode(Archivo.self, from: d) else {
            return Lectura(valor: nil, alDia: nil, fallo: "habitos.json ilegible")
        }
        let mtime = (try? FileManager.default.attributesOfItem(atPath: u.path)[.modificationDate]) as? Date
        // OJO: un día sin marcas NO es un fallo — es un día que aún no se ha
        // registrado, y el widget lo pinta como 0/8 con las casillas vacías.
        // Eso sí es un dato: "todavía nada". Lo que no existiría es el archivo.
        return Lectura(valor: Estado(marcas: a.marcas?[GDate.formatDay(dia)] ?? [:], escritoEn: mtime),
                       alDia: Date(), fallo: nil)
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - La sonda: `sfmap --sonda-dia`
// ════════════════════════════════════════════════════════════════════════════

/// Enseña lo que las tres fuentes devuelven AHORA, en texto. Existe porque un
/// widget que se verifica por su propio log no está verificado: primero se
/// comprueba que el DATO llega (esto) y después que se PINTA (la foto). Si se
/// confunden los dos pasos, un panel bonito con datos inventados pasa el examen.
enum SondaDia {
    static func correr() async {
        let (d, h) = Cronista.ventana()
        print("── ventana pedida: \(GDate.formatDay(d)) → \(GDate.formatDay(h))")

        let ev = await LecturaGoogle.eventos(desde: d, hasta: h)
        print("\n── CALENDARIO (Google directo, tokens de sfcal)")
        print("   cuentas: \(LlaveSfcal.cuentas().map(\.etiqueta).joined(separator: ", "))")
        print("   calendarios visibles: \(LecturaGoogle.ultimosCalendarios.count)  ·  ocultos en sfcal: \(LecturaGoogle.ocultos().count)")
        if let e = ev.valor {
            print("   eventos en ventana: \(e.count)   última lectura: \(Cronista.sello(ev.alDia) ?? "—")")
            let hoy = e.filter { DateKit.isToday($0.start) && !$0.isAllDay }
            print("   HOY (\(hoy.count)):")
            for x in hoy.prefix(12) {
                print("     \(DateKit.timeShort.string(from: x.start))–\(DateKit.timeShort.string(from: x.end))  \(x.summary)")
            }
        } else { print("   SIN DATO: \(ev.fallo ?? "?")") }

        print("\n── MONK MODE (derivado del núcleo compartido con sfcal)")
        print("   día \(MonkMode.dayNumber()) de \(MonkMode.totalDays)")
        let bloques = MonkMode.bloquesDeHoy(eventos: (ev.valor ?? []).filter { DateKit.isToday($0.start) })
        print("   bloques de hoy: \(bloques.count)")
        for b in bloques.prefix(10) { print("     \(b.hora)  \(b.titulo)") }
        let hb = LecturaHabitos.del(Date())
        if let e = hb.valor {
            let hechos = Habitos.todos.filter { e.marcas[$0.clave] == .hecho }.count
            print("   hábitos: \(hechos)/\(Habitos.todos.count)   archivo escrito: \(e.escritoEn.map { DateKit.timeShort.string(from: $0) } ?? "—")")
        } else { print("   hábitos SIN DATO: \(hb.fallo ?? "?")") }

        let tk = await LecturaTodoist.tareas()
        print("\n── TAREAS (Todoist API v1)")
        if let t = tk.valor {
            let hoyISO = GDate.formatDay(Date())
            let vencidas = t.filter { ($0.dia ?? "9") < hoyISO && $0.dia != nil }
            let hoy = t.filter { $0.dia == hoyISO }
            print("   total activas: \(t.count)  ·  vencidas: \(vencidas.count)  ·  hoy: \(hoy.count)  ·  sin fecha: \(t.filter { $0.dia == nil }.count)")
            for x in (vencidas + hoy).prefix(8) {
                print("     [p\(x.prioridad)] \(x.contenido.prefix(56))  · \(x.frente ?? "—")  · \(x.dia ?? "sin fecha")")
            }
        } else { print("   SIN DATO: \(tk.fallo ?? "?")") }
    }
}

extension LecturaTodoist {
    static func completadas() async -> Lectura<[TareaDia]> {
        guard let tk=token() else {return Lectura(valor:nil,alDia:nil,fallo:"sin token")}
        let now=Date(), dia=GDate.formatDay(now)
        let start=Calendar.current.startOfDay(for:now)
        let end=Calendar.current.date(byAdding:.day,value:1,to:start)!
        let iso=ISO8601DateFormatter()
        var cursor:String?, result:[TareaDia]=[]
        do {
            for _ in 0..<20 {
                var u=URLComponents(string:"https://api.todoist.com/api/v1/tasks/completed/by_completion_date")!
                u.queryItems=[URLQueryItem(name:"since",value:iso.string(from:start)),URLQueryItem(name:"until",value:iso.string(from:end)),URLQueryItem(name:"limit",value:"200")]
                if let cursor {u.queryItems!.append(URLQueryItem(name:"cursor",value:cursor))}
                let d=try await pedir(u.url!,cabeceras:["Authorization":"Bearer "+tk])
                guard let page=try JSONSerialization.jsonObject(with:d) as? [String:Any],let items=page["items"] as? [[String:Any]] else {throw URLError(.cannotParseResponse)}
                for t in items {
                    guard let content=t["content"] as? String else {continue}
                    let id=(t["task_id"] as? String) ?? (t["id"] as? String) ?? content
                    result.append(TareaDia(id:id,contenido:content,prioridad:4,dia:dia,hora:nil,frente:nil,frenteId:t["project_id"] as? String))
                }
                cursor=page["next_cursor"] as? String
                if cursor == nil {return Lectura(valor:result,alDia:now,fallo:nil)}
            }
            throw URLError(.dataLengthExceedsMaximum)
        } catch {return Lectura(valor:nil,alDia:nil,fallo:String(describing:error))}
    }
}
