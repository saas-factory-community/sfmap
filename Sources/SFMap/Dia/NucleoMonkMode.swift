// NUCLEO COMPARTIDO — la PARED: un reto con fecha de inicio y de fin, tu rutina
// canónica, y `bloquesDeHoy`, que es la derivación que el widget NO puede
// re-escribir por su cuenta sin abrir la puerta a dos verdades del mismo día.
//
// ⚠️ ESTO ES UNA PLANTILLA. Todo lo que hay aquí abajo son DATOS TUYOS, no del
// programa: las fechas, los no-negociables y la rutina. Cámbialos por los tuyos
// y la pared se pinta sola. El mecanismo (el conteo día N/total, el calendario
// mandando sobre el protocolo, el protocolo prestando el detalle) NO se toca.
//
// La idea de fondo: la HORA la manda tu calendario real, porque es lo que tú
// firmaste hoy; la NOTA la pone tu doctrina. Un horario ideal fijo se ve
// genérico justo los días en que ya planeaste otra cosa.

import SwiftUI

enum MonkMode {
    // ── TUYO: el reto. Cambia estas tres líneas y todo lo demás se recalcula.
    static let dayOne = DateComponents(year: 2026, month: 1, day: 1)
    static let lastDay = DateComponents(year: 2026, month: 3, day: 31)
    static let totalDays = 90

    static var start: Date { DateKit.cal.date(from: dayOne) ?? Date() }
    static var end: Date { DateKit.cal.date(from: lastDay) ?? Date() }

    static func dayNumber(_ now: Date = Date()) -> Int {
        let d = (DateKit.cal.dateComponents([.day], from: DateKit.startOfDay(start),
                                            to: DateKit.startOfDay(now)).day ?? 0) + 1
        return min(max(d, 0), totalDays)
    }

    struct Fecha {
        let comps: DateComponents
        let titulo: String
        let detalle: String
    }

    /// ── TUYO: los hitos con fecha que quieres tener SIEMPRE a la vista.
    /// Déjalo vacío y la banda de hitos no se pinta. Ejemplo del formato:
    ///
    ///     .init(comps: .init(year: 2026, month: 3, day: 31), titulo: "31 MAR",
    ///           detalle: "Cierra el trimestre. El número que decide todo.")
    static let fechas: [Fecha] = []

    struct NoNegociable {
        let titulo: String
        let detalle: String
    }

    /// ── TUYO: las 2-4 cosas que no se negocian. Si son diez, no son
    /// no-negociables: son una lista de deseos.
    static let noNegociables: [NoNegociable] = [
        .init(titulo: "La hora de despertar",
              detalle: "La misma todos los días. Es la que ancla el resto."),
        .init(titulo: "El bloque de mayor fricción, en el pico del día",
              detalle: "Lo que más cuesta va primero, cuando todavía hay con qué."),
        .init(titulo: "La rutina de cierre",
              detalle: "Sin pantallas. Es lo que hace posible el despertar de mañana."),
    ]

    struct Bloque {
        let desde: Double   // minutos desde medianoche
        let hasta: Double
        let hora: String
        let titulo: String
        let nota: String
        let estrella: Bool
    }

    /// ── TUYO: la rutina canónica, según el día (entre semana vs fin de semana).
    /// Es el RESPALDO: solo se pinta cuando el calendario del día está vacío.
    /// `desde`/`hasta` van en minutos desde medianoche (5:30 = 330).
    static func rutina(for date: Date) -> [Bloque] {
        let weekday = DateKit.cal.component(.weekday, from: date)   // 1 = domingo
        let weekend = weekday == 1 || weekday == 7
        if !weekend {
            return [
                .init(desde: 360, hasta: 390, hora: "6:00", titulo: "Despertar",
                      nota: "La misma hora todos los días. Agua antes que pantalla.", estrella: true),
                .init(desde: 390, hasta: 720, hora: "6:30–12:00", titulo: "Bloque profundo",
                      nota: "Lo que más fricción da, en el pico del día. Una sola cosa.", estrella: true),
                .init(desde: 750, hasta: 840, hora: "12:30–14:00", titulo: "Entrenar",
                      nota: "Mover el cuerpo a media jornada rompe el bajón de la tarde.", estrella: false),
                .init(desde: 840, hasta: 870, hora: "14:00", titulo: "Comida",
                      nota: "Proteína primero. Los carbos aquí te tumban la tarde.", estrella: false),
                .init(desde: 900, hasta: 1020, hora: "15:00–17:00", titulo: "Ejecución",
                      nota: "Lo que ya está decidido: construir, editar, despachar.", estrella: false),
                .init(desde: 1050, hasta: 1200, hora: "17:30–20:00", titulo: "Trabajo ligero",
                      nota: "Responder, sueltas, lo que no exige el pico.", estrella: false),
                .init(desde: 1200, hasta: 1260, hora: "20:00–21:00", titulo: "Cierre",
                      nota: "Sin pantallas. Revisar el día por escrito.", estrella: true),
                .init(desde: 1320, hasta: 1380, hora: "22:00", titulo: "Cama",
                      nota: "Ocho horas. Cuarto fresco, oscuro, teléfono fuera.", estrella: false),
            ]
        }
        return [
            .init(desde: 360, hasta: 390, hora: "6:00", titulo: "Despertar",
                  nota: "El fin de semana no negocia la hora de despertar.", estrella: true),
            .init(desde: 390, hasta: 600, hora: "6:30–10:00", titulo: "Bloque profundo",
                  nota: "Versión corta de fin de semana.", estrella: true),
            .init(desde: 600, hasta: 720, hora: "10:00–12:00", titulo: "Entrenar",
                  nota: "Sesión larga, sin prisa.", estrella: false),
            .init(desde: 750, hasta: 780, hora: "12:30", titulo: "Comida",
                  nota: "Proteína primero.", estrella: false),
            .init(desde: 800, hasta: 1200, hora: "tarde", titulo: "Libre",
                  nota: "Gente, descanso, nada de pantalla obligatoria.", estrella: false),
            .init(desde: 1200, hasta: 1260, hora: "20:00–21:00", titulo: "Cierre",
                  nota: "Revisar la semana por escrito.", estrella: true),
            .init(desde: 1320, hasta: 1380, hora: "22:00", titulo: "Cama",
                  nota: "Ocho horas.", estrella: false),
        ]
    }

    // MARK: - La rutina VIVA: el calendario manda, el protocolo presta el detalle

    /// Un bloque de la pared. Viene del CALENDARIO REAL (lo que agendaste) o, si
    /// el día está vacío, del protocolo canónico de arriba.
    struct BloqueVivo: Identifiable {
        let id: String
        let desde: Double
        let hasta: Double
        let hora: String
        let titulo: String
        let nota: String
        let estrella: Bool
    }

    /// ── TUYO: el protocolo. Cada `if` empareja PALABRAS del título de tu evento
    /// con la nota que quieres ver al lado. Así el detalle no depende de que
    /// escribas la descripción completa en cada evento del calendario.
    /// Agrega, quita o cambia los casos: la comparación ignora tildes y mayúsculas.
    static func protocolo(para titulo: String) -> (nota: String, estrella: Bool) {
        let t = titulo.folding(options: [.diacriticInsensitive, .caseInsensitive],
                               locale: Locale(identifier: "es_MX")).lowercased()
        func tiene(_ ks: String...) -> Bool { ks.contains { t.contains($0) } }

        if tiene("despertar", "rutina de despertar") {
            return ("La misma hora todos los días. Agua antes que pantalla.", true)
        }
        if tiene("deep work", "bloque", "profundo", "enfoque") {
            return ("Una sola cosa, la de mayor fricción, en el pico del día.", true)
        }
        if tiene("gym", "entren", "pesas", "correr", "nata") {
            return ("Mover el cuerpo a media jornada rompe el bajón de la tarde.", false)
        }
        if tiene("nsdr", "siesta", "descanso") {
            return ("Después de comer, que es donde sirve.", false)
        }
        if tiene("comida", "comer", "desayuno", "cena") {
            return ("Proteína primero. La última comida, lejos de la cama.", false)
        }
        if tiene("construc", "ejecuc", "build") {
            return ("Lo que ya está decidido. Aquí no se decide, se despacha.", false)
        }
        if tiene("ligero", "light", "sueltas", "responder") {
            return ("Lo que no exige el pico. Sal un rato a la luz de la tarde.", false)
        }
        if tiene("cierre", "nocturna") {
            return ("Sin pantallas. Revisar el día por escrito antes de dormir.", true)
        }
        if tiene("cama", "dormir") {
            return ("Ocho horas. Cuarto fresco, oscuro, teléfono fuera.", false)
        }
        if tiene("planea", "planific", "review") {
            return ("Lo que no se planea se improvisa, y lo improvisado no compone.", false)
        }
        return ("", false)
    }

    /// La descripción de un evento puede traer marcadores de máquina (`[algo]`)
    /// que sirven al sistema y estorban en la pared. Se limpian al PINTAR, jamás
    /// en el calendario: el marcador tiene que seguir ahí para quien lo lee.
    static func limpiarNota(_ raw: String?) -> String {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return "" }
        s = s.replacingOccurrences(of: #"\s*\[[a-z0-9\-]+\]\s*$"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Los bloques de HOY. Prefiere SIEMPRE el calendario real; el protocolo
    /// canónico es el respaldo para un día sin nada agendado (jamás un hueco).
    static func bloquesDeHoy(eventos: [CalEvent], date: Date = Date()) -> [BloqueVivo] {
        let reales = eventos.filter { !$0.isAllDay && $0.status != "cancelled" }
        guard !reales.isEmpty else {
            return rutina(for: date).map {
                BloqueVivo(id: "canon·\($0.hora)·\($0.titulo)", desde: $0.desde, hasta: $0.hasta,
                           hora: $0.hora, titulo: $0.titulo, nota: $0.nota, estrella: $0.estrella)
            }
        }
        let inicioDia = DateKit.startOfDay(date)
        return reales.map { e in
            let desde = e.start < inicioDia ? 0 : DateKit.minutesIntoDay(e.start)
            // Un bloque que cruza medianoche daría 'hasta' MENOR que 'desde' y
            // nunca se marcaría como activo: se topa al final del día.
            let crudoHasta = DateKit.minutesIntoDay(e.end)
            let hasta = (e.end > DateKit.addDays(inicioDia, 1) || crudoHasta <= desde) ? 1440 : crudoHasta
            let prot = protocolo(para: e.summary)
            let notas = limpiarNota(e.notes)
            return BloqueVivo(
                id: e.id,
                desde: desde,
                hasta: hasta,
                hora: "\(DateKit.timeShort.string(from: e.start))–\(DateKit.timeShort.string(from: e.end))",
                titulo: e.summary,
                // Lo que escribiste en el evento gana sobre la doctrina.
                nota: notas.isEmpty ? prot.nota : notas,
                // Si el título YA trae la estrella (para marcar lo no negociable),
                // no se pone otra: "★ ⭐" es ruido.
                estrella: prot.estrella && !e.summary.contains("⭐"))
        }
        .sorted { $0.desde != $1.desde ? $0.desde < $1.desde : $0.titulo < $1.titulo }
    }
}
