// NUCLEO COMPARTIDO — los HÁBITOS como VOCABULARIO: las filas de la rejilla, el
// mapeo bloque→hábito, los pasos de un bloque. La PERSISTENCIA vive en
// `HabitStore.swift` y NO se comparte: sfmap solo lee el archivo, jamás escribe.
//
// ⚠️ ESTO ES UNA PLANTILLA. Las filas de hábitos y los pasos de abajo son DATOS
// TUYOS. Cámbialos por los tuyos; el mecanismo no se toca.

import Foundation

/// LOS HÁBITOS a través del tiempo: la hoja impresa, viva. Filas de hábito × los
/// días del mes, más el objetivo del día como una fila más.
///
/// POR QUÉ VIVE EN UN ARCHIVO Y NO EN UserDefaults: los checks se guardaban en
/// defaults y morían ahí — nadie fuera de la app podía leerlos, así que "marcar"
/// no alimentaba ningún sensor. Este archivo (`~/.sfcal/habitos.json`) lo escribe
/// la app Y lo puede leer cualquier otro proceso tuyo para cruzarlo con lo demás.
///
/// ⚠️ Un día SIN registro no es un día fallado: es un día NO MEDIDO. La rejilla
/// los pinta distinto (vacío vs ✗) porque confundirlos convierte una racha real
/// en una mentira, en las dos direcciones.
enum HabitEstado: String, Codable {
    case hecho, fallado
}

struct Habito: Identifiable, Hashable {
    let clave: String
    let nombre: String
    let detalle: String
    let estrella: Bool          // los no negociables
    var id: String { clave }
}

enum Habitos {
    /// De un BLOQUE de la rutina al hábito que representa. Es el puente que
    /// sincroniza las dos vistas: marcar un bloque en la pared llena su casilla
    /// en la rejilla, y al revés. Sin esto hay dos verdades del mismo día.
    /// Devuelve nil para bloques que no son hábito.
    ///
    /// ── TUYO: las palabras de la izquierda son las que aparecen en los títulos
    /// de TUS bloques; las claves de la derecha tienen que existir en `todos`.
    static func claveDeBloque(_ titulo: String) -> String? {
        let t = titulo.folding(options: [.diacriticInsensitive, .caseInsensitive],
                               locale: Locale(identifier: "es_MX")).lowercased()
        func tiene(_ ks: String...) -> Bool { ks.contains { t.contains($0) } }
        if tiene("despertar") { return "despertar" }
        if tiene("deep work", "bloque", "profundo", "enfoque") { return "profundo" }
        if tiene("nsdr", "siesta", "descanso") { return "descanso" }
        if tiene("gym", "entren", "pesas", "correr", "nata") { return "entrenar" }
        if tiene("cierre", "nocturna") { return "cierre" }
        return nil
    }

    // MARK: - Pasos de un bloque

    /// Un PASO dentro de un bloque de la rutina: la unidad que se palomea al
    /// desplegar el bloque. Solo cuando se completan todos se rellena el hábito.
    struct Paso: Identifiable, Hashable {
        let id: String          // namespaced: "despertar.agua"
        let hora: String
        let titulo: String
        let detalle: String
    }

    /// ── TUYO: los pasos de tu despertar. Tres o cuatro, no diez.
    static let pasosDespertar: [Paso] = [
        .init(id: "despertar.mover", hora: "6:00–6:10", titulo: "Mover el cuerpo",
              detalle: "Diez minutos, lo que sea. El objetivo es no volver a la cama."),
        .init(id: "despertar.agua", hora: "6:10–6:20", titulo: "Agua",
              detalle: "Antes que el café y antes que la pantalla."),
        .init(id: "despertar.luz", hora: "6:20–6:30", titulo: "Luz",
              detalle: "Salir o asomarse. Es lo que le pone hora al reloj interno."),
    ]

    /// ── TUYO: qué entrenas cada día de la semana.
    static func splitDelDia(_ dia: Date) -> String {
        switch DateKit.cal.component(.weekday, from: dia) {
        case 2, 5: return "Tren inferior"                // lun, jue
        case 3, 6: return "Espalda · bíceps"             // mar, vie
        case 4, 7: return "Pecho · hombro · tríceps"     // mié, sáb
        default: return "Cardio suave"                    // dom
        }
    }

    /// Los pasos del bloque de entrenar: lo del DÍA (por eso pide la fecha).
    static func pasosGym(_ dia: Date) -> [Paso] {
        [
            .init(id: "gym.fuerza", hora: "", titulo: splitDelDia(dia),
                  detalle: "El aparato que esté libre. Lo importante es aparecer."),
            .init(id: "gym.cierre", hora: "", titulo: "Cierre",
                  detalle: "Estirar y agua. Diez minutos."),
        ]
    }

    static let pasosNatacion: [Paso] = [
        .init(id: "gym.cardio", hora: "", titulo: "Cardio suave",
              detalle: "Zona 2: puedes hablar mientras lo haces."),
    ]

    /// De un BLOQUE de la rutina a sus pasos. Hermano de `claveDeBloque` (misma
    /// normalización, mismo riesgo: el mapeo es por TÍTULO). Pide la FECHA porque
    /// el entrenamiento cambia con el día. Un bloque sin detalle devuelve vacío.
    static func pasosDeBloque(_ titulo: String, dia: Date) -> [Paso] {
        let t = titulo.folding(options: [.diacriticInsensitive, .caseInsensitive],
                               locale: Locale(identifier: "es_MX")).lowercased()
        if t.contains("despertar") { return pasosDespertar }
        if t.contains("nata") || t.contains("cardio") { return pasosNatacion }
        if t.contains("gym") || t.contains("entren") || t.contains("pesas") { return pasosGym(dia) }
        return []
    }

    /// ── TUYO: las filas de la rejilla, en su orden. Los `estrella: true` son
    /// tus no negociables y van arriba con fondo propio. Cinco a ocho está bien;
    /// veinte no se sostiene.
    static let todos: [Habito] = [
        .init(clave: "despertar", nombre: "Despertar a la hora",
              detalle: "la misma todos los días", estrella: true),
        .init(clave: "profundo", nombre: "Bloque profundo",
              detalle: "una sola cosa, en el pico", estrella: true),
        .init(clave: "cierre", nombre: "Rutina de cierre",
              detalle: "sin pantallas", estrella: true),
        .init(clave: "entrenar", nombre: "Entrenar",
              detalle: "según el split", estrella: false),
        .init(clave: "descanso", nombre: "Descanso deliberado",
              detalle: "después de comer", estrella: false),
        .init(clave: "objetivo_dia", nombre: "Objetivo del día",
              detalle: "el que escribiste anoche", estrella: false),
    ]
}
