// NUCLEO COMPARTIDO — lo compilan sfcal y sfmap (enlace simbólico).
//
// "LLÉVAME A ESA VISTA", no solo a la app. Daniel, 25 ago: *"asegúrate que
// cuando le dé doble clic a cierto widget me mande a la vista específica de ese
// widget, no solo la aplicación: si le doy doble clic a la vista de Monk Mode,
// que me mande para allá"*.

import Foundation

/// La vista que sfmap le pide a sfcal al abrirla.
///
/// ════════════════════════════════════════════════════════════════════════════
/// POR QUÉ UN ARCHIVO Y NO UN ESQUEMA `sfcal://`
/// ════════════════════════════════════════════════════════════════════════════
///
/// Un esquema de URL exige registrar el tipo en el `Info.plist` y que
/// LaunchServices lo tenga indexado — y estas apps se reinstalan varias veces al
/// día con firma ad-hoc, que es justo el escenario donde LaunchServices se
/// desincroniza en silencio (el mismo gotcha que ya costó los permisos de TCC).
/// Un archivo en `~/.sfcal/` no tiene registro que se pueda perder, funciona
/// igual con la app abierta o cerrada, y es el mismo patrón que ya usan el
/// filtro y los hábitos.
///
/// ⚠️ **La petición CADUCA.** Sin eso, sfcal saltaría a Monk Mode cada vez que
/// se abriera, para siempre, porque el archivo seguiría ahí. Se consume una vez
/// y se borra; y aunque no se borrase, una petición vieja se ignora.
struct PeticionVista: Codable {

    /// El `rawValue` de `CalViewMode` (monkMode · tasks · week · month…). Se
    /// guarda como texto y no como el enum para que sfmap —que no conoce las
    /// vistas de sfcal— pueda pedirlas sin importar nada de su UI.
    var vista: String
    var cuando: Date

    static var ruta: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".sfcal/vista-pedida.json")
    }

    /// Cuánto vale una petición. Diez segundos es de sobra para que la app
    /// arranque y muy poco para que una de ayer secuestre el arranque de hoy.
    static let vigencia: TimeInterval = 10

    /// Lo llama sfmap ANTES de abrir la app.
    static func pedir(_ vista: String, _ url: URL = PeticionVista.ruta) {
        let p = PeticionVista(vista: vista, cuando: Date())
        guard let d = try? JSONEncoder().encode(p) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? d.write(to: url)
    }

    /// Lo llama sfcal al arrancar y al volver al frente. Devuelve la vista si la
    /// petición es reciente, y **borra el archivo pase lo que pase**: una
    /// petición que sobrevive a su uso es una app que se va sola a otro sitio.
    static func consumir(_ url: URL = PeticionVista.ruta,
                         ahora: Date = Date()) -> String? {
        defer { try? FileManager.default.removeItem(at: url) }
        guard let d = try? Data(contentsOf: url),
              let p = try? JSONDecoder().decode(PeticionVista.self, from: d),
              ahora.timeIntervalSince(p.cuando) < vigencia,
              ahora.timeIntervalSince(p.cuando) > -vigencia   // relojes que se adelantan
        else { return nil }
        return p.vista
    }

    /// De un widget de sfmap a la vista de sfcal que le corresponde. Vive aquí
    /// —en el núcleo compartido— para que las dos apps estén de acuerdo sobre a
    /// dónde lleva cada cosa.
    static func vistaDeWidget(_ tipo: String) -> String? {
        switch tipo {
        case "calendario": return "week"       // la semana: lo que el widget enseña
        case "monk":       return "monkMode"
        case "tareas":     return "tasks"
        default:           return nil          // el trofeo no vive en sfcal
        }
    }
}
