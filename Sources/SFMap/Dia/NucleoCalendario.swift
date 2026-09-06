// NUCLEO COMPARTIDO — este archivo lo compilan DOS apps.
//
// sfcal (que escribe el calendario) y sfmap (que solo lo MIRA, en el widget
// del centro de mando) enlazan este mismo archivo. No es una copia: es un
// enlace simbólico desde `sfmap/Sources/SFMap/Dia/`. Si se edita aquí, cambia
// en las dos — que es justo el punto: dos definiciones del mismo evento se
// separan en silencio y un día el panel dice una cosa y el calendario otra.
//
// ⚠️ Solo entra aquí lo PURO y Foundation-only. Nada de red, nada de disco,
// nada de SwiftUI: eso es de cada app, y sfmap además tiene prohibido escribir.

import Foundation

struct CalAccount: Codable, Identifiable, Hashable {
    let id: String        // "personal" | "empresa"
    let email: String
}

struct CalendarInfo: Codable, Identifiable, Hashable {
    let id: String        // google calendar id
    let accountId: String
    var summary: String
    var bgColorHex: String
    var fgColorHex: String
    var accessRole: String
    var isPrimary: Bool

    /// Los calendarios "Objetivo del dia/semana/mes" alimentan la banda de hitos,
    /// no la fila de all-day.
    var isObjetivo: Bool { summary.lowercased().hasPrefix("objetivo") }

    /// MES · SEMANA · DÍA. Vive aquí y no en el store porque el widget de sfmap
    /// necesita justo esta distinción para saber cuál es EL objetivo de hoy, y
    /// dos clasificaciones del mismo calendario acabarían señalando objetivos
    /// distintos en dos pantallas del mismo escritorio.
    var nivelObjetivo: String {
        let s = summary.lowercased()
        if s.contains("semana") { return "SEMANA" }
        if s.contains("mes") { return "MES" }
        return "DÍA"
    }
    var canWrite: Bool { accessRole == "owner" || accessRole == "writer" }
}

struct CalEvent: Codable, Identifiable, Hashable {
    var id: String
    var calendarId: String
    var accountId: String
    var summary: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var status: String
    var recurringEventId: String?
    var etag: String?
    var notes: String?
    var location: String?
    var updated: Date?
    var pending: Bool = false     // op optimista en vuelo

    var duration: TimeInterval { end.timeIntervalSince(start) }
}
