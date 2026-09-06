// NUCLEO COMPARTIDO — lo compilan sfcal y sfmap (enlace simbólico).
//
// EL FILTRO DE TAREAS. Daniel lo pidió el 25 ago: *"permíteme filtrarlas estilo
// Notion siguiendo mejores prácticas… que sfcal recuerde mi última
// configuración… y que el espejo en sfmap también se actualice y sea acorde"*.
//
// Por eso vive aquí y no en `UserDefaults`: el espejo tiene que poder leer el
// MISMO filtro. Un panel que filtra distinto que su cabina no es un espejo, es
// una segunda opinión — y este sistema ya pagó caro esa lección hoy mismo
// (sfcal decía "cero pendientes" mientras el widget enseñaba siete).

import Foundation

/// El filtro de la lista de tareas, en el modelo de Notion **reducido a lo que
/// una lista de tareas necesita**: unos pocos ejes, chips, sin constructor de
/// condiciones anidadas.
///
/// ════════════════════════════════════════════════════════════════════════════
/// LAS TRES REGLAS QUE LO DEFINEN (y por qué no es un query builder)
/// ════════════════════════════════════════════════════════════════════════════
///
/// 1. **OR dentro de un eje, AND entre ejes.** «YouTube o Comunidad» Y «p1».
///    Es lo que todo el mundo espera de una barra de chips y lo que hace Notion
///    con sus filtros rápidos. Un constructor de condiciones anidadas en un
///    panel de veinte tareas es potencia que nadie usa y complejidad que todos
///    pagan.
///
/// 2. **Vacío = SIN restricción, jamás «ninguno».** Es la trampa clásica: si
///    "sin nada marcado" significara "no mostrar nada", el primer clic de
///    limpiar dejaría la lista en blanco y parecería que se borró todo.
///
/// 3. **El eje de FECHA es un HORIZONTE, no una repetición de la agrupación.**
///    La lista se agrupa por fecha, así que filtrar por "hoy / mañana / …"
///    sería decir lo mismo dos veces. Lo que sí falta —y Daniel pidió— es
///    recortar **hasta dónde miras**: hoy · próximos 7 · el mes · todas. Eso no
///    compite con los grupos: los limita. Y **las VENCIDAS entran siempre**,
///    porque un horizonte que esconde lo que ya se te pasó es justo el que
///    convierte una deuda en una sorpresa.
///
/// ⚠️ Y la regla que este sistema aprendió HOY, aplicada aquí: **un filtro que
/// esconde en silencio es la misma mentira que un cero sin medir.** Quien pinte
/// esto tiene que decir cuántas oculta — `ocultas(de:)` existe para eso y no es
/// opcional.
struct FiltroTareas: Codable, Equatable {

    /// Ids de proyecto de Todoist. **Ids y no nombres**: renombrar un proyecto
    /// no puede vaciarle el filtro sin avisar.
    var frentes: Set<String> = []
    /// Prioridades **ya invertidas** (1 = urgente … 4 = normal), que es como las
    /// lee el resto del sistema (`query_todoist` de `now-snapshot.py`).
    var prioridades: Set<Int> = []
    /// Etiquetas de Todoist (`labels`). Ya viajaban en el modelo y en el
    /// `.env`; no estaban aprovechadas por ningún filtro.
    var etiquetas: Set<String> = []
    /// Hasta dónde se mira. Las vencidas entran siempre.
    var horizonte: Horizonte = .todas

    /// EL HORIZONTE: hasta dónde miras, no qué grupo miras.
    enum Horizonte: String, Codable, CaseIterable {
        // ⚠️ MAÑANA existe como paso propio (25 ago). Daniel: *"hacen falta las
        // tareas de hoy y de mañana; el filtro ahora solo diferencia los
        // próximos siete días"*. Y tenía razón: de "hoy" a "7 días" hay un
        // salto de seis, y el día que de verdad se planea por la noche es el
        // siguiente. Sin este escalón, "¿qué tengo mañana?" obligaba a mirar
        // una semana entera.
        case hoy, manana, semana, mes, todas

        var rotulo: String {
            switch self {
            case .hoy: return "Hoy"
            case .manana: return "Mañana"
            case .semana: return "7 días"
            case .mes: return "Mes"
            case .todas: return "Todas"
            }
        }
        /// Cuántos días hacia delante. `nil` = sin límite.
        var dias: Int? {
            switch self {
            case .hoy: return 0
            case .manana: return 1
            case .semana: return 7
            case .mes: return 30
            case .todas: return nil
            }
        }
    }

    var estaVacio: Bool {
        frentes.isEmpty && prioridades.isEmpty && etiquetas.isEmpty && horizonte == .todas
    }

    /// Cuántos ejes están restringiendo. Sirve para el rótulo del botón.
    var ejesActivos: Int {
        (frentes.isEmpty ? 0 : 1) + (prioridades.isEmpty ? 0 : 1)
            + (etiquetas.isEmpty ? 0 : 1) + (horizonte == .todas ? 0 : 1)
    }

    /// ¿Pasa esta tarea? OR dentro de cada eje, AND entre los dos.
    ///
    /// `prioridad` llega YA invertida (1 = urgente). Se pide así, y no el valor
    /// crudo de la API (4 = urgente), para que las dos apps no puedan invertirla
    /// cada una a su manera: el filtro habla el idioma del sistema, no el de
    /// Todoist.
    func deja(frente: String?, prioridad: Int,
              etiquetas etqs: [String] = [], dia: String? = nil,
              hoy: String = FiltroTareas.hoyISO()) -> Bool {
        if !frentes.isEmpty {
            guard let f = frente, frentes.contains(f) else { return false }
        }
        if !prioridades.isEmpty {
            guard prioridades.contains(prioridad) else { return false }
        }
        if !etiquetas.isEmpty {
            guard etqs.contains(where: { etiquetas.contains($0) }) else { return false }
        }
        if let n = horizonte.dias {
            // ⚠️ LAS VENCIDAS ENTRAN SIEMPRE. Un horizonte que esconde lo que
            // ya se te pasó convierte una deuda en una sorpresa: justo lo
            // contrario de para qué existe mirar la lista.
            guard let d = dia else { return false }        // sin fecha = fuera del horizonte
            if d < hoy { return true }
            guard d <= FiltroTareas.masDias(hoy, n) else { return false }
        }
        return true
    }

    /// Comparaciones por CADENA ISO, igual que `query_todoist()` de
    /// `now-snapshot.py`: para días es barato y correcto, y es lo que ya usa
    /// el resto del sistema. Dos aritméticas de fecha distintas sobre la misma
    /// lista acabarían discrepando un día cualquiera a medianoche.
    static func hoyISO(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    static func masDias(_ iso: String, _ n: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso),
              let s = Calendar(identifier: .gregorian).date(byAdding: .day, value: n, to: d)
        else { return iso }
        return f.string(from: s)
    }

    // ── persistencia: un archivo, dos apps ──────────────────────────────────

    /// `~/.sfcal/filtro-tareas.json`. Mismo patrón que `habitos.json`: sfcal es
    /// la CABINA (lo escribe) y sfmap el ESPEJO (solo lo lee).
    static var ruta: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".sfcal/filtro-tareas.json")
    }

    static func cargar(_ url: URL = FiltroTareas.ruta) -> FiltroTareas {
        // ⚠️ Sin archivo = SIN filtro, no "filtro vacío que oculta todo". Es la
        // regla 2 otra vez, en la puerta del disco.
        guard let d = try? Data(contentsOf: url),
              let f = try? JSONDecoder().decode(FiltroTareas.self, from: d) else { return .init() }
        return f
    }

    /// Escritura ATÓMICA: sfmap puede estar leyendo justo ahora, y medio JSON
    /// se decodifica como "sin filtro" — o sea, la lista entera apareciendo y
    /// desapareciendo sola.
    func guardar(_ url: URL = FiltroTareas.ruta) {
        guard let d = try? JSONEncoder().encode(self) else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = url.appendingPathExtension("tmp")
        try? d.write(to: tmp)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try? FileManager.default.moveItem(at: tmp, to: url)
        }
    }
}

extension Notification.Name {
    /// "Reléete del disco". La manda ⌘R y la escuchan las vistas cuyo estado no
    /// vive en memoria: sin esto, recargar traía datos nuevos con el filtro
    /// viejo puesto.
    static let sfcalRecargar = Notification.Name("sfcal.recargar")
}

/// Los rótulos de prioridad, en un solo sitio para que las dos apps escriban lo
/// mismo. (Todoist las llama p1…p4 y el 1 es el urgente.)
enum PrioridadTarea {
    static let todas = [1, 2, 3, 4]
    static func rotulo(_ p: Int) -> String { "p\(p)" }
    /// De la prioridad CRUDA de la API (4 = urgente) a la del sistema (1 = urgente).
    static func delApi(_ crudo: Int) -> Int { 5 - crudo }
}
